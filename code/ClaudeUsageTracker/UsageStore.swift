// meta: created=2026-02-21 updated=2026-03-07 checked=2026-03-03
import Foundation
import SQLite3
import ClaudeUsageTrackerShared

final class UsageStore {

    let dbPath: String
    private let dirURL: URL

    init(dbPath: String) {
        self.dbPath = dbPath
        self.dirURL = URL(fileURLWithPath: dbPath).deletingLastPathComponent()
        checkIntegrity()
    }

    private func checkIntegrity() {
        guard FileManager.default.fileExists(atPath: dbPath) else { return }

        let isCorrupt = SQLiteHelper.withDatabase(path: dbPath) { db -> Bool in
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "PRAGMA quick_check", -1, &stmt, nil) == SQLITE_OK else {
                return true
            }
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW,
                  let cStr = sqlite3_column_text(stmt, 0) else {
                return true
            }
            return String(cString: cStr) != "ok"
        } ?? true

        guard isCorrupt else { return }

        NSLog("[UsageStore] Database integrity check failed, recovering")
        let dbURL = URL(fileURLWithPath: dbPath)
        let corruptURL = dbURL.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: corruptURL)
        try? FileManager.default.moveItem(at: dbURL, to: corruptURL)
        // Clean up WAL/SHM files
        for ext in ["-wal", "-shm"] {
            let auxURL = URL(fileURLWithPath: dbPath + ext)
            try? FileManager.default.removeItem(at: auxURL)
        }
    }

    static let shared: UsageStore = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            let tmpDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("ClaudeUsageTracker-test-shared")
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
            NSLog("[UsageStore] Failed to create directory: %@", error.localizedDescription)
            return
        }

        withDatabase { db in
            sqlite3_exec(db, "PRAGMA foreign_keys = ON", nil, nil, nil)

            guard sqlite3_exec(db, Self.createSQL, nil, nil, nil) == SQLITE_OK else {
                NSLog("[UsageStore] Failed to create table")
                return
            }

            let now = Int64(Date().timeIntervalSince1970)

            let hourlySID = result.fiveHourResetsAt.flatMap { self.getOrCreateHourlySessionId(db: db, date: $0) }
            let weeklySID = result.sevenDayResetsAt.flatMap { self.getOrCreateWeeklySessionId(db: db, date: $0) }

            let insertSQL = """
                INSERT INTO usage_log (timestamp, hourly_percent, weekly_percent,
                    hourly_session_id, weekly_session_id) VALUES (?, ?, ?, ?, ?);
                """
            SQLiteHelper.withStatement(db: db, sql: insertSQL) { stmt in
                sqlite3_bind_int64(stmt, 1, now)
                SQLiteHelper.bindDouble(stmt, 2, result.fiveHourPercent)
                SQLiteHelper.bindDouble(stmt, 3, result.sevenDayPercent)
                SQLiteHelper.bindInt64(stmt, 4, hourlySID)
                SQLiteHelper.bindInt64(stmt, 5, weeklySID)

                if sqlite3_step(stmt) != SQLITE_DONE {
                    NSLog("[UsageStore] Failed to insert row")
                }
            }
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
        withDatabase { db in
            let sql = """
                SELECT u.timestamp, u.hourly_percent, u.weekly_percent,
                       hs.resets_at AS hourly_resets_at,
                       ws.resets_at AS weekly_resets_at
                FROM usage_log u
                LEFT JOIN hourly_sessions hs ON u.hourly_session_id = hs.id
                LEFT JOIN weekly_sessions ws ON u.weekly_session_id = ws.id
                ORDER BY u.timestamp ASC;
                """
            return SQLiteHelper.withStatement(db: db, sql: sql) { stmt in
                readDataPoints(stmt)
            } ?? []
        } ?? []
    }

    // MARK: - Load History (windowed)

    func loadHistory(windowSeconds: TimeInterval) -> [DataPoint] {
        withDatabase { db in
            let cutoff = Int64(Date().addingTimeInterval(-windowSeconds).timeIntervalSince1970)
            let sql = """
                SELECT u.timestamp, u.hourly_percent, u.weekly_percent,
                       hs.resets_at AS hourly_resets_at,
                       ws.resets_at AS weekly_resets_at
                FROM usage_log u
                LEFT JOIN hourly_sessions hs ON u.hourly_session_id = hs.id
                LEFT JOIN weekly_sessions ws ON u.weekly_session_id = ws.id
                WHERE u.timestamp >= ?
                ORDER BY u.timestamp ASC;
                """
            return SQLiteHelper.withStatement(db: db, sql: sql) { stmt in
                sqlite3_bind_int64(stmt, 1, cutoff)
                return readDataPoints(stmt)
            } ?? []
        } ?? []
    }

    // MARK: - Load Daily Usage

    /// Calculate the total sevenDayPercent increase since a given date.
    /// Returns nil if insufficient data (no records in the range).
    /// Handles session boundaries: accumulates usage within each session separately.
    func loadDailyUsage(since: Date) -> Double? {
        (withDatabase { db -> Double? in
            let cutoff = Int64(since.timeIntervalSince1970)
            let sql = """
                SELECT u.weekly_percent, ws.resets_at AS weekly_resets_at
                FROM usage_log u
                LEFT JOIN weekly_sessions ws ON u.weekly_session_id = ws.id
                WHERE u.timestamp >= ? AND u.weekly_percent IS NOT NULL
                ORDER BY u.timestamp ASC;
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, cutoff)

            struct Record {
                let weeklyPercent: Double
                let sessionResetsAt: Int64?
            }

            var records: [Record] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let percent = sqlite3_column_double(stmt, 0)
                let resetsAt = SQLiteHelper.columnInt64(stmt!, 1)
                records.append(Record(weeklyPercent: percent, sessionResetsAt: resetsAt))
            }

            guard records.count >= 2 else { return nil }

            var totalUsage = 0.0
            var sessionStart = records[0].weeklyPercent
            var currentSession = records[0].sessionResetsAt

            for i in 1..<records.count {
                let record = records[i]
                if record.sessionResetsAt != currentSession {
                    let previousLast = records[i - 1].weeklyPercent
                    totalUsage += max(0, previousLast - sessionStart)
                    sessionStart = record.weeklyPercent
                    currentSession = record.sessionResetsAt
                }
            }

            let lastPercent = records[records.count - 1].weeklyPercent
            totalUsage += max(0, lastPercent - sessionStart)

            return totalUsage
        }) ?? nil
    }

    // MARK: - Private: Database Helper

    private func withDatabase<T>(_ body: (OpaquePointer) -> T?) -> T? {
        SQLiteHelper.withDatabase(path: dbPath) { db -> T? in
            body(db)
        } ?? nil
    }

    /// Read DataPoints from a prepared statement with 5 columns:
    /// timestamp, hourly_percent, weekly_percent, hourly_resets_at, weekly_resets_at
    private func readDataPoints(_ stmt: OpaquePointer) -> [DataPoint] {
        var results: [DataPoint] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let tsEpoch = sqlite3_column_int64(stmt, 0)
            let ts = Date(timeIntervalSince1970: TimeInterval(tsEpoch))
            let fiveH = SQLiteHelper.columnDouble(stmt, 1)
            let sevenD = SQLiteHelper.columnDouble(stmt, 2)
            let fiveHResets: Date? = SQLiteHelper.columnInt64(stmt, 3)
                .map { Date(timeIntervalSince1970: TimeInterval($0)) }
            let sevenDResets: Date? = SQLiteHelper.columnInt64(stmt, 4)
                .map { Date(timeIntervalSince1970: TimeInterval($0)) }
            results.append(DataPoint(timestamp: ts, fiveHourPercent: fiveH, sevenDayPercent: sevenD,
                                     fiveHourResetsAt: fiveHResets, sevenDayResetsAt: sevenDResets))
        }
        return results
    }

    // MARK: - Private Helpers

    private func getOrCreateHourlySessionId(db: OpaquePointer, date: Date) -> Int64? {
        getOrCreateSessionId(
            db: db, date: date,
            insertSQL: "INSERT OR IGNORE INTO hourly_sessions (resets_at) VALUES (?)",
            selectSQL: "SELECT id FROM hourly_sessions WHERE resets_at = ?"
        )
    }

    private func getOrCreateWeeklySessionId(db: OpaquePointer, date: Date) -> Int64? {
        getOrCreateSessionId(
            db: db, date: date,
            insertSQL: "INSERT OR IGNORE INTO weekly_sessions (resets_at) VALUES (?)",
            selectSQL: "SELECT id FROM weekly_sessions WHERE resets_at = ?"
        )
    }

    private func getOrCreateSessionId(db: OpaquePointer, date: Date, insertSQL: String, selectSQL: String) -> Int64? {
        let normalized = Int64(normalizeResetsAt(date))

        SQLiteHelper.withStatement(db: db, sql: insertSQL) { stmt in
            sqlite3_bind_int64(stmt, 1, normalized)
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE {
                NSLog("[UsageStore] Session INSERT returned %d", rc)
            }
        }

        return (SQLiteHelper.withStatement(db: db, sql: selectSQL) { stmt -> Int64? in
            sqlite3_bind_int64(stmt, 1, normalized)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return sqlite3_column_int64(stmt, 0)
        }) ?? nil
    }
}
