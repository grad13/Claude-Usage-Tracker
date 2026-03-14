# Test Refactoring Analysis: test_binary_backup.py

## Metadata
- **Path**: tests/tools/test_binary_backup.py
- **Status**: should (refactor)
- **Lines**: 171
- **Issues Identified**: S6, S7

---

## Issues

### S6: Mixed Responsibilities
**Severity**: Medium

The file covers two distinct functional areas without clear separation:
1. **Binary backup logic** (Tests 6-8): Version-tagged rename, missing Info.plist fallback, overwrite scenarios
2. **Atomic install logic** (Tests 20-21): Widget verification, swap operations, failure handling

**Current structure**:
```
test_binary_backup()          # parametrized, covers 3 scenarios
test_atomic_install_widget_missing()
test_atomic_install_success()
```

**Impact**:
- Tests for different features are intermingled
- Helper functions (`_run_backup_logic`) are tightly coupled to one concern
- Future changes to atomic install may require understanding backup tests

---

### S7: Hand-Written Utilities Instead of Fixtures/Mocking
**Severity**: Medium

The file uses ad-hoc helper functions instead of pytest fixtures or standard mocking patterns:

**Current implementation**:
```python
def _create_app_with_version(install_dir, app_name, version=None):
    """Create an .app directory with optional Info.plist version."""
    app_dir = install_dir / f"{app_name}.app" / "Contents"
    app_dir.mkdir(parents=True)
    if version is not None:
        plist_path = app_dir / "Info.plist"
        with open(plist_path, "wb") as f:
            plistlib.dump({"CFBundleShortVersionString": version}, f)
    return install_dir / f"{app_name}.app"

def _run_backup_logic(install_dir, app_name):
    """Run the same backup logic as build_and_install.install_app."""
    current_app = install_dir / f"{app_name}.app"
    if current_app.is_dir():
        current_version = get_app_version(str(current_app))
        backup_app = install_dir / f"{app_name}.app.v{current_version}"
        if backup_app.exists():
            shutil.rmtree(str(backup_app))
        current_app.rename(backup_app)
```

**Issues**:
- Manual plist construction duplicates logic
- `_run_backup_logic()` is a copy of production code (violates DRY)
- No option for isolating backup logic in tests (mockable interface)
- Hard to test edge cases systematically

---

## Refactoring Recommendations

### 1. Split into Two Test Modules
```
tests/tools/test_binary_backup.py           → Binary backup logic only
tests/tools/test_atomic_install.py          → Atomic install logic only
```

### 2. Extract Fixtures to conftest.py
Move reusable test utilities to `tests/tools/conftest.py`:
```python
@pytest.fixture
def mock_app_with_version(tmp_path):
    """Factory fixture for creating .app bundles with optional Info.plist."""
    def _create(app_name: str, version: str | None = None) -> Path:
        app_dir = tmp_path / f"{app_name}.app" / "Contents"
        app_dir.mkdir(parents=True)
        if version:
            plist = app_dir / "Info.plist"
            plistlib.dump({"CFBundleShortVersionString": version}, plist, sort_keys=False)
        return tmp_path / f"{app_name}.app"
    return _create
```

### 3. Refactor Backup Tests
- Import backup logic from `code/tools/build_and_install.py` (or extract to module)
- Use fixture instead of `_create_app_with_version()`
- Verify against actual implementation, not mock code

### 4. Refactor Atomic Install Tests
- Create separate atomic install function/class if not already extracted
- Use mock for widget verification
- Test swap operation independently

---

## Acceptance Criteria

✓ Binary backup tests isolated in `test_binary_backup.py`
✓ Atomic install tests isolated in `test_atomic_install.py`
✓ Shared fixtures moved to `conftest.py`
✓ No duplicate production logic in tests
✓ All 5 tests (6, 7, 8, 20, 21) still pass
