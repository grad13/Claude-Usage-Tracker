import XCTest
import WebKit
import SQLite3
@testable import ClaudeUsageTracker

// MARK: - AnalysisSchemeHandler Tests

final class AnalysisSchemeHandlerTests: XCTestCase {

    private var handler: AnalysisSchemeHandler!
    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalysisSchemeHandlerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        // Create real SQLite databases with normalized 3-table schema
        let usageDbPath = tmpDir.appendingPathComponent("usage.db").path
        let tokensDbPath = tmpDir.appendingPathComponent("tokens.db").path
        createDb(at: usageDbPath, sql: """
            CREATE TABLE hourly_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                resets_at INTEGER NOT NULL UNIQUE
            );
            CREATE TABLE weekly_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                resets_at INTEGER NOT NULL UNIQUE
            );
            CREATE TABLE usage_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp INTEGER NOT NULL,
                hourly_percent REAL,
                weekly_percent REAL,
                hourly_session_id INTEGER REFERENCES hourly_sessions(id),
                weekly_session_id INTEGER REFERENCES weekly_sessions(id),
                CHECK (hourly_percent IS NOT NULL OR weekly_percent IS NOT NULL)
            );
            INSERT INTO hourly_sessions (resets_at) VALUES (1771945200);
            INSERT INTO weekly_sessions (resets_at) VALUES (1772532000);
            INSERT INTO usage_log (timestamp, hourly_percent, weekly_percent, hourly_session_id, weekly_session_id)
            VALUES (1771927200, 42.5, 15.0, 1, 1);
            """)
        createDb(at: tokensDbPath, sql: """
            CREATE TABLE token_records (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                request_id TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                model TEXT NOT NULL,
                speed TEXT NOT NULL DEFAULT 'standard',
                input_tokens INTEGER NOT NULL DEFAULT 0,
                output_tokens INTEGER NOT NULL DEFAULT 0,
                cache_read_tokens INTEGER NOT NULL DEFAULT 0,
                cache_creation_tokens INTEGER NOT NULL DEFAULT 0
            );
            INSERT INTO token_records (request_id, timestamp, model, input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens)
            VALUES ('req-1', '2026-02-24T10:00:00.000Z', 'claude-sonnet-4-20250514', 1000, 500, 200, 100);
            """)

