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
}
