# Diagnosis: AppWindowsSupplementTests

## 入力

- テストファイル: tests/ClaudeUsageTrackerTests/ui/AppWindowsSupplementTests.swift
- Sourceファイル: code/ClaudeUsageTracker/MenuBarLabel.swift
- 出力先: code/.code-from-tests/diagnosis/ui/AppWindowsSupplementTests.md

## チェックリスト

### クラスC（整合性問題 — 静的分析）
- [x] C1: テスト内にソースロジックの再実装がある
- [x] C2: テストが期待するIFとソースの公開IFが一致している

### クラスA/B（実行診断）
- 全テスト pass（クラスA/B問題なし）

## テスト実行結果

| 項目 | 値 |
|------|-----|
| テスト数 | pass（全体584中の一部） |
| 成功 | 全数 |
| 失敗 | 0 |

## 問題のあるチェック項目

### C1: 自己充足テスト

**What**
- テスト内で `graphCount` 計算式 `(showHourlyGraph ? 1 : 0) + (showWeeklyGraph ? 1 : 0)` を再実装
- Retina スケーリング `CGFloat(cgImage.width) / 2.0` を再実装
- フォールバックサイズ `NSSize(width: 80, height: 18)` を定数として再実装
- これらはすべて `MenuBarLabel.renderGraphs()` 内のロジックと同一

**Why**
`renderGraphs()` は `MenuBarLabel` の Body 内で使われる private メソッド。テストからは直接呼べないため、ロジックを複製してテスト内で検証する形になった。

**How**
選択肢1: `renderGraphs()` を `internal` にして `@testable import` で直接テスト
選択肢2: 公開IFからの間接テストに書き換え（MenuBarLabel の出力画像サイズで検証）

## 最終判定

- クラス: C
- レベル: C1
- 戻り値: `RESULT: fail:0:A:0:B:0:C:1`
