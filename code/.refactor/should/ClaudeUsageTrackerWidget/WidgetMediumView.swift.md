---
File: ClaudeUsageTrackerWidget/WidgetMediumView.swift
Lines: 264
Judgment: should
Issues: [責務混在: 2つの独立structが1ファイルに同居, Canvas描画ロジックが巨大モノリシック]
---

# WidgetMediumView.swift

## 問題点

### 1. WidgetMiniGraph が同一ファイルに同居している

**現状**: `WidgetMediumView`(6-94行) と `WidgetMiniGraph`(98-263行) という2つの独立した struct が1ファイルに定義されている。WidgetMiniGraph は約165行あり、ファイル全体の62%を占める。
**本質**: WidgetMiniGraph は label, history, windowSeconds 等を受け取る汎用的なグラフコンポーネントであり、WidgetMediumView に依存していない。別ファイルに分離すれば、他のウィジェットサイズ(Small, Large)からも自然に参照でき、ファイルの責務が明確になる。
**あるべき姿**: `WidgetMiniGraph.swift` として独立ファイルに分離する。

### 2. Canvas 描画ロジックが1つの body クロージャにフラット展開されている

**現状**: WidgetMiniGraph の body (113-262行) 内に、背景描画・ラベル描画・目盛り描画・データポイント構築・no-data領域・過去領域塗り・未来領域塗り(ストライプ)・使用率ライン・マーカー・パーセントテキストという約10の描画フェーズが150行のフラットなコードとして並んでいる。
**本質**: 各描画フェーズ間に論理的な区切りがなく、変更時に影響範囲の特定が困難。例えば「ストライプパターンを変更したい」場合、204-224行の該当箇所を150行の中から探す必要がある。Canvas の context と size をキャプチャする都合で SwiftUI の `@ViewBuilder` 分割は使えないが、private メソッドへの抽出は可能。
**あるべき姿**: Canvas 内の各描画フェーズを private メソッド(例: `drawBackground`, `drawTicks`, `drawArea`, `drawFutureStripes`, `drawMarker` 等)に抽出し、body では呼び出し順序だけが見えるようにする。
