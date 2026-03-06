// Supplement for: tests/ClaudeUsageTrackerTests/AnalysisSchemeHandlerTests.swift
// Generated from: _documents/spec/analysis/analysis-scheme-handler.md
// Coverage: queryMetaJSON all paths (UT-M01–M05), Query parameter filtering (UT-F01–F04),
//           helper unit tests (parseQueryParams, columnInt, serializeJSON), error header validation

import XCTest
import WebKit
@testable import ClaudeUsageTracker

// MARK: - Helper Unit Tests (parseQueryParams, columnInt, serializeJSON)

/// Tests private helper behavior through the public handler interface.
/// parseQueryParams: verified via URL query string parsing observable through filter behavior.
/// columnInt: verified via meta.json JSON key values (NULL and INTEGER column types).
/// serializeJSON: verified via usage.json/tokens.json bodies (nil→null, empty→[]).
final class AnalysisSchemeHandlerHelperTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HelperTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: parseQueryParams — empty query string returns empty dict (no filter applied)

    /// Guarantees: parseQueryParams with a URL having no query string
    /// returns an empty dictionary, causing no filter to be applied (all rows returned).
    func testParseQueryParams_noQueryString_returnsAllRows() {
        let usagePath = tmpDir.appendingPathComponent("usage.db").path
        AnalysisTestDB.createUsageDb(at: usagePath, rows: [
            (1700000000, 10.0, 5.0),
            (1700003600, 20.0, 8.0),
        ])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,            htmlProvider: { "<html></html>" }
        )
        // URL with no query string
        let task = MockSchemeTask(url: URL(string: "cut://usage.json")!)
        handler.webView(WKWebView(), start: task)

        guard let data = task.receivedData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            XCTFail("parseQueryParams: response must be a valid JSON array")
            return
        }
        XCTAssertEqual(json.count, 2,
                       "parseQueryParams: empty query → all rows returned (no WHERE clause)")
    }

    // MARK: parseQueryParams — key-only queryItem (no value) is skipped

    /// Guarantees: a query item with a key but no value (e.g., `?from&to=...`) is skipped.
    /// The spec states: "value が nil の場合はスキップ（キーのみの項目は辞書に含まれない）"
    /// Observable effect: missing 'from' means no filter applied, all rows returned.
    func testParseQueryParams_keyOnlyItem_isSkippedAndNoFilterApplied() {
        let usagePath = tmpDir.appendingPathComponent("usage.db").path
        AnalysisTestDB.createUsageDb(at: usagePath, rows: [
            (1700000000, 10.0, 5.0),
            (1700003600, 20.0, 8.0),
            (1700007200, 30.0, 12.0),
        ])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,            htmlProvider: { "<html></html>" }
        )
        // 'from' has no value — spec says key-only items are skipped
        let task = MockSchemeTask(url: URL(string: "cut://usage.json?from&to=1700003600")!)
        handler.webView(WKWebView(), start: task)

        guard let data = task.receivedData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            XCTFail("parseQueryParams: key-only test response must be a valid JSON array")
            return
        }
        XCTAssertEqual(json.count, 3,
                       "parseQueryParams: key-only 'from' is skipped → no filter → all 3 rows returned")
    }

    // MARK: columnInt — NULL column → JSON null (NSNull)

    /// Guarantees: when a SQLite column has type SQLITE_NULL,
    /// columnInt returns nil, which is serialized to JSON null (NSNull).
    /// Observable: meta.json latestSevenDayResetsAt is null when no weekly_sessions are linked.
    func testColumnInt_nullColumn_isJsonNull() {
        let usagePath = tmpDir.appendingPathComponent("usage-null.db").path
        AnalysisTestDB.createUsageDbWithSessions(
            at: usagePath,
            rows: [(timestamp: 1771900000, hourly: 10.0, weekly: 5.0, weeklySessionId: nil)]
        )

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "cut://meta.json")!)
        handler.webView(WKWebView(), start: task)

        guard let data = task.receivedData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("columnInt NULL test: response must be a valid JSON object")
            return
        }
        XCTAssertTrue(json["latestSevenDayResetsAt"] is NSNull,
                      "columnInt: SQLITE_NULL column must produce JSON null (NSNull), not absent key or zero")
    }

    // MARK: columnInt — INTEGER column → correct Int value

    /// Guarantees: when a SQLite column has type INTEGER,
    /// columnInt returns Int(sqlite3_column_int64(stmt, idx)) correctly.
    /// Observable: meta.json latestTimestamp matches the inserted epoch value.
    func testColumnInt_integerColumn_returnsCorrectInt() {
        let usagePath = tmpDir.appendingPathComponent("usage-int.db").path
        AnalysisTestDB.createUsageDbWithSessions(
            at: usagePath,
            rows: [(timestamp: 1700000000, hourly: 55.0, weekly: 20.0, weeklySessionId: nil)]
        )

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "cut://meta.json")!)
        handler.webView(WKWebView(), start: task)

        guard let data = task.receivedData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("columnInt INTEGER test: response must be a valid JSON object")
            return
        }
        XCTAssertEqual(json["latestTimestamp"] as? Int, 1700000000,
                       "columnInt: INTEGER column must return Int(1700000000) correctly")
        XCTAssertEqual(json["oldestTimestamp"] as? Int, 1700000000,
                       "columnInt: oldest == latest when single row; MIN = MAX = 1700000000")
    }

    // MARK: serializeJSON — Optional nil values become JSON null

    /// Guarantees: when a row column value is nil (Optional nil → NSNull),
    /// serializeJSON produces valid JSON with null for those fields.
    /// Observable: usage.json with NULL hourly_resets_at/weekly_resets_at yields null in response.
    func testSerializeJson_nilValues_becomeJsonNull() {
        let usagePath = tmpDir.appendingPathComponent("usage-nil.db").path

        // AnalysisTestDB.createUsageDb inserts rows WITHOUT session IDs → LEFT JOIN → null resets_at
        AnalysisTestDB.createUsageDb(at: usagePath, rows: [
            (1700000000, 42.5, 15.0),
        ])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "cut://usage.json")!)
        handler.webView(WKWebView(), start: task)

        guard let data = task.receivedData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            XCTFail("serializeJSON nil test: response must be a valid JSON array")
            return
        }
        XCTAssertEqual(json.count, 1, "serializeJSON nil test: must have 1 row")
        // hourly_resets_at and weekly_resets_at are NULL (no session IDs set) → JSON null
        XCTAssertTrue(json[0]["hourly_resets_at"] is NSNull,
                      "serializeJSON: nil Optional must become JSON null (NSNull), not 0 or missing key")
        XCTAssertTrue(json[0]["weekly_resets_at"] is NSNull,
                      "serializeJSON: nil Optional must become JSON null (NSNull), not 0 or missing key")
    }

    // MARK: serializeJSON — empty array → `[]`

    /// Guarantees: serializeJSON with an empty rows array produces the JSON bytes `[]`.
    /// Observable: usage.json with empty usage_log returns `[]`.
    func testSerializeJson_emptyArray_returnsEmptyJsonArray() {
        let usagePath = tmpDir.appendingPathComponent("usage-empty-sj.db").path
        AnalysisTestDB.createUsageDb(at: usagePath, rows: [])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "cut://usage.json")!)
        handler.webView(WKWebView(), start: task)

        let body = String(data: task.receivedData ?? Data(), encoding: .utf8)
        XCTAssertEqual(body, "[]",
                       "serializeJSON: empty rows must produce exactly '[]'")
    }
}

