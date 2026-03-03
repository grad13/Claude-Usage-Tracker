---
File: ClaudeUsageTracker/UsageViewModel.swift
Lines: 325
Judgment: should
Issues: [Cookie/Session management mixed with state management, Auto-refresh timer logic coupled with fetch, WebViewCoordinatorDelegate mixed with ViewModel responsibility, applyResult performs too many side effects across multiple stores]
---

# UsageViewModel.swift

## 問題点

### 1. Cookie/Session管理がViewModelに混在

**現状**: Lines 149, 154-156, 177, 238
- `startCookieObservation()`, `restoreSessionCookies()`, `backupSessionCookies()` がViewModel内で直接呼び出される
- 初期化時にクッキー復元を含む非同期処理をTask内で実行
- クッキー変更の監視が`cookieObserver`フィールドで保持されている

**本質**: セッション管理はクッキー同期の詳細であり、使用量データ取得のViewModelレイヤーに入るべきではない。これはコーディネータ層またはサービス層が担うべき関心事。

**あるべき姿**: セッション復元・バックアップをSessionCoordinatorなど専用クラスに分離。ViewModelは「セッションが復元された」というイベントを受け取るだけ。

### 2. Auto-refresh タイマー管理が複数の責務に結合

**現状**: Lines 302-323
- `startAutoRefresh()` はタイマーを開始し、内部で`fetch()`を呼び出し
- `restartAutoRefresh()` は停止→再開。`isLoggedIn`状態に基づいて条件分岐
- リフレッシュ間隔は`refreshInterval`で計算。設定変更時の再起動ロジックがない

**本質**: タイマー管理とフェッチロジックが密結合。設定の動的変更に対応していない。タイマーは再利用可能なユーティリティ（RefreshCoordinator）に分離すべき。

**あるべき姿**: RefreshCoordinatorまたはTimerMangerを分離。ViewModelは「今からリフレッシュを開始したい」という意図を示すだけ。内部の周期実行メカニズムはジョブスケジューラーに委譲。

### 3. WebViewCoordinatorDelegate責務がViewModelに混在

**現状**: Lines 9, 163-193
- `WebViewCoordinatorDelegate` を実装してコーディネータからコールバック受け取り
- `handlePageReady()` 内で、ページの場所確認→リダイレクト判定→セッション確認→フェッチという複数ステップを実行
- リダイレクト回避ロジック（`lastRedirectAt`, `canRedirect()`）がViewModelに入っている

**本質**: `handlePageReady()` はコーディネータイベントハンドラであり、ここに「ユーザーが手動で使用量ページへ移動したい」「自動リダイレクトは5秒ごと」などのビジネスロジックが入るべきではない。

**あるべき姿**: PageReadyイベントハンドラーをPageReadyCoordinatorに分離。ViewModelはそこから通知を受け取り、状態更新のみ行う。リダイレクト判定・クールダウンは別のコーディネータが担当。

### 4. applyResult() が多数の副作用を実行

**現状**: Lines 252-272
```swift
func applyResult(_ result: UsageResult) {
    fiveHourPercent = result.fiveHourPercent
    sevenDayPercent = result.sevenDayPercent
    fiveHourResetsAt = result.fiveHourResetsAt
    sevenDayResetsAt = result.sevenDayResetsAt
    usageStore.save(result)                    // ストレージ
    alertChecker.checkAlerts(...)              // アラート
    reloadHistory()                            // UI更新
    snapshotWriter.saveAfterFetch(...)         // スナップショット
    widgetReloader.reloadAllTimelines()        // ウィジェット
    fetchPredict()                             // 予測取得
}
```

**本質**: 1つの結果に対して6つの異なるシステムに影響。責務が集中している。UI状態更新 vs 副作用の責務が混在。

**あるべき姿**:
- `applyResult()` はUI状態のみ更新
- 副作用（save, alerts, snapshots, widget reload）はPublisherパターンで処理。UsageStore.save()後に自動的にアラート・スナップショット・ウィジェット更新が続く構造に
- fetchPredict() は独立したタイミングで実行（fetch完了後の自動トリガーではなく、独立した定期タスク）

### 5. 初期化時に多数の非同期処理と副作用がある

**現状**: Lines 104-159
- コンフィグ生成（WKWebViewConfiguration）
- ストレージ初期化（設定読み込み）
- コーディネーター初期化
- SQLiteバックアップ実行
- 予測取得開始
- ログインアイテム同期
- クッキー観察開始
- Task内での非同期クッキー復元と初期フェッチ

**本質**: 初期化が順序敏感（クッキー復元→ページロード→ログイン確認→フェッチ）。副作用が多い。テスト困難。初期化失敗時の復旧ロジックが不明確。

**あるべき姿**: 初期化を段階化。初期化メソッドを分割（setupUI, setupStorage, startInitialSync）。各段階で失敗ハンドリング明確化。非同期初期化はStatePattern（initializing → ready → error）で管理。

## 推奨される分離

```
UsageViewModel (現在 325行 → 150行程度に削減)
├─ SessionCoordinator (クッキー, セッション復復)
├─ RefreshCoordinator (タイマー, 周期実行)
├─ PageReadyCoordinator (ページロード, リダイレクト判定)
├─ ResultProcessor (副作用パイプライン)
└─ InitializationCoordinator (段階化初期化)
```
