---
Created: 2026-02-26
Updated: 2026-03-14
Checked: -
Deprecated: -
Format: spec-v2.1
Source: code/ClaudeUsageTracker/UsageViewModel.swift, code/ClaudeUsageTracker/UsageViewModel+Session.swift, code/ClaudeUsageTracker/UsageViewModel+Settings.swift, code/ClaudeUsageTracker/UsageViewModel+Debug.swift
---

# UsageViewModel Lifecycle

## 0. Meta

| Source | Runtime |
|--------|---------|
| code/ClaudeUsageTracker/UsageViewModel.swift | macOS |
| code/ClaudeUsageTracker/UsageViewModel+Session.swift | macOS |
| code/ClaudeUsageTracker/UsageViewModel+Settings.swift | macOS |
| code/ClaudeUsageTracker/UsageViewModel+Debug.swift | macOS |

| Field | Value |
|-------|-------|
| Related | spec/meta/viewmodel-session.md, spec/data/usage-fetcher.md, spec/meta/architecture.md |
| Test Type | Unit |

## init() Initialization Sequence

`UsageViewModel.init()` performs initialization in the following order. Everything runs on `@MainActor`.

```
1. Dependency injection (6 protocols + optional WKWebViewConfiguration)
   - fetcher: UsageFetching
   - settingsStore: SettingsStoring
   - usageStore: UsageStoring
   - widgetReloader: WidgetReloading
   - loginItemManager: LoginItemManaging
   - alertChecker: AlertChecking
   - webViewConfiguration: WKWebViewConfiguration? (nil = production default)

2. WKWebView creation
   - If webViewConfiguration is provided, use it directly (tests pass .nonPersistent() to avoid touching real cookie store)
   - Otherwise, create production config:
     - Generate app-specific data store via WKWebsiteDataStore(forIdentifier: UUID)
       → .default() is avoided because it shares data with Safari and triggers macOS TCC prompts
     - UUID is a fixed value "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
     - javaScriptCanOpenWindowsAutomatically = true (for OAuth popups)

3. Load settings
   - settingsStore.load() → AppSettings

4. Coordinator setup
   - Create WebViewCoordinator and set it as webView's navigationDelegate / uiDelegate

5. Synchronous operations (executed sequentially)
   a. reloadHistory()              ← Load history from SQLite into memory
   b. SQLiteBackup.perform()       ← Back up usage DB (details below)
   c. syncLoginItem()              ← Sync auto-launch setting via SMAppService
   d. startCookieObservation()     ← Register WKHTTPCookieStoreObserver

6. Asynchronous operations (Task)
   a. restoreSessionCookies()      ← Restore cookies from App Group
   b. loadUsagePage()              ← Load claude.ai in WebView
   c. startLoginPolling()          ← Start login detection polling at 3-second intervals
```

## SQLiteBackup at Launch

SQLite database backup is performed in init() step 5b.

- **Target DB**: usage DB (`usageStore.dbPath`)
- **Timing**: Once at app launch (synchronous within init)
- **Retention period**: 3 days (handled by SQLiteBackup logic)

## fetch() vs fetchSilently() Differences

Both methods call `fetcher.fetch(from: webView)`, but differ in the following ways.

| Aspect | fetch() | fetchSilently() |
|--------|---------|------------------|
| **Trigger** | Manual (Refresh button), auto-refresh | Automatic (at launch, after login) |
| **isAutoRefreshEnabled guard** | None (always executes) | None (guard is in startAutoRefresh) |
| **Additional processing on success** | None | Calls `backupSessionCookies()` |
| **Error display** | Always sets `self.error` | Sets `self.error` only when `isLoggedIn == true` |
| **On auth error** | `isAutoRefreshEnabled = false` | Same |
| **Retry on failure** | No | Yes (non-auth errors only, exponential backoff) |
| **Debug logging** | None | Logs start, success, errors, and retries |

### fetchSilently() Retry Logic

On non-auth errors, `fetchSilently()` automatically retries with exponential backoff:

| Retry # | Delay | Total elapsed |
|---------|-------|---------------|
| 1 | 30s | 30s |
| 2 | 60s | 1m 30s |
| 3 | 120s | 3m 30s |

- **Max retries**: 3 (`maxRetries`)
- **Auth errors**: No retry (user must re-authenticate)
- **On success**: `retryCount` reset to 0
- **After max retries**: `retryCount` reset to 0, error remains displayed
- **Concurrency**: `isFetching` is set to `false` before the sleep, so manual `fetch()` can proceed. However, `fetchSilently()` re-checks `isFetching` guard on retry.
- **Task cancellation**: `Task.sleep` respects cancellation (e.g., app backgrounding)

