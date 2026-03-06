# refactor-tests Summary

Date: 2026-03-07
Analyzed: 20 / 61 files (top 20 by line count)

## Results

| Judgment | Count | Files |
|----------|-------|-------|
| must     | 1     | 500行超 |
| should   | 5     | S6/S7 該当 |
| clean    | 14    | 問題なし |

## must (1 file)

| File | Lines | Issues |
|------|-------|--------|
| `meta/ViewModelLifecycleSupplementTests2.swift` | 535 | M2 (500行超) |

Details: `must/unit/meta/ViewModelLifecycleSupplementTests2.swift.md`

## should (5 files)

| File | Lines | Issues |
|------|-------|--------|
| `analysis/AnalysisSchemeHandlerHelperTests.swift` | 324 | S6 (責務混在: 2クラス混在) |
| `ui/MenuContentSupplementTests2.swift` | 314 | S7 (手書き部分モック) |
| `meta/WebViewCoordinatorTests.swift` | 307 | S7 (手書き部分モック) |
| `analysis/AnalysisSchemeHandlerMetaJSONTests.swift` | 264 | S7 (手書き部分モック) |
| `meta/ViewModelTests+Fetch.swift` | 259 | S7 (手書き部分モック) |

Details: `should/unit/{path}.md`

## clean (14 files)

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
| `data/UsageFetcherSupplementTests.swift` | 304 |
| `meta/ViewModelLifecycleSupplementTests.swift` | 302 |
| `analysis/AnalysisSchemeHandlerTests.swift` | 265 |
| `widget/WidgetMiniGraphCalcTests.swift` | 261 |
| `meta/ViewModelTests.swift` | 259 |

## Next Steps

- **must**: ViewModelLifecycleSupplementTests2.swift を分割（535行 → 2ファイル程度）
- **should S7**: protocol conformance ベースのモックに統一（4ファイル）
- **should S6**: AnalysisSchemeHandlerHelperTests.swift の2クラスをファイル分離
