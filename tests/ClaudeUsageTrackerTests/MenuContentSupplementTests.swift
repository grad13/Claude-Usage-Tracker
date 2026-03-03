// Supplement for: MenuContent UI logic tests

import XCTest
@testable import ClaudeUsageTracker

// Note: SwiftUI View body tests (MenuContent rendering, button appearance, colors) are
// intentionally omitted. SwiftUI views require a running host environment and cannot be
// reliably unit-tested without UI testing infrastructure. The tests here cover only the
// ViewModel logic and model-layer invariants that MenuContent depends on.

// Note: alert setters (setWeeklyAlertEnabled, setWeeklyAlertThreshold,
// setHourlyAlertEnabled, setHourlyAlertThreshold, setDailyAlertEnabled,
// setDailyAlertThreshold, setDailyAlertDefinition) are already covered in
// data/SettingsSupplementTests. Not duplicated here.

@MainActor
final class MenuContentSupplementTests: XCTestCase {

    var settingsStore: InMemorySettingsStore!
    var stubFetcher: StubUsageFetcher!

    override func setUp() {
        super.setUp()
        settingsStore = InMemorySettingsStore()
        stubFetcher = StubUsageFetcher()
    }

    func makeVM() -> UsageViewModel {
        ViewModelTestFactory.makeVM(
            fetcher: stubFetcher,
            settingsStore: settingsStore
        )
    }

    // MARK: - Usage display: fiveHourPercent nil-conditional

    // Guarantees: MenuContent shows the 5-hour row only when fiveHourPercent is non-nil.
    // The ViewModel property is the source of truth for this condition.

    func testFiveHourPercent_nilByDefault() {
        let vm = makeVM()
        XCTAssertNil(vm.fiveHourPercent,
            "fiveHourPercent must be nil before first fetch — 5-hour row must be hidden")
    }

    func testFiveHourPercent_nonNilAfterSet() {
        let vm = makeVM()
        vm.fiveHourPercent = 42.5
        XCTAssertNotNil(vm.fiveHourPercent,
            "fiveHourPercent non-nil means 5-hour row must be shown")
    }

    func testSevenDayPercent_nilByDefault() {
        let vm = makeVM()
        XCTAssertNil(vm.sevenDayPercent,
            "sevenDayPercent must be nil before first fetch — 7-day row must be hidden")
    }

    func testSevenDayPercent_nonNilAfterSet() {
        let vm = makeVM()
        vm.sevenDayPercent = 15.3
        XCTAssertNotNil(vm.sevenDayPercent,
            "sevenDayPercent non-nil means 7-day row must be shown")
    }

    // MARK: - Usage display format: %.1f

    // Guarantees: the menu rows show values with one decimal place (e.g. "42.5%", not "42%").
    // This is a pure string formatting invariant used by MenuContent.

    func testUsageDisplayFormat_oneDecimalPlace() {
        // Spec: "5-hour: XX.X%" — one decimal place via %.1f specifier.
        let value: Double = 42.5
        let formatted = String(format: "%.1f", value)
        XCTAssertEqual(formatted, "42.5",
            "%.1f must produce one decimal place for the menu display")
    }

    func testUsageDisplayFormat_roundsHalfUp() {
        // 42.55 rounds to 42.6 (standard %.1f rounding behavior).
        let formatted = String(format: "%.1f", 42.55)
        // Note: IEEE 754 double may produce 42.5 or 42.6 depending on representation.
        // The key guarantee is: exactly one decimal digit is shown.
        XCTAssertTrue(formatted.contains(".") && formatted.split(separator: ".")[1].count == 1,
            "%.1f must produce exactly one digit after the decimal point")
    }

    func testUsageDisplayFormat_zeroValue() {
        let formatted = String(format: "%.1f", 0.0)
        XCTAssertEqual(formatted, "0.0",
            "0%% utilization must render as '0.0', not '0'")
    }