Shared success processing (within `applyResult`, 4 phases):
1. Update `@Published` properties (5h/7d percent, resetsAt)
2. Save to SQLite via `usageStore.save(result)` + `reloadHistory()`
3. Evaluate thresholds and send notifications via `alertChecker.checkAlerts(result:settings:)`
4. Update widget via `widgetReloader.reloadAllTimelines()`

## statusText Calculation Logic

```swift
var statusText: String {
    let fiveH = fiveHourPercent.map { String(format: "%.0f%%", $0) } ?? "--"
    let sevenD = sevenDayPercent.map { String(format: "%.0f%%", $0) } ?? "--"
    return "5h: \(fiveH) / 7d: \(sevenD)"
}
```

- Displays `"--"` when `fiveHourPercent` / `sevenDayPercent` is nil
- When non-nil, shows integer percentage with no decimal places (e.g., `"73%"`)
- Format: `"5h: {value} / 7d: {value}"`

## timeProgress Calculation Logic

```swift
static func timeProgress(resetsAt: Date?, windowSeconds: TimeInterval, now: Date = Date()) -> Double
```

Returns the X-axis position (time progress) for the menu bar graph as a value from 0.0 to 1.0.

- **Input**: `resetsAt` (scheduled reset time), `windowSeconds` (window duration: 5h=18000s, 7d=604800s)
- **Formula**: `elapsed = windowSeconds - resetsAt.timeIntervalSince(now)`, `progress = elapsed / windowSeconds`
- **Clamping**: `min(max(..., 0.0), 1.0)` constrains the result to 0.0 - 1.0
- **When resetsAt is nil**: Returns `0.0`
- **Meaning**: The fraction of time elapsed since the window started. resetsAt is the window end, now is the current position.

Derived properties:
- `fiveHourTimeProgress`: `timeProgress(resetsAt: fiveHourResetsAt, windowSeconds: 5 * 3600)`
- `sevenDayTimeProgress`: `timeProgress(resetsAt: sevenDayResetsAt, windowSeconds: 7 * 24 * 3600)`

## remainingTimeText Calculation Logic

```swift
func remainingTimeText(for resetsAt: Date?) -> String? {
    guard let resetsAt else { return nil }
    return DisplayHelpers.remainingText(until: resetsAt)
}
```

- Returns nil when `resetsAt` is nil
- Otherwise delegates to `DisplayHelpers.remainingText(until:)` (formatting details are in the DisplayHelpers spec)
- Derived: `fiveHourRemainingText`, `sevenDayRemainingText`

## debug() Logging Specification

```swift
func debug(_ message: String)
```

Records logs using a dual-output approach.

1. **NSLog**: Outputs to macOS unified log with format `[ClaudeUsageTracker] {message}`
2. **File**: Appends to a temporary file with format `{ISO8601 timestamp} {message}\n`

Log file details:
- **Path**: `FileManager.default.temporaryDirectory` / `ClaudeUsageTracker-debug.log`
- **Lifecycle**: Initialized as an empty file at app launch (writes `""` during `logURL` lazy initialization)
- **Writing**: Appends at end of file via FileHandle. Creates the file if it doesn't exist.
- **Timestamp**: Default `ISO8601DateFormatter()` format (e.g., `2026-02-26T12:34:56Z`)
- **Rotation**: None (cleared on each launch)

## @Published Properties

| Property | Type | Initial Value | Description |
|----------|------|---------------|-------------|
| `fiveHourPercent` | `Double?` | `nil` | 5-hour window usage (%) |
| `sevenDayPercent` | `Double?` | `nil` | 7-day window usage (%) |
| `fiveHourResetsAt` | `Date?` | `nil` | 5-hour window reset time |
| `sevenDayResetsAt` | `Date?` | `nil` | 7-day window reset time |
| `error` | `String?` | `nil` | Error message |
| `isFetching` | `Bool` | `false` | Fetching in progress flag |
| `isLoggedIn` | `Bool` | `false` | Login status |
| `settings` | `AppSettings` | `settingsStore.load()` | Application settings |
| `popupWebView` | `WKWebView?` | `nil` | OAuth popup WebView |
| `fiveHourHistory` | `[UsageStore.DataPoint]` | `[]` | 5-hour window history data |
| `sevenDayHistory` | `[UsageStore.DataPoint]` | `[]` | 7-day window history data |


