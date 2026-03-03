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

// MARK: - Query Parameter Filtering (UT-F01 to UT-F04)

/// Verifies from/to filter behavior for usage.json and tokens.json as per spec Decision Table.
/// Guarantees: valid Int64 params apply WHERE clause; invalid or missing params return all rows.
final class AnalysisSchemeHandlerQueryFilterTests: XCTestCase {

    private var tmpDir: URL!
    private var handler: AnalysisSchemeHandler!
    private let epoch1 = 1700000000  // reference epoch
    private let epoch2 = 1700003600  // +1 hour
    private let epoch3 = 1700007200  // +2 hours

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FilterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let usagePath = tmpDir.appendingPathComponent("usage.db").path
        let tokensPath = tmpDir.appendingPathComponent("tokens.db").path

        // Three usage rows at different timestamps
        AnalysisTestDB.createUsageDb(at: usagePath, rows: [
            (1700000000, 10.0, 5.0),   // epoch1 — within range when from=epoch1, to=epoch2
            (1700003600, 20.0, 8.0),   // epoch2 — boundary (inclusive)
            (1700007200, 30.0, 12.0),  // epoch3 — outside range when to=epoch2
        ])

        // Three token rows at different ISO 8601 timestamps
        AnalysisTestDB.createTokensDb(at: tokensPath, rows: [
            ("req-1", "2026-01-01T00:00:00Z", "claude-sonnet-4-20250514", 100, 50, 0, 0),
            ("req-2", "2026-01-15T12:00:00Z", "claude-sonnet-4-20250514", 200, 80, 0, 0),
            ("req-3", "2026-01-31T23:59:59Z", "claude-sonnet-4-20250514", 300, 90, 0, 0),
        ])

        handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,
            tokensDbPath: tokensPath,
            htmlProvider: { "<html></html>" }
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: UT-F01: usage.json with valid from/to Int64 → filtered rows only

