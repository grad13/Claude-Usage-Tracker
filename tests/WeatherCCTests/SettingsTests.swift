import XCTest
@testable import WeatherCC

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
}
