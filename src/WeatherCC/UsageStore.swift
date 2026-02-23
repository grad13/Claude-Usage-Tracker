// meta: created=2026-02-21 updated=2026-02-23 checked=never
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

    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Static convenience (delegates to shared)

    static func save(_ result: UsageResult) { shared.save(result) }
    static func loadAllHistory() -> [DataPoint] { shared.loadAllHistory() }
    static func loadHistory(windowSeconds: TimeInterval) -> [DataPoint] { shared.loadHistory(windowSeconds: windowSeconds) }

    // MARK: - Instance Methods

    func save(_ result: UsageResult) {
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

        let createSQL = """
            CREATE TABLE IF NOT EXISTS usage_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                five_hour_percent REAL,
                seven_day_percent REAL,
                five_hour_resets_at TEXT,
                seven_day_resets_at TEXT,
                five_hour_status INTEGER,
                seven_day_status INTEGER,
                five_hour_limit REAL,
                five_hour_remaining REAL,
                seven_day_limit REAL,
                seven_day_remaining REAL,
                raw_json TEXT
            );
            """
        guard sqlite3_exec(db, createSQL, nil, nil, nil) == SQLITE_OK else {
            print("[UsageStore] Failed to create table")
            return
        }

        // Migration for existing databases (errors ignored — duplicate column is expected)
        let migrations = [
            "ALTER TABLE usage_log ADD COLUMN five_hour_status INTEGER",
            "ALTER TABLE usage_log ADD COLUMN seven_day_status INTEGER",
            "ALTER TABLE usage_log ADD COLUMN five_hour_limit REAL",
            "ALTER TABLE usage_log ADD COLUMN five_hour_remaining REAL",
            "ALTER TABLE usage_log ADD COLUMN seven_day_limit REAL",
            "ALTER TABLE usage_log ADD COLUMN seven_day_remaining REAL",
            "ALTER TABLE usage_log ADD COLUMN raw_json TEXT",
        ]
        for sql in migrations {
            sqlite3_exec(db, sql, nil, nil, nil)
        }

        let insertSQL = """
            INSERT INTO usage_log (
                timestamp, five_hour_percent, seven_day_percent,
                five_hour_resets_at, seven_day_resets_at,
                five_hour_status, seven_day_status,
                five_hour_limit, five_hour_remaining,
                seven_day_limit, seven_day_remaining,
                raw_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
            print("[UsageStore] Failed to prepare statement")
            return
        }
        defer { sqlite3_finalize(stmt) }

        let now = iso.string(from: Date())
        sqlite3_bind_text(stmt, 1, (now as NSString).utf8String, -1, nil)
        bindDouble(stmt, 2, result.fiveHourPercent)
        bindDouble(stmt, 3, result.sevenDayPercent)
        bindText(stmt, 4, result.fiveHourResetsAt.map { iso.string(from: $0) })
        bindText(stmt, 5, result.sevenDayResetsAt.map { iso.string(from: $0) })
        bindInt(stmt, 6, result.fiveHourStatus)
        bindInt(stmt, 7, result.sevenDayStatus)
        bindDouble(stmt, 8, result.fiveHourLimit)
        bindDouble(stmt, 9, result.fiveHourRemaining)
        bindDouble(stmt, 10, result.sevenDayLimit)
        bindDouble(stmt, 11, result.sevenDayRemaining)
        bindText(stmt, 12, result.rawJSON)

        if sqlite3_step(stmt) != SQLITE_DONE {
            print("[UsageStore] Failed to insert row")
        }
    }

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

    func loadAllHistory() -> [DataPoint] {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT timestamp, five_hour_percent, seven_day_percent,
                   five_hour_resets_at, seven_day_resets_at
            FROM usage_log
            ORDER BY timestamp ASC;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var results: [DataPoint] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let tsRaw = sqlite3_column_text(stmt, 0),
                  let ts = iso.date(from: String(cString: tsRaw)) else { continue }
            let fiveH: Double? = sqlite3_column_type(stmt, 1) != SQLITE_NULL ? sqlite3_column_double(stmt, 1) : nil
            let sevenD: Double? = sqlite3_column_type(stmt, 2) != SQLITE_NULL ? sqlite3_column_double(stmt, 2) : nil
            let fiveHResets: Date? = {
                guard sqlite3_column_type(stmt, 3) != SQLITE_NULL,
                      let raw = sqlite3_column_text(stmt, 3) else { return nil }
                return iso.date(from: String(cString: raw))
            }()
            let sevenDResets: Date? = {
                guard sqlite3_column_type(stmt, 4) != SQLITE_NULL,
                      let raw = sqlite3_column_text(stmt, 4) else { return nil }
                return iso.date(from: String(cString: raw))
            }()
            results.append(DataPoint(timestamp: ts, fiveHourPercent: fiveH, sevenDayPercent: sevenD,
                                     fiveHourResetsAt: fiveHResets, sevenDayResetsAt: sevenDResets))
        }
        return results
    }

    func loadHistory(windowSeconds: TimeInterval) -> [DataPoint] {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }

        let cutoff = iso.string(from: Date().addingTimeInterval(-windowSeconds))
        let sql = """
            SELECT timestamp, five_hour_percent, seven_day_percent
            FROM usage_log
            WHERE timestamp >= ?
            ORDER BY timestamp ASC;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (cutoff as NSString).utf8String, -1, nil)

        var results: [DataPoint] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let tsRaw = sqlite3_column_text(stmt, 0),
                  let ts = iso.date(from: String(cString: tsRaw)) else { continue }
            let fiveH: Double? = sqlite3_column_type(stmt, 1) != SQLITE_NULL ? sqlite3_column_double(stmt, 1) : nil
            let sevenD: Double? = sqlite3_column_type(stmt, 2) != SQLITE_NULL ? sqlite3_column_double(stmt, 2) : nil
            results.append(DataPoint(timestamp: ts, fiveHourPercent: fiveH, sevenDayPercent: sevenD))
        }
        return results
    }

    private func bindInt(_ stmt: OpaquePointer?, _ index: Int32, _ value: Int?) {
        if let v = value {
            sqlite3_bind_int(stmt, index, Int32(v))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bindDouble(_ stmt: OpaquePointer?, _ index: Int32, _ value: Double?) {
        if let v = value {
            sqlite3_bind_double(stmt, index, v)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let v = value {
            sqlite3_bind_text(stmt, index, (v as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }
}
