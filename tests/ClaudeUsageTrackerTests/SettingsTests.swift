import XCTest
@testable import ClaudeUsageTracker

final class SettingsTests: XCTestCase {

    // MARK: - Default Values

    func testDefaultValues() {
        let settings = AppSettings()
        XCTAssertEqual(settings.refreshIntervalMinutes, 5)
        XCTAssertFalse(settings.startAtLogin)
        XCTAssertTrue(settings.showHourlyGraph)
        XCTAssertTrue(settings.showWeeklyGraph)
        XCTAssertEqual(settings.chartWidth, 48)
        XCTAssertEqual(settings.hourlyColorPreset, .blue)
        XCTAssertEqual(settings.weeklyColorPreset, .pink)
    }

    func testPresetsContainsExpectedValues() {
        XCTAssertEqual(AppSettings.presets, [1, 2, 3, 5, 10, 20, 60])
    }

    // MARK: - Validation

    func testValidation_negativeInterval() {
        var settings = AppSettings()
        settings.refreshIntervalMinutes = -10
        let validated = settings.validated()
        XCTAssertEqual(validated.refreshIntervalMinutes, 5, "Negative value should fall back to default")
    }

    func testValidation_zeroInterval() {
        var settings = AppSettings()
        settings.refreshIntervalMinutes = 0
        let validated = settings.validated()
        XCTAssertEqual(validated.refreshIntervalMinutes, 0, "Zero should remain valid (auto-refresh disabled)")
    }

    func testValidation_positiveInterval() {
        var settings = AppSettings()
        settings.refreshIntervalMinutes = 42
        let validated = settings.validated()
        XCTAssertEqual(validated.refreshIntervalMinutes, 42, "Positive value should remain unchanged")
    }

    func testValidation_startAtLoginUnchanged() {
        var settings = AppSettings()
        settings.startAtLogin = true
        settings.refreshIntervalMinutes = -1
        let validated = settings.validated()
        XCTAssertTrue(validated.startAtLogin, "validated() should not modify startAtLogin")
        XCTAssertEqual(validated.refreshIntervalMinutes, 5, "Negative interval should be corrected")
    }

    func testValidation_chartWidthTooSmall() {
        var settings = AppSettings()
        settings.chartWidth = 5
        let validated = settings.validated()
        XCTAssertEqual(validated.chartWidth, 48, "Too-small width should reset to default")
    }

    func testValidation_chartWidthTooLarge() {
        var settings = AppSettings()
        settings.chartWidth = 200
        let validated = settings.validated()
        XCTAssertEqual(validated.chartWidth, 48, "Too-large width should reset to default")
    }

    func testValidation_chartWidthValid() {
        var settings = AppSettings()
        settings.chartWidth = 60
        let validated = settings.validated()
        XCTAssertEqual(validated.chartWidth, 60, "Valid width should remain unchanged")
    }

    // MARK: - JSON Encoding/Decoding

