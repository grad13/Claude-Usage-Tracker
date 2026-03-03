---
File: ClaudeUsageTrackerWidget/WidgetMiniGraph.swift
Lines: 195
Judgment: should
Issues: [Magic numbers and fallback logic, Multiple guard statements with early returns, Tuple return type lacks clarity, Hard-coded color values scattered]
---

# WidgetMiniGraph.swift

## 問題点

### 1. 複数のguard文による段階的フォールバック

**現状**: lines 28, 32, 97, 143 で guard 文が複数存在し、データ検証と描画ロジックが混在
```swift
guard let windowStart = resolveWindowStart() else { return }
guard let built = buildPoints(windowStart: windowStart, w: w, h: h) else { return }
guard fillEndX > effectiveNowX + 1 else { return }
guard !points.isEmpty else { return nil }
```

**本質**: 各ガード条件が異なる責務を持っており、失敗理由の明確性が欠ける。データ不在時とUIレンダリング失敗時の区別が曖昧

**あるべき姿**:
- データ検証ロジックを先行実行し、有効なstate全体をbodyの上部で確認
- 描画フェーズでは「与えられたデータで描画する」に専念
- 各guard文の役割を明文化（「ウィンドウ計算失敗」「描画対象なし」など）

### 2. タプルの戻り値型による可読性低下

**現状**: line 86, 98
```swift
private func buildPoints(windowStart: Date, w: CGFloat, h: CGFloat) -> (points: [(x: CGFloat, y: CGFloat)], lastPercent: Double)?
return (points, lastPercent)
```

**本質**: タプルの命名があるものの、呼び出し側で `built.points` と `built.lastPercent` でアクセスするため、構造体にすべき領域

**あるべき姿**:
```swift
struct BuiltPoints {
    let points: [(x: CGFloat, y: CGFloat)]
    let lastPercent: Double
}
```

### 3. ハードコーディングされた定数値と魔法の数字

**現状**: lines 14-18, 92-93, 131-132, 150, 156, 175, 185 など
```swift
private static let bgColor = Color(red: 0x12/255, green: 0x12/255, blue: 0x12/255)
let divisions = windowSeconds <= 5 * 3600 + 1 ? 5 : 7
let yFrac = min(dp.percent / 100.0, 1.0)
stripe.addLine(to: CGPoint(x: effectiveNowX + offset + (h - lastY), y: lastY))
layerCtx.stroke(stripe, with: .color(areaColor.opacity(areaOpacity * 0.35)), lineWidth: 0.5)
```

**本質**:
- 色値が複数箇所に分散しており、デザイン変更時の影響範囲が不明確
- 時間分割（5 vs 7）の判定値 `5 * 3600 + 1` が不透明
- ストライプ密度（4, 0.35, 0.5）が魔法の数字

**あるべき姿**:
- デザイン定数を別の `struct WidgetStyle` に集約
- 分割ロジック（5時間の判定）を `private static let` で明名化
- ストライプパターン用の定数群を定義
