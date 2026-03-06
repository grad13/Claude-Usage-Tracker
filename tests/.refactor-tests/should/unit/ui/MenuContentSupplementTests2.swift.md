# MenuContentSupplementTests2.swift

- 行数: 314
- テストケース数: 24
- import: XCTest, @testable ClaudeUsageTracker

## 検出された問題

### S6: 重複パターン

Hourly/Weekly で同一構造のテストが対になって繰り返されている。プロパティ名が異なるだけで検証ロジックは同一。

対象グループ:
- `testSetShowHourlyGraph_false_updatesSettingsAndPersists` / `testSetShowWeeklyGraph_false_updatesSettingsAndPersists`
- `testSetShowHourlyGraph_true_updatesSettingsAndPersists` / `testSetShowWeeklyGraph_true_updatesSettingsAndPersists`
- `testShowHourlyGraph_defaultTrue` / `testShowWeeklyGraph_defaultTrue`
- `testSetHourlyColorPreset_updatesSettingsAndPersists` / `testSetWeeklyColorPreset_updatesSettingsAndPersists`
- `testSetHourlyColorPreset_reloadsWidgetTimelines` / `testSetWeeklyColorPreset_reloadsWidgetTimelines`
- `testSetHourlyColorPreset_allPresets` / `testSetWeeklyColorPreset_allPresets`
- `testHourlyColorPreset_defaultBlue` / `testWeeklyColorPreset_defaultPink`

ヘルパーまたはパラメタライズで統合可能。

### S7: 弱いアサーション

- `testColorPreset_allCasesProduceColor` (L305-313): `let _ = preset.color` で「クラッシュしない」ことのみ検証。色の正しさ(RGB値)を一切保証しない。
- `testVersionFormat_withVersion` (L280-286), `testVersionFormat_fallbackWhenNil` (L288-294): プロダクションコードを呼ばず、テスト内のローカル変数で string interpolation を検証。プロダクションの version format ロジックの動作保証にならない。

### S8: テスト対象外のロジックをテスト

- `testVersionFormat_withVersion`, `testVersionFormat_fallbackWhenNil`: テストメソッド内で `"v\(version ?? "?")"` を組み立ててアサーションしている。プロダクションコードの version format メソッド/プロパティを呼んでおらず、テスト自身のローカルロジックをテストしている。
