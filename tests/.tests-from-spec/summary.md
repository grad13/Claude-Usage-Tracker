# Spec to Tests Summary

実行日: 2026-03-07

## 統計

- 対象spec: 17
- covered: 5 (テスト生成不要)
- partial: 12
  - generated: 10 (テスト生成済み)
  - skipped: 2 (ユニットテスト不可)
- 生成テストケース数: 160

## Test一覧

| Test | Spec | Source | Check | Action |
|------|------|--------|-------|--------|
| meta/ArchitectureViewModelStateTests.swift, ArchitectureWebViewStructureTests.swift | meta/architecture.md | ClaudeUsageTracker/*.swift | partial | generated |
| meta/ViewModelTests.swift, ViewModelTests+Fetch.swift, ViewModelLifecycleSupplementTests.swift | meta/viewmodel-lifecycle.md | ClaudeUsageTracker/UsageViewModel.swift | partial | generated |
| meta/ViewModelSessionTests.swift | meta/viewmodel-session.md | ClaudeUsageTracker/UsageViewModel+Session.swift | partial | generated |
| meta/ProtocolsSupplementTests.swift, ProtocolsSupplementTests2.swift, ProtocolsSupplementTests3.swift | meta/protocols.md | ClaudeUsageTracker/Protocols/ | covered | - |
| meta/WebViewCoordinatorTests.swift, WebViewCoordinatorSupplementTests.swift | meta/webview-coordinator.md | ClaudeUsageTracker/WebViewCoordinator.swift | covered | - |
| data/SettingsTests.swift, SettingsStoreTests.swift, SettingsSupplementTests.swift, SettingsPresetsTests.swift, ChartColorPresetTests.swift | data/settings.md | ClaudeUsageTracker/Settings.swift | partial | generated |
| data/UsageStoreTests.swift, UsageStoreSupplementTests.swift | data/usage-store.md | ClaudeUsageTracker/UsageStore.swift | partial | generated |
| data/FetcherTests.swift, UsageFetcherSupplementTests.swift, UsageFetchErrorTests.swift | data/usage-fetcher.md | ClaudeUsageTracker/UsageFetcher.swift | partial | skipped |
| data/AlertCheckerTests.swift, AlertCheckerSupplementTests.swift, NotificationManagerTests.swift, DailyAlertDefinitionTests.swift | data/alert.md | ClaudeUsageTracker/Alert*.swift | covered | - |
| ui/AppWindowsSupplementTests.swift | ui/app-windows.md | ClaudeUsageTracker/*Window*.swift, MenuBarLabel.swift | partial | generated |
| ui/MenuContentSupplementTests.swift | ui/menu-content.md | ClaudeUsageTracker/MenuContent.swift | partial | generated |
| ui/MiniUsageGraphLogicTests.swift | ui/mini-usage-graph.md | ClaudeUsageTracker/MiniUsageGraph.swift | partial | generated |
| analysis/AnalysisWebViewIntegrationTests.swift + 6 others | analysis/overview.md | ClaudeUsageTracker/AnalysisWindowView.swift | partial | skipped |
| analysis/AnalysisSchemeHandlerTests.swift + 6 others | analysis/analysis-scheme-handler.md | ClaudeUsageTracker/AnalysisSchemeHandler.swift | covered | - |
| analysis/AnalysisExporterTests.swift, AnalysisExporterJSLogicTests.swift | analysis/analysis-exporter.md | ClaudeUsageTracker/AnalysisExporter.swift, Resources/analysis.html | partial | generated |
| widget/WidgetMediumViewNowXTests.swift, WidgetDisplayFormatTests.swift, WidgetMiniGraphCalcTests.swift | widget/design.md | ClaudeUsageTrackerWidget/*.swift | partial | generated |
| (build tool - no Swift tests) | tools/build-and-install.md | code/tools/*.py | covered | - |

## 生成ファイル一覧

| # | File | Cases | Spec |
|---|------|-------|------|
| 1 | tests/.tests-from-spec/generated/meta/ArchitectureSupplementTests.swift | 8 | meta/architecture.md |
| 2 | tests/.tests-from-spec/generated/meta/ViewModelLifecycleSupplementTests2.swift | 23 | meta/viewmodel-lifecycle.md |
| 3 | tests/.tests-from-spec/generated/meta/ViewModelSessionSupplementTests.swift | 19 | meta/viewmodel-session.md |
| 4 | tests/.tests-from-spec/generated/data/SettingsSupplementTests2.swift | 13 | data/settings.md |
| 5 | tests/.tests-from-spec/generated/data/UsageStoreSupplementTests2.swift | 10 | data/usage-store.md |
| 6 | tests/.tests-from-spec/generated/ui/AppWindowsSupplementTests2.swift | 7 | ui/app-windows.md |
| 7 | tests/.tests-from-spec/generated/ui/MenuContentSupplementTests2.swift | 27 | ui/menu-content.md |
| 8 | tests/.tests-from-spec/generated/ui/MiniUsageGraphSupplementTests.swift | 12 | ui/mini-usage-graph.md |
| 9 | tests/.tests-from-spec/generated/analysis/AnalysisExporterSupplementTests.swift | 22 | analysis/analysis-exporter.md |
| 10 | tests/.tests-from-spec/generated/widget/WidgetDesignSupplementTests.swift | 19 | widget/design.md |

## スキップ理由

| Spec | Reason |
|------|--------|
| data/usage-fetcher.md | 全ギャップがWKWebViewランタイムまたはサイドエフェクトのみ（NSLog/ファイルログ） |
| analysis/overview.md | 全ギャップがJSコード内（XCTestでテスト不可） |
