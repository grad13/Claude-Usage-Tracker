---
File: ClaudeUsageTracker/UsageStore.swift
Lines: 306
Judgment: should
Issues: [Multiple responsibilities mixed, SQL injection vulnerability in string interpolation, error handling gaps, coupling to AppGroup configuration]
---

# UsageStore.swift

## 問題点

### 1. 複数責務の混在（Data Access + Session Management + Normalization）

**現状**: UsageStore が以下の責務を持っている
- SQLite データ層の管理（save, load）
- セッション ID の作成・取得（getOrCreateSessionId）
- リセット時刻の正規化（normalizeResetsAt）
- データ変換（readDataPoints）

**本質**: 1つのクラスが複数の責務を持つと、テストが複雑になり、再利用が困難になる。例えば normalizeResetsAt は独立してテストしたくても UsageStore 経由でしかアクセスできない

**あるべき姿**: 責務を分離する
- `SessionNormalizer`: resets_at の正規化ロジック
- `DataPointMapper`: SQLite 行 → DataPoint への変換
- `UsageStoreCore`: 上記を組み合わせた data access

---

### 2. SQL インジェクション脆弱性（文字列補間）

**現状**: 行277, 285
```swift
let insertSQL = "INSERT OR IGNORE INTO \(table) (resets_at) VALUES (?)"
let selectSQL = "SELECT id FROM \(table) WHERE resets_at = ?"
```

テーブル名を文字列補間で直接埋め込んでいる。table パラメータが信頼できる値（hardcoded "hourly_sessions" / "weekly_sessions"）とは言え、SQLite のプリペアドステートメントは parameter binding でのみセキュアとされる

**本質**: SQLite3 C API はテーブル名の parameter binding をサポートしないため、ホワイトリスト検証が必須。現在は暗黙的にホワイトリスト化されているが、ドキュメント化されていない

**あるべき姿**: enum または switch で table 名を明示的にホワイトリスト化する
```swift
func getOrCreateSessionId(..., table: SessionType) -> Int64? {
    let tableName = table == .hourly ? "hourly_sessions" : "weekly_sessions"
    // ...
}
```

---

### 3. エラーハンドリングの不均等さ

**現状**:
- save() は多くのエラーを NSLog + return で無視（行78, 86, 101, 113）
- withDatabase は失敗時に nil を返すが、呼び出し側が ?? [] で黙って空配列を返す（行155, 180）
- sqlite3_exec の return 値チェックはあるが、sqlite3_step の失敗は NSLog のみ（行112）

**本質**: エラーが通知されず、データベース操作の失敗が silent に見える。デバッグ時に何が失敗したか追跡が困難

**あるべき姿**:
- Result 型で成功/失敗を明示的に返す
- 重大なエラー（DB 破損など）と soft failures（既存セッション）を区別する

---

### 4. AppGroupConfig への直接カップリング

**現状**: 行25-31 の shared 初期化が AppGroupConfig に依存
```swift
guard let container = AppGroupConfig.containerURL else {
    fatalError("[UsageStore] App Group container not available")
}
```

**本質**: App Group が利用不可な状況で即座に fatalError。テスト時も DEBUG 条件で temporary directory にフォールバックしているが、本番では選択肢がない。UI のテストなどで UsageStore が必要になるたびに App Group 設定が必須になる

**あるべき姿**: 初期化時に dbPath を呼び出し側から注入できるようにする（既に init 側では対応済み）。shared は便利メソッドとして残すが、テストでは DI で別の UsageStore を渡す

---

### 5. loadDailyUsage のロジック複雑さ

**現状**: 行188-239 のセッション境界ハンドリングが内部ロジック
- records 配列を手動で構築（204-216）
- ループで前後のセッションを比較（224-231）
- 最後の値を特別に処理（234-235）

**本質**: 複雑な loop invariant があり、オフバイワン버그のリスク。テストケースが多く必要だが、現在このメソッド固有のテストがあるか不明

**あるべき姿**:
- セッション内での usage 計算を `SessionUsageCalculator` に分離
- 各セッションの usage を計算してから加算する方が読みやすい

---

### 6. bindDouble 関数の抽象度不足

**現状**: 行298-304 で Optional<Double> を binding するヘルパーを定義しているが、他の型は直接 sqlite3_bind_* を呼んでいる（行106, 109-110）

**本質**: binding ロジックが部分的に抽象化されており、一貫性がない。例えば Int64 も Optional を取ることが多いが、毎回 if-else を書いている

**あるべき姿**: Generic helper を用意する（Swift では難しい場合もあるが、少なくともコメントで「Optional binding パターン」を明示する）

---

### 7. normalizeResetsAt の計算式がマジックナンバー

**現状**: 行67
```swift
return ((epoch + 1800) / 3600) * 3600
```

1800 = 30分、3600 = 1時間は値としては正しいが、コメント（行63-64）には「millisecond jitter 対策」とあるのに、式に意図が反映されていない

**本質**: `+ 1800` がなぜ「丸める」のかコードから読取不可。次の人が見たときに「なぜ 1800？」と疑問に思う

**あるべき姿**:
```swift
let halfHourInSeconds = 1800
let hourInSeconds = 3600
return ((epoch + halfHourInSeconds) / hourInSeconds) * hourInSeconds
```

または計算式全体に comment を付ける：
```swift
// Round to nearest hour: (t + 0.5h) / 1h truncate * 1h
return ((epoch + 1800) / 3600) * 3600
```