## Internal State Properties (non-@Published)

| Property | Type | Description |
|----------|------|-------------|
| `coordinator` | `WebViewCoordinator?` | WebView delegate |
| `cookieObserver` | `CookieChangeObserver?` | Cookie change observer |
| `refreshTimer` | `Timer?` | Auto-refresh timer |
| `loginPollTimer` | `Timer?` | Login polling timer (3-second interval) |
| `isAutoRefreshEnabled` | `Bool?` | Auto-refresh state (nil=undetermined, true=enabled, false=disabled) |
| `lastRedirectAt` | `Date?` | Last redirect time (for 5-second cooldown) |
| `retryCount` | `Int` (private) | Current retry count for fetchSilently (0 when idle) |

## handlePageReady() Flow

`handlePageReady()` is called by `WebViewCoordinator.didFinish` when the main WebView finishes loading a page on `claude.ai` (see spec/meta/webview-coordinator.md for trigger conditions).

### Overview

Session cookie check → redirect if not on usage page → fetch if on usage page. All steps run inside a `Task` on `@MainActor`.

### Decision Flow

```
handlePageReady()
  +-- Task {
  |     +-- fetcher.hasValidSession(using: webView)
  |     |     +-- false → return (skip all subsequent steps)
  |     |     +-- true →
  |     |           +-- isLoggedIn = true
  |     |           +-- loginPollTimer?.invalidate() + set nil
  |     |           +-- startAutoRefresh()
  |     |           +-- backupSessionCookies()
  |     |           +-- isOnUsagePage()?
  |     |                 +-- false → canRedirect()?
  |     |                 |           +-- false → return (cooldown active)
  |     |                 |           +-- true →
  |     |                 |                 +-- lastRedirectAt = Date()
  |     |                 |                 +-- loadUsagePage()
  |     |                 |                 +-- return
  |     |                 +-- true → fetchSilently()
  |   }
```

### Decision Table

| Case ID | hasValidSession | isOnUsagePage | canRedirect | Action | Notes |
|---------|-----------------|---------------|-------------|--------|-------|
| PR-01 | false | - | - | return (no-op) | No session cookie; skip silently |
| PR-02 | true | true | - | fetchSilently() | On usage page; proceed to data fetch |
| PR-03 | true | false | true | loadUsagePage() | Not on usage page; redirect to claude.ai |
| PR-04 | true | false | false | return (no-op) | Redirect cooldown (5s) still active |

### Common Side Effects (PR-02, PR-03, PR-04)

When `hasValidSession` returns true (all cases except PR-01), the following side effects always execute before branching:

| Order | Side Effect | Description |
|-------|-------------|-------------|
| 1 | `isLoggedIn = true` | Update login state |
| 2 | `loginPollTimer` invalidate + nil | Stop login polling (no longer needed) |
| 3 | `startAutoRefresh()` | Start periodic auto-refresh timer (no-op if already running) |
| 4 | `backupSessionCookies()` | Persist session cookies to App Group for recovery |

### Redirect Cooldown (canRedirect)

```swift
func canRedirect() -> Bool {
    guard let lastRedirectAt else { return true }
    return Date().timeIntervalSince(lastRedirectAt) > 5
}
```

- **Cooldown duration**: 5 seconds
- **Purpose**: Prevent infinite redirect loops when WebView navigates away from claude.ai (e.g., OAuth flow landing on a different page)
- **First call**: Always returns true (`lastRedirectAt` is nil at launch)
- **Subsequent calls**: Returns true only if more than 5 seconds have elapsed since the last redirect
- `lastRedirectAt` is set to `Date()` immediately before calling `loadUsagePage()` in the redirect path

### isOnUsagePage Check

```swift
func isOnUsagePage() -> Bool {
    guard let url = webView.url else { return false }
    return url.host == Self.targetHost  // "claude.ai"
}
```

- Returns `true` when the WebView's current URL host is exactly `claude.ai`
- Returns `false` when the URL is nil or the host differs

### isAutoRefreshEnabled Interaction

`handlePageReady()` does not read or write `isAutoRefreshEnabled` directly. However:

- `startAutoRefresh()` (called in the common side effects) creates the timer, whose tick checks `isAutoRefreshEnabled != false`
- `fetchSilently()` (called in PR-02) sets `isAutoRefreshEnabled = true` on success, or `false` on auth error
- This means a successful `handlePageReady` → `fetchSilently` cycle establishes the auto-refresh as fully enabled

