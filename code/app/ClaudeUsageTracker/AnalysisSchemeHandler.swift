// meta: updated=2026-08-11 checked=2026-03-03 00:00
import Foundation
import SQLite3
import WebKit
import ClaudeUsageTrackerShared

/// Serves data to the Analysis WKWebView via a custom URL scheme (cut://).
/// Queries SQLite databases on the Swift side and serves JSON to JavaScript.
/// Eliminates CDN dependency on sql.js/WASM.
final class AnalysisSchemeHandler: NSObject, WKURLSchemeHandler {

    static let scheme = "cut"

    private let usageDbPath: String
    private let htmlProvider: () -> String
    private let settingsProvider: () -> [String: String]

    init(usageDbPath: String, htmlProvider: @escaping () -> String,
         settingsProvider: @escaping () -> [String: String] = {
             let s = SettingsStore.load()
             let resolved: String
             switch s.graphColorTheme {
             case .system:
                 let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                 resolved = isDark ? "dark" : "light"
             case .light: resolved = "light"
             case .dark: resolved = "dark"
             }
             return [
                 "hourly_color": s.hourlyColorPreset.hexString,
                 "weekly_color": s.weeklyColorPreset.hexString,
                 "color_theme": resolved,
             ]
         }) {
        self.usageDbPath = usageDbPath
        self.htmlProvider = htmlProvider
        self.settingsProvider = settingsProvider
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            fail(urlSchemeTask, code: 400, message: "Missing URL")
            return
        }

        let path = url.host ?? url.path
        let params = parseQueryParams(url)
        let from = params["from"]
        let to = params["to"]

