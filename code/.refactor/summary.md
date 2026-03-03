# Refactor Analysis Summary

**Date**: 2026-03-03
**Scope**: 全コード（code/ 配下）
**Analyzed**: 20 / 33 files（priority -1 の未チェックファイルから行数上位20件）
**Excluded**: ClaudeUsageTrackerShared.swift (9行, priority -1 で21番目)

## Results

| Judgment | Count | Files |
|----------|-------|-------|
| **must** | 0 | — |
| **should** | 3 | 詳細は `.refactor/should/` 配下 |
| **clean** | 17 | 下記一覧 |

## should (3 files)

### 1. ClaudeUsageTracker/UsageStore.swift (309行)
- DB接続ボイラープレートの重複（全4メソッドで open/close）
- loadAllHistory と loadHistory でデータ取得範囲が不整合
- printベースのサイレント失敗

→ 詳細: `.refactor/should/ClaudeUsageTracker/UsageStore.swift.md`

### 2. ClaudeUsageTracker/TokenStore.swift (280行)
- DBスキーマと TokenRecord モデルの不一致（speed, webSearchRequests がハードコード）
- sync メソッド内のファイルスキャン責務の混在

→ 詳細: `.refactor/should/ClaudeUsageTracker/TokenStore.swift.md`

### 3. ClaudeUsageTrackerWidget/WidgetMediumView.swift (263行)
- WidgetMiniGraph が同一ファイルに同居（165行、ファイルの62%）
- Canvas 描画ロジックが150行のフラットなコード

→ 詳細: `.refactor/should/ClaudeUsageTrackerWidget/WidgetMediumView.swift.md`

## clean (17 files)

| File | Lines |
|------|-------|
| ClaudeUsageTrackerShared/SnapshotStore.swift | 398 |
| ClaudeUsageTracker/AnalysisSchemeHandler.swift | 224 |
| ClaudeUsageTracker/Settings.swift | 183 |
| ClaudeUsageTracker/Protocols.swift | 146 |
| ClaudeUsageTracker/JSONLParser.swift | 137 |
| ClaudeUsageTracker/AlertChecker.swift | 132 |
| ClaudeUsageTrackerWidget/WidgetLargeView.swift | 117 |
| ClaudeUsageTracker/CostEstimator.swift | 103 |
| ClaudeUsageTrackerShared/SQLiteBackup.swift | 87 |
| ClaudeUsageTrackerWidget/WidgetSmallView.swift | 73 |
| ClaudeUsageTrackerWidget/UsageWidget.swift | 66 |
| ClaudeUsageTrackerShared/SnapshotModels.swift | 64 |
| ClaudeUsageTrackerShared/DisplayHelpers.swift | 47 |
| ClaudeUsageTracker/NotificationManager.swift | 41 |
| ClaudeUsageTrackerShared/AppGroupConfig.swift | 31 |
| ClaudeUsageTracker/LoginWebView.swift | 15 |
| ClaudeUsageTrackerWidget/ClaudeUsageTrackerWidgetBundle.swift | 10 |

## Not Analyzed (13 files — already checked or lower priority)

| File | Lines | Priority |
|------|-------|----------|
| ClaudeUsageTracker/UsageFetcher.swift | 327 | 2 |
| ClaudeUsageTracker/UsageViewModel.swift | 324 | 1 |
| ClaudeUsageTracker/MenuContent.swift | 232 | 1 |
| ClaudeUsageTracker/UsageViewModel+Session.swift | 201 | 0 |
| ClaudeUsageTracker/MiniUsageGraph.swift | 149 | 0 |
| ClaudeUsageTracker/UsageViewModel+Settings.swift | 96 | 1 |
| ClaudeUsageTracker/MenuBarLabel.swift | 75 | 0 |
| ClaudeUsageTracker/WebViewCoordinator.swift | 75 | 0 |
| ClaudeUsageTracker/LoginWindowView.swift | 62 | 0 |
| ClaudeUsageTracker/UsageViewModel+Predict.swift | 49 | 0 |
| ClaudeUsageTracker/ClaudeUsageTrackerApp.swift | 36 | 0 |
| ClaudeUsageTracker/AnalysisWindowView.swift | 31 | 0 |
| ClaudeUsageTracker/AnalysisExporter.swift | 18 | 0 |
