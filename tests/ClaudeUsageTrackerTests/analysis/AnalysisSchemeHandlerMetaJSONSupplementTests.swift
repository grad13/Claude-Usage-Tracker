// meta: updated=2026-03-07 05:54 checked=-
// Supplement for: tests/ClaudeUsageTrackerTests/analysis/AnalysisSchemeHandlerMetaJSONTests.swift
// Source spec: spec/analysis/analysis-scheme-handler.md
// Generated: 2026-03-06
//
// Covers:
//   - UT-M06: usage_log + sessions → weeklySessions/hourlySessions arrays
//   - UT-M07: usage_log + empty sessions → empty arrays
//   - UT-M08: empty usage_log + sessions → session arrays only
//   - UT-M09: all empty → {}
//   - UT-M10: session NULL keys → omitted

import XCTest
import WebKit
import SQLite3
@testable import ClaudeUsageTracker

// MARK: - queryMetaJSON — Session List Output (UT-M06 to UT-M10)

/// Verifies session list output paths in queryMetaJSON.
/// Guarantees: weeklySessions/hourlySessions arrays are present when
/// `hasUsageData || !sessions.isEmpty`, and NULL keys are omitted from session objects.
final class AnalysisSchemeHandlerMetaJSONSupplementTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MetaJSONSupplementTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: UT-M06: usage_log has data + sessions tables have data → JSON includes weeklySessions/hourlySessions arrays

    /// Guarantees: when usage_log has rows AND weekly_sessions/hourly_sessions have rows,
    /// meta.json returns all aggregate keys plus weeklySessions and hourlySessions arrays
    /// with session objects containing `id` and `resets_at`.
    func testMetaJson_usageAndSessions_returnsSessionArrays() {
        let usagePath = tmpDir.appendingPathComponent("usage-m06.db").path

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
            INSERT INTO weekly_sessions (resets_at) VALUES (1773136800);
            INSERT INTO hourly_sessions (resets_at) VALUES (1771900800);
            INSERT INTO hourly_sessions (resets_at) VALUES (1771904400);
            INSERT INTO usage_log (timestamp, hourly_percent, weekly_percent, hourly_session_id, weekly_session_id)
            VALUES (1771900000, 10.0, 5.0, 1, 1);
            INSERT INTO usage_log (timestamp, hourly_percent, weekly_percent, hourly_session_id, weekly_session_id)
            VALUES (1771990000, 20.0, 8.0, 2, 2);
            """
        sqlite3_exec(db, schema, nil, nil, nil)

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,
            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "cut://meta.json")!)
        handler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled)
        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.statusCode, 200,
                       "UT-M06: meta.json must return 200")

        guard let data = task.receivedData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("UT-M06: meta.json body must be a valid JSON object")
            return
        }

        // Aggregate keys must be present
        XCTAssertNotNil(json["latestSevenDayResetsAt"],
                        "UT-M06: latestSevenDayResetsAt must be present")
        XCTAssertNotNil(json["latestTimestamp"],
                        "UT-M06: latestTimestamp must be present")
        XCTAssertNotNil(json["oldestTimestamp"],
                        "UT-M06: oldestTimestamp must be present")

        // weeklySessions array
        guard let weeklySessions = json["weeklySessions"] as? [[String: Any]] else {
            XCTFail("UT-M06: weeklySessions must be an array of objects")
            return
        }
        XCTAssertEqual(weeklySessions.count, 2,
                       "UT-M06: weeklySessions must have 2 entries")
        // Ordered by resets_at ASC
        XCTAssertEqual(weeklySessions[0]["id"] as? Int, 1)
        XCTAssertEqual(weeklySessions[0]["resets_at"] as? Int, 1772532000)
        XCTAssertEqual(weeklySessions[1]["id"] as? Int, 2)
        XCTAssertEqual(weeklySessions[1]["resets_at"] as? Int, 1773136800)

        // hourlySessions array
        guard let hourlySessions = json["hourlySessions"] as? [[String: Any]] else {
            XCTFail("UT-M06: hourlySessions must be an array of objects")
            return
        }
        XCTAssertEqual(hourlySessions.count, 2,
                       "UT-M06: hourlySessions must have 2 entries")
        // Ordered by resets_at ASC
        XCTAssertEqual(hourlySessions[0]["id"] as? Int, 1)
        XCTAssertEqual(hourlySessions[0]["resets_at"] as? Int, 1771900800)
        XCTAssertEqual(hourlySessions[1]["id"] as? Int, 2)
        XCTAssertEqual(hourlySessions[1]["resets_at"] as? Int, 1771904400)
    }

    // MARK: UT-M07: usage_log has data + sessions tables empty → weeklySessions:[], hourlySessions:[]

    /// Guarantees: when usage_log has rows but sessions tables are empty,
    /// hasUsageData=true causes session keys to exist as empty arrays.
    func testMetaJson_usageDataNoSessions_returnsEmptySessionArrays() {
        let usagePath = tmpDir.appendingPathComponent("usage-m07.db").path

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
            INSERT INTO usage_log (timestamp, hourly_percent, weekly_percent)
            VALUES (1771900000, 10.0, 5.0);
            """
        sqlite3_exec(db, schema, nil, nil, nil)

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,
            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "cut://meta.json")!)
        handler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled)
        guard let data = task.receivedData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("UT-M07: meta.json body must be a valid JSON object")
            return
        }

        // weeklySessions key must exist and be empty array
        guard let weeklySessions = json["weeklySessions"] as? [[String: Any]] else {
            XCTFail("UT-M07: weeklySessions key must exist (hasUsageData=true)")
            return
        }
        XCTAssertTrue(weeklySessions.isEmpty,
                      "UT-M07: weeklySessions must be an empty array when sessions table is empty")

        // hourlySessions key must exist and be empty array
        guard let hourlySessions = json["hourlySessions"] as? [[String: Any]] else {
            XCTFail("UT-M07: hourlySessions key must exist (hasUsageData=true)")
            return
        }
        XCTAssertTrue(hourlySessions.isEmpty,
                      "UT-M07: hourlySessions must be an empty array when sessions table is empty")
    }

    // MARK: UT-M08: usage_log empty + sessions tables have data → only session arrays output

    /// Guarantees: when usage_log is empty but sessions have data,
    /// hasUsageData=false so aggregate keys are NOT present, but session arrays ARE present
    /// because `!sessions.isEmpty` is true.
    func testMetaJson_noUsageButSessions_returnsSessionArraysOnly() {
        let usagePath = tmpDir.appendingPathComponent("usage-m08.db").path

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
            INSERT INTO hourly_sessions (resets_at) VALUES (1771900800);
            """
        sqlite3_exec(db, schema, nil, nil, nil)

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,
            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "cut://meta.json")!)
        handler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled)
        guard let data = task.receivedData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("UT-M08: meta.json body must be a valid JSON object")
            return
        }

        // Aggregate keys must NOT be present (hasUsageData=false)
        XCTAssertNil(json["latestSevenDayResetsAt"],
                     "UT-M08: latestSevenDayResetsAt must not be present when usage_log is empty")
        XCTAssertNil(json["latestTimestamp"],
                     "UT-M08: latestTimestamp must not be present when usage_log is empty")
        XCTAssertNil(json["oldestTimestamp"],
                     "UT-M08: oldestTimestamp must not be present when usage_log is empty")

        // weeklySessions must be present with data (!sessions.isEmpty)
        guard let weeklySessions = json["weeklySessions"] as? [[String: Any]] else {
            XCTFail("UT-M08: weeklySessions must be present even when usage_log is empty")
            return
        }
        XCTAssertEqual(weeklySessions.count, 1,
                       "UT-M08: weeklySessions must have 1 entry")
        XCTAssertEqual(weeklySessions[0]["resets_at"] as? Int, 1772532000)

        // hourlySessions must be present with data (!sessions.isEmpty)
        guard let hourlySessions = json["hourlySessions"] as? [[String: Any]] else {
            XCTFail("UT-M08: hourlySessions must be present even when usage_log is empty")
            return
        }
        XCTAssertEqual(hourlySessions.count, 1,
                       "UT-M08: hourlySessions must have 1 entry")
        XCTAssertEqual(hourlySessions[0]["resets_at"] as? Int, 1771900800)
    }

    // MARK: UT-M09: usage_log empty + sessions tables empty → `{}`

    /// Guarantees: when both usage_log and sessions tables are empty,
    /// hasUsageData=false and sessions.isEmpty=true → both conditions fail,
    /// so result dict remains empty → body is `{}`.
    func testMetaJson_allEmpty_returnsEmptyObject() {
        let usagePath = tmpDir.appendingPathComponent("usage-m09.db").path
        AnalysisTestDB.createUsageDb(at: usagePath, rows: [])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,
            htmlProvider: { "<html></html>" },
            settingsProvider: { [:] }
        )
        let task = MockSchemeTask(url: URL(string: "cut://meta.json")!)
        handler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled)
        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.statusCode, 200,
                       "UT-M09: meta.json must return 200 when everything is empty")
        let body = String(data: task.receivedData ?? Data(), encoding: .utf8)
        XCTAssertEqual(body, "{}",
                       "UT-M09: body must be '{}' when usage_log and sessions are both empty")
    }

    // MARK: UT-M10: sessions with NULL id or resets_at → key omitted from session object

    /// Guarantees: when a session row has a NULL column, the corresponding key
    /// is omitted from the session object (not set to NSNull).
    /// Uses `if let` guard in code: only non-nil values are added to the dict.
    func testMetaJson_sessionNullKeys_omittedFromObject() {
        let usagePath = tmpDir.appendingPathComponent("usage-m10.db").path

        var db: OpaquePointer?
        sqlite3_open(usagePath, &db)
        defer { sqlite3_close(db) }
        // Create tables without NOT NULL on resets_at to allow NULL insertion
        let schema = """
            CREATE TABLE hourly_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                resets_at INTEGER UNIQUE
            );
            CREATE TABLE weekly_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                resets_at INTEGER UNIQUE
            );
            CREATE TABLE usage_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp INTEGER NOT NULL,
                hourly_percent REAL,
                weekly_percent REAL,
                hourly_session_id INTEGER REFERENCES hourly_sessions(id),
                weekly_session_id INTEGER REFERENCES weekly_sessions(id)
            );
            INSERT INTO weekly_sessions (resets_at) VALUES (NULL);
            INSERT INTO hourly_sessions (resets_at) VALUES (1771900800);
            """
        sqlite3_exec(db, schema, nil, nil, nil)

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,
            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "cut://meta.json")!)
        handler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled)
        guard let data = task.receivedData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("UT-M10: meta.json body must be a valid JSON object")
            return
        }

        // weeklySessions: row with id=1, resets_at=NULL
        // The `if let` guard skips nil values, so "resets_at" key should be omitted
        guard let weeklySessions = json["weeklySessions"] as? [[String: Any]] else {
            XCTFail("UT-M10: weeklySessions must be present (sessions non-empty)")
            return
        }
        XCTAssertEqual(weeklySessions.count, 1,
                       "UT-M10: weeklySessions must have 1 entry")
        // id is AUTOINCREMENT so it's non-NULL → key present
        XCTAssertEqual(weeklySessions[0]["id"] as? Int, 1,
                       "UT-M10: id must be present when non-NULL")
        // resets_at is NULL → key must be OMITTED (not NSNull)
        XCTAssertNil(weeklySessions[0]["resets_at"],
                     "UT-M10: resets_at key must be omitted when column is NULL")
        XCTAssertFalse(weeklySessions[0].keys.contains("resets_at"),
                       "UT-M10: resets_at key must not exist in dict (not NSNull, truly absent)")

        // hourlySessions: row with id=1, resets_at=1771900800 (both non-NULL)
        guard let hourlySessions = json["hourlySessions"] as? [[String: Any]] else {
            XCTFail("UT-M10: hourlySessions must be present")
            return
        }
        XCTAssertEqual(hourlySessions.count, 1)
        XCTAssertEqual(hourlySessions[0]["id"] as? Int, 1,
                       "UT-M10: id must be present")
        XCTAssertEqual(hourlySessions[0]["resets_at"] as? Int, 1771900800,
                       "UT-M10: resets_at must be present when non-NULL")
    }
}
