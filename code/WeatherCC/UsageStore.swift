// meta: created=2026-02-21 updated=2026-02-27 checked=never
import Foundation
import SQLite3
import WeatherCCShared

final class UsageStore {

    let dbPath: String
    private let dirURL: URL

    init(dbPath: String) {
        self.dbPath = dbPath
        self.dirURL = URL(fileURLWithPath: dbPath).deletingLastPathComponent()
    }

    static let shared: UsageStore = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            let tmpDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("WeatherCC-test-shared")
            try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            return UsageStore(dbPath: tmpDir.appendingPathComponent("usage.db").path)
        }
        #endif
        guard let container = AppGroupConfig.containerURL else {
            fatalError("[UsageStore] App Group container not available")
        }
        let dir = container
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(AppGroupConfig.appName, isDirectory: true)
        return UsageStore(dbPath: dir.appendingPathComponent("usage.db").path)
    }()

    private static let createSQL = """
        CREATE TABLE IF NOT EXISTS hourly_sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            resets_at INTEGER NOT NULL UNIQUE
        );
        CREATE TABLE IF NOT EXISTS weekly_sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            resets_at INTEGER NOT NULL UNIQUE
        );
        CREATE TABLE IF NOT EXISTS usage_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            hourly_percent REAL,
            weekly_percent REAL,
            hourly_session_id INTEGER REFERENCES hourly_sessions(id),
            weekly_session_id INTEGER REFERENCES weekly_sessions(id),
            CHECK (hourly_percent IS NOT NULL OR weekly_percent IS NOT NULL)
        );
        """

    // MARK: - Static convenience (delegates to shared)

    static func save(_ result: UsageResult) { shared.save(result) }
    static func loadAllHistory() -> [DataPoint] { shared.loadAllHistory() }
    static func loadHistory(windowSeconds: TimeInterval) -> [DataPoint] { shared.loadHistory(windowSeconds: windowSeconds) }

    // MARK: - normalizeResetsAt

    /// Round a resets_at Date to the nearest hour as epoch seconds.
    /// API returns resets_at with millisecond jitter (e.g. 13:59:59.939 / 14:00:00.082).
    /// This normalizes them to the same session (14:00:00 = 1740405600).
    func normalizeResetsAt(_ date: Date) -> Int {
        let epoch = Int(date.timeIntervalSince1970)
        return ((epoch + 1800) / 3600) * 3600
    }

    // MARK: - Save

    func save(_ result: UsageResult) {
        guard result.fiveHourPercent != nil || result.sevenDayPercent != nil else { return }

        do {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        } catch {
            print("[UsageStore] Failed to create directory: \(error)")
            return
        }

        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            print("[UsageStore] Failed to open DB")
            return
        }
        defer { sqlite3_close(db) }

        sqlite3_exec(db, "PRAGMA foreign_keys = ON", nil, nil, nil)

        guard sqlite3_exec(db, Self.createSQL, nil, nil, nil) == SQLITE_OK else {
            print("[UsageStore] Failed to create table")
            return
        }

        let now = Int64(Date().timeIntervalSince1970)

        let hourlySID = result.fiveHourResetsAt.flatMap { getOrCreateSessionId(db: db, table: "hourly_sessions", date: $0) }
        let weeklySID = result.sevenDayResetsAt.flatMap { getOrCreateSessionId(db: db, table: "weekly_sessions", date: $0) }

        let insertSQL = """
            INSERT INTO usage_log (timestamp, hourly_percent, weekly_percent,
                hourly_session_id, weekly_session_id) VALUES (?, ?, ?, ?, ?);
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
            print("[UsageStore] Failed to prepare statement")
            return
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, now)
        bindDouble(stmt, 2, result.fiveHourPercent)
        bindDouble(stmt, 3, result.sevenDayPercent)
        if let sid = hourlySID { sqlite3_bind_int64(stmt, 4, sid) } else { sqlite3_bind_null(stmt, 4) }
        if let sid = weeklySID { sqlite3_bind_int64(stmt, 5, sid) } else { sqlite3_bind_null(stmt, 5) }

        if sqlite3_step(stmt) != SQLITE_DONE {
            print("[UsageStore] Failed to insert row")
        }
    }

    // MARK: - DataPoint

    struct DataPoint {
        let timestamp: Date
        let fiveHourPercent: Double?
        let sevenDayPercent: Double?
        let fiveHourResetsAt: Date?
        let sevenDayResetsAt: Date?

        init(timestamp: Date, fiveHourPercent: Double?, sevenDayPercent: Double?,
             fiveHourResetsAt: Date? = nil, sevenDayResetsAt: Date? = nil) {
            self.timestamp = timestamp
            self.fiveHourPercent = fiveHourPercent
            self.sevenDayPercent = sevenDayPercent
            self.fiveHourResetsAt = fiveHourResetsAt
            self.sevenDayResetsAt = sevenDayResetsAt
        }
    }

    // MARK: - Load All History

    func loadAllHistory() -> [DataPoint] {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT u.timestamp, u.hourly_percent, u.weekly_percent,
                   hs.resets_at AS hourly_resets_at,
                   ws.resets_at AS weekly_resets_at
            FROM usage_log u
            LEFT JOIN hourly_sessions hs ON u.hourly_session_id = hs.id
            LEFT JOIN weekly_sessions ws ON u.weekly_session_id = ws.id
            ORDER BY u.timestamp ASC;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var results: [DataPoint] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let tsEpoch = sqlite3_column_int64(stmt, 0)
            let ts = Date(timeIntervalSince1970: TimeInterval(tsEpoch))
            let fiveH: Double? = sqlite3_column_type(stmt, 1) != SQLITE_NULL ? sqlite3_column_double(stmt, 1) : nil
            let sevenD: Double? = sqlite3_column_type(stmt, 2) != SQLITE_NULL ? sqlite3_column_double(stmt, 2) : nil
            let fiveHResets: Date? = sqlite3_column_type(stmt, 3) != SQLITE_NULL
                ? Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 3)))
                : nil
            let sevenDResets: Date? = sqlite3_column_type(stmt, 4) != SQLITE_NULL
                ? Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 4)))
                : nil
            results.append(DataPoint(timestamp: ts, fiveHourPercent: fiveH, sevenDayPercent: sevenD,
                                     fiveHourResetsAt: fiveHResets, sevenDayResetsAt: sevenDResets))
        }
        return results
    }

    // MARK: - Load History (windowed)

    func loadHistory(windowSeconds: TimeInterval) -> [DataPoint] {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }

        let cutoff = Int64(Date().addingTimeInterval(-windowSeconds).timeIntervalSince1970)
        let sql = """
            SELECT timestamp, hourly_percent, weekly_percent
            FROM usage_log
            WHERE timestamp >= ?
            ORDER BY timestamp ASC;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, cutoff)

        var results: [DataPoint] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let tsEpoch = sqlite3_column_int64(stmt, 0)
            let ts = Date(timeIntervalSince1970: TimeInterval(tsEpoch))
            let fiveH: Double? = sqlite3_column_type(stmt, 1) != SQLITE_NULL ? sqlite3_column_double(stmt, 1) : nil
            let sevenD: Double? = sqlite3_column_type(stmt, 2) != SQLITE_NULL ? sqlite3_column_double(stmt, 2) : nil
            results.append(DataPoint(timestamp: ts, fiveHourPercent: fiveH, sevenDayPercent: sevenD))
        }
        return results
    }

    // MARK: - Private Helpers

    private func getOrCreateSessionId(db: OpaquePointer?, table: String, date: Date) -> Int64? {
        let normalized = normalizeResetsAt(date)

        var insertStmt: OpaquePointer?
        let insertSQL = "INSERT OR IGNORE INTO \(table) (resets_at) VALUES (?)"
        if sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(insertStmt, 1, Int64(normalized))
            sqlite3_step(insertStmt)
        }
        sqlite3_finalize(insertStmt)

        var selectStmt: OpaquePointer?
        let selectSQL = "SELECT id FROM \(table) WHERE resets_at = ?"
        var sessionId: Int64?
        if sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(selectStmt, 1, Int64(normalized))
            if sqlite3_step(selectStmt) == SQLITE_ROW {
                sessionId = sqlite3_column_int64(selectStmt, 0)
            }
        }
        sqlite3_finalize(selectStmt)

        return sessionId
    }

    private func bindDouble(_ stmt: OpaquePointer?, _ index: Int32, _ value: Double?) {
        if let v = value {
            sqlite3_bind_double(stmt, index, v)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }
}
