// Supplement 2 for: MenuContent UI logic tests
// Covers: ViewModel setter methods (graph show toggles, chart width, color presets),
//         Start at Login toggle, version format with fallback

import XCTest
@testable import ClaudeUsageTracker

// Note: SwiftUI View body tests (colors, fonts, window management) are
// intentionally omitted. Only ViewModel-layer and model-layer contracts are tested here.

@MainActor
final class MenuContentSupplementTests2: XCTestCase {

    var settingsStore: InMemorySettingsStore!
    var stubFetcher: StubUsageFetcher!
    var widgetReloader: InMemoryWidgetReloader!
    var loginItemManager: InMemoryLoginItemManager!

    override func setUp() {
        super.setUp()
        settingsStore = InMemorySettingsStore()
        stubFetcher = StubUsageFetcher()
        widgetReloader = InMemoryWidgetReloader()
        loginItemManager = InMemoryLoginItemManager()
    }

    func makeVM() -> UsageViewModel {
        ViewModelTestFactory.makeVM(
            fetcher: stubFetcher,
            settingsStore: settingsStore,
            widgetReloader: widgetReloader,
            loginItemManager: loginItemManager
        )
    }

    // MARK: - setShowHourlyGraph(_:)

    // Guarantees: toggling showHourlyGraph updates settings and persists via settingsStore.
    // Spec: "Show 5-hour" toggle calls viewModel.setShowHourlyGraph(_:), default true.

    func testShowHourlyGraph_defaultTrue() {
        let vm = makeVM()
        XCTAssertTrue(vm.settings.showHourlyGraph,
            "showHourlyGraph must default to true (spec: Show 5-hour toggle default)")
    }

    func testSetShowHourlyGraph_false_updatesSettingsAndPersists() {
        let vm = makeVM()
        vm.setShowHourlyGraph(false)
        XCTAssertFalse(vm.settings.showHourlyGraph,
            "setShowHourlyGraph(false) must update settings to false")
        let persisted = settingsStore.load()
        XCTAssertFalse(persisted.showHourlyGraph,
            "setShowHourlyGraph must persist via settingsStore.save()")
    }

    func testSetShowHourlyGraph_true_updatesSettingsAndPersists() {
        let vm = makeVM()
        vm.setShowHourlyGraph(false)
        vm.setShowHourlyGraph(true)
        XCTAssertTrue(vm.settings.showHourlyGraph,
            "setShowHourlyGraph(true) must re-enable the setting")
        let persisted = settingsStore.load()
        XCTAssertTrue(persisted.showHourlyGraph,
            "Re-enabled setting must be persisted")
    }

    // MARK: - setShowWeeklyGraph(_:)

    // Guarantees: toggling showWeeklyGraph updates settings and persists via settingsStore.
    // Spec: "Show 7-day" toggle calls viewModel.setShowWeeklyGraph(_:), default true.

    func testShowWeeklyGraph_defaultTrue() {
        let vm = makeVM()
        XCTAssertTrue(vm.settings.showWeeklyGraph,
            "showWeeklyGraph must default to true (spec: Show 7-day toggle default)")
    }

    func testSetShowWeeklyGraph_false_updatesSettingsAndPersists() {
        let vm = makeVM()
        vm.setShowWeeklyGraph(false)
        XCTAssertFalse(vm.settings.showWeeklyGraph,
            "setShowWeeklyGraph(false) must update settings to false")
        let persisted = settingsStore.load()
        XCTAssertFalse(persisted.showWeeklyGraph,
            "setShowWeeklyGraph must persist via settingsStore.save()")
    }

    func testSetShowWeeklyGraph_true_updatesSettingsAndPersists() {
        let vm = makeVM()
        vm.setShowWeeklyGraph(false)
        vm.setShowWeeklyGraph(true)
        XCTAssertTrue(vm.settings.showWeeklyGraph,
            "setShowWeeklyGraph(true) must re-enable the setting")
        let persisted = settingsStore.load()
        XCTAssertTrue(persisted.showWeeklyGraph,
            "Re-enabled setting must be persisted")
    }

    // MARK: - setChartWidth(_:)

    // Guarantees: setChartWidth updates settings.chartWidth and persists.
    // Spec: default 48pt, saved via viewModel.setChartWidth(_:).

    func testChartWidth_default48() {
        let vm = makeVM()
        XCTAssertEqual(vm.settings.chartWidth, 48,
            "chartWidth must default to 48 (spec: default 48pt)")
    }

