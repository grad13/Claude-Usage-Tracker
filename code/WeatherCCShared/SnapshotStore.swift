// meta: created=2026-02-21 updated=2026-02-24 checked=never
import Foundation
import SQLite3
import os

/// Shares UsageSnapshot between the main app and widget extension via App Group SQLite DB.
/// Replaces the previous JSON-based implementation that suffered from full-file overwrites
/// destroying history data on every app launch.
public enum SnapshotStore {

    private static let log = Logger(subsystem: "grad13.weathercc", category: "SnapshotStore")

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Override for tests — set to a temp path to isolate from production DB.
    public nonisolated(unsafe) static var dbPathOverride: String?

    private static var dbPath: String {
        if let override = dbPathOverride { return override }
        return AppGroupConfig.snapshotDBPath ?? ""
    }

    // MARK: - Public API

    /// Create DB file and tables if needed (idempotent).
    /// Also runs one-time JSON → SQLite migration if snapshot.json exists.
    private static func ensureDB() {
        let path = dbPath
        guard !path.isEmpty else { return }

        let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            log.error("ensureDB: failed to open \(path)")
            return
        }
        defer { sqlite3_close(db) }

        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA busy_timeout=3000;", nil, nil, nil)

        let createState = """
            CREATE TABLE IF NOT EXISTS snapshot_state (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                timestamp TEXT NOT NULL,
                five_hour_percent REAL,
                seven_day_percent REAL,
                five_hour_resets_at TEXT,
                seven_day_resets_at TEXT,
                is_logged_in INTEGER NOT NULL DEFAULT 0,
                predict_five_hour_cost REAL,
                predict_seven_day_cost REAL
            );
            """
        let createHistory = """
            CREATE TABLE IF NOT EXISTS snapshot_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                five_hour_percent REAL,
                seven_day_percent REAL
            );
            """
        sqlite3_exec(db, createState, nil, nil, nil)
        sqlite3_exec(db, createHistory, nil, nil, nil)

        sqlite3_exec(db, """
            CREATE INDEX IF NOT EXISTS idx_history_timestamp ON snapshot_history(timestamp);
            """, nil, nil, nil)

