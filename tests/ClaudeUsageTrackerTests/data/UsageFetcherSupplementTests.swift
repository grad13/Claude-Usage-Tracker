// Supplement for: tests/ClaudeUsageTrackerTests/FetcherTests.swift
// Generated from: _documents/spec/data/usage-fetcher.md
// Generated: 2026-03-03
//
// Coverage:
//   - UsageFetchError.isAuthError edge cases (partial match, diag suffix)
//   - parseStatus edge cases (empty string)
//   - calcPercent edge cases (negative remaining, non-numeric Any inputs)
//   - parsePercent edge cases (non-numeric utilization, missing keys)
//   - parseResetsAt edge cases (intTimestamp as Any, booleanValue)
//   - parse(jsonString:) Format B with status field present
//   - parse(jsonString:) Format A/B disambiguation (__error with auth substrings)
//   - parse(jsonString:) rawJSON preserved for Format A
//   - parse(jsonString:) decodingFailed path (non-string body)
//   - hasValidSession / fetch: WebView-dependent — skipped with rationale
//
// NOTE on WebView-dependent functions:
//   hasValidSession(using:) and fetch(using:) require a live WKWebView with an
//   active browser session (cookies, JavaScript context).
//   They cannot be tested without a real WebView because:
//     1. WKWebView cannot be meaningfully stubbed at the interface level; the methods
//        take a concrete WKWebView, not a protocol.
//     2. callAsyncJavaScript relies on a live WKProcess context.
//     3. WKHTTPCookieStore.allCookies() requires an actual website data store.
//   To make these testable, UsageFetcher would need to be refactored to accept a
//   protocol (e.g., CookieStoreProvider, JSExecutor) — see architecture.md §protocols.
//   Until that refactor lands, only parse(jsonString:) and pure static helpers are
//   unit-testable.

import XCTest
@testable import ClaudeUsageTracker

final class UsageFetcherSupplementTests: XCTestCase {

    // MARK: - UsageFetchError.isAuthError — partial match inside longer messages

    /// Spec: isAuthError checks lowercased message for "missing organization".
    /// The JS script appends diag info: "Missing organization id [S1:MISS,S2:MISS,S3:MISS,S4:...]"
    func testIsAuthError_missingOrganizationWithDiagSuffix() {
        let error = UsageFetchError.scriptFailed("Missing organization id [S1:MISS,S2:MISS,S3:MISS,S4:HTTP200]")
        XCTAssertTrue(error.isAuthError,
                      "Diag suffix appended to 'missing organization' must still be recognised as auth error")
    }

    /// Spec: "http 401" match is case-insensitive.
    func testIsAuthError_http401_lowercase() {
        let error = UsageFetchError.scriptFailed("http 401 unauthorized")
        XCTAssertTrue(error.isAuthError)
    }

    /// Spec: "http 403" match is case-insensitive.
    func testIsAuthError_http403_withPath() {
        let error = UsageFetchError.scriptFailed("http 403 [S1:OK,S4:HTTP403 /api/usage]")
        XCTAssertTrue(error.isAuthError)
    }

    /// Spec: error message containing "http 402" (payment required) is NOT an auth error.
    func testIsAuthError_http402_notAuth() {
        let error = UsageFetchError.scriptFailed("HTTP 402 Payment Required")
        XCTAssertFalse(error.isAuthError)
    }

    /// Spec: decodingFailed is always false regardless of context.
    func testIsAuthError_decodingFailed_alwaysFalse() {
        XCTAssertFalse(UsageFetchError.decodingFailed.isAuthError)
    }

    // MARK: - parseStatus — edge cases not in FetcherTests

    /// Spec: any string other than the three known values → nil.
    func testParseStatus_emptyString() {
        XCTAssertNil(UsageFetcher.parseStatus(""),
                     "Empty string is not a valid status")
    }

    /// Spec: leading/trailing whitespace is not normalised — should return nil.
    func testParseStatus_withLeadingSpace() {
        XCTAssertNil(UsageFetcher.parseStatus(" within_limit"),
                     "Whitespace-padded string is not a valid status")
    }

    /// Spec: status values are lowercase only; uppercase variant should be nil.
    func testParseStatus_uppercaseVariant() {
        XCTAssertNil(UsageFetcher.parseStatus("Within_Limit"),
                     "Status matching is case-sensitive per spec")
    }

    // MARK: - calcPercent — edge cases

