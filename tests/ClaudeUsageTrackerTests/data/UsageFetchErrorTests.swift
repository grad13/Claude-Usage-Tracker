// meta: updated=2026-03-04 06:28 checked=-
import XCTest
@testable import ClaudeUsageTracker

// MARK: - UsageFetchError Tests

final class UsageFetchErrorTests: XCTestCase {

    // MARK: - isAuthError

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

    func testIsAuthError_mixedCase() {
        let error = UsageFetchError.scriptFailed("MISSING ORGANIZATION ID")
        XCTAssertTrue(error.isAuthError, "isAuthError uses lowercased(), mixed case should match")
    }

    // MARK: - errorDescription

    func testUsageFetchError_errorDescription() {
        let scriptErr = UsageFetchError.scriptFailed("HTTP 500")
        XCTAssertEqual(scriptErr.errorDescription, "HTTP 500")

        let decodingErr = UsageFetchError.decodingFailed
        XCTAssertEqual(decodingErr.errorDescription, "Failed to decode usage data")
    }
}
