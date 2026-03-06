# AnalysisSchemeHandlerMetaJSONTests.swift

- **行数**: 264
- **テストケース数**: 6
- **import**: XCTest, WebKit, SQLite3, @testable ClaudeUsageTracker

## 検出された問題

### S6: テスト間の重複セットアップコード

UT-M04, UT-M05, UT-M04b の3テストがそれぞれ独自に sqlite3_open/sqlite3_exec/sqlite3_close でDBスキーマを構築している。スキーマ文字列(CREATE TABLE hourly_sessions, weekly_sessions, usage_log)がほぼ同一で3箇所に重複。UT-M01/M02/M03 は AnalysisTestDB ヘルパーや空DBを使っており統一されていない。

**対策**: 共通のDBスキーマ作成ヘルパーを用意し、各テストはデータ挿入のみに集中させる。

### S8: マジックナンバー

タイムスタンプ値がリテラルで散在:
- `1772532000` (UT-M04: resets_at, アサーション)
- `1771900000` (UT-M04: timestamp, UT-M04b: timestamp)
- `1771990000` (UT-M04: timestamp, アサーション)
- `1771800000` (UT-M05: timestamp, アサーション)
- `1771850000` (UT-M05: timestamp, アサーション)

セットアップSQL内のリテラルとアサーション内のリテラルが対応しているが、名前付き定数がないため対応関係がコメント頼り。

**対策**: テストクラス冒頭またはenum で名前付き定数を定義し、セットアップとアサーションの両方で使用する。