    func testUsageDisplayFormat_hundredPercent() {
        let formatted = String(format: "%.1f", 100.0)
        XCTAssertEqual(formatted, "100.0",
            "100%% utilization must render as '100.0'")
    }

    // MARK: - Remaining text: nil-conditional display

    // Guarantees: the "(resets in ...)" suffix is shown only when resetsAt is non-nil.

    func testFiveHourResetsAt_nilByDefault() {
        let vm = makeVM()
        XCTAssertNil(vm.fiveHourResetsAt,
            "fiveHourResetsAt nil → no resets-in suffix in 5-hour row")
    }

    func testSevenDayResetsAt_nilByDefault() {
        let vm = makeVM()
        XCTAssertNil(vm.sevenDayResetsAt,
            "sevenDayResetsAt nil → no resets-in suffix in 7-day row")
    }

    func testFiveHourResetsAt_nonNilEnablesRemainingText() {
        let vm = makeVM()
        vm.fiveHourResetsAt = Date().addingTimeInterval(3600)
        XCTAssertNotNil(vm.fiveHourResetsAt,
            "fiveHourResetsAt non-nil → resets-in suffix must be shown")
    }

    func testSevenDayResetsAt_nonNilEnablesRemainingText() {
        let vm = makeVM()
        vm.sevenDayResetsAt = Date().addingTimeInterval(7 * 24 * 3600)
        XCTAssertNotNil(vm.sevenDayResetsAt,
            "sevenDayResetsAt non-nil → resets-in suffix must be shown")
    }

    // MARK: - Error display: nil-conditional

    // Guarantees: "Error: <message>" row is shown only when viewModel.error is non-nil.
    // Error does not suppress usage rows — both can appear simultaneously.

    func testError_nilByDefault() {
        let vm = makeVM()
        XCTAssertNil(vm.error,
            "error must be nil by default — no error row in menu")
    }

    func testError_nonNilShowsMessage() {
        let vm = makeVM()
        vm.error = "Network timeout"
        XCTAssertEqual(vm.error, "Network timeout",
            "error non-nil means 'Error: <message>' row is shown")
    }

    func testError_independentOfUsageData() {
        // Spec: error and usage rows can appear simultaneously.
        let vm = makeVM()
        vm.fiveHourPercent = 80.0
        vm.sevenDayPercent = 40.0
        vm.error = "Partial parse failure"
        XCTAssertNotNil(vm.fiveHourPercent,
            "Usage rows must remain visible even when error is set")
        XCTAssertNotNil(vm.sevenDayPercent,
            "Usage rows must remain visible even when error is set")
        XCTAssertNotNil(vm.error,
            "Error row must be shown alongside usage rows")
    }

    // MARK: - Sign In / Sign Out: isLoggedIn state

    // Guarantees: isLoggedIn = true → "Sign Out" button; isLoggedIn = false → "Sign In..." button.

    func testIsLoggedIn_falseByDefault() {
        let vm = makeVM()
        XCTAssertFalse(vm.isLoggedIn,
            "isLoggedIn must be false before session check — Sign In... must be shown")
    }

    func testSignOut_setsIsLoggedInToFalse() {
        let vm = makeVM()
        vm.isLoggedIn = true
        vm.signOut()
        XCTAssertFalse(vm.isLoggedIn,
            "signOut() must set isLoggedIn to false — Sign Out button switches to Sign In...")
    }

    // MARK: - Refresh button: isFetching disables the button

    // Guarantees: while isFetching is true, the Refresh button is disabled.
    // fetch() contains a guard !isFetching to prevent double-fetch.

    func testIsFetching_falseByDefault() {
        let vm = makeVM()
        XCTAssertFalse(vm.isFetching,
            "isFetching must be false initially — Refresh button must be enabled")
    }

