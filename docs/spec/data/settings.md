---
Created: 2026-02-21
Updated: 2026-03-07
Checked: -
Deprecated: -
Format: spec-v2.1
Source: code/ClaudeUsageTracker/Settings.swift, code/ClaudeUsageTracker/UsageViewModel+Settings.swift
---

# Specification: Settings

## 0. Meta

| Source | Runtime |
|--------|---------|
| code/ClaudeUsageTracker/Settings.swift | macOS |
| code/ClaudeUsageTracker/UsageViewModel+Settings.swift | macOS |

| Field | Value |
|-------|-------|
| Related | spec/ui/menu-content.md, spec/data/usage-store.md |
| Test Type | Unit |

## Settings File

- Path: `{App Group container}/Library/Application Support/{AppGroupConfig.appName}/settings.json`
- App Group: `group.grad13.claudeusagetracker` (obtained via `AppGroupConfig.containerURL`)
- If `AppGroupConfig.containerURL` cannot be obtained, `fatalError` is triggered
- Format: JSON (pretty-printed, sorted keys)
- Directory and file are created automatically on first launch

## SettingsStore Class Contract

```swift
final class SettingsStore {

    let fileURL: URL
    private let dirURL: URL

    init(fileURL: URL)

    static let shared: SettingsStore

    // Static convenience (delegates to shared)
    static func load() -> AppSettings
    static func save(_ settings: AppSettings)

    // Instance methods
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}
```

### shared singleton initialization logic

```
Normal environment:
  AppGroupConfig.containerURL
  -> {container}/Library/Application Support/{AppGroupConfig.appName}/settings.json

Test environment (DEBUG + XCTestConfigurationFilePath env var present):
  FileManager.default.temporaryDirectory/ClaudeUsageTracker-test-shared/settings.json
```

- In normal environment, if `AppGroupConfig.containerURL` is nil, crash immediately with `fatalError("[SettingsStore] App Group container not available")`

### load() behavior

1. If directory does not exist, create it via `ensureDirectory()`
2. If file does not exist: `save()` a default `AppSettings()` and return it
3. JSON decoding: `keyDecodingStrategy = .convertFromSnakeCase`
4. Apply `validated()` to the decoded result before returning
5. On decode error: log via `NSLog`, rename corrupt file to `.bak`, save defaults, and return `AppSettings()`

### save() behavior

1. Ensure directory via `ensureDirectory()`
2. `keyEncodingStrategy = .convertToSnakeCase`
3. `outputFormatting = [.prettyPrinted, .sortedKeys]`
4. Atomic write via `data.write(to: fileURL, options: .atomic)`
5. On error: `NSLog("[ClaudeUsageTracker] Settings save error: ...")` only (no exception thrown)

## Settings Fields

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `refresh_interval_minutes` | int | `5` | Auto-refresh interval in minutes. 0 disables auto-refresh |
| `start_at_login` | bool | `false` | Auto-launch on macOS login |
| `show_hourly_graph` | bool | `true` | Show 5-hour graph in menu bar |
| `show_weekly_graph` | bool | `true` | Show 7-day graph in menu bar |
| `chart_width` | int | `48` | Width of each menu bar graph (pt) |
| `hourly_color_preset` | string | `"blue"` | Color preset name for the 5-hour graph |
| `weekly_color_preset` | string | `"pink"` | Color preset name for the 7-day graph |
| `graph_color_theme` | string | `"dark"` | Color theme for graphs. `"system"`, `"light"`, or `"dark"` |
| `weekly_alert_enabled` | bool | `false` | Weekly alert ON/OFF |
| `weekly_alert_threshold` | int | `20` | Weekly alert threshold (remaining %). Range: 1-100 |
| `hourly_alert_enabled` | bool | `false` | Hourly alert ON/OFF |
| `hourly_alert_threshold` | int | `20` | Hourly alert threshold (remaining %). Range: 1-100 |
| `daily_alert_enabled` | bool | `false` | Daily alert ON/OFF |
| `daily_alert_threshold` | int | `15` | Daily alert threshold (usage %). Range: 1-100 |
| `daily_alert_definition` | string | `"calendar"` | Definition of "one day". `"calendar"` or `"session"` |

Note: JSON keys are stored in snake_case via `convertToSnakeCase` / `convertFromSnakeCase`.

### DailyAlertDefinition enum

| case | raw value | Description |
|------|-----------|-------------|
| `.calendar` | `"calendar"` | Midnight boundary in local timezone |
| `.session` | `"session"` | Weekly session-based (uses resets_at as reference) |

### Default settings file

