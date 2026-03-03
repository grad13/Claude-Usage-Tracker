# Spec to Tests Summary

実行日: 2026-03-03

## 統計

| 項目 | 件数 |
|------|------|
| 対象spec | 18 |
| covered（スキップ） | 3 |
| partial（追記生成） | 12 |
| missing（新規生成） | 3 |
| 生成test files | 15 |
| 生成test cases | 326 |

## Test一覧

| Test | Spec | Source | Check | Action |
|------|------|--------|-------|--------|
| ClaudeUsageTrackerTests/WebViewCoordinatorTests.swift | spec/meta/webview-coordinator.md | code/ClaudeUsageTracker/WebViewCoordinator.swift | missing | generated |
| ClaudeUsageTrackerTests/ViewModelSessionTests.swift | spec/meta/viewmodel-session.md | code/ClaudeUsageTracker/UsageViewModel+Session.swift | missing | generated |
| ClaudeUsageTrackerTests/MiniUsageGraphTests.swift | spec/ui/mini-usage-graph.md | code/ClaudeUsageTracker/MiniUsageGraph.swift | missing | generated |
| ClaudeUsageTrackerTests/UsageStoreSupplementTests.swift | spec/data/usage-store.md | code/ClaudeUsageTracker/UsageStore.swift | partial | generated |
| ClaudeUsageTrackerTests/TokenStoreSupplementTests.swift | spec/data/token-store.md | code/ClaudeUsageTracker/TokenStore.swift | partial | generated |
| ClaudeUsageTrackerTests/AlertCheckerSupplementTests.swift | spec/data/alert.md | code/ClaudeUsageTracker/AlertChecker.swift | partial | generated |
| ClaudeUsageTrackerTests/SettingsSupplementTests.swift | spec/data/settings.md | code/ClaudeUsageTracker/Settings.swift | partial | generated |
| ClaudeUsageTrackerTests/UsageFetcherSupplementTests.swift | spec/data/usage-fetcher.md | code/ClaudeUsageTracker/UsageFetcher.swift | partial | generated |
| ClaudeUsageTrackerTests/ProtocolsSupplementTests.swift | spec/meta/protocols.md | code/ClaudeUsageTracker/Protocols.swift | partial | generated |
| ClaudeUsageTrackerTests/ViewModelLifecycleSupplementTests.swift | spec/meta/viewmodel-lifecycle.md | code/ClaudeUsageTracker/UsageViewModel.swift | partial | generated |
| ClaudeUsageTrackerTests/ArchitectureSupplementTests.swift | spec/meta/architecture.md | code/ClaudeUsageTracker/ (multiple) | partial | generated |
| ClaudeUsageTrackerTests/AnalysisSchemeHandlerSupplementTests.swift | spec/analysis/analysis-scheme-handler.md | code/ClaudeUsageTracker/AnalysisSchemeHandler.swift | partial | generated |
| ClaudeUsageTrackerTests/WidgetDesignSupplementTests.swift | spec/widget/design.md | code/ClaudeUsageTrackerWidget/ (multiple) | partial | generated |
| ClaudeUsageTrackerTests/MenuContentSupplementTests.swift | spec/ui/menu-content.md | code/ClaudeUsageTracker/MenuContent.swift | partial | generated |
| ClaudeUsageTrackerTests/AppWindowsSupplementTests.swift | spec/ui/app-windows.md | code/ClaudeUsageTracker/ClaudeUsageTrackerApp.swift | partial | generated |
| ClaudeUsageTrackerTests/UsageStoreTests.swift | spec/data/usage-store.md | code/ClaudeUsageTracker/UsageStore.swift | partial | - |
| ClaudeUsageTrackerTests/FetcherTests.swift | spec/data/usage-fetcher.md | code/ClaudeUsageTracker/UsageFetcher.swift | partial | - |
| ClaudeUsageTrackerTests/TokenStoreTests.swift | spec/data/token-store.md | code/ClaudeUsageTracker/TokenStore.swift | partial | - |
| ClaudeUsageTrackerTests/SettingsTests.swift | spec/data/settings.md | code/ClaudeUsageTracker/Settings.swift | partial | - |
| ClaudeUsageTrackerTests/SettingsStoreTests.swift | spec/data/settings.md | code/ClaudeUsageTracker/Settings.swift | partial | - |
| ClaudeUsageTrackerTests/ViewModelTests+Settings.swift | spec/data/settings.md | code/ClaudeUsageTracker/UsageViewModel+Settings.swift | partial | - |
| ClaudeUsageTrackerTests/AlertCheckerTests.swift | spec/data/alert.md | code/ClaudeUsageTracker/AlertChecker.swift | partial | - |
| ClaudeUsageTrackerTests/ViewModelTests.swift | spec/meta/viewmodel-lifecycle.md | code/ClaudeUsageTracker/UsageViewModel.swift | partial | - |
| ClaudeUsageTrackerTests/ViewModelTests+Fetch.swift | spec/meta/viewmodel-lifecycle.md | code/ClaudeUsageTracker/UsageViewModel.swift | partial | - |
| ClaudeUsageTrackerTests/AnalysisSchemeHandlerTests.swift | spec/analysis/analysis-scheme-handler.md | code/ClaudeUsageTracker/AnalysisSchemeHandler.swift | partial | - |
| ClaudeUsageTrackerTests/SnapshotStoreTests.swift | spec/widget/design.md | code/ClaudeUsageTrackerShared/SnapshotStore.swift | partial | - |
| ClaudeUsageTrackerTests/SnapshotModelTests.swift | spec/widget/design.md | code/ClaudeUsageTrackerShared/SnapshotModels.swift | partial | - |
| ClaudeUsageTrackerTests/DisplayHelpersTests.swift | spec/widget/design.md | code/ClaudeUsageTrackerShared/DisplayHelpers.swift | partial | - |
| - | spec/predict/jsonl-cost.md | code/ClaudeUsageTracker/JSONLParser.swift + CostEstimator.swift | covered | - |
| - | spec/analysis/overview.md | code/ClaudeUsageTracker/AnalysisExporter.swift | covered | - |
| - | spec/analysis/analysis-exporter.md | code/ClaudeUsageTracker/AnalysisExporter.swift | covered | - |

