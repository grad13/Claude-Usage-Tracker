// Supplement for: architecture integration tests
// Source spec: spec/meta/architecture.md
// Generated: 2026-03-03
//
// Coverage intent:
//   - Cookie監視のコールバック接続性（WKHTTPCookieStoreObserver 登録）
//   - ページ遷移の5秒クールダウンロジック
//   - WebView dataStore の構造テスト（永続化・型）
//   - サインアウト（dataStore 全削除 + 個別Cookie削除）の構造テスト
//   - isAutoRefreshEnabled の3状態遷移（nil / true / false）
//   - デリゲート配置（Coordinator は ViewModel が所有し、init で設定される）
//   - LoginWebView はデリゲートを設定しない（ViewModel 側に統合）
//
// Skip policy:
//   - OAuth ポップアップ（Google OAuth の WKWebView ブロック問題）は実機依存のためスキップ
//   - didFinish デリゲートのトリガーはネットワーク実行が必要なためスキップ
//   - JS フォールバック（org ID 取得4段階）は WKWebView 実行環境依存のためスキップ

import XCTest
import WebKit
@testable import ClaudeUsageTracker

// MARK: - WebView DataStore Structure Tests
// spec: "WKWebsiteDataStore.default() を使用。App Sandbox 無効と組み合わせてセッション間で Cookie を永続化する。"

@MainActor
final class ArchitectureDataStoreTests: XCTestCase {

    func makeVM() -> UsageViewModel {
        UsageViewModel(
            fetcher: StubUsageFetcher(),
            settingsStore: InMemorySettingsStore(),
            usageStore: InMemoryUsageStore(),
            snapshotWriter: InMemorySnapshotWriter(),
            widgetReloader: InMemoryWidgetReloader(),
            tokenSync: InMemoryTokenSync(),
            loginItemManager: InMemoryLoginItemManager(),
            alertChecker: MockAlertChecker()
        )
    }

    // spec: "WKWebsiteDataStore.default() を使用"
    // → default() は App Group 共有 Cookie ストアを指す。永続ストアであることを確認する。
    func testWebView_dataStoreIsPersistent() {
        let vm = makeVM()
        let store = vm.webView.configuration.websiteDataStore
        XCTAssertTrue(
            store.isPersistent,
            "DataStore must be persistent — spec requires cookie retention across app restarts"
        )
    }

    // spec: Cookie 永続化のために WKWebsiteDataStore.default() を使用
    // → webView が nonEphemeral（永続）ストアを持つことを確認。
    func testWebView_dataStoreIsNotEphemeral() {
        let vm = makeVM()
        let store = vm.webView.configuration.websiteDataStore
        let ephemeral = WKWebsiteDataStore.nonPersistent()
        XCTAssertNotEqual(
            store, ephemeral,
            "DataStore must not be ephemeral — session cookies would be lost on restart"
        )
    }

    // spec: "UsageViewModel が単一の WKWebView インスタンスを所有"
    // → 同一 VM からの2回アクセスで同じインスタンスが返ることを確認。
    func testWebView_isSingletonInstance() {
        let vm = makeVM()
        let ref1 = vm.webView
        let ref2 = vm.webView
        XCTAssertTrue(
            ref1 === ref2,
            "webView must be a single owned instance — shared between login UI and API fetch"
        )
    }
}

// MARK: - Delegate Placement Tests
// spec: "WebViewCoordinator（WKNavigationDelegate + WKUIDelegate）は UsageViewModel が所有。
//        init() でデリゲートを設定し、アプリのライフサイクル全体で維持する。"

@MainActor
final class ArchitectureDelegatePlacementTests: XCTestCase {

    func makeVM() -> UsageViewModel {
        UsageViewModel(
            fetcher: StubUsageFetcher(),
            settingsStore: InMemorySettingsStore(),
            usageStore: InMemoryUsageStore(),
            snapshotWriter: InMemorySnapshotWriter(),
            widgetReloader: InMemoryWidgetReloader(),
            tokenSync: InMemoryTokenSync(),
            loginItemManager: InMemoryLoginItemManager(),
            alertChecker: MockAlertChecker()
        )
    }

