# refactor-code Summary

**Date**: 2026-03-04
**Target**: code/ (全35ファイル、サンプリングなし)
**Result**: must: 0 / should: 13 / clean: 22

## should (13 files)

| Lines | File | Issues |
|------:|------|--------|
| 398 | ClaudeUsageTrackerShared/SnapshotStore.swift | SQLite3 API直接露出、エラーハンドリング欠陥、責務過集約 |
| 327 | ClaudeUsageTracker/UsageFetcher.swift | 複数責務混在（OrgID/API/JSON解析）、4段階フォールバック |
| 324 | ClaudeUsageTracker/UsageViewModel.swift | Cookie/Session管理混在、applyResult()の副作用過多、init()の複雑さ |
| 305 | ClaudeUsageTracker/UsageStore.swift | 複数責務混在（DataAccess/Session/Normalization）、SQLインジェクション脆弱性 |
| 305 | ClaudeUsageTracker/TokenStore.swift | sync()内の責務混在、エラーハンドリング不統一、ステートメント結果チェック不足 |
| 234 | ClaudeUsageTracker/AnalysisSchemeHandler.swift | SchemeHandler+SQLiteクエリ混在、Silent Fallback、クエリコード重複 |
| 232 | ClaudeUsageTracker/MenuContent.swift | 宣言的UI+命令型ダイアログ混在、プリセット値ハードコード |
| 194 | ClaudeUsageTrackerWidget/WidgetMiniGraph.swift | guard段階的フォールバック、タプル戻り値型、ハードコード定数 |
| 183 | ClaudeUsageTracker/Settings.swift | AppSettingsに検証ロジック混在、デフォルト値の重複生成 |
| 137 | ClaudeUsageTracker/JSONLParser.swift | 解析と重複排除の密結合、サイレント失敗、脆弱なJSON抽出 |
| 132 | ClaudeUsageTracker/AlertChecker.swift | 3アラートメソッドのコード重複、不要なフォールバックラッパー |
| 87 | ClaudeUsageTrackerShared/SQLiteBackup.swift | WAL checkpointエラー無視、DateFormatter毎回生成、force unwrap |
| 36 | ClaudeUsageTracker/ClaudeUsageTrackerApp.swift | AppDelegate+App混在、ハードコードウィンドウサイズ |

## clean (22 files)

| Lines | File |
|------:|------|
| 201 | ClaudeUsageTracker/UsageViewModel+Session.swift |
| 160 | ClaudeUsageTracker/Protocols.swift |
| 149 | ClaudeUsageTracker/MiniUsageGraph.swift |
| 117 | ClaudeUsageTrackerWidget/WidgetLargeView.swift |
| 103 | ClaudeUsageTracker/CostEstimator.swift |
| 96 | ClaudeUsageTracker/UsageViewModel+Settings.swift |
| 94 | ClaudeUsageTrackerWidget/WidgetMediumView.swift |
| 75 | ClaudeUsageTracker/MenuBarLabel.swift |
| 75 | ClaudeUsageTracker/WebViewCoordinator.swift |
| 73 | ClaudeUsageTrackerWidget/WidgetSmallView.swift |
| 66 | ClaudeUsageTrackerWidget/UsageWidget.swift |
| 64 | ClaudeUsageTrackerShared/SnapshotModels.swift |
| 62 | ClaudeUsageTracker/LoginWindowView.swift |
| 49 | ClaudeUsageTracker/UsageViewModel+Predict.swift |
| 48 | ClaudeUsageTrackerShared/DisplayHelpers.swift |
| 41 | ClaudeUsageTracker/NotificationManager.swift |
| 31 | ClaudeUsageTrackerShared/AppGroupConfig.swift |
| 31 | ClaudeUsageTracker/AnalysisWindowView.swift |
| 18 | ClaudeUsageTracker/AnalysisExporter.swift |
| 15 | ClaudeUsageTracker/LoginWebView.swift |
| 10 | ClaudeUsageTrackerWidget/ClaudeUsageTrackerWidgetBundle.swift |
| 9 | ClaudeUsageTrackerShared/ClaudeUsageTrackerShared.swift |
