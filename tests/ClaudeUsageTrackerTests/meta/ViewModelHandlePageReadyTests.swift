// meta: updated=2026-08-11 checked=-
// Supplement for: docs/spec/meta/viewmodel-lifecycle.md
// Covers: handlePageReady decision table (PR-01~04), common side effects,
//         canRedirect cooldown, isOnUsagePage

import XCTest
import WebKit
import ClaudeUsageTrackerShared
@testable import ClaudeUsageTracker

private final class FinishedURLWebView: WKWebView {
    private let testURL: URL

    override var url: URL? { testURL }

    init(url: URL) {
        self.testURL = url
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        super.init(frame: .zero, configuration: configuration)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - handlePageReady Decision Table Tests

@MainActor
final class ViewModelHandlePageReadyTests: XCTestCase {

    var stubFetcher: StubUsageFetcher!
    var settingsStore: InMemorySettingsStore!
    var usageStore: InMemoryUsageStore!
    var widgetReloader: InMemoryWidgetReloader!
    var loginItemManager: InMemoryLoginItemManager!
    var alertChecker: MockAlertChecker!

    override func setUp() {
        super.setUp()
        stubFetcher = StubUsageFetcher()
        settingsStore = InMemorySettingsStore()
        usageStore = InMemoryUsageStore()
        widgetReloader = InMemoryWidgetReloader()
        loginItemManager = InMemoryLoginItemManager()
        alertChecker = MockAlertChecker()
    }

    func makeVM(
        timerScheduler: any ViewModelTimerScheduling = ManualViewModelTimerScheduler(),
        now: @escaping () -> Date = Date.init
    ) -> UsageViewModel {
        ViewModelTestFactory.makeVM(
            fetcher: stubFetcher,
            settingsStore: settingsStore,
            usageStore: usageStore,
            widgetReloader: widgetReloader,
            loginItemManager: loginItemManager,
            alertChecker: alertChecker,
            startLifecycle: false,
            sleeper: { _ in },
            timerScheduler: timerScheduler,
            now: now
        )
    }

    // MARK: - PR-01: hasValidSession=false -> no-op

    func testCoordinatorDidFinish_routesFinishedURLToHandler() {
        let vm = makeVM()
        let finishedURL = URL(string: "https://claude.ai/usage")!
        var routedURLs: [URL] = []
        let coordinator = WebViewCoordinator(viewModel: vm) { routedURLs.append($0) }

        coordinator.webView(FinishedURLWebView(url: finishedURL), didFinish: nil)

        XCTAssertEqual(routedURLs, [finishedURL])
    }

    /// Spec PR-01: When hasValidSession returns false, handlePageReady must
    /// skip all subsequent steps. isLoggedIn remains false, no fetch occurs.
    func testHandlePageReady_PR01_noSession_doesNothing() {
        stubFetcher.hasValidSessionResult = false

        let vm = makeVM()
        XCTAssertFalse(vm.isLoggedIn)

        let completed = expectation(description: "handlePageReady completes")
        vm.handlePageReady(finishedURL: URL(string: "https://claude.ai")!) { outcome in
            XCTAssertEqual(outcome, .noSession)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2.0)

        XCTAssertEqual(stubFetcher.hasValidSessionCallCount, 1,
                       "handlePageReady must call hasValidSession")
        XCTAssertFalse(vm.isLoggedIn,
                       "PR-01: isLoggedIn must remain false when no session")
        XCTAssertEqual(stubFetcher.fetchCallCount, 0,
                       "PR-01: fetchSilently must not be called when no session")
        _ = vm
    }

    // MARK: - PR-02: hasValidSession=true, isOnUsagePage=true -> fetchSilently

    /// Spec PR-02: When session is valid and WebView is on claude.ai,
    /// handlePageReady must call fetchSilently (which calls fetcher.fetch).
    func testHandlePageReady_PR02_onUsagePage_callsFetchSilently() {
        stubFetcher.hasValidSessionResult = true
        stubFetcher.shouldSuspendFetch = true
        let result = UsageResultFactory.make(
            fiveHourPercent: 40.0, sevenDayPercent: 20.0
        )

        let vm = makeVM()

        let fetchStarted = expectation(description: "page-ready silent fetch starts")
        stubFetcher.onFetch = { _ in fetchStarted.fulfill() }
        var didComplete = false
        let done = expectation(description: "handlePageReady completes")
        vm.handlePageReady(finishedURL: URL(string: "https://claude.ai/usage")!) { outcome in
            XCTAssertEqual(outcome, .fetch(.success))
            didComplete = true
            done.fulfill()
        }

        wait(for: [fetchStarted], timeout: 2.0)
        XCTAssertFalse(didComplete,
                       "page-ready completion must remain chained to the silent-fetch terminal outcome")
        XCTAssertEqual(stubFetcher.pendingFetchCount, 1)

        stubFetcher.resumeNextFetch(with: .success(result))
        wait(for: [done], timeout: 3.0)

        XCTAssertTrue(vm.isLoggedIn,
                      "PR-02: isLoggedIn must be set to true")
        XCTAssertEqual(stubFetcher.fetchCallCount, 1,
                       "PR-02: fetchSilently must call fetcher.fetch exactly once on success")
        XCTAssertEqual(vm.fiveHourPercent, 40)
        XCTAssertEqual(vm.sevenDayPercent, 20)
        _ = vm
    }

    // MARK: - PR-04: hasValidSession=true, isOnUsagePage=false, canRedirect=false -> no-op

    /// Spec PR-04: When session is valid, not on usage page, but redirect cooldown
    /// is active, handlePageReady must return without redirecting.
    func testHandlePageReady_PR04_cooldownActive_doesNotRedirect() {
        stubFetcher.hasValidSessionResult = true

        let currentTime = Date(timeIntervalSince1970: 1_000)
        let vm = makeVM(now: { currentTime })
        let cooldownTime = currentTime.addingTimeInterval(-2)
        vm.lastRedirectAt = cooldownTime

        let done = expectation(description: "handlePageReady completes")
        vm.handlePageReady(finishedURL: URL(string: "https://example.com")!) { outcome in
            XCTAssertEqual(outcome, .cooldownSuppressed)
            done.fulfill()
        }
        wait(for: [done], timeout: 2.0)

        XCTAssertTrue(vm.isLoggedIn,
                      "PR-04: common side effects must still execute (isLoggedIn = true)")
        XCTAssertEqual(vm.lastRedirectAt, cooldownTime,
                       "PR-04: lastRedirectAt must not be updated (no redirect occurred)")
        _ = vm
    }

    // MARK: - Common Side Effects (when hasValidSession=true)

    /// Spec: When hasValidSession returns true, the common side effects must
    /// execute: isLoggedIn=true, startAutoRefresh called.
    /// loginPollTimer must remain alive — it is stopped only by applyResult() so that
    /// post-cookie failures (page load / fetch) can still be retried by polling.
    func testHandlePageReady_commonSideEffects_keepsLoginPollTimerAlive() {
        stubFetcher.hasValidSessionResult = true

        var settings = AppSettings()
        settings.refreshIntervalMinutes = 5
        settingsStore.save(settings)

        let scheduler = ManualViewModelTimerScheduler()
        let vm = makeVM(timerScheduler: scheduler)
        vm.startLoginPolling()
        XCTAssertNotNil(vm.loginPollTimer, "Precondition: loginPollTimer is running")

        let completed = expectation(description: "handlePageReady completes")
        vm.handlePageReady(finishedURL: URL(string: "https://example.com")!) { outcome in
            XCTAssertEqual(outcome, .redirected)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2.0)

        XCTAssertTrue(vm.isLoggedIn,
                      "Common side effect 1: isLoggedIn must be true")
        XCTAssertNotNil(vm.loginPollTimer,
                        "Common side effect 2: loginPollTimer must remain alive — stopped only by applyResult()")
        XCTAssertNotNil(vm.refreshTimer,
                        "Common side effect 3: startAutoRefresh must create a refresh timer")
        _ = vm
    }
}

// MARK: - canRedirect Cooldown Tests

@MainActor
final class ViewModelCanRedirectTests: XCTestCase {

    let currentTime = Date(timeIntervalSince1970: 1_000)

    func makeVM() -> UsageViewModel {
        ViewModelTestFactory.makeVM(startLifecycle: false, now: { self.currentTime })
    }

    /// Spec: First call always returns true (lastRedirectAt is nil at launch).
    func testCanRedirect_nilLastRedirectAt_returnsTrue() {
        let vm = makeVM()
        XCTAssertNil(vm.lastRedirectAt)
        XCTAssertTrue(vm.canRedirect(),
                      "canRedirect must return true when lastRedirectAt is nil")
        _ = vm
    }

    /// Spec: Returns false when less than 5 seconds have elapsed since last redirect.
    func testCanRedirect_withinCooldown_returnsFalse() {
        let vm = makeVM()
        vm.lastRedirectAt = currentTime
        XCTAssertFalse(vm.canRedirect(),
                       "canRedirect must return false within 5-second cooldown")
        _ = vm
    }

    /// Spec: Returns true when more than 5 seconds have elapsed.
    func testCanRedirect_afterCooldown_returnsTrue() {
        let vm = makeVM()
        vm.lastRedirectAt = currentTime.addingTimeInterval(-6)
        XCTAssertTrue(vm.canRedirect(),
                      "canRedirect must return true after 5-second cooldown expires")
        _ = vm
    }

    /// Spec: Cooldown is exactly 5 seconds. At 5.0s boundary, should still be within cooldown.
    func testCanRedirect_atExactBoundary_returnsFalse() {
        let vm = makeVM()
        vm.lastRedirectAt = currentTime.addingTimeInterval(-5)
        XCTAssertFalse(vm.canRedirect(),
                       "canRedirect uses > 5, so exactly 5 seconds remains suppressed")
        _ = vm
    }
}

// MARK: - isOnUsagePage Tests

@MainActor
final class ViewModelIsOnUsagePageTests: XCTestCase {

    func makeVM() -> UsageViewModel {
        ViewModelTestFactory.makeVM(startLifecycle: false)
    }

    /// Spec: Returns false when webView.url is nil.
    /// Note: init() now calls loadUsagePage() which sets webView.url to claude.ai.
    /// We load about:blank to simulate a state where host != claude.ai.
    func testIsOnUsagePage_nonClaudeURL_returnsFalse() {
        let vm = makeVM()
        XCTAssertFalse(vm.isOnUsagePage(URL(string: "about:blank")!),
                       "isOnUsagePage must return false when webView.url is not claude.ai")
        _ = vm
    }
}