        switch path {
        case "analysis.html":
            serve(urlSchemeTask, url: url, data: htmlProvider().data(using: .utf8), mime: "text/html")
        case "usage.json":
            serve(urlSchemeTask, url: url, data: queryUsageJSON(from: from, to: to), mime: "application/json")
        case "meta.json":
            serve(urlSchemeTask, url: url, data: queryMetaJSON(), mime: "application/json")
        default:
            fail(urlSchemeTask, code: 404, message: "Not found: \(path)")
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    // MARK: - SQLite Queries

    private func queryUsageJSON(from: String?, to: String?) -> Data? {
        let fallback = "[]".data(using: .utf8)
        return SQLiteHelper.withDatabase(path: usageDbPath, flags: SQLITE_OPEN_READONLY) { db in
            guard self.tableExists(db, name: "usage_log") else { return fallback }
            let hasFiveHourExact = self.columnExists(db, table: "usage_log", name: "five_hour_resets_at")
            let hasSevenDayExact = self.columnExists(db, table: "usage_log", name: "seven_day_resets_at")
            let hasObservedAt = self.columnExists(db, table: "usage_log", name: "resets_at_observed_at")
            let fiveHourResetSelect = hasFiveHourExact
                ? "COALESCE(u.five_hour_resets_at, hs.resets_at)" : "hs.resets_at"
            let sevenDayResetSelect = hasSevenDayExact
                ? "COALESCE(u.seven_day_resets_at, ws.resets_at)" : "ws.resets_at"
            let fiveHourObservedAtSelect = hasFiveHourExact && hasObservedAt
                ? "CASE WHEN u.five_hour_resets_at IS NOT NULL THEN u.resets_at_observed_at END" : "NULL"
            let sevenDayObservedAtSelect = hasSevenDayExact && hasObservedAt
                ? "CASE WHEN u.seven_day_resets_at IS NOT NULL THEN u.resets_at_observed_at END" : "NULL"
            var sql = """
                SELECT u.timestamp, u.hourly_percent, u.weekly_percent,
                       \(fiveHourResetSelect), \(sevenDayResetSelect),
                       \(fiveHourObservedAtSelect), \(sevenDayObservedAtSelect)
                FROM usage_log u
                LEFT JOIN hourly_sessions hs ON u.hourly_session_id = hs.id
                LEFT JOIN weekly_sessions ws ON u.weekly_session_id = ws.id
                """
            var bindings: [Int64] = []
            if let from = from, let to = to,
               let fromEpoch = Int64(from), let toEpoch = Int64(to) {
                sql += " WHERE u.timestamp >= ? AND u.timestamp <= ?"
                bindings = [fromEpoch, toEpoch]
            }
            sql += " ORDER BY u.timestamp ASC"

            return SQLiteHelper.withStatement(db: db, sql: sql) { stmt in
                for (i, value) in bindings.enumerated() {
                    sqlite3_bind_int64(stmt, Int32(i + 1), value)
                }

                var rows: [[String: Any?]] = []
                while sqlite3_step(stmt) == SQLITE_ROW {
                    rows.append([
                        "timestamp": SQLiteHelper.columnInt(stmt, 0),
                        "hourly_percent": SQLiteHelper.columnDouble(stmt, 1),
                        "weekly_percent": SQLiteHelper.columnDouble(stmt, 2),
                        "hourly_resets_at": self.columnNumber(stmt, 3),
                        "weekly_resets_at": self.columnNumber(stmt, 4),
                        "hourly_resets_at_observed_at": self.columnNumber(stmt, 5),
                        "weekly_resets_at_observed_at": self.columnNumber(stmt, 6),
                        // Kept for old consumers. Per-window keys above are authoritative.
                        "resets_at_observed_at": self.columnNumber(stmt, 5)
                            ?? self.columnNumber(stmt, 6),
                    ])
                }
                return serializeJSON(rows)
            } ?? fallback
        } ?? fallback
    }

    private func queryMetaJSON() -> Data? {
        let fallback = "{}".data(using: .utf8)
        return SQLiteHelper.withDatabase(path: usageDbPath, flags: SQLITE_OPEN_READONLY) { db -> Data? in
            guard self.tableExists(db, name: "usage_log") else { return fallback }
            var result: [String: Any] = [:]
            var hasUsageData = false
            let hasSevenDayExact = self.columnExists(db, table: "usage_log", name: "seven_day_resets_at")
            let hasObservedAt = self.columnExists(db, table: "usage_log", name: "resets_at_observed_at")
            let latestSevenDayResetSelect = hasSevenDayExact
                ? "COALESCE((SELECT u2.seven_day_resets_at FROM usage_log u2 WHERE u2.seven_day_resets_at IS NOT NULL ORDER BY u2.timestamp DESC, u2.id DESC LIMIT 1), MAX(ws.resets_at))"
                : "MAX(ws.resets_at)"
            let latestSevenDayObservedAtSelect = hasSevenDayExact && hasObservedAt
                ? "(SELECT u2.resets_at_observed_at FROM usage_log u2 WHERE u2.seven_day_resets_at IS NOT NULL ORDER BY u2.timestamp DESC, u2.id DESC LIMIT 1)"
                : "NULL"

            // Aggregate meta (timestamps)
            SQLiteHelper.withStatement(db: db, sql: """
                SELECT \(latestSevenDayResetSelect), \(latestSevenDayObservedAtSelect),
                       MAX(u.timestamp), MIN(u.timestamp)
                FROM usage_log u
                LEFT JOIN weekly_sessions ws ON u.weekly_session_id = ws.id
                """) { stmt in
                guard sqlite3_step(stmt) == SQLITE_ROW else { return }
                guard SQLiteHelper.columnInt(stmt, 2) != nil ||
                      SQLiteHelper.columnInt(stmt, 3) != nil else { return }
                hasUsageData = true
                result["latestSevenDayResetsAt"] = self.columnNumber(stmt, 0) ?? NSNull()
                result["latestSevenDayResetsAtObservedAt"] = self.columnNumber(stmt, 1) ?? NSNull()
                result["latestTimestamp"] = SQLiteHelper.columnInt(stmt, 2) ?? NSNull()
                result["oldestTimestamp"] = SQLiteHelper.columnInt(stmt, 3) ?? NSNull()
            }

            // Session lists for session-based navigation. `started_at` is the
            // earliest usage_log timestamp tied to the session — the actual
            // session start, not `resets_at - 7d`. Sessions are not always
            // exactly 7 days, so the JS side uses started_at to draw the
            // navigation slot range correctly.
            let sessionQueries: [(String, String, String, String)] = [
                ("weeklySessions", "weekly_sessions", "weekly_session_id", "seven_day_resets_at"),
                ("hourlySessions", "hourly_sessions", "hourly_session_id", "five_hour_resets_at"),
            ]
            for (key, table, fkColumn, exactColumn) in sessionQueries {
                guard self.tableExists(db, name: table) else { continue }
                let hasExact = self.columnExists(db, table: "usage_log", name: exactColumn)
                let exactResetSelect = hasExact
                    ? "COALESCE((SELECT u2.\(exactColumn) FROM usage_log u2 WHERE u2.\(fkColumn) = s.id AND u2.\(exactColumn) IS NOT NULL ORDER BY u2.timestamp DESC, u2.id DESC LIMIT 1), s.resets_at)"
                    : "s.resets_at"
                let observedAtSelect = hasExact && hasObservedAt
                    ? "(SELECT u2.resets_at_observed_at FROM usage_log u2 WHERE u2.\(fkColumn) = s.id AND u2.\(exactColumn) IS NOT NULL ORDER BY u2.timestamp DESC, u2.id DESC LIMIT 1)"
                    : "NULL"
                let sql = """
                    SELECT s.id, \(exactResetSelect) AS resets_at,
                           s.resets_at AS normalized_resets_at,
                           MIN(u.timestamp) AS started_at,
                           \(observedAtSelect) AS resets_at_observed_at
                    FROM \(table) s
                    LEFT JOIN usage_log u ON u.\(fkColumn) = s.id
                    GROUP BY s.id, s.resets_at
                    ORDER BY s.resets_at ASC
                    """
                SQLiteHelper.withStatement(db: db, sql: sql) { stmt in
                    var sessions: [[String: Any]] = []
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        var session: [String: Any] = [:]
                        if let id = SQLiteHelper.columnInt(stmt, 0) { session["id"] = id }
                        if let ra = self.columnNumber(stmt, 1) { session["resets_at"] = ra }
                        if let normalized = SQLiteHelper.columnInt(stmt, 2) {
                            session["normalized_resets_at"] = normalized
                        }
                        if let sa = SQLiteHelper.columnInt(stmt, 3) { session["started_at"] = sa }
                        if let observedAt = self.columnNumber(stmt, 4) {
                            session["resets_at_observed_at"] = observedAt
                        }
                        sessions.append(session)
                    }
                    if hasUsageData || !sessions.isEmpty {
                        result[key] = sessions
                    }
                }
            }

            if result.isEmpty { return fallback }
            result["settings"] = settingsProvider()
            return try? JSONSerialization.data(withJSONObject: result)
        } ?? fallback
    }