    /// Spec: remaining > limit is numerically valid; result would be negative percent.
    /// The spec does not explicitly cap at 0, so the raw formula result is returned.
    func testCalcPercent_remainingExceedsLimit() {
        let result = UsageFetcher.calcPercent(limit: 100.0, remaining: 150.0)
        // (100 - 150) / 100 * 100 = -50 — formula result, not clamped per spec
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, -50.0, accuracy: 0.001)
    }

    /// Spec: nil remaining → nil.
    func testCalcPercent_nilRemaining() {
        XCTAssertNil(UsageFetcher.calcPercent(limit: 100.0, remaining: nil))
    }

    /// Spec: negative limit (≤ 0) → nil.
    func testCalcPercent_negativeLimitIsNil() {
        XCTAssertNil(UsageFetcher.calcPercent(limit: -1.0, remaining: 50.0),
                     "Negative limit must return nil (limit ≤ 0 guard)")
    }

    /// Spec: both nil → nil.
    func testCalcPercent_bothNil() {
        XCTAssertNil(UsageFetcher.calcPercent(limit: nil, remaining: nil))
    }

    // MARK: - parsePercent — non-numeric / invalid utilization

    /// Spec: parsePercent reads "utilization" as Double or Int.
    /// A String value for utilization is not a valid numeric type → falls through to calcPercent path.
    func testParsePercent_utilizationAsString_fallsToCalcPercent() {
        // "utilization" is String, not Double/Int → calcPercent path
        // No limit/remaining either → nil
        let result = UsageFetcher.parsePercent(["utilization": "25"])
        XCTAssertNil(result,
                     "String utilization cannot be parsed as numeric; no limit/remaining → nil")
    }

    /// Spec: dict with only "remaining" but no "limit" → calcPercent returns nil.
    func testParsePercent_onlyRemainingNoLimit() {
        let result = UsageFetcher.parsePercent(["remaining": 25.0])
        XCTAssertNil(result, "remaining without limit → calcPercent returns nil")
    }

    /// Spec: dict with only "limit" but no "remaining" → calcPercent returns nil.
    func testParsePercent_onlyLimitNoRemaining() {
        let result = UsageFetcher.parsePercent(["limit": 100.0])
        XCTAssertNil(result, "limit without remaining → calcPercent returns nil")
    }

    // MARK: - parseResetsAt — additional type cases

    /// Spec: String value → parseResetDate ISO 8601 path.
    func testParseResetsAt_isoWithFractionalAndOffset() {
        let date = UsageFetcher.parseResetsAt("2026-02-23T10:00:00.123456+00:00")
        XCTAssertNotNil(date, "High-precision ISO 8601 string with offset should parse via trim path")
    }

    /// Spec: Array type is neither String nor numeric → nil.
    func testParseResetsAt_booleanValue_isNil() {
        // Bool is not String, Double, or Int — should return nil
        let date = UsageFetcher.parseResetsAt(true)
        XCTAssertNil(date, "Bool value is not a recognised type for parseResetsAt")
    }

    /// Spec: parseResetsAt accepts Int Unix timestamps.
    func testParseResetsAt_intTimestamp_epoch() {
        let date = UsageFetcher.parseResetsAt(0 as Int)
        XCTAssertNotNil(date)
        XCTAssertEqual(date!.timeIntervalSince1970, 0.0, accuracy: 0.001,
                       "Int 0 should parse as Unix epoch")
    }

    // MARK: - parse(jsonString:) — Format B with status field

    /// Spec: Format B uses "windows" key. Status field inside window is parsed via parseStatus.
    /// This test verifies that if a Format B window includes a "status" string field it is parsed.
    func testParse_formatB_withStatusField() throws {
        let json = """
        {"windows":{"5h":{"limit":100,"remaining":30,"status":"approaching_limit","resets_at":1740000000},\
        "7d":{"limit":500,"remaining":500,"status":"within_limit","resets_at":1740500000}}}
        """
        let result = try UsageFetcher.parse(jsonString: json)
        XCTAssertEqual(result.fiveHourPercent!, 70.0, accuracy: 0.001)
        XCTAssertEqual(result.sevenDayPercent!, 0.0, accuracy: 0.001)
        // Status is defined in the spec for Format B windows; verify it is extracted
        XCTAssertEqual(result.fiveHourStatus, 1, "approaching_limit → 1")
        XCTAssertEqual(result.sevenDayStatus, 0, "within_limit → 0")
    }

    // MARK: - parse(jsonString:) — Format A rawJSON preservation

    /// Spec: rawJSON field holds the original JSON string, regardless of Format A or B.
    func testParse_formatA_preservesRawJSON() throws {
        let json = #"{"five_hour":{"utilization":33},"seven_day":{"utilization":66}}"#
        let result = try UsageFetcher.parse(jsonString: json)
        XCTAssertEqual(result.rawJSON, json,
                       "rawJSON must equal the original jsonString for Format A")
    }

    // MARK: - parse(jsonString:) — __error key with auth-triggering message

    /// Spec: __error key → scriptFailed; message lowercased for isAuthError check.
    /// The JS stage 4 fallback can produce "HTTP 401 [S1:MISS,S4:HTTP401]".
    func testParse_errorWithHTTP401InDiag() {
        let json = #"{"__error":"HTTP 401 [S1:MISS,S2:MISS,S3:MISS,S4:HTTP401]"}"#
        XCTAssertThrowsError(try UsageFetcher.parse(jsonString: json)) { error in
            guard let fetchError = error as? UsageFetchError else {
                XCTFail("Expected UsageFetchError, got \(error)")
                return
            }
            XCTAssertTrue(fetchError.isAuthError,
                          "HTTP 401 in __error message must be recognised as auth error")
        }
    }

    /// Spec: __error key → scriptFailed; "missing organization" triggers isAuthError.
    func testParse_errorMissingOrgId_isAuthError() {
        let json = #"{"__error":"Missing organization id [S1:MISS,S2:MISS,S3:MISS,S4:HTTP200]"}"#
        XCTAssertThrowsError(try UsageFetcher.parse(jsonString: json)) { error in
            guard let fetchError = error as? UsageFetchError else {
                XCTFail("Expected UsageFetchError")
                return
            }
            XCTAssertTrue(fetchError.isAuthError)
        }
    }

    // MARK: - parse(jsonString:) — decodingFailed path

    /// Spec: decodingFailed is thrown when raw cannot be converted to Data/String.
    /// An empty string body should fail JSON serialisation → decodingFailed.
    func testParse_emptyString_throws() {
        XCTAssertThrowsError(try UsageFetcher.parse(jsonString: ""),
                             "Empty string is not valid JSON")
    }

    /// Spec: top-level JSON array is not a dictionary → parsing yields nil fields (not a throw).
    /// Verifies parse handles non-dict top-level gracefully (no crash).
    func testParse_topLevelArray_yieldsNilFields() throws {
        // A JSON array at top level is valid JSON but has no "windows"/"five_hour" keys.
        // Per spec, parse() checks json["windows"] first. An array cast to [String:Any] will fail,
        // so the result should have all nil fields.
        let json = #"[{"utilization":50}]"#
        // This may throw decodingFailed or return an empty result depending on implementation.
        // Both behaviours are acceptable; what must NOT happen is a crash.
        do {
            let result = try UsageFetcher.parse(jsonString: json)
            XCTAssertNil(result.fiveHourPercent,
                         "Top-level array cannot carry five_hour/windows keys")
        } catch {
            // decodingFailed is also acceptable
            XCTAssertTrue(error is UsageFetchError,
                          "Only UsageFetchError should be thrown")
        }
    }

    /// parseResetsAt accepts negative Double timestamps (before Unix epoch).
    func testParseResetsAt_negativeDouble() {
        let date = UsageFetcher.parseResetsAt(-1.0)
        XCTAssertNotNil(date, "Negative Double should produce a Date before epoch")
        XCTAssertEqual(date!.timeIntervalSince1970, -1.0, accuracy: 0.001)
    }

    // MARK: - trimFractionalSeconds — boundary: exactly 4 digits

    /// Spec: 4+ fractional digits → trim to 3. Exactly 4 digits is the boundary case.
    func testTrimFractionalSeconds_exactly4Digits() {
        let result = UsageFetcher.trimFractionalSeconds("2026-02-22T12:00:00.1234Z")
        XCTAssertEqual(result, "2026-02-22T12:00:00.123Z",
                       "Exactly 4 fractional digits → trim to 3")
    }

    /// Spec: 3 digits → trimFractionalSeconds returns the original string unchanged (≤3 → no trim).
    func testTrimFractionalSeconds_exactly3Digits_unchanged() {
        let input = "2026-02-22T12:00:00.000Z"
        XCTAssertEqual(UsageFetcher.trimFractionalSeconds(input), input,
                       "3 fractional digits → return original unchanged")
    }

    // MARK: - UsageFetchError LocalizedError conformance

    /// Spec: UsageFetchError conforms to LocalizedError.
    /// scriptFailed errorDescription must equal its message argument.
    func testScriptFailedErrorDescription_equalsMessage() {
        let msg = "HTTP 503 Service Unavailable"
        let error = UsageFetchError.scriptFailed(msg)
        XCTAssertEqual(error.errorDescription, msg)
    }

    /// Spec: decodingFailed errorDescription is a fixed string.
    func testDecodingFailedErrorDescription_isFixed() {
        let error = UsageFetchError.decodingFailed
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty,
                       "decodingFailed must have a non-empty errorDescription")
    }

    // MARK: - Skipped: hasValidSession, fetch (WebView-dependent)
    //
    // hasValidSession(using:WKWebView):
    //   - Reads WKHTTPCookieStore.allCookies() and checks sessionKey cookie expiry
    //   - Requires live WKWebView with a real cookie store
    //   - Cannot be unit-tested without a CookieStoreProvider abstraction
    //
    // fetch(using:WKWebView):
    //   - Executes a multi-stage JS script via callAsyncJavaScript
    //   - Requires live WKProcess + claude.ai session cookies
    //   - Cannot be unit-tested without a JSExecutor protocol abstraction
    //
    // Recommended refactor to enable unit testing:
    //   protocol JSExecutor { func callAsyncJavaScript(...) async throws -> Any? }
    //   protocol CookieStoreProvider { func allCookies() async -> [HTTPCookie] }
    //   WKWebView would conform to both protocols via extensions.
    //   Mock implementations would allow injecting controlled responses in tests.
}
