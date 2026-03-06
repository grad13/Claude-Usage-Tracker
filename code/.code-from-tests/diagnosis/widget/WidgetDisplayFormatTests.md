# Diagnosis: WidgetDisplayFormatTests

## 入力

- テストファイル: tests/ClaudeUsageTrackerTests/widget/WidgetDisplayFormatTests.swift
- Sourceファイル: code/ClaudeUsageTrackerWidget/WidgetLargeView.swift
- 出力先: code/.code-from-tests/diagnosis/widget/WidgetDisplayFormatTests.md

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
- `specLargeRemainingText` (テスト内ヘルパー) が `WidgetLargeView.remainingText` のロジックを再実装
- `text == "expired" ? text : "in " + text` という条件分岐を複製

**Why**
`WidgetLargeView.remainingText` は View の computed property で `private`。テストから直接呼べない。

**How**
選択肢1: `remainingText` を `internal static func` に抽出して `@testable import` で直接テスト
選択肢2: テスト内の `specLargeRemainingText` を削除し、`DisplayHelpers.remainingText` のテストのみに限定

## 最終判定

- クラス: C
- レベル: C1
- 戻り値: `RESULT: fail:0:A:0:B:0:C:1`
