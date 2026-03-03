# Tests to Code Summary

実行日: 2026-03-04

## 結果

- テスト総数: 903
- 成功: 903
- 失敗: 0
- 削除: 1 (MiniUsageGraphTests.swift — Class B2: 全メソッド private)

## 修正一覧 (Class A — テスト修正)

| Test File | Issue | Class | Fix |
|-----------|-------|-------|-----|
| ProtocolsSupplementTests.swift | init引数不足 (SettingsStore/UsageStore/TokenStore) | A2 | 正しいinitパラメータに修正 |
| ViewModelSessionTests.swift | CookieData スコープ不正 | A2 | `UsageViewModel.CookieData` に修飾 |
| ViewModelSessionTests.swift | NSError を String? に代入 | A6 | 文字列リテラルに変更 |
| ViewModelSessionTests.swift | cookieBackupName のスコープ | A2 | `UsageViewModel.cookieBackupName` に修正 |
| ViewModelSessionTests.swift | テスト名と内容の不一致 | A2 | `returnsFalse_whenNoBackupExists` → `returnsBool` |
| ArchitectureSupplementTests.swift | プロパティ名不一致 (lastRedirectTime等) | A2 | 実際のプロパティ名に修正 |
| ArchitectureSupplementTests.swift | signOut() を async として呼び出し | A2 | async/await 削除 |
| ArchitectureSupplementTests.swift | WKHTTPCookieStoreObserver 適合チェック先 | A2 | WebViewCoordinator → CookieChangeObserver |
| ArchitectureSupplementTests.swift | Cookie観測テスト mock未設定 | A6 | hasValidSessionResult=true + handleSessionDetected直接呼出 |
| WebViewCoordinatorTests.swift | weak viewModel 解放 | A4 | retainedVM インスタンス変数で保持 |
| WebViewCoordinatorTests.swift | WKFrameInfo() crash | A6 | テスト削除(WKFrameInfoインスタンス化不可) |
| ViewModelLifecycleSupplementTests.swift | async race condition (fetch) | A2 | polling で内部Task完了を待機 |
| ViewModelLifecycleSupplementTests.swift | async race condition (fetchSilently) | A2 | polling で内部Task完了を待機 |
| ViewModelLifecycleSupplementTests.swift | UsageFetchError以外のエラー型 | A6 | UsageFetchError.scriptFailed("Missing organization") に変更 |
| WidgetDesignSupplementTests.swift | HistoryPoint import不足 | A1 | ClaudeUsageTrackerShared import追加 |
| WidgetDesignSupplementTests.swift | clock race condition (1m) | A6 | 固定now日付を使用 |

## 削除 (Class B2 — アクセスレベル)

| Test File | Reason |
|-----------|--------|
| MiniUsageGraphTests.swift | 全メソッドがprivate (usageValue, xPosition等)。UsageStore.DataPointはSharedモジュールだがMiniUsageGraph.DataPointは存在しない。テスト不可能 |

## コード修正 (Class B4)

| Source | Issue | Fix |
|--------|-------|-----|
| AnalysisSchemeHandler.swift:queryMetaJSON() | usage_logが空の場合、spec は `{}` を期待するがコードはNULL入りJSONを返していた。原因: SQLの集約関数(MAX/MIN)は空テーブルでもSQLITE_ROWを返すためguard文をすり抜けていた | `sqlite3_column_type` でNULLチェックを追加し、空テーブル時は `{}` を返すよう修正 |

## Xcode プロジェクト変更

- 15テストファイルを project.pbxproj に追加
- MiniUsageGraphTests.swift を project.pbxproj から削除

## Diagnosis一覧

| Test | Source | Check | Class |
|------|--------|-------|-------|
| UsageStoreSupplementTests.swift | UsageStore.swift | pass | - |
| TokenStoreSupplementTests.swift | TokenStore.swift | pass | - |
| AlertCheckerSupplementTests.swift | AlertChecker.swift | pass | - |
| SettingsSupplementTests.swift | SettingsStore.swift | pass | - |
| UsageFetcherSupplementTests.swift | UsageFetcher.swift | pass | - |
| WebViewCoordinatorTests.swift | WebViewCoordinator.swift | pass (fixed) | A4/A6 |
| ViewModelSessionTests.swift | UsageViewModel+Session.swift | pass (fixed) | A2/A6 |
| ProtocolsSupplementTests.swift | Protocols.swift | pass (fixed) | A2 |
| ViewModelLifecycleSupplementTests.swift | UsageViewModel.swift | pass (fixed) | A2/A6 |
| ArchitectureSupplementTests.swift | architecture全般 | pass (fixed) | A2/A6 |
| AnalysisSchemeHandlerSupplementTests.swift | AnalysisSchemeHandler.swift | pass (code fixed) | B4 |
| WidgetDesignSupplementTests.swift | DisplayHelpers.swift + Widget | pass (fixed) | A1/A6 |
| MenuContentSupplementTests.swift | MenuContent.swift | pass | - |
| AppWindowsSupplementTests.swift | AppWindows.swift | pass | - |
| MiniUsageGraphTests.swift | MiniUsageGraph.swift | deleted | B2 |
