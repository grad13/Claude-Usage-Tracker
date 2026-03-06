# Diagnosis: WidgetMediumViewNowXTests

## 入力

- テストファイル: tests/ClaudeUsageTrackerTests/widget/WidgetMediumViewNowXTests.swift
- Sourceファイル: code/ClaudeUsageTrackerWidget/WidgetMediumView.swift
- 出力先: code/.code-from-tests/diagnosis/widget/WidgetMediumViewNowXTests.md

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
- `specNowXFraction` が `WidgetMediumView.nowXFraction` の計算ロジックを完全に再実装
- `windowStart = resetsAt - windowSeconds`, `clamp(nowElapsed / windowSeconds, 0, 1)` を複製
- 全7テストがこの再実装ヘルパーのみをテストし、実際のソースコードは一切呼ばない

**Why**
`nowXFraction` は `WidgetMediumView` の `private` computed property。

**How**
選択肢1: `nowXFraction` のロジックを `internal static func nowXFraction(resetsAt:windowSeconds:now:) -> CGFloat` に抽出
選択肢2: テストを削除（public IF経由でのテストが困難な場合）

## 最終判定

- クラス: C
- レベル: C1
- 戻り値: `RESULT: fail:0:A:0:B:0:C:1`
