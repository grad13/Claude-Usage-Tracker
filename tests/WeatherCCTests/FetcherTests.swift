import XCTest
@testable import WeatherCC

final class FetcherTests: XCTestCase {

    // MARK: - usagePercent / resetsAtDate (tested via UsageResult construction helpers)
    // These helpers are private, so we test indirectly via the parsing output.
    // For unit tests, we test the UsageViewModel's time progress and remaining text instead.

    // MARK: - UsageFetchError.isAuthError

    func testIsAuthError_missingOrganization() {
        let error = UsageFetchError.scriptFailed("Missing organization id")
        XCTAssertTrue(error.isAuthError)
    }

    func testIsAuthError_http401() {
        let error = UsageFetchError.scriptFailed("HTTP 401")
        XCTAssertTrue(error.isAuthError)
    }

    func testIsAuthError_http403() {
        let error = UsageFetchError.scriptFailed("HTTP 403")
        XCTAssertTrue(error.isAuthError)
    }

    func testIsAuthError_otherError() {
        let error = UsageFetchError.scriptFailed("HTTP 500")
        XCTAssertFalse(error.isAuthError)
    }

    func testIsAuthError_decodingFailed() {
        let error = UsageFetchError.decodingFailed
        XCTAssertFalse(error.isAuthError)
    }

    // MARK: - parseResetDate

