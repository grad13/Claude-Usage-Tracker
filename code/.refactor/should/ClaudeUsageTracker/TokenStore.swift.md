---
File: ClaudeUsageTracker/TokenStore.swift
Lines: 305
Judgment: should
Issues: [複数責務混在, SQLiteデバッグ情報の欠如, エラーハンドリング不統一]
---

# TokenStore.swift

## 問題点

### 1. SQLite操作とファイルシステム操作の責務混在

**現状**: `sync()` メソッド（行50-86）内で以下の処理が順序立てて実行される:
- ディレクトリ作成（ファイルシステム責務）
- SQLiteオープン（DB責務）
- テーブル作成（スキーマ責務）
- ファイルスキャン（FS責務）
- レコード挿入（DB責務）
- ファイルメタデータ記録（DB責務）

**本質**: 単一のメソッド内で3つの異なる責務（FS操作、DB接続・管理、ファイル処理パイプライン）が混在しているため、テスト・保守・エラー処理の局所化が困難。例えば「ファイルスキャン処理だけをテストしたい」「DB操作だけを他のクラスから再利用したい」という要求に対応しにくい。

**あるべき姿**: 責務を分離して以下のような構造にする:
- `SQLiteProvider`: DB接続・クローズ・トランザクション管理（シングルトン）
- `FileScanner`: ディレクトリスキャン＆フィルタリング（ステートレス）
- `sync()`: 上記2つをオーケストレートするメソッド

### 2. SQLiteエラーハンドリング不統一

**現状**:
- 行59-61: `sqlite3_open` 失敗時は `NSLog` してreturn
- 行93, 107: `sqlite3_open_v2` 失敗時は空配列をreturn（ログなし）
- 行139-141: テーブル作成失敗時は `NSLog` して続行
- 行230: `sqlite3_prepare_v2` 失敗時は無言でreturn

**本質**: 同じ種類のエラーでも呼び出し元に返す結果が異なる（ログあり/なし、ログレベルが一定でない）。デバッグ時にどのシナリオで失敗したのか追跡困難。特に本番環境では「DB読み込み失敗 → 空配列返却」の原因が把握しにくい。

**あるべき姿**: エラーハンドリング戦略を明確に定義し、統一する:
- 致命的エラー（DB開けない）: `NSLog` + 例外またはオプション返却
- リカバリ可能エラー（カラム追加失敗は無視でOK）: 黙って継続 + コメントで意図を明記
- 各関数の先頭にエラーハンドリングポリシーをドキュメント化

### 3. SQLiteプリペアドステートメント準備と実行の分散

**現状**:
- `upsertRecord()` 行229-244: `sqlite3_prepare_v2` → バイン処理 → `sqlite3_step`（結果チェックなし）
- `markFileProcessed()` 行251-259: `sqlite3_prepare_v2` → バインド → `sqlite3_step`（結果チェックなし）
- `queryRecords()` 行268-274: `sqlite3_prepare_v2` → バインド → ループで `sqlite3_step`

**本質**: いずれも `sqlite3_step` の戻り値をチェックしていない。INSERTが成功したか、UPDATE後いくつのロー変更されたか不明。特に `upsertRecord` で重複キー競合時の動作が不透明。また、バイン結果チェックもなし。

**あるべき姿**:
- すべてのSQLite API呼び出し結果をチェック（`SQLITE_DONE`, `SQLITE_ROW` 等）
- 結果チェック失敗時は `NSLog` + 呼び出し元に反映（成功/失敗のbool返却など）
- 複雑なバイン・ステップ処理はヘルパー関数に抽出（重複排除）

### 4. ISO8601DateFormatterの初期化方法が冗長

**現状**: 行34-38で計算プロパティで初期化
```swift
private let iso: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
```

**本質**: クロージャで初期化する必要がない（プロパティの初期値が複数行の場合の標準パターンだが、ここではこのプロパティが多回使用される）。むしろ、このフォーマッタは静的で、すべてのインスタンス間で共有可能。

**あるべき姿**: 以下のいずれかに:
1. **static let**: 共有フォーマッタ化 → `TokenStore.iso` でアクセス可能、メモリ効率化
   ```swift
   private static let iso = ISO8601DateFormatter()
   ```
   初期化ブロックは `init()` で一度だけ実行（静的に初期化済み）

2. または、現行のまま保持するなら、コメントで「各インスタンス個別フォーマッタ」の意図を明記

### 5. 「既知ファイル」メタデータと同期ロジック的分離不足

**現状**:
- `loadKnownFiles()` 行150-164: jsonl_filesテーブルから既知ファイルのパス＆mtime取得
- `findFilesToProcess()` 行168-193: ファイルシステムをスキャンし、既知ファイルとの比較で差分抽出
- `sync()` 行50-86: 上記2関数を順序立てて呼び出す

**本質**: 「ファイルが新規か変更されたか判定する」ロジック（mtime比較 line 185）とファイルスキャンロジックが別関数に分散。新規/変更判定の閾値（`abs(knownMod - modTime) < 1.0`）がファイルスキャナーに埋め込まれており、テスト・カスタマイズが困難。

**あるべき姿**: 差分判定ロジックを明示的なメソッド/関数に抽出:
```swift
private func shouldReprocess(path: String, knownModTime: Double?, currentModTime: Double) -> Bool {
    guard let known = knownModTime else { return true }
    return abs(known - currentModTime) >= 1.0
}
```
これで testability向上、意図の明確化。

## 推奨優先度

| 問題 | 優先度 | 理由 |
|------|--------|------|
| 責務混在（問題1） | 高 | テスタビリティ・再利用性に影響 |
| エラーハンドリング不統一（問題2） | 高 | 本番デバッグ困難、リスク |
| ステートメント結果チェック（問題3） | 高 | 無言の失敗 → デバッグ困難 |
| フォーマッタ静的化（問題4） | 低 | メモリ最適化のみ、機能に影響なし |
| 差分判定ロジック抽出（問題5） | 中 | テストカバレッジ向上 |

## 関連ファイル
- `JSONLParser.swift`: `sync()` で呼び出すパーサー
- `TokenRecord.swift`: 本ファイルで使用するデータモデル
- `AppGroupConfig.swift`: DB パスの決定に使用
