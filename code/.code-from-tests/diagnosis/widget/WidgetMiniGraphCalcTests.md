# Diagnosis: WidgetMiniGraphCalcTests

## 入力

- テストファイル: tests/ClaudeUsageTrackerTests/widget/WidgetMiniGraphCalcTests.swift
- Sourceファイル: code/ClaudeUsageTrackerWidget/WidgetMiniGraph.swift
- 出力先: code/.code-from-tests/diagnosis/widget/WidgetMiniGraphCalcTests.md

## チェックリスト

### クラスC（整合性問題 — 静的分析）
- [x] C1: テスト内にソースロジックの再実装がある
- [x] C2: テストが期待するIFとソースの公開IFが一致している

### クラスA/B（実行診断）
- 全テスト pass（クラスA/B問題なし）

## テスト実行結果

| 項目 | 値 |
|------|-----|
| テスト数 | pass |
| 成功 | 全数 |
| 失敗 | 0 |

## 問題のあるチェック項目

### C1: 自己充足テスト

**What**
3つの private メソッドのロジックをテスト内で再実装:

1. `specResolveWindowStart` → `WidgetMiniGraph.resolveWindowStart` の3段階優先ロジックを複製
2. `specBuildPoints` → `WidgetMiniGraph.buildPoints` の elapsed/xFrac/yFrac 計算を複製
3. `specTickDivisions` → `WidgetMiniGraph.drawTicks` の `windowSeconds <= 5*3600+1 ? 5 : 7` を複製

全テストがこれらの再実装ヘルパーのみをテストし、実際のソースコードは一切呼ばない。

**Why**
`resolveWindowStart`, `buildPoints`, `drawTicks` は全て `private`。

**How**
選択肢1: 3メソッドを `internal static func` に抽出して `@testable import` で直接テスト
選択肢2: テストを削除（Widget の描画結果での間接テストは困難）

## 最終判定

- クラス: C
- レベル: C1
- 戻り値: `RESULT: fail:0:A:0:B:0:C:4`