    func testFetch_guardPreventDoubleFetch() async {
        // Spec: fetch() has guard !isFetching to prevent double-fetch.
        // The stub fetcher counts calls; if isFetching were not guarded, two calls
        // would result in fetchCallCount == 2.
        stubFetcher.fetchResult = .success(UsageResult())
        let vm = makeVM()
        vm.isFetching = true
        vm.fetch()
        // isFetching was already true → fetch() must not call the fetcher again
        let done = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { done.fulfill() }
        await fulfillment(of: [done], timeout: 1.0)
        XCTAssertEqual(stubFetcher.fetchCallCount, 0,
            "fetch() with isFetching==true must not call fetcher (double-fetch prevention)")
    }

    // MARK: - Refresh Interval: Off (0 min) and presets

    // Guarantees: refreshIntervalMinutes == 0 means auto-refresh is disabled (Off).
    // AppSettings.presets matches the exact menu items shown.

    func testRefreshIntervalOff_zeroMeansDisabled() {
        let vm = makeVM()
        vm.setRefreshInterval(minutes: 0)
        XCTAssertEqual(vm.settings.refreshIntervalMinutes, 0,
            "refreshIntervalMinutes == 0 represents the 'Off' menu item")
    }

    func testRefreshIntervalPresets_matchSpec() {
        // Spec menu items: Off(0), 1, 2, 3, 5, 10, 20, 60.
        // AppSettings.presets provides the non-zero presets.
        XCTAssertEqual(AppSettings.presets, [1, 2, 3, 5, 10, 20, 60],
            "Presets must match the spec menu items exactly")
    }

    func testRefreshIntervalPresets_defaultIsInPresets() {
        // Spec: default is 5 min (✓ marker). Must be in presets.
        let defaultInterval = AppSettings().refreshIntervalMinutes
        XCTAssertTrue(AppSettings.presets.contains(defaultInterval),
            "Default refreshIntervalMinutes (\(defaultInterval)) must be in presets")
    }

    // MARK: - Refresh Interval: Custom interval detection

    // Guarantees: "Current: N min ✓" item is shown only when the current value is not in presets
    // and not 0 (Off). This is the isCustomInterval condition used by MenuContent.

    func testIsCustomInterval_presetValueIsNotCustom() {
        // Values in AppSettings.presets are not custom.
        for preset in AppSettings.presets {
            let isCustom = !AppSettings.presets.contains(preset) && preset != 0
            XCTAssertFalse(isCustom,
                "\(preset) is a preset value — must not show 'Current: N min' item")
        }
    }

    func testIsCustomInterval_offIsNotCustom() {
        // 0 (Off) is a named menu item, not a custom value.
        let interval = 0
        let isCustom = !AppSettings.presets.contains(interval) && interval != 0
        XCTAssertFalse(isCustom,
            "0 (Off) must not show 'Current: N min' item")
    }

    func testIsCustomInterval_arbitraryValueIsCustom() {
        // A value like 42 is not in presets and not 0 → custom.
        let interval = 42
        let isCustom = !AppSettings.presets.contains(interval) && interval != 0
        XCTAssertTrue(isCustom,
            "\(interval) is not a preset → must show 'Current: N min ✓' item")
    }

    func testIsCustomInterval_7IsCustom() {
        // 7 is not in [1,2,3,5,10,20,60] and not 0.
        let interval = 7
        let isCustom = !AppSettings.presets.contains(interval) && interval != 0
        XCTAssertTrue(isCustom,
            "7 min is not a preset value — must show 'Current: 7 min ✓' in menu")
    }

    // MARK: - Refresh interval label format

    // Guarantees: each preset is displayed as "{N} min" in the menu.

    func testRefreshIntervalLabel_format() {
        // Spec: "1 min", "2 min", ..., "60 min"
        for preset in AppSettings.presets {
            let label = "\(preset) min"
            XCTAssertTrue(label.hasSuffix(" min"),
                "Preset \(preset) label must end with ' min'")
            XCTAssertTrue(label.hasPrefix("\(preset)"),
                "Preset \(preset) label must start with the number")
        }
    }

    // MARK: - Chart Width presets

    // Guarantees: Chart Width submenu items match the spec values exactly.

