# refactor-tests Summary

**実行日**: 2026-03-04
**対象**: tests/ClaudeUsageTrackerTests/ 全37ファイル (12,871行)

## 結果概要

| 判定 | 件数 | ファイル |
|------|------|----------|
| **must** | 4 | 500行超 |
| **should** | 11 | S6/S7該当 |
| **clean** | 22 | 問題なし |

## must (4件) — 500行超、分割必須

| # | ファイル | 行数 | 問題 |
|---|---------|------|------|
| 1 | AnalysisJSTests.swift | 1406 | M2, S6 (3クラス混在: Logic/Extended/Template) |
| 2 | AnalysisRenderTests.swift | 1142 | M2 (2クラス: TemplateRender/BugHunting) |
| 3 | AnalysisSchemeHandlerSupplementTests.swift | 766 | M2, S6, S7 (4クラス混在 + 手書きMockSchemeTask) |
| 4 | WidgetDesignSupplementTests.swift | 757 | M2, S6, S7 (8-10クラス + spec再実装ヘルパー) |

## should (11件) — 推奨リファクタリング

| # | ファイル | 行数 | 問題 |
|---|---------|------|------|
| 1 | MenuContentSupplementTests.swift | 490 | S6 (ViewModel/AppSettings/Enum混在) |
| 2 | AnalysisSchemeHandlerTests.swift | 468 | S6 (Core/SQLite統合が混在) |
| 3 | FetcherTests.swift | 456 | S6, S7 (UsageFetcher+FetchError混在, 辞書手動構築) |
| 4 | ArchitectureSupplementTests.swift | 385 | S6, S7 (6クラス混在 + makeVM重複) |
| 5 | AlertCheckerTests.swift | 383 | S6, S7 (Weekly/Hourly/Daily混在 + 手書きモック) |
| 6 | AlertCheckerSupplementTests.swift | 333 | clean判定 ※エージェント判定 |
| 7 | AnalysisSQLQueryTests.swift | 270 | S6 (SchemeHandler SQL + TokenRecord + CostEstimator混在) |
| 8 | WebViewCoordinatorTests.swift | 266 | S6, S7 (Coordinator+CookieObserver + MockVM手書き) |
| 9 | AnalysisWebViewIntegrationTests.swift | 139 | S6, S7 (4モジュール混在 + TestNavDelegate手書き) |
| 10 | CostEstimatorParityTests.swift | 124 | S6 (CostEstimator+AnalysisExporter混在) |
| 11 | NotificationManagerTests.swift | 58 | S6 (MockSender+DefaultSender混在) |
| 12 | ProtocolsSupplementTests.swift | 111 | S6 (3protocol混在: SettingsStoring/UsageStoring/TokenSyncing) |

**注**: AlertCheckerSupplementTests.swift はエージェントがclean判定したが、リスト上はshould候補として残す（再確認推奨）。

## clean (22件) — 問題なし

| ファイル | 行数 |
|---------|------|
| SnapshotStoreTests.swift | 509 |
| ViewModelSessionTests.swift | 457 |
| UsageStoreTests.swift | 415 |
| SettingsTests.swift | 395 |
| JSONLParserTests.swift | 354 |
| TokenStoreTests.swift | 350 |
| AlertCheckerSupplementTests.swift | 333 |
| UsageFetcherSupplementTests.swift | 323 |
| ViewModelLifecycleSupplementTests.swift | 308 |
| ViewModelTests.swift | 297 |
| CostEstimatorTests.swift | 286 |
| TokenStoreSupplementTests.swift | 227 |
| SnapshotModelTests.swift | 219 |
| AnalysisExporterTests.swift | 205 |
| UsageStoreSupplementTests.swift | 189 |
| DisplayHelpersTests.swift | 181 |
| SettingsStoreTests.swift | 153 |
| AppWindowsSupplementTests.swift | 151 |
| SQLiteBackupTests.swift | 113 |
| SettingsSupplementTests.swift | 77 |
| ProductionSettingsIntegrityTests.swift | 59 |
| AppGroupConfigTests.swift | 49 |

## 検出パターン集計

| 問題ID | 説明 | 件数 |
|--------|------|------|
| M2 | 500行超 | 4 |
| S6 | 複数モジュール/責務混在 | 14 |
| S7 | 手書き部分モック | 7 |
| S8 | xcodebuildエラー | 0 |

## 次工程

1. **must 4件**: 計画書を作成して分割実施
2. **should 11件**: 優先度付けして段階的に対処
3. テスト↔コード整合性は `tests-to-code` で別途実施
4. テスト↔spec整合性は `tests-to-spec` で別途実施
