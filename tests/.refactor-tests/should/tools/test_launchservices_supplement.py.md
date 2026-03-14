# test_launchservices_supplement.py — Refactoring Analysis

## File
`tests/tools/test_launchservices_supplement.py`

## Verdict
**SHOULD REFACTOR** (S7 — Hand-written mock data)

## Issues Detected

### S7: Hand-written Mock Data
**Lines**: 98-102, 105-107, 120-123, 126-128

**Problem**:
- Fake `lsregister` dump output hardcoded as strings in test functions
- Manual construction of `subprocess.CompletedProcess` objects scattered across tests
- No reuse — same patterns repeated for "found" and "not found" cases

**Evidence**:
```python
# Line 98-102: Fake dump hardcoded
fake_dump = (
    "path:    /Applications/TestApp.app/Contents/PlugIns/TestWidget.appex\n"
    "name:    TestWidget\n"
    "plugin Identifiers:         com.example.testwidget\n"
)

# Line 105-107: Manual CompletedProcess construction
mock_run.return_value = subprocess.CompletedProcess(
    args=[], returncode=0, stdout=fake_dump, stderr=""
)
```

**Impact**:
- Difficult to maintain — if lsregister output format changes, multiple places need updates
- No clear semantic meaning — magic strings don't explain what structure is being tested
- Low test readability — requires parsing the hardcoded strings to understand expected format

## Recommended Refactoring

### Option 1: Pytest Fixtures (Preferred)
```python
@pytest.fixture
def lsregister_dump_found():
    return (
        "path:    /Applications/TestApp.app/Contents/PlugIns/TestWidget.appex\n"
        "name:    TestWidget\n"
        "plugin Identifiers:         com.example.testwidget\n"
    )

@pytest.fixture
def lsregister_dump_not_found():
    return (
        "path:    /Applications/SomeOtherApp.app\n"
        "name:    SomeOtherApp\n"
    )

@pytest.fixture
def mock_subprocess_result():
    """Factory for CompletedProcess with common defaults."""
    def _factory(stdout, returncode=0):
        return subprocess.CompletedProcess(
            args=[], returncode=returncode, stdout=stdout, stderr=""
        )
    return _factory
```

### Option 2: Helper Function
```python
def _make_lsregister_dump(widget_id=None):
    if widget_id:
        return f"""path:    /Applications/TestApp.app/Contents/PlugIns/TestWidget.appex
name:    TestWidget
plugin Identifiers:         {widget_id}
"""
    return """path:    /Applications/SomeOtherApp.app
name:    SomeOtherApp
"""
```

## Other Observations

**Strengths**:
- Clean test structure with clear sections (lines 30-31, 51-52, etc.)
- Good docstrings explaining what's being tested
- Appropriate use of `patch` decorator
- Proper use of `tmp_path` for filesystem mocking

**No other issues**: File is short (132 lines), single responsibility per test, no syntax/import errors.

## Priority
**Medium** — Improves maintainability and clarity. Can be done incrementally without affecting test behavior.
