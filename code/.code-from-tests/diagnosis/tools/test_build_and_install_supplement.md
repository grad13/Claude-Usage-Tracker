# Diagnosis: test_build_and_install_supplement.py

## 対象テスト
- `tests/tools/test_build_and_install_supplement.py`

## 対象ソース
- `code/tools/build_and_install.py` (imports `backup_database` from `db_backup`)
- `code/tools/lib/db_backup.py` (defines `backup_database(db_path, appgroup_dir)`)

## 失敗テスト

### test_backup_database_creates_backup — Class A6
### test_backup_database_db_not_found — Class A6
### test_backup_database_rotation — Class A6

**What**: テストが `bai.backup_database()` を引数なしで呼び出しているが、実際の関数シグネチャは `backup_database(db_path: Path, appgroup_dir: Path)` で2引数必須。

**Why**: テストはモジュールレベル定数 `APPGROUP_DIR` / `APPGROUP_DB` を monkeypatch してから引数なしで呼ぶ想定だが、`backup_database` は `db_backup` モジュールで定義されており、引数で受け取る設計。`build_and_install.py` の `main()` でも `backup_database(APPGROUP_DB, APPGROUP_DIR)` と明示的に引数を渡している。

**How**: テストの呼び出しを `bai.backup_database(db, appgroup)` に修正。monkeypatch は不要になる。

## 成功テスト
- test_bundle_bit_check_detects_missing — pass
- test_bundle_bit_check_passes — pass
