# Refactor Code Analysis Summary

**Date**: 2026-02-26
**Target**: code/ (20 files analyzed, 3 excluded)

## must (500行超 — 3件)

| File | Lines | Issues |
|------|------:|--------|
| [WeatherCC/AnalysisExporter.swift](must/WeatherCC/AnalysisExporter.swift.md) | 709 | HTML/CSS/JS 700行がSwift文字列リテラル埋め込み、JS内の責務混在 |
| [WeatherCC/UsageViewModel.swift](must/WeatherCC/UsageViewModel.swift.md) | 678 | God Object（10+責務）、Cookie管理内包、設定メソッド羅列、デバッグログ基盤埋め込み |
| [WeatherCC/WeatherCCApp.swift](must/WeatherCC/WeatherCCApp.swift.md) | 522 | 7責務が1ファイルに同居（Menu, Graph, Login, Analysis, App） |

## should (責務混在/fallback — 0件)

なし

## clean (問題なし — 17件)

| File | Lines |
|------|------:|
| WeatherCC/UsageFetcher.swift | 327 |
| WeatherCCShared/SnapshotStore.swift | 398 |
| WeatherCC/TokenStore.swift | 280 |
| WeatherCC/UsageStore.swift | 284 |
| WeatherCCWidget/WidgetMediumView.swift | 263 |
| WeatherCC/Settings.swift | 157 |
| WeatherCC/AnalysisSchemeHandler.swift | 155 |
| WeatherCC/JSONLParser.swift | 137 |
| WeatherCC/Protocols.swift | 123 |
| WeatherCCWidget/WidgetLargeView.swift | 117 |
| WeatherCC/CostEstimator.swift | 103 |
| WeatherCCShared/SQLiteBackup.swift | 87 |
| WeatherCCWidget/WidgetSmallView.swift | 73 |
| WeatherCCWidget/UsageWidget.swift | 66 |
| WeatherCCShared/SnapshotModels.swift | 64 |
| WeatherCCShared/DisplayHelpers.swift | 47 |
| WeatherCCShared/AppGroupConfig.swift | 31 |

## excluded (分析対象外 — 3件)

| File | Lines | Reason |
|------|------:|--------|
| WeatherCC/LoginWebView.swift | 15 | 小さすぎて分析不要 |
| WeatherCCWidget/WeatherCCWidgetBundle.swift | 10 | 小さすぎて分析不要 |
| WeatherCCShared/WeatherCCShared.swift | 9 | 小さすぎて分析不要 |

## 総括

- **must 3件**: 全て500行超かつ責務混在。分割が必要
- **should 0件**: 500行未満のファイルは概ね単一責務を維持できている
- **clean 17件**: DI リファクタリング済みのため、Store 系・Widget 系はきれいに分離されている

### 推奨アクション（優先度順）

1. **AnalysisExporter.swift** (709行) — HTML/CSS/JS をバンドルリソースに分離。Swift コードは実質9行なので、分離後は最小になる
2. **UsageViewModel.swift** (678行) — SessionManager, AutoRefreshScheduler を抽出し God Object を解消
3. **WeatherCCApp.swift** (522行) — MiniUsageGraph, MenuContent, LoginWindowView を個別ファイルに分離