```json
{
  "chart_width" : 48,
  "daily_alert_definition" : "calendar",
  "daily_alert_enabled" : false,
  "daily_alert_threshold" : 15,
  "hourly_alert_enabled" : false,
  "hourly_alert_threshold" : 20,
  "graph_color_theme" : "dark",
  "hourly_color_preset" : "blue",
  "refresh_interval_minutes" : 5,
  "show_hourly_graph" : true,
  "show_weekly_graph" : true,
  "start_at_login" : false,
  "weekly_alert_enabled" : false,
  "weekly_alert_threshold" : 20,
  "weekly_color_preset" : "pink"
}
```

## refresh_interval_minutes

Specifies the auto-refresh interval in minutes.

- **0**: Auto-refresh disabled (manual refresh via Cmd+R only)
- **1 or greater**: Fetch at the specified interval
- **Negative values**: Invalid. Falls back to default (5)

### Preset values

Selectable from the menu: 1, 2, 3, 5, 10, 20, 60 minutes

"Custom..." allows entering any integer value.

Defined as `AppSettings.presets`:

```swift
static let presets = [1, 2, 3, 5, 10, 20, 60]
```

## start_at_login

Whether to auto-launch the app on macOS login.

- **true**: Register via `loginItemManager.setEnabled(true)`
- **false**: Unregister via `loginItemManager.setEnabled(false)`

### Behavior flow

1. User clicks "Start at Login" in the menu
2. Toggle `settings.startAtLogin` and save to `settings.json`
3. Execute `loginItemManager.setEnabled()`
4. **On success**: Menu toggle checkmark updates immediately
5. **On failure**: Revert `settings.startAtLogin` (restore original value), save to `settings.json`, display error message in UI

```swift
func syncLoginItem() {
    do {
        try loginItemManager.setEnabled(settings.startAtLogin)
    } catch {
        settings.startAtLogin.toggle()  // revert
        settingsStore.save(settings)
        self.error = "Login item failed: \(error.localizedDescription)"
        debug("syncLoginItem failed: \(error)")
    }
}
```

### Sync on launch

On app launch, `loginItemManager.setEnabled()` is called based on the `start_at_login` value in `settings.json` to synchronize state. Even if the settings file was manually edited, the change takes effect on the next launch.

### LoginItemManaging protocol

`SMAppService.mainApp` is abstracted through the `LoginItemManaging` protocol rather than being referenced directly.

```swift
protocol LoginItemManaging {
    func setEnabled(_ enabled: Bool) throws
}
```

The production implementation `DefaultLoginItemManager` calls `SMAppService.mainApp.register()` / `.unregister()`:

```swift
struct DefaultLoginItemManager: LoginItemManaging {
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
```

- `UsageViewModel.init()` accepts `DefaultLoginItemManager()` as a default argument
- A mock can be injected for testing (`any LoginItemManaging` type)
- `setEnabled(_:)` is `throws`, and the caller `syncLoginItem()` handles failures via `do-catch`

### Why SMAppService is not referenced directly

Initially, `SMAppService.mainApp.status == .enabled` was used to determine UI state, but this had the following issues:

- With `xcodebuild` CLI builds (placed in DerivedData), `status` sometimes does not become `.enabled` even after a successful `register()` call
- `Toggle` inside `MenuBarExtra` does not detect changes to `SMAppService.mainApp.status`, preventing checkmark updates

**Solution**: Store `start_at_login` in the settings file (`settings.json`) and have the UI reference this value. `LoginItemManaging.setEnabled()` is executed as a side effect; on failure, the setting is reverted and an error is shown in the UI.

## show_hourly_graph / show_weekly_graph

Toggles for showing/hiding mini-graphs in the menu bar.

- **true**: Display the corresponding graph in the menu bar
- **false**: Hide it

ViewModel methods: `setShowHourlyGraph(_:)`, `setShowWeeklyGraph(_:)`. Setting changes are saved immediately.

## chart_width

Width of each menu bar graph in pt.

- **Validation**: Values below 12 or above 120 fall back to the default (48)
- Range is 12-120 (values outside presets are allowed, but extreme values are reset)

ViewModel method: `setChartWidth(_:)`.

### chartWidthPresets

Preset values for graph width selectable from the menu.

- Presets: 12, 24, 36, 48, 60, 72 (pt)
- Defined as: `AppSettings.chartWidthPresets`

```swift
static let chartWidthPresets = [12, 24, 36, 48, 60, 72]
```

## ChartColorPreset enum

`ChartColorPreset` is an `enum` defined in `Settings.swift`. It has a `String` raw value and conforms to `CaseIterable` and `Codable`.

| case | raw value | RGB | Default usage |
|------|-----------|-----|---------------|
| `.blue` | `"blue"` | (100, 180, 255) | 5-hour graph |
| `.pink` | `"pink"` | (255, 130, 180) | 7-day graph |
| `.green` | `"green"` | (70, 210, 80) | - |
| `.teal` | `"teal"` | (0, 210, 190) | - |
| `.purple` | `"purple"` | (150, 110, 255) | - |
| `.orange` | `"orange"` | (255, 160, 60) | - |
| `.white` | `"white"` | (230, 230, 230) | - |