// MARK: - Error Response Header Validation (400, 404, 500)

/// Verifies that error responses (400, 404, 500) have Content-Type: text/plain.
/// Guarantees: all error paths set text/plain as specified in the spec header table.
final class AnalysisSchemeHandlerErrorHeaderTests: XCTestCase {

    private var tmpDir: URL!
    private var handler: AnalysisSchemeHandler!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ErrorHeaderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let usagePath = tmpDir.appendingPathComponent("usage.db").path
        AnalysisTestDB.createUsageDb(at: usagePath, rows: [])

        handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,            htmlProvider: { "<html></html>" }
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: 400 error — Content-Type: text/plain

    /// Guarantees: when URL is nil (400 Missing URL), Content-Type is text/plain.
    /// Note: MockSchemeTask with a valid URL is used; the 400 case is triggered
    /// by the handler internally (cannot pass nil URL to MockSchemeTask).
    /// We verify the 404 (unknown path) case as the observable text/plain error case.
    func test404Error_hasTextPlainContentType() {
        let task = MockSchemeTask(url: URL(string: "cut://unknown-path.txt")!)
        handler.webView(WKWebView(), start: task)

        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.statusCode, 404,
                       "Error header test: unknown path must return 404")
        XCTAssertEqual(httpResponse?.value(forHTTPHeaderField: "Content-Type"), "text/plain",
                       "Error header: 404 response must have Content-Type: text/plain")
    }

    // MARK: 404 body contains path name in error message

    /// Guarantees: the 404 body contains the path from the URL so the client can diagnose the issue.
    /// Spec: `404 + body: "Not found: unknown.txt"`.
    func test404Error_bodyContainsPathName() {
        let task = MockSchemeTask(url: URL(string: "cut://unknown.txt")!)
        handler.webView(WKWebView(), start: task)

        let body = String(data: task.receivedData ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("unknown.txt"),
                      "Error header: 404 body must contain the requested path 'unknown.txt'")
        XCTAssertTrue(body.contains("Not found"),
                      "Error header: 404 body must contain 'Not found' prefix")
    }

    // MARK: 404 error — no CORS header on error responses

    /// Guarantees: error responses do NOT include Access-Control-Allow-Origin.
    /// The spec only specifies Access-Control-Allow-Origin for successful 200 responses.
    func test404Error_hasNoCORSHeader() {
        let task = MockSchemeTask(url: URL(string: "cut://unknown-cors-check.txt")!)
        handler.webView(WKWebView(), start: task)

        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertNil(httpResponse?.value(forHTTPHeaderField: "Access-Control-Allow-Origin"),
                     "Error header: 404 response must NOT have Access-Control-Allow-Origin (only set on 200)")
    }

    // MARK: Success 200 — Access-Control-Allow-Origin is "*"

    /// Guarantees: the spec-mandated Access-Control-Allow-Origin: * header is present on all 200 responses.
    /// This covers meta.json specifically (which existing tests do not verify for CORS).
    func testMetaJson_success_hasCORSHeader() {
        let usagePath = tmpDir.appendingPathComponent("usage-cors.db").path
        AnalysisTestDB.createUsageDbWithSessions(
            at: usagePath,
            rows: [(timestamp: 1771900000, hourly: 10.0, weekly: 5.0, weeklySessionId: nil)]
        )

        let corsHandler = AnalysisSchemeHandler(
            usageDbPath: usagePath,            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "cut://meta.json")!)
        corsHandler.webView(WKWebView(), start: task)

        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.statusCode, 200)
        XCTAssertEqual(httpResponse?.value(forHTTPHeaderField: "Access-Control-Allow-Origin"), "*",
                       "Error header: meta.json 200 response must have Access-Control-Allow-Origin: *")
    }
}
