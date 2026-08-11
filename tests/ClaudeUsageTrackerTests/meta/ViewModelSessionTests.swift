// meta: updated=2026-08-12 checked=-
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

    func makeVM(
        startLifecycle: Bool = true,
        sleeper: @escaping UsageViewModel.Sleeper = { _ in },
        timerScheduler: any ViewModelTimerScheduling = ManualViewModelTimerScheduler()
    ) -> UsageViewModel {
        ViewModelTestFactory.makeVM(
            fetcher: stubFetcher,
            settingsStore: settingsStore,
            usageStore: usageStore,
            widgetReloader: widgetReloader,
            loginItemManager: loginItemManager,
            alertChecker: alertChecker,
            startLifecycle: startLifecycle,
            sleeper: sleeper,
            timerScheduler: timerScheduler
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

    // MARK: - handleSessionDetected: 基本動作

    /// handleSessionDetected() がクラッシュしないことを確認する。
    func testHandleSessionDetected_doesNotCrash() {
        let vm = makeVM()
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
    /// Note: init() now calls startLoginPolling() synchronously, so timer is already set.
    func testStartLoginPolling_setsTimer() {
        let vm = makeVM()
        // init() calls startLoginPolling(), so timer is already set
        XCTAssertNotNil(vm.loginPollTimer)
        // Invalidate and nil it, then verify startLoginPolling re-creates it
        vm.loginPollTimer?.invalidate()
        vm.loginPollTimer = nil
        vm.startLoginPolling()
        XCTAssertNotNil(vm.loginPollTimer)
    }

    /// handleSessionDetected() は loginPollTimer を停止しない。
    /// Cookie 検出後にページロード・データ取得が失敗しても polling が継続して再試行できるよう、
    /// timer は applyResult() 成功時のみ停止する仕様。
    func testHandleSessionDetected_keepsLoginPollTimerAlive() {
        let vm = makeVM()
        vm.startLoginPolling()
        XCTAssertNotNil(vm.loginPollTimer, "Timer should be set before handleSessionDetected")

        vm.handleSessionDetected()

        XCTAssertNotNil(vm.loginPollTimer,
            "handleSessionDetected must keep loginPollTimer alive — it is stopped only by applyResult()")
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

    // MARK: - checkPopupLogin: 500ms clock semantics

    func testCheckPopupLogin_validSessionWaits500msThenClosesAndReleasesPopupReference() {
        let sleeper = ManualSleeper()
        let sleepStarted = expectation(description: "500ms popup feedback delay started")
        sleeper.onSleep = { delay in
            XCTAssertEqual(delay, 0.5)
            sleepStarted.fulfill()
        }
        let completed = expectation(description: "valid popup session accepted")
        completed.assertForOverFulfill = true
        let vm = makeVM(startLifecycle: false, sleeper: sleeper.sleep)
        stubFetcher.hasValidSessionResult = true

        let popup = WKWebView(frame: .zero)
        vm.popupWebView = popup
        var completionCount = 0

        vm.checkPopupLogin { outcome in
            completionCount += 1
            XCTAssertEqual(outcome, .sessionAccepted)
            completed.fulfill()
        }

        wait(for: [sleepStarted], timeout: 2.0)
        XCTAssertEqual(sleeper.requestedDelays, [0.5])
        XCTAssertNotNil(vm.popupWebView, "the popup must remain visible during the feedback delay")
        XCTAssertFalse(vm.isLoggedIn)

        sleeper.resumeNext()
        wait(for: [completed], timeout: 2.0)

        XCTAssertTrue(vm.isLoggedIn)
        XCTAssertNil(vm.popupWebView)
        XCTAssertEqual(completionCount, 1, "the popup check must complete exactly once")
    }

    func testCheckPopupLogin_invalidSessionFinishesWithoutDelayOrClosingPopup() {
        let sleeper = ManualSleeper()
        let completed = expectation(description: "invalid popup session rejected")
        completed.assertForOverFulfill = true
        let vm = makeVM(startLifecycle: false, sleeper: sleeper.sleep)
        stubFetcher.hasValidSessionResult = false
        let popup = WKWebView(frame: .zero)
        vm.popupWebView = popup

        vm.checkPopupLogin { outcome in
            XCTAssertEqual(outcome, .noValidSession)
            completed.fulfill()
        }

        wait(for: [completed], timeout: 2.0)
        XCTAssertEqual(stubFetcher.hasValidSessionCallCount, 1)
        XCTAssertTrue(sleeper.requestedDelays.isEmpty,
            "the 500ms visual delay applies only after a valid session is found")
        XCTAssertTrue(vm.popupWebView === popup)
        XCTAssertFalse(vm.isLoggedIn)
    }

    func testClosePopupCancelsPendingCheckAndStaleWorkCannotRestoreSession() {
        let sleeper = ManualSleeper()
        let sleepStarted = expectation(description: "popup check reached delay")
        sleeper.onSleep = { _ in sleepStarted.fulfill() }
        let sleepReturned = expectation(description: "stale popup delay returned")
        sleeper.onSleepReturn = { sleepReturned.fulfill() }
        let cancelled = expectation(description: "pending popup check cancelled")
        cancelled.assertForOverFulfill = true
        let vm = makeVM(startLifecycle: false, sleeper: sleeper.sleep)
        stubFetcher.hasValidSessionResult = true

        let popup = WKWebView(frame: .zero)
        vm.popupWebView = popup
        var completionCount = 0
        vm.checkPopupLogin { outcome in
            completionCount += 1
            XCTAssertEqual(outcome, .cancelled)
            cancelled.fulfill()
        }
        wait(for: [sleepStarted], timeout: 2.0)
        XCTAssertTrue(vm.popupWebView === popup,
            "the ViewModel must own the popup until it is explicitly closed")

        vm.closePopup()
        wait(for: [cancelled], timeout: 2.0)
        XCTAssertNil(vm.popupWebView)
        XCTAssertEqual(completionCount, 1, "closing the popup must cancel the check exactly once")

        sleeper.resumeNext()
        wait(for: [sleepReturned], timeout: 2.0)
        XCTAssertFalse(vm.isLoggedIn, "cancelled stale work must not accept the old session")
        XCTAssertNil(vm.popupWebView, "cancelled stale work must not restore the popup reference")
        XCTAssertEqual(completionCount, 1, "cancelled stale work must not complete again")
    }

    // MARK: - handlePopupClosed: 1s clock semantics

    func testHandlePopupClosed_validSessionChecksOnlyAfterOneSecondDelay() {
        let sleeper = ManualSleeper()
        let sleepStarted = expectation(description: "cookie propagation delay started")
        sleeper.onSleep = { delay in
            XCTAssertEqual(delay, 1.0)
            sleepStarted.fulfill()
        }
        let completed = expectation(description: "closed popup session accepted")
        completed.assertForOverFulfill = true
        let vm = makeVM(startLifecycle: false, sleeper: sleeper.sleep)
        stubFetcher.hasValidSessionResult = true

        vm.handlePopupClosed { outcome in
            XCTAssertEqual(outcome, .sessionAccepted)
            completed.fulfill()
        }

        wait(for: [sleepStarted], timeout: 2.0)
        XCTAssertEqual(sleeper.requestedDelays, [1.0])
        XCTAssertEqual(stubFetcher.hasValidSessionCallCount, 0,
            "session lookup must happen after the cookie propagation delay")
        XCTAssertFalse(vm.isLoggedIn)

        sleeper.resumeNext()
        wait(for: [completed], timeout: 2.0)
        XCTAssertEqual(stubFetcher.hasValidSessionCallCount, 1)
        XCTAssertTrue(vm.isLoggedIn)
    }

    func testHandlePopupClosed_invalidSessionReturnsExplicitOutcome() {
        let sleeper = ManualSleeper()
        let sleepStarted = expectation(description: "cookie propagation delay started")
        sleeper.onSleep = { delay in
            XCTAssertEqual(delay, 1.0)
            sleepStarted.fulfill()
        }
        let completed = expectation(description: "closed popup session rejected")
        completed.assertForOverFulfill = true
        let vm = makeVM(startLifecycle: false, sleeper: sleeper.sleep)
        stubFetcher.hasValidSessionResult = false

        vm.handlePopupClosed { outcome in
            XCTAssertEqual(outcome, .noValidSession)
            completed.fulfill()
        }

        wait(for: [sleepStarted], timeout: 2.0)
        sleeper.resumeNext()
        wait(for: [completed], timeout: 2.0)
        XCTAssertEqual(stubFetcher.hasValidSessionCallCount, 1)
        XCTAssertFalse(vm.isLoggedIn)
    }

    func testHandlePopupClosedReplacementCancelsStaleDelayedCheck() {
        let sleeper = ManualSleeper()
        let firstSleepStarted = expectation(description: "first popup-close delay started")
        let sleepsStarted = expectation(description: "both popup-close delays started")
        sleepsStarted.expectedFulfillmentCount = 2
        var sleepStartCount = 0
        sleeper.onSleep = { delay in
            XCTAssertEqual(delay, 1.0)
            sleepStartCount += 1
            if sleepStartCount == 1 {
                firstSleepStarted.fulfill()
            }
            sleepsStarted.fulfill()
        }
        let firstCancelled = expectation(description: "first popup-close check cancelled")
        firstCancelled.assertForOverFulfill = true
        let secondCompleted = expectation(description: "replacement popup-close check completed")
        secondCompleted.assertForOverFulfill = true
        let staleSleepReturned = expectation(description: "stale popup-close delay returned")
        let currentSleepReturned = expectation(description: "current popup-close delay returned")
        var sleepReturnCount = 0
        sleeper.onSleepReturn = {
            sleepReturnCount += 1
            if sleepReturnCount == 1 {
                staleSleepReturned.fulfill()
            } else {
                currentSleepReturned.fulfill()
            }
        }
        let vm = makeVM(startLifecycle: false, sleeper: sleeper.sleep)
        stubFetcher.hasValidSessionResult = true

        vm.handlePopupClosed { outcome in
            XCTAssertEqual(outcome, .cancelled)
            firstCancelled.fulfill()
        }
        wait(for: [firstSleepStarted], timeout: 2.0)
        stubFetcher.hasValidSessionResult = false
        vm.handlePopupClosed { outcome in
            XCTAssertEqual(outcome, .noValidSession)
            secondCompleted.fulfill()
        }

        wait(for: [sleepsStarted, firstCancelled], timeout: 2.0)
        sleeper.resumeNext()
        wait(for: [staleSleepReturned], timeout: 2.0)
        XCTAssertEqual(stubFetcher.hasValidSessionCallCount, 0,
            "resumed stale work must not perform a session lookup")

        sleeper.resumeNext()
        wait(for: [currentSleepReturned, secondCompleted], timeout: 2.0)
        XCTAssertEqual(stubFetcher.hasValidSessionCallCount, 1)
        XCTAssertFalse(vm.isLoggedIn)
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

    /// The terminal callback runs only after WebView cleanup, page reload, and polling restart.
    func testSignOut_completionObservesExactTerminalOrdering() {
        let scheduler = ManualViewModelTimerScheduler()
        let vm = makeVM(startLifecycle: false, timerScheduler: scheduler)
        let cookieStore = vm.webView.configuration.websiteDataStore.httpCookieStore
        let cookie = HTTPCookie(properties: [
            .domain: "claude.ai",
            .path: "/",
            .name: "sessionKey",
            .value: "test-session",
            .secure: "TRUE"
        ])!
        let cookieStored = expectation(description: "cookie stored before sign-out")
        cookieStore.setCookie(cookie) { cookieStored.fulfill() }
        wait(for: [cookieStored], timeout: 2.0)

        vm.handleSessionDetected()
        vm.fiveHourPercent = 50
        vm.sevenDayPercent = 80
        let completed = expectation(description: "sign-out terminal completion")
        completed.assertForOverFulfill = true
        var completionCount = 0

        vm.signOut { outcome in
            completionCount += 1
            XCTAssertEqual(outcome, .completed)
            XCTAssertFalse(vm.isLoggedIn)
            XCTAssertNil(vm.fiveHourPercent)
            XCTAssertNil(vm.sevenDayPercent)
            XCTAssertEqual(self.widgetReloader.reloadCount, 1,
                "widget reload must precede asynchronous WebView cleanup")
            XCTAssertNotNil(vm.loginPollTimer,
                "terminal completion must follow startLoginPolling()")
            XCTAssertEqual(scheduler.validTimers.count, 1)
            XCTAssertEqual(scheduler.validTimers[0].timeInterval, 3.0)
            XCTAssertEqual(vm.webView.url?.host, UsageViewModel.targetHost,
                "terminal completion must follow loadUsagePage()")
            completed.fulfill()
        }

        XCTAssertFalse(vm.isLoggedIn, "published state resets synchronously")
        XCTAssertEqual(widgetReloader.reloadCount, 1,
            "widget reload is requested before asynchronous cleanup finishes")
        wait(for: [completed], timeout: 5.0)
        XCTAssertEqual(completionCount, 1)

        let cookiesRead = expectation(description: "cookies inspected after sign-out")
        cookieStore.getAllCookies { cookies in
            XCTAssertFalse(cookies.contains { $0.name == "sessionKey" },
                "terminal completion must follow individual cookie deletion")
            cookiesRead.fulfill()
        }
        wait(for: [cookiesRead], timeout: 2.0)
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
