# MenuContentSupplementTests.swift — Should Refactor

## Criterion: S6 — Multiple Modules in One Test File

**Location**: `/Users/takuo-h/Workspace/Code/2-experiments/24-ClaudeUsageTracker/tests/ClaudeUsageTrackerTests/MenuContentSupplementTests.swift`

**Issue**:
This test file covers multiple distinct modules/classes in a single file:
- `UsageViewModel` (main ViewModel)
- `AppSettings` (settings model)
- `ChartColorPreset` (enum)
- `DailyAlertDefinition` (enum)

**Current Structure** (lines 1–491):
- Tests for ViewModel properties and behavior
- Tests for AppSettings presets and defaults
- Tests for ChartColorPreset display names
- Tests for DailyAlertDefinition cases
- Tests for refresh interval logic
- Tests for alert threshold presets

**Recommendation**:
Split into focused test files by responsibility:
1. `UsageViewModelMenuSupplementTests.swift` — ViewModel-specific tests (refresh, fetch, error, login state)
2. `AppSettingsMenuSupplementTests.swift` — Settings presets, defaults, label formats
3. `MenuEnumSupplementTests.swift` — ChartColorPreset, DailyAlertDefinition, enum properties

**Benefit**:
- Faster test discovery and execution (smaller files run quicker)
- Easier to locate tests for a specific module
- Clearer test-to-module mapping
- Reduced cognitive load per test file
