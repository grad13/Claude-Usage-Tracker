---
File: ClaudeUsageTracker/UsageFetcher.swift
Lines: 320
Judgment: should
Issues: [責務混在（フェッチ/パース/日付処理/JS生成が1ファイル）, Format A/B フォールバック, UsageResultモデル同居]
---

# UsageFetcher.swift

## 問題点

### 1. 複数責務が1つのenumに集約

**現状**: `UsageFetcher` enum (L44-320) が以下を全て担う:
- Org ID 取得（cookie + JS fallback, L49-63）
- Usage API フェッチ（WebView経由, L68-81）
- JSON パース（Format A/B 分岐, L87-126）
- セッション有効性チェック（L131-145）
- JavaScript コード生成（70行超のJSリテラル, L149-219）
- ISO 8601 / Unix timestamp 日付パース（L260-319）
- パーセント計算（L238-255）

**本質**: パース・日付処理・計算ロジックはWebViewに依存しないにもかかわらず、WebView依存のフェッチャーと同居している。テスト時にパースだけ検証するには `UsageFetcher.parse()` を呼ぶ必要があり、モジュール境界が曖昧。

**あるべき姿**: パース/計算ロジック（`parse`, `parsePercent`, `calcPercent`, `parseResetsAt`, `parseResetDate` 等）を独立した型に分離し、フェッチャーはフェッチとパーサー呼び出しのみに集中させる。

### 2. Format A/B のフォールバック分岐がパース内にハードコード

**現状**: `parse()` メソッド内（L98-111）で2つのAPIレスポンス形式を `if let windows` で分岐。Format B は "documented" とコメントにあるが、実際に使われているかの検証手段がない。

**本質**: APIレスポンス形式の判定とデータ抽出が同じメソッドに混在。新しい形式が追加された場合、このメソッドが肥大化する。

**あるべき姿**: レスポンス形式の判定と各形式からの値抽出を分離し、形式ごとのパーサーを用意する。

### 3. UsageResult がモデルとしてファイル先頭に同居

**現状**: `UsageResult` 構造体（L5-17）と `UsageFetchError`（L19-42）が `UsageFetcher` と同じファイルに定義されている。

**本質**: `UsageResult` はViewModelやWidget等の複数箇所から参照されるデータモデルであり、フェッチャーの実装詳細ではない。

**あるべき姿**: `UsageResult` を独立ファイルに分離し、フェッチャーからの依存方向を明確にする。