Properties:
- `color: Color` -- returns a SwiftUI Color
- `displayName: String` -- English display name for UI (capitalized case name)
- `hexString: String` -- returns a CSS hex color string (e.g., `"#64b4ff"` for blue)

Encoded as a raw value string (e.g., `"blue"`) when saved to JSON.

ViewModel methods: `setHourlyColorPreset(_:)`, `setWeeklyColorPreset(_:)`. Both trigger `widgetReloader.reloadAllTimelines()` to immediately update the Widget.

## GraphColorTheme enum

`GraphColorTheme` is an `enum` defined in `Settings.swift`. It has a `String` raw value and conforms to `CaseIterable` and `Codable`.

| case | raw value | Description |
|------|-----------|-------------|
| `.system` | `"system"` | Follows macOS system appearance |
| `.light` | `"light"` | Light theme |
| `.dark` | `"dark"` | Dark theme |

Properties:
- `displayName: String` -- English display name for UI ("System", "Light", "Dark")
- `resolvedColorScheme() -> ColorScheme` -- resolves `.system` to `.light` or `.dark` based on `NSApp.effectiveAppearance`

ViewModel method: `setGraphColorTheme(_:)`. Triggers `widgetReloader.reloadAllTimelines()` to immediately update the Widget.

## Validation

### AppSettings.validated() method

```swift
/// Validate and return a corrected copy. Negative values reset to default.
func validated() -> AppSettings
```

Validation logic:
- `refreshIntervalMinutes < 0` -> reset to default (5)
- `chartWidth < 12 || chartWidth > 120` -> reset to default (48)
- `weeklyAlertThreshold` -> clamped via `max(1, min(100, value))`
- `hourlyAlertThreshold` -> clamped via `max(1, min(100, value))`
- `dailyAlertThreshold` -> clamped via `max(1, min(100, value))`

Note: `refreshIntervalMinutes == 0` is valid (auto-refresh disabled) and passes through.

Validation performed on file load:

| Condition | Behavior |
|-----------|----------|
| File does not exist | Create new file with defaults |
| JSON parse error (syntax, type mismatch) | Rename corrupt file to `.bak`, save defaults, return defaults. Log via NSLog |
| `refresh_interval_minutes` is negative | Fall back to default (5) |
| `refresh_interval_minutes` is 0 | Valid (auto-refresh disabled) |
| `start_at_login` is missing | Use default (false) |
| `show_hourly_graph` is missing | Use default (true) |
| `show_weekly_graph` is missing | Use default (true) |
| `chart_width` is missing | Use default (48) |
| `chart_width` is below 12 or above 120 | Fall back to default (48) |
| `hourly_color_preset` is missing or invalid string | Use default (`"blue"`) |
| `weekly_color_preset` is missing or invalid string | Use default (`"pink"`) |
| `graph_color_theme` is missing or invalid string | Use default (`"dark"`) |
| `weekly_alert_enabled` is missing | Use default (false) |
| `weekly_alert_threshold` below 1 | Clamp to 1 |
| `weekly_alert_threshold` above 100 | Clamp to 100 |
| `hourly_alert_enabled` is missing | Use default (false) |
| `hourly_alert_threshold` below 1 | Clamp to 1 |
| `hourly_alert_threshold` above 100 | Clamp to 100 |
| `daily_alert_enabled` is missing | Use default (false) |
| `daily_alert_threshold` below 1 | Clamp to 1 |
| `daily_alert_threshold` above 100 | Clamp to 100 |
| `daily_alert_definition` is missing or invalid string | Use default (`"calendar"`) |

### Decoder backward compatibility

`AppSettings.init(from:)` uses `decodeIfPresent` for all keys, applying default values for missing keys. Reading an older settings.json (where newer keys are absent) does not produce an error. This ensures smooth upgrades from older versions of the settings file.

The 7 alert-related fields added in v0.8.0 (`weekly_alert_enabled`, `weekly_alert_threshold`, `hourly_alert_enabled`, `hourly_alert_threshold`, `daily_alert_enabled`, `daily_alert_threshold`, `daily_alert_definition`) all fall back to defaults via `decodeIfPresent`.

No user notification is shown on error. Since each menu item reflects the current value, users can confirm whether their settings were applied there.

## Test path switching

When `SettingsStore.shared` is initialized, the test environment is detected and a temporary directory is used.

- Condition: `#if DEBUG` and the environment variable `XCTestConfigurationFilePath` exists
- Test path: `FileManager.default.temporaryDirectory/ClaudeUsageTracker-test-shared/settings.json`
- Prevents file mixing between production and test environments

## Related Specs

- [usage-store.md](usage-store.md) -- SQLite usage history storage (usage_log table, DataPoint, migration)
- [menu-content.md](../ui/menu-content.md) -- Dropdown menu UI (MenuContent, Graph Settings, Sign In/Out)
