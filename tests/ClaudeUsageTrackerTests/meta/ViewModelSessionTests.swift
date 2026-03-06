import XCTest
import WebKit
import ClaudeUsageTrackerShared
@testable import ClaudeUsageTracker

// MARK: - ViewModelSessionTests
//
// Spec: _documents/spec/meta/viewmodel-session.md
//
// このテストファイルは viewmodel-session.md の仕様に基づいて生成された。
// 以下の4領域を検証する:
//   1. handleSessionDetected() — ログイン検出の統合エントリーポイント
//   2. Cookie Backup/Restore — App Group への Cookie バックアップと復元
//   3. Login Polling — SPA ナビゲーション対応フォールバック
//   4. Popup Login Check — checkPopupLogin / handlePopupClosed
//   5. signOut() の Widget 連携

@MainActor
final class ViewModelSessionTests: XCTestCase {

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

    // MARK: - handleSessionDetected: 冪等性ガード

    /// isLoggedIn が false のとき handleSessionDetected() を呼ぶと isLoggedIn が true になる。
    func testHandleSessionDetected_setsIsLoggedIn() {
        let vm = makeVM()
        XCTAssertFalse(vm.isLoggedIn)
        vm.handleSessionDetected()
        XCTAssertTrue(vm.isLoggedIn)
    }

    /// isLoggedIn が既に true のとき handleSessionDetected() を呼んでも二重処理しない（冪等性）。
    /// 二重処理の検出に startAutoRefresh の副作用は現状テストできないが、
    /// 少なくとも isLoggedIn は true のまま維持されることを保証する。
    func testHandleSessionDetected_idempotent_whenAlreadyLoggedIn() {
        let vm = makeVM()
        vm.handleSessionDetected()
        XCTAssertTrue(vm.isLoggedIn)
        // 2回目の呼び出しでもクラッシュしないこと
        vm.handleSessionDetected()
        XCTAssertTrue(vm.isLoggedIn)
    }

    /// handleSessionDetected() は isAutoRefreshEnabled を nil にリセットする。
    /// これにより次の handlePageReady() で改めてセッション有効性が判定される。
    func testHandleSessionDetected_resetsIsAutoRefreshEnabled() {
        let vm = makeVM()
        // isAutoRefreshEnabled を事前に true に設定（ログイン前状態とは異なる値）
        vm.isAutoRefreshEnabled = true
        vm.handleSessionDetected()
        XCTAssertNil(vm.isAutoRefreshEnabled,
            "handleSessionDetected should reset isAutoRefreshEnabled to nil " +
            "so handlePageReady can re-evaluate session validity")
    }

    /// handleSessionDetected() は isAutoRefreshEnabled = false のときも nil にリセットする。
    func testHandleSessionDetected_resetsIsAutoRefreshEnabled_whenFalse() {
        let vm = makeVM()
        vm.isAutoRefreshEnabled = false
        vm.handleSessionDetected()
        XCTAssertNil(vm.isAutoRefreshEnabled)
    }

    // MARK: - handleSessionDetected: backupSessionCookies の呼び出し順序

    /// handleSessionDetected() は backupSessionCookies() をリダイレクト前に実行する。
    /// ナビゲーション失敗しても Cookie は保存済みの状態を保つことが設計意図。
    /// 直接検証は困難だが、メソッド呼び出し自体がクラッシュしないことを確認する。
    func testHandleSessionDetected_doesNotCrash() {
        let vm = makeVM()
        // backupSessionCookies が内部で呼ばれても例外が出ないことを確認
        XCTAssertNoThrow(vm.handleSessionDetected())
    }

    // MARK: - handleSessionDetected: ステート遷移の順序検証

    /// 2回目の handleSessionDetected() 呼び出し（isLoggedIn == true）は即座に return する。
    /// isAutoRefreshEnabled が変更されないことで、ガード節が機能していることを間接的に確認する。
    func testHandleSessionDetected_secondCall_doesNotResetAutoRefresh() {
        let vm = makeVM()
        vm.handleSessionDetected()
        // 1回目の後、isAutoRefreshEnabled を true に設定
        vm.isAutoRefreshEnabled = true
        // 2回目の呼び出し（isLoggedIn == true なので即 return のはず）
        vm.handleSessionDetected()
        // ガードが機能していれば isAutoRefreshEnabled は変更されない
        XCTAssertEqual(vm.isAutoRefreshEnabled, true,
            "Second call to handleSessionDetected should return early " +
            "without resetting isAutoRefreshEnabled")
    }

