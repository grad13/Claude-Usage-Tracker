// meta: created=2026-02-23 updated=2026-02-23 checked=never
// Dependency injection protocols.
// Enables testing UsageViewModel without touching production state.
import Foundation
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
    func save(_ snapshot: UsageSnapshot)
    func backup()
}

struct DefaultSnapshotWriter: SnapshotWriting {
    func save(_ snapshot: UsageSnapshot) {
        SnapshotStore.save(snapshot)
    }
    func backup() {
        guard let url = AppGroupConfig.snapshotURL else { return }
        let backupURL = url.deletingLastPathComponent().appendingPathComponent("snapshot.json.bak")
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        try? fm.removeItem(at: backupURL)
        try? fm.copyItem(at: url, to: backupURL)
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

// MARK: - Token (JSONL cost estimation)

protocol TokenSyncing: Sendable {
    func sync(directories: [URL])
    func loadRecords(since cutoff: Date) -> [TokenRecord]
}

extension TokenStore: TokenSyncing {}
