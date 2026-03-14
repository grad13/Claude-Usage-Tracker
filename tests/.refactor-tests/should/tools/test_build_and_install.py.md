# Refactor Analysis: test_build_and_install.py

**Category**: SHOULD (S6 - Mixed responsibility: wrong file location)

**Severity**: Low-Medium (organizational issue, not code quality)

## Issue Summary

File `/tests/tools/test_build_and_install.py` contains tests for `db_backup.py`, not `build_and_install.py`.

### Evidence

```
File name:      test_build_and_install.py
Actual content: Tests for db_backup.py (check_lost_rows, rotate_backups)
Import:         from db_backup import check_lost_rows, rotate_backups
```

- Line 1-5: Docstring states "Tests for db_backup.py logic"
- Line 18: Imports from `db_backup` module
- Tests 1-5: All validate `db_backup` functions only

## Refactoring Recommendation

**Action**: Move/rename file to match content.

**Option A (Preferred)**:
- Create: `tests/tools/test_db_backup.py` with current content
- Delete: `tests/tools/test_build_and_install.py`

**Option B (Alternative)**:
- Rename: `test_build_and_install.py` → `test_db_backup.py`

## Test Quality Assessment

The tests themselves are **well-written**:

- ✅ Clear parametrization (4 test cases with IDs)
- ✅ Proper setup with tmp_path fixture
- ✅ Helper functions (`_create_usage_db`, `_insert_rows`) well-encapsulated
- ✅ No syntax/import errors
- ✅ 114 lines (manageable, no M2 complexity)
- ✅ Single responsibility per test function (no S6 mixing within tests)
- ✅ No hand-written mocks (uses SQLite with proper fixtures)

## No Changes Required to Test Code

The tests themselves do **not** need refactoring. Only the file location/naming is incorrect.

---

**Impact**: Low - Documentation/organization only. Tests are functional and correct.

**Effort**: Minimal - File move/rename operation.
