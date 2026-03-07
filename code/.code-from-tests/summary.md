# Tests to Code Summary

実行日: 2026-03-07

## 実行結果

- テスト実行: 805 tests, 0 failures
- 静的分析: 64 test files analyzed (2 helpers excluded)
- クラスA/B問題: なし（全テスト成功）
- クラスC問題: C1 × 2件（自己充足テスト）

## Diagnosis一覧

| Test | Source | Check | Class |
|------|--------|-------|-------|
| data/AlertCheckerTests.swift | AlertChecker.swift | pass | - |
| data/AlertCheckerSupplementTests.swift | AlertChecker.swift | pass | - |
| data/NotificationManagerTests.swift | NotificationManager.swift | pass | - |
| data/ProductionSettingsIntegrityTests.swift | Settings.swift | pass | - |
| data/SettingsStoreTests.swift | Settings.swift | pass | - |
| data/SettingsSupplementTests.swift | Settings.swift | pass | - |
| data/SettingsSupplementTests2.swift | Settings.swift | pass | - |
| data/SettingsTests.swift | Settings.swift | pass | - |
| data/SettingsPresetsTests.swift | Settings.swift | pass | - |
| data/ChartColorPresetTests.swift | Settings.swift | pass | - |
| data/DailyAlertDefinitionTests.swift | Settings.swift | pass | - |
| data/UsageFetchErrorTests.swift | UsageFetcher.swift | pass | - |
| data/UsageStoreTests.swift | UsageStore.swift | pass | - |
| data/UsageStoreSupplementTests.swift | UsageStore.swift | pass | - |
| data/UsageStoreSupplementTests2.swift | UsageStore.swift | pass | - |
| data/FetcherTests.swift | UsageFetcher.swift | pass | - |
| data/UsageFetcherSupplementTests.swift | UsageFetcher.swift | pass | - |
| meta/ViewModelTests.swift | UsageViewModel.swift | pass | - |
| meta/ViewModelTests+Settings.swift | UsageViewModel+Settings.swift | pass | - |
| meta/ViewModelTests+Fetch.swift | UsageViewModel.swift | pass | - |
| meta/ViewModelTests+StatusText.swift | UsageViewModel.swift | pass | - |
| meta/ViewModelTests+TimeProgress.swift | UsageViewModel.swift | pass | - |
| meta/ViewModelSessionTests.swift | UsageViewModel+Session.swift | pass | - |
| meta/ViewModelSessionSupplementTests.swift | UsageViewModel+Session.swift | pass | - |
| meta/ViewModelLifecycleSupplementTests.swift | UsageViewModel.swift | pass | - |
| meta/ViewModelFetchSilentlyTests.swift | UsageViewModel.swift | pass | - |
| meta/ViewModelSettingsWidgetReloaderTests.swift | UsageViewModel+Settings.swift | pass | - |
| meta/ViewModelHandlePageReadyTests.swift | UsageViewModel.swift | pass | - |
| meta/ArchitectureViewModelStateTests.swift | UsageViewModel.swift | pass | - |
| meta/ArchitectureWebViewStructureTests.swift | WebViewCoordinator.swift | pass | - |
| meta/ArchitectureSupplementTests.swift | UsageViewModel+Protocols.swift | pass | - |
| meta/ProtocolsSupplementTests.swift | Protocols.swift | pass | - |
| meta/ProtocolsSupplementTests2.swift | Protocols.swift | pass | - |
| meta/ProtocolsSupplementTests3.swift | Protocols.swift | pass | - |
| meta/WebViewCoordinatorTests.swift | WebViewCoordinator.swift | pass | - |
| meta/WebViewCoordinatorSupplementTests.swift | WebViewCoordinator.swift | pass | - |
| shared/SQLiteBackupTests.swift | SQLiteBackup.swift | pass | - |
| shared/SQLiteHelperTests.swift | SQLiteHelper.swift | pass | - |
| shared/AppGroupConfigTests.swift | AppGroupConfig.swift | pass | - |
| shared/DisplayHelpersTests.swift | DisplayHelpers.swift | pass | - |
| shared/DisplayHelpersMarkerTests.swift | DisplayHelpers.swift | pass | - |
| shared/SnapshotModelTests.swift | SnapshotModels.swift | pass | - |
| analysis/AnalysisSQLQueryTests.swift | AnalysisSchemeHandler.swift | pass | - |
| analysis/AnalysisSchemeHandlerTests.swift | AnalysisSchemeHandler.swift | pass | - |
| analysis/AnalysisSchemeHandlerQueryFilterTests.swift | AnalysisSchemeHandler.swift | pass | - |
| analysis/AnalysisSchemeHandlerSQLiteTests.swift | AnalysisSchemeHandler.swift | pass | - |
| analysis/AnalysisSchemeHandlerSupplementTests2.swift | AnalysisSchemeHandler.swift | pass | - |
| analysis/AnalysisSchemeHandlerMetaJSONTests.swift | AnalysisSchemeHandler.swift | pass | - |
| analysis/AnalysisSchemeHandlerMetaJSONSupplementTests.swift | AnalysisSchemeHandler.swift | pass | - |
| analysis/AnalysisSchemeHandlerSettingsTests.swift | AnalysisSchemeHandler.swift | pass | - |
| analysis/AnalysisSchemeHandlerHelperTests.swift | AnalysisSchemeHandler.swift | pass | - |
| analysis/AnalysisWebViewIntegrationTests.swift | AnalysisWindowView.swift | pass | - |
| analysis/AnalysisExporterTests.swift | AnalysisExporter.swift | pass | - |
| analysis/AnalysisExporterJSLogicTests.swift | AnalysisExporter.swift | pass | - |
| analysis/AnalysisExporterSupplementTests.swift | AnalysisExporter.swift | pass | - |
| ui/MenuContentSupplementTests.swift | MenuContent.swift | pass | - |
| ui/MenuContentSupplementTests2.swift | MenuContent.swift | pass | - |
| ui/AppWindowsSupplementTests.swift | ClaudeUsageTrackerApp.swift | pass | - |
| ui/AppWindowsSupplementTests2.swift | ClaudeUsageTrackerApp.swift | pass | - |
| ui/MiniUsageGraphLogicTests.swift | MiniUsageGraph.swift | pass | - |
| ui/MiniUsageGraphSupplementTests.swift | MiniUsageGraph.swift | fail | C1 |
| widget/WidgetMediumViewNowXTests.swift | WidgetMediumView.swift | pass | - |
| widget/WidgetDisplayFormatTests.swift | DisplayHelpers.swift | pass | - |
| widget/WidgetMiniGraphCalcTests.swift | GraphCalc.swift | pass | - |
| widget/WidgetDesignSupplementTests.swift | WidgetColorThemeResolver.swift | fail | C1 |

## C1問題の詳細

### C1-1: MiniUsageGraphSupplementTests.swift (line 194)

- **What**: `yFrac(usage:)` ヘルパーが `min(usage / 100.0, 1.0)` を再実装
- **Why**: ソースの formula は Canvas クロージャ内のインライン計算（MiniUsageGraph.swift:90）で、外部から呼び出せない
- **対処案**: ソースから formula を static メソッドに抽出し、テストがそれを呼ぶように修正

### C1-2: WidgetDesignSupplementTests.swift (line 107)

- **What**: `specResolve()` が `WidgetColorThemeResolver.resolve()` の決定テーブルを再実装。`testAreaOpacityValues_matchSpec()` はリテラル値の自己比較（トートロジー）
- **Why**: Widget ターゲットがテストターゲットからインポート不可
- **対処案**: `WidgetColorThemeResolver` を Shared ターゲットに移動、または spec ベーステストとして許容
