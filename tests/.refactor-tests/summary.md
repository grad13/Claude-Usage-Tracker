# refactor-tests Summary

Date: 2026-03-07
Total analyzed: 20 / 62 files (top 20 by line count)

## Results

| Judgment | Count | Files |
|----------|-------|-------|
| must     | 0     | (前回の1件は分割済み) |
| should   | 3     | S6/S7 該当 |
| clean    | 17    | 問題なし |

## should (3 files)

| File | Lines | Issues | Description |
|------|-------|--------|-------------|
| `meta/WebViewCoordinatorTests.swift` | 303 | S7 | Hand-written partial mocks: MockUsageViewModel, MockWKNavigationAction, MockWKWindowFeatures |
| `meta/ViewModelTests.swift` | 259 | S6 | 6 distinct concerns in single file (statusText, timeProgress, WebView config, closePopup, reloadHistory, alert integration) |
| `analysis/AnalysisSchemeHandlerMetaJSONTests.swift` | 211 | S7 | Hand-written partial mock (前回分析、今回未再分析) |

Details: `should/unit/{path}.md`

## clean (17 files)

| File | Lines |
|------|-------|
| `meta/ViewModelSessionTests.swift` | 468 |
| `data/SettingsTests.swift` | 428 |
| `data/UsageStoreTests.swift` | 408 |
| `data/FetcherTests.swift` | 392 |
| `data/AlertCheckerTests.swift` | 383 |
| `analysis/AnalysisSchemeHandlerMetaJSONSupplementTests.swift` | 367 |
| `data/AlertCheckerSupplementTests.swift` | 333 |
| `meta/ViewModelSessionSupplementTests.swift` | 329 |
| `analysis/AnalysisExporterSupplementTests.swift` | 328 |
| `ui/MenuContentSupplementTests2.swift` | 314 |
| `data/UsageFetcherSupplementTests.swift` | 304 |
| `meta/ViewModelLifecycleSupplementTests.swift` | 302 |
| `analysis/AnalysisSchemeHandlerHelperTests.swift` | 287 |
| `analysis/AnalysisSchemeHandlerTests.swift` | 265 |
| `widget/WidgetMiniGraphCalcTests.swift` | 261 |
| `meta/ViewModelTests+Fetch.swift` | 259 |
| `meta/ViewModelHandlePageReadyTests.swift` | 228 |
| `meta/ArchitectureViewModelStateTests.swift` | 228 |

## Notes

- 前回 must だった `ViewModelLifecycleSupplementTests2.swift` (535行) は既に3ファイルに分割済み (commit d8b0b34)
- 前回 should だった3ファイル (AnalysisSchemeHandlerHelperTests, MenuContentSupplementTests2, ViewModelTests+Fetch) は今回 clean と判定 → 古い分析ファイル削除済み

## Next Steps

- **S7**: WebViewCoordinatorTests.swift, AnalysisSchemeHandlerMetaJSONTests.swift の hand-written partial mock を protocol conformance ベースに統一
- **S6**: ViewModelTests.swift の6責務を関連テストファイルに分散
