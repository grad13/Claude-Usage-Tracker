# Tests to Code Summary

実行日: 2026-03-06

## 実行結果

| 項目 | 値 |
|------|-----|
| テスト総数 | 584 |
| 成功 | 584 |
| 失敗 | 0 |

## Diagnosis一覧

| Test | Source | Check | Class |
|------|--------|-------|-------|
| data/AlertCheckerTests.swift | AlertChecker.swift | pass | - |
| data/AlertCheckerSupplementTests.swift | AlertChecker.swift | pass | - |
| data/FetcherTests.swift | UsageFetcher.swift | pass | - |
| data/NotificationManagerTests.swift | NotificationManager.swift | pass | - |
| data/ProductionSettingsIntegrityTests.swift | Settings.swift | pass | - |
| data/SettingsStoreTests.swift | Settings.swift | pass | - |
| data/SettingsSupplementTests.swift | Settings.swift | pass | - |
| data/SettingsTests.swift | Settings.swift | pass | - |
| data/UsageFetchErrorTests.swift | UsageModels.swift | pass | - |
| data/UsageFetcherSupplementTests.swift | UsageFetcher.swift | pass | - |
| data/UsageStoreSupplementTests.swift | UsageStore.swift | pass | - |
| data/UsageStoreTests.swift | UsageStore.swift | pass | - |
| data/SettingsPresetsTests.swift | Settings.swift | pass | - |
| data/ChartColorPresetTests.swift | Settings.swift | pass | - |
| data/DailyAlertDefinitionTests.swift | Settings.swift | pass | - |
| meta/ArchitectureViewModelStateTests.swift | UsageViewModel.swift | pass | - |
| meta/ArchitectureWebViewStructureTests.swift | UsageViewModel.swift | pass | - |
| meta/ViewModelTests+Settings.swift | UsageViewModel+Settings.swift | pass | - |
| meta/WebViewCoordinatorTests.swift | WebViewCoordinator.swift | pass | - |
| meta/WebViewCoordinatorSupplementTests.swift | WebViewCoordinator.swift | pass | - |
| meta/ProtocolsSupplementTests.swift | Protocols.swift | pass | - |
| meta/ProtocolsSupplementTests2.swift | Protocols.swift | pass | - |
| meta/ProtocolsSupplementTests3.swift | Protocols.swift | pass | - |
| meta/ViewModelLifecycleSupplementTests.swift | UsageViewModel.swift | pass | - |
| meta/ViewModelSessionTests.swift | UsageViewModel+Session.swift | pass | - |
| meta/ViewModelTests.swift | UsageViewModel.swift | pass | - |
| meta/ViewModelTests+Fetch.swift | UsageViewModel.swift | pass | - |
| shared/SQLiteBackupTests.swift | SQLiteBackup.swift | pass | - |
| shared/SQLiteHelperTests.swift | SQLiteHelper.swift | pass | - |
| shared/AppGroupConfigTests.swift | AppGroupConfig.swift | pass | - |
| shared/DisplayHelpersTests.swift | DisplayHelpers.swift | pass | - |
| shared/DisplayHelpersMarkerTests.swift | DisplayHelpers.swift | pass | - |
| shared/SnapshotModelTests.swift | SnapshotModels.swift | pass | - |
| ui/AppWindowsSupplementTests.swift | MenuBarLabel.swift | fail | C1 |
| ui/MiniUsageGraphLogicTests.swift | MiniUsageGraph.swift | pass | - |
| ui/MenuContentSupplementTests.swift | MenuContent.swift | pass | - |
| analysis/AnalysisSQLQueryTests.swift | AnalysisSchemeHandler.swift | pass | - |
| analysis/AnalysisSchemeHandlerHelperTests.swift | AnalysisSchemeHandler.swift | pass | - |
| analysis/AnalysisSchemeHandlerMetaJSONTests.swift | AnalysisSchemeHandler.swift | pass | - |
| analysis/AnalysisSchemeHandlerQueryFilterTests.swift | AnalysisSchemeHandler.swift | pass | - |
| analysis/AnalysisSchemeHandlerSQLiteTests.swift | AnalysisSchemeHandler.swift | pass | - |
| analysis/AnalysisSchemeHandlerTests.swift | AnalysisSchemeHandler.swift | pass | - |
| analysis/AnalysisWebViewIntegrationTests.swift | AnalysisSchemeHandler.swift | pass | - |
| analysis/AnalysisExporterTests.swift | AnalysisExporter.swift | pass | - |
| analysis/AnalysisSchemeHandlerMetaJSONSupplementTests.swift | AnalysisSchemeHandler.swift | pass | - |
| analysis/AnalysisExporterJSLogicTests.swift | AnalysisExporter.swift | pass | - |
| analysis/AnalysisSchemeHandlerSupplementTests2.swift | AnalysisSchemeHandler.swift | pass | - |
| widget/WidgetDisplayFormatTests.swift | WidgetLargeView.swift | fail | C1 |
| widget/WidgetMediumViewNowXTests.swift | WidgetMediumView.swift | fail | C1 |
| widget/WidgetMiniGraphCalcTests.swift | WidgetMiniGraph.swift | fail | C1 |

## C1問題の詳細

4件のC1（自己充足テスト）が検出された。いずれもソースの `private` メソッドのロジックをテスト内で再実装している。

### ui/AppWindowsSupplementTests.swift
- `graphCount` 計算式 `(showHourlyGraph ? 1 : 0) + (showWeeklyGraph ? 1 : 0)` を再実装
- Retina スケーリング `CGFloat(cgImage.width) / 2.0` を再実装
- フォールバックサイズ `NSSize(width: 80, height: 18)` を定数として再実装

### widget/WidgetDisplayFormatTests.swift
- `specLargeRemainingText` が `WidgetLargeView.remainingText` のロジックを再実装

### widget/WidgetMediumViewNowXTests.swift
- `specNowXFraction` が `WidgetMediumView.nowXFraction` の計算を再実装

### widget/WidgetMiniGraphCalcTests.swift
- `specResolveWindowStart` が `WidgetMiniGraph.resolveWindowStart` を再実装
- `specBuildPoints` が `WidgetMiniGraph.buildPoints` を再実装
- `specTickDivisions` が `WidgetMiniGraph.drawTicks` の分割数ロジックを再実装

## 根本原因

テスト対象のメソッドが全て `private` であるため、テストから直接呼び出せない。
spec-to-tests で生成された際にロジックをテスト内に複製して検証する形になった。

## 推奨アクション

C1問題はテストの修正が必要だが、対象メソッドが `private` であるため2つの選択肢がある:

1. **ソースのアクセスレベルを変更**: `private` → `internal` にしてテストから `@testable import` で呼べるようにする
2. **テストを公開IFからの間接テストに書き換え**: private メソッドの結果を公開IFの出力で検証する

選択肢1が最小変更。選択肢2はより正しいが大規模な書き換えが必要。