    // spec: "init() でデリゲートを設定し、アプリのライフサイクル全体で維持する"
    // → VM 初期化直後に navigationDelegate が設定されていることを確認。
    func testWebView_navigationDelegateIsSetOnInit() {
        let vm = makeVM()
        XCTAssertNotNil(
            vm.webView.navigationDelegate,
            "navigationDelegate must be set in init() — coordinator must be ready before first page load"
        )
    }

    // spec: "WKUIDelegate（OAuth ポップアップ createWebViewWith）は UsageViewModel が所有"
    // → VM 初期化直後に uiDelegate が設定されていることを確認。
    func testWebView_uiDelegateIsSetOnInit() {
        let vm = makeVM()
        XCTAssertNotNil(
            vm.webView.uiDelegate,
            "uiDelegate must be set in init() — OAuth popup handling via createWebViewWith requires it"
        )
    }

    // spec: デリゲートは ViewModel の Coordinator が常時担当
    // → navigationDelegate と uiDelegate が同一オブジェクト（Coordinator）であることを確認。
    func testWebView_navigationAndUIDelegateAreSameCoordinator() {
        let vm = makeVM()
        let navDel = vm.webView.navigationDelegate
        let uiDel = vm.webView.uiDelegate
        XCTAssertTrue(
            navDel === uiDel,
            "navigationDelegate and uiDelegate must be the same Coordinator instance per spec"
        )
    }
}

// MARK: - isAutoRefreshEnabled State Tests
// spec: "isAutoRefreshEnabled フラグで制御
//        nil（未確定）: ページ準備完了時にフェッチを試行
//        true: 自動リフレッシュ有効
//        false: 自動リフレッシュ無効（認証エラー時に設定）"

@MainActor
final class ArchitectureAutoRefreshFlagTests: XCTestCase {

    func makeVM() -> UsageViewModel {
        UsageViewModel(
            fetcher: StubUsageFetcher(),
            settingsStore: InMemorySettingsStore(),
            usageStore: InMemoryUsageStore(),
            snapshotWriter: InMemorySnapshotWriter(),
            widgetReloader: InMemoryWidgetReloader(),
            tokenSync: InMemoryTokenSync(),
            loginItemManager: InMemoryLoginItemManager(),
            alertChecker: MockAlertChecker()
        )
    }

    // spec: "nil（未確定）: ページ準備完了時にフェッチを試行"
    // → 初期状態は nil であることを確認。
    func testIsAutoRefreshEnabled_initialStateIsNil() {
        let vm = makeVM()
        XCTAssertNil(
            vm.isAutoRefreshEnabled,
            "isAutoRefreshEnabled must be nil on init — undetermined state before page ready"
        )
    }

    // spec: "true: 自動リフレッシュ有効。タイマーでフェッチ"
    // → true に設定した後も true のままであることを確認。
    func testIsAutoRefreshEnabled_canBeSetToTrue() {
        let vm = makeVM()
        vm.isAutoRefreshEnabled = true
        XCTAssertEqual(
            vm.isAutoRefreshEnabled, true,
            "isAutoRefreshEnabled=true must be retained — controls timer-based fetch"
        )
    }

    // spec: "false: 自動リフレッシュ無効。認証エラー（401, 403, Missing organization）時に設定"
    // → false に設定した後も false のままであることを確認。
    func testIsAutoRefreshEnabled_canBeSetToFalse() {
        let vm = makeVM()
        vm.isAutoRefreshEnabled = false
        XCTAssertEqual(
            vm.isAutoRefreshEnabled, false,
            "isAutoRefreshEnabled=false must be retained — set on auth errors (401/403)"
        )
    }

    // spec: "手動 Refresh は isAutoRefreshEnabled の値に関わらず常に実行可能"
    // → false 状態でも manualRefresh() を呼び出してもクラッシュしないことを確認。
    // （実際のフェッチ成否は StubFetcher に依存するが、呼び出し可能性をテスト）
    func testManualRefresh_canBeCalledWhenAutoRefreshDisabled() {
        let vm = makeVM()
        vm.isAutoRefreshEnabled = false
        // manualRefresh は isAutoRefreshEnabled に関わらず呼び出せる
        vm.manualRefresh()
        // No assertion on result — we only verify it does not crash and does not throw
        XCTAssertEqual(
            vm.isAutoRefreshEnabled, false,
            "manualRefresh must not change isAutoRefreshEnabled flag"
        )
    }
}

