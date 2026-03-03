---
File: tests/ClaudeUsageTrackerTests/AnalysisJSTests.swift
Lines: 1406
Judgment: must
Issues: [M2, S6]
---

# AnalysisJSTests.swift

## 問題点

### 1. [M2] 単一テストファイルが 1406 行を超過

**現状**: `AnalysisJSTests.swift` は 1406 行で構成され、以下の 3 つの独立したテストクラスを含む:
- `AnalysisJSLogicTests`（~559行：pricingForModel, costForRecord, computeDeltas, timeXScale, computeKDE, timeSlots）
- `AnalysisJSExtendedTests`（~471行：境界値テスト、cumulative cost、stats、template drift）
- `AnalysisTemplateJSTests`（~365行：HTMLテンプレート生成と validation）

**本質**:
- テストファイルが 500 行を超えると、IDE のナビゲーション、リファクタリング、デバッグが低速化
- 3 つの独立した関心事が混在し、変更の影響範囲判定が困難
- 新機能追加時にどのファイルに追加すべきか判断しにくい

**あるべき姿**:
テストファイルを機能別に分割：
1. `AnalysisJSLogicTests.swift` → pricingForModel, costForRecord, computeDeltas, timeXScale, computeKDE, timeSlots
2. `AnalysisJSExtendedTests.swift` → 境界値テスト、cumulative cost、stats computation、template drift
3. `AnalysisTemplateJSTests.swift` → HTMLテンプレート生成と validation

### 2. [S6] 複数の非関連なモジュール・機能セットを 1 ファイルでテスト

**現状**: 3 つのテストクラスが同一ファイル内で、以下の異なる機能をテスト:
- **AnalysisJSLogicTests**: コスト計算ロジック（pricing, costFor, deltas, KDE）
- **AnalysisJSExtendedTests**: 時系列フィルタリング（timeSlots）と統計計算（cumulative, stats）
- **AnalysisTemplateJSTests**: HTML テンプレート生成と DOM 操作

**本質**:
- 各クラスが互いに異なるドメイン（pricing, temporal, template）を対象とするため、テスト時の心的負荷が高い
- ファイルの責任が広すぎて、変更時の回帰テスト範囲が不透明
- チームメンバーが機能別テストを探す際のサーチコストが増加
- `AnalysisJSTestCase` ベースクラスが共有されているが、各テストクラスの依存性は限定的

**あるべき姿**:
- 各テストクラスを別ファイルに分割
- ファイル名とテスト対象を 1:1 対応させ、責任を明確化
- `AnalysisJSTestCase` 共有ベースクラスは共通ユーティリティ（`evalJS`）を提供するため、分割後も依存性を維持する