## Auto-Refresh Control Flow

```
startAutoRefresh()
  +-- refreshTimer already exists → no-op (prevents double-start)
  +-- refreshIntervalMinutes == 0 → no-op (disabled setting)
  +-- Timer.scheduledTimer(repeats: true)
       +-- tick → isAutoRefreshEnabled != false → fetch()

restartAutoRefresh()
  +-- Invalidate refreshTimer + set to nil
  +-- isLoggedIn == true → startAutoRefresh()
```

- Timer interval: `settings.refreshIntervalMinutes * 60` seconds
- Calling `setRefreshInterval(minutes:)` triggers `restartAutoRefresh()` to restart the timer
- If `isAutoRefreshEnabled == false` at tick time, fetch is skipped (prevents unnecessary retries after auth errors)

## Settings Mutation Methods

All 15 methods defined in `UsageViewModel+Settings.swift`. All run on `@MainActor` and follow a common pattern: "mutate `settings` → `settingsStore.save(settings)` → (optional side effect)".

### Common Pattern

```
settings.{field} = {value}
settingsStore.save(settings)
[side effect (optional)]
```

Methods without side effects complete after saving (saving is the only side effect).

### Method List and Side Effects

| Method | Modified Field | Side Effect |
|--------|---------------|-------------|
| `setGraphColorTheme(_:)` | `graphColorTheme` | Calls `widgetReloader.reloadAllTimelines()` |
| `setRefreshInterval(minutes:)` | `refreshIntervalMinutes` | Calls `restartAutoRefresh()` |
| `toggleStartAtLogin()` | `startAtLogin` (toggled) | Calls `syncLoginItem()` |
| `setShowHourlyGraph(_:)` | `showHourlyGraph` | None |
| `setShowWeeklyGraph(_:)` | `showWeeklyGraph` | None |
| `setChartWidth(_:)` | `chartWidth` | None |
| `setHourlyColorPreset(_:)` | `hourlyColorPreset` | Calls `widgetReloader.reloadAllTimelines()` |
| `setWeeklyColorPreset(_:)` | `weeklyColorPreset` | Calls `widgetReloader.reloadAllTimelines()` |
| `setWeeklyAlertEnabled(_:)` | `weeklyAlertEnabled` | None |
| `setWeeklyAlertThreshold(_:)` | `weeklyAlertThreshold` | None |
| `setHourlyAlertEnabled(_:)` | `hourlyAlertEnabled` | None |
| `setHourlyAlertThreshold(_:)` | `hourlyAlertThreshold` | None |
| `setDailyAlertEnabled(_:)` | `dailyAlertEnabled` | None |
| `setDailyAlertThreshold(_:)` | `dailyAlertThreshold` | None |
| `setDailyAlertDefinition(_:)` | `dailyAlertDefinition` | None |
| `syncLoginItem()` | (see below) | `loginItemManager.setEnabled()` + rollback |

### syncLoginItem Logic (Decision Table)

`syncLoginItem()` synchronizes the `settings.startAtLogin` state with the system's Login Item setting. If `loginItemManager.setEnabled(_:)` fails, it performs a rollback to prevent the UI from diverging from the actual system state.

#### Flow

```
syncLoginItem()
  +-- Attempt loginItemManager.setEnabled(settings.startAtLogin)
  |   +-- Success → no-op (settings already has the correct value)
  |   +-- Failure (throws) →
  |       +-- settings.startAtLogin.toggle()    ← Rollback (revert to pre-change value)
  |       +-- settingsStore.save(settings)      ← Persist the rolled-back value
  |       +-- self.error = "Login item failed: {error.localizedDescription}"
  |       +-- debug("syncLoginItem failed: {error}")
```

#### Decision Table

| `setEnabled` Result | Final `settings.startAtLogin` | `self.error` |
|---------------------|-------------------------------|--------------|
| Success | Changed value (already set before the call) | No change |
| Failure | Original value (rolled back via toggle) | Error message set |

#### Call Sites

- `toggleStartAtLogin()`: Called immediately after toggling `startAtLogin` via UI interaction
- `init()` step 5c: Called at launch to sync the setting value with the system state

#### Design Intent

If `loginItemManager.setEnabled()` fails without rolling back `settings.startAtLogin`, the UI (e.g., checkbox) would display a state that doesn't match the actual system state. The rollback maintains the invariant that "the state shown in the UI = the actual system state".
