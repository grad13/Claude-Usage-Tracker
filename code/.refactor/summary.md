# Refactor Analysis Summary

Date: 2026-03-07
Analyzed: 20 / 36 files

## Results

| Judgment | Count | Files |
|----------|-------|-------|
| must     | 0     | -     |
| should   | 3     | see below |
| clean    | 17    | see below |

## should (推奨対象)

### 1. ClaudeUsageTracker/UsageFetcher.swift (282 lines)
- org ID 取得ロジックが Swift 側と JS 側で重複
- `readOrgId` が未使用の可能性（`fetch()` は JS 内の4段階フォールバックを直接使用）
- `parseUnixTimestamp` と `parseResetsAt` の機能重複
- **詳細**: `.refactor/should/ClaudeUsageTracker/UsageFetcher.swift.md`

### 2. ClaudeUsageTracker/UsageViewModel.swift (317 lines)
- WebView 初期化・設定が ViewModel 内に埋め込み（テスト困難）
- ナビゲーション制御とリダイレクトスロットリングの混在
- リトライロジックが fetchSilently 内にインライン展開
- **詳細**: `.refactor/should/ClaudeUsageTracker/UsageViewModel.swift.md`

### 3. ClaudeUsageTracker/UsageViewModel+Session.swift (201 lines)
- Login Polling が Timer ベースの fallback（SPA 遷移補償）
- Cookie Backup/Restore のファイルパス構築がインライン
- **詳細**: `.refactor/should/ClaudeUsageTracker/UsageViewModel+Session.swift.md`

## clean (問題なし)

| File | Lines |
|------|-------|
| ClaudeUsageTracker/MenuBarLabel.swift | 83 |
| ClaudeUsageTracker/UsageViewModel+Settings.swift | 104 |
| ClaudeUsageTracker/MiniUsageGraph.swift | 165 |
| ClaudeUsageTracker/MenuContent.swift | 241 |
| ClaudeUsageTracker/Settings.swift | 242 |
| ClaudeUsageTracker/UsageStore.swift | 322 |
| ClaudeUsageTracker/AlertChecker.swift | 132 |
| ClaudeUsageTracker/ClaudeUsageTrackerApp.swift | 36 |
| ClaudeUsageTracker/AnalysisSchemeHandler.swift | 202 |
| ClaudeUsageTrackerWidget/WidgetMediumView.swift | 105 |
| ClaudeUsageTrackerWidget/WidgetMiniGraph.swift | 231 |
| ClaudeUsageTrackerWidget/WidgetLargeView.swift | 121 |
| ClaudeUsageTrackerWidget/WidgetSmallView.swift | 86 |
| ClaudeUsageTrackerShared/AppGroupConfig.swift | 36 |
| ClaudeUsageTrackerShared/GraphCalc.swift | 60 |
| ClaudeUsageTrackerShared/SQLiteBackup.swift | 92 |
| ClaudeUsageTrackerShared/DisplayHelpers.swift | 43 |
| ClaudeUsageTrackerShared/SQLiteHelper.swift | 111 |

## Not Analyzed (16 files)

Priority が低く今回の対象外。次回以降に分析。