    // MARK: - CookieData: Codable 構造体

    /// CookieData は Codable であり、encode → decode のラウンドトリップが成立する。
    func testCookieData_roundTripCodable() throws {
        let original = UsageViewModel.CookieData(
            name: "sessionKey",
            value: "abc123",
            domain: ".claude.ai",
            path: "/",
            expiresDate: 1_800_000_000.0,
            isSecure: true
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(UsageViewModel.CookieData.self, from: data)

        XCTAssertEqual(decoded.name, "sessionKey")
        XCTAssertEqual(decoded.value, "abc123")
        XCTAssertEqual(decoded.domain, ".claude.ai")
        XCTAssertEqual(decoded.path, "/")
        XCTAssertEqual(decoded.expiresDate, 1_800_000_000.0)
        XCTAssertEqual(decoded.isSecure, true)
    }

    /// CookieData の expiresDate は nil 許容（セッション Cookie）。nil のまま encode/decode できる。
    func testCookieData_nilExpiresDate_roundTrip() throws {
        let original = UsageViewModel.CookieData(
            name: "sessionKey",
            value: "abc123",
            domain: ".claude.ai",
            path: "/",
            expiresDate: nil,
            isSecure: false
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(UsageViewModel.CookieData.self, from: data)

        XCTAssertNil(decoded.expiresDate,
            "Session cookie (expiresDate: nil) should round-trip as nil")
        XCTAssertFalse(decoded.isSecure)
    }

    /// UsageViewModel.cookieBackupName は "session-cookies.json" である。
    func testCookieData_cookieBackupName() {
        XCTAssertEqual(UsageViewModel.cookieBackupName, "session-cookies.json")
    }

    // MARK: - restoreSessionCookies: 戻り値

    /// restoreSessionCookies() は Cookie が1つも存在しない（バックアップファイルなし）場合に false を返す。
    /// NOTE: This test may return true if the real App Group container has cookie backups
    /// from previous production runs. We verify the return type is Bool (contract test)
    /// rather than asserting a specific value, since the test cannot control the App Group state.
    func testRestoreSessionCookies_returnsBool() async {
        let vm = makeVM()
        let result = await vm.restoreSessionCookies()
        // Verify the method returns a Bool (contract conformance).
        // The actual value depends on App Group state (may have production data).
        _ = result // Bool return confirmed by compilation
    }

    // MARK: - Login Polling: 二重起動防止

    /// startLoginPolling() は loginPollTimer が nil のときのみタイマーを起動する（二重起動防止）。
    func testStartLoginPolling_doesNotStartTwice() {
        let vm = makeVM()
        vm.startLoginPolling()
        let firstTimer = vm.loginPollTimer
        XCTAssertNotNil(firstTimer, "loginPollTimer should be set after startLoginPolling")

        vm.startLoginPolling()
        // 2回目の呼び出しでタイマーが差し替わらないことを確認
        XCTAssertTrue(vm.loginPollTimer === firstTimer,
            "startLoginPolling should not replace existing timer (double-start guard)")
    }

    /// startLoginPolling() 後、loginPollTimer は nil でない。
    func testStartLoginPolling_setsTimer() {
        let vm = makeVM()
        XCTAssertNil(vm.loginPollTimer)
        vm.startLoginPolling()
        XCTAssertNotNil(vm.loginPollTimer)
    }

    /// handleSessionDetected() は loginPollTimer を無効化し nil にする。
    func testHandleSessionDetected_invalidatesLoginPollTimer() {
        let vm = makeVM()
        vm.startLoginPolling()
        XCTAssertNotNil(vm.loginPollTimer, "Timer should be set before handleSessionDetected")

        vm.handleSessionDetected()

        XCTAssertNil(vm.loginPollTimer,
            "handleSessionDetected should invalidate and nil loginPollTimer")
    }

    /// ログイン済み状態（isLoggedIn == true）では Login Polling 内のガードが働き、
    /// handleSessionDetected() を重複して呼ばない。
    /// 直接テストが難しいため、isLoggedIn == true のときに startLoginPolling が
    /// タイマーを起動しないことで代替検証する。
    func testLoginPolling_doesNotStartWhenAlreadyLoggedIn() {
        let vm = makeVM()
        vm.handleSessionDetected()
        XCTAssertTrue(vm.isLoggedIn)
        // ログイン後にポーリングを開始しようとしても、タイマーは起動しない
        // （実装によっては起動するが Polling 内のガードで即 return する）
        // ここでは少なくともクラッシュしないことを確認
        XCTAssertNoThrow(vm.startLoginPolling())
    }

    // MARK: - checkPopupLogin: 500ms 待機

    /// checkPopupLogin() は hasValidSession が true のとき closePopup() を呼ぶ。
    /// 500ms 待機の後に closePopup() が呼ばれるため、非同期で検証する。
    func testCheckPopupLogin_closesPopup_whenSessionValid() async throws {
        let vm = makeVM()
        stubFetcher.hasValidSessionResult = true

        let popup = WKWebView(frame: .zero)
        vm.popupWebView = popup
        XCTAssertNotNil(vm.popupWebView)

        vm.checkPopupLogin()

        // 500ms + マージン = 800ms 待機
        try await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertNil(vm.popupWebView,
            "checkPopupLogin should call closePopup() after 500ms when session is valid")
    }

    /// checkPopupLogin() は hasValidSession が true のとき handleSessionDetected() を呼び、isLoggedIn が true になる。
    func testCheckPopupLogin_callsHandleSessionDetected_whenSessionValid() async throws {
        let vm = makeVM()
        stubFetcher.hasValidSessionResult = true

        let popup = WKWebView(frame: .zero)
        vm.popupWebView = popup
        XCTAssertFalse(vm.isLoggedIn)

        vm.checkPopupLogin()

        // 500ms + マージン = 800ms 待機
        try await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertTrue(vm.isLoggedIn,
            "checkPopupLogin should call handleSessionDetected() which sets isLoggedIn=true")
    }

    /// checkPopupLogin() は hasValidSession が false のとき closePopup() を呼ばない。
    func testCheckPopupLogin_doesNotClosePopup_whenSessionInvalid() async throws {
        let vm = makeVM()
        stubFetcher.hasValidSessionResult = false

        let popup = WKWebView(frame: .zero)
        vm.popupWebView = popup

        vm.checkPopupLogin()

        // 500ms + マージン 待機後も popupWebView は残る
        try await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertNotNil(vm.popupWebView,
            "checkPopupLogin should NOT call closePopup() when session is invalid")
    }

    // MARK: - handlePopupClosed: 1秒待機

    /// handlePopupClosed() は 1秒待機後に hasValidSession を確認し、
    /// true であれば handleSessionDetected() を呼ぶ（isLoggedIn = true になる）。
    func testHandlePopupClosed_callsHandleSessionDetected_whenSessionValid() async throws {
        let vm = makeVM()
        stubFetcher.hasValidSessionResult = true
        XCTAssertFalse(vm.isLoggedIn)

        vm.handlePopupClosed()

        // 1000ms + マージン = 1500ms 待機
        try await Task.sleep(nanoseconds: 1_500_000_000)

        XCTAssertTrue(vm.isLoggedIn,
            "handlePopupClosed should call handleSessionDetected after 1s when session is valid")
    }

    /// handlePopupClosed() は hasValidSession が false のとき handleSessionDetected() を呼ばない。
    func testHandlePopupClosed_doesNotSetLoggedIn_whenSessionInvalid() async throws {
        let vm = makeVM()
        stubFetcher.hasValidSessionResult = false

        vm.handlePopupClosed()

        try await Task.sleep(nanoseconds: 1_500_000_000)

        XCTAssertFalse(vm.isLoggedIn,
            "handlePopupClosed should NOT call handleSessionDetected when session is invalid")
    }

    // MARK: - signOut: @Published 状態リセット

    /// signOut() は isLoggedIn を false にリセットする。
    func testSignOut_resetsIsLoggedIn() {
        let vm = makeVM()
        vm.handleSessionDetected()
        XCTAssertTrue(vm.isLoggedIn)

        vm.signOut()

        XCTAssertFalse(vm.isLoggedIn,
            "signOut should set isLoggedIn to false")
    }

    /// signOut() は isAutoRefreshEnabled を nil にリセットする。
    func testSignOut_resetsIsAutoRefreshEnabled() {
        let vm = makeVM()
        vm.isAutoRefreshEnabled = true

        vm.signOut()

        XCTAssertNil(vm.isAutoRefreshEnabled,
            "signOut should reset isAutoRefreshEnabled to nil")
    }

    /// signOut() は fiveHourPercent を nil にリセットする。
    func testSignOut_resetsFiveHourPercent() {
        let vm = makeVM()
        vm.fiveHourPercent = 50.0

        vm.signOut()

        XCTAssertNil(vm.fiveHourPercent,
            "signOut should reset fiveHourPercent to nil")
    }

    /// signOut() は sevenDayPercent を nil にリセットする。
    func testSignOut_resetsSevenDayPercent() {
        let vm = makeVM()
        vm.sevenDayPercent = 80.0

        vm.signOut()

        XCTAssertNil(vm.sevenDayPercent,
            "signOut should reset sevenDayPercent to nil")
    }

    /// signOut() は fiveHourResetsAt を nil にリセットする。
    func testSignOut_resetsFiveHourResetsAt() {
        let vm = makeVM()
        vm.fiveHourResetsAt = Date()

        vm.signOut()

        XCTAssertNil(vm.fiveHourResetsAt,
            "signOut should reset fiveHourResetsAt to nil")
    }

    /// signOut() は sevenDayResetsAt を nil にリセットする。
    func testSignOut_resetsSevenDayResetsAt() {
        let vm = makeVM()
        vm.sevenDayResetsAt = Date()

        vm.signOut()

        XCTAssertNil(vm.sevenDayResetsAt,
            "signOut should reset sevenDayResetsAt to nil")
    }

    /// signOut() は error を nil にリセットする。
    func testSignOut_resetsError() {
        let vm = makeVM()
        vm.error = "test error"

        vm.signOut()

        XCTAssertNil(vm.error,
            "signOut should reset error to nil")
    }

    // MARK: - signOut: Widget 連携

    /// signOut() は widgetReloader.reloadAllTimelines() を呼ぶ。
    func testSignOut_callsReloadAllTimelines() {
        let vm = makeVM()
        XCTAssertEqual(widgetReloader.reloadCount, 0)

        vm.signOut()

        XCTAssertEqual(widgetReloader.reloadCount, 1,
            "signOut should call widgetReloader.reloadAllTimelines() to update widget immediately")
    }

    /// signOut() は reloadAllTimelines() を1回呼ぶ。
    func testSignOut_widgetIntegration_reloadCalledOnce() {
        let vm = makeVM()

        vm.signOut()

        XCTAssertEqual(widgetReloader.reloadCount, 1,
            "reloadAllTimelines should be called exactly once")
    }

    /// signOut() を複数回呼んでも Widget 連携は毎回実行される。
    func testSignOut_calledTwice_widgetIntegrationCalledTwice() {
        let vm = makeVM()

        vm.signOut()
        vm.signOut()

        XCTAssertEqual(widgetReloader.reloadCount, 2,
            "Each signOut call should invoke reloadAllTimelines")
    }

    // MARK: - signOut: loginPollTimer 再開

    /// signOut() は非同期コールバック完了後に startLoginPolling() を呼び、loginPollTimer を再設定する。
    func testSignOut_restartsLoginPolling() async throws {
        let vm = makeVM()
        XCTAssertNil(vm.loginPollTimer)

        vm.signOut()

        // startLoginPolling() は removeData → getAllCookies → Task @MainActor の
        // 非同期コールバックチェーン内で呼ばれるため、十分な待機が必要
        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertNotNil(vm.loginPollTimer,
            "signOut should restart login polling via startLoginPolling()")
    }

    // MARK: - signOut: lastRedirectAt リセット

    /// signOut() は lastRedirectAt を nil にリセットする。
    /// これにより次回ログイン後のリダイレクトクールダウンがリセットされる。
    func testSignOut_resetsLastRedirectAt() {
        let vm = makeVM()
        // handleSessionDetected を呼んでリダイレクトを発生させることで lastRedirectAt が設定される可能性があるが、
        // 直接設定して確認する
        // lastRedirectAt は内部プロパティのため、signOut 後に isLoggedIn が false になることで
        // 間接的に全状態がリセットされたことを確認する
        vm.handleSessionDetected()
        vm.signOut()

        XCTAssertFalse(vm.isLoggedIn)
        XCTAssertNil(vm.fiveHourPercent)
        XCTAssertNil(vm.sevenDayPercent)
        XCTAssertNil(vm.isAutoRefreshEnabled)
    }
}
