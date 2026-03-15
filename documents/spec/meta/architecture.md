---
Created: 2026-02-21
Updated: 2026-03-16
Checked: -
Deprecated: -
Format: spec-v2.1
Source: Multiple files (architecture overview)
---

# ClaudeUsageTracker Architecture

## 0. Meta

| Source | Runtime |
|--------|---------|
| code/app/ClaudeUsageTracker/ClaudeUsageTrackerApp.swift | macOS |
| code/app/ClaudeUsageTracker/UsageViewModel.swift | macOS |
| code/app/ClaudeUsageTracker/WebViewCoordinator.swift | macOS |

| Field | Value |
|-------|-------|
| Related | spec/ui/app-windows.md, spec/data/usage-fetcher.md, spec/meta/viewmodel-lifecycle.md |
| Test Type | - |

## Data Retrieval Approach

Approach C (WebView + claude.ai internal API) is adopted.
See `decisions/usage-data-approaches.md` for the decision rationale and comparison with other approaches.
See `reference/api-response.md` for API response field names.

## Data Flow

```
App launch
  → UsageViewModel.init()
  → Set Coordinator as delegate
  → Start cookie observation (CookieChangeObserver)
  → Load usage URL in WebView
  → didFinish → handlePageReady()
  → Check sessionKey cookie → if present, isLoggedIn=true
  → Check lastActiveOrg cookie → if present, fetchSilently()
  → If absent, navigate to usage page (5-second cooldown)
  → On success → start timer
  → No cookie → wait (login screen is displayed)

Login window display
  → LoginWebView simply displays the webView (no delegate setup)
  → The ViewModel's Coordinator always handles delegation

After OAuth login
  → CookieChangeObserver detects cookie change
  → Check sessionKey cookie → isLoggedIn=true
  → isAutoRefreshEnabled=true → navigate to usage page
  → didFinish → handlePageReady() → fetchSilently() → display data
```

## File Structure

```
code/app/ClaudeUsageTracker/
├── ClaudeUsageTrackerApp.swift              # Entry point, Scene definitions, AppDelegate
├── MenuContent.swift               # Dropdown menu UI
├── MenuBarLabel.swift              # Menu bar label + MenuBarGraphsContent
├── MiniUsageGraph.swift            # Canvas graph drawing (36x14pt)
├── LoginWindowView.swift           # Login window + OAuth popup UI
├── AnalysisWindowView.swift        # Analysis window (WKWebView)
├── UsageViewModel.swift            # State management, fetch control, auto-refresh
├── UsageViewModel+Session.swift    # Cookie observation/backup, login polling, sign out
├── UsageViewModel+Settings.swift   # Settings mutation methods, login item management
├── WebViewCoordinator.swift        # WKNavigationDelegate + WKUIDelegate + CookieChangeObserver
├── UsageFetcher.swift              # Org ID retrieval (cookie + JS) + usage API fetch + JSON parsing
├── LoginWebView.swift              # NSViewRepresentable (thin WKWebView wrapper)
├── UsageStore.swift                # SQLite3-based fetch history storage
├── Settings.swift                  # JSON settings file read/write
├── AnalysisExporter.swift          # Load analysis.html from bundle resources
├── AnalysisSchemeHandler.swift     # cut:// scheme handler (SQLite → JSON)
├── AlertChecker.swift              # Alert threshold evaluation + duplicate notification prevention
├── NotificationManager.swift       # UNUserNotificationCenter wrapper
├── Resources/analysis.html         # Analysis page HTML/CSS/JS (Chart.js)
├── Info.plist                      # LSUIElement=true (hidden from Dock)
└── ClaudeUsageTracker.entitlements          # App Sandbox disabled + App Group (widget data sharing)
```

## Components

