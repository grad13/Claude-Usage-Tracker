---
Created: 2026-03-03
Updated: 2026-03-06
Checked: -
Deprecated: -
Format: spec-v2.1
Source: code/ClaudeUsageTracker/UsageViewModel+Session.swift
---

# UsageViewModel Session Management

## 0. Meta

| Source | Runtime |
|--------|---------|
| code/ClaudeUsageTracker/UsageViewModel+Session.swift | macOS |

| Field | Value |
|-------|-------|
| Related | spec/meta/viewmodel-lifecycle.md, spec/data/usage-fetcher.md |
| Test Type | Unit |

## handleSessionDetected() — Unified Entry Point for Login Detection

`handleSessionDetected()` is the unified entry point for login detection, invoked from three distinct paths.

### Invocation Paths

```
Path 1: Cookie Observer
  cookiesDidChange → hasValidSession check → handleSessionDetected()

Path 2: Login Polling (3-second interval)
  Timer tick → hasValidSession check → handleSessionDetected()

Path 3: OAuth Popup Close
  webViewDidClose → handlePopupClosed() → 1-second wait → hasValidSession check → handleSessionDetected()
```

### Guard

Returns immediately if `isLoggedIn == true` (idempotency guarantee).
This prevents duplicate processing even when all three paths fire simultaneously.

### State Transition (Order Guaranteed)

```
handleSessionDetected()
  +-- guard !isLoggedIn else { return }     ← Idempotency guard
  +-- isLoggedIn = true                      ← Transition to logged-in state
  +-- isAutoRefreshEnabled = nil             ← Reset to undetermined (next handlePageReady will evaluate)
  +-- loginPollTimer?.invalidate()           ← Stop login polling
  +-- loginPollTimer = nil
  +-- backupSessionCookies()                 ← Back up cookies to App Group
  +-- startAutoRefresh()                     ← Start auto-refresh timer
  +-- guard canRedirect() else { return }    ← 5-second cooldown check
  +-- lastRedirectAt = Date()                ← Record redirect time
  +-- loadUsagePage()                        ← Navigate to usage page
```

### Design Intent

- Resetting `isAutoRefreshEnabled` to nil allows the next `handlePageReady()` call to re-evaluate session validity.
- Executing `backupSessionCookies()` before the redirect ensures cookies are saved even if the navigation fails.
- The `canRedirect()` guard ensures that even with multiple rapid invocations (e.g., cookie observation + polling racing), the usage page navigation occurs only once.

### Difference from handlePageReady()

- `handlePageReady()` is called "after a page has loaded" and executes `fetchSilently()` if already on the usage page.
- `handleSessionDetected()` is called "the moment a session cookie is detected" and navigates to the usage page.
- They are complementary: handleSessionDetected() → loadUsagePage() → didFinish → handlePageReady() → fetchSilently()

## Cookie Backup/Restore

Cookie persistence via `WKWebsiteDataStore(forIdentifier:)` is lost upon app reinstallation. Cookies are backed up as a JSON file to the App Group container, enabling restoration after reinstallation.

### CookieData Struct

`CookieData`, defined in `UsageViewModel+Session.swift`, is a Codable struct used for cookie backup and restore via App Group.

```swift
struct CookieData: Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresDate: Double?   // Date.timeIntervalSince1970. nil = session cookie
    let isSecure: Bool
}
```

| Field | Type | Nullable | Description |
|-------|------|----------|-------------|
| `name` | `String` | No | Cookie name |
| `value` | `String` | No | Cookie value |
| `domain` | `String` | No | Cookie domain (e.g., `.claude.ai`) |
| `path` | `String` | No | Cookie path (e.g., `/`) |
| `expiresDate` | `Double?` | Yes | UNIX timestamp (seconds). nil = session cookie (expires when browser closes) |
| `isSecure` | `Bool` | No | Whether the `Secure` attribute is set |

Constant:

```swift
static let cookieBackupName = "session-cookies.json"
```

File name used by both `backupSessionCookies()` and `restoreSessionCookies()`.

Conversion rules (HTTPCookie <-> CookieData):

- **Backup (HTTPCookie → CookieData)**: `expiresDate` is `HTTPCookie.expiresDate?.timeIntervalSince1970` (nullable), `isSecure` is `HTTPCookie.isSecure`
- **Restore (CookieData → HTTPCookieProperties)**: If `expiresDate` is non-nil and in the past → skip cookie (expired). If `expiresDate` is non-nil and in the future → set `.expires` key to `Date(timeIntervalSince1970: exp)`. If `isSecure == true` → set `.secure` key to `"TRUE"`

### Backup (backupSessionCookies)

- **Timing**: Runs on every login success within `handleSessionDetected()`
- **Filter**: Only cookies whose `domain` ends with `claude.ai`
- **Destination**: `AppGroupConfig.containerURL` / `Library/Application Support` / `AppGroupConfig.appName` / `session-cookies.json`
- **Format**: JSON array of `CookieData` structs (name, value, domain, path, expiresDate, isSecure)
- **expiresDate**: Stored as `Date.timeIntervalSince1970` (Double). nil for session cookies.

