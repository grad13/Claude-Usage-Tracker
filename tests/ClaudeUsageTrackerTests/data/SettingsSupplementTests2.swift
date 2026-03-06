// Supplement for: docs/spec/data/settings.md
// Covers: corrupt file .bak rename, GraphColorTheme.displayName,
//         GraphColorTheme.resolvedColorScheme(), widgetReloader on color/theme setters,
//         setGraphColorTheme ViewModel method

import XCTest
import SwiftUI
@testable import ClaudeUsageTracker

// MARK: - SettingsStore: corrupt file .bak rename

final class SettingsStoreCorruptBakTests: XCTestCase {

    private var tmpDir: URL!
    private var store: SettingsStore!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsStoreBakTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        store = SettingsStore(fileURL: tmpDir.appendingPathComponent("settings.json"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    /// Spec: "On decode error: rename corrupt file to `.bak`, save defaults, return AppSettings()"
    func testLoad_corruptFile_renamedToBak() throws {
        let corruptData = "this is not json"
        try corruptData.write(to: store.fileURL, atomically: true, encoding: .utf8)

        let _ = store.load()

        let bakURL = store.fileURL.appendingPathExtension("bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bakURL.path),
                      "Corrupt file should be renamed to .bak")
    }

    /// Verify original corrupt file is replaced with valid defaults after .bak rename
    func testLoad_corruptFile_bakContainsOriginalContent() throws {
        let corruptData = "this is not json"
        try corruptData.write(to: store.fileURL, atomically: true, encoding: .utf8)

        let _ = store.load()

        let bakURL = store.fileURL.appendingPathExtension("bak")
        let bakContent = try String(contentsOf: bakURL, encoding: .utf8)
        XCTAssertEqual(bakContent, corruptData,
                       ".bak file should contain the original corrupt content")
    }

    /// After .bak rename, the settings file itself should contain valid defaults
    func testLoad_corruptFile_settingsFileRewrittenWithDefaults() throws {
        try "broken json {{{".write(to: store.fileURL, atomically: true, encoding: .utf8)

        let settings = store.load()
        XCTAssertEqual(settings.refreshIntervalMinutes, 5,
                       "Should return defaults after handling corrupt file")

        // The settings file should now be valid JSON
        let reloaded = store.load()
        XCTAssertEqual(reloaded.refreshIntervalMinutes, 5,
                       "Re-loading should succeed with valid defaults file")
    }
}

// MARK: - GraphColorTheme.displayName

final class GraphColorThemeDisplayNameTests: XCTestCase {

    /// Spec: displayName returns "System", "Light", "Dark"
    func testDisplayName_system() {
        XCTAssertEqual(GraphColorTheme.system.displayName, "System")
    }

    func testDisplayName_light() {
        XCTAssertEqual(GraphColorTheme.light.displayName, "Light")
    }

    func testDisplayName_dark() {
        XCTAssertEqual(GraphColorTheme.dark.displayName, "Dark")
    }
}

// MARK: - GraphColorTheme.resolvedColorScheme()

final class GraphColorThemeResolvedTests: XCTestCase {

    /// Spec: .light resolves to ColorScheme.light
    func testResolvedColorScheme_light() {
        XCTAssertEqual(GraphColorTheme.light.resolvedColorScheme(), .light)
    }

    /// Spec: .dark resolves to ColorScheme.dark
    func testResolvedColorScheme_dark() {
        XCTAssertEqual(GraphColorTheme.dark.resolvedColorScheme(), .dark)
    }

    /// Spec: .system resolves based on NSApp.effectiveAppearance (either .light or .dark)
    func testResolvedColorScheme_system_returnsLightOrDark() {
        let result = GraphColorTheme.system.resolvedColorScheme()
        XCTAssertTrue(result == .light || result == .dark,
                      "system must resolve to either .light or .dark, got: \(result)")
    }
}

// MARK: - ViewModel: setGraphColorTheme + widgetReloader

extension ViewModelTests {

    /// Spec: setGraphColorTheme persists to settings store
    func testSetGraphColorTheme_persists() {
        let vm = makeVM()
        vm.setGraphColorTheme(.light)
        XCTAssertEqual(vm.settings.graphColorTheme, .light)
        XCTAssertEqual(settingsStore.current.graphColorTheme, .light,
                       "Should persist to injected store")
    }

    /// Spec: setGraphColorTheme triggers widgetReloader.reloadAllTimelines()
    func testSetGraphColorTheme_triggersWidgetReload() {
        let vm = makeVM()
        let before = widgetReloader.reloadCount
        vm.setGraphColorTheme(.system)
        XCTAssertEqual(widgetReloader.reloadCount, before + 1,
                       "setGraphColorTheme must trigger widget reload")
    }

    /// Spec: setHourlyColorPreset triggers widgetReloader.reloadAllTimelines()
    func testSetHourlyColorPreset_triggersWidgetReload() {
        let vm = makeVM()
        let before = widgetReloader.reloadCount
        vm.setHourlyColorPreset(.teal)
        XCTAssertEqual(widgetReloader.reloadCount, before + 1,
                       "setHourlyColorPreset must trigger widget reload")
    }

    /// Spec: setWeeklyColorPreset triggers widgetReloader.reloadAllTimelines()
    func testSetWeeklyColorPreset_triggersWidgetReload() {
        let vm = makeVM()
        let before = widgetReloader.reloadCount
        vm.setWeeklyColorPreset(.orange)
        XCTAssertEqual(widgetReloader.reloadCount, before + 1,
                       "setWeeklyColorPreset must trigger widget reload")
    }
}
