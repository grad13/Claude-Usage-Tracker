---
File: tests/tools/test_binary_backup_supplement.py
Lines: 196
Judgment: should
Issues: [S6, S7]
---

# test_binary_backup_supplement.py

## 問題点

### 1. [S6] 複数モジュールの責務混在

**現状**: 単一ファイル内で `db_backup.py` の3つの異なる関数をテストしている:
- `rotate_backups()` (RO-02, RO-04)
- `backup_database()` (BD-03, BD-04)
- `check_lost_rows()` (CL-03, CL-04)

**本質**: `db_backup.py` は論理的に独立した3つの責務を持つモジュールであり、各関数は異なる側面（ローテーション、バックアップ作成、整合性確認）をテストしている。これらをまとめると、テストスイート全体の構造が不透明になり、特定の関数の仕様変更時に影響範囲を把握しにくくなる。

**あるべき姿**: 責務ごとにテストファイルを分割:
- `test_rotate_backups.py` — 回転機構
- `test_backup_database.py` — バックアップ作成
- `test_check_lost_rows.py` — 行喪失チェック

### 2. [S7] 手書きフィクスチャ（DB構築ヘルパー）

**現状**: `_create_usage_db_with_rows()` (行30-60) は実際の SQLite3 コネクションを直接生成し、スキーマとデータを手作成している。各テストが複雑な DB セットアップロジックに依存している。

**本質**:
- テスト毎に SQLite API の全体フロー（executescript, execute, commit）を実行する重複
- フィクスチャとテストロジックの結合度が高い
- DB スキーマが変わると全テストに波及

**あるべき姿**: pytest の `@pytest.fixture` を使ってフィクスチャを専用ファイルまたは conftest.py に分離:
```python
@pytest.fixture
def usage_db(tmp_path):
    """Create a standard usage.db with N rows."""
    # shared fixture implementation
    return db_path
```

加えて、不変なスキーマ定義をモジュール定数として共有。