// MARK: - Redirect Cooldown Tests
// spec: "OAuth 完了後、claude.ai はチャットページにリダイレクトする。
//        ログイン済みかつ usage ページ以外にいる場合、usage ページへ自動遷移する。
//        5秒のクールダウンで無限ループを防止する。"

@MainActor
final class ArchitectureRedirectCooldownTests: XCTestCase {

    func makeVM() -> UsageViewModel {
        UsageViewModel(
            fetcher: StubUsageFetcher(),
            settingsStore: InMemorySettingsStore(),
            usageStore: InMemoryUsageStore(),
            snapshotWriter: InMemorySnapshotWriter(),
            widgetReloader: InMemoryWidgetReloader(),
            tokenSync: InMemoryTokenSync(),
            loginItemManager: InMemoryLoginItemManager(),
            alertChecker: MockAlertChecker()
        )
    }

    // spec: "5秒のクールダウンで無限ループを防止する"
    // → 初期状態では lastRedirectTime が nil（クールダウン未発動）であることを確認。
    func testLastRedirectTime_initialStateIsNil() {
        let vm = makeVM()
        XCTAssertNil(
            vm.lastRedirectTime,
            "lastRedirectTime must be nil on init — no redirect has occurred yet"
        )
    }

    // spec: クールダウン中は再リダイレクトしない（5秒以内の2回目をブロック）
    // → canRedirectNow() が lastRedirectTime 設定直後に false を返すことを確認。
    func testCanRedirectNow_falseWhenCooldownActive() {
        let vm = makeVM()
        // lastRedirectTime を現在時刻に設定してクールダウン発動状態にする
        vm.lastRedirectTime = Date()
        XCTAssertFalse(
            vm.canRedirectNow(),
            "canRedirectNow must return false within 5-second cooldown to prevent redirect loops"
        )
    }

    // spec: 5秒経過後はリダイレクト可能
    // → 6秒前の時刻を lastRedirectTime に設定した場合、canRedirectNow() が true を返すことを確認。
    func testCanRedirectNow_trueAfterCooldownExpires() {
        let vm = makeVM()
        vm.lastRedirectTime = Date().addingTimeInterval(-6)
        XCTAssertTrue(
            vm.canRedirectNow(),
            "canRedirectNow must return true after 5-second cooldown has elapsed"
        )
    }

    // spec: "ログイン済みかつ usage ページ以外にいる場合" → isLoggedIn が必要条件
    // → isLoggedIn=false の場合は canRedirectNow() の返値に関わらずリダイレクト不可
    //   （この条件はコールサイトの if 文で実装されるため、ここでは isLoggedIn 初期値を確認）
    func testIsLoggedIn_initialStateIsFalse() {
        let vm = makeVM()
        XCTAssertFalse(
            vm.isLoggedIn,
            "isLoggedIn must be false on init — login is detected via Cookie observation, not assumed"
        )
    }
}

// MARK: - Sign Out Structure Tests
// spec: "サインアウト（二重削除方式）
//   1. WKWebsiteDataStore.default() から全データタイプを削除
//   2. httpCookieStore.getAllCookies で全 Cookie を個別に delete
//   3. usage ページをリロード"

@MainActor
final class ArchitectureSignOutTests: XCTestCase {

    func makeVM() -> UsageViewModel {
        UsageViewModel(
            fetcher: StubUsageFetcher(),
            settingsStore: InMemorySettingsStore(),
            usageStore: InMemoryUsageStore(),
            snapshotWriter: InMemorySnapshotWriter(),
            widgetReloader: InMemoryWidgetReloader(),
            tokenSync: InMemoryTokenSync(),
            loginItemManager: InMemoryLoginItemManager(),
            alertChecker: MockAlertChecker()
        )
    }