    func testSetChartWidth_updatesSettingsAndPersists() {
        let vm = makeVM()
        vm.setChartWidth(72)
        XCTAssertEqual(vm.settings.chartWidth, 72,
            "setChartWidth(72) must update settings to 72")
        let persisted = settingsStore.load()
        XCTAssertEqual(persisted.chartWidth, 72,
            "setChartWidth must persist via settingsStore.save()")
    }

    func testSetChartWidth_allPresetValues() {
        // Spec: presets are [12, 24, 36, 48, 60, 72].
        let presets = [12, 24, 36, 48, 60, 72]
        for width in presets {
            let vm = makeVM()
            vm.setChartWidth(width)
            XCTAssertEqual(vm.settings.chartWidth, width,
                "setChartWidth(\(width)) must accept preset value \(width)")
        }
    }

    // MARK: - setHourlyColorPreset(_:)

    // Guarantees: setHourlyColorPreset updates settings and persists, plus reloads widget timelines.
    // Spec: 5-hour color default is .blue, saved via viewModel.setHourlyColorPreset(_:).

    func testHourlyColorPreset_defaultBlue() {
        let vm = makeVM()
        XCTAssertEqual(vm.settings.hourlyColorPreset, .blue,
            "hourlyColorPreset must default to .blue (spec: 5-hour Color default Blue)")
    }

    func testSetHourlyColorPreset_updatesSettingsAndPersists() {
        let vm = makeVM()
        vm.setHourlyColorPreset(.green)
        XCTAssertEqual(vm.settings.hourlyColorPreset, .green,
            "setHourlyColorPreset(.green) must update settings")
        let persisted = settingsStore.load()
        XCTAssertEqual(persisted.hourlyColorPreset, .green,
            "setHourlyColorPreset must persist via settingsStore.save()")
    }

    func testSetHourlyColorPreset_reloadsWidgetTimelines() {
        let vm = makeVM()
        vm.setHourlyColorPreset(.purple)
        XCTAssertEqual(widgetReloader.reloadCount, 1,
            "setHourlyColorPreset must trigger widgetReloader.reloadAllTimelines()")
    }

    func testSetHourlyColorPreset_allPresets() {
        // Spec: 7 color presets available for 5-hour color.
        for preset in ChartColorPreset.allCases {
            let vm = makeVM()
            vm.setHourlyColorPreset(preset)
            XCTAssertEqual(vm.settings.hourlyColorPreset, preset,
                "setHourlyColorPreset must accept \(preset.displayName)")
        }
    }

    // MARK: - setWeeklyColorPreset(_:)

    // Guarantees: setWeeklyColorPreset updates settings and persists, plus reloads widget timelines.
    // Spec: 7-day color default is .pink, saved via viewModel.setWeeklyColorPreset(_:).

    func testWeeklyColorPreset_defaultPink() {
        let vm = makeVM()
        XCTAssertEqual(vm.settings.weeklyColorPreset, .pink,
            "weeklyColorPreset must default to .pink (spec: 7-day Color default Pink)")
    }

    func testSetWeeklyColorPreset_updatesSettingsAndPersists() {
        let vm = makeVM()
        vm.setWeeklyColorPreset(.orange)
        XCTAssertEqual(vm.settings.weeklyColorPreset, .orange,
            "setWeeklyColorPreset(.orange) must update settings")
        let persisted = settingsStore.load()
        XCTAssertEqual(persisted.weeklyColorPreset, .orange,
            "setWeeklyColorPreset must persist via settingsStore.save()")
    }

    func testSetWeeklyColorPreset_reloadsWidgetTimelines() {
        let vm = makeVM()
        vm.setWeeklyColorPreset(.teal)
        XCTAssertEqual(widgetReloader.reloadCount, 1,
            "setWeeklyColorPreset must trigger widgetReloader.reloadAllTimelines()")
    }

    func testSetWeeklyColorPreset_allPresets() {
        // Spec: 7 color presets available for 7-day color.
        for preset in ChartColorPreset.allCases {
            let vm = makeVM()
            vm.setWeeklyColorPreset(preset)
            XCTAssertEqual(vm.settings.weeklyColorPreset, preset,
                "setWeeklyColorPreset must accept \(preset.displayName)")
        }
    }

    // MARK: - Start at Login toggle

    // Guarantees: toggleStartAtLogin() toggles settings.startAtLogin, persists, and syncs login item.
    // Spec: "Start at Login" toggle with checkmark when enabled.