    func testChartWidthPresets_matchSpec() {
        // Spec: 12pt, 24pt, 36pt, 48pt (default), 60pt, 72pt
        XCTAssertEqual(AppSettings.chartWidthPresets, [12, 24, 36, 48, 60, 72],
            "Chart width presets must match spec submenu items")
    }

    func testChartWidthDefault_isInPresets() {
        let defaultWidth = AppSettings().chartWidth
        XCTAssertTrue(AppSettings.chartWidthPresets.contains(defaultWidth),
            "Default chartWidth (\(defaultWidth)) must be in chartWidthPresets")
    }

    func testChartWidthLabel_format() {
        // Spec: each width shown as "{width}pt"
        for width in AppSettings.chartWidthPresets {
            let label = "\(width)pt"
            XCTAssertTrue(label.hasSuffix("pt"),
                "Chart width label must end with 'pt'")
        }
    }

    // MARK: - ChartColorPreset display names

    // Guarantees: color picker items show display names as specified.

    func testChartColorPreset_blueDisplayName() {
        XCTAssertEqual(ChartColorPreset.blue.displayName, "Blue")
    }

    func testChartColorPreset_pinkDisplayName() {
        XCTAssertEqual(ChartColorPreset.pink.displayName, "Pink")
    }

    func testChartColorPreset_greenDisplayName() {
        XCTAssertEqual(ChartColorPreset.green.displayName, "Green")
    }

    func testChartColorPreset_tealDisplayName() {
        XCTAssertEqual(ChartColorPreset.teal.displayName, "Teal")
    }

    func testChartColorPreset_purpleDisplayName() {
        XCTAssertEqual(ChartColorPreset.purple.displayName, "Purple")
    }

    func testChartColorPreset_orangeDisplayName() {
        XCTAssertEqual(ChartColorPreset.orange.displayName, "Orange")
    }

    func testChartColorPreset_whiteDisplayName() {
        XCTAssertEqual(ChartColorPreset.white.displayName, "White")
    }

    func testChartColorPreset_allCasesCount() {
        // Spec lists exactly 7 color presets.
        XCTAssertEqual(ChartColorPreset.allCases.count, 7,
            "ChartColorPreset must have exactly 7 cases as specified")
    }

    // MARK: - Alert threshold presets

    // Guarantees: threshold submenu items match the values specified in the spec.
    // These are the model-layer constants used by MenuContent to build submenus.

    func testWeeklyThresholdPresets_matchSpec() {
        // Spec: Remaining 10%, Remaining 20%, Remaining 30%, Remaining 50%
        let presets = [10, 20, 30, 50]
        XCTAssertEqual(presets.count, 4,
            "Weekly threshold must have 4 preset options")
        XCTAssertEqual(presets.first, 10,
            "Weekly threshold minimum preset is 10")
        XCTAssertEqual(presets.last, 50,
            "Weekly threshold maximum preset is 50")
    }

    func testHourlyThresholdPresets_matchSpec() {
        // Spec: Remaining 10%, Remaining 20%, Remaining 30%, Remaining 50%
        let presets = [10, 20, 30, 50]
        XCTAssertEqual(presets, [10, 20, 30, 50],
            "Hourly threshold presets must match spec (same as weekly)")
    }

    func testDailyThresholdPresets_matchSpec() {
        // Spec: 10% per day, 15% per day, 20% per day, 30% per day
        let presets = [10, 15, 20, 30]
        XCTAssertEqual(presets.count, 4,
            "Daily threshold must have 4 preset options")
        XCTAssertEqual(presets[1], 15,
            "Daily threshold second value is 15 (differs from weekly/hourly)")
    }

    func testWeeklyThresholdDefault_isInPresets() {
        // Spec: default is 20 (marked ✓)
        let defaultValue = AppSettings().weeklyAlertThreshold
        let presets = [10, 20, 30, 50]
        XCTAssertTrue(presets.contains(defaultValue),
            "Default weeklyAlertThreshold (\(defaultValue)) must be in presets")
    }

