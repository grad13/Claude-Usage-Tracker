---
File: ClaudeUsageTracker/UsageStore.swift
Lines: 309
Judgment: should
Issues: [DB接続ボイラープレートの重複, loadメソッド間のデータ取得不整合, サイレント失敗のエラーハンドリング]
---

# UsageStore.swift

## 問題点

### 1. DB接続・クローズのボイラープレートが全メソッドで重複

**現状**: `save`(L82-87), `loadAllHistory`(L145-147), `loadHistory`(L183-185), `loadDailyUsage`(L217-219) の4メソッド全てで `sqlite3_open` / `defer { sqlite3_close(db) }` が繰り返されている。
**本質**: DB接続の開閉は横断的関心事であり、各メソッドに散在させると変更時（例: WALモード有効化、接続プール導入）に全箇所を修正する必要がある。
**あるべき姿**: `withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T` のようなヘルパーでDB接続ライフサイクルを一元管理する。

### 2. loadAllHistory と loadHistory でデータ取得範囲が不整合

**現状**: `loadAllHistory`(L149-157) はJOINで `hourly_resets_at`, `weekly_resets_at` を取得して `DataPoint` に設定するが、`loadHistory`(L188-193) はJOINなしでこれらをnilのまま返す。同じ `DataPoint` 型を返すのに情報量が異なる。
**本質**: 呼び出し元が `DataPoint.fiveHourResetsAt` を使おうとしたとき、どのloadメソッドで取得したかによって値の有無が変わる。暗黙の契約違反が起きやすい。
**あるべき姿**: 同じ型を返すならJOINの有無を統一するか、resetsAtを含まない軽量版が必要なら別の型（またはオプションパラメータでJOIN有無を制御）にする。

### 3. エラーハンドリングがprintベースのサイレント失敗

**現状**: `save`メソッド(L78-79, L84, L93, L107, L119) でDB操作失敗時に `print` してから `return` するだけ。loadメソッド群も空配列/nilを返すのみ。
**本質**: 呼び出し元はデータ保存が成功したか失敗したかを区別できない。テスト時にもエラー検出が困難。「データがない」と「保存に失敗した」が同じに見える。
**あるべき姿**: `save` は `throws` にするか、少なくとも `Bool` を返す。loadメソッドは `Result<[DataPoint], Error>` を返すか、エラー時にログレベルを上げる仕組みを持つ。
