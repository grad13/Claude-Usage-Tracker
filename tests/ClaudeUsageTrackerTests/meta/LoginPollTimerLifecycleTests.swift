// meta: updated=2026-04-19 02:25 checked=-
// Spec: documents/spec/meta/viewmodel-session.md "Login Polling"
//
// Verifies that loginPollTimer survives intermediate steps
// (handleSessionDetected, handlePageReady) and is stopped only by applyResult().
// This is the core invariant that lets polling retry post-cookie failures
// (e.g., -1009 right after PC reboot).

import XCTest
import WebKit
import ClaudeUsageTrackerShared
@testable import ClaudeUsageTracker

@MainActor
final class LoginPollTimerLifecycleTests: XCTestCase {

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
        timerScheduler: any ViewModelTimerScheduling = ManualViewModelTimerScheduler()
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
            timerScheduler: timerScheduler
        )
    }

    // MARK: - Timer alive after intermediate steps

    /// Login polling is started explicitly so initialization-owned WebKit work is isolated.
    func testTimerAlive_afterExplicitStart() {
        let vm = makeVM()
        XCTAssertNil(vm.loginPollTimer)

        vm.startLoginPolling()

        XCTAssertNotNil(vm.loginPollTimer, "startLoginPolling() must create the timer")
    }

    /// handleSessionDetected() must NOT stop the timer (only applyResult does).
    func testTimerAlive_afterHandleSessionDetected() {
        let vm = makeVM()
        vm.startLoginPolling()
        XCTAssertNotNil(vm.loginPollTimer)

        vm.handleSessionDetected()

        XCTAssertNotNil(vm.loginPollTimer,
            "Cookie detection alone must not stop the timer — page load / fetch may still fail")
    }

    /// handlePageReady() must NOT stop the timer (only applyResult does).
    func testTimerAlive_afterHandlePageReady_validSession() {
        stubFetcher.hasValidSessionResult = true
        let vm = makeVM()
        vm.startLoginPolling()
        XCTAssertNotNil(vm.loginPollTimer)

        let completed = expectation(description: "page-ready redirect decision completes")
        vm.handlePageReady(finishedURL: URL(string: "https://example.com")!) { outcome in
            XCTAssertEqual(outcome, .redirected)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2.0)

        XCTAssertTrue(vm.isLoggedIn, "Precondition: handlePageReady must transition to logged-in")
        XCTAssertNotNil(vm.loginPollTimer,
            "handlePageReady must keep the timer alive — only applyResult stops it")
    }

    // MARK: - Timer stops only at applyResult

    /// applyResult() is the SOLE place the timer is invalidated.
    func testTimerStops_afterApplyResult() {
        let vm = makeVM()
        vm.startLoginPolling()
        XCTAssertNotNil(vm.loginPollTimer, "Precondition: timer is running")

        let result = UsageResultFactory.make(fiveHourPercent: 25.0, sevenDayPercent: 50.0)
        vm.applyResult(result)

        XCTAssertNil(vm.loginPollTimer,
            "applyResult must stop the timer (Phase 5)")
    }

    // MARK: - Tick logic 3-way branch

    /// When data already fetched, the tick should early-return (no hasValidSession call).
    /// We verify this by manually firing the injected timer.
    func testTick_dataAlreadyFetched_skipsSessionCheck() {
        let scheduler = ManualViewModelTimerScheduler()
        let vm = makeVM(timerScheduler: scheduler)
        vm.fiveHourPercent = 25.0
        vm.sevenDayPercent = 50.0
        vm.startLoginPolling()

        scheduler.validTimers[0].fire()

        XCTAssertEqual(stubFetcher.hasValidSessionCallCount, 0)
    }

    /// A timer retained across lifecycle invalidation must not start a stale poll check.
    func testTick_staleLifecycleGeneration_isIgnored() {
        let scheduler = ManualViewModelTimerScheduler()
        let vm = makeVM(timerScheduler: scheduler)
        vm.startLoginPolling()
        let staleTimer = scheduler.validTimers[0]

        vm.invalidateAsyncOperations()
        staleTimer.fire()

        XCTAssertTrue(staleTimer.isValid, "generation guard, not invalidation, must suppress this tick")
        XCTAssertEqual(stubFetcher.hasValidSessionCallCount, 0)
    }
}
