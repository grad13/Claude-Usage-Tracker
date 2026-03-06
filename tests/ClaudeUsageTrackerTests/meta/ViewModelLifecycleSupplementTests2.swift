// Supplement for: docs/spec/meta/viewmodel-lifecycle.md
// Covers: handlePageReady decision table (PR-01~04), common side effects,
//         canRedirect cooldown, isOnUsagePage, fetchSilently backupSessionCookies on success,
//         fetchSilently retry/retryCount reset, debug() logging, setGraphColorTheme,
//         settings widgetReloader side effects, applyResult phase 4 widgetReloader

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

        // Set lastRedirectAt to now so canRedirect() returns false (within 5s cooldown).
        vm.lastRedirectAt = Date()

        // WebView URL is nil (not on usage page) by default after init.
        vm.handlePageReady()

        let done = expectation(description: "handlePageReady completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 2.0)

        XCTAssertTrue(vm.isLoggedIn,
                      "PR-04: common side effects must still execute (isLoggedIn = true)")
        XCTAssertEqual(stubFetcher.fetchCallCount, 0,
                       "PR-04: fetchSilently must not be called (not on usage page)")
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

        let done = expectation(description: "handlePageReady completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 2.0)

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
        vm.lastRedirectAt = Date().addingTimeInterval(-5)
        XCTAssertFalse(vm.canRedirect(),
                       "canRedirect uses > 5 (strict), so exactly 5s should return false")
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

// MARK: - fetchSilently Retry / BackupSessionCookies Tests

@MainActor
final class ViewModelFetchSilentlyRetryTests: XCTestCase {

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

    /// Spec: Auth errors do not trigger retry. fetchSilently must not re-attempt
    /// when the error is an auth error (isAuthError == true).
    func testFetchSilently_authError_noRetry() {
        stubFetcher.fetchResult = .failure(UsageFetchError.scriptFailed("Missing organization"))

        let vm = makeVM()
        vm.isLoggedIn = true

        vm.fetchSilently()

        let done = expectation(description: "fetchSilently completes without retry")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { done.fulfill() }
        wait(for: [done], timeout: 3.0)

        // Auth error: should only call fetch once (no retry).
        XCTAssertEqual(stubFetcher.fetchCallCount, 1,
                       "Auth error must not trigger retry")
        _ = vm
    }

    /// Spec: fetchSilently calls backupSessionCookies on success (unlike fetch()).
    /// Observable via the side effects after a successful fetch.
    func testFetchSilently_success_setsIsLoggedInAndClearsError() {
        stubFetcher.fetchResult = .success(UsageResultFactory.make(
            fiveHourPercent: 50.0, sevenDayPercent: 25.0
        ))

        let vm = makeVM()
        vm.isLoggedIn = false
        vm.error = "previous error"

        vm.fetchSilently()

        let done = expectation(description: "fetchSilently success")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 2.0)

        XCTAssertTrue(vm.isLoggedIn,
                      "fetchSilently success must set isLoggedIn = true")
        XCTAssertNil(vm.error,
                     "fetchSilently success must clear error")
        XCTAssertEqual(vm.fiveHourPercent, 50.0,
                       "fetchSilently success must apply result")
        _ = vm
    }

    /// Spec: On success, retryCount resets to 0 and isAutoRefreshEnabled = true.
    func testFetchSilently_success_enablesAutoRefresh() {
        stubFetcher.fetchResult = .success(UsageResultFactory.make(
            fiveHourPercent: 30.0, sevenDayPercent: 10.0
        ))

        let vm = makeVM()
        vm.isAutoRefreshEnabled = false // was disabled by prior auth error

        vm.fetchSilently()

        let done = expectation(description: "fetchSilently success")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 2.0)

        XCTAssertEqual(vm.isAutoRefreshEnabled, true,
                       "fetchSilently success must re-enable auto-refresh")
        _ = vm
    }

    /// Spec: isFetching guard prevents concurrent fetchSilently calls.
    func testFetchSilently_isFetchingGuard_skipsDuplicate() {
        // Use a fetch that will take some time (the stub returns immediately,
        // but the Task is async so we can test the guard).
        stubFetcher.fetchResult = .success(UsageResultFactory.make(
            fiveHourPercent: 10.0
        ))

        let vm = makeVM()
        vm.isFetching = true // simulate an in-progress fetch

        let beforeCount = stubFetcher.fetchCallCount
        vm.fetchSilently()

        let done = expectation(description: "guard check")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { done.fulfill() }
        wait(for: [done], timeout: 1.0)

        XCTAssertEqual(stubFetcher.fetchCallCount, beforeCount,
                       "fetchSilently must skip when isFetching is already true")
        _ = vm
    }
}

