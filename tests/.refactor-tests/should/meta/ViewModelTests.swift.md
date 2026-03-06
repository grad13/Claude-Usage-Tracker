# ViewModelTests.swift -- should refactor

- **File**: `tests/ClaudeUsageTrackerTests/meta/ViewModelTests.swift` (259 lines)
- **Criteria hit**: S6, S7

## S6: Multiple modules

Imports both `ClaudeUsageTrackerShared` and `@testable import ClaudeUsageTracker`. The test couples to two separate module boundaries, meaning changes in either module can break these tests.

## S7: Hand-written partial mocks

Six hand-written test doubles are instantiated in `setUp()`:

- `StubUsageFetcher`
- `InMemorySettingsStore`
- `InMemoryUsageStore`
- `InMemoryWidgetReloader`
- `InMemoryLoginItemManager`
- `MockAlertChecker`

All defined in `ViewModelTestDoubles.swift`. Each conforms to a protocol and is manually maintained. The factory `ViewModelTestFactory.makeVM(...)` wires them together. While test doubles are centralized in one file (good), the sheer count (6) increases coupling surface and maintenance burden when protocols change.
