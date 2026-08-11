// meta: updated=2026-03-07 15:13 checked=-
import XCTest
import WebKit
import ClaudeUsageTrackerShared
@testable import ClaudeUsageTracker

// MARK: - ViewModelSessionSupplementTests
//
// Spec: docs/spec/meta/viewmodel-session.md
// Analysis: tests/.tests-from-spec/analysis/meta-viewmodel-session.md
//
// Supplement tests covering gaps identified in analysis:
//   1. handleSessionDetected: canRedirect cooldown, startAutoRefresh, loadUsagePage (lastRedirectAt)
//   2. Cookie restore: expired-skip logic, secure attribute (via HTTPCookie properties)
//   3. signOut: refreshTimer stop/nil-out
//   4. Login polling: 3-second interval verification
//
// Skipped (require WKHTTPCookieStore runtime):
//   - signOut 3-stage WebView cleanup (removeData/getAllCookies/delete)

@MainActor
final class ViewModelSessionSupplementTests: XCTestCase {

    let currentTime = Date(timeIntervalSince1970: 1_000)

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
            timerScheduler: timerScheduler,
            now: { self.currentTime }
        )
    }

    // MARK: - handleSessionDetected: startAutoRefresh

    /// Spec: handleSessionDetected() calls startAutoRefresh(), which sets refreshTimer.
    /// After handleSessionDetected(), refreshTimer should be non-nil (auto-refresh started).
    func testHandleSessionDetected_startsAutoRefresh() {
        let vm = makeVM()
        XCTAssertNil(vm.refreshTimer, "refreshTimer should be nil before login")

        vm.handleSessionDetected()

        XCTAssertNotNil(vm.refreshTimer,
            "handleSessionDetected should call startAutoRefresh(), setting refreshTimer")
    }

    /// Spec: The idempotency guard prevents duplicate startAutoRefresh() calls.
    /// Calling handleSessionDetected() twice should not replace the refreshTimer.
    func testHandleSessionDetected_idempotent_doesNotReplaceRefreshTimer() {
        let vm = makeVM()
        vm.handleSessionDetected()
        let firstTimer = vm.refreshTimer
        XCTAssertNotNil(firstTimer)

        // Second call should be guarded by isLoggedIn == true
        vm.handleSessionDetected()

        XCTAssertTrue(vm.refreshTimer === firstTimer,
            "Idempotency guard should prevent duplicate startAutoRefresh calls")
    }

    // MARK: - handleSessionDetected: canRedirect 5-second cooldown

    /// Spec: canRedirect() returns true when lastRedirectAt is nil.
    func testCanRedirect_returnsTrue_whenLastRedirectAtIsNil() {
        let vm = makeVM()
        XCTAssertNil(vm.lastRedirectAt)
        XCTAssertTrue(vm.canRedirect(),
            "canRedirect should return true when lastRedirectAt is nil")
    }

    /// Spec: canRedirect() returns false within 5 seconds of lastRedirectAt.
    func testCanRedirect_returnsFalse_withinCooldown() {
        let vm = makeVM()
        vm.lastRedirectAt = currentTime
        XCTAssertFalse(vm.canRedirect(),
            "canRedirect should return false within 5-second cooldown")
    }

    /// Spec: canRedirect() returns true after 5 seconds have elapsed.
    func testCanRedirect_returnsTrue_afterCooldownExpired() {
        let vm = makeVM()
        vm.lastRedirectAt = currentTime.addingTimeInterval(-6)
        XCTAssertTrue(vm.canRedirect(),
            "canRedirect should return true after 5-second cooldown has expired")
    }

    /// Spec: canRedirect() returns false at exactly 5 seconds (boundary: > 5, not >= 5).
    func testCanRedirect_returnsFalse_atExactly5Seconds() {
        let vm = makeVM()
        vm.lastRedirectAt = currentTime.addingTimeInterval(-5)
        XCTAssertFalse(vm.canRedirect(),
            "canRedirect should return false at exactly 5 seconds (strictly greater than 5)")
    }

    // MARK: - handleSessionDetected: lastRedirectAt set (loadUsagePage invocation proxy)

    /// Spec: handleSessionDetected() sets lastRedirectAt = Date() before calling loadUsagePage().
    /// When canRedirect() returns true, lastRedirectAt is updated, proving the redirect path executed.
    func testHandleSessionDetected_setsLastRedirectAt() {
        let vm = makeVM()
        XCTAssertNil(vm.lastRedirectAt)

        vm.handleSessionDetected()

        XCTAssertEqual(vm.lastRedirectAt, currentTime,
            "handleSessionDetected should use the injected clock when redirecting")
    }

    /// Spec: When canRedirect() returns false (within cooldown), lastRedirectAt is NOT updated.
    /// This verifies the canRedirect guard prevents loadUsagePage invocation.
    func testHandleSessionDetected_doesNotUpdateLastRedirectAt_whenCooldownActive() {
        let vm = makeVM()
        // Simulate a recent redirect
        let recentRedirect = currentTime.addingTimeInterval(-2)
        vm.lastRedirectAt = recentRedirect

        vm.handleSessionDetected()

        // lastRedirectAt should remain the old value (canRedirect returned false)
        XCTAssertEqual(vm.lastRedirectAt!.timeIntervalSince1970,
            recentRedirect.timeIntervalSince1970, accuracy: 0.001,
            "lastRedirectAt should not be updated when canRedirect returns false")
    }

    // MARK: - signOut: refreshTimer stop and nil-out

    /// Spec: signOut() stops and nils refreshTimer.
    func testSignOut_stopsAndNilsRefreshTimer() {
        let vm = makeVM()
        vm.handleSessionDetected()
        XCTAssertNotNil(vm.refreshTimer, "refreshTimer should be set after login")

        vm.signOut()

        XCTAssertNil(vm.refreshTimer,
            "signOut should invalidate and nil refreshTimer")
    }

    /// Spec: signOut() stops refreshTimer even when called without prior login.
    /// (Defensive: no crash when refreshTimer is already nil.)
    func testSignOut_doesNotCrash_whenRefreshTimerIsNil() {
        let vm = makeVM()
        XCTAssertNil(vm.refreshTimer)
        XCTAssertNoThrow(vm.signOut(),
            "signOut should not crash when refreshTimer is already nil")
    }

    /// Spec: After signOut(), refreshTimer is invalidated (isValid == false).
    /// Capture the timer before signOut to verify it was invalidated.
    func testSignOut_invalidatesRefreshTimer() {
        let vm = makeVM()
        vm.handleSessionDetected()
        let timer = vm.refreshTimer
        XCTAssertNotNil(timer)
        XCTAssertTrue(timer!.isValid, "Timer should be valid before signOut")

        vm.signOut()

        XCTAssertFalse(timer!.isValid,
            "signOut should invalidate the refreshTimer (isValid == false)")
    }

    // MARK: - Login Polling: 3-second interval

    /// Spec: Login polling uses a 3-second interval.
    func testLoginPolling_usesThreeSecondInterval() {
        let scheduler = ManualViewModelTimerScheduler()
        let vm = makeVM(timerScheduler: scheduler)
        vm.startLoginPolling()

        let timer = vm.loginPollTimer
        XCTAssertNotNil(timer)
        XCTAssertEqual(timer!.timeInterval, 3.0, accuracy: 0.001,
            "Login polling timer should fire at 3-second intervals")
        XCTAssertTrue(scheduler.validTimers.first?.repeats == true)
    }

    /// Spec: Login polling timer repeats.
    func testLoginPolling_timerRepeats() {
        let scheduler = ManualViewModelTimerScheduler()
        let vm = makeVM(timerScheduler: scheduler)
        vm.startLoginPolling()

        XCTAssertEqual(scheduler.validTimers.count, 1)
        XCTAssertTrue(scheduler.validTimers[0].repeats,
            "Login polling timer should repeat")
    }

    func testRefreshTimer_staleGenerationTickDoesNotFetch() {
        let scheduler = ManualViewModelTimerScheduler()
        let vm = makeVM(timerScheduler: scheduler)
        vm.isLoggedIn = true
        vm.isAutoRefreshEnabled = true
        vm.startAutoRefresh()
        let staleTimer = scheduler.validTimers[0]

        vm.invalidateAsyncOperations()
        staleTimer.fire()

        XCTAssertTrue(staleTimer.isValid, "generation guard must isolate the stale timer callback")
        XCTAssertEqual(stubFetcher.fetchCallCount, 0)
    }
}