## 新規test（missing → generated）

| File | Cases | 内容 |
|------|-------|------|
| WebViewCoordinatorTests.swift | 13 | CookieChangeObserver callback、WKNavigationDelegate/WKUIDelegate conformance、createWebViewWith popup、webViewDidClose |
| ViewModelSessionTests.swift | 30 | handleSessionDetected、CookieData Codable、Login Polling timer、checkPopupLogin/handlePopupClosed timing、signOut state reset |
| MiniUsageGraphTests.swift | 22 | usageValue windowSeconds切替、xPosition座標正規化、windowStart優先度、backgroundColor、yFrac線形マッピング |

## 追記用test（partial → generated）

| File | Cases | 内容 |
|------|-------|------|
| UsageStoreSupplementTests.swift | 8 | loadDailyUsage: セッション境界合算、<2件nil、マイナス値0扱い |
| TokenStoreSupplementTests.swift | 9 | shared singleton初期化、.jsonlフィルタ、loadRecords境界、NULL/invalidスキップ |
| AlertCheckerSupplementTests.swift | 8 | DA-07 calendar再通知、DU-01-05 Daily Usage計算、NI-02-03 identifier共存 |
| SettingsSupplementTests.swift | 7 | 7つのalert setter（weekly/hourly/daily enabled/threshold + dailyDefinition） |
| UsageFetcherSupplementTests.swift | 30 | isAuthError/parseStatus/calcPercent/parseResetsAt エッジケース、parse統合テスト |
| ProtocolsSupplementTests.swift | 10 | SettingsStoring/UsageStoring/TokenSyncing conformance検証 |
| ViewModelLifecycleSupplementTests.swift | 9 | startAutoRefresh二重起動防止、restartAutoRefreshタイマー差替、fetchSilently vs fetch差分 |
| ArchitectureSupplementTests.swift | 20 | DataStore永続化、delegate設定、autoRefresh 3状態、5秒クールダウン、signOutリセット |
| AnalysisSchemeHandlerSupplementTests.swift | 16 | queryMetaJSON 5パス、Query parameter filtering、helper単体、エラーheader |
| WidgetDesignSupplementTests.swift | 77 | UsageEntry/TimelineProvider、座標計算、マーカー配置、Large/Small View引数マッピング |
| MenuContentSupplementTests.swift | 53 | 表示条件(nil-conditional)、%.1f format、プリセット値、alert gating、ChartColorPreset |
| AppWindowsSupplementTests.swift | 14 | graphCount計算、fallback NSImage 80x18、Retina scale 2.0 |
