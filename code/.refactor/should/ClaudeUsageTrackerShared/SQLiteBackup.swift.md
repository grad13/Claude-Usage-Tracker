---
File: ClaudeUsageTrackerShared/SQLiteBackup.swift
Lines: 87
Judgment: should
Issues: [WAL checkpoint エラーハンドリング不足, DateFormatter 毎回生成, force unwrap による危険性]
---

# SQLiteBackup.swift

## 問題点

### 1. WAL checkpoint時のエラーハンドリング不足

**現状**: 35-38行目で `sqlite3_exec` の戻り値を無視している。`PRAGMA wal_checkpoint(TRUNCATE)` が失敗しても処理は続行される。

```swift
if sqlite3_open(dbPath, &db) == SQLITE_OK {
    sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
    sqlite3_close(db)
}
```

**本質**: SQLiteのcheckpoint操作はディスク同期の重要な処理。失敗時にログ出力や呼び出し元への通知がないため、バックアップが不完全なまま進行する可能性がある。また、sqlite3_closeの成功も確認されていない。

**あるべき姿**: `sqlite3_exec`の戻り値をチェックし、失敗時はエラーログを出力して早期リターン。`sqlite3_close`の成否も確認。

---

### 2. DateFormatter毎回生成によるパフォーマンス低下

**現状**: 55-60行目の `dateStamp(from:)` と 72-74行目の `purge(directory:dbName:retentionDays:)` でそれぞれ `DateFormatter` を毎回生成している。

```swift
private static func dateStamp(from date: Date = Date()) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = .current
    return f.string(from: date)
}
```

**本質**: DateFormatterはOSレベルで比較的重い処理。このメソッドは`purge()`内のループ（76-85行）で複数回呼ばれる可能性があり、ファイル数が多い場合にパフォーマンスが低下する。

**あるべき姿**: `static let`で計算の重い部分（DateFormatterの初期化）を一度だけ行う。または ISO 8601 フォーマットを使用。

---

### 3. force unwrap による危険性

**現状**: 70行目で`calendar.startOfDay(for: Date())`の結果に対して force unwrap（`!`）を使用している。

```swift
let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: calendar.startOfDay(for: Date()))!
```

**本質**: 通常は`calendar.date(byAdding:value:to:)`がnilを返さないが、本番環境でカレンダーが予期しない状態にあった場合クラッシュする。定期的に実行される処理のため、リスクが高い。

**あるべき姿**: Optional binding（`guard let`）または nil coalescing演算子を使用して安全に処理。失敗時はエラーログを出力して処理を中断。

---

## 改善の優先度

1. **WAL checkpoint エラーハンドリング** — 高（データ整合性に直結）
2. **force unwrap の除去** — 高（本番クラッシュリスク）
3. **DateFormatter パフォーマンス** — 中（機能的には動作するが効率化の余地）
