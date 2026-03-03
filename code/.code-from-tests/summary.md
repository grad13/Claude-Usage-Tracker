# Tests to Code Summary

実行日: 2026-03-04（第2回）

## テスト実行結果

| 項目 | 値 |
|------|-----|
| テスト数 | 905 |
| 成功 | 905 |
| 失敗 | 0 |

## Diagnosis一覧

| Test | Source | Check | Class |
|------|--------|-------|-------|
| AnalysisExporterTests.swift | AnalysisExporter.swift | pass | - |
| AnalysisWebViewIntegrationTests.swift | AnalysisSchemeHandler.swift | pass | - |
| AnalysisJSLogicTests.swift | analysis.html | pass | - |
| **AnalysisJSExtendedTests.swift** | analysis.html | **fail** | **C1** |
| AnalysisTemplateJSTests.swift | analysis.html, CostEstimator.swift | pass | - |
| AnalysisTemplateRenderTests.swift | analysis.html | pass | - |
| AnalysisBugHuntingTests.swift | analysis.html | pass | - |
| AnalysisSchemeHandlerMetaJSONTests.swift | AnalysisSchemeHandler.swift | pass | - |
| AnalysisSchemeHandlerQueryFilterTests.swift | AnalysisSchemeHandler.swift | pass | - |
| AnalysisSchemeHandlerHelperTests.swift | AnalysisSchemeHandler.swift | pass | - |
| AnalysisSchemeHandlerSQLiteTests.swift | AnalysisSchemeHandler.swift | pass | - |
| AnalysisSchemeHandlerTests.swift | AnalysisSchemeHandler.swift | pass | - |
| **AnalysisSQLQueryTests.swift** | AnalysisSchemeHandler.swift | **fail** | **C1 (borderline)** |
| ViewModelTests.swift | UsageViewModel.swift | pass | - |
| **ViewModelTests+Fetch.swift** | UsageViewModel.swift | **fail** | **C1** |
| ViewModelTests+Settings.swift | UsageViewModel+Settings.swift | pass | - |
| ViewModelSessionTests.swift | UsageViewModel+Session.swift | pass | - |
| ViewModelLifecycleSupplementTests.swift | UsageViewModel.swift | pass | - |
| ArchitectureViewModelStateTests.swift | UsageViewModel.swift | pass | - |
| FetcherTests.swift | UsageFetcher.swift | pass | - |
| SettingsTests.swift | Settings.swift | pass | - |
| SettingsStoreTests.swift | Settings.swift | pass | - |
| SettingsSupplementTests.swift | UsageViewModel+Settings.swift | pass | - |
| ProductionSettingsIntegrityTests.swift | Settings.swift, AppGroupConfig.swift | pass | - |
| UsageStoreTests.swift | UsageStore.swift | pass | - |
| UsageStoreSupplementTests.swift | UsageStore.swift | pass | - |
| TokenStoreTests.swift | TokenStore.swift | pass | - |
| TokenStoreSupplementTests.swift | TokenStore.swift | pass | - |
| **SQLiteBackupTests.swift** | SQLiteBackup.swift | **fail** | **C1 (minor)** |
| SnapshotModelTests.swift | SnapshotModels.swift | pass | - |
| SnapshotStoreTests.swift | SnapshotStore.swift | pass | - |
| CostEstimatorTests.swift | CostEstimator.swift | pass | - |
| CostEstimatorParityTests.swift | CostEstimator.swift | pass | - |
| JSONLParserTests.swift | JSONLParser.swift | pass | - |
| **WidgetMiniGraphCalcTests.swift** | WidgetMiniGraph.swift, DisplayHelpers.swift | **fail** | **C1 + C2** |
| **WidgetDisplayFormatTests.swift** | WidgetLargeView.swift, DisplayHelpers.swift | **fail** | **C1 (partial)** |
| **WidgetConfigTests.swift** | UsageWidget.swift | **fail** | **C1** |
| MenuContentSupplementTests.swift | MenuContent.swift | pass | - |
| **AppWindowsSupplementTests.swift** | ClaudeUsageTrackerApp.swift, MenuBarLabel.swift | **fail** | **C1** |
| DisplayHelpersTests.swift | DisplayHelpers.swift | pass | - |
| AlertCheckerTests.swift | AlertChecker.swift | pass | - |
| AlertCheckerSupplementTests.swift | AlertChecker.swift | pass | - |
| NotificationManagerTests.swift | NotificationManager.swift | pass | - |
| AppGroupConfigTests.swift | AppGroupConfig.swift | pass | - |
| ProtocolsSupplementTests.swift | Protocols.swift | pass | - |
| UsageFetcherSupplementTests.swift | UsageFetcher.swift | pass | - |
| UsageFetchErrorTests.swift | UsageFetcher.swift | pass | - |
| ArchitectureWebViewStructureTests.swift | WebViewCoordinator.swift | pass | - |
| WebViewCoordinatorTests.swift | WebViewCoordinator.swift | pass | - |

