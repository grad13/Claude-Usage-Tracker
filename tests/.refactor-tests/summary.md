# refactor-tests: 全テストファイル分析サマリー

**実行日**: 2026-03-06
**対象**: 全テストファイル（Swift 40ファイル + Python 10ファイル = 50ファイル, 合計 10,074行）

## 結果概要

| 判定 | 件数 |
|------|------|
| must | 0 |
| should | 8 |
| clean | 42 |

**500行超のファイルなし**（最大484行）。must候補は0件。

## should（推奨対処）

### Swift テスト（6件）

| ファイル | 行数 | 問題ID | 概要 |
|----------|------|--------|------|
| ui/MenuContentSupplementTests.swift | 484 | S6 | 複数コンポーネントを1ファイルでテスト |
| widget/WidgetMiniGraphCalcTests.swift | 471 | S6 | 複数モジュール（ClaudeUsageTracker + ClaudeUsageTrackerShared）の複数コンポーネントを1ファイルでテスト |
| meta/WebViewCoordinatorTests.swift | 307 | S7 | 手書き部分モック（MockWKNavigationAction等がWKクラスをサブクラス化） |
| analysis/AnalysisSchemeHandlerTests.swift | 265 | S7 | 手書きモック（MockSchemeTask for WKURLSchemeTask） |
| analysis/AnalysisSchemeHandlerMetaJSONTests.swift | 262 | S7 | 手書きモック（MockSchemeTask） |
| meta/ViewModelTests.swift | 259 | S6,S7 | 複数モジュール + 手書き部分モック |
| meta/ProtocolsSupplementTests.swift | 79 | S6 | 複数モジュール（ClaudeUsageTrackerShared + ClaudeUsageTracker） |
| data/NotificationManagerTests.swift | 58 | S7 | 手書き部分モック |

### Python テスト（2件、2026-03-04 分析）

| ファイル | 行数 | 問題ID | 概要 |
|----------|------|--------|------|
| tools/test_build_and_install.py | 124 | S7 | プロダクションコード未インポート。ロジック再実装をテスト内に持つ |
| tools/test_lib_functions.py | 63 | S6 | version.py と launchservices.py の2独立モジュールを1ファイルに混在 |

## clean（問題なし）— 42件

### Swift テスト（34件）

| ファイル | 行数 |
|----------|------|
| meta/ViewModelSessionTests.swift | 433 |
| data/FetcherTests.swift | 416 |
| data/UsageStoreTests.swift | 408 |
| data/SettingsTests.swift | 395 |
| data/AlertCheckerTests.swift | 383 |
| analysis/AnalysisSchemeHandlerMetaJSONSupplementTests.swift | 366 |
| data/AlertCheckerSupplementTests.swift | 333 |
| analysis/AnalysisSchemeHandlerHelperTests.swift | 324 |
| data/UsageFetcherSupplementTests.swift | 323 |
| meta/ViewModelLifecycleSupplementTests.swift | 302 |
| meta/ArchitectureViewModelStateTests.swift | 228 |
| analysis/AnalysisExporterJSLogicTests.swift | 217 |
| analysis/AnalysisSQLQueryTests.swift | 194 |
| shared/SnapshotModelTests.swift | 186 |
| data/UsageStoreSupplementTests.swift | 182 |
| shared/DisplayHelpersTests.swift | 168 |
| meta/WebViewCoordinatorSupplementTests.swift | 167 |
| ui/MiniUsageGraphLogicTests.swift | 164 |
| shared/SQLiteHelperTests.swift | 162 |
| data/SettingsStoreTests.swift | 153 |
| ui/AppWindowsSupplementTests.swift | 151 |
| widget/WidgetDisplayFormatTests.swift | 147 |
| analysis/AnalysisWebViewIntegrationTests.swift | 134 |
| analysis/AnalysisSchemeHandlerSQLiteTests.swift | 121 |
| shared/SQLiteBackupTests.swift | 113 |
| analysis/AnalysisExporterTests.swift | 110 |
| analysis/AnalysisSchemeHandlerQueryFilterTests.swift | 108 |
| meta/ArchitectureWebViewStructureTests.swift | 101 |
| data/SettingsSupplementTests.swift | 77 |
| data/ProductionSettingsIntegrityTests.swift | 59 |
| data/UsageFetchErrorTests.swift | 49 |
| shared/AppGroupConfigTests.swift | 37 |
| data/NotificationManagerTests.swift の一部 | — |
| meta/ProtocolsSupplementTests.swift の一部 | — |

### Python テスト（8件）

| ファイル | 行数 |
|----------|------|
| tools/test_data_protection.py | 171 |
| tools/test_binary_backup.py | 170 |
| tools/test_build_and_install_supplement.py | 133 |
| tools/test_launchservices_supplement.py | 131 |
| tools/test_data_protection_supplement.py | 120 |
| tools/test_rollback.py | 113 |
| tools/test_rollback_supplement.py | 109 |
| tools/conftest.py | 46 |

## 問題パターン分析

### S6（責務混在）— 4件
複数モジュール・コンポーネントを1ファイルに混在。分割により責務が明確になる。

### S7（手書き部分モック）— 5件
`MockSchemeTask`（WKURLSchemeTask）、`MockWKNavigationAction`（WKNavigationAction サブクラス）等。
WebKit の protocol/class を手書きでモック化している。protocol conformance で統一可能か要検討。

## 詳細ファイル

- `tests/.refactor-tests/should/ui/MenuContentSupplementTests.swift.md`
- `tests/.refactor-tests/should/widget/WidgetMiniGraphCalcTests.swift.md`
- `tests/.refactor-tests/should/meta/WebViewCoordinatorTests.swift.md`
- `tests/.refactor-tests/should/analysis/AnalysisSchemeHandlerTests.swift.md`
- `tests/.refactor-tests/should/analysis/AnalysisSchemeHandlerMetaJSONTests.swift.md`
- `tests/.refactor-tests/should/meta/ViewModelTests.swift.md`
- `tests/.refactor-tests/should/meta/ProtocolsSupplementTests.swift.md`
- `tests/.refactor-tests/should/data/NotificationManagerTests.swift.md`
- `tests/.refactor-tests/should/tools/test_build_and_install.py.md`
- `tests/.refactor-tests/should/tools/test_lib_functions.py.md`
