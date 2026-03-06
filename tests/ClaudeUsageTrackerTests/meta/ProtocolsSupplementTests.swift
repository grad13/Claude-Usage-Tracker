// Supplement for: protocol conformance tests
// Source spec: spec/meta/protocols.md
// Generated: 2026-03-03
//
// Covers:
//   - DI-01: SettingsStore conforms to SettingsStoring
//   - DI-02: UsageStore conforms to UsageStoring
//
// Not covered (source type absent):
//   - DI-08: DefaultAlertChecker — type does not exist in source at time of generation.
//             Spec defines `struct DefaultAlertChecker: AlertChecking` delegating to
//             `AlertChecker.shared`, but the struct is not present in the codebase.
//             Add tests here when the type is introduced.

import XCTest
import ClaudeUsageTrackerShared
@testable import ClaudeUsageTracker

// MARK: - DI-01: SettingsStore conforms to SettingsStoring

final class SettingsStoringConformanceTests: XCTestCase {

    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("test-settings-\(UUID().uuidString).json")
    }

    func test_settingsStore_isAssignableToSettingsStoring() {
        let store = SettingsStore(fileURL: makeTempURL())
        let _: any SettingsStoring = store
    }

    func test_settingsStore_load_returnsAppSettings() {
        let store: any SettingsStoring = SettingsStore(fileURL: makeTempURL())
        let result = store.load()
        _ = result
    }

    func test_settingsStore_save_acceptsAppSettings() {
        let store: any SettingsStoring = SettingsStore(fileURL: makeTempURL())
        let settings = AppSettings()
        store.save(settings)
    }
}

// MARK: - DI-02: UsageStore conforms to UsageStoring

final class UsageStoringConformanceTests: XCTestCase {

    private func makeTempDbPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("test-usage-\(UUID().uuidString).sqlite").path
    }

    func test_usageStore_isAssignableToUsageStoring() {
        let store = UsageStore(dbPath: makeTempDbPath())
        let _: any UsageStoring = store
    }

    func test_usageStore_save_acceptsUsageResult() {
        let store: any UsageStoring = UsageStore(dbPath: makeTempDbPath())
        let result = UsageResult()
        store.save(result)
    }

    func test_usageStore_loadHistory_returnsArray() {
        let store: any UsageStoring = UsageStore(dbPath: makeTempDbPath())
        let history = store.loadHistory(windowSeconds: 3600)
        XCTAssertNotNil(history)
    }

    func test_usageStore_loadDailyUsage_returnsOptionalDouble() {
        let store: any UsageStoring = UsageStore(dbPath: makeTempDbPath())
        let since = Date(timeIntervalSinceNow: -86400)
        let daily = store.loadDailyUsage(since: since)
        _ = daily
    }
}

