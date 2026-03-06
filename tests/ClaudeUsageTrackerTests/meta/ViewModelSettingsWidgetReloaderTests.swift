// Supplement for: docs/spec/meta/viewmodel-lifecycle.md
// Covers: setGraphColorTheme, settings widgetReloader side effects,
//         applyResult phase 4 widgetReloader

import XCTest
@testable import ClaudeUsageTracker

// MARK: - setGraphColorTheme and widgetReloader Side Effect Tests

@MainActor
final class ViewModelSettingsWidgetReloaderTests: XCTestCase {

    var settingsStore: InMemorySettingsStore!
    var widgetReloader: InMemoryWidgetReloader!

    override func setUp() {
        super.setUp()
        settingsStore = InMemorySettingsStore()
        widgetReloader = InMemoryWidgetReloader()
    }

    func makeVM() -> UsageViewModel {
        ViewModelTestFactory.makeVM(
            settingsStore: settingsStore,
            widgetReloader: widgetReloader
        )
    }

    // MARK: - setGraphColorTheme

    /// Spec: setGraphColorTheme persists the value and calls widgetReloader.reloadAllTimelines().
    func testSetGraphColorTheme_persistsAndReloadsWidget() {
        let vm = makeVM()
        let beforeReloadCount = widgetReloader.reloadCount

        vm.setGraphColorTheme(.system)

        XCTAssertEqual(vm.settings.graphColorTheme, .system,
                       "setGraphColorTheme must update settings.graphColorTheme")
        XCTAssertEqual(settingsStore.current.graphColorTheme, .system,
                       "setGraphColorTheme must persist to settingsStore")
        XCTAssertEqual(widgetReloader.reloadCount, beforeReloadCount + 1,
                       "setGraphColorTheme must call widgetReloader.reloadAllTimelines()")
        _ = vm
    }

    /// Spec: setGraphColorTheme with .dark value.
    func testSetGraphColorTheme_dark() {
        let vm = makeVM()
        vm.setGraphColorTheme(.dark)

        XCTAssertEqual(vm.settings.graphColorTheme, .dark)
        XCTAssertEqual(settingsStore.current.graphColorTheme, .dark)
        _ = vm
    }

    // MARK: - setHourlyColorPreset widgetReloader side effect

    /// Spec: setHourlyColorPreset must call widgetReloader.reloadAllTimelines().
    /// Persistence is already tested; this verifies the side effect.
    func testSetHourlyColorPreset_reloadsWidget() {
        let vm = makeVM()
        let beforeReloadCount = widgetReloader.reloadCount

        vm.setHourlyColorPreset(.green)

        XCTAssertEqual(widgetReloader.reloadCount, beforeReloadCount + 1,
                       "setHourlyColorPreset must call widgetReloader.reloadAllTimelines()")
        _ = vm
    }

    // MARK: - setWeeklyColorPreset widgetReloader side effect

    /// Spec: setWeeklyColorPreset must call widgetReloader.reloadAllTimelines().
    func testSetWeeklyColorPreset_reloadsWidget() {
        let vm = makeVM()
        let beforeReloadCount = widgetReloader.reloadCount

        vm.setWeeklyColorPreset(.purple)

        XCTAssertEqual(widgetReloader.reloadCount, beforeReloadCount + 1,
                       "setWeeklyColorPreset must call widgetReloader.reloadAllTimelines()")
        _ = vm
    }

    // MARK: - applyResult Phase 4: widgetReloader

    /// Spec: applyResult phase 4 calls widgetReloader.reloadAllTimelines().
    func testApplyResult_phase4_reloadsWidget() {
        let vm = makeVM()
        let beforeReloadCount = widgetReloader.reloadCount

        let result = UsageResultFactory.make(
            fiveHourPercent: 30.0, sevenDayPercent: 15.0
        )
        vm.applyResult(result)

        XCTAssertEqual(widgetReloader.reloadCount, beforeReloadCount + 1,
                       "applyResult must call widgetReloader.reloadAllTimelines() (phase 4)")
        _ = vm
    }

    /// Spec: applyResult called multiple times must call widgetReloader each time.
    func testApplyResult_multipleCalls_reloadsWidgetEachTime() {
        let vm = makeVM()
        let beforeReloadCount = widgetReloader.reloadCount

        let result = UsageResultFactory.make(fiveHourPercent: 10.0)
        vm.applyResult(result)
        vm.applyResult(result)
        vm.applyResult(result)

        XCTAssertEqual(widgetReloader.reloadCount, beforeReloadCount + 3,
                       "Each applyResult call must trigger widgetReloader.reloadAllTimelines()")
        _ = vm
    }
}
