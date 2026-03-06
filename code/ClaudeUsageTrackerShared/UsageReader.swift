// meta: created=2026-03-04 updated=2026-03-04 checked=never
import Foundation
import SQLite3
import os

/// Read-only access to usage.db for the widget extension.
/// The main app writes via UsageStore; this type only reads.
public enum UsageReader {

    private static let log = Logger(subsystem: "grad13.claudeusagetracker", category: "UsageReader")

    /// How recent the latest data must be to consider the user "logged in".
    private static let loginFreshnessSeconds: TimeInterval = 600 // 10 minutes

    /// Load a UsageSnapshot from usage.db for widget display.
    public static func load() -> UsageSnapshot? {
        guard let path = AppGroupConfig.usageDBPath else {
            log.warning("load: usageDBPath is nil")
            return nil
        }
        guard FileManager.default.fileExists(atPath: path) else {
            log.warning("load: usage.db not found at \(path)")
            return nil
        }

        return SQLiteHelper.withDatabase(
            path: path,
            flags: SQLITE_OPEN_READONLY,
            pragmas: ["PRAGMA busy_timeout=3000;"]
        ) { db -> UsageSnapshot? in

            // Latest state: most recent row with non-NULL values
            guard let state = loadLatestState(db: db) else {
                log.warning("load: no data in usage_log")
                return nil
            }

            let fiveHourHistory = loadHistory(db: db, windowSeconds: 5 * 3600, columnName: "hourly_percent")
            let sevenDayHistory = loadHistory(db: db, windowSeconds: 7 * 24 * 3600, columnName: "weekly_percent")

            let isLoggedIn = state.timestamp.timeIntervalSinceNow > -loginFreshnessSeconds

            log.info("load: 5h=\(state.fiveHourPercent ?? -1) 7d=\(state.sevenDayPercent ?? -1) 5hHist=\(fiveHourHistory.count) 7dHist=\(sevenDayHistory.count) loggedIn=\(isLoggedIn)")

            return UsageSnapshot(
                timestamp: state.timestamp,
                fiveHourPercent: state.fiveHourPercent,
                sevenDayPercent: state.sevenDayPercent,
                fiveHourResetsAt: state.fiveHourResetsAt,
                sevenDayResetsAt: state.sevenDayResetsAt,
                fiveHourHistory: fiveHourHistory,
                sevenDayHistory: sevenDayHistory,
                isLoggedIn: isLoggedIn
            )
        } ?? nil
    }

    // MARK: - Private

    private struct LatestState {
        let timestamp: Date
        let fiveHourPercent: Double?
        let sevenDayPercent: Double?
        let fiveHourResetsAt: Date?
        let sevenDayResetsAt: Date?
    }

    /// Get the most recent usage_log row with its session resets_at values.
    private static func loadLatestState(db: OpaquePointer) -> LatestState? {
        let sql = """
            SELECT u.timestamp, u.hourly_percent, u.weekly_percent,
                   hs.resets_at AS hourly_resets_at,
                   ws.resets_at AS weekly_resets_at
            FROM usage_log u
            LEFT JOIN hourly_sessions hs ON u.hourly_session_id = hs.id
            LEFT JOIN weekly_sessions ws ON u.weekly_session_id = ws.id
            ORDER BY u.timestamp DESC
            LIMIT 1;
            """
        return SQLiteHelper.withStatement(db: db, sql: sql) { stmt -> LatestState? in
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            let tsEpoch = sqlite3_column_int64(stmt, 0)
            return LatestState(
                timestamp: Date(timeIntervalSince1970: TimeInterval(tsEpoch)),
                fiveHourPercent: SQLiteHelper.columnDouble(stmt, 1),
                sevenDayPercent: SQLiteHelper.columnDouble(stmt, 2),
                fiveHourResetsAt: SQLiteHelper.columnInt64(stmt, 3)
                    .map { Date(timeIntervalSince1970: TimeInterval($0)) },
                sevenDayResetsAt: SQLiteHelper.columnInt64(stmt, 4)
                    .map { Date(timeIntervalSince1970: TimeInterval($0)) }
            )
        } ?? nil
    }

    /// Load history points for a given time window.
    /// columnName: "hourly_percent" for 5h, "weekly_percent" for 7d.
    private static func loadHistory(db: OpaquePointer, windowSeconds: TimeInterval, columnName: String) -> [HistoryPoint] {
        let cutoff = Int64(Date().addingTimeInterval(-windowSeconds).timeIntervalSince1970)
        let sql = """
            SELECT timestamp, \(columnName)
            FROM usage_log
            WHERE timestamp >= ? AND \(columnName) IS NOT NULL
            ORDER BY timestamp ASC;
            """
        return SQLiteHelper.withStatement(db: db, sql: sql) { stmt in
            sqlite3_bind_int64(stmt, 1, cutoff)
            var results: [HistoryPoint] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let tsEpoch = sqlite3_column_int64(stmt, 0)
                let percent = sqlite3_column_double(stmt, 1)
                results.append(HistoryPoint(
                    timestamp: Date(timeIntervalSince1970: TimeInterval(tsEpoch)),
                    percent: percent
                ))
            }
            return results
        } ?? []
    }
}
