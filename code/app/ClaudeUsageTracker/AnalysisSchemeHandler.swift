// meta: updated=2026-03-16 06:52 checked=2026-03-03 00:00
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
            var sql = """
                SELECT u.timestamp, u.hourly_percent, u.weekly_percent,
                       hs.resets_at AS hourly_resets_at,
                       ws.resets_at AS weekly_resets_at
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
                        "hourly_resets_at": SQLiteHelper.columnInt(stmt, 3),
                        "weekly_resets_at": SQLiteHelper.columnInt(stmt, 4),
                    ])
                }
                return serializeJSON(rows)
            } ?? fallback
        } ?? fallback
    }

    private func queryMetaJSON() -> Data? {
        let fallback = "{}".data(using: .utf8)
        return SQLiteHelper.withDatabase(path: usageDbPath, flags: SQLITE_OPEN_READONLY) { db -> Data? in
            var result: [String: Any] = [:]
            var hasUsageData = false

            // Aggregate meta (timestamps)
            SQLiteHelper.withStatement(db: db, sql: """
                SELECT MAX(ws.resets_at), MAX(u.timestamp), MIN(u.timestamp)
                FROM usage_log u
                LEFT JOIN weekly_sessions ws ON u.weekly_session_id = ws.id
                """) { stmt in
                guard sqlite3_step(stmt) == SQLITE_ROW else { return }
                guard SQLiteHelper.columnInt(stmt, 1) != nil ||
                      SQLiteHelper.columnInt(stmt, 2) != nil else { return }
                hasUsageData = true
                result["latestSevenDayResetsAt"] = SQLiteHelper.columnInt(stmt, 0) ?? NSNull()
                result["latestTimestamp"] = SQLiteHelper.columnInt(stmt, 1) ?? NSNull()
                result["oldestTimestamp"] = SQLiteHelper.columnInt(stmt, 2) ?? NSNull()
            }

            // Session lists for session-based navigation
            for (key, table) in [("weeklySessions", "weekly_sessions"), ("hourlySessions", "hourly_sessions")] {
                SQLiteHelper.withStatement(db: db, sql:
                    "SELECT id, resets_at FROM \(table) ORDER BY resets_at ASC"
                ) { stmt in
                    var sessions: [[String: Any]] = []
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        var session: [String: Any] = [:]
                        if let id = SQLiteHelper.columnInt(stmt, 0) { session["id"] = id }
                        if let ra = SQLiteHelper.columnInt(stmt, 1) { session["resets_at"] = ra }
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
