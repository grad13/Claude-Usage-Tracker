# Diagnosis: test_data_protection_supplement.py

## 対象テスト
- `tests/tools/test_data_protection_supplement.py`

## 対象ソース
- `code/tools/lib/data_protection.py`

## 失敗テスト

### TestSnapshot::test_raises_on_copy_failure — Class A6

**What**: テストが `pytest.raises(OSError, match="Failed to create backup")` を期待しているが、実際のエラーメッセージは `"Backup created but not found: ..."`.

**Why**: `_snapshot()` は2段階でエラーを出す:
1. `shutil.copy2` が例外を投げた場合 → `"Failed to backup {file}: {e}"`
2. コピーは成功したが `.backup` が存在しない場合 → `"Backup created but not found: {backup}"`

テストは `shutil.copy2` をモックで置き換え（例外を投げないno-op）。結果、第1段階はスキップされ、第2段階のエラーが発生。テストの `match` パターンが第2段階のメッセージと合わない。

**How**: テストの `match` パターンを `"Backup created but not found"` に修正。

## 成功テスト
- TestRestoreIfChanged::test_returns_0_unchanged — pass
- TestRestoreIfChanged::test_returns_1_corrupted — pass
- TestRestoreIfChanged::test_returns_2_deleted — pass
- TestRestoreIfChanged::test_returns_0_skipped — pass
- TestShelterFile::test_restores_unconditionally — pass
- TestShelterFile::test_nonexistent — pass
