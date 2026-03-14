# Refactoring Analysis: test_data_protection_supplement.py

**Status**: SHOULD refactor
**Triggered Criteria**: S6, S7
**Line Count**: 149 (OK)

---

## Issues Detected

### S6: Mixed Responsibilities
- **Location**: Entire file
- **Problem**: Tests 5 different functions (`_restore_if_changed`, `_sha256`, `_snapshot`, `shelter_file`) across 8 test cases
- **Current state**:
  - Tests 28-31: `_restore_if_changed` (4 tests, lines 30-108)
  - Test 32: `_snapshot` (1 test, lines 114-122)
  - Tests 38-39: `shelter_file` (2 tests, lines 129-149)
- **Impact**: High cohesion needed for maintainability
- **Recommendation**: Consider splitting by tested function
  - `test_restore_if_changed_*.py` (4 tests)
  - `test_snapshot_*.py` (1 test)
  - `test_shelter_file_*.py` (2 tests)

### S7: Hand-Written Mocking
- **Location**: Line 120
- **Code**:
  ```python
  with patch("data_protection.shutil.copy2"):
      with pytest.raises(OSError, match="Failed to create backup"):
          _snapshot(target)
  ```
- **Problem**: Patches `shutil.copy2` to trigger failure path; relies on implicit backup verification
- **Impact**: Fragile test - depends on internal implementation detail (shutil.copy2)
- **Recommendation**:
  - Consider using `pytest.MonkeyPatch` if available
  - Or use conditional skip/mark to document mocking intent
  - Verify that the mocked behavior truly validates the OSError contract

---

## Statistics

| Category | Count |
|----------|-------|
| Total tests | 8 |
| Functions tested | 5 |
| Hand-written patches | 1 |
| Test cohesion issues | High |

---

## Priority
**Medium** — Refactor when consolidating test suite, not urgent for functionality