    func testJSONRoundTrip() throws {
        var original = AppSettings()
        original.refreshIntervalMinutes = 10
        original.startAtLogin = true
        original.showHourlyGraph = false
        original.showWeeklyGraph = true
        original.chartWidth = 60
        original.hourlyColorPreset = .teal
        original.weeklyColorPreset = .orange

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.refreshIntervalMinutes, 10)
        XCTAssertTrue(decoded.startAtLogin)
        XCTAssertFalse(decoded.showHourlyGraph)
        XCTAssertTrue(decoded.showWeeklyGraph)
        XCTAssertEqual(decoded.chartWidth, 60)
        XCTAssertEqual(decoded.hourlyColorPreset, .teal)
        XCTAssertEqual(decoded.weeklyColorPreset, .orange)
    }

    func testJSONSnakeCase() throws {
        var settings = AppSettings()
        settings.refreshIntervalMinutes = 3
        settings.startAtLogin = true

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(settings)
        let jsonString = String(data: data, encoding: .utf8)!

        XCTAssertTrue(jsonString.contains("refresh_interval_minutes"))
        XCTAssertTrue(jsonString.contains("start_at_login"))
        XCTAssertFalse(jsonString.contains("refreshIntervalMinutes"))
        XCTAssertFalse(jsonString.contains("startAtLogin"))
    }

    func testJSONMissingKey_refreshInterval() throws {
        // JSON with only start_at_login — refreshIntervalMinutes should get default
        let json = #"{"start_at_login": true}"#
        let data = json.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let settings = try decoder.decode(AppSettings.self, from: data)

        XCTAssertEqual(settings.refreshIntervalMinutes, 5, "Missing key should use default")
        XCTAssertTrue(settings.startAtLogin)
    }

    func testJSONMissingKey_startAtLogin() throws {
        // JSON with only refresh_interval_minutes — startAtLogin should get default
        let json = #"{"refresh_interval_minutes": 20}"#
        let data = json.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let settings = try decoder.decode(AppSettings.self, from: data)

        XCTAssertEqual(settings.refreshIntervalMinutes, 20)
        XCTAssertFalse(settings.startAtLogin, "Missing key should use default")
    }

    func testJSONMissingKey_newGraphFields() throws {
        // Old JSON without graph settings — should use defaults
        let json = #"{"refresh_interval_minutes": 5, "start_at_login": false}"#
        let data = json.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let settings = try decoder.decode(AppSettings.self, from: data)

        XCTAssertTrue(settings.showHourlyGraph)
        XCTAssertTrue(settings.showWeeklyGraph)
        XCTAssertEqual(settings.chartWidth, 48)
        XCTAssertEqual(settings.hourlyColorPreset, .blue)
        XCTAssertEqual(settings.weeklyColorPreset, .pink)
    }

    // MARK: - ChartColorPreset

    func testChartColorPreset_allCasesHaveDisplayName() {
        for preset in ChartColorPreset.allCases {
            XCTAssertFalse(preset.displayName.isEmpty, "\(preset.rawValue) should have a display name")
        }
    }

    func testChartColorPreset_jsonRoundTrip() throws {
        let presets = ChartColorPreset.allCases
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for preset in presets {
            let data = try encoder.encode(preset)
            let decoded = try decoder.decode(ChartColorPreset.self, from: data)
            XCTAssertEqual(decoded, preset)
        }
    }

    // MARK: - chartWidth Boundary Values

    func testValidation_chartWidthExactLowerBound() {
        var settings = AppSettings()
        settings.chartWidth = 12
        let validated = settings.validated()
        XCTAssertEqual(validated.chartWidth, 12, "chartWidth 12 is valid (lower bound)")
    }

    func testValidation_chartWidthExactUpperBound() {
        var settings = AppSettings()
        settings.chartWidth = 120
        let validated = settings.validated()
        XCTAssertEqual(validated.chartWidth, 120, "chartWidth 120 is valid (upper bound)")
    }

    func testValidation_chartWidthJustBelowLowerBound() {
        var settings = AppSettings()
        settings.chartWidth = 11
        let validated = settings.validated()
        XCTAssertEqual(validated.chartWidth, 48, "chartWidth 11 should reset to default")
    }

    func testValidation_chartWidthJustAboveUpperBound() {
        var settings = AppSettings()
        settings.chartWidth = 121
        let validated = settings.validated()
        XCTAssertEqual(validated.chartWidth, 48, "chartWidth 121 should reset to default")
    }

    func testChartWidthPresetsContent() {
        XCTAssertEqual(AppSettings.chartWidthPresets, [12, 24, 36, 48, 60, 72])
    }

    // MARK: - validated() both invalid simultaneously

    func testValidation_bothInvalid() {
        var settings = AppSettings()
        settings.refreshIntervalMinutes = -5
        settings.chartWidth = 999
        let validated = settings.validated()
        XCTAssertEqual(validated.refreshIntervalMinutes, 5,
                       "Both invalid: interval should reset to default")
        XCTAssertEqual(validated.chartWidth, 48,
                       "Both invalid: chartWidth should reset to default")
    }

    // MARK: - ChartColorPreset.color (verify no crash for each preset)

    func testChartColorPreset_colorDoesNotCrash() {
        for preset in ChartColorPreset.allCases {
            // Accessing .color should not crash
            let _ = preset.color
        }
    }

    // MARK: - Decode with wrong type (type mismatch → throws)

    func testDecode_wrongType_throws() {
        // refreshIntervalMinutes is Int, but JSON has String → decodeIfPresent throws
        let json = #"{"refresh_interval_minutes": "five"}"#
        let data = json.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        XCTAssertThrowsError(try decoder.decode(AppSettings.self, from: data),
                             "Type mismatch (String instead of Int) should throw, not use default")
    }

    func testDecode_wrongType_boolAsString_throws() {
        let json = #"{"start_at_login": "yes"}"#
        let data = json.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        XCTAssertThrowsError(try decoder.decode(AppSettings.self, from: data),
                             "Type mismatch (String instead of Bool) should throw")
    }

    // MARK: - Alert Settings: Default Values

    func testAlertDefaultValues() {
        let settings = AppSettings()
        XCTAssertFalse(settings.weeklyAlertEnabled)
        XCTAssertEqual(settings.weeklyAlertThreshold, 20)
        XCTAssertFalse(settings.hourlyAlertEnabled)
        XCTAssertEqual(settings.hourlyAlertThreshold, 20)
        XCTAssertFalse(settings.dailyAlertEnabled)
        XCTAssertEqual(settings.dailyAlertThreshold, 15)
        XCTAssertEqual(settings.dailyAlertDefinition, .calendar)
    }

    // MARK: - Alert Settings: Backward Compatibility

    func testJSONMissingKey_alertFields() throws {
        // Old JSON without alert settings — should use defaults
        let json = #"{"refresh_interval_minutes": 5, "start_at_login": false}"#
        let data = json.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let settings = try decoder.decode(AppSettings.self, from: data)

        XCTAssertFalse(settings.weeklyAlertEnabled)
        XCTAssertEqual(settings.weeklyAlertThreshold, 20)
        XCTAssertFalse(settings.hourlyAlertEnabled)
        XCTAssertEqual(settings.hourlyAlertThreshold, 20)
        XCTAssertFalse(settings.dailyAlertEnabled)
        XCTAssertEqual(settings.dailyAlertThreshold, 15)
        XCTAssertEqual(settings.dailyAlertDefinition, .calendar)
    }

    // MARK: - Alert Settings: JSON Round Trip

    func testAlertJSONRoundTrip() throws {
        var original = AppSettings()
        original.weeklyAlertEnabled = true
        original.weeklyAlertThreshold = 30
        original.hourlyAlertEnabled = true
        original.hourlyAlertThreshold = 10
        original.dailyAlertEnabled = true
        original.dailyAlertThreshold = 25
        original.dailyAlertDefinition = .session

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(AppSettings.self, from: data)

        XCTAssertTrue(decoded.weeklyAlertEnabled)
        XCTAssertEqual(decoded.weeklyAlertThreshold, 30)
        XCTAssertTrue(decoded.hourlyAlertEnabled)
        XCTAssertEqual(decoded.hourlyAlertThreshold, 10)
        XCTAssertTrue(decoded.dailyAlertEnabled)
        XCTAssertEqual(decoded.dailyAlertThreshold, 25)
        XCTAssertEqual(decoded.dailyAlertDefinition, .session)
    }

    // MARK: - Alert Settings: Threshold Validation

    func testValidation_alertThreshold_clampToMin() {
        var settings = AppSettings()
        settings.weeklyAlertThreshold = 0
        settings.hourlyAlertThreshold = -5
        settings.dailyAlertThreshold = 0
        let validated = settings.validated()
        XCTAssertEqual(validated.weeklyAlertThreshold, 1, "Threshold 0 should clamp to 1")
        XCTAssertEqual(validated.hourlyAlertThreshold, 1, "Threshold -5 should clamp to 1")
        XCTAssertEqual(validated.dailyAlertThreshold, 1, "Threshold 0 should clamp to 1")
    }

    func testValidation_alertThreshold_clampToMax() {
        var settings = AppSettings()
        settings.weeklyAlertThreshold = 101
        settings.hourlyAlertThreshold = 200
        settings.dailyAlertThreshold = 150
        let validated = settings.validated()
        XCTAssertEqual(validated.weeklyAlertThreshold, 100, "Threshold 101 should clamp to 100")
        XCTAssertEqual(validated.hourlyAlertThreshold, 100, "Threshold 200 should clamp to 100")
        XCTAssertEqual(validated.dailyAlertThreshold, 100, "Threshold 150 should clamp to 100")
    }

    func testValidation_alertThreshold_validRange() {
        var settings = AppSettings()
        settings.weeklyAlertThreshold = 1
        settings.hourlyAlertThreshold = 50
        settings.dailyAlertThreshold = 100
        let validated = settings.validated()
        XCTAssertEqual(validated.weeklyAlertThreshold, 1, "Threshold 1 is valid (lower bound)")
        XCTAssertEqual(validated.hourlyAlertThreshold, 50, "Threshold 50 is valid")
        XCTAssertEqual(validated.dailyAlertThreshold, 100, "Threshold 100 is valid (upper bound)")
    }

    // MARK: - DailyAlertDefinition

    func testDailyAlertDefinition_jsonRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for definition in DailyAlertDefinition.allCases {
            let data = try encoder.encode(definition)
            let decoded = try decoder.decode(DailyAlertDefinition.self, from: data)
            XCTAssertEqual(decoded, definition)
        }
    }

    func testDailyAlertDefinition_rawValues() {
        XCTAssertEqual(DailyAlertDefinition.calendar.rawValue, "calendar")
        XCTAssertEqual(DailyAlertDefinition.session.rawValue, "session")
    }

    // MARK: - Alert Settings: Snake Case Keys

    func testAlertJSONSnakeCase() throws {
        var settings = AppSettings()
        settings.weeklyAlertEnabled = true
        settings.dailyAlertDefinition = .session

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(settings)
        let jsonString = String(data: data, encoding: .utf8)!

        XCTAssertTrue(jsonString.contains("weekly_alert_enabled"))
        XCTAssertTrue(jsonString.contains("daily_alert_definition"))
        XCTAssertFalse(jsonString.contains("weeklyAlertEnabled"))
        XCTAssertFalse(jsonString.contains("dailyAlertDefinition"))
    }
}
