---
File: ClaudeUsageTrackerShared/SnapshotStore.swift
Lines: 399
Judgment: should
Issues: [責務の混在 (SQLite3 API + ビジネスロジック + JSON移行), エラーハンドリングが呼び出し元に伝播しない, 低レベルAPI操作が直接露出]
---

# SnapshotStore.swift

## 問題点

### 1. 責務の混在：SQLite3低レベルAPI + ビジネスロジック + JSON移行

**現状**:
- `ensureDB()` → テーブル作成 + JSON移行実行（L31-77）
- `saveAfterFetch()` →状態保存 + 履歴追加（L80-138）
- `updatePredict()` → 予測値更新（L142-159）
- `clearOnSignOut()` → ログアウト時リセット（L162-189）
- `load()` → 状態読込 + 履歴読込（L192-266）
- `migrateFromJSON()` → JSON→SQLite移行（L318-397）

すべてが同一enum内で直接SQLite3 C-APIを操作している。

**本質**:
- SQLite3 C-APIの低レベル操作（`sqlite3_open`, `sqlite3_prepare_v2`, `sqlite3_bind_*`, `sqlite3_step`）がビジネスロジックと混在
- JSON移行はone-timeタスクであり、通常の読み書き操作と別の責務
- テーブルスキーマ定義、SQL生成、バインディングロジックが分離されていない

**あるべき姿**:
- SQLite3低レベルAPI操作を専用層（e.g., `SQLiteDatabase`）に分離
- JSON移行を別クラス（e.g., `SnapshotMigrator`）に抽出
- ビジネスロジック（save/load/update/clear）を高レベルインターフェース（`SnapshotStore`）に集約

---

### 2. エラーハンドリングが呼び出し元に伝播しない

**現状**:
- `saveAfterFetch()` (L80-138): 失敗時 `log.error` して return、呼び出し元はエラーを認識できない
- `updatePredict()` (L142-159): 失敗時何もしない（silent failure）
- `clearOnSignOut()` (L162-189): 失敗時ログのみ
- `load()` (L192-266): 失敗時 `nil` を返すが、callerが詳細を知らない

**本質**:
- ログに記録されるだけで、UIレイヤーやVMが「何が失敗したか」「再試行は可能か」を判定できない
- 特に `saveAfterFetch` は重要な操作（APIから取得したデータ保存）なのに失敗を無視している

**あるべき姿**:
```swift
// 現状: 呼び出し元は成功か失敗かわからない
SnapshotStore.saveAfterFetch(...)

// あるべき姿: 結果型で伝播
SnapshotStore.saveAfterFetch(...) -> Result<Void, SnapshotStoreError>
// または
SnapshotStore.saveAfterFetch(...) throws
```

---

### 3. SQLite3低レベルAPI操作が直接露出

**現状**:
- `OpaquePointer` による DB ハンドル管理（L38, 87, 145, etc.）
- `sqlite3_open`, `sqlite3_prepare_v2`, `sqlite3_bind_*`, `sqlite3_step` の直接呼び出し
- PRAGMA設定（WAL, busy_timeout）が複数箇所に散在（L45-46, 90, 149, 168, 209）

**本質**:
- リソースリーク（`defer sqlite3_close` に依存）
- PRAGMA設定の重複（4箇所で同じコード）
- SQL文字列の直接組み立て（SQLインジェクション風味）
- メモリ管理が複雑で、新機能追加時にバグを招きやすい

**あるべき姿**:
- SQLite3操作を抽象化したラッパー（e.g., `SQLiteConnection`）
```swift
class SQLiteConnection {
    func execute(_ sql: String) throws
    func prepare(_ sql: String) throws -> Statement
    func close()
}
```
- PRAGMA設定を初期化時に集約
- SQL文字列の生成を単一の場所で管理

---

### 4. 複数の単一責任原則（SRP）違反

**現状**:
- テーブルスキーマ定義: `createState`, `createHistory` (L48-70)
- SQL生成: `stateSQL`, `histSQL`, `legacyDecoder` (L95, 126, 323)
- バインディング: `bindDouble`, `bindText`, `readDate` (L300-314)
- 履歴読込ロジック: `loadHistory` (L270-298)
- JSON移行: `migrateFromJSON` (L318-397)

SRPに従えば、これらは別のクラスに分離されるべき。

**あるべき姿**:
```
SnapshotStore (facade)
  ├─ SQLiteDatabase (低レベルAPI)
  ├─ SnapshotQuery (SQL文生成)
  ├─ SnapshotMigrator (JSON移行)
  └─ HistoryLoader (履歴読込)
```

---

### 5. テスト化の困難さ

**現状**:
- `dbPathOverride` (L20) でテスト時にパスをオーバーライド
- しかし、低レベルAPI操作が直接露出しているため、状態保存をモック化しにくい

**本質**:
- 依存性注入（DI）がないため、テスト時にDBを置き換えられない
- `ensureDB()` が `migrateFromJSON` を暗黙的に呼び出すため、テストがJSON ファイルの有無に依存

**あるべき姿**:
```swift
protocol SnapshotStorageBackend {
    func save(_ snapshot: UsageSnapshot) throws
    func load() throws -> UsageSnapshot?
    func updatePredict(...) throws
}

class SnapshotStore {
    let backend: SnapshotStorageBackend
    init(backend: SnapshotStorageBackend = SQLiteSnapshotBackend()) { ... }
}
```

---

## 優先度

1. **高**: エラーハンドリング → callerに失敗を通知しないと、データ損失につながる
2. **高**: SQLite3 API の抽象化 → 新機能追加時のバグリスク
3. **中**: JSON移行の分離 → one-time操作を本体と分離して理解性向上
4. **中**: テスト化の容易性 → DI導入でモック化可能に
