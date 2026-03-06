---
File: tests/ClaudeUsageTrackerTests/widget/WidgetMiniGraphCalcTests.swift
Lines: 471
Judgment: should
Issues: [S6]
---
# WidgetMiniGraphCalcTests.swift

## 問題点

### 1. [S6] 複数モジュール・複数コンポーネントを1ファイルでテスト

**現状**: 1ファイル内に4つのXCTestCaseクラス（`ResolveWindowStartTests`, `DrawTicksDivisionsTests`, `BuildPointsTests`, `NowXFractionTests`, `MarkerTextPositioningTests`）が存在し、テスト対象が複数のコンポーネント（WidgetMiniGraph座標計算、WidgetMediumView nowXFraction、DisplayHelpers マーカーテキスト配置）にまたがっている。さらに `ClaudeUsageTrackerShared`（DisplayHelpers）と `ClaudeUsageTracker`（WidgetMiniGraph, WidgetMediumView）の2モジュールを横断している（行21-23, 426-471）。

**本質**: テストファイルの責務が曖昧になり、どのコンポーネントの変更時にどのテストが影響を受けるか判断しにくい。DisplayHelpersのテスト（MarkerTextPositioningTests）はSharedモジュールのテストであり、WidgetMiniGraphの座標計算テストとは独立した関心事。

**あるべき姿**: モジュール・コンポーネント単位でテストファイルを分割する。例: WidgetMiniGraph座標計算（resolveWindowStart, drawTicks, buildPoints）を1ファイル、nowXFractionをWidgetMediumViewのテストファイルへ、DisplayHelpers.percentText系をSharedモジュールのテストファイルへ。
