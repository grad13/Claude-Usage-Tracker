import XCTest
import WebKit
import SQLite3
@testable import ClaudeUsageTracker

// MARK: - SQL Query Correctness Tests
//
// Responsibilities:
//   - Usage query: column order, JOIN, sorting, NULL handling

/// Verifies that the SQL queries used in the HTML template produce correct results
/// when run against real SQLite databases with the same schema as UsageStore.
/// This catches column ordering bugs, missing columns, and type mismatches.
final class AnalysisSQLQueryTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SQLQueryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: - Usage Query: Column Order

    /// Execute the EXACT usage JOIN query from AnalysisSchemeHandler against a real SQLite DB.
    func testUsageQuery_columnOrderMatchesJSMapping() {
        let path = tmpDir.appendingPathComponent("usage.db").path
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        sqlite3_exec(db, """
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
                weekly_session_id INTEGER REFERENCES weekly_sessions(id),
                CHECK (hourly_percent IS NOT NULL OR weekly_percent IS NOT NULL)
            );
            INSERT INTO hourly_sessions (resets_at) VALUES (1771945200);
            INSERT INTO weekly_sessions (resets_at) VALUES (1772532000);
            INSERT INTO usage_log (timestamp, hourly_percent, weekly_percent, hourly_session_id, weekly_session_id)
            VALUES (1771927200, 42.5, 15.0, 1, 1);
            """, nil, nil, nil)

        // This is the EXACT query from AnalysisSchemeHandler.queryUsageJSON()
        let sql = """
            SELECT u.timestamp, u.hourly_percent, u.weekly_percent,
                   hs.resets_at AS hourly_resets_at,
                   ws.resets_at AS weekly_resets_at
            FROM usage_log u
            LEFT JOIN hourly_sessions hs ON u.hourly_session_id = hs.id
            LEFT JOIN weekly_sessions ws ON u.weekly_session_id = ws.id
            ORDER BY u.timestamp ASC
            """
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &stmt, nil), SQLITE_OK)
        defer { sqlite3_finalize(stmt) }

        XCTAssertEqual(sqlite3_step(stmt), SQLITE_ROW)

        // JSON maps: timestamp, hourly_percent, weekly_percent, hourly_resets_at, weekly_resets_at
        XCTAssertEqual(Int(sqlite3_column_int64(stmt, 0)), 1771927200,
                       "Column 0 must be timestamp (epoch)")
        XCTAssertEqual(sqlite3_column_double(stmt, 1), 42.5, accuracy: 0.01,
                       "Column 1 must be hourly_percent")
        XCTAssertEqual(sqlite3_column_double(stmt, 2), 15.0, accuracy: 0.01,
                       "Column 2 must be weekly_percent")
        XCTAssertEqual(Int(sqlite3_column_int64(stmt, 3)), 1771945200,
                       "Column 3 must be hourly_resets_at (epoch)")
        XCTAssertEqual(Int(sqlite3_column_int64(stmt, 4)), 1772532000,
                       "Column 4 must be weekly_resets_at (epoch)")
    }

    // MARK: - Usage Query: Sort Order

    /// Verify usage query returns rows sorted by timestamp ascending.
    func testUsageQuery_orderByTimestampAsc() {
        let path = tmpDir.appendingPathComponent("usage.db").path
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        sqlite3_exec(db, """
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
                hourly_percent REAL, weekly_percent REAL,
                hourly_session_id INTEGER REFERENCES hourly_sessions(id),
                weekly_session_id INTEGER REFERENCES weekly_sessions(id),
                CHECK (hourly_percent IS NOT NULL OR weekly_percent IS NOT NULL)
            );
            INSERT INTO usage_log (timestamp, hourly_percent, weekly_percent) VALUES (1771934400, 30.0, 10.0);
            INSERT INTO usage_log (timestamp, hourly_percent, weekly_percent) VALUES (1771927200, 10.0, 5.0);
            INSERT INTO usage_log (timestamp, hourly_percent, weekly_percent) VALUES (1771930800, 20.0, 8.0);
            """, nil, nil, nil)

        let sql = """
            SELECT u.timestamp, u.hourly_percent, u.weekly_percent,
                   hs.resets_at AS hourly_resets_at, ws.resets_at AS weekly_resets_at
            FROM usage_log u
            LEFT JOIN hourly_sessions hs ON u.hourly_session_id = hs.id
            LEFT JOIN weekly_sessions ws ON u.weekly_session_id = ws.id
            ORDER BY u.timestamp ASC
            """
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }

        // Inserted out of order — query must return them sorted
        sqlite3_step(stmt)
        XCTAssertEqual(Int(sqlite3_column_int64(stmt, 0)), 1771927200)
        XCTAssertEqual(sqlite3_column_double(stmt, 1), 10.0, accuracy: 0.01)

        sqlite3_step(stmt)
        XCTAssertEqual(Int(sqlite3_column_int64(stmt, 0)), 1771930800)
        XCTAssertEqual(sqlite3_column_double(stmt, 1), 20.0, accuracy: 0.01)

        sqlite3_step(stmt)
        XCTAssertEqual(Int(sqlite3_column_int64(stmt, 0)), 1771934400)
        XCTAssertEqual(sqlite3_column_double(stmt, 1), 30.0, accuracy: 0.01)
    }

    // MARK: - Usage Query: NULL Handling

    /// Verify null session IDs produce NULL resets_at via LEFT JOIN.
    func testUsageQuery_nullSessionIds_joinReturnsNull() {
        let path = tmpDir.appendingPathComponent("usage.db").path
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        sqlite3_exec(db, """
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
                hourly_percent REAL, weekly_percent REAL,
                hourly_session_id INTEGER REFERENCES hourly_sessions(id),
                weekly_session_id INTEGER REFERENCES weekly_sessions(id),
                CHECK (hourly_percent IS NOT NULL OR weekly_percent IS NOT NULL)
            );
            INSERT INTO usage_log (timestamp, hourly_percent) VALUES (1771927200, 42.5);
            """, nil, nil, nil)

        let sql = """
            SELECT u.timestamp, u.hourly_percent, u.weekly_percent,
                   hs.resets_at AS hourly_resets_at, ws.resets_at AS weekly_resets_at
            FROM usage_log u
            LEFT JOIN hourly_sessions hs ON u.hourly_session_id = hs.id
            LEFT JOIN weekly_sessions ws ON u.weekly_session_id = ws.id
            ORDER BY u.timestamp ASC
            """
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }

        sqlite3_step(stmt)
        XCTAssertEqual(sqlite3_column_type(stmt, 2), SQLITE_NULL, "weekly_percent should be NULL")
        XCTAssertEqual(sqlite3_column_type(stmt, 3), SQLITE_NULL, "hourly_resets_at should be NULL (no session)")
        XCTAssertEqual(sqlite3_column_type(stmt, 4), SQLITE_NULL, "weekly_resets_at should be NULL (no session)")
    }

}
