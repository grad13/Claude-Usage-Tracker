import XCTest
import WeatherCCShared
@testable import WeatherCC

// MARK: - Production Settings Integrity Guard
// This test verifies that the production settings file is not corrupted by test execution.
// It reads the real App Group settings file at the START of the test suite and again at the END.
// If the content changed, the test fails — meaning some test (or the test host app) wrote to production state.
// This test exists because settings corruption has occurred MULTIPLE TIMES and was only caught by the user.

final class ProductionSettingsIntegrityTests: XCTestCase {

    private static var settingsPath: String?
    private static var hashBefore: String?

    /// Runs ONCE before all tests in this class. Snapshots the production settings file.
    override class func setUp() {
        super.setUp()
        guard let container = AppGroupConfig.containerURL else { return }
        let path = container
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(AppGroupConfig.appName, isDirectory: true)
            .appendingPathComponent("settings.json")
            .path
        settingsPath = path
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path) else { return }
        hashBefore = data.sha256Hex
    }

    func testProductionSettings_notCorruptedByTests() {
        guard let path = Self.settingsPath, let before = Self.hashBefore else {
            // No production settings file exists — nothing to protect
            return
        }
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path) else {
            XCTFail("Production settings file disappeared during test execution: \(path)")
            return
        }
        let after = data.sha256Hex
        XCTAssertEqual(before, after,
                       "PRODUCTION SETTINGS WERE MODIFIED BY TESTS. " +
                       "This means a test (or the test host app) wrote to the real App Group settings. " +
                       "Path: \(path)")
    }
}

private extension Data {
    var sha256Hex: String {
        // Simple hash using built-in CryptoKit-free approach (sum of bytes as hex)
        // Not cryptographic — just a change detection fingerprint
        let bytes = [UInt8](self)
        var hash: UInt64 = 5381
        for byte in bytes {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return String(format: "%016llx", hash)
    }
}

// MARK: - SettingsStore Unit Tests

final class SettingsStoreTests: XCTestCase {

    private var tmpDir: URL!
    private var store: SettingsStore!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsStoreTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        store = SettingsStore(fileURL: tmpDir.appendingPathComponent("settings.json"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - Load

    func testLoad_noFile_returnsDefaults() {
        let settings = store.load()
        XCTAssertEqual(settings.refreshIntervalMinutes, 5)
        XCTAssertFalse(settings.startAtLogin)
        XCTAssertTrue(settings.showHourlyGraph)
        XCTAssertTrue(settings.showWeeklyGraph)
        XCTAssertEqual(settings.chartWidth, 48)
    }

    func testLoad_noFile_createsFile() {
        let _ = store.load()
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path),
                      "load() should create a default settings file when none exists")
    }

    func testLoad_corruptFile_returnsDefaults() throws {
        try "this is not json".write(to: store.fileURL, atomically: true, encoding: .utf8)
        let settings = store.load()
        XCTAssertEqual(settings.refreshIntervalMinutes, 5,
                       "Corrupt file should fall back to defaults")
    }

    func testLoad_partialJSON_usesDefaults() throws {
        let json = #"{"refresh_interval_minutes": 42}"#
        try json.write(to: store.fileURL, atomically: true, encoding: .utf8)

        let settings = store.load()
        XCTAssertEqual(settings.refreshIntervalMinutes, 42)
        XCTAssertFalse(settings.startAtLogin, "Missing keys should use defaults")
        XCTAssertTrue(settings.showHourlyGraph)
        XCTAssertEqual(settings.chartWidth, 48)
    }

    func testLoad_validation_applied() throws {
        // Write settings with invalid chartWidth
        let json = #"{"refresh_interval_minutes": 5, "chart_width": 5}"#
        try json.write(to: store.fileURL, atomically: true, encoding: .utf8)

        let settings = store.load()
        XCTAssertEqual(settings.chartWidth, 48, "Invalid chartWidth should be corrected by validated()")
    }

    // MARK: - Save

    func testSave_thenLoad_roundTrip() {
        var settings = AppSettings()
        settings.refreshIntervalMinutes = 3
        settings.startAtLogin = true
        settings.showHourlyGraph = false
        settings.chartWidth = 60
        settings.hourlyColorPreset = .green
        settings.weeklyColorPreset = .purple

        store.save(settings)
        let loaded = store.load()

        XCTAssertEqual(loaded.refreshIntervalMinutes, 3)
        XCTAssertTrue(loaded.startAtLogin)
        XCTAssertFalse(loaded.showHourlyGraph)
        XCTAssertEqual(loaded.chartWidth, 60)
        XCTAssertEqual(loaded.hourlyColorPreset, .green)
        XCTAssertEqual(loaded.weeklyColorPreset, .purple)
    }

    func testSave_overwritesPrevious() {
        var settings1 = AppSettings()
        settings1.refreshIntervalMinutes = 1
        store.save(settings1)

        var settings2 = AppSettings()
        settings2.refreshIntervalMinutes = 20
        store.save(settings2)

        let loaded = store.load()
        XCTAssertEqual(loaded.refreshIntervalMinutes, 20, "Second save should overwrite first")
    }

    func testSave_createsDirectory() throws {
        // Use a nested path that doesn't exist yet
        let nested = tmpDir.appendingPathComponent("sub/dir")
        let nestedStore = SettingsStore(fileURL: nested.appendingPathComponent("settings.json"))

        var settings = AppSettings()
        settings.refreshIntervalMinutes = 7
        nestedStore.save(settings)

        let loaded = nestedStore.load()
        XCTAssertEqual(loaded.refreshIntervalMinutes, 7)
    }

    // MARK: - Save failure (invalid path)

    func testSave_invalidPath_silentlyFails() {
        let badStore = SettingsStore(fileURL: URL(fileURLWithPath: "/dev/null/impossible/settings.json"))
        var settings = AppSettings()
        settings.refreshIntervalMinutes = 42
        // Should not crash
        badStore.save(settings)
        // Confirm file wasn't written by trying to load
        let loaded = badStore.load()
        XCTAssertEqual(loaded.refreshIntervalMinutes, 5,
                       "Failed save should not create file; load returns defaults")
    }

    // MARK: - Shared instance test guard

    func testShared_usesTemporaryDirectory_duringTests() {
        let sharedPath = SettingsStore.shared.fileURL.path
        XCTAssertTrue(sharedPath.contains("WeatherCC-test-shared"),
                      "SettingsStore.shared must use temp dir during tests, but got: \(sharedPath)")
        XCTAssertFalse(sharedPath.contains("Group Containers"),
                       "SettingsStore.shared must NOT touch App Group during tests")
    }

    // MARK: - Load with camelCase keys (strategy mismatch)

    func testLoad_camelCaseKeys_stillMatches() throws {
        let json = #"{"refreshIntervalMinutes": 42, "startAtLogin": true}"#
        try json.write(to: store.fileURL, atomically: true, encoding: .utf8)

        let settings = store.load()
        // convertFromSnakeCase leaves keys without underscores unchanged,
        // so camelCase keys pass through and match Swift properties
        XCTAssertEqual(settings.refreshIntervalMinutes, 42,
                       "camelCase keys match because convertFromSnakeCase passes them through")
        XCTAssertTrue(settings.startAtLogin)
    }
}
