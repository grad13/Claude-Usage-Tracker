# tests

Automated tests for ClaudeUsageTracker, split by language/runtime.

## Directory Structure

```
tests/
├── ClaudeUsageTrackerTests/   # Swift XCTest for the app
│   ├── ui/ analysis/ widget/ shared/ predict/ data/ meta/
├── tools/                     # Python pytest for the build/deploy pipeline
│                              #   (covers code/tools/: build_and_install, rollback, lib/…)
└── pytest.ini                 # pytest config (rootdir for the Python suite)
```

## How to run

```bash
# Swift (XCTest target ClaudeUsageTrackerTests, wired into the shared scheme)
xcodebuild test -project code/app/ClaudeUsageTracker.xcodeproj \
  -scheme ClaudeUsageTracker -destination 'platform=macOS'

# Python tooling tests
cd tests && python3 -m pytest
```

## Naming convention

Source-mirrored — `ClaudeUsageTrackerTests/` mirrors the app's source layout;
`tools/` mirrors `code/tools/`. Python test files follow pytest's `test_*.py`.
**No date prefix** (these are living tests, not dated documents).
