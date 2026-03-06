---
Created: 2026-02-26
Updated: 2026-03-06
Checked: -
Deprecated: -
Format: spec-v2.1
Source: code/ClaudeUsageTracker/Protocols.swift
---

# Specification: Protocols (DI Protocols & Default Implementations)

## 0. Meta

| Source | Runtime |
|--------|---------|
| code/ClaudeUsageTracker/Protocols.swift | Swift |

| Field | Value |
|-------|-------|
| Related | spec/meta/architecture.md, spec/data/settings.md, spec/data/usage-store.md |
| Test Type | Unit |

## 1. Contract (Swift)

> AI Instruction: Treat these type definitions as the single source of truth. Use them for mocks and test types.

```swift
// MARK: - Settings

protocol SettingsStoring {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}

// SettingsStore conforms to SettingsStoring (extension declaration only, no additional methods)

// MARK: - Usage History

protocol UsageStoring {
    func save(_ result: UsageResult)
    func loadHistory(windowSeconds: TimeInterval) -> [UsageStore.DataPoint]
    func loadDailyUsage(since: Date) -> Double?
}

// UsageStore conforms to UsageStoring (extension declaration only, no additional methods)

// MARK: - Widget Data Sharing (note: no dedicated protocol)
//
// The widget reads usage data directly from usage.db via UsageReader (ClaudeUsageTrackerShared).
// The main app writes via UsageStore (UsageStoring protocol), and the widget reads via
// UsageReader.load() → UsageSnapshot. No SnapshotWriting protocol is needed because
// the write side is already covered by UsageStoring, and the read side (UsageReader)
// is a read-only utility in the Shared framework.

// MARK: - Usage Fetching

protocol UsageFetching {
    @MainActor func fetch(from webView: WKWebView) async throws -> UsageResult
    @MainActor func hasValidSession(using webView: WKWebView) async -> Bool
}

struct DefaultUsageFetcher: UsageFetching {
    // All methods delegate to UsageFetcher's static methods
}

// MARK: - Widget Reload

protocol WidgetReloading {
    func reloadAllTimelines()
}

struct DefaultWidgetReloader: WidgetReloading {
    // Delegates to WidgetCenter.shared.reloadAllTimelines()
}

// MARK: - Login Item

protocol LoginItemManaging {
    func setEnabled(_ enabled: Bool) throws
}

struct DefaultLoginItemManager: LoginItemManaging {
    // Delegates to SMAppService.mainApp.register() / unregister()
}

// MARK: - Alert Checking

protocol AlertChecking {
    func checkAlerts(result: UsageResult, settings: AppSettings)
}

struct DefaultAlertChecker: AlertChecking {
    // Delegates to AlertChecker.shared
}

// MARK: - Notification Sending

protocol NotificationSending {
    func requestAuthorization() async -> Bool
    func send(title: String, body: String, identifier: String) async
}

struct DefaultNotificationSender: NotificationSending {
    // Delegates to NotificationManager.shared
}

// MARK: - WebView Coordinator Delegate

/// Interface used by WebViewCoordinator to communicate with its owner.
/// Decouples the coordinator from concrete UsageViewModel for testability.
@MainActor
protocol WebViewCoordinatorDelegate: AnyObject {
    var popupWebView: WKWebView? { get set }
    func debug(_ message: String)
    func checkPopupLogin()
    func handlePageReady()
    func closePopup()
    func handlePopupClosed()
}

// UsageViewModel conforms to WebViewCoordinatorDelegate
```

## 2. State (Mermaid)

None.

This is a protocol definition file and holds no state. Each conforming type (SettingsStore, UsageStore, etc.) manages its own state.

## 3. Logic (Decision Table)

> AI Instruction: Generate a unit test for each row, either as individual test methods or parameterized loops.

### 3.1 Default Implementation Delegation Targets

Each default implementation is a thin wrapper with no logic. During testing, mocks are injected against the protocols.

| Case ID | Protocol | Default Implementation | Delegation Target | Conformance Method |
|---------|----------|----------------------|-------------------|-------------------|
| DI-01 | SettingsStoring | None (extension conformance) | SettingsStore | Extension declaration only |
| DI-02 | UsageStoring | None (extension conformance) | UsageStore | Extension declaration only |
| DI-04 | UsageFetching | DefaultUsageFetcher | UsageFetcher (static) | Struct wrapper |
| DI-05 | WidgetReloading | DefaultWidgetReloader | WidgetCenter.shared | Struct wrapper |
| DI-06 | LoginItemManaging | DefaultLoginItemManager | SMAppService.mainApp | Struct wrapper |
| DI-08 | AlertChecking | DefaultAlertChecker | AlertChecker.shared | Struct wrapper |
| DI-09 | NotificationSending | DefaultNotificationSender | NotificationManager.shared | Struct wrapper |
| DI-10 | WebViewCoordinatorDelegate | None (conformance) | UsageViewModel | Existing type conforms |

Note: DI-03 (SnapshotWriting) was removed — widget data sharing uses UsageReader directly reading usage.db written by UsageStore.

### 3.2 LoginItemManaging.setEnabled Branching

| Case ID | enabled | Expected | Notes |
|---------|---------|----------|-------|
| LI-01 | true | SMAppService.mainApp.register() | Register as login item |
| LI-02 | false | SMAppService.mainApp.unregister() | Unregister from login items |
| EX-01 | true (on failure) | throws | When register() fails |
| EX-02 | false (on failure) | throws | When unregister() fails |

## 4. Side Effects (Integration)

> AI Instruction: In integration tests, use spies/mocks to verify the following side effects.

| Type | Description | Related Protocol |
|------|-------------|-----------------|
| Store | Read/write AppSettings (UserDefaults / Keychain) | SettingsStoring |
| Store | Persist UsageResult (widget reads via UsageReader from same DB) | UsageStoring |
| Network | Fetch usage API via WKWebView | UsageFetching |
| System | WidgetCenter.shared.reloadAllTimelines() — reload widget timelines | WidgetReloading |
| System | SMAppService.mainApp.register() / unregister() — login item registration | LoginItemManaging |
| System | UNUserNotificationCenter.requestAuthorization + add(UNNotificationRequest) | NotificationSending |
| Logic | AlertChecker threshold evaluation + duplicate notification prevention | AlertChecking |
| Navigation | WKWebView delegate (navigation + UI) via WebViewCoordinator | WebViewCoordinatorDelegate |
| UI State | Show/hide/close OAuth popup window | WebViewCoordinatorDelegate |

## 5. Notes

- The purpose of this file is to abstract UsageViewModel's dependencies, enabling mock injection during testing.
- There are two conformance styles:
  - **Extension declaration only**: Existing concrete types (SettingsStore, UsageStore) already satisfy the protocol's method signatures, so they conform via a simple extension declaration.
  - **Struct wrapper**: When the delegation target uses static methods or singletons (UsageFetcher, WidgetCenter.shared, SMAppService.mainApp), instance methods wrap them to enable DI.
- UsageFetching methods have a `@MainActor` constraint because WKWebView can only be operated on the main thread.
- Widget data sharing: The main app writes usage data via `UsageStoring` (UsageStore), and the widget reads via `UsageReader.load()` (ClaudeUsageTrackerShared). No separate protocol is needed for the read side.
- WebViewCoordinatorDelegate is a protocol that decouples communication between WebViewCoordinator and UsageViewModel. The `@MainActor` constraint ensures WKWebView thread safety. It can be mocked in tests to verify popup event sequences.
