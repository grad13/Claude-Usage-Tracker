---
File: ClaudeUsageTracker/UsageViewModel.swift
Lines: 308
Judgment: should
Issues: [WebView構築がViewModel内, デバッグログ機構が埋め込み, Cookie/Session管理が混在, applyResultの副作用集中, 初期化の副作用過多]
---

# UsageViewModel.swift

## 問題点

### 1. WebView の構築・設定が ViewModel 内にある

**現状**: init() の L114-128 で WKWebViewConfiguration の生成、WKWebsiteDataStore の設定（ハードコードされた UUID）、WKWebView のインスタンス化、coordinator の設定をすべて ViewModel が行っている。
**本質**: WebView の構築はインフラ層の責務であり、ViewModel が WebKit の詳細（dataStore ID、javaScriptCanOpenWindowsAutomatically など）を知る必要はない。テスト時に WKWebView を差し替えられない。
**あるべき姿**: WebView の生成は外部から注入するか、ファクトリに委譲する。ViewModel は WebView のインターフェースのみに依存する。

### 2. デバッグログ機構が埋め込まれている

**現状**: L76-93 で logURL（static let）と debug() メソッドがファイル書き込みまで含めて定義されている。ViewModel の全メソッドから直接呼ばれている。
**本質**: ログ出力はクロスカッティング関心事であり、特定の ViewModel に属さない。FileHandle 操作という I/O 詳細も ViewModel が持つべきではない。
**あるべき姿**: Logger プロトコルに抽出し、init で注入する。NSLog + ファイル書き込みの実装は別クラスに分離する。

### 3. Cookie/Session管理がViewModelに混在

**現状**: L136 startCookieObservation()、L141 restoreSessionCookies()、L164 backupSessionCookies() がViewModel内で直接呼び出される。cookieObserver フィールド（L31）で監視を保持。
**本質**: セッション永続化は認証インフラの責務。ViewModel がいつバックアップし、いつリストアするかを知っている状態は、認証ロジックの変更時に ViewModel を修正する必要が生じる。
**あるべき姿**: SessionCoordinator に委譲し、ViewModel は「ログイン済みかどうか」だけを受け取る。

### 4. handlePageReady() にオーケストレーションロジックが集中

**現状**: L150-179 で、セッション確認 → ログイン状態更新 → タイマー停止 → auto-refresh開始 → cookie バックアップ → ページ判定 → リダイレクト判定 → フェッチという複数ステップを1メソッドで実行。リダイレクトのクールダウン（lastRedirectAt, canRedirect()）もViewModel内。
**本質**: WebViewCoordinatorDelegate のイベントハンドリングとビジネスロジック（リダイレクト判定、クールダウン）が密結合。
**あるべき姿**: ページ遷移コーディネータに分離。ViewModel は状態更新のみ。

### 5. 初期化時の副作用が多い

**現状**: init() L99-146 で、WebView構築、設定読み込み、coordinator設定、履歴ロード、SQLiteバックアップ実行、ログインアイテム同期、cookie観察開始、非同期cookie復元、ページロード、ログインポーリング開始を一気に行う。
**本質**: 初期化が順序敏感で副作用が多い。テスト時にすべてが走る。初期化失敗時の復旧パスが不明確。
**あるべき姿**: 初期化を段階化。構築と起動を分離し、start() メソッドで非同期処理を明示的に開始する。
