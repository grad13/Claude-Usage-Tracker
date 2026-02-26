// meta: created=2026-02-24 updated=2026-02-26 checked=never
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

        switch path {
        case "analysis.html":
            serve(urlSchemeTask, url: url, data: htmlProvider().data(using: .utf8), mime: "text/html")
        case "usage.json":
            serve(urlSchemeTask, url: url, data: queryUsageJSON(), mime: "application/json")
        case "tokens.json":
            serve(urlSchemeTask, url: url, data: queryTokensJSON(), mime: "application/json")
        default:
            fail(urlSchemeTask, code: 404, message: "Not found: \(path)")
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    // MARK: - SQLite Queries

    private func queryUsageJSON() -> Data? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(usageDbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return "[]".data(using: .utf8) }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT timestamp, five_hour_percent, seven_day_percent,
                   five_hour_resets_at, seven_day_resets_at
            FROM usage_log ORDER BY timestamp ASC
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return "[]".data(using: .utf8) }
        defer { sqlite3_finalize(stmt) }

        var rows: [[String: Any?]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let timestamp = columnText(stmt, 0)
            let fiveH = columnDouble(stmt, 1)
            let sevenD = columnDouble(stmt, 2)
            let fiveHResets = columnText(stmt, 3)
            let sevenDResets = columnText(stmt, 4)
            rows.append([
                "timestamp": timestamp,
                "five_hour_percent": fiveH,
                "seven_day_percent": sevenD,
                "five_hour_resets_at": fiveHResets,
                "seven_day_resets_at": sevenDResets,
            ])
        }
        return serializeJSON(rows)
    }

    private func queryTokensJSON() -> Data? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(tokensDbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return "[]".data(using: .utf8) }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT timestamp, model, input_tokens, output_tokens,
                   cache_read_tokens, cache_creation_tokens
            FROM token_records ORDER BY timestamp ASC
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return "[]".data(using: .utf8) }
        defer { sqlite3_finalize(stmt) }

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

    // MARK: - Helpers

    private func columnText(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
        guard sqlite3_column_type(stmt, idx) != SQLITE_NULL else { return nil }
        return String(cString: sqlite3_column_text(stmt, idx))
    }

    private func columnDouble(_ stmt: OpaquePointer?, _ idx: Int32) -> Double? {
        guard sqlite3_column_type(stmt, idx) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(stmt, idx)
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