    // MARK: - Helpers

    private func tableExists(_ db: OpaquePointer, name: String) -> Bool {
        SQLiteHelper.withStatement(
            db: db,
            sql: "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1"
        ) { stmt in
            SQLiteHelper.bindText(stmt, 1, name)
            return sqlite3_step(stmt) == SQLITE_ROW
        } ?? false
    }

    private func columnExists(_ db: OpaquePointer, table: String, name: String) -> Bool {
        SQLiteHelper.withStatement(db: db, sql: "PRAGMA table_info(\(table))") { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let text = sqlite3_column_text(stmt, 1), String(cString: text) == name {
                    return true
                }
            }
            return false
        } ?? false
    }

    /// Preserve INTEGER legacy values and REAL exact values in JSON without rounding.
    private func columnNumber(_ stmt: OpaquePointer, _ index: Int32) -> Any? {
        switch sqlite3_column_type(stmt, index) {
        case SQLITE_INTEGER: return Int(sqlite3_column_int64(stmt, index))
        case SQLITE_FLOAT: return sqlite3_column_double(stmt, index)
        default: return nil
        }
    }

    private func parseQueryParams(_ url: URL) -> [String: String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return [:] }
        var params: [String: String] = [:]
        for item in items {
            if let value = item.value {
                params[item.name] = value
            }
        }
        return params
    }

    private func serializeJSON(_ rows: [[String: Any?]]) -> Data? {
        // JSONSerialization doesn't handle Optional — convert to NSNull
        let cleaned = rows.map { row in
            row.mapValues { $0 ?? NSNull() }
        }
        return try? JSONSerialization.data(withJSONObject: cleaned)
    }

    private func serve(_ task: WKURLSchemeTask, url: URL, data: Data?, mime: String) {
        guard let data = data else {
            fail(task, code: 500, message: "Failed to generate response")
            return
        }
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mime,
                "Content-Length": "\(data.count)",
                "Access-Control-Allow-Origin": "*",
            ]
        )!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private func fail(_ task: WKURLSchemeTask, code: Int, message: String) {
        let response = HTTPURLResponse(
            url: task.request.url ?? URL(string: "cut://error")!,
            statusCode: code, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/plain"]
        )!
        task.didReceive(response)
        task.didReceive(message.data(using: .utf8)!)
        task.didFinish()
    }
}
