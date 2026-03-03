// meta: created=2026-03-04 updated=2026-03-04 checked=never
import Foundation
import SQLite3
import os

/// Centralizes repetitive SQLite3 C API patterns used across UsageStore, SnapshotStore,
/// TokenStore, AnalysisSchemeHandler, and SQLiteBackup.
public enum SQLiteHelper {

    private static let log = Logger(subsystem: "grad13.claudeusagetracker", category: "SQLiteHelper")

    /// Standard WAL pragmas applied to writable databases.
    public static let walPragmas = [
        "PRAGMA journal_mode=WAL;",
        "PRAGMA busy_timeout=3000;",
    ]

    // MARK: - Database Lifecycle

    /// Open a database, apply optional pragmas, execute `body`, then close.
    /// Returns nil if the database cannot be opened.
    @discardableResult
    public static func withDatabase<T>(
        path: String,
        flags: Int32 = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
        pragmas: [String] = [],
        body: (OpaquePointer) -> T
    ) -> T? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            log.error("withDatabase: failed to open \(path)")
            return nil
        }
        defer { sqlite3_close(db) }
        for pragma in pragmas {
            sqlite3_exec(db, pragma, nil, nil, nil)
        }
        return body(db!)
    }

    // MARK: - Statement Lifecycle

    /// Prepare a statement, execute `body`, then finalize. Returns nil on prepare failure.
    @discardableResult
    public static func withStatement<T>(
        db: OpaquePointer,
        sql: String,
        body: (OpaquePointer) -> T
    ) -> T? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            log.error("withStatement: prepare failed for: \(sql.prefix(80))")
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        return body(stmt!)
    }

    // MARK: - Bind Helpers

    /// Bind an optional Double (nil binds NULL).
    public static func bindDouble(_ stmt: OpaquePointer, _ index: Int32, _ value: Double?) {
        if let v = value { sqlite3_bind_double(stmt, index, v) }
        else { sqlite3_bind_null(stmt, index) }
    }

    /// Bind an optional String (nil binds NULL).
    public static func bindText(_ stmt: OpaquePointer, _ index: Int32, _ value: String?) {
        if let v = value { sqlite3_bind_text(stmt, index, (v as NSString).utf8String, -1, nil) }
        else { sqlite3_bind_null(stmt, index) }
    }

    /// Bind an optional Int64 (nil binds NULL).
    public static func bindInt64(_ stmt: OpaquePointer, _ index: Int32, _ value: Int64?) {
        if let v = value { sqlite3_bind_int64(stmt, index, v) }
        else { sqlite3_bind_null(stmt, index) }
    }

    // MARK: - Column Readers

    /// Read a Double column, returning nil if NULL.
    public static func columnDouble(_ stmt: OpaquePointer, _ index: Int32) -> Double? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(stmt, index)
    }

    /// Read a String column, returning nil if NULL.
    public static func columnText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let raw = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: raw)
    }

    /// Read an Int column, returning nil if NULL.
    public static func columnInt(_ stmt: OpaquePointer, _ index: Int32) -> Int? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(stmt, index))
    }

    /// Read an Int64 column, returning nil if NULL.
    public static func columnInt64(_ stmt: OpaquePointer, _ index: Int32) -> Int64? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(stmt, index)
    }

    /// Read a TEXT column as a Date via the provided ISO8601DateFormatter, returning nil if NULL.
    public static func columnDate(_ stmt: OpaquePointer, _ index: Int32, formatter: ISO8601DateFormatter) -> Date? {
        guard let text = columnText(stmt, index) else { return nil }
        return formatter.date(from: text)
    }
}
