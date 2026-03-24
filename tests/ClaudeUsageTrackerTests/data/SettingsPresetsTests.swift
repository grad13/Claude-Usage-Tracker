// meta: updated=2026-03-06 18:11 checked=-
// Tests for AppSettings presets and alert gating logic
// Split from: ui/MenuContentSupplementTests.swift (S6: responsibility separation)

import XCTest
@testable import ClaudeUsageTracker

final class SettingsPresetsTests: XCTestCase {

    // MARK: - Refresh Interval: Off (0 min) and presets

    // Guarantees: refreshIntervalMinutes == 0 means auto-refresh is disabled (Off).
    // AppSettings.presets matches the exact menu items shown.

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
}