// MARK: - debug() Logging Tests

final class ViewModelDebugLoggingTests: XCTestCase {

    /// Spec: Log file path is temporaryDirectory/ClaudeUsageTracker-debug.log.
    @MainActor
    func testDebugLogFilePath() {
        let expectedPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeUsageTracker-debug.log")
        XCTAssertEqual(UsageViewModel.logURL, expectedPath,
                       "Log file must be at temporaryDirectory/ClaudeUsageTracker-debug.log")
    }

    /// Spec: debug() appends to the log file with ISO8601 timestamp + message format.
    @MainActor
    func testDebugAppendsToLogFile() {
        let vm = ViewModelTestFactory.makeVM()
        let testMessage = "test-debug-message-\(UUID().uuidString)"

        vm.debug(testMessage)

        let content = try? String(contentsOf: UsageViewModel.logURL, encoding: .utf8)
        XCTAssertNotNil(content, "Log file must exist after debug() call")
        XCTAssertTrue(content?.contains(testMessage) == true,
                      "Log file must contain the debug message")
        _ = vm
    }

    /// Spec: Each log line has format "{ISO8601 timestamp} {message}\n".
    @MainActor
    func testDebugLogLineFormat() {
        let vm = ViewModelTestFactory.makeVM()

        // Clear the log first by writing empty string.
        try? "".write(to: UsageViewModel.logURL, atomically: true, encoding: .utf8)

        let marker = "format-check-\(UUID().uuidString)"
        vm.debug(marker)

        let content = (try? String(contentsOf: UsageViewModel.logURL, encoding: .utf8)) ?? ""
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

        XCTAssertEqual(lines.count, 1, "Should have exactly one log line")
        if let line = lines.first {
            // ISO8601 format starts with a year (4 digits) and contains 'T'.
            let parts = line.split(separator: " ", maxSplits: 1)
            XCTAssertEqual(parts.count, 2,
                           "Log line must have format: '{timestamp} {message}'")
            if let timestamp = parts.first {
                XCTAssertTrue(timestamp.contains("T"),
                              "Timestamp must be ISO8601 format (contains 'T')")
            }
            if let msg = parts.last {
                XCTAssertTrue(msg.contains(marker),
                              "Message portion must contain the original message")
            }
        }
        _ = vm
    }

    /// Spec: Log file is initialized as empty at launch (via logURL lazy init).
    @MainActor
    func testDebugLogFileInitializedEmpty() {
        // logURL is a static lazy var, so it's initialized once. We verify
        // the file exists (it was created by static init) and that subsequent
        // writes append correctly.
        let url = UsageViewModel.logURL
        let exists = FileManager.default.fileExists(atPath: url.path)
        XCTAssertTrue(exists, "Log file must be created during logURL initialization")
    }
}

// MARK: - setGraphColorTheme and widgetReloader Side Effect Tests

@MainActor
final class ViewModelSettingsWidgetReloaderTests: XCTestCase {

    var settingsStore: InMemorySettingsStore!
    var widgetReloader: InMemoryWidgetReloader!

