---
updated: 2026-04-19 02:25
checked: -
Deprecated: -
Format: spec-v2.1
Source: code/app/ClaudeUsageTracker/UsageViewModel+Session.swift
---

# UsageViewModel Session Management

## 0. Meta

| Source | Runtime |
|--------|---------|
| code/app/ClaudeUsageTracker/UsageViewModel+Session.swift | macOS |

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
  +-- startAutoRefresh()                     ← Start auto-refresh timer
  +-- guard canRedirect() else { return }    ← 5-second cooldown check
  +-- lastRedirectAt = Date()                ← Record redirect time
  +-- loadUsagePage()                        ← Navigate to usage page
```

### Design Intent

- Resetting `isAutoRefreshEnabled` to nil allows the next `handlePageReady()` call to re-evaluate session validity.
- The `canRedirect()` guard ensures that even with multiple rapid invocations (e.g., cookie observation + polling racing), the usage page navigation occurs only once.
- **`loginPollTimer` is intentionally NOT stopped here.** Cookie detection is only an intermediate step — the page load and API fetch that follow can still fail. Only `applyResult()` (i.e. successful data fetch) stops the timer, so any failure between cookie detection and data arrival is automatically retried by the next polling tick.

### Difference from handlePageReady()

- `handlePageReady()` is called "after a page has loaded" and executes `fetchSilently()` if already on the usage page.
- `handleSessionDetected()` is called "the moment a session cookie is detected" and navigates to the usage page.
- They are complementary: handleSessionDetected() → loadUsagePage() → didFinish → handlePageReady() → fetchSilently()

## Login Polling

In SPA navigation (e.g., client-side transitions after OAuth completion), the `didFinish` delegate may not fire. Cookie changes may also go undetected during SPA internal state changes. Login Polling serves as a fallback to bridge these gaps. It also acts as the universal retry path for **any** failure between cookie detection and successful data fetch (e.g., post-reboot network outage causing `loadUsagePage` to fail with NSURLErrorNotConnectedToInternet).

### Specification

- **Interval**: 3 seconds (`Timer.scheduledTimer(withTimeInterval: 3, repeats: true)`)
- **Start condition**: Only when `loginPollTimer == nil` (guard against double-start)
- **Stop condition**: `invalidate()` + nil assignment **only inside `applyResult()`** (i.e. successful data fetch). Cookie detection alone does NOT stop the timer.
- **Tick logic** (3-way branch, evaluated each tick):
  1. `fiveHourPercent != nil && sevenDayPercent != nil` → early return (data already fetched; stragglers before invalidate land here)
  2. `hasValidSession == false` → wait (no cookie yet)
  3. `hasValidSession == true && !isLoggedIn` → call `handleSessionDetected()` (transitions to logged-in + redirects to usage page)
  4. `hasValidSession == true && isLoggedIn` → call `loadUsagePage()` (logged in but data not yet fetched; previous load likely failed). Also clears `lastRedirectAt` so `canRedirect()` cooldown does not block the retry.

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
