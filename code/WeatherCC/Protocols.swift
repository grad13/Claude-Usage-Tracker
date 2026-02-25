// meta: created=2026-02-23 updated=2026-02-23 checked=never
// Dependency injection protocols.
// Enables testing UsageViewModel without touching production state.
import Foundation
import ServiceManagement
import WebKit
import WidgetKit
import WeatherCCShared

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
}

extension UsageStore: UsageStoring {}

// MARK: - Widget Snapshot

protocol SnapshotWriting {
    /// Fetch success: update state + append history.
    func saveAfterFetch(
        timestamp: Date,
        fiveHourPercent: Double?, sevenDayPercent: Double?,
        fiveHourResetsAt: Date?, sevenDayResetsAt: Date?,
        isLoggedIn: Bool
    )
    /// Update predict values only (other state fields untouched).
    func updatePredict(fiveHourCost: Double?, sevenDayCost: Double?)
    /// Sign out: reset state to logged-out (history preserved).
    func clearOnSignOut()
}

struct DefaultSnapshotWriter: SnapshotWriting {
    func saveAfterFetch(
        timestamp: Date,
        fiveHourPercent: Double?, sevenDayPercent: Double?,
        fiveHourResetsAt: Date?, sevenDayResetsAt: Date?,
        isLoggedIn: Bool
    ) {
        SnapshotStore.saveAfterFetch(
            timestamp: timestamp,
            fiveHourPercent: fiveHourPercent,
            sevenDayPercent: sevenDayPercent,
            fiveHourResetsAt: fiveHourResetsAt,
            sevenDayResetsAt: sevenDayResetsAt,
            isLoggedIn: isLoggedIn
        )
    }

    func updatePredict(fiveHourCost: Double?, sevenDayCost: Double?) {
        SnapshotStore.updatePredict(fiveHourCost: fiveHourCost, sevenDayCost: sevenDayCost)
    }

    func clearOnSignOut() {
        SnapshotStore.clearOnSignOut()
    }
}

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

struct DefaultWidgetReloader: WidgetReloading {
    func reloadAllTimelines() {
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

// MARK: - Token (JSONL cost estimation)

protocol TokenSyncing: Sendable {
    func sync(directories: [URL])
    func loadRecords(since cutoff: Date) -> [TokenRecord]
}

extension TokenStore: TokenSyncing {}