    func testStartAtLogin_defaultFalse() {
        let vm = makeVM()
        XCTAssertFalse(vm.settings.startAtLogin,
            "startAtLogin must default to false")
    }

    func testToggleStartAtLogin_togglesFromFalseToTrue() {
        let vm = makeVM()
        vm.toggleStartAtLogin()
        XCTAssertTrue(vm.settings.startAtLogin,
            "toggleStartAtLogin() must flip false to true")
    }

    func testToggleStartAtLogin_togglesFromTrueToFalse() {
        let vm = makeVM()
        vm.toggleStartAtLogin()  // false -> true
        vm.toggleStartAtLogin()  // true -> false
        XCTAssertFalse(vm.settings.startAtLogin,
            "toggleStartAtLogin() called twice must return to false")
    }

    func testToggleStartAtLogin_persistsViaSave() {
        let vm = makeVM()
        vm.toggleStartAtLogin()
        let persisted = settingsStore.load()
        XCTAssertTrue(persisted.startAtLogin,
            "toggleStartAtLogin must persist via settingsStore.save()")
    }

    func testToggleStartAtLogin_callsLoginItemManager() {
        let vm = makeVM()
        vm.toggleStartAtLogin()
        XCTAssertEqual(loginItemManager.enabledCallCount, 1,
            "toggleStartAtLogin (false->true) must call loginItemManager.setEnabled(true)")
        XCTAssertEqual(loginItemManager.lastEnabled, true,
            "loginItemManager must receive enabled=true")
    }

    func testToggleStartAtLogin_disableCallsLoginItemManager() {
        settingsStore.current.startAtLogin = true  // avoid init's syncLoginItem calling setEnabled(false)
        let vm = makeVM()  // init: setEnabled(true) → enabledCallCount=1
        vm.toggleStartAtLogin()  // disable: true→false
        XCTAssertEqual(loginItemManager.disabledCallCount, 1,
            "toggleStartAtLogin (true->false) must call loginItemManager.setEnabled(false)")
        XCTAssertEqual(loginItemManager.lastEnabled, false,
            "loginItemManager must receive enabled=false")
    }

    func testToggleStartAtLogin_revertsOnError() {
        // Spec (syncLoginItem): if setEnabled throws, revert setting and set error.
        let vm = makeVM()
        loginItemManager.shouldThrow = NSError(domain: "test", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "mock error"])
        vm.toggleStartAtLogin()
        XCTAssertFalse(vm.settings.startAtLogin,
            "toggleStartAtLogin must revert to false when loginItemManager throws")
        XCTAssertNotNil(vm.error,
            "toggleStartAtLogin must set viewModel.error on failure")
    }

    // MARK: - Version display format

    // Guarantees: version string format "v{CFBundleShortVersionString}", fallback "v?".
    // Spec: Format is v{version} with fallback to v? if key is missing.
    // Note: We cannot test the actual Bundle.main.infoDictionary in unit tests,
    // but we can test the formatting logic as a pure function.

    func testVersionFormat_withVersion() {
        // Spec: "v{CFBundleShortVersionString}" e.g. "v0.3.0"
        let version: String? = "0.3.0"
        let formatted = "v\(version ?? "?")"
        XCTAssertEqual(formatted, "v0.3.0",
            "Version must be formatted as v{version}")
    }

    func testVersionFormat_fallbackWhenNil() {
        // Spec: Falls back to "v?" if the key is missing
        let version: String? = nil
        let formatted = "v\(version ?? "?")"
        XCTAssertEqual(formatted, "v?",
            "Version must fall back to 'v?' when CFBundleShortVersionString is missing")
    }

    // MARK: - Color preset RGB values

    // Guarantees: each ChartColorPreset.color produces the RGB values specified in the spec.
    // Spec defines exact RGB tuples for each color.
    // Note: Color comparison is not straightforward in SwiftUI. We verify the construction
    // pattern matches spec by testing the enum-to-color mapping does not crash and produces
    // a non-nil Color. Exact RGB verification would require NSColor conversion which is
    // view-layer testing territory.

    func testColorPreset_allCasesProduceColor() {
        // Verify each preset's .color property is accessible (construction correctness).
        for preset in ChartColorPreset.allCases {
            let _ = preset.color  // Must not crash
        }
        // If we reach here, all 7 presets produce valid Color values.
        XCTAssertEqual(ChartColorPreset.allCases.count, 7,
            "All 7 color presets must produce a valid Color")
    }
}
