---
File: tests/WeatherCCTests/AnalysisExporterTests.swift
Lines: 4747
Judgment: must
Issues: [M2, S6]
---

# AnalysisExporterTests.swift

## 問題点

### 1. [M2] 4747行の巨大ファイル — 11個のテストクラスが1ファイルに同居

**現状**: 1ファイルに以下の11クラス + 2つのヘルパー型が詰め込まれている:
- `AnalysisExporterTests` (L6-218): HTML テンプレートの文字列検査
- `AnalysisSchemeHandlerTests` (L222-517): スキームハンドラの単体テスト
- `AnalysisSchemeHandlerSQLiteTests` (L523-746): SQLite DB を使った統合テスト
- `AnalysisWebViewIntegrationTests` (L753-911): WKWebView + スキームハンドラの結合テスト
- `CostEstimatorParityTests` (L926-1043): Swift/JS コスト計算の一致検証
- `AnalysisJSLogicTests` (L1051-1808): JS 関数の WKWebView 実行テスト
- `AnalysisSQLQueryTests` (L1815-2025): SQL クエリの正確性テスト
- `AnalysisJSExtendedTests` (L2031-2604): JS 拡張テスト（timeSlots, gap, cumulative 等）
- `AnalysisTemplateJSTests` (L2698-3175): 実テンプレートから抽出した JS テスト
- `AnalysisTemplateRenderTests` (L3182-3680): DOM 操作を伴うレンダリングテスト
- `AnalysisBugHuntingTests` (L3686-4713): バグ探索テスト
- `TemplateTestHelper` (L2612-2691): テスト用 HTML 生成ヘルパー
- `MockSchemeTask` (L4718-4747) + `TestNavDelegate` (L914-919): モック/ヘルパー

**本質**: ファイルが巨大すぎて以下の問題が発生する:
1. **ナビゲーション不能**: 特定のテストを見つけるのに検索が必須。MARK コメントはあるが4747行では焼け石に水
2. **重複コード**: `setUp`/`tearDown` が各クラスで似たパターンを繰り返している。特に `createUsageDb`/`createTokensDb` ヘルパーが `AnalysisSchemeHandlerSQLiteTests` (L538-610), `AnalysisWebViewIntegrationTests` (L767-803), `AnalysisSQLQueryTests` で3箇所に重複
3. **evalJS ヘルパーの重複**: `AnalysisJSLogicTests` (L1071-1085), `AnalysisJSExtendedTests` (L2049-2063), `AnalysisTemplateJSTests` (L2713-2727), `AnalysisTemplateRenderTests` (L3197-3211), `AnalysisBugHuntingTests` (L3701-3715) の5箇所でほぼ同一の `evalJS` メソッドが定義されている
4. **WKWebView セットアップの重複**: 上記5クラスで `setUp` の WKWebView 初期化コードがほぼ同一
5. **テストの重複**: `AnalysisJSLogicTests` と `AnalysisTemplateJSTests` が同じ関数を同じ入力で二重にテストしている（例: `pricingForModel`, `costForRecord`, `computeDeltas`, `computeKDE`, `insertResetPoints`）。`TemplateTestHelper` が実テンプレートから JS を抽出する仕組みがあるため、前者は不要

**あるべき姿**: 関心事ごとにファイルを分割する:
- `AnalysisExporterTests.swift` — HTML テンプレート構造テスト (L6-218)
- `AnalysisSchemeHandlerTests.swift` — スキームハンドラテスト (L222-746 の2クラス統合)
- `AnalysisWebViewIntegrationTests.swift` — WKWebView 結合テスト (L753-911)
- `AnalysisJSLogicTests.swift` — JS 関数テスト（重複排除後の統合）
- `AnalysisSQLQueryTests.swift` — SQL クエリテスト (L1815-2025)
- `CostEstimatorParityTests.swift` — Swift/JS 一致テスト (L926-1043)
- `AnalysisTestHelpers.swift` — 共通ヘルパー (`TemplateTestHelper`, `MockSchemeTask`, `TestNavDelegate`, `evalJS`, DB作成ヘルパー)

### 2. [S6] 独立した関心事が1ファイルに混在

**現状**: HTML テンプレート文字列検査、SQLite DB 統合テスト、WKWebView JS 実行テスト、SQL クエリ検証、DOM レンダリングテストなど、全く異なるテスト手法・依存関係を持つ11クラスが1ファイルに存在する。import は `@testable import WeatherCC` 1つだがテスト対象は `AnalysisExporter`, `AnalysisSchemeHandler`, `CostEstimator`, `TokenRecord` と複数の型にまたがる。

**本質**: テスト対象の型が異なり、テスト手法も異なる（文字列マッチング vs SQLite 操作 vs WKWebView JS 実行 vs DOM 検査）のに1ファイルにまとめる理由がない。特に WKWebView を使うテストは実行が重く、軽量な文字列テストと分離すべき。

**あるべき姿**: テスト対象の型 + テスト手法でファイルを分割し、各ファイルが1つの明確な責務を持つ構成にする。
