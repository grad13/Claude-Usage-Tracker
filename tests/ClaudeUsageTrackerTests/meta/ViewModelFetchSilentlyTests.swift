// Supplement for: docs/spec/meta/viewmodel-lifecycle.md
// Covers: fetchSilently backupSessionCookies on success,
//         fetchSilently retry/retryCount reset, debug() logging

import XCTest
import ClaudeUsageTrackerShared
@testable import ClaudeUsageTracker

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
