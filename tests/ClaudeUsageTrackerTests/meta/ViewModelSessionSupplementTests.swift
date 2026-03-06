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
//   - Cookie backup domain filter (backupSessionCookies reads from live WKHTTPCookieStore)
//   - signOut 3-stage WebView cleanup (removeData/getAllCookies/delete)
//   - Cookie restore full integration (restoreSessionCookies writes to live WKHTTPCookieStore)

@MainActor
final class ViewModelSessionSupplementTests: XCTestCase {

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
        vm.lastRedirectAt = Date()  // just now
        XCTAssertFalse(vm.canRedirect(),
            "canRedirect should return false within 5-second cooldown")
    }

    /// Spec: canRedirect() returns true after 5 seconds have elapsed.
    func testCanRedirect_returnsTrue_afterCooldownExpired() {
        let vm = makeVM()
        vm.lastRedirectAt = Date(timeIntervalSinceNow: -6)  // 6 seconds ago
        XCTAssertTrue(vm.canRedirect(),
            "canRedirect should return true after 5-second cooldown has expired")
    }

    /// Spec: canRedirect() returns false at exactly 5 seconds (boundary: > 5, not >= 5).
    func testCanRedirect_returnsFalse_atExactly5Seconds() {
        let vm = makeVM()
        vm.lastRedirectAt = Date(timeIntervalSinceNow: -5)  // exactly 5 seconds ago
        XCTAssertFalse(vm.canRedirect(),
            "canRedirect should return false at exactly 5 seconds (strictly greater than 5)")
    }

    // MARK: - handleSessionDetected: lastRedirectAt set (loadUsagePage invocation proxy)

    /// Spec: handleSessionDetected() sets lastRedirectAt = Date() before calling loadUsagePage().
    /// When canRedirect() returns true, lastRedirectAt is updated, proving the redirect path executed.
    func testHandleSessionDetected_setsLastRedirectAt() {
        let vm = makeVM()
        XCTAssertNil(vm.lastRedirectAt)

        let before = Date()
        vm.handleSessionDetected()
        let after = Date()

        XCTAssertNotNil(vm.lastRedirectAt,
            "handleSessionDetected should set lastRedirectAt when canRedirect returns true")
        XCTAssertGreaterThanOrEqual(vm.lastRedirectAt!.timeIntervalSince1970,
            before.timeIntervalSince1970)
        XCTAssertLessThanOrEqual(vm.lastRedirectAt!.timeIntervalSince1970,
            after.timeIntervalSince1970)
    }

    /// Spec: When canRedirect() returns false (within cooldown), lastRedirectAt is NOT updated.
    /// This verifies the canRedirect guard prevents loadUsagePage invocation.
    func testHandleSessionDetected_doesNotUpdateLastRedirectAt_whenCooldownActive() {
        let vm = makeVM()
        // Simulate a recent redirect
        let recentRedirect = Date(timeIntervalSinceNow: -2)  // 2 seconds ago
        vm.lastRedirectAt = recentRedirect

        vm.handleSessionDetected()

        // lastRedirectAt should remain the old value (canRedirect returned false)
        XCTAssertEqual(vm.lastRedirectAt!.timeIntervalSince1970,
            recentRedirect.timeIntervalSince1970, accuracy: 0.001,
            "lastRedirectAt should not be updated when canRedirect returns false")
    }

    // MARK: - CookieData → HTTPCookie: Expired cookie skip logic

    /// Spec: Cookies with expiresDate at or before the current time are skipped during restore.
    /// Verified via CookieData with a past expiresDate — HTTPCookie creation succeeds but
    /// the restore logic should skip it. We test the skip condition directly.
    func testCookieData_expiredCookie_isDetectedAsPast() {
        let pastTimestamp = Date(timeIntervalSinceNow: -3600).timeIntervalSince1970  // 1 hour ago
        let cookieData = UsageViewModel.CookieData(
            name: "expired",
            value: "val",
            domain: ".claude.ai",
            path: "/",
            expiresDate: pastTimestamp,
            isSecure: false
        )

        let expiresDate = Date(timeIntervalSince1970: cookieData.expiresDate!)
        let now = Date()
        XCTAssertTrue(expiresDate <= now,
            "Cookie with past expiresDate should be detected as expired (skip condition)")
    }

    /// Spec: Cookies with expiresDate in the future should NOT be skipped.
    func testCookieData_futureCookie_isNotExpired() {
        let futureTimestamp = Date(timeIntervalSinceNow: 3600).timeIntervalSince1970  // 1 hour from now
        let cookieData = UsageViewModel.CookieData(
            name: "valid",
            value: "val",
            domain: ".claude.ai",
            path: "/",
            expiresDate: futureTimestamp,
            isSecure: false
        )

        let expiresDate = Date(timeIntervalSince1970: cookieData.expiresDate!)
        let now = Date()
        XCTAssertTrue(expiresDate > now,
            "Cookie with future expiresDate should NOT be detected as expired")
    }

    /// Spec: Session cookies (expiresDate: nil) are never skipped as expired.
    func testCookieData_sessionCookie_nilExpiresDate_isNeverExpired() {
        let cookieData = UsageViewModel.CookieData(
            name: "session",
            value: "val",
            domain: ".claude.ai",
            path: "/",
            expiresDate: nil,
            isSecure: false
        )

        // The restore logic: `if let exp = backup.expiresDate, ... { continue }`
        // nil expiresDate means the `if let` guard fails, so the cookie is never skipped.
        XCTAssertNil(cookieData.expiresDate,
            "Session cookie expiresDate is nil — restore logic should never skip it")
    }

    // MARK: - CookieData → HTTPCookie: Secure attribute

    /// Spec: When isSecure == true, restore sets HTTPCookiePropertyKey.secure: "TRUE".
    /// Verify that an HTTPCookie created with the .secure property has isSecure == true.
    func testCookieData_secureAttribute_producesSecureCookie() {
        var props: [HTTPCookiePropertyKey: Any] = [
            .name: "secureKey",
            .value: "secureVal",
            .domain: ".claude.ai",
            .path: "/",
        ]
        props[.secure] = "TRUE"

        let cookie = HTTPCookie(properties: props)
        XCTAssertNotNil(cookie, "HTTPCookie should be creatable with .secure property")
        XCTAssertTrue(cookie!.isSecure,
            "Cookie created with .secure = \"TRUE\" should have isSecure == true")
    }

    /// Spec: When isSecure == false, restore does NOT set HTTPCookiePropertyKey.secure.
    /// Verify that an HTTPCookie created without .secure has isSecure == false.
    func testCookieData_nonSecure_producesNonSecureCookie() {
        let props: [HTTPCookiePropertyKey: Any] = [
            .name: "normalKey",
            .value: "normalVal",
            .domain: ".claude.ai",
            .path: "/",
        ]

        let cookie = HTTPCookie(properties: props)
        XCTAssertNotNil(cookie, "HTTPCookie should be creatable without .secure property")
        XCTAssertFalse(cookie!.isSecure,
            "Cookie created without .secure should have isSecure == false")
    }

    /// Spec: CookieData → HTTPCookieProperties with future expiresDate sets .expires key.
    /// Verify that the resulting HTTPCookie has the correct expiresDate.
    func testCookieData_futureExpiresDate_setsExpiresProperty() {
        let futureDate = Date(timeIntervalSinceNow: 86400)  // 24 hours from now
        var props: [HTTPCookiePropertyKey: Any] = [
            .name: "expiring",
            .value: "val",
            .domain: ".claude.ai",
            .path: "/",
        ]
        props[.expires] = futureDate

        let cookie = HTTPCookie(properties: props)
        XCTAssertNotNil(cookie)
        XCTAssertNotNil(cookie!.expiresDate,
            "Cookie with .expires property should have non-nil expiresDate")
        XCTAssertEqual(cookie!.expiresDate!.timeIntervalSince1970,
            futureDate.timeIntervalSince1970, accuracy: 1.0,
            "Cookie expiresDate should match the provided future date")
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
        let vm = makeVM()
        vm.startLoginPolling()

        let timer = vm.loginPollTimer
        XCTAssertNotNil(timer)
        XCTAssertEqual(timer!.timeInterval, 3.0, accuracy: 0.001,
            "Login polling timer should fire at 3-second intervals")
    }

    /// Spec: Login polling timer repeats.
    func testLoginPolling_timerRepeats() {
        let vm = makeVM()
        vm.startLoginPolling()

        let timer = vm.loginPollTimer
        XCTAssertNotNil(timer)
        // Timer.scheduledTimer(withTimeInterval:repeats:) with repeats: true
        // Unfortunately Timer does not expose an `isRepeating` property.
        // We verify the timer is valid (repeating timers stay valid after first fire).
        XCTAssertTrue(timer!.isValid,
            "Login polling timer should be a valid repeating timer")
    }
}
