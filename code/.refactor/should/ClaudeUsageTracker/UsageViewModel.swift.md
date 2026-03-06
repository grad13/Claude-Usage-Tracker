---
File: ClaudeUsageTracker/UsageViewModel.swift
Lines: 317
Judgment: should
Issues: [責務混在 - WebView初期化/Cookie管理/ナビゲーション制御/リトライロジックがViewModel内に同居]
---

# UsageViewModel.swift

## 問題点

### 1. WebView 初期化・設定が ViewModel に埋め込まれている

**現状**: init() 内(L99-107)で WKWebViewConfiguration の生成、UUID ベースの WKWebsiteDataStore 設定、WKWebView のインスタンス化を直接行っている。
**本質**: WebView のインフラ構築は ViewModel の責務ではない。テスト時に WebView の設定をモックや差し替えできず、init が重い副作用を持つ。
**あるべき姿**: WebView の生成・設定をファクトリまたは外部から注入し、ViewModel は受け取るだけにする。

### 2. ナビゲーション制御とリダイレクトスロットリングの混在

**現状**: loadUsagePage(L269-276)、isOnUsagePage(L278-281)、canRedirect(L283-286)、lastRedirectAt(L37) がナビゲーション状態管理を担い、handlePageReady(L135-165) 内でリダイレクト判定ロジックが展開されている。
**本質**: ページ遷移の制御は WebViewCoordinator 側の関心事であり、ViewModel がリダイレクトのクールダウン管理まで持つと責務境界が曖昧になる。
**あるべき姿**: ナビゲーション判定ロジックを Coordinator またはナビゲーション専用オブジェクトに移動し、ViewModel は「データ取得を依頼する」だけにする。

### 3. リトライロジックが fetchSilently 内にインライン展開されている

**現状**: fetchSilently(L201-246) 内で retryCount、maxRetries、retryDelays による指数バックオフリトライが直接実装されている(L233-241)。再帰的に自身を呼び出す構造。
**本質**: リトライポリシーがフェッチロジックと密結合しており、リトライ戦略の変更やテストが困難。再帰呼び出しは状態追跡を複雑にする。
**あるべき姿**: リトライロジックを汎用的なユーティリティまたは fetcher 側の責務として分離する。
