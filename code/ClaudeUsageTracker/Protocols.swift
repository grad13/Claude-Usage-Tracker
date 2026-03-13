// meta: created=2026-02-23 updated=2026-02-27 checked=2026-03-03
// Dependency injection protocols.
// Enables testing UsageViewModel without touching production state.
import Foundation
import ServiceManagement
import WebKit
import WidgetKit
import ClaudeUsageTrackerShared

// MARK: - Settings

protocol SettingsStoring {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}

extension SettingsStore: SettingsStoring {}

// MARK: - Usage History

protocol UsageStoring {
    func save(_ result: UsageResult)
    func loadHistory(windowSeconds: TimeInterval) -> [UsageStore.DataPoint]
    func loadDailyUsage(since: Date) -> Double?
}

extension UsageStore: UsageStoring {}

// MARK: - Usage Fetching

protocol UsageFetching {
    @MainActor func fetch(from webView: WKWebView) async throws -> UsageResult
    @MainActor func hasValidSession(using webView: WKWebView) async -> Bool
}

struct DefaultUsageFetcher: UsageFetching {
    @MainActor func fetch(from webView: WKWebView) async throws -> UsageResult {
        try await UsageFetcher.fetch(from: webView)
    }
    @MainActor func hasValidSession(using webView: WKWebView) async -> Bool {
        await UsageFetcher.hasValidSession(using: webView)
    }
}

// MARK: - Widget Reload

protocol WidgetReloading {
    func reloadAllTimelines()
}

final class DefaultWidgetReloader: WidgetReloading {
    /// Minimum interval between actual WidgetKit reload calls.
    /// WidgetKit has a daily reload budget (~40-70), so calling every minute
    /// exhausts it within an hour. 5 minutes matches the widget's timeline policy.
    private static let minimumInterval: TimeInterval = 5 * 60
    private var lastReloadDate: Date = .distantPast

    func reloadAllTimelines() {
        let now = Date()
        guard now.timeIntervalSince(lastReloadDate) >= Self.minimumInterval else { return }
        lastReloadDate = now
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Login Item

protocol LoginItemManaging {
    /// Register or unregister the app as a login item.
    /// Throws on failure so callers can handle it (e.g., revert UI state).
    func setEnabled(_ enabled: Bool) throws
}

struct DefaultLoginItemManager: LoginItemManaging {
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
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

// MARK: - Alert Checking

protocol AlertChecking {
    func checkAlerts(result: UsageResult, settings: AppSettings)
}

// MARK: - Notification Sending

protocol NotificationSending {
    func requestAuthorization() async -> Bool
    func send(title: String, body: String, identifier: String) async
}

struct DefaultNotificationSender: NotificationSending {
    func requestAuthorization() async -> Bool {
        await NotificationManager.shared.requestAuthorization()
    }
    func send(title: String, body: String, identifier: String) async {
        await NotificationManager.shared.send(title: title, body: body, identifier: identifier)
    }
}