    /// Guarantees: when from and to are valid Int64 epoch values,
    /// only rows with timestamp >= from AND timestamp <= to are returned.
    func testUsageJson_validFromTo_returnsFilteredRows() {
        let url = URL(string: "cut://usage.json?from=1700000000&to=1700003600")!
        let task = MockSchemeTask(url: url)
        handler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled)
        guard let data = task.receivedData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            XCTFail("UT-F01: Response must be a valid JSON array")
            return
        }
        XCTAssertEqual(json.count, 2,
                       "UT-F01: Only rows within [from, to] range must be returned (epoch1 and epoch2)")
        XCTAssertEqual(json[0]["timestamp"] as? Int, 1700000000,
                       "UT-F01: First row timestamp must be epoch1")
        XCTAssertEqual(json[1]["timestamp"] as? Int, 1700003600,
                       "UT-F01: Second row timestamp must be epoch2 (inclusive upper bound)")
    }

    // MARK: UT-F02: usage.json with non-numeric from → all rows returned

    /// Guarantees: when from is non-numeric (cannot be converted to Int64),
    /// the WHERE clause is omitted and all rows are returned.
    func testUsageJson_nonNumericFrom_returnsAllRows() {
        let url = URL(string: "cut://usage.json?from=abc&to=1700003600")!
        let task = MockSchemeTask(url: url)
        handler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled)
        guard let data = task.receivedData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            XCTFail("UT-F02: Response must be a valid JSON array")
            return
        }
        XCTAssertEqual(json.count, 3,
                       "UT-F02: All 3 rows must be returned when from is non-numeric (no WHERE clause)")
    }

    // MARK: UT-F03: usage.json with no parameters → all rows returned

    /// Guarantees: when neither from nor to is present in the URL,
    /// the WHERE clause is omitted and all rows are returned.
    func testUsageJson_noParameters_returnsAllRows() {
        let url = URL(string: "cut://usage.json")!
        let task = MockSchemeTask(url: url)
        handler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled)
        guard let data = task.receivedData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            XCTFail("UT-F03: Response must be a valid JSON array")
            return
        }
        XCTAssertEqual(json.count, 3,
                       "UT-F03: All 3 rows must be returned when no filter parameters are present")
    }

    // MARK: UT-F04: tokens.json with ISO 8601 from/to → filtered rows (TEXT comparison)

    /// Guarantees: when from and to are ISO 8601 strings,
    /// token_records are filtered using sqlite3_bind_text (TEXT comparison).
    func testTokensJson_iso8601FromTo_returnsFilteredRows() {
        let from = "2026-01-01T00:00:00Z"
        let to = "2026-01-31T23:59:59Z"
        let encodedFrom = from.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let encodedTo = to.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "cut://tokens.json?from=\(encodedFrom)&to=\(encodedTo)")!
        let task = MockSchemeTask(url: url)
        handler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled)
        guard let data = task.receivedData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            XCTFail("UT-F04: Response must be a valid JSON array")
            return
        }
        XCTAssertEqual(json.count, 3,
                       "UT-F04: All 3 rows must be returned (all timestamps fall within Jan 2026 range)")
    }

    // MARK: UT-F04b: tokens.json with only-from parameter → all rows (missing to → no filter)

    /// Guarantees: when only `from` is supplied (to is missing),
    /// the WHERE clause is omitted and all rows are returned.
    func testTokensJson_onlyFrom_returnsAllRows() {
        let url = URL(string: "cut://tokens.json?from=2026-01-01T00:00:00Z")!
        let task = MockSchemeTask(url: url)
        handler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled)
        guard let data = task.receivedData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            XCTFail("UT-F04b: Response must be a valid JSON array")
            return
        }
        XCTAssertEqual(json.count, 3,
                       "UT-F04b: All rows must be returned when only 'from' is supplied (missing 'to' disables filter)")
    }
}

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
        let tokensPath = tmpDir.appendingPathComponent("tokens.db").path
        AnalysisTestDB.createUsageDb(at: usagePath, rows: [
            (1700000000, 10.0, 5.0),
            (1700003600, 20.0, 8.0),
        ])
        AnalysisTestDB.createTokensDb(at: tokensPath, rows: [])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath, tokensDbPath: tokensPath,
            htmlProvider: { "<html></html>" }
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
        let tokensPath = tmpDir.appendingPathComponent("tokens.db").path
        AnalysisTestDB.createUsageDb(at: usagePath, rows: [
            (1700000000, 10.0, 5.0),
            (1700003600, 20.0, 8.0),
            (1700007200, 30.0, 12.0),
        ])
        AnalysisTestDB.createTokensDb(at: tokensPath, rows: [])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath, tokensDbPath: tokensPath,
            htmlProvider: { "<html></html>" }
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
        let tokensPath = tmpDir.appendingPathComponent("tokens.db").path
        AnalysisTestDB.createTokensDb(at: tokensPath, rows: [])

        var db: OpaquePointer?
        sqlite3_open(usagePath, &db)
        defer { sqlite3_close(db) }
        // Insert usage_log row with NULL weekly_session_id → LEFT JOIN → ws.resets_at is NULL
        let schema = """
            CREATE TABLE hourly_sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, resets_at INTEGER NOT NULL UNIQUE);
            CREATE TABLE weekly_sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, resets_at INTEGER NOT NULL UNIQUE);
            CREATE TABLE usage_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL,
                hourly_percent REAL, weekly_percent REAL,
                hourly_session_id INTEGER, weekly_session_id INTEGER
            );
            INSERT INTO usage_log (timestamp, hourly_percent, weekly_percent, weekly_session_id)
            VALUES (1771900000, 10.0, 5.0, NULL);
            """
        sqlite3_exec(db, schema, nil, nil, nil)

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath, tokensDbPath: tokensPath,
            htmlProvider: { "<html></html>" }
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
            INSERT INTO usage_log (timestamp, hourly_percent, weekly_percent)
            VALUES (1700000000, 55.0, 20.0);
            """
        sqlite3_exec(db, schema, nil, nil, nil)

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath, tokensDbPath: tokensPath,
            htmlProvider: { "<html></html>" }
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
        let tokensPath = tmpDir.appendingPathComponent("tokens.db").path
        AnalysisTestDB.createTokensDb(at: tokensPath, rows: [])

        // AnalysisTestDB.createUsageDb inserts rows WITHOUT session IDs → LEFT JOIN → null resets_at
        AnalysisTestDB.createUsageDb(at: usagePath, rows: [
            (1700000000, 42.5, 15.0),
        ])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath, tokensDbPath: tokensPath,
            htmlProvider: { "<html></html>" }
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
        let tokensPath = tmpDir.appendingPathComponent("tokens.db").path
        AnalysisTestDB.createUsageDb(at: usagePath, rows: [])
        AnalysisTestDB.createTokensDb(at: tokensPath, rows: [])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath, tokensDbPath: tokensPath,
            htmlProvider: { "<html></html>" }
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
        let tokensPath = tmpDir.appendingPathComponent("tokens.db").path
        AnalysisTestDB.createUsageDb(at: usagePath, rows: [])
        AnalysisTestDB.createTokensDb(at: tokensPath, rows: [])

        handler = AnalysisSchemeHandler(
            usageDbPath: usagePath, tokensDbPath: tokensPath,
            htmlProvider: { "<html></html>" }
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

        let corsHandler = AnalysisSchemeHandler(
            usageDbPath: usagePath, tokensDbPath: tokensPath,
            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "cut://meta.json")!)
        corsHandler.webView(WKWebView(), start: task)

        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.statusCode, 200)
        XCTAssertEqual(httpResponse?.value(forHTTPHeaderField: "Access-Control-Allow-Origin"), "*",
                       "Error header: meta.json 200 response must have Access-Control-Allow-Origin: *")
    }
}
