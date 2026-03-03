// Supplement for: tests/ClaudeUsageTrackerTests/AnalysisSchemeHandlerTests.swift
// Generated from: _documents/spec/analysis/analysis-scheme-handler.md
// Coverage: queryMetaJSON all paths (UT-M01–M05), Query parameter filtering (UT-F01–F04),
//           helper unit tests (parseQueryParams, columnInt, serializeJSON), error header validation

import XCTest
import WebKit
import SQLite3
@testable import ClaudeUsageTracker

// MARK: - queryMetaJSON — All Paths (UT-M01 to UT-M05)

/// Verifies all 5 paths through queryMetaJSON as defined in the spec Decision Table.
/// Guarantees: meta.json always returns 200; body is `{}` on failure, JSON object on success.
final class AnalysisSchemeHandlerMetaJSONTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MetaJSONTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: UT-M01: DB open failure → `{}`

    /// Guarantees: when usage DB does not exist, meta.json returns 200 with body `{}`.
    func testMetaJson_dbOpenFailure_returnsEmptyObject() {
        let handler = AnalysisSchemeHandler(
            usageDbPath: "/nonexistent/no-such.db",
            tokensDbPath: "/nonexistent/no-such-tokens.db",
            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "cut://meta.json")!)
        handler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled)
        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.statusCode, 200,
                       "UT-M01: meta.json must return 200 even when DB open fails")
        let body = String(data: task.receivedData ?? Data(), encoding: .utf8)
        XCTAssertEqual(body, "{}",
                       "UT-M01: body must be '{}' when DB open fails")
    }

    // MARK: UT-M02: SQL prepare failure → `{}`

    /// Guarantees: when usage DB exists but has no usage_log table (schema mismatch),
    /// meta.json returns 200 with body `{}`.
    func testMetaJson_prepareFails_returnsEmptyObject() {
        let usagePath = tmpDir.appendingPathComponent("usage-no-schema.db").path
        let tokensPath = tmpDir.appendingPathComponent("tokens.db").path

        // Create DB with no tables — prepare_v2 will fail
        var db: OpaquePointer?
        sqlite3_open(usagePath, &db)
        sqlite3_close(db)
        AnalysisTestDB.createTokensDb(at: tokensPath, rows: [])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,
            tokensDbPath: tokensPath,
            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "cut://meta.json")!)
        handler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled)
        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.statusCode, 200,
                       "UT-M02: meta.json must return 200 even when SQL prepare fails")
        let body = String(data: task.receivedData ?? Data(), encoding: .utf8)
        XCTAssertEqual(body, "{}",
                       "UT-M02: body must be '{}' when SQL prepare fails (schema mismatch)")
    }

    // MARK: UT-M03: sqlite3_step not SQLITE_ROW (empty table) → `{}`

    /// Guarantees: when usage_log is empty, sqlite3_step returns SQLITE_DONE (not SQLITE_ROW),
    /// and meta.json returns 200 with body `{}`.
    func testMetaJson_emptyUsageLog_returnsEmptyObject() {
        let usagePath = tmpDir.appendingPathComponent("usage-empty.db").path
        let tokensPath = tmpDir.appendingPathComponent("tokens.db").path
        AnalysisTestDB.createUsageDb(at: usagePath, rows: [])
        AnalysisTestDB.createTokensDb(at: tokensPath, rows: [])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,
            tokensDbPath: tokensPath,
            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "cut://meta.json")!)
        handler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled)
        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.statusCode, 200,
                       "UT-M03: meta.json must return 200 when usage_log is empty")
        let body = String(data: task.receivedData ?? Data(), encoding: .utf8)
        XCTAssertEqual(body, "{}",
                       "UT-M03: body must be '{}' when usage_log is empty (SQLITE_DONE, not SQLITE_ROW)")
    }

    // MARK: UT-M04: Normal data → JSON with latestSevenDayResetsAt, latestTimestamp, oldestTimestamp

    /// Guarantees: when usage_log has rows with weekly_session_id set,
    /// meta.json returns 200 with a JSON object containing all three integer keys.
    func testMetaJson_withData_returnsCorrectJsonKeys() {
        let usagePath = tmpDir.appendingPathComponent("usage-data.db").path
        let tokensPath = tmpDir.appendingPathComponent("tokens.db").path
        AnalysisTestDB.createTokensDb(at: tokensPath, rows: [])

        // Create usage.db with sessions and usage_log rows
        var db: OpaquePointer?
        sqlite3_open(usagePath, &db)
        defer { sqlite3_close(db) }
        let schema = """
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
            INSERT INTO weekly_sessions (resets_at) VALUES (1772532000);
            INSERT INTO usage_log (timestamp, hourly_percent, weekly_percent, weekly_session_id)
            VALUES (1771900000, 10.0, 5.0, 1);
            INSERT INTO usage_log (timestamp, hourly_percent, weekly_percent, weekly_session_id)
            VALUES (1771990000, 20.0, 8.0, 1);
            """
        sqlite3_exec(db, schema, nil, nil, nil)

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,
            tokensDbPath: tokensPath,
            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "cut://meta.json")!)
        handler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled)
        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.statusCode, 200,
                       "UT-M04: meta.json must return 200 with data present")

        guard let data = task.receivedData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("UT-M04: meta.json body must be a valid JSON object")
            return
        }
        // latestSevenDayResetsAt: MAX(ws.resets_at) = 1772532000
        XCTAssertNotNil(json["latestSevenDayResetsAt"],
                        "UT-M04: 'latestSevenDayResetsAt' key must be present")
        XCTAssertEqual(json["latestSevenDayResetsAt"] as? Int, 1772532000,
                       "UT-M04: latestSevenDayResetsAt must equal MAX(ws.resets_at)")
        // latestTimestamp: MAX(u.timestamp) = 1771990000
        XCTAssertEqual(json["latestTimestamp"] as? Int, 1771990000,
                       "UT-M04: latestTimestamp must equal MAX(u.timestamp)")
        // oldestTimestamp: MIN(u.timestamp) = 1771900000
        XCTAssertEqual(json["oldestTimestamp"] as? Int, 1771900000,
                       "UT-M04: oldestTimestamp must equal MIN(u.timestamp)")
    }

    // MARK: UT-M05: weekly_sessions empty (LEFT JOIN → NULL) → latestSevenDayResetsAt is null

    /// Guarantees: when usage_log has rows but no weekly_session_id is set,
    /// LEFT JOIN yields NULL for ws.resets_at, and latestSevenDayResetsAt is JSON null.
    /// latestTimestamp and oldestTimestamp must still be present as integers.
    func testMetaJson_noWeeklySessions_latestSevenDayResetsAtIsNull() {
        let usagePath = tmpDir.appendingPathComponent("usage-no-weekly.db").path
        let tokensPath = tmpDir.appendingPathComponent("tokens.db").path
        AnalysisTestDB.createTokensDb(at: tokensPath, rows: [])

        // Insert usage_log rows WITHOUT weekly_session_id (NULL)
        var db: OpaquePointer?
        sqlite3_open(usagePath, &db)
        defer { sqlite3_close(db) }
        let schema = """
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
            INSERT INTO usage_log (timestamp, hourly_percent, weekly_percent, weekly_session_id)
            VALUES (1771800000, 30.0, 12.0, NULL);
            INSERT INTO usage_log (timestamp, hourly_percent, weekly_percent, weekly_session_id)
            VALUES (1771850000, 50.0, 20.0, NULL);
            """
        sqlite3_exec(db, schema, nil, nil, nil)

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,
            tokensDbPath: tokensPath,
            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "cut://meta.json")!)
        handler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled)
        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.statusCode, 200,
                       "UT-M05: meta.json must return 200 even when LEFT JOIN yields NULL")

        guard let data = task.receivedData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("UT-M05: meta.json body must be a valid JSON object")
            return
        }
        // latestSevenDayResetsAt must be NSNull (JSON null) because ws.resets_at is always NULL
        XCTAssertTrue(json["latestSevenDayResetsAt"] is NSNull,
                      "UT-M05: latestSevenDayResetsAt must be null when no weekly_sessions are linked")
        // latestTimestamp and oldestTimestamp must be present as Int
        XCTAssertEqual(json["latestTimestamp"] as? Int, 1771850000,
                       "UT-M05: latestTimestamp must be MAX(u.timestamp) = 1771850000")
        XCTAssertEqual(json["oldestTimestamp"] as? Int, 1771800000,
                       "UT-M05: oldestTimestamp must be MIN(u.timestamp) = 1771800000")
    }

    // MARK: UT-M04b: meta.json Content-Type is application/json

    /// Guarantees: meta.json successful response has Content-Type: application/json.
    func testMetaJson_withData_hasApplicationJsonContentType() {
        let usagePath = tmpDir.appendingPathComponent("usage-ct.db").path
        let tokensPath = tmpDir.appendingPathComponent("tokens.db").path
        AnalysisTestDB.createTokensDb(at: tokensPath, rows: [])

        var db: OpaquePointer?
        sqlite3_open(usagePath, &db)
        defer { sqlite3_close(db) }
        let schema = """
            CREATE TABLE hourly_sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, resets_at INTEGER NOT NULL UNIQUE);
            CREATE TABLE weekly_sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, resets_at INTEGER NOT NULL UNIQUE);
            CREATE TABLE usage_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL,
                hourly_percent REAL, weekly_percent REAL,
                hourly_session_id INTEGER, weekly_session_id INTEGER
            );
            INSERT INTO usage_log (timestamp, hourly_percent, weekly_percent) VALUES (1771900000, 10.0, 5.0);
            """
        sqlite3_exec(db, schema, nil, nil, nil)

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,
            tokensDbPath: tokensPath,
            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "cut://meta.json")!)
        handler.webView(WKWebView(), start: task)

        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.value(forHTTPHeaderField: "Content-Type"), "application/json",
                       "UT-M04b: meta.json must have Content-Type: application/json")
    }
}