### Restore (restoreSessionCookies)

- **Timing**: At app launch (depends on call site of `restoreSessionCookies()`)
- **Return value**: `async -> Bool` (returns `true` if at least one cookie was restored)
- **Expired cookie handling**: Cookies with `expiresDate` at or before the current time are skipped
- **Restore target**: Set individually via `setCookie()` on `webView.configuration.websiteDataStore.httpCookieStore`
- **Secure attribute**: When `isSecure == true`, sets `HTTPCookiePropertyKey.secure: "TRUE"`

### Directory Structure

```
{App Group Container}/
+-- Library/Application Support/
    +-- {AppGroupConfig.appName}/
        +-- session-cookies.json
```

## Login Polling

In SPA navigation (e.g., client-side transitions after OAuth completion), the `didFinish` delegate may not fire. Cookie changes may also go undetected during SPA internal state changes. Login Polling serves as a fallback to bridge these gaps.

### Specification

- **Interval**: 3 seconds (`Timer.scheduledTimer(withTimeInterval: 3, repeats: true)`)
- **Start condition**: Only when `loginPollTimer == nil` (guard against double-start)
- **Stop condition**: `invalidate()` + nil assignment within `handleSessionDetected()`
- **Evaluation**: Calls `handleSessionDetected()` when `fetcher.hasValidSession(using: webView)` returns `true`
- **Guard**: Checks `!self.isLoggedIn` within the polling tick; no-op if already logged in

### Login Detection Paths Overview

| Path | Trigger | Purpose |
|------|---------|---------|
| Cookie observation | `WKHTTPCookieStoreObserver`'s `cookiesDidChange` | Immediate detection of cookie changes |
| Login Polling | 3-second interval timer | Fallback when cookie changes aren't detected during SPA navigation |
| Popup page completion | WebViewCoordinator's `didFinish` (popup) | Immediate login detection within popup → `closePopup()` |
| Popup close | `webViewDidClose` (`closePopup()` or manual close) | Wait for cookie propagation after popup closure (1 second) |

All four paths ultimately call `handleSessionDetected()`.

> **Popup page completion → Popup close chain**: `checkPopupLogin()` → 500ms → `closePopup()` → `webViewDidClose` → `handlePopupClosed()` → 1000ms → `handleSessionDetected()`. The `isLoggedIn` guard within `handleSessionDetected()` prevents duplicate processing.

### checkPopupLogin 500ms Wait Specification

`checkPopupLogin()` is called by WebViewCoordinator when a popup page finishes loading.

```swift
func checkPopupLogin() {
    Task {
        let isLoggedIn = await fetcher.hasValidSession(using: webView)
        if isLoggedIn {
            try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms
            closePopup()
        }
    }
}
```

Purpose of the wait: When `hasValidSession` returns true after an OAuth popup finishes loading, calling `closePopup()` immediately would prevent the user from seeing the popup's content (e.g., "Login successful" feedback). The 500ms delay gives the user time to see the success state.

Related 1-second wait (handlePopupClosed):

```swift
func handlePopupClosed() {
    Task {
        try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1000ms
        let hasSession = await fetcher.hasValidSession(using: webView)
        if hasSession { handleSessionDetected() }
    }
}
```

This 1-second wait provides time for cookies to propagate to the browser's cookie store. After OAuth completion, cookie writes happen asynchronously, so checking immediately might find the cookie not yet present.

Comparison of the two waits:

| Method | Wait Duration | Purpose | Timing |
|--------|--------------|---------|--------|
| `checkPopupLogin()` | 500ms | Ensure visual feedback for the user | After session check, before closePopup |
| `handlePopupClosed()` | 1000ms | Allow time for cookie propagation | Before session check |

## signOut() Widget Integration

### Full Sign-Out Processing

```
signOut()
  +-- Stop and nil-out refreshTimer
  +-- Reset all @Published state
  |   +-- isLoggedIn = false
  |   +-- isAutoRefreshEnabled = nil
  |   +-- lastRedirectAt = nil
  |   +-- fiveHourPercent = nil
  |   +-- sevenDayPercent = nil
  |   +-- fiveHourResetsAt = nil
  |   +-- sevenDayResetsAt = nil
  |   +-- error = nil
  +-- widgetReloader.reloadAllTimelines()    ← Request widget timeline reload
  +-- WebView data deletion (3 stages)
      +-- Stage 1: removeData(allWebsiteDataTypes, distantPast)
      +-- Stage 2: getAllCookies → delete each cookie individually
      +-- Stage 3: loadUsagePage() + startLoginPolling()
```

### Widget Integration Details

| Method | Responsibility |
|--------|----------------|
| `widgetReloader.reloadAllTimelines()` | Calls `WidgetCenter.shared.reloadAllTimelines()` to request immediate timeline reconstruction. |

### Execution Order Rationale

`reloadAllTimelines()` runs before WebView data deletion (an async callback chain), so the widget updates immediately without waiting for the WebView cleanup to complete. Stage 3 includes `startLoginPolling()` to begin detecting the next login.