    func testParseResetDate_iso8601() {
        let date = UsageFetcher.parseResetDate("2026-02-22T12:00:00Z")
        XCTAssertNotNil(date)
        // Verify it's the correct date (noon UTC on 2026-02-22)
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: date!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 22)
        XCTAssertEqual(components.hour, 12)
    }

    func testParseResetDate_fractional() {
        let date = UsageFetcher.parseResetDate("2026-02-22T12:00:00.123Z")
        XCTAssertNotNil(date)
    }

    func testParseResetDate_highPrecision() {
        // 6-digit fractional seconds (trimmed to 3)
        let date = UsageFetcher.parseResetDate("2026-02-22T12:00:00.123456Z")
        XCTAssertNotNil(date)
    }

    func testParseResetDate_nil() {
        XCTAssertNil(UsageFetcher.parseResetDate(nil))
    }

    // MARK: - parseStatus

    func testParseStatus_withinLimit() {
        XCTAssertEqual(UsageFetcher.parseStatus("within_limit"), 0)
    }

    func testParseStatus_approachingLimit() {
        XCTAssertEqual(UsageFetcher.parseStatus("approaching_limit"), 1)
    }

    func testParseStatus_exceededLimit() {
        XCTAssertEqual(UsageFetcher.parseStatus("exceeded_limit"), 2)
    }

    func testParseStatus_unknown() {
        XCTAssertNil(UsageFetcher.parseStatus("foo"))
    }

    // MARK: - trimFractionalSeconds

    func testTrimFractionalSeconds_noDot() {
        XCTAssertNil(UsageFetcher.trimFractionalSeconds("2026-02-22T12:00:00Z"),
                     "No dot → should return nil")
    }

    func testTrimFractionalSeconds_exactly3Digits() {
        let input = "2026-02-22T12:00:00.123Z"
        XCTAssertEqual(UsageFetcher.trimFractionalSeconds(input), input,
                       "Exactly 3 fractional digits → return original")
    }

    func testTrimFractionalSeconds_fewerThan3Digits() {
        let input = "2026-02-22T12:00:00.1Z"
        XCTAssertEqual(UsageFetcher.trimFractionalSeconds(input), input,
                       "Fewer than 3 fractional digits → return original")
    }

    func testTrimFractionalSeconds_moreThan3Digits() {
        let result = UsageFetcher.trimFractionalSeconds("2026-02-22T12:00:00.123456Z")
        XCTAssertEqual(result, "2026-02-22T12:00:00.123Z",
                       "6 fractional digits → trimmed to 3")
    }

    func testTrimFractionalSeconds_timezoneOffset() {
        let result = UsageFetcher.trimFractionalSeconds("2026-02-22T12:00:00.123456+05:30")
        XCTAssertEqual(result, "2026-02-22T12:00:00.123+05:30",
                       "Should handle + timezone offset")
    }

    func testTrimFractionalSeconds_noSuffix() {
        XCTAssertNil(UsageFetcher.trimFractionalSeconds("2026-02-22T12:00:00.123456"),
                     "No Z/+/- suffix → should return nil")
    }

    func testTrimFractionalSeconds_negativeTimezoneOffset() {
        let result = UsageFetcher.trimFractionalSeconds("2026-02-22T12:00:00.123456-05:00")
        XCTAssertEqual(result, "2026-02-22T12:00:00.123-05:00",
                       "Should handle - timezone offset")
    }

    func testIsAuthError_mixedCase() {
        let error = UsageFetchError.scriptFailed("MISSING ORGANIZATION ID")
        XCTAssertTrue(error.isAuthError, "isAuthError uses lowercased(), mixed case should match")
    }

    func testParseResetDate_completelyInvalid() {
        XCTAssertNil(UsageFetcher.parseResetDate("not a date at all"))
    }

    // MARK: - parseStatus nil input

    func testParseStatus_nil() {
        XCTAssertNil(UsageFetcher.parseStatus(nil),
                     "nil input should return nil")
    }

    // MARK: - parseResetDate: high precision with positive timezone offset

    func testParseResetDate_highPrecisionWithPositiveOffset() {
        // Forces the trimFractionalSeconds path + non-Z timezone suffix
        let date = UsageFetcher.parseResetDate("2026-02-22T12:00:00.123456+05:30")
        XCTAssertNotNil(date, "High-precision timestamp with +offset should parse via trim path")
    }

    func testUsageFetchError_errorDescription() {
        let scriptErr = UsageFetchError.scriptFailed("HTTP 500")
        XCTAssertEqual(scriptErr.errorDescription, "HTTP 500")

        let decodingErr = UsageFetchError.decodingFailed
        XCTAssertEqual(decodingErr.errorDescription, "Failed to decode usage data")
    }

    // MARK: - calcPercent

    func testCalcPercent_normal() {
        let result = UsageFetcher.calcPercent(limit: 100.0, remaining: 47.0)
        XCTAssertEqual(result!, 53.0, accuracy: 0.001)
    }

    func testCalcPercent_zeroRemaining() {
        let result = UsageFetcher.calcPercent(limit: 100.0, remaining: 0.0)
        XCTAssertEqual(result!, 100.0, accuracy: 0.001)
    }

    func testCalcPercent_fullRemaining() {
        let result = UsageFetcher.calcPercent(limit: 100.0, remaining: 100.0)
        XCTAssertEqual(result!, 0.0, accuracy: 0.001)
    }

    func testCalcPercent_nilLimit() {
        XCTAssertNil(UsageFetcher.calcPercent(limit: nil, remaining: 50.0))
    }

    func testCalcPercent_zeroLimit() {
        XCTAssertNil(UsageFetcher.calcPercent(limit: 0.0, remaining: 0.0))
    }

    func testCalcPercent_intValues() {
        // API may return Int instead of Double
        let result = UsageFetcher.calcPercent(limit: 100 as Int, remaining: 25 as Int)
        XCTAssertEqual(result!, 75.0, accuracy: 0.001)
    }

    // MARK: - parseUnixTimestamp

    func testParseUnixTimestamp_valid() {
        let date = UsageFetcher.parseUnixTimestamp(1740000000.0)
        XCTAssertNotNil(date)
        XCTAssertEqual(date!.timeIntervalSince1970, 1740000000.0, accuracy: 0.001)
    }

    func testParseUnixTimestamp_nil() {
        XCTAssertNil(UsageFetcher.parseUnixTimestamp(nil))
    }

    func testParseUnixTimestamp_string() {
        // String value should not be parsed (type mismatch)
        XCTAssertNil(UsageFetcher.parseUnixTimestamp("1740000000"))
    }

    func testParseUnixTimestamp_int() {
        // API may return Int instead of Double
        let date = UsageFetcher.parseUnixTimestamp(1740000000 as Int)
        XCTAssertNotNil(date)
        XCTAssertEqual(date!.timeIntervalSince1970, 1740000000.0, accuracy: 0.001)
    }

    // MARK: - parse(jsonString:) — testable without WebView

    func testParse_validAPIResponse() throws {
        let json = """
        {"windows":{"5h":{"status":"within_limit","resets_at":1740000000,"limit":100,"remaining":47},"7d":{"status":"approaching_limit","resets_at":1740500000,"limit":200,"remaining":170}}}
        """
        let result = try UsageFetcher.parse(jsonString: json)
        XCTAssertEqual(result.fiveHourPercent!, 53.0, accuracy: 0.001)
        XCTAssertEqual(result.sevenDayPercent!, 15.0, accuracy: 0.001)
        XCTAssertEqual(result.fiveHourResetsAt!.timeIntervalSince1970, 1740000000, accuracy: 0.001)
        XCTAssertEqual(result.sevenDayResetsAt!.timeIntervalSince1970, 1740500000, accuracy: 0.001)
        XCTAssertEqual(result.fiveHourStatus, 0)
        XCTAssertEqual(result.sevenDayStatus, 1)
        XCTAssertEqual(result.fiveHourLimit, 100.0)
        XCTAssertEqual(result.fiveHourRemaining, 47.0)
    }

    func testParse_errorResponse() {
        let json = #"{"__error":"Missing organization id"}"#
        XCTAssertThrowsError(try UsageFetcher.parse(jsonString: json)) { error in
            guard let fetchError = error as? UsageFetchError else {
                XCTFail("Expected UsageFetchError")
                return
            }
            XCTAssertTrue(fetchError.isAuthError)
        }
    }

    func testParse_emptyWindows() throws {
        let json = #"{"windows":{}}"#
        let result = try UsageFetcher.parse(jsonString: json)
        XCTAssertNil(result.fiveHourPercent)
        XCTAssertNil(result.sevenDayPercent)
    }

    func testParse_invalidJSON() {
        XCTAssertThrowsError(try UsageFetcher.parse(jsonString: "not json at all"))
    }

    func testParse_missingWindowsKey() throws {
        let json = #"{"something":"else"}"#
        let result = try UsageFetcher.parse(jsonString: json)
        XCTAssertNil(result.fiveHourPercent)
        XCTAssertNil(result.sevenDayPercent)
    }

    func testParse_integerLimitAndRemaining() throws {
        // API may return integers instead of doubles
        let json = #"{"windows":{"5h":{"status":"within_limit","resets_at":1740000000,"limit":100,"remaining":25}}}"#
        let result = try UsageFetcher.parse(jsonString: json)
        XCTAssertEqual(result.fiveHourPercent!, 75.0, accuracy: 0.001)
    }

    // MARK: - Format A: five_hour/utilization (actual API response 2026-02)

    func testParse_formatA_realResponse() throws {
        let json = """
        {"five_hour":{"utilization":25,"resets_at":"2026-02-23T10:00:00.696818+00:00"},\
        "seven_day":{"utilization":54,"resets_at":"2026-02-27T08:00:00.696853+00:00"},\
        "seven_day_sonnet":{"utilization":11,"resets_at":"2026-02-25T06:59:59.696861+00:00"}}
        """
        let result = try UsageFetcher.parse(jsonString: json)
        XCTAssertEqual(result.fiveHourPercent!, 25.0, accuracy: 0.001)
        XCTAssertEqual(result.sevenDayPercent!, 54.0, accuracy: 0.001)
        XCTAssertNotNil(result.fiveHourResetsAt)
        XCTAssertNotNil(result.sevenDayResetsAt)
    }

    func testParse_formatA_integerUtilization() throws {
        let json = #"{"five_hour":{"utilization":0},"seven_day":{"utilization":100}}"#
        let result = try UsageFetcher.parse(jsonString: json)
        XCTAssertEqual(result.fiveHourPercent!, 0.0, accuracy: 0.001)
        XCTAssertEqual(result.sevenDayPercent!, 100.0, accuracy: 0.001)
    }

    func testParsePercent_utilization() {
        let window: [String: Any] = ["utilization": 42]
        XCTAssertEqual(UsageFetcher.parsePercent(window)!, 42.0, accuracy: 0.001)
    }

    func testParsePercent_limitRemaining() {
        let window: [String: Any] = ["limit": 100.0, "remaining": 25.0]
        XCTAssertEqual(UsageFetcher.parsePercent(window)!, 75.0, accuracy: 0.001)
    }

    func testParsePercent_nil() {
        XCTAssertNil(UsageFetcher.parsePercent(nil))
    }

    func testParseResetsAt_isoString() {
        let date = UsageFetcher.parseResetsAt("2026-02-23T10:00:00.696818+00:00")
        XCTAssertNotNil(date)
    }

    func testParseResetsAt_unixTimestamp() {
        let date = UsageFetcher.parseResetsAt(1740000000.0)
        XCTAssertNotNil(date)
        XCTAssertEqual(date!.timeIntervalSince1970, 1740000000.0, accuracy: 0.001)
    }

    func testParseResetsAt_nil() {
        XCTAssertNil(UsageFetcher.parseResetsAt(nil))
    }

    func testParse_preservesRawJSON() throws {
        let json = #"{"windows":{"5h":{"limit":100,"remaining":50}}}"#
        let result = try UsageFetcher.parse(jsonString: json)
        XCTAssertEqual(result.rawJSON, json)
    }

    // MARK: - Format A: Real API response from debug log (2026-02-23)

    func testParse_formatA_realDebugLogResponse() throws {
        // Exact response captured in WeatherCC-debug.log
        let json = """
        {"five_hour":{"utilization":26,"resets_at":"2026-02-23T10:00:00.739124+00:00"},\
        "seven_day":{"utilization":54,"resets_at":"2026-02-27T08:00:00.739142+00:00"},\
        "seven_day_oauth_apps":null,"seven_day_opus":null,\
        "seven_day_sonnet":{"utilization":11,"resets_at":"2026-02-25T06:59:59.739150+00:00"},\
        "seven_day_cowork":null,"iguana_necktie":null,"extra_usage":null,\
        "__diag":"S1:OK,orgId=d7315981..."}
        """
        let result = try UsageFetcher.parse(jsonString: json)
        XCTAssertEqual(result.fiveHourPercent!, 26.0, accuracy: 0.001)
        XCTAssertEqual(result.sevenDayPercent!, 54.0, accuracy: 0.001)
        XCTAssertNotNil(result.fiveHourResetsAt)
        XCTAssertNotNil(result.sevenDayResetsAt)
        // Verify that extra keys (seven_day_sonnet, iguana_necktie, etc.) don't break parsing
    }

    func testParse_formatA_onlyFiveHour() throws {
        let json = #"{"five_hour":{"utilization":50}}"#
        let result = try UsageFetcher.parse(jsonString: json)
        XCTAssertEqual(result.fiveHourPercent!, 50.0, accuracy: 0.001)
        XCTAssertNil(result.sevenDayPercent, "Missing seven_day should yield nil")
    }

    func testParse_formatA_onlySevenDay() throws {
        let json = #"{"seven_day":{"utilization":75}}"#
        let result = try UsageFetcher.parse(jsonString: json)
        XCTAssertNil(result.fiveHourPercent, "Missing five_hour should yield nil")
        XCTAssertEqual(result.sevenDayPercent!, 75.0, accuracy: 0.001)
    }

    func testParse_formatA_utilizationAsDouble() throws {
        let json = #"{"five_hour":{"utilization":25.5},"seven_day":{"utilization":54.3}}"#
        let result = try UsageFetcher.parse(jsonString: json)
        XCTAssertEqual(result.fiveHourPercent!, 25.5, accuracy: 0.001)
        XCTAssertEqual(result.sevenDayPercent!, 54.3, accuracy: 0.001)
    }

    func testParse_formatA_diagFieldIgnored() throws {
        let json = #"{"five_hour":{"utilization":10},"__diag":"S1:OK"}"#
        let result = try UsageFetcher.parse(jsonString: json)
        XCTAssertEqual(result.fiveHourPercent!, 10.0, accuracy: 0.001)
    }

    func testParse_formatA_nullWindowsIgnored() throws {
        let json = #"{"five_hour":{"utilization":10},"seven_day_opus":null,"iguana_necktie":null}"#
        let result = try UsageFetcher.parse(jsonString: json)
        XCTAssertEqual(result.fiveHourPercent!, 10.0, accuracy: 0.001)
    }

    // MARK: - Format B: limit/remaining edge cases

    func testParse_formatB_onlyFiveHour() throws {
        let json = #"{"windows":{"5h":{"limit":100,"remaining":75}}}"#
        let result = try UsageFetcher.parse(jsonString: json)
        XCTAssertEqual(result.fiveHourPercent!, 25.0, accuracy: 0.001)
        XCTAssertNil(result.sevenDayPercent, "Missing 7d window should yield nil")
    }

    func testParse_formatB_zeroRemaining() throws {
        let json = #"{"windows":{"5h":{"limit":100,"remaining":0},"7d":{"limit":200,"remaining":0}}}"#
        let result = try UsageFetcher.parse(jsonString: json)
        XCTAssertEqual(result.fiveHourPercent!, 100.0, accuracy: 0.001)
        XCTAssertEqual(result.sevenDayPercent!, 100.0, accuracy: 0.001)
    }

    // MARK: - parseResetsAt edge cases

    func testParseResetsAt_intTimestamp() {
        let date = UsageFetcher.parseResetsAt(1740000000 as Int)
        XCTAssertNotNil(date)
        XCTAssertEqual(date!.timeIntervalSince1970, 1740000000.0, accuracy: 0.001)
    }

    func testParseResetsAt_invalidType() {
        let date = UsageFetcher.parseResetsAt([1, 2, 3])  // Array, not String or Number
        XCTAssertNil(date, "Invalid type should return nil")
    }

    // MARK: - parsePercent edge cases

    func testParsePercent_emptyDict() {
        let result = UsageFetcher.parsePercent([:])
        XCTAssertNil(result, "Empty dict has neither utilization nor limit/remaining")
    }

    func testParsePercent_utilizationZero() {
        let result = UsageFetcher.parsePercent(["utilization": 0])
        XCTAssertEqual(result!, 0.0, accuracy: 0.001)
    }

    func testParsePercent_utilizationDouble() {
        let result = UsageFetcher.parsePercent(["utilization": 33.3])
        XCTAssertEqual(result!, 33.3, accuracy: 0.001)
    }

    func testParsePercent_utilizationTakesPrecedence() {
        // If both utilization and limit/remaining exist, utilization wins
        let window: [String: Any] = [
            "utilization": 42,
            "limit": 100.0,
            "remaining": 25.0
        ]
        XCTAssertEqual(UsageFetcher.parsePercent(window)!, 42.0, accuracy: 0.001,
                       "utilization should take precedence over limit/remaining")
    }

    // MARK: - Error response edge cases

    func testParse_errorWithEmptyMessage() {
        let json = #"{"__error":""}"#
        XCTAssertThrowsError(try UsageFetcher.parse(jsonString: json)) { error in
            guard let fetchError = error as? UsageFetchError else {
                XCTFail("Expected UsageFetchError")
                return
            }
            XCTAssertFalse(fetchError.isAuthError, "Empty error message is not auth error")
        }
    }

    func testParse_errorWithHTTPStatus() {
        let json = #"{"__error":"HTTP 500 [S1:OK,S2:MISS]"}"#
        XCTAssertThrowsError(try UsageFetcher.parse(jsonString: json)) { error in
            guard let fetchError = error as? UsageFetchError else {
                XCTFail("Expected UsageFetchError")
                return
            }
            XCTAssertFalse(fetchError.isAuthError, "HTTP 500 is not auth error")
        }
    }
}
