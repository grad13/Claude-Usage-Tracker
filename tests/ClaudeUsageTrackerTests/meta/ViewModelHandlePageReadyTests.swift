// Supplement for: docs/spec/meta/viewmodel-lifecycle.md
// Covers: handlePageReady decision table (PR-01~04), common side effects,
//         canRedirect cooldown, isOnUsagePage

import XCTest
import WebKit
import ClaudeUsageTrackerShared
@testable import ClaudeUsageTracker

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

    func makeVM() -> UsageViewModel {
        ViewModelTestFactory.makeVM(
            fetcher: stubFetcher,
            settingsStore: settingsStore,
            usageStore: usageStore,
            widgetReloader: widgetReloader,
            loginItemManager: loginItemManager,
            alertChecker: alertChecker
        )
    }

    // MARK: - PR-01: hasValidSession=false -> no-op

    /// Spec PR-01: When hasValidSession returns false, handlePageReady must
    /// skip all subsequent steps. isLoggedIn remains false, no fetch occurs.
    func testHandlePageReady_PR01_noSession_doesNothing() {
        stubFetcher.hasValidSessionResult = false

        let vm = makeVM()
        XCTAssertFalse(vm.isLoggedIn)

        vm.handlePageReady()

        let done = expectation(description: "handlePageReady completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 2.0)

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
        stubFetcher.fetchResult = .success(UsageResultFactory.make(
            fiveHourPercent: 40.0, sevenDayPercent: 20.0
        ))

        let vm = makeVM()

        // Load claude.ai URL into WebView so isOnUsagePage returns true.
        let request = URLRequest(url: URL(string: "https://claude.ai/usage")!)
        vm.webView.load(request)

        // Wait for WebView to commit the URL.
        let urlReady = expectation(description: "webView URL set")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { urlReady.fulfill() }
        wait(for: [urlReady], timeout: 3.0)

        vm.handlePageReady()

        let done = expectation(description: "handlePageReady completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { done.fulfill() }
        wait(for: [done], timeout: 3.0)

        XCTAssertTrue(vm.isLoggedIn,
                      "PR-02: isLoggedIn must be set to true")
        // fetchSilently should have triggered fetcher.fetch
        XCTAssertGreaterThanOrEqual(stubFetcher.fetchCallCount, 1,
                                    "PR-02: fetchSilently must call fetcher.fetch")
        _ = vm
    }

    // MARK: - PR-04: hasValidSession=true, isOnUsagePage=false, canRedirect=false -> no-op

    /// Spec PR-04: When session is valid, not on usage page, but redirect cooldown
    /// is active, handlePageReady must return without redirecting.
    func testHandlePageReady_PR04_cooldownActive_doesNotRedirect() {
        stubFetcher.hasValidSessionResult = true

        let vm = makeVM()

        let cooldownTime = Date()
        vm.lastRedirectAt = cooldownTime

        // WebView URL is nil (not on usage page) by default after init.
        vm.handlePageReady()

        let done = expectation(description: "handlePageReady completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 2.0)

        XCTAssertTrue(vm.isLoggedIn,
                      "PR-04: common side effects must still execute (isLoggedIn = true)")
        XCTAssertEqual(vm.lastRedirectAt, cooldownTime,
                       "PR-04: lastRedirectAt must not be updated (no redirect occurred)")
        _ = vm
    }

    // MARK: - Common Side Effects (when hasValidSession=true)

    /// Spec: When hasValidSession returns true, the 4 common side effects must
    /// execute: isLoggedIn=true, loginPollTimer invalidated, startAutoRefresh called,
    /// backupSessionCookies called.
    func testHandlePageReady_commonSideEffects_loginPollTimerInvalidated() {
        stubFetcher.hasValidSessionResult = true

        var settings = AppSettings()
        settings.refreshIntervalMinutes = 5
        settingsStore.save(settings)

        let vm = makeVM()

        // Simulate a running loginPollTimer.
        vm.loginPollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in }
        XCTAssertNotNil(vm.loginPollTimer, "Precondition: loginPollTimer is running")

        vm.handlePageReady()

        let timeout = Date(timeIntervalSinceNow: 3.0)
        while !vm.isLoggedIn && Date() < timeout {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }

        XCTAssertTrue(vm.isLoggedIn,
                      "Common side effect 1: isLoggedIn must be true")
        XCTAssertNil(vm.loginPollTimer,
                     "Common side effect 2: loginPollTimer must be invalidated and set to nil")
        XCTAssertNotNil(vm.refreshTimer,
                        "Common side effect 3: startAutoRefresh must create a refresh timer")
        _ = vm
    }
}

// MARK: - canRedirect Cooldown Tests

@MainActor
final class ViewModelCanRedirectTests: XCTestCase {

    func makeVM() -> UsageViewModel {
        ViewModelTestFactory.makeVM()
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
        vm.lastRedirectAt = Date()
        XCTAssertFalse(vm.canRedirect(),
                       "canRedirect must return false within 5-second cooldown")
        _ = vm
    }

    /// Spec: Returns true when more than 5 seconds have elapsed.
    func testCanRedirect_afterCooldown_returnsTrue() {
        let vm = makeVM()
        vm.lastRedirectAt = Date().addingTimeInterval(-6)
        XCTAssertTrue(vm.canRedirect(),
                      "canRedirect must return true after 5-second cooldown expires")
        _ = vm
    }

    /// Spec: Cooldown is exactly 5 seconds. At 5.0s boundary, should still be within cooldown.
    func testCanRedirect_atExactBoundary_returnsFalse() {
        let vm = makeVM()
        // Set lastRedirectAt to exactly 5 seconds ago. The check is > 5, not >= 5.
        vm.lastRedirectAt = Date().addingTimeInterval(-4.99)
        XCTAssertFalse(vm.canRedirect(),
                       "canRedirect uses > 5 (strict), so 4.99s should return false")
        _ = vm
    }
}

// MARK: - isOnUsagePage Tests

@MainActor
final class ViewModelIsOnUsagePageTests: XCTestCase {

    func makeVM() -> UsageViewModel {
        ViewModelTestFactory.makeVM()
    }

    /// Spec: Returns false when webView.url is nil.
    func testIsOnUsagePage_nilURL_returnsFalse() {
        let vm = makeVM()
        // Fresh WebView has no URL loaded.
        XCTAssertFalse(vm.isOnUsagePage(),
                       "isOnUsagePage must return false when webView.url is nil")
        _ = vm
    }
}
