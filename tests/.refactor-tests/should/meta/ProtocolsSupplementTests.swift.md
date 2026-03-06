# ProtocolsSupplementTests.swift — should refactor

- **File**: `tests/ClaudeUsageTrackerTests/meta/ProtocolsSupplementTests.swift` (79 lines)
- **Criteria**: S6 (複数モジュール import)

## S6: 複数モジュール import

- `import ClaudeUsageTrackerShared`
- `@testable import ClaudeUsageTracker`

Two modules are imported. Protocol conformance tests for `SettingsStore` / `UsageStore` use concrete types from the main app module and shared types from the shared module. Consider whether tests can be scoped to a single module or if cross-module conformance testing is intentional and justified.
