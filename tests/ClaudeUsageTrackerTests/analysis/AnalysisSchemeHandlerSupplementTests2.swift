// Supplement for: tests/ClaudeUsageTrackerTests/analysis/AnalysisSchemeHandlerTests.swift
//
// Covers spec cases not present in the main test file:
//   UT-05: URL nil → 400 + body "Missing URL"
//   UT-09: queryUsageJSON SQL prepare failure → "[]"
//   UT-14: queryTokensJSON SQL prepare failure → "[]"
//   UT-20: serve method data=nil → 500 + body "Failed to generate response"

import XCTest
import WebKit
import SQLite3
@testable import ClaudeUsageTracker

// MARK: - NilURLMockSchemeTask

/// A MockSchemeTask variant whose `request.url` returns nil.
/// Standard URLRequest(url:) always has a non-nil URL, so we use
/// a URLRequest built from a raw string that produces a nil URL property.
/// Approach: construct URLRequest with an empty-string URL which yields request.url == nil.
private final class NilURLMockSchemeTask: NSObject, WKURLSchemeTask {
    let request: URLRequest = {
        // URLRequest with no URL: use the default initializer via NSURLRequest
        // A URLRequest created from an invalid/empty URL string has url == nil
        var req = URLRequest(url: URL(string: "cut://placeholder")!)
        // Overwrite by setting URL to nil via NSMutableURLRequest
        let mutable = (req as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        mutable.url = nil
        return mutable as URLRequest
    }()

    var receivedResponse: URLResponse?
    var receivedData: Data?
    var didFinishCalled = false

    func didReceive(_ response: URLResponse) {
        self.receivedResponse = response
    }

    func didReceive(_ data: Data) {
        if self.receivedData == nil {
            self.receivedData = data
        } else {
            self.receivedData!.append(data)
        }
    }

    func didFinish() {
        didFinishCalled = true
    }

    func didFailWithError(_ error: Error) {}
}

// MARK: - AnalysisSchemeHandlerSupplementTests2

final class AnalysisSchemeHandlerSupplementTests2: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalysisSupplementTests2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    private func createDb(at path: String, sql: String) {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - UT-05: URL nil → 400 + body "Missing URL"

    /// When WKURLSchemeTask.request.url is nil, the handler must respond
    /// with HTTP 400 and body "Missing URL" (spec UT-05, state: CheckURL → Fail400).
    func testStart_nilURL_returns400WithMissingURLBody() {
        let handler = AnalysisSchemeHandler(
            usageDbPath: "/nonexistent/usage.db",
            tokensDbPath: "/nonexistent/tokens.db",
            htmlProvider: { "<html></html>" }
        )
        let task = NilURLMockSchemeTask()
        handler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled,
                      "didFinish must be called even on 400 to avoid WKWebView leak")

        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertNotNil(httpResponse, "Should receive an HTTPURLResponse")
        XCTAssertEqual(httpResponse?.statusCode, 400,
                       "nil URL must result in HTTP 400")
        XCTAssertEqual(httpResponse?.value(forHTTPHeaderField: "Content-Type"), "text/plain",
                       "Error responses must have text/plain Content-Type")

        let body = String(data: task.receivedData ?? Data(), encoding: .utf8) ?? ""
        XCTAssertEqual(body, "Missing URL",
                       "400 body must be exactly 'Missing URL' per spec UT-05")
    }

    // MARK: - UT-09: queryUsageJSON SQL prepare failure → "[]"

