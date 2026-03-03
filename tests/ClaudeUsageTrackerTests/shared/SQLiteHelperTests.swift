// meta: created=2026-03-04 updated=2026-03-04 checked=never
import XCTest
import SQLite3
@testable import ClaudeUsageTrackerShared

final class SQLiteHelperTests: XCTestCase {

    private var dbPath: String!

    override func setUp() {
        super.setUp()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("SQLiteHelperTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        dbPath = tmp.appendingPathComponent("test.db").path
    }

    override func tearDown() {
        let dir = URL(fileURLWithPath: dbPath).deletingLastPathComponent()
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    // MARK: - withDatabase

    func testWithDatabase_createsAndOpens() {
        let result = SQLiteHelper.withDatabase(path: dbPath, pragmas: SQLiteHelper.walPragmas) { db -> Bool in
            sqlite3_exec(db, "CREATE TABLE t (id INTEGER PRIMARY KEY);", nil, nil, nil)
            return true
        }
        XCTAssertEqual(result, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbPath))
    }

    func testWithDatabase_returnsNilForInvalidPath() {
        let result = SQLiteHelper.withDatabase(path: "/nonexistent/path/test.db", flags: SQLITE_OPEN_READONLY) { _ in
            return true
        }
        XCTAssertNil(result)
    }

    // MARK: - withStatement

    func testWithStatement_preparesAndExecutes() {
        SQLiteHelper.withDatabase(path: dbPath) { db in
            sqlite3_exec(db, "CREATE TABLE t (val REAL);", nil, nil, nil)
            sqlite3_exec(db, "INSERT INTO t VALUES (42.5);", nil, nil, nil)

            let value = SQLiteHelper.withStatement(db: db, sql: "SELECT val FROM t;") { stmt -> Double? in
                guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
                return SQLiteHelper.columnDouble(stmt, 0)
            }
            XCTAssertEqual(value, 42.5)
        }
    }

    func testWithStatement_returnsNilForInvalidSQL() {
        SQLiteHelper.withDatabase(path: dbPath) { db in
            let result = SQLiteHelper.withStatement(db: db, sql: "INVALID SQL") { _ in true }
            XCTAssertNil(result)
        }
    }

    // MARK: - Bind & Column Helpers

    func testBindAndColumnDouble() {
        SQLiteHelper.withDatabase(path: dbPath) { db in
            sqlite3_exec(db, "CREATE TABLE t (a REAL, b REAL);", nil, nil, nil)

            SQLiteHelper.withStatement(db: db, sql: "INSERT INTO t VALUES (?, ?);") { stmt in
                SQLiteHelper.bindDouble(stmt, 1, 3.14)
                SQLiteHelper.bindDouble(stmt, 2, nil)
                sqlite3_step(stmt)
            }

            SQLiteHelper.withStatement(db: db, sql: "SELECT a, b FROM t;") { stmt in
                guard sqlite3_step(stmt) == SQLITE_ROW else { return XCTFail("No row") }
                XCTAssertEqual(SQLiteHelper.columnDouble(stmt, 0), 3.14)
                XCTAssertNil(SQLiteHelper.columnDouble(stmt, 1))
            }
        }
    }

    func testBindAndColumnText() {
        SQLiteHelper.withDatabase(path: dbPath) { db in
            sqlite3_exec(db, "CREATE TABLE t (a TEXT, b TEXT);", nil, nil, nil)

            SQLiteHelper.withStatement(db: db, sql: "INSERT INTO t VALUES (?, ?);") { stmt in
                SQLiteHelper.bindText(stmt, 1, "hello")
                SQLiteHelper.bindText(stmt, 2, nil)
                sqlite3_step(stmt)
            }

            SQLiteHelper.withStatement(db: db, sql: "SELECT a, b FROM t;") { stmt in
                guard sqlite3_step(stmt) == SQLITE_ROW else { return XCTFail("No row") }
                XCTAssertEqual(SQLiteHelper.columnText(stmt, 0), "hello")
                XCTAssertNil(SQLiteHelper.columnText(stmt, 1))
            }
        }
    }

    func testBindAndColumnInt64() {
        SQLiteHelper.withDatabase(path: dbPath) { db in
            sqlite3_exec(db, "CREATE TABLE t (a INTEGER, b INTEGER);", nil, nil, nil)

            SQLiteHelper.withStatement(db: db, sql: "INSERT INTO t VALUES (?, ?);") { stmt in
                SQLiteHelper.bindInt64(stmt, 1, 9876543210)
                SQLiteHelper.bindInt64(stmt, 2, nil)
                sqlite3_step(stmt)
            }

            SQLiteHelper.withStatement(db: db, sql: "SELECT a, b FROM t;") { stmt in
                guard sqlite3_step(stmt) == SQLITE_ROW else { return XCTFail("No row") }
                XCTAssertEqual(SQLiteHelper.columnInt64(stmt, 0), 9876543210)
                XCTAssertNil(SQLiteHelper.columnInt64(stmt, 1))
            }
        }
    }

    func testColumnInt() {
        SQLiteHelper.withDatabase(path: dbPath) { db in
            sqlite3_exec(db, "CREATE TABLE t (a INTEGER, b INTEGER);", nil, nil, nil)
            sqlite3_exec(db, "INSERT INTO t VALUES (42, NULL);", nil, nil, nil)

            SQLiteHelper.withStatement(db: db, sql: "SELECT a, b FROM t;") { stmt in
                guard sqlite3_step(stmt) == SQLITE_ROW else { return XCTFail("No row") }
                XCTAssertEqual(SQLiteHelper.columnInt(stmt, 0), 42)
                XCTAssertNil(SQLiteHelper.columnInt(stmt, 1))
            }
        }
    }

    func testColumnDate() {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dateStr = "2026-03-04T12:00:00.000Z"
        let expectedDate = iso.date(from: dateStr)!

        SQLiteHelper.withDatabase(path: dbPath) { db in
            sqlite3_exec(db, "CREATE TABLE t (ts TEXT, empty TEXT);", nil, nil, nil)

            SQLiteHelper.withStatement(db: db, sql: "INSERT INTO t VALUES (?, NULL);") { stmt in
                SQLiteHelper.bindText(stmt, 1, dateStr)
                sqlite3_step(stmt)
            }

            SQLiteHelper.withStatement(db: db, sql: "SELECT ts, empty FROM t;") { stmt in
                guard sqlite3_step(stmt) == SQLITE_ROW else { return XCTFail("No row") }
                XCTAssertEqual(SQLiteHelper.columnDate(stmt, 0, formatter: iso), expectedDate)
                XCTAssertNil(SQLiteHelper.columnDate(stmt, 1, formatter: iso))
            }
        }
    }

    // MARK: - walPragmas

    func testWalPragmas_isNonEmpty() {
        XCTAssertEqual(SQLiteHelper.walPragmas.count, 2)
        XCTAssertTrue(SQLiteHelper.walPragmas[0].contains("WAL"))
        XCTAssertTrue(SQLiteHelper.walPragmas[1].contains("busy_timeout"))
    }
}
