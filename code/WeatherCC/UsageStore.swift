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
        migrateSchemaIfNeeded()
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

    // MARK: - Schema Migration (old → new)

    /// Detect old schema (five_hour_percent column) and migrate to new normalized schema.
    /// Creates a new DB file, copies transformed data, then swaps files.
    /// Backup is saved as usage.db.bak for rollback.
    private func migrateSchemaIfNeeded() {
        guard FileManager.default.fileExists(atPath: dbPath) else { return }

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return }

        // Detect old schema: presence of five_hour_percent column
        var hasOldSchema = false
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA table_info(usage_log)", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let name = sqlite3_column_text(stmt, 1),
                   String(cString: name) == "five_hour_percent" {
                    hasOldSchema = true
                    break
                }
            }
        }
        sqlite3_finalize(stmt)

        guard hasOldSchema else {
            sqlite3_close(db)
            return
        }

        // Read all rows from old schema
        let readSQL = """
            SELECT timestamp, five_hour_percent, seven_day_percent,
                   five_hour_resets_at, seven_day_resets_at
            FROM usage_log
            ORDER BY timestamp ASC
            """
        struct OldRow {
            let timestamp: String
            let fiveHourPercent: Double?
            let sevenDayPercent: Double?
            let fiveHourResetsAt: String?
            let sevenDayResetsAt: String?
        }

        var oldRows: [OldRow] = []
        if sqlite3_prepare_v2(db, readSQL, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let tsRaw = sqlite3_column_text(stmt, 0) else { continue }
                let ts = String(cString: tsRaw)
                let fhp: Double? = sqlite3_column_type(stmt, 1) != SQLITE_NULL ? sqlite3_column_double(stmt, 1) : nil
                let sdp: Double? = sqlite3_column_type(stmt, 2) != SQLITE_NULL ? sqlite3_column_double(stmt, 2) : nil
                guard fhp != nil || sdp != nil else { continue }
                let fhra: String? = {
                    guard sqlite3_column_type(stmt, 3) != SQLITE_NULL,
                          let raw = sqlite3_column_text(stmt, 3) else { return nil }
                    return String(cString: raw)
                }()
                let sdra: String? = {
                    guard sqlite3_column_type(stmt, 4) != SQLITE_NULL,
                          let raw = sqlite3_column_text(stmt, 4) else { return nil }
                    return String(cString: raw)
                }()
                oldRows.append(OldRow(timestamp: ts, fiveHourPercent: fhp, sevenDayPercent: sdp,
                                      fiveHourResetsAt: fhra, sevenDayResetsAt: sdra))
            }
        }
        sqlite3_finalize(stmt)
        sqlite3_close(db)

        // ISO8601 parsers for old TEXT timestamps
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]
        func parseISO(_ text: String) -> Date? {
            isoFrac.date(from: text) ?? isoNoFrac.date(from: text)
        }

        // Create new DB at temporary path
        let migratePath = dirURL.appendingPathComponent("usage_migrate.db").path
        try? FileManager.default.removeItem(atPath: migratePath)

        var newDB: OpaquePointer?
        guard sqlite3_open(migratePath, &newDB) == SQLITE_OK else {
            print("[UsageStore] Migration: failed to create new DB")
            return
        }

        sqlite3_exec(newDB, "PRAGMA foreign_keys = ON", nil, nil, nil)
        guard sqlite3_exec(newDB, Self.createSQL, nil, nil, nil) == SQLITE_OK else {
            print("[UsageStore] Migration: failed to create tables")
            sqlite3_close(newDB)
            try? FileManager.default.removeItem(atPath: migratePath)
            return
        }

        // Session caches: normalized epoch → session row id
        var hourlyCache: [Int: Int64] = [:]
        var weeklyCache: [Int: Int64] = [:]

        sqlite3_exec(newDB, "BEGIN TRANSACTION", nil, nil, nil)

        var migrated = 0
        for row in oldRows {
            guard let tsDate = parseISO(row.timestamp) else { continue }
            let tsEpoch = Int64(tsDate.timeIntervalSince1970)

            let hourlySID: Int64? = row.fiveHourResetsAt.flatMap { text -> Int64? in
                guard let date = parseISO(text) else { return nil }
                let norm = normalizeResetsAt(date)
                if let cached = hourlyCache[norm] { return cached }
                return insertSession(db: newDB, table: "hourly_sessions", epoch: norm, cache: &hourlyCache)
            }

            let weeklySID: Int64? = row.sevenDayResetsAt.flatMap { text -> Int64? in
                guard let date = parseISO(text) else { return nil }
                let norm = normalizeResetsAt(date)
                if let cached = weeklyCache[norm] { return cached }
                return insertSession(db: newDB, table: "weekly_sessions", epoch: norm, cache: &weeklyCache)
            }

            var insertStmt: OpaquePointer?
            let insertSQL = "INSERT INTO usage_log (timestamp, hourly_percent, weekly_percent, hourly_session_id, weekly_session_id) VALUES (?, ?, ?, ?, ?)"
            if sqlite3_prepare_v2(newDB, insertSQL, -1, &insertStmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(insertStmt, 1, tsEpoch)
                bindDouble(insertStmt, 2, row.fiveHourPercent)
                bindDouble(insertStmt, 3, row.sevenDayPercent)
                if let sid = hourlySID { sqlite3_bind_int64(insertStmt, 4, sid) } else { sqlite3_bind_null(insertStmt, 4) }
                if let sid = weeklySID { sqlite3_bind_int64(insertStmt, 5, sid) } else { sqlite3_bind_null(insertStmt, 5) }
                if sqlite3_step(insertStmt) == SQLITE_DONE { migrated += 1 }
            }
            sqlite3_finalize(insertStmt)
        }

        sqlite3_exec(newDB, "COMMIT", nil, nil, nil)
        sqlite3_close(newDB)

        // Swap files: old → .bak, new → usage.db
        let backupPath = dbPath + ".bak"
        do {
            try? FileManager.default.removeItem(atPath: backupPath)
            try FileManager.default.moveItem(atPath: dbPath, toPath: backupPath)
            try FileManager.default.moveItem(atPath: migratePath, toPath: dbPath)
            print("[UsageStore] Migration complete: \(migrated) rows, backup at \(backupPath)")
        } catch {
            print("[UsageStore] Migration file swap failed: \(error)")
            try? FileManager.default.removeItem(atPath: dbPath)
            try? FileManager.default.moveItem(atPath: backupPath, toPath: dbPath)
            try? FileManager.default.removeItem(atPath: migratePath)
        }
    }

    /// INSERT OR IGNORE a session row and return its id. Updates the cache.
    private func insertSession(db: OpaquePointer?, table: String, epoch: Int, cache: inout [Int: Int64]) -> Int64? {
        var insertStmt: OpaquePointer?
        let insertSQL = "INSERT OR IGNORE INTO \(table) (resets_at) VALUES (?)"
        if sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(insertStmt, 1, Int64(epoch))
            sqlite3_step(insertStmt)
        }
        sqlite3_finalize(insertStmt)

        var selectStmt: OpaquePointer?
        let selectSQL = "SELECT id FROM \(table) WHERE resets_at = ?"
        var sessionId: Int64?
        if sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(selectStmt, 1, Int64(epoch))
            if sqlite3_step(selectStmt) == SQLITE_ROW {
                sessionId = sqlite3_column_int64(selectStmt, 0)
                cache[epoch] = sessionId!
            }
        }
        sqlite3_finalize(selectStmt)

        return sessionId
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
