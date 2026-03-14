# Tests to Code Summary

実行日: 2026-03-15

## 全体結果

- 対象テストファイル: 30
- テスト数: 128 (118 passed, 10 failed)

## Diagnosis一覧

| Test | Source | Check | Class | 修正対象 |
|------|--------|-------|-------|---------|
| test_build_and_install_supplement.py (Tests 33-35) | db_backup.py | fail | A6 | テスト修正 |
| test_data_protection_supplement.py (Test 32) | data_protection.py | fail | A6 | テスト修正 |
| test_launchservices_supplement.py (Tests 23-27) | launchservices.py | fail | A6 | テスト修正 |
| test_deploy_integration.py (Test 3) | 実環境 | fail | A3 | 修正不要 |
| その他26ファイル | - | pass | - | - |

## 修正計画

### 1. test_build_and_install_supplement.py — 3件 (A6)
- `bai.backup_database()` → `bai.backup_database(db, appgroup)` に引数追加
- monkeypatch による APPGROUP_DIR/APPGROUP_DB 設定を削除

### 2. test_data_protection_supplement.py — 1件 (A6)
- `match="Failed to create backup"` → `match="Backup created but not found"` に修正

### 3. test_launchservices_supplement.py — 5件 (A6)
- `patch("launchservices.subprocess.run")` → `patch("launchservices.run")` に修正
- アサーションを `runner.run` の呼び出し規約（`on_error`, `label` kwargs）に合わせる

### 4. test_deploy_integration.py — 1件 (A3)
- 環境依存。修正対象外（次回クリーンビルドで解消）

## 合計修正: 9件（テスト修正のみ、コード修正なし）