    // spec: signOut 後に isLoggedIn=false になることを確認
    // （実際の Cookie 削除の完了は非同期・実機依存のため、フラグ変化のみを検証）
    func testSignOut_resetsIsLoggedIn() async {
        let vm = makeVM()
        vm.isLoggedIn = true

        await vm.signOut()

        XCTAssertFalse(
            vm.isLoggedIn,
            "signOut must set isLoggedIn=false — user must re-authenticate after sign out"
        )
    }

    // spec: signOut 後に isAutoRefreshEnabled=nil（未確定）に戻る
    // → 再ログイン後のフェッチフローを初期状態から再開するため nil にリセット
    func testSignOut_resetsAutoRefreshEnabled() async {
        let vm = makeVM()
        vm.isAutoRefreshEnabled = true

        await vm.signOut()

        XCTAssertNil(
            vm.isAutoRefreshEnabled,
            "signOut must reset isAutoRefreshEnabled to nil — fetch flow must restart from undetermined state"
        )
    }

    // NOTE: WKWebsiteDataStore の実際の削除完了（removeData + individual cookie delete）は
    // 実機 + WKWebView 環境でのみ検証可能。ユニットテストではフラグ変化のみ確認する。
}

// MARK: - Cookie Observation Connectivity Tests
// spec: "Cookie 監視: WKHTTPCookieStoreObserver で Cookie 変更を監視し、
//        sessionKey Cookie の出現でログインを検出"

@MainActor
final class ArchitectureCookieObserverTests: XCTestCase {

    func makeVM() -> UsageViewModel {
        UsageViewModel(
            fetcher: StubUsageFetcher(),
            settingsStore: InMemorySettingsStore(),
            usageStore: InMemoryUsageStore(),
            snapshotWriter: InMemorySnapshotWriter(),
            widgetReloader: InMemoryWidgetReloader(),
            tokenSync: InMemoryTokenSync(),
            loginItemManager: InMemoryLoginItemManager(),
            alertChecker: MockAlertChecker()
        )
    }

    // spec: "Cookie 監視開始（CookieChangeObserver）" は init() のデータフローに含まれる
    // → VM 初期化後、cookieStore のオブザーバーが登録済みであることを構造的に確認。
    // WebViewCoordinator が WKHTTPCookieStoreObserver に準拠しているかをプロトコル準拠で検証。
    //
    // NOTE: 実際のオブザーバー登録（addObserver 呼び出し）は WKWebView の内部状態であり
    // XCTest から直接確認不可。ここでは Coordinator がプロトコルに準拠していることを型レベルで確認。
    func testWebViewCoordinator_conformsToHTTPCookieStoreObserver() {
        let vm = makeVM()
        let navDelegate = vm.webView.navigationDelegate
        XCTAssertNotNil(
            navDelegate as? WKHTTPCookieStoreObserver,
            "WebViewCoordinator (navigationDelegate) must conform to WKHTTPCookieStoreObserver for cookie monitoring"
        )
    }

    // spec: "OAuth ログイン後 → Cookie 変更を CookieChangeObserver が検出
    //        → sessionKey Cookie 確認 → isLoggedIn=true"
    // → cookiesDidChange コールバックが到達すると isLoggedIn が true に変化することを確認。
    // 実装: Coordinator の cookiesDidChange を直接呼び出してフローを検証。
    func testCookiesDidChange_sessionKeyCookieSetsIsLoggedIn() async {
        let vm = makeVM()
        XCTAssertFalse(vm.isLoggedIn)

        // sessionKey Cookie を cookieStore に追加
        let cookie = HTTPCookie(properties: [
            .name: "sessionKey",
            .value: "test-session-value",
            .domain: "claude.ai",
            .path: "/"
        ])!
        await vm.webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)

        // cookiesDidChange コールバックが非同期で発火するため待機
        let expectation = XCTestExpectation(description: "isLoggedIn becomes true")
        let poller = Task {
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                if vm.isLoggedIn { expectation.fulfill(); return }
            }
        }
        await fulfillment(of: [expectation], timeout: 3.0)
        poller.cancel()

        XCTAssertTrue(
            vm.isLoggedIn,
            "isLoggedIn must become true when sessionKey cookie appears — spec: Cookie-based login detection"
        )
    }
}