## 問題サマリー

### C1: 自己充足テスト（テスト内にソースロジック再実装）

| # | テストファイル | 重要度 | 内容 |
|---|-------------|--------|------|
| 1 | WidgetMiniGraphCalcTests.swift | **高** | ファイル全体が private メソッドの再実装。specResolveWindowStart, specBuildPoints, specTickDivisions, specNowXFraction, specTextIsBelow, specTextAnchor の6関数がソースロジックを複製 |
| 2 | AnalysisJSExtendedTests.swift | **中** | 8テストが cumulative/stats 計算ロジック（cumCost累積、rounding、stats集計）を JS で再実装。AnalysisTemplateRenderTests が同じ機能を正しくテスト済み |
| 3 | WidgetConfigTests.swift | **中** | 全テストがリテラル同士の比較（トートロジー）。ソースの型を一切参照せず、値が変更されても検出不可 |
| 4 | ViewModelTests+Fetch.swift | **中** | testWidgetGraphRenderability_variousSnapshotStates が WidgetMiniGraph.resolveWindowStart() を再実装（テスト内コメントで明記） |
| 5 | AppWindowsSupplementTests.swift | **低** | graphCount 計算をインラインで再実装。Retina scale テストはリテラル比較 |
| 6 | WidgetDisplayFormatTests.swift | **低** | LargeViewRemainingTextTests の specLargeRemainingText が private メソッド WidgetLargeView.remainingText() を再実装 |
| 7 | SQLiteBackupTests.swift | **低** | todayStamp/dateStamp ヘルパーが SQLiteBackup.dateStamp(from:) と同じ DateFormatter ロジックを複製 |
| 8 | AnalysisSQLQueryTests.swift | **低** | SQL文字列をソースからハードコピー。AnalysisSchemeHandlerSQLiteTests が同じ機能を公開IF経由でテスト済み |

### C2: IF不整合（テスト期待IF ≠ ソース公開IF）

| # | テストファイル | ソースファイル | 内容 |
|---|-------------|--------------|------|
| 1 | WidgetMiniGraphCalcTests.swift | DisplayHelpers.swift | specTextIsBelow が `topMargin < 14 \|\| isLowerHalf` を使用。ソースの percentTextShowsBelow は `markerY < topMargin` のみ。"lower half" 条件がソースに存在しない |

## 統計

- 対象テストファイル: 48（ヘルパー3を除く51ファイル中）
- pass: 40 (83%)
- C1: 8（高1、中3、低4）
- C2: 1（WidgetMiniGraphCalcTests.swift、C1と重複）
- 実行診断での問題: 0（全905テスト成功）

## 推奨アクション

### 修正対象（C1 — テスト修正）

1. **WidgetMiniGraphCalcTests.swift**: private メソッドをテスト可能にするため、ソース側で `internal` に変更するか、テストを公開IFを通した統合テストに書き換え
2. **AnalysisJSExtendedTests.swift**: AnalysisTemplateRenderTests と重複する8テストを削除し、独自テストのみ残す
3. **WidgetConfigTests.swift**: ソースの実際の型/定数を参照するように書き換えるか、トートロジーテストを削除
4. **ViewModelTests+Fetch.swift**: testWidgetGraphRenderability を WidgetMiniGraph の公開IFを使うように修正

### 修正対象（C2 — コード修正）

1. **DisplayHelpers.percentTextShowsBelow**: テストが期待する "lower half" 条件の追加を検討（テストが正しい場合）、またはテストの specTextIsBelow をソースに合わせて修正（ソースが正しい場合）
