---
File: tests/tools/test_rollback_supplement2.py
Lines: 195
Judgment: should
Issues: [S7]
---

# test_rollback_supplement2.py

## 問題点

### 1. [S7] Hand-written mock without abstraction (lines 105-115)

**現状**:
Test `test_rollback_copytree_file_exists_error_retries` implements a custom mock function `copytree_fail_once` by hand:

```python
original_copytree = shutil.copytree
call_count = 0

def copytree_fail_once(src, dst, **kwargs):
    nonlocal call_count
    call_count += 1
    if call_count == 1:
        Path(dst).mkdir(parents=True, exist_ok=True)
        raise FileExistsError(f"[Errno 17] File exists: '{dst}'")
    return original_copytree(src, dst, **kwargs)

monkeypatch.setattr(shutil, "copytree", copytree_fail_once)
```

This pattern:
- Manually tracks state (`call_count` via `nonlocal`)
- Implements conditional behavior manually
- Duplicates logic that `unittest.mock` provides natively

**本質**:
Hand-written mocks mix test logic with mock behavior, making tests harder to:
1. Understand at a glance (custom logic instead of standard Mock API)
2. Extend (adding another failure point requires manual refactoring)
3. Reuse (other tests can't easily share this pattern)

The test is verifying the correct behavior (retry after rmtree), but the mock implementation obscures this intent.

**あるべき姿**:
Extract mock behavior into a helper function or use `unittest.mock.MagicMock` with `side_effect`:

```python
# Option 1: Helper function (reusable)
def copytree_fail_on_first_call(original_func, exception_on_call=1):
    """Returns a callable that fails on specified call number(s)."""
    call_count = 0
    def wrapper(src, dst, **kwargs):
        nonlocal call_count
        call_count += 1
        if call_count == exception_on_call:
            Path(dst).mkdir(parents=True, exist_ok=True)
            raise FileExistsError(f"[Errno 17] File exists: '{dst}'")
        return original_func(src, dst, **kwargs)
    return wrapper

# In test:
monkeypatch.setattr(shutil, "copytree", copytree_fail_on_first_call(original_copytree))

# Option 2: Use side_effect (unittest.mock approach)
from unittest.mock import MagicMock, call

original_copytree = shutil.copytree

def side_effect(src, dst, **kwargs):
    Path(dst).mkdir(parents=True, exist_ok=True)
    raise FileExistsError(f"[Errno 17] File exists: '{dst}'")

mock_copytree = MagicMock(side_effect=[side_effect, original_copytree])
# However: side_effect as list requires exact call sequence, less flexible

# Option 3: Create a MockCopytree class
class MockCopytreeFailOnce:
    def __init__(self, original_copytree):
        self.original = original_copytree
        self.call_count = 0

    def __call__(self, src, dst, **kwargs):
        self.call_count += 1
        if self.call_count == 1:
            Path(dst).mkdir(parents=True, exist_ok=True)
            raise FileExistsError(f"[Errno 17] File exists: '{dst}'")
        return self.original(src, dst, **kwargs)

monkeypatch.setattr(shutil, "copytree", MockCopytreeFailOnce(original_copytree))
assert MockCopytreeFailOnce.call_count == 2  # via instance
```

**Recommended**: Option 1 (helper function) for readability + reusability, or Option 3 (class) if this pattern is used across multiple tests.
