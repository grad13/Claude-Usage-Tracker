---
File: WeatherCC/AnalysisExporter.swift
Lines: 709
Judgment: must
Issues: [HTML/CSS/JS embedded in Swift string literal (700+ lines), multiple concerns in single JS blob]
---

# AnalysisExporter.swift

## 問題点

### 1. 700行超のHTML/CSS/JavaScriptが単一のSwift文字列リテラルに埋め込まれている

**現状**: ファイル全709行のうち、Swift コードは実質9行（enum宣言、static let宣言、閉じ括弧）。残り約700行はHTML/CSS/JavaScriptの生文字列リテラル（行9-707）。
**本質**: Swift コンパイラがビルドのたびにこの巨大文字列をパースする。HTML/CSS/JS にはシンタックスハイライト・リンター・フォーマッターが効かない。テストも不可能。フロントエンドの変更のたびに Swift ファイルを編集する必要がある。
**あるべき姿**: HTML テンプレートをバンドルリソース（.html ファイル）として分離し、Swift 側では `Bundle.main.url(forResource:)` でロードする。CSS と JS も別ファイルに分離可能。

### 2. JavaScript内の責務混在（計算ロジック + UI描画 + データ取得）

**現状**: 埋め込みJavaScript（行231-703）に以下が全て同一スコープで混在:
- モデル価格定義 `MODEL_PRICING`（行237-241）
- コスト計算 `costForRecord`（行249-256）
- データ取得 `loadData`/`fetchJSON`（行258-280）
- 統計計算 `computeKDE`（行297-319）、`computeDeltas`（行321-339）
- 6種のチャート描画関数（行382-611）
- UI制御: タブ切替、日付フィルタ、スライダー（行625-658）
- ヒートマップDOM生成 `buildHeatmap`（行341-380）
**本質**: どの関数を変更しても他への影響が不透明。チャート追加・変更時に470行のJSブロック全体を読む必要がある。グローバル変数（`_usageData`, `_tokenData`, `_allDeltas`, `_charts`, `_rendered`, `gapThresholdMs`）で状態管理しており、依存関係が暗黙的。
**あるべき姿**: HTML分離後、JSも機能別にモジュール分割する（データ層、計算層、描画層）。ただしWKWebViewでのモジュール読み込みには制約があるため、ビルド時結合か単一ファイル内のセクション分離が現実的。
