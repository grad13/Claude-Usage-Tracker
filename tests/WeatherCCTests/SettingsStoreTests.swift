import XCTest
@testable import WeatherCC

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