| File | Responsibility |
|------|----------------|
| `ClaudeUsageTrackerApp` | SwiftUI App, MenuBarExtra, Window scenes, AppDelegate |
| `MenuBarLabel` | Menu bar label: Canvas graph → ImageRenderer → NSImage |
| `MenuBarGraphsContent` | Two graphs (5h / 7d) arranged in an HStack |
| `MiniUsageGraph` | Canvas-drawn usage bar (width represents %) + time progress marker (vertical line) at 36x14pt |
| `MenuContent` | Dropdown menu: usage %, remaining time, Visit Usage Page, settings |
| `UsageViewModel` | @Published state, Coordinator (navigation + OAuth), cookie observation, fetch/signOut, Timer, settings management, time progress calculation |
| `UsageFetcher` | Retrieve org ID from cookies (JS fallback) → fetch /usage API → return UsageResult |
| `LoginWebView` | NSViewRepresentable wrapper for WKWebView (no logic) |
| `UsageStore` | INSERT into usage_log table via SQLite3 C API |
| `Settings` | AppSettings struct + SettingsStore (JSON read/write, validation) |
| `AnalysisExporter` | Load analysis.html from bundle, serve to WKWebView (AnalysisWindowView) |
| `AlertChecker` | Weekly/Hourly/Daily threshold evaluation + per-session duplicate notification prevention |
| `NotificationManager` | UNUserNotificationCenter wrapper (requestAuthorization, send) |

## Design Decisions

### WKWebView Ownership

UsageViewModel owns a single WKWebView instance, shared between the login UI and API fetching.
LoginWebView merely displays this webView — it neither sets delegates nor creates instances.

### Delegate Placement

WebViewCoordinator (WKNavigationDelegate + WKUIDelegate) is owned by UsageViewModel.
Delegates are set in init() and maintained throughout the app's lifecycle.

In v0.1.0, the delegate was placed inside LoginWebView, but this caused the delegate to be unset during background fetches at launch. It was therefore consolidated into the ViewModel.

### Org ID Retrieval + API Fetch (Single JS Script Approach)

Org ID retrieval and API invocation are completed within a single JS script. No branching is needed on the Swift side.

The JS-based org ID retrieval uses a 4-stage fallback:
1. Extract the `lastActiveOrg` cookie from `document.cookie` via regex
2. Reverse-search `performance.getEntriesByType("resource")` for the `/api/organizations/{UUID}/` pattern
3. Search `document.documentElement.innerHTML` for the same UUID pattern via regex
4. Call `fetch("https://claude.ai/api/organizations")` and use the `uuid` or `id` field from the first element

Each stage's success or failure is recorded in a `diag` array (e.g., `"S1:OK"`, `"S2:MISS"`, `"S4:HTTP200"`), providing diagnostic information via error messages and the response's `__diag` field.

After obtaining the org ID, the same script calls the usage API via `fetch()`.
Session cookies are automatically sent with `credentials: "include"`.
Results are returned to Swift via `JSON.stringify()`.

In v0.1.0, the `/api/organizations` API was called directly but returned 403 errors, prompting a switch to the cookie/JS-based approach.
Previously, there were three separate stages in Swift: cookie → JS fallback → separate API call.
Based on insights from agentlimits-approach-extract.md, these were consolidated into a 4-stage fallback within a single JS script.

### API Response Parsing (Format A/B Dual Support)

The `/usage` API response exists in two formats, and the parser supports both.

**Detection logic**: If `json["windows"]` exists, it's Format B; otherwise, Format A.

**Format A** (current API):
- Top-level keys: `json["five_hour"]` / `json["seven_day"]`
- Usage: `utilization` field (direct percentage value)
- Reset time: `resets_at` (ISO 8601 string)

**Format B** (legacy format):
- Top-level keys: `json["windows"]["5h"]` / `json["windows"]["7d"]`
- Usage: calculated as `(limit - remaining) / limit * 100` (no `utilization` field)
- Reset time: `resets_at` (Unix seconds, converted via `Date(timeIntervalSince1970:)`)

Initially only Format A was supported, but Format B support was added based on the HTML/JS investigation results in `reference/api-response.md`. See `data/usage-fetcher.md` for detailed parsing logic.

### Menu Bar Graph Rendering

A Canvas-based `MiniUsageGraph` (36x14pt) is converted to NSImage via `ImageRenderer` and displayed in the MenuBarExtra label. It shows a usage bar (width represents %) plus a time progress marker (vertical line).
Colors change from green to orange to red based on usage level.

### Cookie Persistence

Uses `WKWebsiteDataStore(forIdentifier:)` (creates an app-specific persistent store with a fixed UUID). `.default()` is not used because it shares data with Safari and triggers an access permission prompt on every launch.

### Login Detection

- Cookie observation: Monitors cookie changes via `WKHTTPCookieStoreObserver` and detects login when the `sessionKey` cookie appears.
- Page ready: Detects claude.ai page load completion via the `didFinish` delegate.