        handler = AnalysisSchemeHandler(
            usageDbPath: usageDbPath,
            tokensDbPath: tokensDbPath,
            htmlProvider: { "<html>test</html>" }
        )
    }

    private func createDb(at path: String, sql: String) {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: - Scheme constant

    func testSchemeIsCut() {
        XCTAssertEqual(AnalysisSchemeHandler.scheme, "cut")
    }

    // MARK: - HTML serving

    func testStart_analysisHtml_servesHtmlContent() {
        let task = MockSchemeTask(url: URL(string: "cut://analysis.html")!)
        handler.webView(WKWebView(), start: task)

        XCTAssertNotNil(task.receivedResponse, "Should receive a response")
        XCTAssertNotNil(task.receivedData, "Should receive data")
        XCTAssertTrue(task.didFinishCalled, "Should call didFinish")

        let html = String(data: task.receivedData!, encoding: .utf8)
        XCTAssertEqual(html, "<html>test</html>")

        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertNotNil(httpResponse, "Should be HTTPURLResponse")
        XCTAssertEqual(httpResponse?.statusCode, 200)
        XCTAssertEqual(httpResponse?.value(forHTTPHeaderField: "Content-Type"), "text/html")
    }

    func testStart_analysisHtml_usesDynamicHtmlProvider() {
        var callCount = 0
        let dynamicHandler = AnalysisSchemeHandler(
            usageDbPath: tmpDir.appendingPathComponent("usage.db").path,
            tokensDbPath: tmpDir.appendingPathComponent("tokens.db").path,
            htmlProvider: {
                callCount += 1
                return "<html>call-\(callCount)</html>"
            }
        )
        let task1 = MockSchemeTask(url: URL(string: "cut://analysis.html")!)
        dynamicHandler.webView(WKWebView(), start: task1)
        XCTAssertEqual(String(data: task1.receivedData!, encoding: .utf8), "<html>call-1</html>")

        let task2 = MockSchemeTask(url: URL(string: "cut://analysis.html")!)
        dynamicHandler.webView(WKWebView(), start: task2)
        XCTAssertEqual(String(data: task2.receivedData!, encoding: .utf8), "<html>call-2</html>")
    }

    // MARK: - JSON serving

    func testStart_usageJson_servesJSON() {
        let task = MockSchemeTask(url: URL(string: "cut://usage.json")!)
        handler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled)
        let json = try! JSONSerialization.jsonObject(with: task.receivedData!) as! [[String: Any]]
        XCTAssertEqual(json.count, 1)
        XCTAssertEqual(json[0]["hourly_percent"] as? Double, 42.5)

        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.statusCode, 200)
        XCTAssertEqual(httpResponse?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testStart_tokensJson_servesJSON() {
        let task = MockSchemeTask(url: URL(string: "cut://tokens.json")!)
        handler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled)
        let json = try! JSONSerialization.jsonObject(with: task.receivedData!) as! [[String: Any]]
        XCTAssertEqual(json.count, 1)
        XCTAssertEqual(json[0]["model"] as? String, "claude-sonnet-4-20250514")

        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.statusCode, 200)
        XCTAssertEqual(httpResponse?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    // MARK: - HTTP status codes (200 for all valid paths)

    func testStart_successResponses_areHTTPWith200() {
        for path in ["analysis.html", "usage.json", "tokens.json"] {
            let task = MockSchemeTask(url: URL(string: "cut://\(path)")!)
            handler.webView(WKWebView(), start: task)
            let httpResponse = task.receivedResponse as? HTTPURLResponse
            XCTAssertNotNil(httpResponse, "\(path): Should be HTTPURLResponse")
            XCTAssertEqual(httpResponse?.statusCode, 200,
                           "\(path): Status must be 200 so fetch().response.ok is true")
        }
    }

    // MARK: - CORS headers

    func testStart_successResponses_haveCORSHeader() {
        for path in ["analysis.html", "usage.json", "tokens.json"] {
            let task = MockSchemeTask(url: URL(string: "cut://\(path)")!)
            handler.webView(WKWebView(), start: task)
            let httpResponse = task.receivedResponse as? HTTPURLResponse
            XCTAssertEqual(httpResponse?.value(forHTTPHeaderField: "Access-Control-Allow-Origin"), "*",
                           "\(path): CORS header must be * for cross-origin fetch in WKWebView")
        }
    }

    // MARK: - Content-Length header

    func testStart_contentLengthMatchesActualData() {
        for path in ["analysis.html", "usage.json", "tokens.json"] {
            let task = MockSchemeTask(url: URL(string: "cut://\(path)")!)
            handler.webView(WKWebView(), start: task)
            let httpResponse = task.receivedResponse as? HTTPURLResponse
            let declaredLength = httpResponse?.value(forHTTPHeaderField: "Content-Length")
            XCTAssertNotNil(declaredLength, "\(path): Content-Length header must be present")
            XCTAssertEqual(Int(declaredLength!), task.receivedData!.count,
                           "\(path): Content-Length must match actual data size")
        }
    }

    // MARK: - MIME types

    func testMimeType_html() {
        let task = MockSchemeTask(url: URL(string: "cut://analysis.html")!)
        handler.webView(WKWebView(), start: task)
        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.value(forHTTPHeaderField: "Content-Type"), "text/html")
    }

    func testMimeType_json_isApplicationJson() {
        let task = MockSchemeTask(url: URL(string: "cut://usage.json")!)
        handler.webView(WKWebView(), start: task)
        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    // MARK: - didFinish called on every response

    func testStart_allPaths_callDidFinish() {
        for path in ["analysis.html", "usage.db", "tokens.db", "nonexistent.txt"] {
            let task = MockSchemeTask(url: URL(string: "cut://\(path)")!)
            handler.webView(WKWebView(), start: task)
            XCTAssertTrue(task.didFinishCalled,
                          "\(path): didFinish must always be called to avoid WKWebView leak")
        }
    }

    // MARK: - 404 for unknown paths

    func testStart_unknownPath_returns404() {
        let task = MockSchemeTask(url: URL(string: "cut://nonexistent.txt")!)
        handler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled)
        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertNotNil(httpResponse)
        XCTAssertEqual(httpResponse?.statusCode, 404)
    }

    func testStart_unknownPath_404HasTextPlainContentType() {
        let task = MockSchemeTask(url: URL(string: "cut://nonexistent.txt")!)
        handler.webView(WKWebView(), start: task)

        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.value(forHTTPHeaderField: "Content-Type"), "text/plain")
    }

    func testStart_unknownPath_404BodyContainsErrorMessage() {
        let task = MockSchemeTask(url: URL(string: "cut://nonexistent.txt")!)
        handler.webView(WKWebView(), start: task)

        let body = String(data: task.receivedData ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("Not found"),
                      "404 body should contain 'Not found' message")
    }

    // MARK: - Missing DB files (JSON endpoints return 200 + empty array)

    func testStart_missingUsageDb_returnsEmptyJsonArray() {
        let badHandler = AnalysisSchemeHandler(
            usageDbPath: "/nonexistent/path/usage.db",
            tokensDbPath: "/nonexistent/path/tokens.db",
            htmlProvider: { "<html>test</html>" }
        )
        let task = MockSchemeTask(url: URL(string: "cut://usage.json")!)
        badHandler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled)
        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.statusCode, 200)
        XCTAssertEqual(String(data: task.receivedData!, encoding: .utf8), "[]")
    }

    func testStart_missingTokensDb_returnsEmptyJsonArray() {
        let badHandler = AnalysisSchemeHandler(
            usageDbPath: "/nonexistent/path/usage.db",
            tokensDbPath: "/nonexistent/path/tokens.db",
            htmlProvider: { "<html>test</html>" }
        )
        let task = MockSchemeTask(url: URL(string: "cut://tokens.json")!)
        badHandler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled)
        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.statusCode, 200)
        XCTAssertEqual(String(data: task.receivedData!, encoding: .utf8), "[]")
    }

    func testStart_missingDb_htmlStillWorks() {
        // Even if DB files are missing, HTML should still serve
        let badHandler = AnalysisSchemeHandler(
            usageDbPath: "/nonexistent/path/usage.db",
            tokensDbPath: "/nonexistent/path/tokens.db",
            htmlProvider: { "<html>still works</html>" }
        )
        let task = MockSchemeTask(url: URL(string: "cut://analysis.html")!)
        badHandler.webView(WKWebView(), start: task)

        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.statusCode, 200)
        XCTAssertEqual(String(data: task.receivedData!, encoding: .utf8), "<html>still works</html>")
    }

    // MARK: - Stop handler doesn't crash

    func testStop_doesNotCrash() {
        let task = MockSchemeTask(url: URL(string: "cut://analysis.html")!)
        // Calling stop should be a no-op, not crash
        handler.webView(WKWebView(), stop: task)
    }

    // MARK: - Response URL matches request URL

    func testStart_responseURL_matchesRequestURL() {
        for path in ["analysis.html", "usage.json", "tokens.json"] {
            let requestURL = URL(string: "cut://\(path)")!
            let task = MockSchemeTask(url: requestURL)
            handler.webView(WKWebView(), start: task)
            let httpResponse = task.receivedResponse as? HTTPURLResponse
            XCTAssertEqual(httpResponse?.url, requestURL,
                           "\(path): response URL must match request URL for fetch() to work")
        }
    }
}

