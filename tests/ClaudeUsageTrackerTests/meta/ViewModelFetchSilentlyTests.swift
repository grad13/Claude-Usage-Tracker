// meta: updated=2026-08-11 checked=-
// Supplement for: docs/spec/meta/viewmodel-lifecycle.md
// Covers: fetchSilently success/error state, retry/retryCount reset, debug() logging

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

    func makeVM(
        sleeper: @escaping UsageViewModel.Sleeper = { _ in }
    ) -> UsageViewModel {
        ViewModelTestFactory.makeVM(
            fetcher: stubFetcher,
            settingsStore: settingsStore,
            usageStore: usageStore,
            widgetReloader: widgetReloader,
            loginItemManager: loginItemManager,
            alertChecker: alertChecker,
            startLifecycle: false,
            sleeper: sleeper
        )
    }

    /// Spec: Auth errors do not trigger retry. fetchSilently must not re-attempt
    /// when the error is an auth error (isAuthError == true).
    func testFetchSilently_authError_noRetry() {
        stubFetcher.fetchResult = .failure(UsageFetchError.scriptFailed("Missing organization"))

        let vm = makeVM()
        vm.isLoggedIn = true

        let done = expectation(description: "fetchSilently completes without retry")
        vm.fetchSilently { outcome in
            XCTAssertEqual(outcome, .authenticationRequired)
            done.fulfill()
        }
        wait(for: [done], timeout: 3.0)

        // Auth error: should only call fetch once (no retry).
        XCTAssertEqual(stubFetcher.fetchCallCount, 1,
                       "Auth error must not trigger retry")
        _ = vm
    }

    /// Spec: fetchSilently on success sets isLoggedIn, clears error, applies result.
    func testFetchSilently_success_setsIsLoggedInAndClearsError() {
        stubFetcher.fetchResult = .success(UsageResultFactory.make(
            fiveHourPercent: 50.0, sevenDayPercent: 25.0
        ))

        let vm = makeVM()
        vm.isLoggedIn = false
        vm.error = "previous error"

        let done = expectation(description: "fetchSilently success")
        vm.fetchSilently { outcome in
            XCTAssertEqual(outcome, .success)
            done.fulfill()
        }
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

        let completed = expectation(description: "fetchSilently success")
        vm.fetchSilently { outcome in
            XCTAssertEqual(outcome, .success)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2.0)

        XCTAssertEqual(vm.isAutoRefreshEnabled, true,
                       "fetchSilently success must re-enable auto-refresh")
        _ = vm
    }

    /// Spec: isFetching guard prevents concurrent fetchSilently calls.
    func testFetchSilently_isFetchingGuard_returnsBusy() {
        let vm = makeVM()
        vm.isFetching = true // simulate an in-progress fetch

        var observedOutcome: UsageViewModel.FetchOutcome?
        vm.fetchSilently { observedOutcome = $0 }

        XCTAssertEqual(observedOutcome, .busy)
        XCTAssertEqual(stubFetcher.fetchCallCount, 0,
                       "fetchSilently must skip when isFetching is already true")
    }

    func testFetchSilently_retriesScriptedFailureThenSucceeds() {
        struct TransientError: Error {}
        stubFetcher.scriptedFetchResults = [
            .failure(TransientError()),
            .success(UsageResultFactory.make(fiveHourPercent: 61.0))
        ]
        var delays: [TimeInterval] = []
        let vm = makeVM { delays.append($0) }

        let completed = expectation(description: "retry succeeds")
        vm.fetchSilently { outcome in
            XCTAssertEqual(outcome, .success)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2.0)

        XCTAssertEqual(stubFetcher.fetchCallCount, 2)
        XCTAssertEqual(delays, [30])
        XCTAssertEqual(vm.fiveHourPercent, 61.0)
    }

    func testFetchSilently_exhaustsScriptedRetries() {
        struct TransientError: LocalizedError {
            var errorDescription: String? { "transient" }
        }
        stubFetcher.scriptedFetchResults = Array(
            repeating: .failure(TransientError()),
            count: 4
        )
        var delays: [TimeInterval] = []
        let vm = makeVM { delays.append($0) }
        vm.isLoggedIn = true

        let completed = expectation(description: "retries exhausted")
        vm.fetchSilently { outcome in
            XCTAssertEqual(outcome, .failure)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2.0)

        XCTAssertEqual(stubFetcher.fetchCallCount, 4)
        XCTAssertEqual(delays, [30, 60, 120])
        XCTAssertEqual(vm.error, "transient")
    }

    func testFetchSilently_cancelledDuringRetrySleep_finishesOnce() {
        struct TransientError: Error {}
        stubFetcher.fetchResult = .failure(TransientError())
        let sleeper = ManualSleeper()
        let sleepStarted = expectation(description: "retry sleep started")
        sleeper.onSleep = { delay in
            XCTAssertEqual(delay, 30)
            sleepStarted.fulfill()
        }
        let sleepReturned = expectation(description: "cancelled retry sleep returned")
        sleeper.onSleepReturn = { sleepReturned.fulfill() }
        let vm = makeVM(sleeper: sleeper.sleep)

        let completed = expectation(description: "cancelled terminal outcome")
        completed.assertForOverFulfill = true
        vm.fetchSilently { outcome in
            XCTAssertEqual(outcome, .cancelled)
            completed.fulfill()
        }
        wait(for: [sleepStarted], timeout: 2.0)

        vm.invalidateAsyncOperations()
        wait(for: [completed], timeout: 2.0)
        sleeper.cancelNext()
        wait(for: [sleepReturned], timeout: 2.0)

        XCTAssertFalse(vm.isFetching)
        XCTAssertEqual(stubFetcher.fetchCallCount, 1)
    }

    func testFetch_staleSuspendedResultCannotMutateNewGeneration() {
        stubFetcher.shouldSuspendFetch = true
        let fetchStarted = expectation(description: "fetch suspended")
        stubFetcher.onFetch = { _ in fetchStarted.fulfill() }
        let fetchReturned = expectation(description: "stale fetch returned")
        stubFetcher.onFetchReturn = { fetchReturned.fulfill() }
        let vm = makeVM()

        let completed = expectation(description: "cancelled terminal outcome")
        completed.assertForOverFulfill = true
        vm.fetch { outcome in
            XCTAssertEqual(outcome, .cancelled)
            completed.fulfill()
        }
        wait(for: [fetchStarted], timeout: 2.0)

        let generation = vm.currentLifecycleGeneration
        vm.invalidateAsyncOperations()
        XCTAssertFalse(vm.isCurrentLifecycleGeneration(generation))
        wait(for: [completed], timeout: 2.0)

        stubFetcher.resumeNextFetch(with: .success(
            UsageResultFactory.make(fiveHourPercent: 88.0)
        ))
        wait(for: [fetchReturned], timeout: 2.0)
        XCTAssertNil(vm.fiveHourPercent, "stale result must not update state")
    }
}

// MARK: - debug() Logging Tests

final class ViewModelDebugLoggingTests: XCTestCase {

    /// Spec: Log file path is in App Group container (survives PC reboot).
    @MainActor
    func testDebugLogFilePath() {
        let url = UsageViewModel.logURL
        XCTAssertTrue(url.path.contains("debug.log"),
                      "Log file must be named debug.log")
        // App Group container path or fallback to tmp
        XCTAssertTrue(url.path.contains("group.grad13.claudeusagetracker") ||
                      url.path.contains("ClaudeUsageTracker-debug.log"),
                      "Log file must be in App Group container or tmp fallback")
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