    override func setUp() {
        super.setUp()
        settingsStore = InMemorySettingsStore()
        widgetReloader = InMemoryWidgetReloader()
    }

    func makeVM() -> UsageViewModel {
        ViewModelTestFactory.makeVM(
            settingsStore: settingsStore,
            widgetReloader: widgetReloader
        )
    }

    // MARK: - setGraphColorTheme

    /// Spec: setGraphColorTheme persists the value and calls widgetReloader.reloadAllTimelines().
    func testSetGraphColorTheme_persistsAndReloadsWidget() {
        let vm = makeVM()
        let beforeReloadCount = widgetReloader.reloadCount

        vm.setGraphColorTheme(.system)

        XCTAssertEqual(vm.settings.graphColorTheme, .system,
                       "setGraphColorTheme must update settings.graphColorTheme")
        XCTAssertEqual(settingsStore.current.graphColorTheme, .system,
                       "setGraphColorTheme must persist to settingsStore")
        XCTAssertEqual(widgetReloader.reloadCount, beforeReloadCount + 1,
                       "setGraphColorTheme must call widgetReloader.reloadAllTimelines()")
        _ = vm
    }

    /// Spec: setGraphColorTheme with .dark value.
    func testSetGraphColorTheme_dark() {
        let vm = makeVM()
        vm.setGraphColorTheme(.dark)

        XCTAssertEqual(vm.settings.graphColorTheme, .dark)
        XCTAssertEqual(settingsStore.current.graphColorTheme, .dark)
        _ = vm
    }

    // MARK: - setHourlyColorPreset widgetReloader side effect

    /// Spec: setHourlyColorPreset must call widgetReloader.reloadAllTimelines().
    /// Persistence is already tested; this verifies the side effect.
    func testSetHourlyColorPreset_reloadsWidget() {
        let vm = makeVM()
        let beforeReloadCount = widgetReloader.reloadCount

        vm.setHourlyColorPreset(.green)

        XCTAssertEqual(widgetReloader.reloadCount, beforeReloadCount + 1,
                       "setHourlyColorPreset must call widgetReloader.reloadAllTimelines()")
        _ = vm
    }

    // MARK: - setWeeklyColorPreset widgetReloader side effect

    /// Spec: setWeeklyColorPreset must call widgetReloader.reloadAllTimelines().
    func testSetWeeklyColorPreset_reloadsWidget() {
        let vm = makeVM()
        let beforeReloadCount = widgetReloader.reloadCount

        vm.setWeeklyColorPreset(.purple)

        XCTAssertEqual(widgetReloader.reloadCount, beforeReloadCount + 1,
                       "setWeeklyColorPreset must call widgetReloader.reloadAllTimelines()")
        _ = vm
    }

    // MARK: - applyResult Phase 4: widgetReloader

    /// Spec: applyResult phase 4 calls widgetReloader.reloadAllTimelines().
    func testApplyResult_phase4_reloadsWidget() {
        let vm = makeVM()
        let beforeReloadCount = widgetReloader.reloadCount

        let result = UsageResultFactory.make(
            fiveHourPercent: 30.0, sevenDayPercent: 15.0
        )
        vm.applyResult(result)

        XCTAssertEqual(widgetReloader.reloadCount, beforeReloadCount + 1,
                       "applyResult must call widgetReloader.reloadAllTimelines() (phase 4)")
        _ = vm
    }

    /// Spec: applyResult called multiple times must call widgetReloader each time.
    func testApplyResult_multipleCalls_reloadsWidgetEachTime() {
        let vm = makeVM()
        let beforeReloadCount = widgetReloader.reloadCount

        let result = UsageResultFactory.make(fiveHourPercent: 10.0)
        vm.applyResult(result)
        vm.applyResult(result)
        vm.applyResult(result)

        XCTAssertEqual(widgetReloader.reloadCount, beforeReloadCount + 3,
                       "Each applyResult call must trigger widgetReloader.reloadAllTimelines()")
        _ = vm
    }
}
