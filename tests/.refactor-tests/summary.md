# refactor-tests サマリー

実行日: 2026-02-26
対象: tests/WeatherCCTests/*Tests.swift (14ファイル)

## 結果一覧

| # | ファイル | 行数 | 判定 | 問題 |
|---|---------|------|------|------|
| 1 | AnalysisExporterTests.swift | 4747 | **must** | M2, S6 |
| 2 | ViewModelTests.swift | 874 | **must** | M2 |
| 3 | SnapshotStoreTests.swift | 509 | clean | — |
| 4 | FetcherTests.swift | 456 | clean | — |
| 5 | UsageStoreTests.swift | 444 | clean | — |
| 6 | JSONLParserTests.swift | 354 | clean | — |
| 7 | TokenStoreTests.swift | 339 | clean | — |
| 8 | CostEstimatorTests.swift | 286 | clean | — |
| 9 | SettingsTests.swift | 262 | clean | — |
| 10 | SnapshotModelTests.swift | 219 | clean | — |
| 11 | SettingsStoreTests.swift | 211 | **should** | S6 |
| 12 | DisplayHelpersTests.swift | 181 | clean | — |
| 13 | SQLiteBackupTests.swift | 113 | clean | — |
| 14 | AppGroupConfigTests.swift | 49 | clean | — |

## 統計

- **must**: 2ファイル
- **should**: 1ファイル
- **clean**: 11ファイル

## must 詳細

### AnalysisExporterTests.swift (4747行) — M2, S6

11個のテストクラス + 2つのヘルパー型が1ファイルに同居。
- `evalJS` ヘルパーが5箇所で重複定義
- `createUsageDb`/`createTokensDb` が3箇所で重複
- WKWebView セットアップが5クラスでほぼ同一
- `AnalysisJSLogicTests` と `AnalysisTemplateJSTests` でテスト自体が重複

→ 詳細: `tests/.refactor-tests/must/WeatherCCTests/AnalysisExporterTests.swift.md`

### ViewModelTests.swift (874行) — M2

40以上のテストメソッドが1ファイルに集約。
- モック定義96行 + テスト766行
- ウィジェット描画ロジックのテストが ViewModel テストに混在
- `DispatchQueue.main.asyncAfter(0.5) + wait(2.0)` パターンが11箇所

→ 詳細: `tests/.refactor-tests/must/WeatherCCTests/ViewModelTests.swift.md`

## should 詳細

### SettingsStoreTests.swift (211行) — S6

`ProductionSettingsIntegrityTests` (WeatherCCShared依存) と `SettingsStoreTests` (@testable import WeatherCC依存) が同一ファイルに存在。モジュール依存が混在。

→ 詳細: `tests/.refactor-tests/should/WeatherCCTests/SettingsStoreTests.swift.md`
