// meta: created=2026-02-24 updated=2026-02-27 checked=never
// changed: 2026-02-27 JOIN query for normalized sessions, epoch timestamps, new JSON key names
import Foundation
import SQLite3
import WebKit

/// Serves data to the Analysis WKWebView via a custom URL scheme (wcc://).
/// Queries SQLite databases on the Swift side and serves JSON to JavaScript.
/// Eliminates CDN dependency on sql.js/WASM.
final class AnalysisSchemeHandler: NSObject, WKURLSchemeHandler {

    static let scheme = "wcc"

    private let usageDbPath: String
    private let tokensDbPath: String
    private let htmlProvider: () -> String

    init(usageDbPath: String, tokensDbPath: String, htmlProvider: @escaping () -> String) {
        self.usageDbPath = usageDbPath
        self.tokensDbPath = tokensDbPath
        self.htmlProvider = htmlProvider
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
        case "tokens.json":
            serve(urlSchemeTask, url: url, data: queryTokensJSON(from: from, to: to), mime: "application/json")
        case "meta.json":
            serve(urlSchemeTask, url: url, data: queryMetaJSON(), mime: "application/json")
        default:
            fail(urlSchemeTask, code: 404, message: "Not found: \(path)")
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    // MARK: - SQLite Queries

    private func queryUsageJSON(from: String?, to: String?) -> Data? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(usageDbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return "[]".data(using: .utf8) }
        defer { sqlite3_close(db) }

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

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return "[]".data(using: .utf8) }
        defer { sqlite3_finalize(stmt) }

        for (i, value) in bindings.enumerated() {
            sqlite3_bind_int64(stmt, Int32(i + 1), value)
        }

        var rows: [[String: Any?]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append([
                "timestamp": columnInt(stmt, 0),
                "hourly_percent": columnDouble(stmt, 1),
                "weekly_percent": columnDouble(stmt, 2),
                "hourly_resets_at": columnInt(stmt, 3),
                "weekly_resets_at": columnInt(stmt, 4),
            ])
        }
        return serializeJSON(rows)
    }

    private func queryTokensJSON(from: String?, to: String?) -> Data? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(tokensDbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return "[]".data(using: .utf8) }
        defer { sqlite3_close(db) }

        var sql = """
            SELECT timestamp, model, input_tokens, output_tokens,
                   cache_read_tokens, cache_creation_tokens
            FROM token_records
            """
        var bindings: [String] = []
        if let from = from, let to = to {
            sql += " WHERE timestamp >= ? AND timestamp <= ?"
            bindings = [from, to]
        }
        sql += " ORDER BY timestamp ASC"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return "[]".data(using: .utf8) }
        defer { sqlite3_finalize(stmt) }

        for (i, value) in bindings.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), (value as NSString).utf8String, -1, nil)
        }

        var rows: [[String: Any?]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append([
                "timestamp": columnText(stmt, 0),
                "model": columnText(stmt, 1),
                "input_tokens": Int(sqlite3_column_int64(stmt, 2)),
                "output_tokens": Int(sqlite3_column_int64(stmt, 3)),
                "cache_read_tokens": Int(sqlite3_column_int64(stmt, 4)),
                "cache_creation_tokens": Int(sqlite3_column_int64(stmt, 5)),
            ])
        }
        return serializeJSON(rows)
    }

    private func queryMetaJSON() -> Data? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(usageDbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return "{}".data(using: .utf8) }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT MAX(ws.resets_at), MAX(u.timestamp), MIN(u.timestamp)
            FROM usage_log u
            LEFT JOIN weekly_sessions ws ON u.weekly_session_id = ws.id
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return "{}".data(using: .utf8) }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return "{}".data(using: .utf8) }

        let result: [String: Any?] = [
            "latestSevenDayResetsAt": columnInt(stmt, 0),
            "latestTimestamp": columnInt(stmt, 1),
            "oldestTimestamp": columnInt(stmt, 2),
        ]
        let cleaned = result.mapValues { $0 ?? NSNull() }
        return try? JSONSerialization.data(withJSONObject: cleaned)
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

    private func columnText(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
        guard sqlite3_column_type(stmt, idx) != SQLITE_NULL else { return nil }
        return String(cString: sqlite3_column_text(stmt, idx))
    }

    private func columnDouble(_ stmt: OpaquePointer?, _ idx: Int32) -> Double? {
        guard sqlite3_column_type(stmt, idx) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(stmt, idx)
    }

    private func columnInt(_ stmt: OpaquePointer?, _ idx: Int32) -> Int? {
        guard sqlite3_column_type(stmt, idx) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(stmt, idx))
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
            url: task.request.url ?? URL(string: "wcc://error")!,
            statusCode: code, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/plain"]
        )!
        task.didReceive(response)
        task.didReceive(message.data(using: .utf8)!)
        task.didFinish()
    }
}