        migrateFromJSON(db: db!)
    }

    /// Called after a successful fetch: update state + append history.
    public static func saveAfterFetch(
        timestamp: Date,
        fiveHourPercent: Double?, sevenDayPercent: Double?,
        fiveHourResetsAt: Date?, sevenDayResetsAt: Date?,
        isLoggedIn: Bool
    ) {
        ensureDB()
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "PRAGMA busy_timeout=3000;", nil, nil, nil)

        // INSERT OR REPLACE snapshot_state (id=1 fixed).
        // predict_* preserved via subquery (evaluated before DELETE in INSERT OR REPLACE).
        // percent COALESCE: if nil (API didn't return a window), keep existing value.
        let stateSQL = """
            INSERT OR REPLACE INTO snapshot_state (
                id, timestamp, five_hour_percent, seven_day_percent,
                five_hour_resets_at, seven_day_resets_at, is_logged_in,
                predict_five_hour_cost, predict_seven_day_cost
            ) VALUES (
                1, ?,
                COALESCE(?, (SELECT five_hour_percent FROM snapshot_state WHERE id=1)),
                COALESCE(?, (SELECT seven_day_percent FROM snapshot_state WHERE id=1)),
                ?, ?, ?,
                (SELECT predict_five_hour_cost FROM snapshot_state WHERE id=1),
                (SELECT predict_seven_day_cost FROM snapshot_state WHERE id=1)
            );
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, stateSQL, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        let ts = iso.string(from: timestamp)
        sqlite3_bind_text(stmt, 1, (ts as NSString).utf8String, -1, nil)
        bindDouble(stmt, 2, fiveHourPercent)
        bindDouble(stmt, 3, sevenDayPercent)
        bindText(stmt, 4, fiveHourResetsAt.map { iso.string(from: $0) })
        bindText(stmt, 5, sevenDayResetsAt.map { iso.string(from: $0) })
        sqlite3_bind_int(stmt, 6, isLoggedIn ? 1 : 0)

        if sqlite3_step(stmt) != SQLITE_DONE {
            log.error("saveAfterFetch: state INSERT failed")
        }

        // INSERT snapshot_history
        let histSQL = "INSERT INTO snapshot_history (timestamp, five_hour_percent, seven_day_percent) VALUES (?, ?, ?);"
        var histStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, histSQL, -1, &histStmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(histStmt) }

        sqlite3_bind_text(histStmt, 1, (ts as NSString).utf8String, -1, nil)
        bindDouble(histStmt, 2, fiveHourPercent)
        bindDouble(histStmt, 3, sevenDayPercent)

        if sqlite3_step(histStmt) != SQLITE_DONE {
            log.error("saveAfterFetch: history INSERT failed")
        }
    }

    /// Update predict values only (state's other fields untouched).
    /// If DB doesn't exist or state row is absent, this is a no-op.
    public static func updatePredict(fiveHourCost: Double?, sevenDayCost: Double?) {
        let path = dbPath
        guard !path.isEmpty else { return }
        guard FileManager.default.fileExists(atPath: path) else { return }
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "PRAGMA busy_timeout=3000;", nil, nil, nil)

        let sql = "UPDATE snapshot_state SET predict_five_hour_cost = ?, predict_seven_day_cost = ? WHERE id = 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        bindDouble(stmt, 1, fiveHourCost)
        bindDouble(stmt, 2, sevenDayCost)
        sqlite3_step(stmt)
    }

    /// Sign out: reset state to logged-out, keep history.
    public static func clearOnSignOut() {
        let path = dbPath
        guard !path.isEmpty else { return }
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "PRAGMA busy_timeout=3000;", nil, nil, nil)

        let sql = """
            UPDATE snapshot_state SET
                timestamp = ?,
                five_hour_percent = NULL,
                seven_day_percent = NULL,
                five_hour_resets_at = NULL,
                seven_day_resets_at = NULL,
                is_logged_in = 0,
                predict_five_hour_cost = NULL,
                predict_seven_day_cost = NULL
            WHERE id = 1;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        let ts = iso.string(from: Date())
        sqlite3_bind_text(stmt, 1, (ts as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
    }

    /// Load snapshot for widget display.
    public static func load() -> UsageSnapshot? {
        let path = dbPath
        guard !path.isEmpty else {
            log.warning("load: dbPath is empty")
            return nil
        }
        guard FileManager.default.fileExists(atPath: path) else {
            log.warning("load: file not found at \(path)")
            return nil
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            log.error("load: sqlite3_open_v2 failed for \(path)")
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "PRAGMA busy_timeout=3000;", nil, nil, nil)

        // 1. Read current state
        let stateSQL = """
            SELECT timestamp, five_hour_percent, seven_day_percent,
                   five_hour_resets_at, seven_day_resets_at, is_logged_in,
                   predict_five_hour_cost, predict_seven_day_cost
            FROM snapshot_state WHERE id = 1;
            """
        var stateStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, stateSQL, -1, &stateStmt, nil) == SQLITE_OK else {
            log.error("load: prepare state query failed")
            return nil
        }
        defer { sqlite3_finalize(stateStmt) }

        guard sqlite3_step(stateStmt) == SQLITE_ROW else {
            log.warning("load: no state row found")
            return nil
        }

        guard let tsRaw = sqlite3_column_text(stateStmt, 0),
              let timestamp = iso.date(from: String(cString: tsRaw)) else {
            log.error("load: failed to parse timestamp")
            return nil
        }

        let fiveHourPercent: Double? = sqlite3_column_type(stateStmt, 1) != SQLITE_NULL
            ? sqlite3_column_double(stateStmt, 1) : nil
        let sevenDayPercent: Double? = sqlite3_column_type(stateStmt, 2) != SQLITE_NULL
            ? sqlite3_column_double(stateStmt, 2) : nil
        let fiveHourResetsAt: Date? = readDate(stateStmt, column: 3)
        let sevenDayResetsAt: Date? = readDate(stateStmt, column: 4)
        let isLoggedIn = sqlite3_column_int(stateStmt, 5) != 0
        let predictFiveH: Double? = sqlite3_column_type(stateStmt, 6) != SQLITE_NULL
            ? sqlite3_column_double(stateStmt, 6) : nil
        let predictSevenD: Double? = sqlite3_column_type(stateStmt, 7) != SQLITE_NULL
            ? sqlite3_column_double(stateStmt, 7) : nil

        // 2. Load history for 5h and 7d windows
        let fiveHourHistory = loadHistory(db: db!, windowSeconds: 5 * 3600)
        let sevenDayHistory = loadHistory(db: db!, windowSeconds: 7 * 24 * 3600)

        log.info("load: success — 5h=\(fiveHourPercent ?? -1) 7d=\(sevenDayPercent ?? -1) 5hHist=\(fiveHourHistory.count) 7dHist=\(sevenDayHistory.count)")

        return UsageSnapshot(
            timestamp: timestamp,
            fiveHourPercent: fiveHourPercent,
            sevenDayPercent: sevenDayPercent,
            fiveHourResetsAt: fiveHourResetsAt,
            sevenDayResetsAt: sevenDayResetsAt,
            fiveHourHistory: fiveHourHistory,
            sevenDayHistory: sevenDayHistory,
            isLoggedIn: isLoggedIn,
            predictFiveHourCost: predictFiveH,
            predictSevenDayCost: predictSevenD
        )
    }

    // MARK: - Private Helpers

    private static func loadHistory(db: OpaquePointer, windowSeconds: TimeInterval) -> [HistoryPoint] {
        let cutoff = iso.string(from: Date().addingTimeInterval(-windowSeconds))
        let sql = """
            SELECT timestamp, five_hour_percent, seven_day_percent
            FROM snapshot_history
            WHERE timestamp >= ?
            ORDER BY timestamp ASC;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (cutoff as NSString).utf8String, -1, nil)

        // 5h window (18000s) → five_hour_percent (column 1)
        // 7d window (604800s) → seven_day_percent (column 2)
        let fiveHourWindow: TimeInterval = 5 * 3600
        let columnIndex: Int32 = windowSeconds <= fiveHourWindow ? 1 : 2

        var results: [HistoryPoint] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let tsRaw = sqlite3_column_text(stmt, 0),
                  let ts = iso.date(from: String(cString: tsRaw)) else { continue }
            let percent: Double? = sqlite3_column_type(stmt, columnIndex) != SQLITE_NULL
                ? sqlite3_column_double(stmt, columnIndex) : nil
            guard let p = percent else { continue }
            results.append(HistoryPoint(timestamp: ts, percent: p))
        }
        return results
    }

    private static func bindDouble(_ stmt: OpaquePointer?, _ index: Int32, _ value: Double?) {
        if let v = value { sqlite3_bind_double(stmt, index, v) }
        else { sqlite3_bind_null(stmt, index) }
    }

    private static func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let v = value { sqlite3_bind_text(stmt, index, (v as NSString).utf8String, -1, nil) }
        else { sqlite3_bind_null(stmt, index) }
    }

    private static func readDate(_ stmt: OpaquePointer?, column: Int32) -> Date? {
        guard sqlite3_column_type(stmt, column) != SQLITE_NULL,
              let raw = sqlite3_column_text(stmt, column) else { return nil }
        return iso.date(from: String(cString: raw))
    }

    // MARK: - JSON → SQLite Migration

    private static func migrateFromJSON(db: OpaquePointer) {
        guard let legacyURL = AppGroupConfig.legacySnapshotURL,
              FileManager.default.fileExists(atPath: legacyURL.path) else { return }

        // Decode with .iso8601 (no fractional seconds) to match old JSONEncoder format
        let legacyDecoder = JSONDecoder()
        legacyDecoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: legacyURL),
              let snapshot = try? legacyDecoder.decode(UsageSnapshot.self, from: data) else {
            log.error("migrateFromJSON: decode failed, skipping")
            return
        }

        // 1. Insert snapshot_state
        let ts = iso.string(from: snapshot.timestamp)
        let stateSQL = """
            INSERT OR REPLACE INTO snapshot_state (
                id, timestamp, five_hour_percent, seven_day_percent,
                five_hour_resets_at, seven_day_resets_at, is_logged_in,
                predict_five_hour_cost, predict_seven_day_cost
            ) VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        var stateStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, stateSQL, -1, &stateStmt, nil) == SQLITE_OK else {
            log.error("migrateFromJSON: state prepare failed")
            return
        }
        defer { sqlite3_finalize(stateStmt) }

        sqlite3_bind_text(stateStmt, 1, (ts as NSString).utf8String, -1, nil)
        bindDouble(stateStmt, 2, snapshot.fiveHourPercent)
        bindDouble(stateStmt, 3, snapshot.sevenDayPercent)
        bindText(stateStmt, 4, snapshot.fiveHourResetsAt.map { iso.string(from: $0) })
        bindText(stateStmt, 5, snapshot.sevenDayResetsAt.map { iso.string(from: $0) })
        sqlite3_bind_int(stateStmt, 6, snapshot.isLoggedIn ? 1 : 0)
        bindDouble(stateStmt, 7, snapshot.predictFiveHourCost)
        bindDouble(stateStmt, 8, snapshot.predictSevenDayCost)

        if sqlite3_step(stateStmt) != SQLITE_DONE {
            log.error("migrateFromJSON: state INSERT failed")
            return
        }

        // 2. Merge 5h + 7d history by timestamp, insert into snapshot_history
        var historyMap: [TimeInterval: (fiveH: Double?, sevenD: Double?)] = [:]
        for hp in snapshot.fiveHourHistory {
            let key = hp.timestamp.timeIntervalSince1970
            historyMap[key, default: (nil, nil)].fiveH = hp.percent
        }
        for hp in snapshot.sevenDayHistory {
            let key = hp.timestamp.timeIntervalSince1970
            historyMap[key, default: (nil, nil)].sevenD = hp.percent
        }

        let sorted = historyMap.sorted { $0.key < $1.key }
        let histSQL = "INSERT INTO snapshot_history (timestamp, five_hour_percent, seven_day_percent) VALUES (?, ?, ?);"
        var histStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, histSQL, -1, &histStmt, nil) == SQLITE_OK else {
            log.error("migrateFromJSON: history prepare failed")
            return
        }
        defer { sqlite3_finalize(histStmt) }

        sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
        for (epoch, percents) in sorted {
            let histTS = iso.string(from: Date(timeIntervalSince1970: epoch))
            sqlite3_reset(histStmt)
            sqlite3_bind_text(histStmt, 1, (histTS as NSString).utf8String, -1, nil)
            bindDouble(histStmt, 2, percents.fiveH)
            bindDouble(histStmt, 3, percents.sevenD)
            sqlite3_step(histStmt)
        }
        sqlite3_exec(db, "COMMIT;", nil, nil, nil)

        // 3. Rename JSON to .bak
        let bakURL = legacyURL.deletingLastPathComponent().appendingPathComponent("snapshot.json.bak")
        try? FileManager.default.removeItem(at: bakURL)
        try? FileManager.default.moveItem(at: legacyURL, to: bakURL)
        log.info("migrateFromJSON: migrated \(sorted.count) history points, backed up JSON")
    }
}
