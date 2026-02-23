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

    func testParse_preservesRawJSON() throws {
        let json = #"{"windows":{"5h":{"limit":100,"remaining":50}}}"#
        let result = try UsageFetcher.parse(jsonString: json)
        XCTAssertEqual(result.rawJSON, json)
    }
}
