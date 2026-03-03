// Supplement for: protocol conformance tests
// Source spec: spec/meta/protocols.md
// Generated: 2026-03-03
//
// Covers:
//   - DI-01: SettingsStore conforms to SettingsStoring
//   - DI-02: UsageStore conforms to UsageStoring
//   - DI-07: TokenStore conforms to TokenSyncing
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

    // Verifies that SettingsStore can be assigned to a SettingsStoring variable,
    // confirming the extension-based conformance declaration is present and the
    // required method signatures match the protocol.
    func test_settingsStore_isAssignableToSettingsStoring() {
        let store = SettingsStore()
        let _: any SettingsStoring = store
        // If this compiles and reaches here, conformance is confirmed.
    }

    // Verifies that SettingsStore.load() returns an AppSettings value without crashing.
    func test_settingsStore_load_returnsAppSettings() {
        let store: any SettingsStoring = SettingsStore()
        let result = store.load()
        // load() must return a valid AppSettings instance (not a crash or nil).
        _ = result  // type check: result is AppSettings
    }

    // Verifies that SettingsStore.save(_:) accepts an AppSettings value without crashing.
    func test_settingsStore_save_acceptsAppSettings() {
        let store: any SettingsStoring = SettingsStore()
        let settings = AppSettings()
        store.save(settings)
        // If no crash occurs, save(_:) is callable through the protocol interface.
    }
}

// MARK: - DI-02: UsageStore conforms to UsageStoring

final class UsageStoringConformanceTests: XCTestCase {

    // Verifies that UsageStore can be assigned to a UsageStoring variable,
    // confirming the extension-based conformance declaration is present and the
    // required method signatures match the protocol.
    func test_usageStore_isAssignableToUsageStoring() {
        let store = UsageStore()
        let _: any UsageStoring = store
    }

    // Verifies that UsageStore.save(_:) accepts a UsageResult without crashing.
    func test_usageStore_save_acceptsUsageResult() {
        let store: any UsageStoring = UsageStore()
        let result = UsageResult()
        store.save(result)
    }

    // Verifies that UsageStore.loadHistory(windowSeconds:) returns an array
    // (possibly empty) without crashing when called through the protocol interface.
    func test_usageStore_loadHistory_returnsArray() {
        let store: any UsageStoring = UsageStore()
        let history = store.loadHistory(windowSeconds: 3600)
        // Result is [UsageStore.DataPoint]; an empty array is acceptable.
        XCTAssertNotNil(history)
    }

    // Verifies that UsageStore.loadDailyUsage(since:) is callable through the
    // protocol interface and returns an Optional Double without crashing.
    func test_usageStore_loadDailyUsage_returnsOptionalDouble() {
        let store: any UsageStoring = UsageStore()
        let since = Date(timeIntervalSinceNow: -86400)
        let daily = store.loadDailyUsage(since: since)
        // daily is Double?; nil is a valid result when no data is stored.
        _ = daily  // type check: daily is Double?
    }
}

// MARK: - DI-07: TokenStore conforms to TokenSyncing

final class TokenSyncingConformanceTests: XCTestCase {

    // Verifies that TokenStore can be assigned to a TokenSyncing variable,
    // confirming the extension-based conformance declaration is present, the
    // required method signatures match the protocol, and Sendable is satisfied.
    func test_tokenStore_isAssignableToTokenSyncing() {
        let store = TokenStore()
        let _: any TokenSyncing = store
    }

    // Verifies that TokenStore.sync(directories:) accepts an empty directory list
    // without crashing when called through the protocol interface.
    func test_tokenStore_sync_acceptsEmptyDirectories() {
        let store: any TokenSyncing = TokenStore()
        store.sync(directories: [])
    }

    // Verifies that TokenStore.loadRecords(since:) returns an array
    // (possibly empty) without crashing when called through the protocol interface.
    func test_tokenStore_loadRecords_returnsArray() {
        let store: any TokenSyncing = TokenStore()
        let cutoff = Date(timeIntervalSinceNow: -3600)
        let records = store.loadRecords(since: cutoff)
        XCTAssertNotNil(records)
    }

    // Verifies that TokenSyncing conforms to Sendable as declared in the protocol.
    // Assigns to a Sendable-constrained variable to confirm the constraint is met.
    func test_tokenStore_satisfiesSendableConstraint() {
        let store = TokenStore()
        let _: any TokenSyncing & Sendable = store
    }
}
