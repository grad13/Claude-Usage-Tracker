// meta: created=2026-02-23 updated=2026-02-23 checked=never
// Dependency injection protocols.
// Enables testing UsageViewModel without touching production state.
import Foundation
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
}

struct DefaultSnapshotWriter: SnapshotWriting {
    func save(_ snapshot: UsageSnapshot) {
        SnapshotStore.save(snapshot)
    }
}

// MARK: - Token (JSONL cost estimation)

protocol TokenSyncing: Sendable {
    func sync(directories: [URL])
    func loadRecords(since cutoff: Date) -> [TokenRecord]
}

extension TokenStore: TokenSyncing {}