    /// When the usage DB exists and opens successfully, but lacks the expected
    /// tables (usage_log, hourly_sessions, weekly_sessions), sqlite3_prepare_v2
    /// fails. The handler must return 200 with body "[]" (spec UT-09).
    func testStart_usageDb_noTables_returnEmptyJsonArray() {
        let usagePath = tmpDir.appendingPathComponent("usage_no_tables.db").path
        let tokensPath = tmpDir.appendingPathComponent("tokens.db").path

        // Create a valid SQLite DB with NO tables — open succeeds, prepare fails
        createDb(at: usagePath, sql: "SELECT 1;")
        // Create a normal tokens DB (not under test here)
        AnalysisTestDB.createTokensDb(at: tokensPath, rows: [])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,
            tokensDbPath: tokensPath,
            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "cut://usage.json")!)
        handler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled)

        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.statusCode, 200,
                       "SQL prepare failure must still return 200 (not 500)")
        XCTAssertEqual(httpResponse?.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = String(data: task.receivedData ?? Data(), encoding: .utf8)
        XCTAssertEqual(body, "[]",
                       "SQL prepare failure must return empty JSON array '[]' per spec UT-09")
    }

    // MARK: - UT-14: queryTokensJSON SQL prepare failure → "[]"

    /// When the tokens DB exists and opens successfully, but lacks the
    /// token_records table, sqlite3_prepare_v2 fails. The handler must
    /// return 200 with body "[]" (spec UT-14).
    func testStart_tokensDb_noTables_returnEmptyJsonArray() {
        let usagePath = tmpDir.appendingPathComponent("usage.db").path
        let tokensPath = tmpDir.appendingPathComponent("tokens_no_tables.db").path

        // Create a normal usage DB (not under test here)
        AnalysisTestDB.createUsageDb(at: usagePath, rows: [])
        // Create a valid SQLite DB with NO tables — open succeeds, prepare fails
        createDb(at: tokensPath, sql: "SELECT 1;")

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,
            tokensDbPath: tokensPath,
            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "cut://tokens.json")!)
        handler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled)

        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.statusCode, 200,
                       "SQL prepare failure must still return 200 (not 500)")
        XCTAssertEqual(httpResponse?.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = String(data: task.receivedData ?? Data(), encoding: .utf8)
        XCTAssertEqual(body, "[]",
                       "SQL prepare failure must return empty JSON array '[]' per spec UT-14")
    }

    // MARK: - UT-20: serve with data=nil → 500

    /// When serializeJSON returns nil (JSONSerialization failure), the serve
    /// method receives data=nil and must respond with HTTP 500 and body
    /// "Failed to generate response" (spec UT-20, state: CheckData → Fail500).
    ///
    /// Trigger: Store Double.nan in a usage DB column. SQLite allows NaN storage.
    /// When queried, columnDouble returns NaN → serializeJSON calls
    /// JSONSerialization.data() which throws for NaN → returns nil → serve gets nil.
    func testStart_serializeFailure_returns500() {
        let usagePath = tmpDir.appendingPathComponent("usage_nan.db").path
        let tokensPath = tmpDir.appendingPathComponent("tokens.db").path

        // Create usage DB with NaN value in hourly_percent.
        // SQLite does not reject NaN on INSERT; it stores IEEE 754 NaN.
        // JSONSerialization.data(withJSONObject:) throws for NaN/Infinity.
        var db: OpaquePointer?
        guard sqlite3_open(usagePath, &db) == SQLITE_OK else {
            XCTFail("Failed to create test DB")
            return
        }
        let createSQL = """
            CREATE TABLE hourly_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                resets_at INTEGER NOT NULL UNIQUE
            );
            CREATE TABLE weekly_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                resets_at INTEGER NOT NULL UNIQUE
            );
            CREATE TABLE usage_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp INTEGER NOT NULL,
                hourly_percent REAL,
                weekly_percent REAL,
                hourly_session_id INTEGER REFERENCES hourly_sessions(id),
                weekly_session_id INTEGER REFERENCES weekly_sessions(id)
            );
            """
        sqlite3_exec(db, createSQL, nil, nil, nil)

        // Insert a row with NaN in hourly_percent using direct IEEE 754 bind
        let insertSQL = "INSERT INTO usage_log (timestamp, hourly_percent, weekly_percent) VALUES (?, ?, ?);"
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil)
        sqlite3_bind_int64(stmt, 1, 1771927200)
        sqlite3_bind_double(stmt, 2, Double.nan)
        sqlite3_bind_double(stmt, 3, 50.0)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        sqlite3_close(db)

        AnalysisTestDB.createTokensDb(at: tokensPath, rows: [])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,
            tokensDbPath: tokensPath,
            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "cut://usage.json")!)
        handler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled,
                      "didFinish must be called even on 500 to avoid WKWebView leak")

        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.statusCode, 500,
                       "serializeJSON returning nil must trigger HTTP 500 via serve()")
        XCTAssertEqual(httpResponse?.value(forHTTPHeaderField: "Content-Type"), "text/plain",
                       "Error responses must have text/plain Content-Type")

        let body = String(data: task.receivedData ?? Data(), encoding: .utf8) ?? ""
        XCTAssertEqual(body, "Failed to generate response",
                       "500 body must be 'Failed to generate response' per spec UT-20")
    }
}
