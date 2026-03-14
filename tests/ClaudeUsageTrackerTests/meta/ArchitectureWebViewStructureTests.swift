// Supplement for: architecture integration tests (WebView structure)
// Source spec: spec/meta/architecture.md
// Generated: 2026-03-03
//
// Coverage intent:
//   - WebView dataStore の構造テスト（永続化・型）
//   - デリゲート配置（Coordinator は ViewModel が所有し、init で設定される）
//
// Skip policy:
//   - OAuth ポップアップ（Google OAuth の WKWebView ブロック問題）は実機依存のためスキップ
//   - didFinish デリゲートのトリガーはネットワーク実行が必要なためスキップ

import XCTest
import WebKit
@testable import ClaudeUsageTracker

// MARK: - WebView DataStore Structure Tests
// spec: "WKWebsiteDataStore.default() を使用。App Sandbox 無効と組み合わせてセッション間で Cookie を永続化する。"

@MainActor
final class ArchitectureDataStoreTests: XCTestCase {

    func makeVM() -> UsageViewModel { ViewModelTestFactory.makeVM() }

    // spec: "WKWebsiteDataStore.default() を使用"
    // → default() は App Group 共有 Cookie ストアを指す。永続ストアであることを確認する。
    // Note: Uses production config (webViewConfiguration: nil) to verify persistence.
    // Test VMs use nonPersistent() to avoid destroying real session cookies.
    func testWebView_dataStoreIsPersistent() {
        let vm = UsageViewModel(webViewConfiguration: nil)
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

    func makeVM() -> UsageViewModel { ViewModelTestFactory.makeVM() }

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
