---
File: tests/ClaudeUsageTrackerTests/WidgetDesignSupplementTests.swift
Lines: 758
Judgment: must
Issues: [M2, S6, S7]
---

# WidgetDesignSupplementTests.swift

## 問題点

### 1. [M2] ファイルサイズ超過（750行超）

**現状**: 758行。XCTest ファイルとして明らかに大きすぎる（推奨上限 300行）

**本質**: テスト保守性の低下。多くのテストクラス（8個）と helper 関数がファイル内に密集しており、各テストの責任範囲が不明確。検索・修正時の認知負荷が高い

**あるべき姿**: 最大 300行程度に分割。単一のテスト対象（または関連する2-3個の機能）ごとに 1ファイル

---

### 2. [S6] 複数モジュールを 1ファイルで検証

**現状**: 以下 8個の独立したテストクラスが混在：
1. `UsageEntryTests` — timeline policy + widget constants
2. `ResolveWindowStartTests` — resolveWindowStart ロジック
3. `DrawTicksDivisionsTests` — drawTicks divisions
4. `BuildPointsTests` —座標計算
5. `NowXFractionTests` — WidgetMediumView 計算
6. `MarkerTextPositioningTests` — marker text placement
7. `LargeViewRemainingTextTests` — WidgetLargeView prefix ロジック
8. `DisplayHelpersRemainingTextTests` — DisplayHelpers formatting
9. `WidgetSmallViewArgumentMappingTests` — Small view 定数
10. `WidgetLargeViewArgumentMappingTests` — Large view 定数

**本質**: 「widget design の統合テスト」という名目だが、実際には 8-10 個の機能を検証。各クラスが独立しており、クラス間の依存関係は明確ではない。テスト失敗時の原因特定が困難

**あるべき姿**: 最小限 3-4 ファイルに分割：
- `ResolveWindowStartTests.swift`
- `DrawTicksAndBuildPointsTests.swift`（関連ロジック）
- `TextPositioningAndFormattingTests.swift`（marker text + remainingText）
- `WidgetConstantsAndMappingTests.swift`（全ての定数テスト）

---

### 3. [S7] 手書きの partial object で protocol をモック

**現状**: helper 関数群で spec の動作を手書き再実装（lines 25-88）：
- `specResolveWindowStart()`
- `specBuildPoints()`
- `specTickDivisions()`
- `specNowXFraction()`
- `specLargeRemainingText()`
- `HP` typealias (line 29)

加えて `specTextIsBelow()`、`specTextAnchor()` も同様

**本質**:
- テストが spec の「再実装」になっており、「spec と実装の乖離を検出できない」
- 実装が変わっても、helper も同じ変わり方をすれば test pass（false positive）
- helper 関数自体にバグがあっても気付けない

**あるべき姿**:
- Protocol conformance test か stub 型（MockHistoryProvider など）を使用
- 実装と spec 間の gap を明確にするため、spec 参照は comment に留める
- テストは「実装がこう動く」を検証し、「spec を再実装」しない