// MARK: - Real SQLite DB Integration Tests

/// Tests AnalysisSchemeHandler with actual SQLite databases (not dummy strings).
/// Verifies the full data flow: create SQLite DB → handler serves it → bytes are valid SQLite.
final class AnalysisSchemeHandlerSQLiteTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalysisSQLiteTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: - JSON data correctness

    func testUsageJson_returnsCorrectData() {
        let usagePath = tmpDir.appendingPathComponent("usage.db").path
        let tokensPath = tmpDir.appendingPathComponent("tokens.db").path
        AnalysisTestDB.createUsageDb(at: usagePath, rows: [
            (1771927200, 25.5, 12.3),
            (1771927500, 80.0, 45.0),
        ])
        AnalysisTestDB.createTokensDb(at: tokensPath, rows: [])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath, tokensDbPath: tokensPath,
            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "cut://usage.json")!)
        handler.webView(WKWebView(), start: task)

        let json = try! JSONSerialization.jsonObject(with: task.receivedData!) as! [[String: Any]]
        XCTAssertEqual(json.count, 2)
        XCTAssertEqual(json[0]["timestamp"] as? Int, 1771927200)
        XCTAssertEqual(json[0]["hourly_percent"] as! Double, 25.5, accuracy: 0.01)
        XCTAssertEqual(json[0]["weekly_percent"] as! Double, 12.3, accuracy: 0.01)
        XCTAssertEqual(json[1]["hourly_percent"] as! Double, 80.0, accuracy: 0.01)
        XCTAssertEqual(json[1]["weekly_percent"] as! Double, 45.0, accuracy: 0.01)
    }

    func testTokensJson_returnsCorrectData() {
        let usagePath = tmpDir.appendingPathComponent("usage.db").path
        let tokensPath = tmpDir.appendingPathComponent("tokens.db").path
        AnalysisTestDB.createUsageDb(at: usagePath, rows: [])
        AnalysisTestDB.createTokensDb(at: tokensPath, rows: [
            ("req-1", "2026-02-24T10:00:00.000Z", "claude-sonnet-4-20250514", 1000, 500, 200, 100),
            ("req-2", "2026-02-24T10:01:00.000Z", "claude-opus-4-20250514", 2000, 800, 0, 0),
        ])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath, tokensDbPath: tokensPath,
            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "cut://tokens.json")!)
        handler.webView(WKWebView(), start: task)

        let json = try! JSONSerialization.jsonObject(with: task.receivedData!) as! [[String: Any]]
        XCTAssertEqual(json.count, 2)
        XCTAssertEqual(json[0]["model"] as? String, "claude-sonnet-4-20250514")
        XCTAssertEqual(json[0]["input_tokens"] as? Int, 1000)
        XCTAssertEqual(json[0]["output_tokens"] as? Int, 500)
        XCTAssertEqual(json[0]["cache_read_tokens"] as? Int, 200)
        XCTAssertEqual(json[0]["cache_creation_tokens"] as? Int, 100)
        XCTAssertEqual(json[1]["model"] as? String, "claude-opus-4-20250514")
        XCTAssertEqual(json[1]["input_tokens"] as? Int, 2000)
        XCTAssertEqual(json[1]["output_tokens"] as? Int, 800)
    }

    // MARK: - Empty DB returns empty JSON array

    func testEmptyDb_returnsEmptyJsonArray() {
        let usagePath = tmpDir.appendingPathComponent("usage.db").path
        let tokensPath = tmpDir.appendingPathComponent("tokens.db").path
        AnalysisTestDB.createUsageDb(at: usagePath, rows: [])
        AnalysisTestDB.createTokensDb(at: tokensPath, rows: [])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath, tokensDbPath: tokensPath,
            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "cut://usage.json")!)
        handler.webView(WKWebView(), start: task)

        let json = try! JSONSerialization.jsonObject(with: task.receivedData!) as! [Any]
        XCTAssertEqual(json.count, 0)
    }

    // MARK: - Integration: real HTML template served correctly

    func testHandler_servesRealHtmlTemplate() {
        let usagePath = tmpDir.appendingPathComponent("usage.db").path
        let tokensPath = tmpDir.appendingPathComponent("tokens.db").path
        AnalysisTestDB.createUsageDb(at: usagePath, rows: [])
        AnalysisTestDB.createTokensDb(at: tokensPath, rows: [])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath, tokensDbPath: tokensPath,
            htmlProvider: { AnalysisExporter.htmlTemplate }
        )
        let task = MockSchemeTask(url: URL(string: "cut://analysis.html")!)
        handler.webView(WKWebView(), start: task)

        let html = String(data: task.receivedData!, encoding: .utf8)!
        // The served HTML must be the full template, not truncated or corrupted
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(html.hasSuffix("</html>\n") || html.hasSuffix("</html>"))
        XCTAssertTrue(html.contains("cut://usage.json"))
        XCTAssertTrue(html.contains("cut://tokens.json"))
        XCTAssertTrue(html.contains("function renderMain"))

        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.statusCode, 200)
        // Content-Length must match the full template size
        let expectedSize = AnalysisExporter.htmlTemplate.data(using: .utf8)!.count
        XCTAssertEqual(task.receivedData!.count, expectedSize,
                       "Served HTML size must match template size — truncation means broken page")
    }

    // MARK: - Large dataset JSON handling

    func testUsageJson_largeDataset_returnsAllRows() {
        let usagePath = tmpDir.appendingPathComponent("usage.db").path
        let tokensPath = tmpDir.appendingPathComponent("tokens.db").path

        // Create 1000 rows — similar to real production data (5-min intervals)
        let baseEpoch = 1771927200
        var rows: [(Int, Double, Double)] = []
        for i in 0..<1000 {
            rows.append((baseEpoch + i * 300, Double(i % 100), Double(i % 50)))
        }
        AnalysisTestDB.createUsageDb(at: usagePath, rows: rows)
        AnalysisTestDB.createTokensDb(at: tokensPath, rows: [])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath, tokensDbPath: tokensPath,
            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "cut://usage.json")!)
        handler.webView(WKWebView(), start: task)

        let json = try! JSONSerialization.jsonObject(with: task.receivedData!) as! [[String: Any]]
        XCTAssertEqual(json.count, 1000,
                       "All 1000 rows must be present in JSON response")
        // Spot-check first and last values
        XCTAssertEqual(json[0]["hourly_percent"] as! Double, 0.0, accuracy: 0.01)
        XCTAssertEqual(json[999]["hourly_percent"] as! Double, 99.0, accuracy: 0.01)
    }
}