In v0.1.0, isLoggedIn was set to true upon successful fetch, but this caused isLoggedIn to remain false when fetches silently failed at launch despite being logged in. This was changed to cookie-based detection.

### Navigation Control

- **Before login**: All navigation is allowed (for the OAuth flow).
- **After login**: Only claude.ai domain is allowed.
- Sub-resources (CSS, JS, images, etc.) are always allowed.

In v0.1.0, navigation was restricted to the usage page only, but now the entire claude.ai domain is allowed.

### Fetch Control (autoRefreshEnabled Approach)

The `pendingFetch` flag (single-use) was replaced with the `isAutoRefreshEnabled` flag.

- `nil` (undetermined): Attempt fetch when page ready
- `true`: Auto-refresh enabled. Fetch on timer tick.
- `false`: Auto-refresh disabled. Set on authentication errors (401, 403, Missing organization).

Manual Refresh is always available regardless of the isAutoRefreshEnabled value.

Changed based on insights from agentlimits-approach-extract.md. The previous `pendingFetch` would ignore events once set to false, with no retry mechanism.

### Redirect Control

After OAuth completion, claude.ai redirects to the chat page.
If logged in and not on the usage page, the app automatically navigates to the usage page.
A 5-second cooldown prevents infinite loops.

### OAuth Popup (Sheet Modal Approach)

When an OAuth provider (e.g., Google) requests a popup, it is displayed as a modal window using SwiftUI's `.sheet()`.

- `createWebViewWith` (WKUIDelegate) creates the popup WKWebView
- The popup's `didFinish` checks login status
- If logged in, the popup auto-closes after 0.5 seconds

Previously, `webView.addSubview()` was used to overlay on the main WebView.
Changed to sheet modal based on insights from agentlimits-approach-extract.md.

### Sign Out (Dual Deletion Approach)

1. Delete all data types from `webView.configuration.websiteDataStore`
2. Retrieve all cookies via `httpCookieStore.getAllCookies` and delete each individually
3. Reload the usage page

Previously, only records containing `"claude"` were deleted, but this risked missed deletions.
Changed to full deletion + individual deletion based on insights from agentlimits-approach-extract.md.

### Launch at Login

Uses `SMAppService.mainApp` to toggle register/unregister.

## Entitlements

App Sandbox is **disabled**. App Group is used for widget data sharing.

```xml
<key>com.apple.security.app-sandbox</key>
<false/>
<key>com.apple.security.application-groups</key>
<array>
    <string>group.grad13.claudeusagetracker</string>
</array>
```

### Reasons for Disabling App Sandbox

1. **Cookie persistence**: `xcodebuild` CLI builds produce different ad-hoc signatures each time, causing the Sandbox container to be regenerated and cookies to be lost (discovered in v0.1.0).
2. **File access**: Need to access JSONL files in `~/.claude/projects/`. With Sandbox ON, `homeDirectoryForCurrentUser` returns the container path, requiring a `getpwuid` hack (discovered in v0.3.0).
3. **Not distributed via Mac App Store**: Direct distribution means Sandbox is optional.
4. **Same configuration as AgentLimits**: The reference project also has Sandbox OFF for the main app.

The widget extension (`ClaudeUsageTrackerWidget`) remains Sandbox ON. WidgetKit effectively requires Sandbox.
Detailed investigation: `reports/sandbox-data-sharing.md`

## Unverified Items (as of 2026-02-21)

The following require real-device testing. **All are unverified.**
See `archive/phase1-verification-plan.md` for detailed analysis.

- [ ] Login persistence after reboot (cookie persistence)
- [ ] Data retrieval from the usage API (field name verification → `reference/api-response.md`)
- [ ] OAuth popup behavior (Google OAuth WKWebView blocking issue)
- [ ] Redirect control after login
- [ ] Org ID retrieval (cookie + JS fallback)

Verification priority: OAuth → Redirect → Org ID → API → Cookie (failure at step 1 blocks all subsequent steps)

## Bundle ID

`grad13.claudeusagetracker`

## Build

```bash
xcodebuild -scheme ClaudeUsageTracker -destination 'platform=macOS' build
```

## Related Specifications

- [App Windows (URL scheme, Window definitions, menu bar label, graph UI)](../ui/app-windows.md)
- [UsageFetcher (UsageResult, error types, parsing, org ID retrieval)](../data/usage-fetcher.md)
- [ViewModel Lifecycle (init, fetch, cookie, login, sign out)](viewmodel-lifecycle.md)