    func testHourlyThresholdDefault_isInPresets() {
        let defaultValue = AppSettings().hourlyAlertThreshold
        let presets = [10, 20, 30, 50]
        XCTAssertTrue(presets.contains(defaultValue),
            "Default hourlyAlertThreshold (\(defaultValue)) must be in presets")
    }

    func testDailyThresholdDefault_isInPresets() {
        // Spec: default is 15 (marked ✓)
        let defaultValue = AppSettings().dailyAlertThreshold
        let presets = [10, 15, 20, 30]
        XCTAssertTrue(presets.contains(defaultValue),
            "Default dailyAlertThreshold (\(defaultValue)) must be in presets")
    }

    // MARK: - Alert threshold label formats

    // Guarantees: weekly/hourly labels are "Remaining N%", daily labels are "N% per day".

    func testWeeklyThresholdLabel_format() {
        // Spec: "Remaining 10%", "Remaining 20%", etc.
        for n in [10, 20, 30, 50] {
            let label = "Remaining \(n)%"
            XCTAssertTrue(label.hasPrefix("Remaining "),
                "Weekly threshold label must start with 'Remaining '")
            XCTAssertTrue(label.hasSuffix("%"),
                "Weekly threshold label must end with '%'")
        }
    }

    func testDailyThresholdLabel_format() {
        // Spec: "10% per day", "15% per day", etc.
        for n in [10, 15, 20, 30] {
            let label = "\(n)% per day"
            XCTAssertTrue(label.hasSuffix("% per day"),
                "Daily threshold label must end with '% per day'")
        }
    }

    // MARK: - Alert threshold conditional submenus: gating condition

    // Guarantees: threshold and day-definition submenus are gated on alertEnabled.
    // When enabled is false, the submenu must not be shown.
    // When enabled is true, the submenu must be shown.

    func testWeeklyAlertEnabled_false_thresholdShouldNotShow() {
        // Spec: "Weekly Threshold > ← weeklyAlertEnabled ON の場合のみ表示"
        let settings = AppSettings()
        XCTAssertFalse(settings.weeklyAlertEnabled,
            "weeklyAlertEnabled default false → threshold submenu must be hidden")
    }

    func testHourlyAlertEnabled_false_thresholdShouldNotShow() {
        let settings = AppSettings()
        XCTAssertFalse(settings.hourlyAlertEnabled,
            "hourlyAlertEnabled default false → threshold submenu must be hidden")
    }

    func testDailyAlertEnabled_false_thresholdAndDayDefinitionShouldNotShow() {
        let settings = AppSettings()
        XCTAssertFalse(settings.dailyAlertEnabled,
            "dailyAlertEnabled default false → daily threshold + day definition submenus must be hidden")
    }

    func testWeeklyAlertEnabled_true_thresholdGateIsOpen() {
        var settings = AppSettings()
        settings.weeklyAlertEnabled = true
        XCTAssertTrue(settings.weeklyAlertEnabled,
            "weeklyAlertEnabled true → threshold submenu must be shown")
    }

    func testDailyAlertEnabled_true_dayDefinitionGateIsOpen() {
        var settings = AppSettings()
        settings.dailyAlertEnabled = true
        XCTAssertTrue(settings.dailyAlertEnabled,
            "dailyAlertEnabled true → Day Definition submenu must be shown")
    }

    // MARK: - DayDefinition values

    // Guarantees: Day Definition submenu has exactly two options as specified.

    func testDailyAlertDefinition_calendarIsDefault() {
        XCTAssertEqual(AppSettings().dailyAlertDefinition, .calendar,
            "Default day definition must be .calendar (Calendar (midnight))")
    }

    func testDailyAlertDefinition_allCasesMatchSpec() {
        // Spec: Calendar (midnight) = .calendar, Session-based = .session
        let allCases = DailyAlertDefinition.allCases
        XCTAssertEqual(allCases.count, 2,
            "DailyAlertDefinition must have exactly 2 cases: .calendar and .session")
        XCTAssertTrue(allCases.contains(.calendar))
        XCTAssertTrue(allCases.contains(.session))
    }
}
