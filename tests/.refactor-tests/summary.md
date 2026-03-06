# refactor-tests: 全テストファイル分析サマリー

**実行日**: 2026-03-06
**対象**: 全テストファイル（Swift 45ファイル + Python 10ファイル = 55ファイル）
**更新**: 2026-03-06 S6 2件を分割対処済み

## 結果概要

| 判定 | 件数 | 備考 |
|------|------|------|
| must | 0 | 500行超なし（最大330行） |
| should | 6 | S7: 4件（対処不要）、S6: 2件（対処不要）+ Python 2件（未対処） |
| resolved | 2 | S6 分割済み |
| clean | 45 | 分割で5ファイル増加 |

## resolved（対処済み）

| 元ファイル | 行数 | 問題ID | 対処内容 |
|----------|------|--------|---------|
| ui/MenuContentSupplementTests.swift | 484→220 | S6 | 3ファイルに分割: SettingsPresetsTests(223), ChartColorPresetTests(44), DailyAlertDefinitionTests(24) |
| widget/WidgetMiniGraphCalcTests.swift | 471→330 | S6 | 2ファイルに分割: WidgetMediumViewNowXTests(85), DisplayHelpersMarkerTests(55) |

## should（残存・対処不要）

### Swift テスト — S7（4件: WebKit opaque class / 共有テストダブル使用で改善不可）

| ファイル | 行数 | 問題ID | 理由 |
|----------|------|--------|------|
| meta/WebViewCoordinatorTests.swift | 307 | S7 | WKNavigationAction等はopaque class。サブクラス化が唯一の方法 |
| analysis/AnalysisSchemeHandlerTests.swift | 265 | S7 | MockSchemeTaskは共有ヘルパー（protocol conformance済み）。ファイル内モックなし |
| analysis/AnalysisSchemeHandlerMetaJSONTests.swift | 262 | S7 | 同上 |
| data/NotificationManagerTests.swift | 58 | S7 | MockNotificationSenderは共有テストダブル（protocol conformance済み） |

### Swift テスト — S6（2件: 行数が少なく費用対効果が低い）

| ファイル | 行数 | 問題ID | 理由 |
|----------|------|--------|------|
| meta/ViewModelTests.swift | 259 | S6,S7 | 259行でmanageable。Supplementファイルで既に分散済み |
| meta/ProtocolsSupplementTests.swift | 79 | S6 | 79行で分割の費用対効果が低い |

### Python テスト（2件、2026-03-04 分析・未対処）

| ファイル | 行数 | 問題ID | 概要 |
|----------|------|--------|------|
| tools/test_build_and_install.py | 124 | S7 | プロダクションコード未インポート。ロジック再実装をテスト内に持つ |
| tools/test_lib_functions.py | 63 | S6 | version.py と launchservices.py の2独立モジュールを1ファイルに混在 |

## clean — 45件

### Swift テスト（39件、分割新規5件含む）

| ファイル | 行数 |
|----------|------|
| meta/ViewModelSessionTests.swift | 433 |
| data/FetcherTests.swift | 416 |
| data/UsageStoreTests.swift | 408 |
| data/SettingsTests.swift | 395 |
| data/AlertCheckerTests.swift | 383 |
| analysis/AnalysisSchemeHandlerMetaJSONSupplementTests.swift | 366 |
| data/AlertCheckerSupplementTests.swift | 333 |
| widget/WidgetMiniGraphCalcTests.swift | 330 |
| analysis/AnalysisSchemeHandlerHelperTests.swift | 324 |
| data/UsageFetcherSupplementTests.swift | 323 |
| meta/ViewModelLifecycleSupplementTests.swift | 302 |
| meta/ArchitectureViewModelStateTests.swift | 228 |
| data/SettingsPresetsTests.swift | 223 |
| ui/MenuContentSupplementTests.swift | 220 |
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
| widget/WidgetMediumViewNowXTests.swift | 85 |
| data/SettingsSupplementTests.swift | 77 |
| data/ProductionSettingsIntegrityTests.swift | 59 |
| shared/DisplayHelpersMarkerTests.swift | 55 |
| data/UsageFetchErrorTests.swift | 49 |
| data/ChartColorPresetTests.swift | 44 |
| shared/AppGroupConfigTests.swift | 37 |
| data/DailyAlertDefinitionTests.swift | 24 |

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

## 詳細ファイル

- `tests/.refactor-tests/should/meta/WebViewCoordinatorTests.swift.md`
- `tests/.refactor-tests/should/analysis/AnalysisSchemeHandlerTests.swift.md`
- `tests/.refactor-tests/should/analysis/AnalysisSchemeHandlerMetaJSONTests.swift.md`
- `tests/.refactor-tests/should/meta/ViewModelTests.swift.md`
- `tests/.refactor-tests/should/meta/ProtocolsSupplementTests.swift.md`
- `tests/.refactor-tests/should/data/NotificationManagerTests.swift.md`
- `tests/.refactor-tests/should/tools/test_build_and_install.py.md`
- `tests/.refactor-tests/should/tools/test_lib_functions.py.md`
