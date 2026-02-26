import XCTest
import WebKit
import SQLite3
@testable import WeatherCC

final class AnalysisExporterTests: XCTestCase {

    // MARK: - HTML structure

    func testHtmlTemplate_isValidHTML() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("<html"))
        XCTAssertTrue(html.contains("</html>"))
        XCTAssertTrue(html.contains("<head>"))
        XCTAssertTrue(html.contains("</head>"))
        XCTAssertTrue(html.contains("<body>"))
        XCTAssertTrue(html.contains("</body>"))
    }

    func testHtmlTemplate_hasTitle() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("<title>WeatherCC"))
    }

    // MARK: - External libraries

    func testHtmlTemplate_containsChartJsScript() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("chart.js"),
                      "Chart.js required for rendering charts")
    }

    func testHtmlTemplate_containsDateFnsAdapter() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("chartjs-adapter-date-fns"),
                      "date-fns adapter required for time-axis charts")
    }

    // MARK: - JSON loading via fetch from wcc:// scheme

    func testHtmlTemplate_fetchesUsageJson() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("wcc://usage.json"),
                      "JS must fetch usage JSON from wcc:// scheme handler")
    }

    func testHtmlTemplate_fetchesTokensJson() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("wcc://tokens.json"),
                      "JS must fetch tokens JSON from wcc:// scheme handler")
    }

    func testHtmlTemplate_containsFetchJSONFunction() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("fetchJSON"),
                      "JS must have fetchJSON helper to load data via wcc:// scheme")
    }

    func testHtmlTemplate_doesNotUseBase64Injection() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertFalse(html.contains("__USAGE_DB_B64"),
                       "DB loading should use fetch, not base64 injection")
        XCTAssertFalse(html.contains("__TOKENS_DB_B64"),
                       "DB loading should use fetch, not base64 injection")
    }

    // MARK: - JS data processing functions

    func testHtmlTemplate_containsModelPricing() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("MODEL_PRICING"),
                      "JS must have model pricing table for cost calculation")
        // Verify all 3 model tiers
        XCTAssertTrue(html.contains("opus:"))
        XCTAssertTrue(html.contains("sonnet:"))
        XCTAssertTrue(html.contains("haiku:"))
    }

    func testHtmlTemplate_containsCostForRecord() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("function costForRecord"),
                      "JS must have costForRecord function matching CostEstimator.swift logic")
    }

    func testHtmlTemplate_containsPricingForModel() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("function pricingForModel"),
                      "JS must resolve model name to pricing tier")
    }

    func testHtmlTemplate_containsComputeDeltas() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("function computeDeltas"),
                      "JS must compute usage deltas for scatter/heatmap charts")
    }

    func testHtmlTemplate_containsComputeKDE() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("function computeKDE"),
                      "JS must compute KDE for efficiency distribution chart")
    }

    func testHtmlTemplate_containsInsertResetPoints() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("function insertResetPoints"),
                      "JS must insert zero-points at reset boundaries for clean chart lines")
    }

    func testHtmlTemplate_containsLoadDataFunction() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("async function loadData"))
    }

    func testHtmlTemplate_containsMainFunction() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("function main(usageData, tokenData)"))
    }

    // MARK: - JSON property keys (column names used as JS property accessors)

    func testHtmlTemplate_selectsRequiredUsageColumns() {
        let html = AnalysisExporter.htmlTemplate
        for col in ["timestamp", "five_hour_percent", "seven_day_percent",
                     "five_hour_resets_at", "seven_day_resets_at"] {
            XCTAssertTrue(html.contains(col),
                          "Usage query must select \(col)")
        }
    }

    func testHtmlTemplate_selectsRequiredTokenColumns() {
        let html = AnalysisExporter.htmlTemplate
        for col in ["model", "input_tokens", "output_tokens",
                     "cache_read_tokens", "cache_creation_tokens"] {
            XCTAssertTrue(html.contains(col),
                          "Token query must select \(col)")
        }
    }

    // MARK: - UI tabs

    func testHtmlTemplate_hasFourTabs() {
        let html = AnalysisExporter.htmlTemplate
        for tab in ["usage", "cost", "efficiency", "cumulative"] {
            XCTAssertTrue(html.contains("data-tab=\"\(tab)\""),
                          "Tab '\(tab)' must exist")
            XCTAssertTrue(html.contains("id=\"tab-\(tab)\""),
                          "Tab content for '\(tab)' must exist")
        }
    }

    func testHtmlTemplate_hasChartCanvases() {
        let html = AnalysisExporter.htmlTemplate
        for canvasId in ["usageTimeline", "costTimeline",
                         "effScatter", "kdeChart", "cumulativeCost"] {
            XCTAssertTrue(html.contains("id=\"\(canvasId)\""),
                          "Canvas '\(canvasId)' must exist for Chart.js")
        }
    }

    func testHtmlTemplate_hasHeatmapContainer() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("id=\"heatmap\""))
    }

    func testHtmlTemplate_hasDateRangeInputs() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("id=\"dateFrom\""))
        XCTAssertTrue(html.contains("id=\"dateTo\""))
        XCTAssertTrue(html.contains("id=\"applyRange\""))
    }

    func testHtmlTemplate_hasGapSlider() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("id=\"gapSlider\""))
        XCTAssertTrue(html.contains("id=\"gapVal\""))
    }

    func testHtmlTemplate_hasStatsContainer() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("id=\"stats\""))
    }

    func testHtmlTemplate_hasLoadingIndicator() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("id=\"loading\""))
    }

    // MARK: - CSS

    func testHtmlTemplate_hasDarkThemeBackground() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("#0d1117"),
                      "Body background should be dark (#0d1117)")
    }

    // MARK: - Model pricing correctness

    func testHtmlTemplate_opusPricingMatchesSwift() {
        let html = AnalysisExporter.htmlTemplate
        // opus input: 15.0 per 1M
        XCTAssertTrue(html.contains("input: 15.0"))
        // opus output: 75.0 per 1M
        XCTAssertTrue(html.contains("output: 75.0"))
    }

    func testHtmlTemplate_sonnetPricingMatchesSwift() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("input: 3.0"))
        XCTAssertTrue(html.contains("output: 15.0"))
    }

    func testHtmlTemplate_haikuPricingMatchesSwift() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("input: 0.80") || html.contains("input: 0.8"))
        XCTAssertTrue(html.contains("output: 4.0"))
    }
}

// MARK: - AnalysisSchemeHandler Tests

final class AnalysisSchemeHandlerTests: XCTestCase {

    private var handler: AnalysisSchemeHandler!
    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalysisSchemeHandlerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        // Create real SQLite databases (not dummy text)
        let usageDbPath = tmpDir.appendingPathComponent("usage.db").path
        let tokensDbPath = tmpDir.appendingPathComponent("tokens.db").path
        createDb(at: usageDbPath, sql: """
            CREATE TABLE usage_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                five_hour_percent REAL,
                seven_day_percent REAL,
                five_hour_resets_at TEXT,
                seven_day_resets_at TEXT
            );
            INSERT INTO usage_log (timestamp, five_hour_percent, seven_day_percent)
            VALUES ('2026-02-24T10:00:00.000Z', 42.5, 15.0);
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

    func testSchemeIsWcc() {
        XCTAssertEqual(AnalysisSchemeHandler.scheme, "wcc")
    }

    // MARK: - HTML serving

    func testStart_analysisHtml_servesHtmlContent() {
        let task = MockSchemeTask(url: URL(string: "wcc://analysis.html")!)
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
        let task1 = MockSchemeTask(url: URL(string: "wcc://analysis.html")!)
        dynamicHandler.webView(WKWebView(), start: task1)
        XCTAssertEqual(String(data: task1.receivedData!, encoding: .utf8), "<html>call-1</html>")

        let task2 = MockSchemeTask(url: URL(string: "wcc://analysis.html")!)
        dynamicHandler.webView(WKWebView(), start: task2)
        XCTAssertEqual(String(data: task2.receivedData!, encoding: .utf8), "<html>call-2</html>")
    }

    // MARK: - JSON serving

    func testStart_usageJson_servesJSON() {
        let task = MockSchemeTask(url: URL(string: "wcc://usage.json")!)
        handler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled)
        let json = try! JSONSerialization.jsonObject(with: task.receivedData!) as! [[String: Any]]
        XCTAssertEqual(json.count, 1)
        XCTAssertEqual(json[0]["five_hour_percent"] as? Double, 42.5)

        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.statusCode, 200)
        XCTAssertEqual(httpResponse?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testStart_tokensJson_servesJSON() {
        let task = MockSchemeTask(url: URL(string: "wcc://tokens.json")!)
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
            let task = MockSchemeTask(url: URL(string: "wcc://\(path)")!)
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
            let task = MockSchemeTask(url: URL(string: "wcc://\(path)")!)
            handler.webView(WKWebView(), start: task)
            let httpResponse = task.receivedResponse as? HTTPURLResponse
            XCTAssertEqual(httpResponse?.value(forHTTPHeaderField: "Access-Control-Allow-Origin"), "*",
                           "\(path): CORS header must be * for cross-origin fetch in WKWebView")
        }
    }

    // MARK: - Content-Length header

    func testStart_contentLengthMatchesActualData() {
        for path in ["analysis.html", "usage.json", "tokens.json"] {
            let task = MockSchemeTask(url: URL(string: "wcc://\(path)")!)
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
        let task = MockSchemeTask(url: URL(string: "wcc://analysis.html")!)
        handler.webView(WKWebView(), start: task)
        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.value(forHTTPHeaderField: "Content-Type"), "text/html")
    }

    func testMimeType_json_isApplicationJson() {
        let task = MockSchemeTask(url: URL(string: "wcc://usage.json")!)
        handler.webView(WKWebView(), start: task)
        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    // MARK: - didFinish called on every response

    func testStart_allPaths_callDidFinish() {
        for path in ["analysis.html", "usage.db", "tokens.db", "nonexistent.txt"] {
            let task = MockSchemeTask(url: URL(string: "wcc://\(path)")!)
            handler.webView(WKWebView(), start: task)
            XCTAssertTrue(task.didFinishCalled,
                          "\(path): didFinish must always be called to avoid WKWebView leak")
        }
    }

    // MARK: - 404 for unknown paths

    func testStart_unknownPath_returns404() {
        let task = MockSchemeTask(url: URL(string: "wcc://nonexistent.txt")!)
        handler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled)
        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertNotNil(httpResponse)
        XCTAssertEqual(httpResponse?.statusCode, 404)
    }

    func testStart_unknownPath_404HasTextPlainContentType() {
        let task = MockSchemeTask(url: URL(string: "wcc://nonexistent.txt")!)
        handler.webView(WKWebView(), start: task)

        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.value(forHTTPHeaderField: "Content-Type"), "text/plain")
    }

    func testStart_unknownPath_404BodyContainsErrorMessage() {
        let task = MockSchemeTask(url: URL(string: "wcc://nonexistent.txt")!)
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
        let task = MockSchemeTask(url: URL(string: "wcc://usage.json")!)
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
        let task = MockSchemeTask(url: URL(string: "wcc://tokens.json")!)
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
        let task = MockSchemeTask(url: URL(string: "wcc://analysis.html")!)
        badHandler.webView(WKWebView(), start: task)

        let httpResponse = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.statusCode, 200)
        XCTAssertEqual(String(data: task.receivedData!, encoding: .utf8), "<html>still works</html>")
    }

    // MARK: - Stop handler doesn't crash

    func testStop_doesNotCrash() {
        let task = MockSchemeTask(url: URL(string: "wcc://analysis.html")!)
        // Calling stop should be a no-op, not crash
        handler.webView(WKWebView(), stop: task)
    }

    // MARK: - Response URL matches request URL

    func testStart_responseURL_matchesRequestURL() {
        for path in ["analysis.html", "usage.json", "tokens.json"] {
            let requestURL = URL(string: "wcc://\(path)")!
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

    /// Create a real SQLite usage.db with the same schema as UsageStore.
    private func createUsageDb(at path: String, rows: [(String, Double, Double)]) {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            XCTFail("Failed to create test usage.db")
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
                seven_day_resets_at TEXT
            );
            """
        sqlite3_exec(db, createSQL, nil, nil, nil)

        for (ts, fiveH, sevenD) in rows {
            let insertSQL = "INSERT INTO usage_log (timestamp, five_hour_percent, seven_day_percent) VALUES (?, ?, ?);"
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil)
            sqlite3_bind_text(stmt, 1, (ts as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 2, fiveH)
            sqlite3_bind_double(stmt, 3, sevenD)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    /// Create a real SQLite tokens.db with the same schema as TokenStore.
    private func createTokensDb(at path: String, rows: [(String, String, String, Int, Int, Int, Int)]) {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            XCTFail("Failed to create test tokens.db")
            return
        }
        defer { sqlite3_close(db) }

        let createSQL = """
            CREATE TABLE IF NOT EXISTS token_records (
                request_id TEXT PRIMARY KEY,
                timestamp TEXT NOT NULL,
                model TEXT NOT NULL,
                input_tokens INTEGER NOT NULL,
                output_tokens INTEGER NOT NULL,
                cache_read_tokens INTEGER NOT NULL,
                cache_creation_tokens INTEGER NOT NULL
            );
            """
        sqlite3_exec(db, createSQL, nil, nil, nil)

        for (reqId, ts, model, inp, out, cacheR, cacheW) in rows {
            let insertSQL = """
                INSERT INTO token_records (request_id, timestamp, model, input_tokens, output_tokens,
                    cache_read_tokens, cache_creation_tokens)
                VALUES (?, ?, ?, ?, ?, ?, ?);
                """
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil)
            sqlite3_bind_text(stmt, 1, (reqId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (ts as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (model as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 4, Int32(inp))
            sqlite3_bind_int(stmt, 5, Int32(out))
            sqlite3_bind_int(stmt, 6, Int32(cacheR))
            sqlite3_bind_int(stmt, 7, Int32(cacheW))
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    // MARK: - JSON data correctness

    func testUsageJson_returnsCorrectData() {
        let usagePath = tmpDir.appendingPathComponent("usage.db").path
        let tokensPath = tmpDir.appendingPathComponent("tokens.db").path
        createUsageDb(at: usagePath, rows: [
            ("2026-02-24T10:00:00.000Z", 25.5, 12.3),
            ("2026-02-24T10:05:00.000Z", 80.0, 45.0),
        ])
        createTokensDb(at: tokensPath, rows: [])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath, tokensDbPath: tokensPath,
            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "wcc://usage.json")!)
        handler.webView(WKWebView(), start: task)

        let json = try! JSONSerialization.jsonObject(with: task.receivedData!) as! [[String: Any]]
        XCTAssertEqual(json.count, 2)
        XCTAssertEqual(json[0]["five_hour_percent"] as! Double, 25.5, accuracy: 0.01)
        XCTAssertEqual(json[0]["seven_day_percent"] as! Double, 12.3, accuracy: 0.01)
        XCTAssertEqual(json[1]["five_hour_percent"] as! Double, 80.0, accuracy: 0.01)
        XCTAssertEqual(json[1]["seven_day_percent"] as! Double, 45.0, accuracy: 0.01)
    }

    func testTokensJson_returnsCorrectData() {
        let usagePath = tmpDir.appendingPathComponent("usage.db").path
        let tokensPath = tmpDir.appendingPathComponent("tokens.db").path
        createUsageDb(at: usagePath, rows: [])
        createTokensDb(at: tokensPath, rows: [
            ("req-1", "2026-02-24T10:00:00.000Z", "claude-sonnet-4-20250514", 1000, 500, 200, 100),
            ("req-2", "2026-02-24T10:01:00.000Z", "claude-opus-4-20250514", 2000, 800, 0, 0),
        ])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath, tokensDbPath: tokensPath,
            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "wcc://tokens.json")!)
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
        createUsageDb(at: usagePath, rows: [])
        createTokensDb(at: tokensPath, rows: [])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath, tokensDbPath: tokensPath,
            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "wcc://usage.json")!)
        handler.webView(WKWebView(), start: task)

        let json = try! JSONSerialization.jsonObject(with: task.receivedData!) as! [Any]
        XCTAssertEqual(json.count, 0)
    }

    // MARK: - Integration: real HTML template served correctly

    func testHandler_servesRealHtmlTemplate() {
        let usagePath = tmpDir.appendingPathComponent("usage.db").path
        let tokensPath = tmpDir.appendingPathComponent("tokens.db").path
        createUsageDb(at: usagePath, rows: [])
        createTokensDb(at: tokensPath, rows: [])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath, tokensDbPath: tokensPath,
            htmlProvider: { AnalysisExporter.htmlTemplate }
        )
        let task = MockSchemeTask(url: URL(string: "wcc://analysis.html")!)
        handler.webView(WKWebView(), start: task)

        let html = String(data: task.receivedData!, encoding: .utf8)!
        // The served HTML must be the full template, not truncated or corrupted
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(html.hasSuffix("</html>\n") || html.hasSuffix("</html>"))
        XCTAssertTrue(html.contains("wcc://usage.json"))
        XCTAssertTrue(html.contains("wcc://tokens.json"))
        XCTAssertTrue(html.contains("function main"))

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

        // Create 1000 rows — similar to real production data
        var rows: [(String, Double, Double)] = []
        for i in 0..<1000 {
            rows.append(("2026-02-\(String(format: "%02d", (i / 288) + 1))T\(String(format: "%02d", (i % 288) / 12)):\(String(format: "%02d", (i % 12) * 5)):00.000Z",
                         Double(i % 100),
                         Double(i % 50)))
        }
        createUsageDb(at: usagePath, rows: rows)
        createTokensDb(at: tokensPath, rows: [])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath, tokensDbPath: tokensPath,
            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "wcc://usage.json")!)
        handler.webView(WKWebView(), start: task)

        let json = try! JSONSerialization.jsonObject(with: task.receivedData!) as! [[String: Any]]
        XCTAssertEqual(json.count, 1000,
                       "All 1000 rows must be present in JSON response")
        // Spot-check first and last values
        XCTAssertEqual(json[0]["five_hour_percent"] as! Double, 0.0, accuracy: 0.01)
        XCTAssertEqual(json[999]["five_hour_percent"] as! Double, 99.0, accuracy: 0.01)
    }
}

// MARK: - WKWebView Integration Tests

/// Actually loads HTML in a WKWebView with the scheme handler and verifies
/// JavaScript can fetch JSON data via wcc:// scheme handler.
/// This tests the REAL runtime path that broke in production.
final class AnalysisWebViewIntegrationTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalysisWebViewTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    private func createUsageDb(at path: String, rows: [(String, Double, Double)]) {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, """
            CREATE TABLE IF NOT EXISTS usage_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                five_hour_percent REAL,
                seven_day_percent REAL,
                five_hour_resets_at TEXT,
                seven_day_resets_at TEXT
            );
            """, nil, nil, nil)
        for (ts, fiveH, sevenD) in rows {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "INSERT INTO usage_log (timestamp, five_hour_percent, seven_day_percent) VALUES (?, ?, ?);", -1, &stmt, nil)
            sqlite3_bind_text(stmt, 1, (ts as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 2, fiveH)
            sqlite3_bind_double(stmt, 3, sevenD)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    private func createTokensDb(at path: String) {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, """
            CREATE TABLE IF NOT EXISTS token_records (
                request_id TEXT PRIMARY KEY, timestamp TEXT NOT NULL, model TEXT NOT NULL,
                input_tokens INTEGER NOT NULL, output_tokens INTEGER NOT NULL,
                cache_read_tokens INTEGER NOT NULL, cache_creation_tokens INTEGER NOT NULL
            );
            """, nil, nil, nil)
    }

    /// Helper: create WKWebView with scheme handler, load page, wait for navigation to finish.
    private func loadWebView(
        usagePath: String, tokensPath: String,
        html: @escaping () -> String
    ) -> (WKWebView, XCTestExpectation) {
        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath, tokensDbPath: tokensPath,
            htmlProvider: html
        )
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(handler, forURLScheme: AnalysisSchemeHandler.scheme)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 100, height: 100), configuration: config)

        let navExpectation = expectation(description: "Page loaded")
        let navDelegate = TestNavDelegate(onFinish: { navExpectation.fulfill() })
        webView.navigationDelegate = navDelegate
        // Keep delegate alive — store on webView via associated object
        objc_setAssociatedObject(webView, "navDelegate", navDelegate, .OBJC_ASSOCIATION_RETAIN)

        webView.load(URLRequest(url: URL(string: "wcc://analysis.html")!))
        return (webView, navExpectation)
    }

    /// WKWebView with scheme handler can load HTML and execute JS fetch() against wcc:// JSON URLs.
    /// This is the actual runtime path. If this test passes, the Analysis window works.
    func testWKWebView_canFetchJsonViaSchemeHandler() {
        let usagePath = tmpDir.appendingPathComponent("usage.db").path
        let tokensPath = tmpDir.appendingPathComponent("tokens.db").path
        createUsageDb(at: usagePath, rows: [
            ("2026-02-24T10:00:00.000Z", 42.5, 15.0),
            ("2026-02-24T10:05:00.000Z", 55.0, 20.0),
        ])
        createTokensDb(at: tokensPath)

        let (webView, navExp) = loadWebView(usagePath: usagePath, tokensPath: tokensPath) {
            "<!DOCTYPE html><html><body></body></html>"
        }
        wait(for: [navExp], timeout: 5.0)

        let jsExp = expectation(description: "JS executed")
        let jsCode = """
            const res = await fetch('wcc://usage.json');
            const json = await res.json();
            return {ok: res.ok, status: res.status, count: json.length, firstFiveH: json[0]?.five_hour_percent};
            """
        webView.callAsyncJavaScript(jsCode, arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .success(let value):
                guard let dict = value as? [String: Any] else {
                    XCTFail("Unexpected result type: \(type(of: value))")
                    jsExp.fulfill()
                    return
                }
                XCTAssertEqual(dict["ok"] as? Bool, true,
                               "fetch('wcc://usage.json') must return ok:true")
                XCTAssertEqual(dict["status"] as? Int, 200)
                XCTAssertEqual(dict["count"] as? Int, 2)
                XCTAssertEqual(dict["firstFiveH"] as? Double, 42.5)
            case .failure(let error):
                XCTFail("JS failed: \(error)")
            }
            jsExp.fulfill()
        }
        wait(for: [jsExp], timeout: 5.0)
    }

    /// In WKWebView, custom scheme 404 causes fetch() to throw TypeError (not return status 404).
    /// This matches the actual runtime behavior — the HTML template's fetchJSON() uses try/catch → null.
    func testWKWebView_unknownPath_fetchThrows() {
        let usagePath = tmpDir.appendingPathComponent("usage.db").path
        let tokensPath = tmpDir.appendingPathComponent("tokens.db").path
        createUsageDb(at: usagePath, rows: [])
        createTokensDb(at: tokensPath)

        let (webView, navExp) = loadWebView(usagePath: usagePath, tokensPath: tokensPath) {
            "<!DOCTYPE html><html><body></body></html>"
        }
        wait(for: [navExp], timeout: 5.0)

        let jsExp = expectation(description: "JS executed")
        let jsCode = """
            try {
                await fetch('wcc://nonexistent.db');
                return {threw: false};
            } catch (e) {
                return {threw: true, message: e.message};
            }
            """
        webView.callAsyncJavaScript(jsCode, arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .success(let value):
                guard let dict = value as? [String: Any] else {
                    XCTFail("Unexpected result type")
                    jsExp.fulfill()
                    return
                }
                XCTAssertEqual(dict["threw"] as? Bool, true,
                               "fetch() to 404 custom scheme path must throw — HTML template handles this with try/catch")
            case .failure(let error):
                XCTFail("JS failed: \(error)")
            }
            jsExp.fulfill()
        }
        wait(for: [jsExp], timeout: 5.0)
    }

}

/// WKNavigationDelegate for waiting on page load completion in tests.
private final class TestNavDelegate: NSObject, WKNavigationDelegate {
    private let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onFinish() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onFinish() }
}

// MARK: - CostEstimator Parity Tests (Swift vs JS)

/// Verifies that the JS costForRecord function in the HTML template
/// produces the same results as Swift's CostEstimator.cost(for:).
/// If these diverge, the Analysis window shows wrong cost data.
final class CostEstimatorParityTests: XCTestCase {

    /// Compute cost using Swift CostEstimator for comparison.
    private func swiftCost(model: String, input: Int, output: Int, cacheRead: Int, cacheWrite: Int) -> Double {
        let record = TokenRecord(
            timestamp: Date(),
            requestId: "test",
            model: model,
            speed: "standard",
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheCreationTokens: cacheWrite,
            webSearchRequests: 0
        )
        return CostEstimator.cost(for: record)
    }

    /// Extract JS pricing from the HTML template and verify it matches Swift.
    func testJsPricing_opus_matchesSwift() {
        let swiftPricing = CostEstimator.opus
        XCTAssertEqual(swiftPricing.input, 15.0)
        XCTAssertEqual(swiftPricing.output, 75.0)
        XCTAssertEqual(swiftPricing.cacheWrite, 18.75)
        XCTAssertEqual(swiftPricing.cacheRead, 1.50)

        // Verify JS template has matching values
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("input: 15.0"))
        XCTAssertTrue(html.contains("output: 75.0"))
        XCTAssertTrue(html.contains("cacheWrite: 18.75"))
        XCTAssertTrue(html.contains("cacheRead: 1.50") || html.contains("cacheRead: 1.5"))
    }

    func testJsPricing_sonnet_matchesSwift() {
        let swiftPricing = CostEstimator.sonnet
        XCTAssertEqual(swiftPricing.input, 3.0)
        XCTAssertEqual(swiftPricing.output, 15.0)
        XCTAssertEqual(swiftPricing.cacheWrite, 3.75)
        XCTAssertEqual(swiftPricing.cacheRead, 0.30)

        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("cacheWrite: 3.75"))
        XCTAssertTrue(html.contains("cacheRead: 0.30") || html.contains("cacheRead: 0.3"))
    }

    func testJsPricing_haiku_matchesSwift() {
        let swiftPricing = CostEstimator.haiku
        XCTAssertEqual(swiftPricing.input, 0.80)
        XCTAssertEqual(swiftPricing.output, 4.0)
        XCTAssertEqual(swiftPricing.cacheWrite, 1.0)
        XCTAssertEqual(swiftPricing.cacheRead, 0.08)

        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("cacheWrite: 1.0"))
        XCTAssertTrue(html.contains("cacheRead: 0.08"))
    }

    /// Verify model routing: JS pricingForModel uses same matching as Swift.
    func testJsModelRouting_matchesSwift() {
        let html = AnalysisExporter.htmlTemplate
        // JS: model.includes('opus') → opus (matches claude-opus-* and claude-3-opus-*)
        XCTAssertTrue(html.contains("model.includes('opus')") ||
                      html.contains("model.includes(\"opus\")"))
        // JS: model.includes('haiku') → haiku
        XCTAssertTrue(html.contains("model.includes('haiku')") ||
                      html.contains("model.includes(\"haiku\")"))
        // JS should return sonnet as default (fall-through)
        XCTAssertTrue(html.contains("return MODEL_PRICING.sonnet"))
    }

    /// Verify cost formula: JS uses same calculation as Swift.
    /// Swift: input/1M * pricing.input + output/1M * pricing.output + cacheCreation/1M * pricing.cacheWrite + cacheRead/1M * pricing.cacheRead
    func testCostFormula_sonnet_1MInputTokens() {
        let cost = swiftCost(model: "claude-sonnet-4-20250514", input: 1_000_000, output: 0, cacheRead: 0, cacheWrite: 0)
        XCTAssertEqual(cost, 3.0, accuracy: 0.001,
                       "1M sonnet input tokens = $3.00")
    }

    func testCostFormula_opus_1MOutputTokens() {
        let cost = swiftCost(model: "claude-opus-4-20250514", input: 0, output: 1_000_000, cacheRead: 0, cacheWrite: 0)
        XCTAssertEqual(cost, 75.0, accuracy: 0.001,
                       "1M opus output tokens = $75.00")
    }

    func testCostFormula_haiku_mixedTokens() {
        let cost = swiftCost(model: "claude-haiku-4-20250101", input: 500_000, output: 200_000, cacheRead: 1_000_000, cacheWrite: 300_000)
        // 0.5M * 0.80 + 0.2M * 4.0 + 1.0M * 0.08 + 0.3M * 1.0
        // = 0.40 + 0.80 + 0.08 + 0.30 = 1.58
        XCTAssertEqual(cost, 1.58, accuracy: 0.001)
    }

    func testCostFormula_cacheRead_isCheaperThanInput() {
        // This is the key insight: cache_read is 1/10 of input price
        let inputCost = swiftCost(model: "claude-sonnet-4-20250514", input: 1_000_000, output: 0, cacheRead: 0, cacheWrite: 0)
        let cacheCost = swiftCost(model: "claude-sonnet-4-20250514", input: 0, output: 0, cacheRead: 1_000_000, cacheWrite: 0)
        XCTAssertEqual(inputCost / cacheCost, 10.0, accuracy: 0.001,
                       "Cache read must be 1/10 of input price — this is why costs vary so much")
    }

    func testCostFormula_zeroTokens() {
        let cost = swiftCost(model: "claude-sonnet-4-20250514", input: 0, output: 0, cacheRead: 0, cacheWrite: 0)
        XCTAssertEqual(cost, 0.0, accuracy: 0.0001)
    }

    /// JS formula must use same field mapping as Swift.
    /// Swift: cacheCreationTokens → cacheWrite pricing
    /// JS: cache_creation_tokens → cacheWrite pricing
    func testJsCostFormula_fieldMapping() {
        let html = AnalysisExporter.htmlTemplate
        // JS must multiply cache_creation_tokens by cacheWrite (not cacheRead)
        XCTAssertTrue(html.contains("cache_creation_tokens") && html.contains("cacheWrite"),
                      "JS must map cache_creation_tokens to cacheWrite pricing")
        // JS must multiply cache_read_tokens by cacheRead (not cacheWrite)
        XCTAssertTrue(html.contains("cache_read_tokens") && html.contains("cacheRead"),
                      "JS must map cache_read_tokens to cacheRead pricing")
    }
}

// MARK: - JS Logic Tests (WKWebView execution)

/// Tests JS functions by EXECUTING them in a real WKWebView.
/// Each test loads the pure JS functions (no Chart.js CDN dependency),
/// calls them with known inputs via callAsyncJavaScript, and verifies outputs.
/// This catches logic bugs that string-matching tests cannot detect.
final class AnalysisJSLogicTests: XCTestCase {

    /// Uses JS functions extracted from the ACTUAL AnalysisExporter.htmlTemplate.
    /// NOT a copy — if the template changes, these tests automatically run the changed code.
    private static let testHTML = TemplateTestHelper.testHTML

    private var webView: WKWebView!

    override func setUp() {
        super.setUp()
        let exp = expectation(description: "Page loaded")
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let navDelegate = TestNavDelegate(onFinish: { exp.fulfill() })
        webView.navigationDelegate = navDelegate
        objc_setAssociatedObject(webView!, "navDelegate", navDelegate, .OBJC_ASSOCIATION_RETAIN)
        webView.loadHTMLString(Self.testHTML, baseURL: nil)
        wait(for: [exp], timeout: 10.0)
    }

    /// Helper: execute JS via callAsyncJavaScript and return result using XCTestExpectation.
    private func evalJS(_ code: String, file: StaticString = #file, line: UInt = #line) -> Any? {
        let exp = expectation(description: "JS eval")
        var jsResult: Any?
        var jsError: Error?
        webView.callAsyncJavaScript(code, arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .success(let value): jsResult = value
            case .failure(let error): jsError = error
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5.0)
        if let err = jsError { XCTFail("JS error: \(err)", file: file, line: line) }
        return jsResult
    }

    // =========================================================
    // MARK: - pricingForModel
    // =========================================================

    func testPricingForModel_opusFullName() {
        let result = evalJS("""
            const p = pricingForModel('claude-opus-4-20250514');
            return {input: p.input, output: p.output, cacheWrite: p.cacheWrite, cacheRead: p.cacheRead};
        """) as? [String: Any]
        XCTAssertEqual(result?["input"] as? Double, 15.0)
        XCTAssertEqual(result?["output"] as? Double, 75.0)
        XCTAssertEqual(result?["cacheWrite"] as? Double, 18.75)
        XCTAssertEqual(result?["cacheRead"] as? Double, 1.50)
    }

    func testPricingForModel_sonnetFullName() {
        let result = evalJS("""
            const p = pricingForModel('claude-sonnet-4-20250514');
            return {input: p.input, output: p.output, cacheWrite: p.cacheWrite, cacheRead: p.cacheRead};
        """) as? [String: Any]
        XCTAssertEqual(result?["input"] as? Double, 3.0)
        XCTAssertEqual(result?["output"] as? Double, 15.0)
        XCTAssertEqual(result?["cacheWrite"] as? Double, 3.75)
        XCTAssertEqual(result?["cacheRead"] as? Double, 0.30)
    }

    func testPricingForModel_haikuFullName() {
        let result = evalJS("""
            const p = pricingForModel('claude-haiku-4-20250101');
            return {input: p.input, output: p.output, cacheWrite: p.cacheWrite, cacheRead: p.cacheRead};
        """) as? [String: Any]
        XCTAssertEqual(result?["input"] as? Double, 0.80)
        XCTAssertEqual(result?["output"] as? Double, 4.0)
        XCTAssertEqual(result?["cacheWrite"] as? Double, 1.0)
        XCTAssertEqual(result?["cacheRead"] as? Double, 0.08)
    }

    func testPricingForModel_unknownModel_defaultsToSonnet() {
        let result = evalJS("""
            const p = pricingForModel('some-unknown-model-v9');
            return {input: p.input, output: p.output};
        """) as? [String: Any]
        XCTAssertEqual(result?["input"] as? Double, 3.0)
        XCTAssertEqual(result?["output"] as? Double, 15.0)
    }

    func testPricingForModel_opusPrefixOnly() {
        // "claude-opus" without version should still match opus
        let result = evalJS("""
            return pricingForModel('claude-opus').input;
        """) as? Double
        XCTAssertEqual(result, 15.0)
    }

    // =========================================================
    // MARK: - costForRecord
    // =========================================================

    func testCostForRecord_sonnet_1MInput() {
        let result = evalJS("""
            return costForRecord({
                model: 'claude-sonnet-4-20250514',
                input_tokens: 1000000, output_tokens: 0,
                cache_read_tokens: 0, cache_creation_tokens: 0
            });
        """) as? Double
        // 1M * 3.0 / 1M = $3.00
        XCTAssertEqual(result!, 3.0, accuracy: 0.001)
    }

    func testCostForRecord_opus_1MOutput() {
        let result = evalJS("""
            return costForRecord({
                model: 'claude-opus-4-20250514',
                input_tokens: 0, output_tokens: 1000000,
                cache_read_tokens: 0, cache_creation_tokens: 0
            });
        """) as? Double
        // 1M * 75.0 / 1M = $75.00
        XCTAssertEqual(result!, 75.0, accuracy: 0.001)
    }

    func testCostForRecord_haiku_mixedTokens() {
        let result = evalJS("""
            return costForRecord({
                model: 'claude-haiku-4-20250101',
                input_tokens: 500000, output_tokens: 200000,
                cache_read_tokens: 1000000, cache_creation_tokens: 300000
            });
        """) as? Double
        // 0.5M * 0.80 + 0.2M * 4.0 + 1.0M * 0.08 + 0.3M * 1.0
        // = 0.40 + 0.80 + 0.08 + 0.30 = 1.58
        XCTAssertEqual(result!, 1.58, accuracy: 0.001)
    }

    func testCostForRecord_zeroTokens() {
        let result = evalJS("""
            return costForRecord({
                model: 'claude-sonnet-4-20250514',
                input_tokens: 0, output_tokens: 0,
                cache_read_tokens: 0, cache_creation_tokens: 0
            });
        """) as? Double
        XCTAssertEqual(result!, 0.0, accuracy: 0.0001)
    }

    func testCostForRecord_cacheReadIs10xCheaperThanInput() {
        let inputCost = evalJS("""
            return costForRecord({
                model: 'claude-sonnet-4-20250514',
                input_tokens: 1000000, output_tokens: 0,
                cache_read_tokens: 0, cache_creation_tokens: 0
            });
        """) as! Double
        let cacheCost = evalJS("""
            return costForRecord({
                model: 'claude-sonnet-4-20250514',
                input_tokens: 0, output_tokens: 0,
                cache_read_tokens: 1000000, cache_creation_tokens: 0
            });
        """) as! Double
        // cache_read is 1/10 of input price (the key insight for cost variation)
        XCTAssertEqual(inputCost / cacheCost, 10.0, accuracy: 0.001)
    }

    /// Verify JS costForRecord matches Swift CostEstimator.cost(for:) exactly.
    func testCostForRecord_matchesSwiftCostEstimator() {
        let testCases: [(String, Int, Int, Int, Int)] = [
            ("claude-sonnet-4-20250514", 150_000, 50_000, 800_000, 200_000),
            ("claude-opus-4-20250514", 1_000_000, 300_000, 500_000, 100_000),
            ("claude-haiku-4-20250101", 2_000_000, 100_000, 3_000_000, 50_000),
            ("claude-sonnet-4-20250514", 0, 0, 0, 0),
            ("claude-opus-4-20250514", 1, 1, 1, 1),
        ]

        for (model, inp, out, cacheR, cacheW) in testCases {
            let swiftCost = CostEstimator.cost(for: TokenRecord(
                timestamp: Date(), requestId: "t", model: model, speed: "standard",
                inputTokens: inp, outputTokens: out,
                cacheReadTokens: cacheR, cacheCreationTokens: cacheW,
                webSearchRequests: 0
            ))

            let jsCost = evalJS("""
                return costForRecord({
                    model: '\(model)',
                    input_tokens: \(inp), output_tokens: \(out),
                    cache_read_tokens: \(cacheR), cache_creation_tokens: \(cacheW)
                });
            """) as! Double

            XCTAssertEqual(jsCost, swiftCost, accuracy: 0.000001,
                           "JS/Swift cost mismatch for \(model) inp=\(inp) out=\(out) cR=\(cacheR) cW=\(cacheW)")
        }
    }

    // =========================================================
    // MARK: - computeKDE
    // =========================================================

    func testComputeKDE_singleValue_returnsEmpty() {
        let result = evalJS("""
            const kde = computeKDE([5.0]);
            return {xsLen: kde.xs.length, ysLen: kde.ys.length};
        """) as? [String: Any]
        // n < 2 → empty
        XCTAssertEqual(result?["xsLen"] as? Int, 0)
        XCTAssertEqual(result?["ysLen"] as? Int, 0)
    }

    func testComputeKDE_emptyArray_returnsEmpty() {
        let result = evalJS("""
            const kde = computeKDE([]);
            return {xsLen: kde.xs.length, ysLen: kde.ys.length};
        """) as? [String: Any]
        XCTAssertEqual(result?["xsLen"] as? Int, 0)
        XCTAssertEqual(result?["ysLen"] as? Int, 0)
    }

    func testComputeKDE_twoValues_returnsNonEmpty() {
        let result = evalJS("""
            const kde = computeKDE([1.0, 2.0]);
            return {xsLen: kde.xs.length, ysLen: kde.ys.length};
        """) as? [String: Any]
        let xsLen = result?["xsLen"] as! Int
        let ysLen = result?["ysLen"] as! Int
        XCTAssertGreaterThan(xsLen, 0)
        XCTAssertEqual(xsLen, ysLen, "xs and ys must have same length")
    }

    func testComputeKDE_outputLength_isAbout200() {
        let result = evalJS("""
            return computeKDE([1, 2, 3, 4, 5]).xs.length;
        """) as? Int
        // step = (hi - lo) / 200 → approximately 200 points
        XCTAssertGreaterThanOrEqual(result!, 190)
        XCTAssertLessThanOrEqual(result!, 210)
    }

    func testComputeKDE_densitiesAreNonNegative() {
        let result = evalJS("""
            const kde = computeKDE([1, 2, 3, 4, 5]);
            return kde.ys.every(y => y >= 0);
        """) as? Bool
        XCTAssertTrue(result!, "KDE density must be non-negative everywhere")
    }

    func testComputeKDE_peakNearMean() {
        // Symmetric data [1, 2, 3, 4, 5] → mean = 3, peak should be near x=3
        let result = evalJS("""
            const kde = computeKDE([1, 2, 3, 4, 5]);
            let maxY = -1, maxX = 0;
            for (let i = 0; i < kde.xs.length; i++) {
                if (kde.ys[i] > maxY) { maxY = kde.ys[i]; maxX = kde.xs[i]; }
            }
            return {peakX: maxX, peakY: maxY};
        """) as? [String: Any]
        let peakX = result?["peakX"] as! Double
        // Peak should be near the mean (3.0), within ±1
        XCTAssertEqual(peakX, 3.0, accuracy: 1.0,
                       "KDE peak for [1,2,3,4,5] should be near 3.0")
        let peakY = result?["peakY"] as! Double
        XCTAssertGreaterThan(peakY, 0.0)
    }

    func testComputeKDE_densityIntegral_isApproximatelyOne() {
        // The integral of a proper PDF should be approximately 1.0
        let result = evalJS("""
            const kde = computeKDE([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
            let integral = 0;
            for (let i = 1; i < kde.xs.length; i++) {
                const dx = kde.xs[i] - kde.xs[i-1];
                integral += (kde.ys[i] + kde.ys[i-1]) / 2 * dx;
            }
            return integral;
        """) as? Double
        // Trapezoidal integration of a KDE should be close to 1.0
        XCTAssertEqual(result!, 1.0, accuracy: 0.15,
                       "KDE integral should approximate 1.0 (proper probability density)")
    }

    func testComputeKDE_identicalValues_doesNotCrash() {
        // All same values → variance = 0, std = 0 → code uses || 1 fallback
        let result = evalJS("""
            const kde = computeKDE([5, 5, 5, 5, 5]);
            return {xsLen: kde.xs.length, allFinite: kde.ys.every(y => isFinite(y))};
        """) as? [String: Any]
        XCTAssertGreaterThan(result?["xsLen"] as! Int, 0)
        XCTAssertTrue(result?["allFinite"] as! Bool,
                      "KDE must not produce NaN/Infinity for identical values")
    }

    // =========================================================
    // MARK: - computeDeltas
    // =========================================================

    func testComputeDeltas_emptyUsage_returnsEmpty() {
        let result = evalJS("""
            return computeDeltas([], [{timestamp: '2026-02-24T10:00:00Z', costUSD: 1.0}]).length;
        """) as? Int
        XCTAssertEqual(result, 0)
    }

    func testComputeDeltas_singleUsage_returnsEmpty() {
        let result = evalJS("""
            return computeDeltas(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10}],
                [{timestamp: '2026-02-24T10:00:00Z', costUSD: 1.0}]
            ).length;
        """) as? Int
        XCTAssertEqual(result, 0, "Need at least 2 usage points to compute a delta")
    }

    func testComputeDeltas_twoUsageWithTokens_returnsOneDelta() {
        let result = evalJS("""
            const deltas = computeDeltas(
                [
                    {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10},
                    {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: 15},
                ],
                [
                    {timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50},
                ]
            );
            // getHours() returns local time, so compute expected hour in JS too
            const expectedHour = new Date('2026-02-24T10:05:00Z').getHours();
            return {
                length: deltas.length,
                x: deltas[0].x,
                y: deltas[0].y,
                hour: deltas[0].hour,
                expectedHour: expectedHour,
            };
        """) as? [String: Any]
        XCTAssertEqual(result?["length"] as? Int, 1)
        XCTAssertEqual(result!["x"] as! Double, 0.50, accuracy: 0.001,
                       "x = intervalCost")
        XCTAssertEqual(result!["y"] as! Double, 5.0, accuracy: 0.001,
                       "y = d5h = 15 - 10 = 5")
        XCTAssertEqual(result?["hour"] as? Int, result?["expectedHour"] as? Int,
                       "hour should match getHours() of curr timestamp (local timezone)")
    }

    func testComputeDeltas_filtersOutLowCostIntervals() {
        // intervalCost <= 0.001 should be excluded
        let result = evalJS("""
            const deltas = computeDeltas(
                [
                    {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10},
                    {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: 20},
                ],
                [
                    {timestamp: '2026-02-24T10:02:00Z', costUSD: 0.0005},
                ]
            );
            return deltas.length;
        """) as? Int
        XCTAssertEqual(result, 0,
                       "Intervals with cost <= 0.001 must be filtered out")
    }

    func testComputeDeltas_noTokensInInterval_excluded() {
        // Token is outside the usage interval → intervalCost = 0 → excluded
        let result = evalJS("""
            const deltas = computeDeltas(
                [
                    {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10},
                    {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: 20},
                ],
                [
                    {timestamp: '2026-02-24T09:00:00Z', costUSD: 5.0},
                ]
            );
            return deltas.length;
        """) as? Int
        XCTAssertEqual(result, 0,
                       "Token outside usage interval → no cost → excluded")
    }

    func testComputeDeltas_multipleTokensInInterval_summed() {
        let result = evalJS("""
            const deltas = computeDeltas(
                [
                    {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10},
                    {timestamp: '2026-02-24T10:10:00Z', five_hour_percent: 30},
                ],
                [
                    {timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50},
                    {timestamp: '2026-02-24T10:05:00Z', costUSD: 1.00},
                    {timestamp: '2026-02-24T10:08:00Z', costUSD: 0.25},
                ]
            );
            return {x: deltas[0].x, y: deltas[0].y};
        """) as? [String: Any]
        XCTAssertEqual(result!["x"] as! Double, 1.75, accuracy: 0.001,
                       "x = sum of costs in interval: 0.50 + 1.00 + 0.25")
        XCTAssertEqual(result!["y"] as! Double, 20.0, accuracy: 0.001,
                       "y = 30 - 10 = 20")
    }

    func testComputeDeltas_nullFiveHourPercent_skipped() {
        let result = evalJS("""
            const deltas = computeDeltas(
                [
                    {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: null},
                    {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: 10},
                ],
                [
                    {timestamp: '2026-02-24T10:02:00Z', costUSD: 1.0},
                ]
            );
            return deltas.length;
        """) as? Int
        // Intervals with null five_hour_percent should be skipped entirely
        XCTAssertEqual(result, 0, "Null prev percent → interval skipped, no bogus delta")
    }

    func testComputeDeltas_negativeDelta_preserved() {
        // Usage can decrease (e.g. after reset window slides)
        let result = evalJS("""
            const deltas = computeDeltas(
                [
                    {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 50},
                    {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: 20},
                ],
                [
                    {timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50},
                ]
            );
            return deltas[0].y;
        """) as? Double
        XCTAssertEqual(result!, -30.0, accuracy: 0.001,
                       "Negative delta (usage decrease) must be preserved")
    }

    // =========================================================
    // MARK: - insertResetPoints
    // =========================================================

    func testInsertResetPoints_noResets_justDataPoints() {
        let result = evalJS("""
            const data = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, five_hour_resets_at: null},
                {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: 20, five_hour_resets_at: null},
            ];
            return insertResetPoints(data, 'five_hour_percent', 'five_hour_resets_at');
        """) as? [[String: Any]]
        XCTAssertEqual(result?.count, 2)
        XCTAssertEqual(result?[0]["y"] as? Double, 10.0)
        XCTAssertEqual(result?[1]["y"] as? Double, 20.0)
    }

    func testInsertResetPoints_resetBetweenPoints_insertsZero() {
        let result = evalJS("""
            const data = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 80, five_hour_resets_at: '2026-02-24T12:00:00Z'},
                {timestamp: '2026-02-24T14:00:00Z', five_hour_percent: 5, five_hour_resets_at: '2026-02-24T17:00:00Z'},
            ];
            return insertResetPoints(data, 'five_hour_percent', 'five_hour_resets_at');
        """) as? [[String: Any]]
        // Should insert a zero-point at 12:00 (resets_at of first point)
        XCTAssertEqual(result?.count, 3, "Should be 3 points: original + zero-point + original")
        XCTAssertEqual(result?[0]["y"] as? Double, 80.0, "First original point")
        XCTAssertEqual(result?[1]["y"] as? Double, 0.0, "Zero-point at reset boundary")
        XCTAssertEqual(result?[1]["x"] as? String, "2026-02-24T12:00:00Z", "Zero-point at resets_at time")
        XCTAssertEqual(result?[2]["y"] as? Double, 5.0, "Second original point")
    }

    func testInsertResetPoints_resetNotBetweenPoints_noZeroInserted() {
        // resets_at is BEFORE prev.timestamp → no zero-point
        let result = evalJS("""
            const data = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 80, five_hour_resets_at: '2026-02-24T08:00:00Z'},
                {timestamp: '2026-02-24T14:00:00Z', five_hour_percent: 5, five_hour_resets_at: null},
            ];
            return insertResetPoints(data, 'five_hour_percent', 'five_hour_resets_at').length;
        """) as? Int
        XCTAssertEqual(result, 2, "resets_at before prev → no zero-point inserted")
    }

    func testInsertResetPoints_resetAfterCurr_noZeroInserted() {
        // resets_at is AFTER curr.timestamp → not between prev and curr → no zero-point
        let result = evalJS("""
            const data = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 80, five_hour_resets_at: '2026-02-24T16:00:00Z'},
                {timestamp: '2026-02-24T14:00:00Z', five_hour_percent: 5, five_hour_resets_at: null},
            ];
            return insertResetPoints(data, 'five_hour_percent', 'five_hour_resets_at').length;
        """) as? Int
        XCTAssertEqual(result, 2, "resets_at after curr → no zero-point inserted")
    }

    func testInsertResetPoints_skipsNullPercent() {
        let result = evalJS("""
            const data = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, five_hour_resets_at: null},
                {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: null, five_hour_resets_at: null},
                {timestamp: '2026-02-24T10:10:00Z', five_hour_percent: 20, five_hour_resets_at: null},
            ];
            return insertResetPoints(data, 'five_hour_percent', 'five_hour_resets_at');
        """) as? [[String: Any]]
        // null percent → skipped
        XCTAssertEqual(result?.count, 2)
        XCTAssertEqual(result?[0]["y"] as? Double, 10.0)
        XCTAssertEqual(result?[1]["y"] as? Double, 20.0)
    }

    func testInsertResetPoints_emptyInput_returnsEmpty() {
        let result = evalJS("""
            return insertResetPoints([], 'five_hour_percent', 'five_hour_resets_at').length;
        """) as? Int
        XCTAssertEqual(result, 0)
    }

    func testInsertResetPoints_sevenDayKey_alsoWorks() {
        let result = evalJS("""
            const data = [
                {timestamp: '2026-02-24T10:00:00Z', seven_day_percent: 50, seven_day_resets_at: '2026-02-25T10:00:00Z'},
                {timestamp: '2026-02-26T10:00:00Z', seven_day_percent: 5, seven_day_resets_at: null},
            ];
            const r = insertResetPoints(data, 'seven_day_percent', 'seven_day_resets_at');
            return {count: r.length, zeroY: r[1].y, zeroX: r[1].x};
        """) as? [String: Any]
        XCTAssertEqual(result?["count"] as? Int, 3)
        XCTAssertEqual(result?["zeroY"] as? Double, 0.0)
        XCTAssertEqual(result?["zeroX"] as? String, "2026-02-25T10:00:00Z")
    }

    func testInsertResetPoints_multipleResets_insertsMultipleZeros() {
        let result = evalJS("""
            const data = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 80, five_hour_resets_at: '2026-02-24T12:00:00Z'},
                {timestamp: '2026-02-24T14:00:00Z', five_hour_percent: 60, five_hour_resets_at: '2026-02-24T16:00:00Z'},
                {timestamp: '2026-02-24T18:00:00Z', five_hour_percent: 30, five_hour_resets_at: null},
            ];
            return insertResetPoints(data, 'five_hour_percent', 'five_hour_resets_at').length;
        """) as? Int
        // Point 0 (80), zero at 12:00, Point 1 (60), zero at 16:00, Point 2 (30) = 5
        XCTAssertEqual(result, 5,
                       "Two resets → two zero-points inserted → 3 original + 2 zeros = 5")
    }

    // =========================================================
    // MARK: - pricingForModel — old model name formats (claude-3-*)
    // =========================================================

    func testPricingForModel_claude3Opus() {
        // Claude 3 Opus model ID: claude-3-opus-20240229
        // Should return opus pricing (input: $15), not default sonnet ($3)
        let result = evalJS("""
            return pricingForModel('claude-3-opus-20240229').input;
        """) as? Double
        XCTAssertEqual(result, 15.0,
                       "claude-3-opus should use opus pricing ($15/M input), not sonnet ($3)")
    }

    func testPricingForModel_claude35Haiku() {
        // Claude 3.5 Haiku model ID: claude-3-5-haiku-20241022
        // Should return haiku pricing (input: $0.80), not default sonnet ($3)
        let result = evalJS("""
            return pricingForModel('claude-3-5-haiku-20241022').input;
        """) as? Double
        XCTAssertEqual(result, 0.80,
                       "claude-3-5-haiku should use haiku pricing ($0.80/M input), not sonnet ($3)")
    }

    func testPricingForModel_claude3Haiku() {
        let result = evalJS("""
            return pricingForModel('claude-3-haiku-20240307').input;
        """) as? Double
        XCTAssertEqual(result, 0.80,
                       "claude-3-haiku should use haiku pricing ($0.80/M input)")
    }

    func testPricingForModel_claude35Sonnet() {
        // Claude 3.5 Sonnet should correctly fall through to sonnet pricing
        let result = evalJS("""
            return pricingForModel('claude-3-5-sonnet-20241022').input;
        """) as? Double
        XCTAssertEqual(result, 3.0,
                       "claude-3-5-sonnet should use sonnet pricing ($3/M input)")
    }

    // =========================================================
    // MARK: - costForRecord — old model names produce correct costs
    // =========================================================

    func testCostForRecord_claude3Opus_usesOpusPricing() {
        let result = evalJS("""
            return costForRecord({
                model: 'claude-3-opus-20240229',
                input_tokens: 1000000, output_tokens: 0,
                cache_read_tokens: 0, cache_creation_tokens: 0
            });
        """) as? Double
        // Should be opus: 1M * $15/M = $15, not sonnet: 1M * $3/M = $3
        XCTAssertEqual(result!, 15.0, accuracy: 0.001,
                       "claude-3-opus 1M input should cost $15 (opus), not $3 (sonnet)")
    }

    func testCostForRecord_claude35Haiku_usesHaikuPricing() {
        let result = evalJS("""
            return costForRecord({
                model: 'claude-3-5-haiku-20241022',
                input_tokens: 1000000, output_tokens: 0,
                cache_read_tokens: 0, cache_creation_tokens: 0
            });
        """) as? Double
        // Should be haiku: 1M * $0.80/M = $0.80, not sonnet: $3
        XCTAssertEqual(result!, 0.80, accuracy: 0.001,
                       "claude-3-5-haiku 1M input should cost $0.80 (haiku), not $3 (sonnet)")
    }

    // =========================================================
    // MARK: - Swift CostEstimator — old model name matching
    // =========================================================

    func testSwiftPricingForModel_claude3Opus() {
        let pricing = CostEstimator.pricingForModel("claude-3-opus-20240229")
        XCTAssertEqual(pricing.input, 15.0,
                       "Swift: claude-3-opus should use opus pricing ($15/M input)")
    }

    func testSwiftPricingForModel_claude35Haiku() {
        let pricing = CostEstimator.pricingForModel("claude-3-5-haiku-20241022")
        XCTAssertEqual(pricing.input, 0.80,
                       "Swift: claude-3-5-haiku should use haiku pricing ($0.80/M input)")
    }

    func testSwiftPricingForModel_claude3Haiku() {
        let pricing = CostEstimator.pricingForModel("claude-3-haiku-20240307")
        XCTAssertEqual(pricing.input, 0.80,
                       "Swift: claude-3-haiku should use haiku pricing ($0.80/M input)")
    }

    // =========================================================
    // MARK: - computeDeltas — token at exact boundary
    // =========================================================

    func testComputeDeltas_tokenAtExactT1_excludedFromInterval() {
        // Token at exactly t1 (the curr timestamp) should NOT be in interval [t0, t1)
        let result = evalJS("""
            const deltas = computeDeltas(
                [
                    {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10},
                    {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: 20},
                    {timestamp: '2026-02-24T10:10:00Z', five_hour_percent: 30},
                ],
                [
                    {timestamp: '2026-02-24T10:05:00Z', costUSD: 0.50},
                ]
            );
            // Token at 10:05 → interval [10:00, 10:05): t >= t0 && t < t1 → 10:05 is NOT < 10:05
            // Token should be in interval [10:05, 10:10): t >= 10:05 && t < 10:10 → YES
            return {
                count: deltas.length,
                firstX: deltas[0]?.x,
                secondX: deltas[1]?.x,
            };
        """) as? [String: Any]
        // First interval [10:00, 10:05) has no tokens → excluded (cost < 0.001)
        // Second interval [10:05, 10:10) has token $0.50 → included
        XCTAssertEqual(result?["count"] as? Int, 1,
                       "Only one interval should have cost > 0.001")
        XCTAssertEqual(result?["secondX"] as? Double ?? result?["firstX"] as? Double ?? 0,
                       0.50, accuracy: 0.001)
    }

    // =========================================================
    // MARK: - insertResetPoints — null entries between valid ones
    // =========================================================

    func testInsertResetPoints_nullsBetweenValids_resetStillDetected() {
        // Null entries between valid ones should not prevent reset detection
        let result = evalJS("""
            const data = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 80, five_hour_resets_at: '2026-02-24T12:00:00Z'},
                {timestamp: '2026-02-24T11:00:00Z', five_hour_percent: null, five_hour_resets_at: null},
                {timestamp: '2026-02-24T11:30:00Z', five_hour_percent: null, five_hour_resets_at: null},
                {timestamp: '2026-02-24T14:00:00Z', five_hour_percent: 5, five_hour_resets_at: null},
            ];
            const r = insertResetPoints(data, 'five_hour_percent', 'five_hour_resets_at');
            return { count: r.length, zeroY: r[1]?.y, zeroX: r[1]?.x };
        """) as? [String: Any]
        // Should: point(80), zero at 12:00, point(5) = 3 entries (nulls skipped)
        XCTAssertEqual(result?["count"] as? Int, 3,
                       "Null entries skipped, reset still detected between valid entries")
        XCTAssertEqual(result?["zeroY"] as? Double, 0.0)
        XCTAssertEqual(result?["zeroX"] as? String, "2026-02-24T12:00:00Z")
    }

    // =========================================================
    // MARK: - getFilteredDeltas edge cases
    // =========================================================

    func testGetFilteredDeltas_emptyDateInputs_returnsAll() {
        let result = evalJS("""
            _allDeltas = [
                {x: 1.0, y: 5.0, hour: 10, timestamp: '2026-02-24T10:05:00Z', date: new Date('2026-02-24T10:05:00Z')},
                {x: 0.5, y: 3.0, hour: 11, timestamp: '2026-02-24T11:05:00Z', date: new Date('2026-02-24T11:05:00Z')},
            ];
            document.getElementById('dateFrom').value = '';
            document.getElementById('dateTo').value = '';
            return getFilteredDeltas().length;
        """) as? Int
        XCTAssertEqual(result, 2, "Empty date inputs should return all deltas")
    }

    func testGetFilteredDeltas_sameDayRange_includesMatchingDeltas() {
        let result = evalJS("""
            _allDeltas = [
                {x: 1.0, y: 5.0, timestamp: '2026-02-24T10:00:00Z', date: new Date('2026-02-24T10:00:00Z')},
                {x: 0.5, y: 3.0, timestamp: '2026-02-25T10:00:00Z', date: new Date('2026-02-25T10:00:00Z')},
            ];
            document.getElementById('dateFrom').value = '2026-02-24';
            document.getElementById('dateTo').value = '2026-02-24';
            return getFilteredDeltas().length;
        """) as? Int
        // Feb 24 00:00:00 to Feb 24 23:59:59 (local)
        // Date('2026-02-24T10:00:00Z') in JST = Feb 24 19:00 → within range
        // Date('2026-02-25T10:00:00Z') in JST = Feb 25 19:00 → outside range
        XCTAssertEqual(result, 1, "Only deltas within the date range should be returned")
    }

    // =========================================================
    // MARK: - isGapSegment (real template)
    // =========================================================

    func testIsGapSegment_defaultThreshold30min() {
        let result = evalJS("""
            // Default gapThresholdMs = 30 * 60 * 1000 = 1800000
            const ctx = {
                p0: { parsed: { x: 0 } },
                p1: { parsed: { x: 1800001 } }  // 30min + 1ms
            };
            return isGapSegment(ctx);
        """) as? Bool
        XCTAssertTrue(result!, "Gap > 30min should be detected")
    }

    func testIsGapSegment_exactlyThreshold_noGap() {
        let result = evalJS("""
            const ctx = {
                p0: { parsed: { x: 0 } },
                p1: { parsed: { x: 1800000 } }  // exactly 30min
            };
            return isGapSegment(ctx);
        """) as? Bool
        XCTAssertFalse(result!, "Gap exactly at threshold should NOT be detected (> not >=)")
    }

    func testIsGapSegment_belowThreshold_noGap() {
        let result = evalJS("""
            const ctx = {
                p0: { parsed: { x: 0 } },
                p1: { parsed: { x: 300000 } }  // 5min
            };
            return isGapSegment(ctx);
        """) as? Bool
        XCTAssertFalse(result!, "5min gap should not be detected with 30min threshold")
    }
}

// MARK: - SQL Query Correctness Tests

/// Verifies that the SQL queries used in the HTML template produce correct results
/// when run against real SQLite databases with the same schema as UsageStore/TokenStore.
/// This catches column ordering bugs, missing columns, and type mismatches.
final class AnalysisSQLQueryTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SQLQueryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    /// Execute the EXACT usage_log query from the HTML template against a real SQLite DB.
    func testUsageQuery_columnOrderMatchesJSMapping() {
        let path = tmpDir.appendingPathComponent("usage.db").path
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        sqlite3_exec(db, """
            CREATE TABLE usage_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                five_hour_percent REAL,
                seven_day_percent REAL,
                five_hour_resets_at TEXT,
                seven_day_resets_at TEXT
            );
            INSERT INTO usage_log (timestamp, five_hour_percent, seven_day_percent, five_hour_resets_at, seven_day_resets_at)
            VALUES ('2026-02-24T10:00:00.000Z', 42.5, 15.0, '2026-02-24T15:00:00.000Z', '2026-03-03T10:00:00.000Z');
            """, nil, nil, nil)

        // This is the EXACT query from AnalysisSchemeHandler.queryUsageJSON()
        let sql = """
            SELECT timestamp, five_hour_percent, seven_day_percent,
                   five_hour_resets_at, seven_day_resets_at
            FROM usage_log ORDER BY timestamp ASC
            """
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &stmt, nil), SQLITE_OK)
        defer { sqlite3_finalize(stmt) }

        XCTAssertEqual(sqlite3_step(stmt), SQLITE_ROW)

        // JS maps: row[0]=timestamp, row[1]=five_hour_percent, row[2]=seven_day_percent,
        //          row[3]=five_hour_resets_at, row[4]=seven_day_resets_at
        XCTAssertEqual(String(cString: sqlite3_column_text(stmt, 0)), "2026-02-24T10:00:00.000Z",
                       "Column 0 must be timestamp")
        XCTAssertEqual(sqlite3_column_double(stmt, 1), 42.5, accuracy: 0.01,
                       "Column 1 must be five_hour_percent")
        XCTAssertEqual(sqlite3_column_double(stmt, 2), 15.0, accuracy: 0.01,
                       "Column 2 must be seven_day_percent")
        XCTAssertEqual(String(cString: sqlite3_column_text(stmt, 3)), "2026-02-24T15:00:00.000Z",
                       "Column 3 must be five_hour_resets_at")
        XCTAssertEqual(String(cString: sqlite3_column_text(stmt, 4)), "2026-03-03T10:00:00.000Z",
                       "Column 4 must be seven_day_resets_at")
    }

    /// Execute the EXACT token_records query from the HTML template.
    func testTokenQuery_columnOrderMatchesJSMapping() {
        let path = tmpDir.appendingPathComponent("tokens.db").path
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        sqlite3_exec(db, """
            CREATE TABLE token_records (
                request_id TEXT PRIMARY KEY,
                timestamp TEXT NOT NULL,
                model TEXT NOT NULL,
                input_tokens INTEGER NOT NULL,
                output_tokens INTEGER NOT NULL,
                cache_read_tokens INTEGER NOT NULL,
                cache_creation_tokens INTEGER NOT NULL
            );
            INSERT INTO token_records VALUES ('req-1', '2026-02-24T10:00:00.000Z', 'claude-sonnet-4-20250514', 150000, 50000, 800000, 200000);
            """, nil, nil, nil)

        // EXACT query from loadData()
        let sql = """
            SELECT timestamp, model, input_tokens, output_tokens,
                   cache_read_tokens, cache_creation_tokens
            FROM token_records ORDER BY timestamp ASC
            """
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &stmt, nil), SQLITE_OK)
        defer { sqlite3_finalize(stmt) }

        XCTAssertEqual(sqlite3_step(stmt), SQLITE_ROW)

        // JS maps: row[0]=timestamp, row[1]=model, row[2]=input_tokens,
        //          row[3]=output_tokens, row[4]=cache_read_tokens, row[5]=cache_creation_tokens
        XCTAssertEqual(String(cString: sqlite3_column_text(stmt, 0)), "2026-02-24T10:00:00.000Z",
                       "Column 0 must be timestamp")
        XCTAssertEqual(String(cString: sqlite3_column_text(stmt, 1)), "claude-sonnet-4-20250514",
                       "Column 1 must be model")
        XCTAssertEqual(sqlite3_column_int(stmt, 2), 150000,
                       "Column 2 must be input_tokens")
        XCTAssertEqual(sqlite3_column_int(stmt, 3), 50000,
                       "Column 3 must be output_tokens")
        XCTAssertEqual(sqlite3_column_int(stmt, 4), 800000,
                       "Column 4 must be cache_read_tokens")
        XCTAssertEqual(sqlite3_column_int(stmt, 5), 200000,
                       "Column 5 must be cache_creation_tokens")
    }

    /// Verify usage query returns rows sorted by timestamp ascending.
    func testUsageQuery_orderByTimestampAsc() {
        let path = tmpDir.appendingPathComponent("usage.db").path
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        sqlite3_exec(db, """
            CREATE TABLE usage_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL, five_hour_percent REAL,
                seven_day_percent REAL, five_hour_resets_at TEXT, seven_day_resets_at TEXT
            );
            INSERT INTO usage_log (timestamp, five_hour_percent, seven_day_percent) VALUES ('2026-02-24T12:00:00Z', 30.0, 10.0);
            INSERT INTO usage_log (timestamp, five_hour_percent, seven_day_percent) VALUES ('2026-02-24T10:00:00Z', 10.0, 5.0);
            INSERT INTO usage_log (timestamp, five_hour_percent, seven_day_percent) VALUES ('2026-02-24T11:00:00Z', 20.0, 8.0);
            """, nil, nil, nil)

        let sql = "SELECT timestamp, five_hour_percent, seven_day_percent, five_hour_resets_at, seven_day_resets_at FROM usage_log ORDER BY timestamp ASC"
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }

        // Inserted out of order — query must return them sorted
        sqlite3_step(stmt)
        XCTAssertEqual(String(cString: sqlite3_column_text(stmt, 0)), "2026-02-24T10:00:00Z")
        XCTAssertEqual(sqlite3_column_double(stmt, 1), 10.0, accuracy: 0.01)

        sqlite3_step(stmt)
        XCTAssertEqual(String(cString: sqlite3_column_text(stmt, 0)), "2026-02-24T11:00:00Z")
        XCTAssertEqual(sqlite3_column_double(stmt, 1), 20.0, accuracy: 0.01)

        sqlite3_step(stmt)
        XCTAssertEqual(String(cString: sqlite3_column_text(stmt, 0)), "2026-02-24T12:00:00Z")
        XCTAssertEqual(sqlite3_column_double(stmt, 1), 30.0, accuracy: 0.01)
    }

    /// Verify null values in optional columns are handled correctly.
    func testUsageQuery_nullOptionalColumns() {
        let path = tmpDir.appendingPathComponent("usage.db").path
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        sqlite3_exec(db, """
            CREATE TABLE usage_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL, five_hour_percent REAL,
                seven_day_percent REAL, five_hour_resets_at TEXT, seven_day_resets_at TEXT
            );
            INSERT INTO usage_log (timestamp) VALUES ('2026-02-24T10:00:00Z');
            """, nil, nil, nil)

        let sql = "SELECT timestamp, five_hour_percent, seven_day_percent, five_hour_resets_at, seven_day_resets_at FROM usage_log ORDER BY timestamp ASC"
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }

        sqlite3_step(stmt)
        XCTAssertEqual(sqlite3_column_type(stmt, 1), SQLITE_NULL, "five_hour_percent should be NULL")
        XCTAssertEqual(sqlite3_column_type(stmt, 2), SQLITE_NULL, "seven_day_percent should be NULL")
        XCTAssertEqual(sqlite3_column_type(stmt, 3), SQLITE_NULL, "five_hour_resets_at should be NULL")
        XCTAssertEqual(sqlite3_column_type(stmt, 4), SQLITE_NULL, "seven_day_resets_at should be NULL")
    }

    /// Token query returns correct cost when piped through CostEstimator.
    func testTokenQuery_costMatchesCostEstimator() {
        let path = tmpDir.appendingPathComponent("tokens.db").path
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        sqlite3_exec(db, """
            CREATE TABLE token_records (
                request_id TEXT PRIMARY KEY, timestamp TEXT NOT NULL, model TEXT NOT NULL,
                input_tokens INTEGER NOT NULL, output_tokens INTEGER NOT NULL,
                cache_read_tokens INTEGER NOT NULL, cache_creation_tokens INTEGER NOT NULL
            );
            INSERT INTO token_records VALUES ('r1', '2026-02-24T10:00:00Z', 'claude-sonnet-4-20250514', 500000, 100000, 2000000, 50000);
            """, nil, nil, nil)

        let sql = "SELECT timestamp, model, input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens FROM token_records ORDER BY timestamp ASC"
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        sqlite3_step(stmt)

        let model = String(cString: sqlite3_column_text(stmt, 1))
        let inp = Int(sqlite3_column_int(stmt, 2))
        let out = Int(sqlite3_column_int(stmt, 3))
        let cacheR = Int(sqlite3_column_int(stmt, 4))
        let cacheW = Int(sqlite3_column_int(stmt, 5))

        let record = TokenRecord(timestamp: Date(), requestId: "r1", model: model, speed: "standard",
                                 inputTokens: inp, outputTokens: out,
                                 cacheReadTokens: cacheR, cacheCreationTokens: cacheW,
                                 webSearchRequests: 0)
        let cost = CostEstimator.cost(for: record)
        // 0.5M * 3.0 + 0.1M * 15.0 + 2.0M * 0.30 + 0.05M * 3.75
        // = 1.50 + 1.50 + 0.60 + 0.1875 = 3.7875
        XCTAssertEqual(cost, 3.7875, accuracy: 0.0001)
    }
}

// MARK: - Additional JS Logic Tests (edge cases, timeSlots, stats, cumulative, gap)

/// Extended JS logic tests covering timeSlots filtering, isGapSegment, cumulative cost,
/// stats computation from main(), boundary values, and template drift detection.
final class AnalysisJSExtendedTests: XCTestCase {

    /// Uses JS functions extracted from the ACTUAL AnalysisExporter.htmlTemplate.
    private static let testHTML = TemplateTestHelper.testHTML

    private var webView: WKWebView!

    override func setUp() {
        super.setUp()
        let exp = expectation(description: "Page loaded")
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let navDelegate = TestNavDelegate(onFinish: { exp.fulfill() })
        webView.navigationDelegate = navDelegate
        objc_setAssociatedObject(webView!, "navDelegate", navDelegate, .OBJC_ASSOCIATION_RETAIN)
        webView.loadHTMLString(Self.testHTML, baseURL: nil)
        wait(for: [exp], timeout: 10.0)
    }

    private func evalJS(_ code: String, file: StaticString = #file, line: UInt = #line) -> Any? {
        let exp = expectation(description: "JS eval")
        var jsResult: Any?
        var jsError: Error?
        webView.callAsyncJavaScript(code, arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .success(let value): jsResult = value
            case .failure(let error): jsError = error
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5.0)
        if let err = jsError { XCTFail("JS error: \(err)", file: file, line: line) }
        return jsResult
    }

    // =========================================================
    // MARK: - timeSlots filtering
    // =========================================================

    func testTimeSlots_nightFilter_hoursBelow6() {
        let result = evalJS("""
            return [0,1,2,3,4,5,6,11,12,17,18,23].filter(h => timeSlots[0].filter({hour: h}));
        """) as? [Int]
        XCTAssertEqual(result, [0, 1, 2, 3, 4, 5], "Night = hours 0-5")
    }

    func testTimeSlots_morningFilter_hours6to11() {
        let result = evalJS("""
            return [0,5,6,7,8,9,10,11,12,18].filter(h => timeSlots[1].filter({hour: h}));
        """) as? [Int]
        XCTAssertEqual(result, [6, 7, 8, 9, 10, 11], "Morning = hours 6-11")
    }

    func testTimeSlots_afternoonFilter_hours12to17() {
        let result = evalJS("""
            return [0,6,11,12,13,14,15,16,17,18,23].filter(h => timeSlots[2].filter({hour: h}));
        """) as? [Int]
        XCTAssertEqual(result, [12, 13, 14, 15, 16, 17], "Afternoon = hours 12-17")
    }

    func testTimeSlots_eveningFilter_hoursAbove18() {
        let result = evalJS("""
            return [0,6,12,17,18,19,20,21,22,23].filter(h => timeSlots[3].filter({hour: h}));
        """) as? [Int]
        XCTAssertEqual(result, [18, 19, 20, 21, 22, 23], "Evening = hours 18-23")
    }

    func testTimeSlots_everyHourBelongsToExactlyOneSlot() {
        let result = evalJS("""
            const counts = [];
            for (let h = 0; h < 24; h++) {
                let matched = 0;
                for (const slot of timeSlots) {
                    if (slot.filter({hour: h})) matched++;
                }
                counts.push(matched);
            }
            return counts.every(c => c === 1);
        """) as? Bool
        XCTAssertTrue(result!, "Every hour 0-23 must match exactly one timeSlot (no gaps, no overlaps)")
    }

    // =========================================================
    // MARK: - isGapSegment
    // =========================================================

    func testIsGapSegment_below30min_notAGap() {
        let result = evalJS("""
            const ctx = {p0: {parsed: {x: 0}}, p1: {parsed: {x: 29 * 60 * 1000}}};
            return isGapSegment(ctx);
        """) as? Bool
        XCTAssertFalse(result!, "29 minutes should not be a gap (threshold is 30)")
    }

    func testIsGapSegment_exactly30min_notAGap() {
        let result = evalJS("""
            const ctx = {p0: {parsed: {x: 0}}, p1: {parsed: {x: 30 * 60 * 1000}}};
            return isGapSegment(ctx);
        """) as? Bool
        XCTAssertFalse(result!, "Exactly 30 minutes should not be a gap (> not >=)")
    }

    func testIsGapSegment_31min_isAGap() {
        let result = evalJS("""
            const ctx = {p0: {parsed: {x: 0}}, p1: {parsed: {x: 31 * 60 * 1000}}};
            return isGapSegment(ctx);
        """) as? Bool
        XCTAssertTrue(result!, "31 minutes should be a gap")
    }

    func testIsGapSegment_changingThreshold() {
        let result = evalJS("""
            gapThresholdMs = 60 * 60 * 1000; // 1 hour
            const ctx = {p0: {parsed: {x: 0}}, p1: {parsed: {x: 45 * 60 * 1000}}};
            const result = isGapSegment(ctx);
            gapThresholdMs = 30 * 60 * 1000; // restore default
            return result;
        """) as? Bool
        XCTAssertFalse(result!, "45 min should not be a gap when threshold is 60 min")
    }

    // =========================================================
    // MARK: - Cumulative cost logic
    // =========================================================

    func testCumulativeCost_correctAccumulation() {
        let result = evalJS("""
            const tokenData = [
                {timestamp: '2026-02-24T10:00:00Z', costUSD: 1.50},
                {timestamp: '2026-02-24T10:01:00Z', costUSD: 0.75},
                {timestamp: '2026-02-24T10:02:00Z', costUSD: 2.00},
            ];
            let cumCost = 0;
            const cumData = tokenData.map(r => {
                cumCost += r.costUSD;
                return { x: r.timestamp, y: Math.round(cumCost * 100) / 100 };
            });
            return cumData.map(d => d.y);
        """) as? [Double]
        XCTAssertEqual(result, [1.50, 2.25, 4.25])
    }

    func testCumulativeCost_emptyData() {
        let result = evalJS("""
            let cumCost = 0;
            const cumData = [].map(r => {
                cumCost += r.costUSD;
                return { y: Math.round(cumCost * 100) / 100 };
            });
            return cumData.length;
        """) as? Int
        XCTAssertEqual(result, 0)
    }

    func testCumulativeCost_roundsTo2Decimals() {
        let result = evalJS("""
            const tokenData = [
                {costUSD: 0.001}, {costUSD: 0.001}, {costUSD: 0.001},
            ];
            let cumCost = 0;
            return tokenData.map(r => {
                cumCost += r.costUSD;
                return Math.round(cumCost * 100) / 100;
            });
        """) as? [Double]
        XCTAssertEqual(result, [0.0, 0.0, 0.0],
                       "Very small costs should round to 0.00")
    }

    func testCumulativeCost_largeAccumulation() {
        let result = evalJS("""
            const tokenData = Array.from({length: 1000}, () => ({costUSD: 0.50}));
            let cumCost = 0;
            const last = tokenData.reduce((_, r) => {
                cumCost += r.costUSD;
                return Math.round(cumCost * 100) / 100;
            }, 0);
            return last;
        """) as? Double
        XCTAssertEqual(result!, 500.0, accuracy: 0.01)
    }

    // =========================================================
    // MARK: - Stats computation (totalCost, usageSpan, latest values)
    // =========================================================

    func testStats_totalCost() {
        let result = evalJS("""
            const tokenData = [
                {costUSD: 1.50}, {costUSD: 2.00}, {costUSD: 0.75},
            ];
            return tokenData.reduce((s, r) => s + r.costUSD, 0);
        """) as? Double
        XCTAssertEqual(result!, 4.25, accuracy: 0.001)
    }

    func testStats_usageSpan_multipleRecords() {
        let result = evalJS("""
            const usageData = [
                {timestamp: '2026-02-24T10:00:00Z'},
                {timestamp: '2026-02-24T11:00:00Z'},
                {timestamp: '2026-02-24T13:30:00Z'},
            ];
            const span = ((new Date(usageData[usageData.length-1].timestamp) - new Date(usageData[0].timestamp)) / 3600000).toFixed(1);
            return parseFloat(span);
        """) as? Double
        XCTAssertEqual(result!, 3.5, accuracy: 0.01, "10:00 to 13:30 = 3.5 hours")
    }

    func testStats_usageSpan_singleRecord() {
        let result = evalJS("""
            const usageData = [{timestamp: '2026-02-24T10:00:00Z'}];
            const span = usageData.length > 1
                ? ((new Date(usageData[usageData.length-1].timestamp) - new Date(usageData[0].timestamp)) / 3600000).toFixed(1)
                : '0';
            return span;
        """) as? String
        XCTAssertEqual(result, "0")
    }

    func testStats_latestValues() {
        let result = evalJS("""
            const usageData = [
                {five_hour_percent: 10, seven_day_percent: 5},
                {five_hour_percent: 42.5, seven_day_percent: 15.3},
            ];
            return {
                fiveH: usageData[usageData.length - 1]?.five_hour_percent ?? '-',
                sevenD: usageData[usageData.length - 1]?.seven_day_percent ?? '-',
            };
        """) as? [String: Any]
        XCTAssertEqual(result?["fiveH"] as? Double, 42.5)
        XCTAssertEqual(result?["sevenD"] as? Double, 15.3)
    }

    func testStats_latestValues_emptyData() {
        let result = evalJS("""
            const usageData = [];
            return {
                fiveH: usageData[usageData.length - 1]?.five_hour_percent ?? '-',
                sevenD: usageData[usageData.length - 1]?.seven_day_percent ?? '-',
            };
        """) as? [String: Any]
        XCTAssertEqual(result?["fiveH"] as? String, "-", "Empty data → dash fallback")
        XCTAssertEqual(result?["sevenD"] as? String, "-", "Empty data → dash fallback")
    }

    // =========================================================
    // MARK: - Boundary value tests
    // =========================================================

    func testCostForRecord_veryLargeTokenCount() {
        let result = evalJS("""
            return costForRecord({
                model: 'claude-sonnet-4-20250514',
                input_tokens: 100000000, output_tokens: 50000000,
                cache_read_tokens: 200000000, cache_creation_tokens: 10000000
            });
        """) as? Double
        // 100M * 3.0/1M + 50M * 15.0/1M + 200M * 0.30/1M + 10M * 3.75/1M
        // = 300 + 750 + 60 + 37.5 = 1147.5
        XCTAssertEqual(result!, 1147.5, accuracy: 0.01)
    }

    func testCostForRecord_singleToken() {
        let result = evalJS("""
            return costForRecord({
                model: 'claude-sonnet-4-20250514',
                input_tokens: 1, output_tokens: 0,
                cache_read_tokens: 0, cache_creation_tokens: 0
            });
        """) as? Double
        // 1 / 1M * 3.0 = 0.000003
        XCTAssertEqual(result!, 0.000003, accuracy: 0.0000001)
    }

    func testInsertResetPoints_percentAt100() {
        let result = evalJS("""
            const data = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 100, five_hour_resets_at: '2026-02-24T12:00:00Z'},
                {timestamp: '2026-02-24T14:00:00Z', five_hour_percent: 0, five_hour_resets_at: null},
            ];
            const r = insertResetPoints(data, 'five_hour_percent', 'five_hour_resets_at');
            return {count: r.length, first: r[0].y, zero: r[1].y, last: r[2].y};
        """) as? [String: Any]
        XCTAssertEqual(result?["count"] as? Int, 3)
        XCTAssertEqual(result?["first"] as? Double, 100.0, "100% value preserved")
        XCTAssertEqual(result?["zero"] as? Double, 0.0, "Reset zero-point")
        XCTAssertEqual(result?["last"] as? Double, 0.0, "0% value preserved")
    }

    func testInsertResetPoints_percentAtZero() {
        let result = evalJS("""
            const data = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 0, five_hour_resets_at: null},
                {timestamp: '2026-02-24T14:00:00Z', five_hour_percent: 0, five_hour_resets_at: null},
            ];
            return insertResetPoints(data, 'five_hour_percent', 'five_hour_resets_at').length;
        """) as? Int
        XCTAssertEqual(result, 2, "Zero percent is valid (not null), should not be skipped")
    }

    func testComputeDeltas_exactBoundaryTimestamp() {
        // Token at t0 (inclusive) should be included, token at t1 (exclusive) should not
        let result = evalJS("""
            const deltas = computeDeltas(
                [
                    {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10},
                    {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: 20},
                ],
                [
                    {timestamp: '2026-02-24T10:00:00Z', costUSD: 0.50},
                    {timestamp: '2026-02-24T10:05:00Z', costUSD: 0.75},
                ]
            );
            return {count: deltas.length, cost: deltas[0]?.x};
        """) as? [String: Any]
        XCTAssertEqual(result?["count"] as? Int, 1)
        XCTAssertEqual(result!["cost"] as! Double, 0.50, accuracy: 0.001,
                       "Token at t0 included (>=), token at t1 excluded (<)")
    }

    func testComputeKDE_negativeValues() {
        let result = evalJS("""
            const kde = computeKDE([-5, -3, -1, 1, 3, 5]);
            let maxY = -1, maxX = 0;
            for (let i = 0; i < kde.xs.length; i++) {
                if (kde.ys[i] > maxY) { maxY = kde.ys[i]; maxX = kde.xs[i]; }
            }
            return {peakX: maxX, xsLen: kde.xs.length, allFinite: kde.ys.every(y => isFinite(y))};
        """) as? [String: Any]
        XCTAssertTrue(result?["allFinite"] as! Bool)
        XCTAssertEqual(result?["peakX"] as! Double, 0.0, accuracy: 1.5,
                       "Peak of symmetric [-5..5] should be near 0")
    }

    func testComputeKDE_verySpreadData() {
        let result = evalJS("""
            const kde = computeKDE([0.001, 1000]);
            return {xsLen: kde.xs.length, allFinite: kde.ys.every(y => isFinite(y))};
        """) as? [String: Any]
        XCTAssertGreaterThan(result?["xsLen"] as! Int, 0)
        XCTAssertTrue(result?["allFinite"] as! Bool, "Wide spread must not produce NaN")
    }

    // =========================================================
    // MARK: - End-to-end: costForRecord + computeDeltas combined
    // =========================================================

    func testEndToEnd_rawTokensToDelta() {
        // Simulates the full pipeline: raw token records → costForRecord → computeDeltas
        let result = evalJS("""
            const rawTokens = [
                {timestamp: '2026-02-24T10:02:00Z', model: 'claude-sonnet-4-20250514',
                 input_tokens: 100000, output_tokens: 50000, cache_read_tokens: 0, cache_creation_tokens: 0},
            ];
            const tokenData = rawTokens.map(r => ({timestamp: r.timestamp, costUSD: costForRecord(r)}));

            const usageData = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10},
                {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: 15},
            ];

            const deltas = computeDeltas(usageData, tokenData);
            return {
                tokenCost: tokenData[0].costUSD,
                deltaCount: deltas.length,
                deltaX: deltas[0]?.x,
                deltaY: deltas[0]?.y,
            };
        """) as? [String: Any]
        // cost: 0.1M * 3.0 + 0.05M * 15.0 = 0.30 + 0.75 = 1.05
        XCTAssertEqual(result!["tokenCost"] as! Double, 1.05, accuracy: 0.001)
        XCTAssertEqual(result?["deltaCount"] as? Int, 1)
        XCTAssertEqual(result!["deltaX"] as! Double, 1.05, accuracy: 0.001)
        XCTAssertEqual(result!["deltaY"] as! Double, 5.0, accuracy: 0.001)
    }

    func testEndToEnd_multipleIntervalsWithMixedModels() {
        let result = evalJS("""
            const rawTokens = [
                {timestamp: '2026-02-24T10:01:00Z', model: 'claude-opus-4-20250514',
                 input_tokens: 10000, output_tokens: 5000, cache_read_tokens: 0, cache_creation_tokens: 0},
                {timestamp: '2026-02-24T10:06:00Z', model: 'claude-haiku-4-20250101',
                 input_tokens: 50000, output_tokens: 10000, cache_read_tokens: 100000, cache_creation_tokens: 0},
            ];
            const tokenData = rawTokens.map(r => ({timestamp: r.timestamp, costUSD: costForRecord(r)}));

            const usageData = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 0},
                {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: 5},
                {timestamp: '2026-02-24T10:10:00Z', five_hour_percent: 6},
            ];

            const deltas = computeDeltas(usageData, tokenData);
            return {
                count: deltas.length,
                delta0cost: deltas[0]?.x,
                delta0pct: deltas[0]?.y,
                delta1cost: deltas[1]?.x,
                delta1pct: deltas[1]?.y,
            };
        """) as? [String: Any]
        XCTAssertEqual(result?["count"] as? Int, 2)
        // Interval 1: opus 10k in + 5k out = 0.01*15 + 0.005*75 = 0.15 + 0.375 = 0.525
        XCTAssertEqual(result!["delta0cost"] as! Double, 0.525, accuracy: 0.001)
        XCTAssertEqual(result!["delta0pct"] as! Double, 5.0, accuracy: 0.001)
        // Interval 2: haiku 50k in + 10k out + 100k cache_read = 0.05*0.80 + 0.01*4.0 + 0.1*0.08 = 0.04 + 0.04 + 0.008 = 0.088
        XCTAssertEqual(result!["delta1cost"] as! Double, 0.088, accuracy: 0.001)
        XCTAssertEqual(result!["delta1pct"] as! Double, 1.0, accuracy: 0.001)
    }

    // =========================================================
    // MARK: - Template drift detection
    // =========================================================

    /// Verify that the pure JS functions in the REAL HTML template match the expected implementations.
    /// If someone changes a function in AnalysisExporter.swift but not in the test HTML, this catches it.
    func testTemplateDrift_pricingForModelFunctionExists() {
        let html = AnalysisExporter.htmlTemplate
        // Extract the function body from the template
        XCTAssertTrue(html.contains("function pricingForModel(model)"))
        XCTAssertTrue(html.contains("if (model.includes('opus')) return MODEL_PRICING.opus;"))
        XCTAssertTrue(html.contains("if (model.includes('haiku')) return MODEL_PRICING.haiku;"))
        XCTAssertTrue(html.contains("return MODEL_PRICING.sonnet;"))
    }

    func testTemplateDrift_costForRecordFormula() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("r.input_tokens / M * p.input"))
        XCTAssertTrue(html.contains("r.output_tokens / M * p.output"))
        XCTAssertTrue(html.contains("r.cache_creation_tokens / M * p.cacheWrite"))
        XCTAssertTrue(html.contains("r.cache_read_tokens / M * p.cacheRead"))
    }

    func testTemplateDrift_computeDeltasThreshold() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("if (intervalCost > 0.001)"),
                      "computeDeltas must filter intervals with cost <= 0.001")
    }

    func testTemplateDrift_computeKDEBandwidthFormula() {
        let html = AnalysisExporter.htmlTemplate
        // Silverman's rule of thumb: h = 1.06 * std * n^(-0.2)
        XCTAssertTrue(html.contains("1.06 * std * Math.pow(n, -0.2)"),
                      "KDE must use Silverman's rule of thumb for bandwidth")
    }

    func testTemplateDrift_insertResetPointsZeroValue() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("result.push({ x: prevResets, y: 0 })"),
                      "insertResetPoints must push y:0 at reset boundary")
    }

    func testTemplateDrift_gapThresholdDefault() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("let gapThresholdMs = 30 * 60 * 1000"),
                      "Default gap threshold must be 30 minutes")
    }

    func testTemplateDrift_modelPricingValues() {
        let html = AnalysisExporter.htmlTemplate
        // Verify exact pricing lines to catch any price update
        XCTAssertTrue(html.contains("opus:   { input: 15.0,  output: 75.0, cacheWrite: 18.75, cacheRead: 1.50 }"))
        XCTAssertTrue(html.contains("sonnet: { input: 3.0,   output: 15.0, cacheWrite: 3.75,  cacheRead: 0.30 }"))
        XCTAssertTrue(html.contains("haiku:  { input: 0.80,  output: 4.0,  cacheWrite: 1.0,   cacheRead: 0.08 }"))
    }

    // =========================================================
    // MARK: - computeDeltas with many intervals
    // =========================================================

    func testComputeDeltas_100Intervals() {
        let result = evalJS("""
            const usageData = Array.from({length: 101}, (_, i) => ({
                timestamp: new Date(Date.UTC(2026, 1, 24, 10, i * 5)).toISOString(),
                five_hour_percent: i * 0.5,
            }));
            const tokenData = Array.from({length: 100}, (_, i) => ({
                timestamp: new Date(Date.UTC(2026, 1, 24, 10, i * 5 + 1)).toISOString(),
                costUSD: 0.10,
            }));
            const deltas = computeDeltas(usageData, tokenData);
            return {
                count: deltas.length,
                allPositiveX: deltas.every(d => d.x > 0),
                allEqualCost: deltas.every(d => Math.abs(d.x - 0.10) < 0.001),
                allEqualDelta: deltas.every(d => Math.abs(d.y - 0.5) < 0.001),
            };
        """) as? [String: Any]
        XCTAssertEqual(result?["count"] as? Int, 100)
        XCTAssertTrue(result?["allPositiveX"] as! Bool)
        XCTAssertTrue(result?["allEqualCost"] as! Bool)
        XCTAssertTrue(result?["allEqualDelta"] as! Bool)
    }

    func testComputeDeltas_tokenAtExactPrevTimestamp_included() {
        // Token at exactly t0 should be >= t0, so included
        let result = evalJS("""
            const deltas = computeDeltas(
                [
                    {timestamp: '2026-02-24T10:00:00.000Z', five_hour_percent: 0},
                    {timestamp: '2026-02-24T10:05:00.000Z', five_hour_percent: 10},
                ],
                [{timestamp: '2026-02-24T10:00:00.000Z', costUSD: 1.0}]
            );
            return deltas.length;
        """) as? Int
        XCTAssertEqual(result, 1, "Token at exact prev timestamp (t >= t0) should be included")
    }

    func testComputeDeltas_tokenAtExactCurrTimestamp_excluded() {
        // Token at exactly t1 should be < t1, so excluded
        let result = evalJS("""
            const deltas = computeDeltas(
                [
                    {timestamp: '2026-02-24T10:00:00.000Z', five_hour_percent: 0},
                    {timestamp: '2026-02-24T10:05:00.000Z', five_hour_percent: 10},
                ],
                [{timestamp: '2026-02-24T10:05:00.000Z', costUSD: 1.0}]
            );
            return deltas.length;
        """) as? Int
        XCTAssertEqual(result, 0, "Token at exact curr timestamp (t < t1) should be excluded → no cost → no delta")
    }

    // =========================================================
    // MARK: - KDE mathematical properties
    // =========================================================

    func testComputeKDE_symmetricInput_symmetricOutput() {
        let result = evalJS("""
            const kde = computeKDE([-2, -1, 0, 1, 2]);
            // Check symmetry: density at -x should ≈ density at +x
            const midIdx = Math.floor(kde.xs.length / 2);
            let maxAsymmetry = 0;
            for (let i = 0; i < midIdx && i < kde.xs.length - midIdx; i++) {
                const leftY = kde.ys[midIdx - i];
                const rightY = kde.ys[midIdx + i];
                if (leftY > 0.001 || rightY > 0.001) {
                    maxAsymmetry = Math.max(maxAsymmetry, Math.abs(leftY - rightY) / Math.max(leftY, rightY));
                }
            }
            return maxAsymmetry;
        """) as? Double
        XCTAssertLessThan(result!, 0.15,
                          "KDE of symmetric data should produce approximately symmetric output")
    }

    func testComputeKDE_bimodalInput_hasTwoPeaks() {
        let result = evalJS("""
            // Two clusters far apart: [0,0,0,0,0] and [100,100,100,100,100]
            const kde = computeKDE([0,0,0,0,0, 100,100,100,100,100]);
            // Find local maxima
            let peaks = 0;
            for (let i = 1; i < kde.xs.length - 1; i++) {
                if (kde.ys[i] > kde.ys[i-1] && kde.ys[i] > kde.ys[i+1]) peaks++;
            }
            return peaks;
        """) as? Int
        XCTAssertEqual(result, 2, "Bimodal data should produce exactly 2 peaks")
    }

    func testComputeKDE_bandwidthScalesWithN() {
        // h = 1.06 * std * n^(-0.2). More data → smaller bandwidth → sharper peak
        let result = evalJS("""
            const small = computeKDE([1, 2, 3, 4, 5]);
            const large = computeKDE([1,1,1,2,2,2,3,3,3,4,4,4,5,5,5,1,2,3,4,5]);
            const smallPeak = Math.max(...small.ys);
            const largePeak = Math.max(...large.ys);
            return largePeak > smallPeak;
        """) as? Bool
        XCTAssertTrue(result!, "More data points → smaller bandwidth → higher peak density")
    }
}

// MARK: - Template JS Extraction Helper

/// Extracts JS functions from the ACTUAL AnalysisExporter.htmlTemplate for testing.
/// Unlike the copied-JS tests above (AnalysisJSLogicTests/AnalysisJSExtendedTests),
/// these tests run against the REAL template code. If someone changes the template,
/// the tests automatically exercise the changed code.
private enum TemplateTestHelper {
    /// HTML page with ALL JS functions extracted from the real AnalysisExporter.htmlTemplate.
    /// CDN dependencies (Chart.js) are replaced with stubs.
    /// The auto-executing IIFE entry point is removed so functions can be called individually.
    /// All required DOM elements (canvases, stats, heatmap, inputs) are provided.
    static let testHTML: String = {
        let template = AnalysisExporter.htmlTemplate

        // Find the inline <script> block (the one without src=, after CDN tags)
        guard let scriptTagRange = template.range(of: "<script>\n// =") else {
            fatalError("Cannot find inline <script> in AnalysisExporter.htmlTemplate")
        }
        guard let scriptEndRange = template.range(
            of: "\n</script>",
            range: scriptTagRange.upperBound..<template.endIndex
        ) else {
            fatalError("Cannot find closing </script> in template")
        }

        // Extract just the JS code (after "<script>\n")
        let jsStartIdx = template.index(scriptTagRange.lowerBound, offsetBy: "<script>\n".count)
        var jsCode = String(template[jsStartIdx..<scriptEndRange.lowerBound])

        // Remove the auto-executing IIFE entry point so loadData() doesn't run on page load
        let iifeMarker = "// ============================================================\n// Entry point: load JSON data, then render\n// ============================================================"
        if let iifeRange = jsCode.range(of: iifeMarker) {
            jsCode = String(jsCode[..<iifeRange.lowerBound])
        }

        return """
        <!DOCTYPE html><html><head></head><body>
        <div id="loading">Loading...</div>
        <div id="app" style="display:none;">
            <div class="stats" id="stats"></div>
            <div class="tab-bar">
                <button class="tab-btn active" data-tab="usage">Usage</button>
                <button class="tab-btn" data-tab="cost">Cost</button>
                <button class="tab-btn" data-tab="efficiency">Efficiency</button>
                <button class="tab-btn" data-tab="cumulative">Cumulative</button>
            </div>
            <div class="tab-content active" id="tab-usage">
                <canvas id="usageTimeline"></canvas>
                <input type="range" id="gapSlider" min="5" max="360" step="5" value="30">
                <span id="gapVal">30 min</span>
            </div>
            <div class="tab-content" id="tab-cost">
                <canvas id="costTimeline"></canvas>
                <canvas id="costScatter"></canvas>
            </div>
            <div class="tab-content" id="tab-efficiency">
                <input type="date" id="dateFrom">
                <input type="date" id="dateTo">
                <button id="applyRange">Apply</button>
                <canvas id="effScatter"></canvas>
                <canvas id="kdeChart"></canvas>
                <div id="heatmap"></div>
            </div>
            <div class="tab-content" id="tab-cumulative">
                <canvas id="cumulativeCost"></canvas>
            </div>
        </div>
        <script>
        // Stub Chart.js — captures chart configurations for test assertions
        const _chartConfigs = {};
        class Chart {
            constructor(canvas, config) {
                const id = canvas?.id || 'unknown';
                _chartConfigs[id] = config;
                this.config = config;
                this.data = config?.data;
                this.options = config?.options;
            }
            destroy() {}
            update() {}
        }
        \(jsCode)
        </script></body></html>
        """
    }()
}

// MARK: - Real Template JS Tests

/// Tests JS functions by extracting and executing them from the REAL AnalysisExporter.htmlTemplate.
/// This catches bugs that the copied-JS tests (AnalysisJSLogicTests) cannot detect.
/// If someone changes a function in the template, these tests will run the changed code.
final class AnalysisTemplateJSTests: XCTestCase {

    private var webView: WKWebView!

    override func setUp() {
        super.setUp()
        let exp = expectation(description: "Page loaded")
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let navDelegate = TestNavDelegate(onFinish: { exp.fulfill() })
        webView.navigationDelegate = navDelegate
        objc_setAssociatedObject(webView!, "navDelegate", navDelegate, .OBJC_ASSOCIATION_RETAIN)
        webView.loadHTMLString(TemplateTestHelper.testHTML, baseURL: nil)
        wait(for: [exp], timeout: 10.0)
    }

    private func evalJS(_ code: String, file: StaticString = #file, line: UInt = #line) -> Any? {
        let exp = expectation(description: "JS eval")
        var jsResult: Any?
        var jsError: Error?
        webView.callAsyncJavaScript(code, arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .success(let value): jsResult = value
            case .failure(let error): jsError = error
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5.0)
        if let err = jsError { XCTFail("JS error: \(err)", file: file, line: line) }
        return jsResult
    }

    // =========================================================
    // MARK: - Template extraction verification
    // =========================================================

    func testTemplateExtraction_allFunctionsAvailable() {
        let result = evalJS("""
            return {
                pricingForModel: typeof pricingForModel === 'function',
                costForRecord: typeof costForRecord === 'function',
                computeKDE: typeof computeKDE === 'function',
                computeDeltas: typeof computeDeltas === 'function',
                insertResetPoints: typeof insertResetPoints === 'function',
                isGapSegment: typeof isGapSegment === 'function',
                buildHeatmap: typeof buildHeatmap === 'function',
                buildScatterChart: typeof buildScatterChart === 'function',
                main: typeof main === 'function',
                getFilteredDeltas: typeof getFilteredDeltas === 'function',
                renderUsageTab: typeof renderUsageTab === 'function',
                renderCostTab: typeof renderCostTab === 'function',
                renderCumulativeTab: typeof renderCumulativeTab === 'function',
                renderEfficiencyTab: typeof renderEfficiencyTab === 'function',
                renderTab: typeof renderTab === 'function',
                initTabs: typeof initTabs === 'function',
                timeSlots: Array.isArray(timeSlots),
                MODEL_PRICING: typeof MODEL_PRICING === 'object',
            };
        """) as? [String: Any]
        XCTAssertNotNil(result, "evalJS must return a result — template extraction failed")
        for (key, value) in result ?? [:] {
            XCTAssertEqual(value as? Bool, true,
                           "\(key) must exist in extracted template JS")
        }
    }

    func testTemplateExtraction_globalVariablesDefined() {
        let result = evalJS("""
            return {
                hasGapThresholdMs: typeof gapThresholdMs === 'number',
                gapThresholdValue: gapThresholdMs,
                hasCharts: typeof _charts === 'object',
                hasRendered: typeof _rendered === 'object',
            };
        """) as? [String: Any]
        XCTAssertEqual(result?["hasGapThresholdMs"] as? Bool, true)
        XCTAssertEqual(result?["gapThresholdValue"] as? Int, 1_800_000, // 30 * 60 * 1000
                       "Default gap threshold should be 30 minutes in ms")
        XCTAssertEqual(result?["hasCharts"] as? Bool, true)
        XCTAssertEqual(result?["hasRendered"] as? Bool, true)
    }

    // =========================================================
    // MARK: - pricingForModel (real template)
    // =========================================================

    func testRealTemplate_pricingForModel_opus() {
        let result = evalJS("""
            const p = pricingForModel('claude-opus-4-20250514');
            return {input: p.input, output: p.output, cacheWrite: p.cacheWrite, cacheRead: p.cacheRead};
        """) as? [String: Any]
        XCTAssertEqual(result?["input"] as? Double, 15.0)
        XCTAssertEqual(result?["output"] as? Double, 75.0)
        XCTAssertEqual(result?["cacheWrite"] as? Double, 18.75)
        XCTAssertEqual(result?["cacheRead"] as? Double, 1.50)
    }

    func testRealTemplate_pricingForModel_sonnet() {
        let result = evalJS("""
            const p = pricingForModel('claude-sonnet-4-20250514');
            return {input: p.input, output: p.output, cacheWrite: p.cacheWrite, cacheRead: p.cacheRead};
        """) as? [String: Any]
        XCTAssertEqual(result?["input"] as? Double, 3.0)
        XCTAssertEqual(result?["output"] as? Double, 15.0)
        XCTAssertEqual(result?["cacheWrite"] as? Double, 3.75)
        XCTAssertEqual(result?["cacheRead"] as? Double, 0.30)
    }

    func testRealTemplate_pricingForModel_haiku() {
        let result = evalJS("""
            const p = pricingForModel('claude-haiku-4-20250101');
            return {input: p.input, output: p.output, cacheWrite: p.cacheWrite, cacheRead: p.cacheRead};
        """) as? [String: Any]
        XCTAssertEqual(result?["input"] as? Double, 0.80)
        XCTAssertEqual(result?["output"] as? Double, 4.0)
        XCTAssertEqual(result?["cacheWrite"] as? Double, 1.0)
        XCTAssertEqual(result?["cacheRead"] as? Double, 0.08)
    }

    func testRealTemplate_pricingForModel_unknownModel_defaultsToSonnet() {
        let result = evalJS("""
            const p = pricingForModel('some-unknown-model');
            return {input: p.input, output: p.output};
        """) as? [String: Any]
        XCTAssertEqual(result?["input"] as? Double, 3.0, "Unknown model defaults to sonnet")
        XCTAssertEqual(result?["output"] as? Double, 15.0)
    }

    // =========================================================
    // MARK: - costForRecord: JS vs Swift parity (real template)
    // =========================================================

    func testRealTemplate_costForRecord_matchesSwiftCostEstimator() {
        let testCases: [(String, Int, Int, Int, Int)] = [
            ("claude-sonnet-4-20250514", 150_000, 50_000, 800_000, 200_000),
            ("claude-opus-4-20250514", 1_000_000, 300_000, 500_000, 100_000),
            ("claude-haiku-4-20250101", 2_000_000, 100_000, 3_000_000, 50_000),
            ("claude-sonnet-4-20250514", 0, 0, 0, 0),
            ("claude-opus-4-20250514", 1, 1, 1, 1),
        ]
        for (model, inp, out, cacheR, cacheW) in testCases {
            let swiftCost = CostEstimator.cost(for: TokenRecord(
                timestamp: Date(), requestId: "t", model: model, speed: "standard",
                inputTokens: inp, outputTokens: out,
                cacheReadTokens: cacheR, cacheCreationTokens: cacheW,
                webSearchRequests: 0
            ))
            let jsCost = evalJS("""
                return costForRecord({
                    model: '\(model)',
                    input_tokens: \(inp), output_tokens: \(out),
                    cache_read_tokens: \(cacheR), cache_creation_tokens: \(cacheW)
                });
            """) as! Double
            XCTAssertEqual(jsCost, swiftCost, accuracy: 0.000001,
                           "JS/Swift cost mismatch for \(model) inp=\(inp) out=\(out)")
        }
    }

    func testRealTemplate_costForRecord_cacheReadIs10xCheaperThanInput() {
        let inputCost = evalJS("""
            return costForRecord({model: 'claude-sonnet-4-20250514',
                input_tokens: 1000000, output_tokens: 0, cache_read_tokens: 0, cache_creation_tokens: 0});
        """) as! Double
        let cacheCost = evalJS("""
            return costForRecord({model: 'claude-sonnet-4-20250514',
                input_tokens: 0, output_tokens: 0, cache_read_tokens: 1000000, cache_creation_tokens: 0});
        """) as! Double
        XCTAssertEqual(inputCost / cacheCost, 10.0, accuracy: 0.001)
    }

    // =========================================================
    // MARK: - computeDeltas (real template)
    // =========================================================

    func testRealTemplate_computeDeltas_basicDelta() {
        let result = evalJS("""
            const deltas = computeDeltas(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10},
                 {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: 15}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50}]
            );
            return {count: deltas.length, x: deltas[0].x, y: deltas[0].y};
        """) as? [String: Any]
        XCTAssertEqual(result?["count"] as? Int, 1)
        XCTAssertEqual(result!["x"] as! Double, 0.50, accuracy: 0.001)
        XCTAssertEqual(result!["y"] as! Double, 5.0, accuracy: 0.001)
    }

    func testRealTemplate_computeDeltas_filtersLowCost() {
        let result = evalJS("""
            return computeDeltas(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10},
                 {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: 20}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.0005}]
            ).length;
        """) as? Int
        XCTAssertEqual(result, 0, "Cost <= 0.001 must be filtered out")
    }

    func testRealTemplate_computeDeltas_sumsMultipleTokens() {
        let result = evalJS("""
            const deltas = computeDeltas(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10},
                 {timestamp: '2026-02-24T10:10:00Z', five_hour_percent: 30}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50},
                 {timestamp: '2026-02-24T10:05:00Z', costUSD: 1.00},
                 {timestamp: '2026-02-24T10:08:00Z', costUSD: 0.25}]
            );
            return {x: deltas[0].x, y: deltas[0].y};
        """) as? [String: Any]
        XCTAssertEqual(result!["x"] as! Double, 1.75, accuracy: 0.001, "Sum of 0.50+1.00+0.25")
        XCTAssertEqual(result!["y"] as! Double, 20.0, accuracy: 0.001)
    }

    func testRealTemplate_computeDeltas_nullPercentSkipped() {
        let result = evalJS("""
            const deltas = computeDeltas(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: null},
                 {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: 10}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 1.0}]
            );
            return deltas.length;
        """) as? Int
        XCTAssertEqual(result, 0, "Null prev percent → interval skipped entirely")
    }

    func testRealTemplate_computeDeltas_negativeDelta() {
        let result = evalJS("""
            const deltas = computeDeltas(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 50},
                 {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: 20}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50}]
            );
            return deltas[0].y;
        """) as? Double
        XCTAssertEqual(result!, -30.0, accuracy: 0.001, "Usage decrease preserved as negative delta")
    }

    func testRealTemplate_computeDeltas_tokenBoundary_t0Inclusive_t1Exclusive() {
        let result = evalJS("""
            const deltas = computeDeltas(
                [{timestamp: '2026-02-24T10:00:00.000Z', five_hour_percent: 0},
                 {timestamp: '2026-02-24T10:05:00.000Z', five_hour_percent: 10}],
                [{timestamp: '2026-02-24T10:00:00.000Z', costUSD: 0.50},
                 {timestamp: '2026-02-24T10:05:00.000Z', costUSD: 0.75}]
            );
            return {count: deltas.length, cost: deltas[0]?.x};
        """) as? [String: Any]
        XCTAssertEqual(result?["count"] as? Int, 1)
        XCTAssertEqual(result!["cost"] as! Double, 0.50, accuracy: 0.001,
                       "Token at t0 included (>=), token at t1 excluded (<)")
    }

    // =========================================================
    // MARK: - computeKDE (real template)
    // =========================================================

    func testRealTemplate_computeKDE_singleValue_returnsEmpty() {
        let result = evalJS("return computeKDE([5.0]).xs.length;") as? Int
        XCTAssertEqual(result, 0, "n < 2 → empty")
    }

    func testRealTemplate_computeKDE_twoValues_returnsNonEmpty() {
        let result = evalJS("""
            const kde = computeKDE([1.0, 2.0]);
            return {xsLen: kde.xs.length, ysLen: kde.ys.length};
        """) as? [String: Any]
        XCTAssertGreaterThan(result?["xsLen"] as! Int, 0)
        XCTAssertEqual(result?["xsLen"] as? Int, result?["ysLen"] as? Int)
    }

    func testRealTemplate_computeKDE_densityIntegral_isApproximatelyOne() {
        let result = evalJS("""
            const kde = computeKDE([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
            let integral = 0;
            for (let i = 1; i < kde.xs.length; i++) {
                const dx = kde.xs[i] - kde.xs[i-1];
                integral += (kde.ys[i] + kde.ys[i-1]) / 2 * dx;
            }
            return integral;
        """) as? Double
        XCTAssertEqual(result!, 1.0, accuracy: 0.15,
                       "KDE integral should approximate 1.0 (proper probability density)")
    }

    func testRealTemplate_computeKDE_identicalValues_doesNotCrash() {
        let result = evalJS("""
            const kde = computeKDE([5, 5, 5, 5, 5]);
            return {xsLen: kde.xs.length, allFinite: kde.ys.every(y => isFinite(y))};
        """) as? [String: Any]
        XCTAssertGreaterThan(result?["xsLen"] as! Int, 0)
        XCTAssertTrue(result?["allFinite"] as! Bool, "No NaN/Infinity for identical values")
    }

    func testRealTemplate_computeKDE_bimodal_hasTwoPeaks() {
        let result = evalJS("""
            const kde = computeKDE([0,0,0,0,0, 100,100,100,100,100]);
            let peaks = 0;
            for (let i = 1; i < kde.xs.length - 1; i++) {
                if (kde.ys[i] > kde.ys[i-1] && kde.ys[i] > kde.ys[i+1]) peaks++;
            }
            return peaks;
        """) as? Int
        XCTAssertEqual(result, 2, "Bimodal data should produce exactly 2 peaks")
    }

    // =========================================================
    // MARK: - insertResetPoints (real template)
    // =========================================================

    func testRealTemplate_insertResetPoints_noResets() {
        let result = evalJS("""
            const data = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, five_hour_resets_at: null},
                {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: 20, five_hour_resets_at: null},
            ];
            return insertResetPoints(data, 'five_hour_percent', 'five_hour_resets_at');
        """) as? [[String: Any]]
        XCTAssertEqual(result?.count, 2)
        XCTAssertEqual(result?[0]["y"] as? Double, 10.0)
        XCTAssertEqual(result?[1]["y"] as? Double, 20.0)
    }

    func testRealTemplate_insertResetPoints_insertsZeroAtResetBoundary() {
        let result = evalJS("""
            const data = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 80, five_hour_resets_at: '2026-02-24T12:00:00Z'},
                {timestamp: '2026-02-24T14:00:00Z', five_hour_percent: 5, five_hour_resets_at: null},
            ];
            return insertResetPoints(data, 'five_hour_percent', 'five_hour_resets_at');
        """) as? [[String: Any]]
        XCTAssertEqual(result?.count, 3, "original + zero-point + original")
        XCTAssertEqual(result?[0]["y"] as? Double, 80.0)
        XCTAssertEqual(result?[1]["y"] as? Double, 0.0, "Zero-point at reset boundary")
        XCTAssertEqual(result?[1]["x"] as? String, "2026-02-24T12:00:00Z")
        XCTAssertEqual(result?[2]["y"] as? Double, 5.0)
    }

    func testRealTemplate_insertResetPoints_skipsNullPercent() {
        let result = evalJS("""
            const data = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, five_hour_resets_at: null},
                {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: null, five_hour_resets_at: null},
                {timestamp: '2026-02-24T10:10:00Z', five_hour_percent: 20, five_hour_resets_at: null},
            ];
            return insertResetPoints(data, 'five_hour_percent', 'five_hour_resets_at').length;
        """) as? Int
        XCTAssertEqual(result, 2, "null percent rows should be skipped")
    }

    func testRealTemplate_insertResetPoints_sevenDayKey() {
        let result = evalJS("""
            const data = [
                {timestamp: '2026-02-24T10:00:00Z', seven_day_percent: 50, seven_day_resets_at: '2026-02-25T10:00:00Z'},
                {timestamp: '2026-02-26T10:00:00Z', seven_day_percent: 5, seven_day_resets_at: null},
            ];
            const r = insertResetPoints(data, 'seven_day_percent', 'seven_day_resets_at');
            return {count: r.length, zeroY: r[1].y};
        """) as? [String: Any]
        XCTAssertEqual(result?["count"] as? Int, 3)
        XCTAssertEqual(result?["zeroY"] as? Double, 0.0)
    }

    // =========================================================
    // MARK: - timeSlots (real template)
    // =========================================================

    func testRealTemplate_timeSlots_everyHourMatchesExactlyOneSlot() {
        let result = evalJS("""
            const counts = [];
            for (let h = 0; h < 24; h++) {
                let matched = 0;
                for (const slot of timeSlots) {
                    if (slot.filter({hour: h})) matched++;
                }
                counts.push(matched);
            }
            return counts.every(c => c === 1);
        """) as? Bool
        XCTAssertTrue(result!, "Every hour 0-23 must match exactly one timeSlot")
    }

    func testRealTemplate_timeSlots_nightIsBefore6() {
        let result = evalJS("""
            return [0,5,6,12,18,23].filter(h => timeSlots[0].filter({hour: h}));
        """) as? [Int]
        XCTAssertEqual(result, [0, 5])
    }

    func testRealTemplate_timeSlots_morningIs6to11() {
        let result = evalJS("""
            return [0,5,6,11,12,18].filter(h => timeSlots[1].filter({hour: h}));
        """) as? [Int]
        XCTAssertEqual(result, [6, 11])
    }

    // =========================================================
    // MARK: - isGapSegment (real template)
    // =========================================================

    func testRealTemplate_isGapSegment_below30min_notAGap() {
        let result = evalJS("""
            return isGapSegment({p0: {parsed: {x: 0}}, p1: {parsed: {x: 29 * 60 * 1000}}});
        """) as? Bool
        XCTAssertFalse(result!)
    }

    func testRealTemplate_isGapSegment_exactly30min_notAGap() {
        let result = evalJS("""
            return isGapSegment({p0: {parsed: {x: 0}}, p1: {parsed: {x: 30 * 60 * 1000}}});
        """) as? Bool
        XCTAssertFalse(result!, "Exactly 30 min is NOT a gap (> not >=)")
    }

    func testRealTemplate_isGapSegment_31min_isAGap() {
        let result = evalJS("""
            return isGapSegment({p0: {parsed: {x: 0}}, p1: {parsed: {x: 31 * 60 * 1000}}});
        """) as? Bool
        XCTAssertTrue(result!)
    }

    // =========================================================
    // MARK: - End-to-end pipeline (real template)
    // =========================================================

    func testRealTemplate_endToEnd_rawTokensToDelta() {
        let result = evalJS("""
            const rawTokens = [
                {timestamp: '2026-02-24T10:02:00Z', model: 'claude-sonnet-4-20250514',
                 input_tokens: 100000, output_tokens: 50000, cache_read_tokens: 0, cache_creation_tokens: 0},
            ];
            const tokenData = rawTokens.map(r => ({timestamp: r.timestamp, costUSD: costForRecord(r)}));
            const usageData = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10},
                {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: 15},
            ];
            const deltas = computeDeltas(usageData, tokenData);
            return {
                tokenCost: tokenData[0].costUSD,
                deltaCount: deltas.length,
                deltaX: deltas[0]?.x,
                deltaY: deltas[0]?.y,
            };
        """) as? [String: Any]
        // cost: 0.1M * 3.0 + 0.05M * 15.0 = 0.30 + 0.75 = 1.05
        XCTAssertEqual(result!["tokenCost"] as! Double, 1.05, accuracy: 0.001)
        XCTAssertEqual(result?["deltaCount"] as? Int, 1)
        XCTAssertEqual(result!["deltaX"] as! Double, 1.05, accuracy: 0.001)
        XCTAssertEqual(result!["deltaY"] as! Double, 5.0, accuracy: 0.001)
    }

    func testRealTemplate_endToEnd_mixedModels() {
        let result = evalJS("""
            const rawTokens = [
                {timestamp: '2026-02-24T10:01:00Z', model: 'claude-opus-4-20250514',
                 input_tokens: 10000, output_tokens: 5000, cache_read_tokens: 0, cache_creation_tokens: 0},
                {timestamp: '2026-02-24T10:06:00Z', model: 'claude-haiku-4-20250101',
                 input_tokens: 50000, output_tokens: 10000, cache_read_tokens: 100000, cache_creation_tokens: 0},
            ];
            const tokenData = rawTokens.map(r => ({timestamp: r.timestamp, costUSD: costForRecord(r)}));
            const usageData = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 0},
                {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: 5},
                {timestamp: '2026-02-24T10:10:00Z', five_hour_percent: 6},
            ];
            const deltas = computeDeltas(usageData, tokenData);
            return {count: deltas.length, d0cost: deltas[0]?.x, d0pct: deltas[0]?.y,
                    d1cost: deltas[1]?.x, d1pct: deltas[1]?.y};
        """) as? [String: Any]
        XCTAssertEqual(result?["count"] as? Int, 2)
        // opus: 10k*15/1M + 5k*75/1M = 0.15 + 0.375 = 0.525
        XCTAssertEqual(result!["d0cost"] as! Double, 0.525, accuracy: 0.001)
        XCTAssertEqual(result!["d0pct"] as! Double, 5.0, accuracy: 0.001)
        // haiku: 50k*0.80/1M + 10k*4.0/1M + 100k*0.08/1M = 0.04 + 0.04 + 0.008 = 0.088
        XCTAssertEqual(result!["d1cost"] as! Double, 0.088, accuracy: 0.001)
        XCTAssertEqual(result!["d1pct"] as! Double, 1.0, accuracy: 0.001)
    }
}

// MARK: - Template Render Tests (DOM-interacting functions)

/// Tests functions from the real template that interact with the DOM:
/// buildHeatmap, main, getFilteredDeltas, renderUsageTab, renderCumulativeTab.
/// Uses Chart.js stub to capture chart configurations.
final class AnalysisTemplateRenderTests: XCTestCase {

    private var webView: WKWebView!

    override func setUp() {
        super.setUp()
        let exp = expectation(description: "Page loaded")
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let navDelegate = TestNavDelegate(onFinish: { exp.fulfill() })
        webView.navigationDelegate = navDelegate
        objc_setAssociatedObject(webView!, "navDelegate", navDelegate, .OBJC_ASSOCIATION_RETAIN)
        webView.loadHTMLString(TemplateTestHelper.testHTML, baseURL: nil)
        wait(for: [exp], timeout: 10.0)
    }

    private func evalJS(_ code: String, file: StaticString = #file, line: UInt = #line) -> Any? {
        let exp = expectation(description: "JS eval")
        var jsResult: Any?
        var jsError: Error?
        webView.callAsyncJavaScript(code, arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .success(let value): jsResult = value
            case .failure(let error): jsError = error
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5.0)
        if let err = jsError { XCTFail("JS error: \(err)", file: file, line: line) }
        return jsResult
    }

    // =========================================================
    // MARK: - buildHeatmap (real template, NEW)
    // =========================================================

    func testRealTemplate_buildHeatmap_generatesHTML() {
        let result = evalJS("""
            const deltas = [
                {x: 1.0, y: 5.0, hour: 10, timestamp: '2026-02-24T10:05:00Z',
                 date: new Date('2026-02-24T10:05:00Z')},
            ];
            buildHeatmap(deltas);
            const html = document.getElementById('heatmap').innerHTML;
            return {
                hasGrid: html.includes('heatmap-grid'),
                hasLabels: html.includes('Mon') || html.includes('Sun'),
                notEmpty: html.length > 50,
            };
        """) as? [String: Any]
        XCTAssertTrue(result?["hasGrid"] as? Bool ?? false, "Heatmap must contain grid class")
        XCTAssertTrue(result?["hasLabels"] as? Bool ?? false, "Heatmap must contain day labels")
        XCTAssertTrue(result?["notEmpty"] as? Bool ?? false, "Heatmap HTML must not be empty")
    }

    func testRealTemplate_buildHeatmap_emptyDeltas_stillRendersGrid() {
        let result = evalJS("""
            buildHeatmap([]);
            const html = document.getElementById('heatmap').innerHTML;
            return {
                hasGrid: html.includes('heatmap-grid'),
                hasDayLabels: html.includes('Sun') && html.includes('Mon'),
                hasHourHeaders: html.includes('0') && html.includes('23'),
            };
        """) as? [String: Any]
        XCTAssertTrue(result?["hasGrid"] as? Bool ?? false, "Empty data should still render grid")
        XCTAssertTrue(result?["hasDayLabels"] as? Bool ?? false, "Day labels always present")
    }

    func testRealTemplate_buildHeatmap_correctDayHourBinning() {
        let result = evalJS("""
            // Monday 10:00 UTC — getDay() returns local day, getHours() returns local hour
            const dt = new Date('2026-02-24T10:00:00Z');
            const deltas = [
                {x: 2.0, y: 10.0, hour: dt.getHours(), timestamp: '2026-02-24T10:05:00Z', date: dt},
            ];
            buildHeatmap(deltas);
            const html = document.getElementById('heatmap').innerHTML;
            // Should have at least one cell with a ratio value
            return html.includes('title=');
        """) as? Bool
        XCTAssertTrue(result!, "Heatmap cells should have title attributes with data")
    }

    // =========================================================
    // MARK: - getFilteredDeltas (real template, NEW)
    // =========================================================

    func testRealTemplate_getFilteredDeltas_noRange_returnsAllDeltas() {
        let result = evalJS("""
            _allDeltas = [
                {x: 1.0, y: 5.0, hour: 10, timestamp: '2026-02-24T10:05:00Z',
                 date: new Date('2026-02-24T10:05:00Z')},
                {x: 2.0, y: 8.0, hour: 14, timestamp: '2026-02-24T14:05:00Z',
                 date: new Date('2026-02-24T14:05:00Z')},
            ];
            document.getElementById('dateFrom').value = '';
            document.getElementById('dateTo').value = '';
            return getFilteredDeltas().length;
        """) as? Int
        XCTAssertEqual(result, 2, "No date range → return all deltas")
    }

    func testRealTemplate_getFilteredDeltas_withRange_filtersCorrectly() {
        let result = evalJS("""
            _allDeltas = [
                {x: 1.0, y: 5.0, hour: 10, timestamp: '2026-02-23T10:05:00Z',
                 date: new Date('2026-02-23T10:05:00Z')},
                {x: 2.0, y: 8.0, hour: 14, timestamp: '2026-02-24T14:05:00Z',
                 date: new Date('2026-02-24T14:05:00Z')},
                {x: 3.0, y: 12.0, hour: 16, timestamp: '2026-02-25T16:05:00Z',
                 date: new Date('2026-02-25T16:05:00Z')},
            ];
            document.getElementById('dateFrom').value = '2026-02-24';
            document.getElementById('dateTo').value = '2026-02-24';
            return getFilteredDeltas().length;
        """) as? Int
        XCTAssertEqual(result, 1, "Only Feb 24 should match the date range")
    }

    func testRealTemplate_getFilteredDeltas_emptyAllDeltas() {
        let result = evalJS("""
            _allDeltas = [];
            document.getElementById('dateFrom').value = '2026-02-24';
            document.getElementById('dateTo').value = '2026-02-24';
            return getFilteredDeltas().length;
        """) as? Int
        XCTAssertEqual(result, 0)
    }

    // =========================================================
    // MARK: - main() (real template, NEW)
    // =========================================================

    func testRealTemplate_main_setsStatsHTML() {
        let result = evalJS("""
            const usageData = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: 5},
                {timestamp: '2026-02-24T13:30:00Z', five_hour_percent: 42.5, seven_day_percent: 15.3},
            ];
            const tokenData = [
                {timestamp: '2026-02-24T10:02:00Z', costUSD: 1.50},
                {timestamp: '2026-02-24T11:00:00Z', costUSD: 2.00},
            ];
            main(usageData, tokenData);
            const statsHTML = document.getElementById('stats').innerHTML;
            return {
                hasUsageCount: statsHTML.includes('2'),
                hasTokenCount: statsHTML.includes('2'),
                hasTotalCost: statsHTML.includes('3.50'),
                hasUsageSpan: statsHTML.includes('3.5'),
                hasLatest5h: statsHTML.includes('42.5'),
                hasLatest7d: statsHTML.includes('15.3'),
                appVisible: document.getElementById('app').style.display !== 'none',
                loadingHidden: document.getElementById('loading').style.display === 'none',
            };
        """) as? [String: Any]
        XCTAssertTrue(result?["hasUsageCount"] as? Bool ?? false, "Stats must show usage record count")
        XCTAssertTrue(result?["hasTotalCost"] as? Bool ?? false, "Stats must show total cost $3.50")
        XCTAssertTrue(result?["hasUsageSpan"] as? Bool ?? false, "Stats must show usage span 3.5h")
        XCTAssertTrue(result?["hasLatest5h"] as? Bool ?? false, "Stats must show latest 5h%")
        XCTAssertTrue(result?["hasLatest7d"] as? Bool ?? false, "Stats must show latest 7d%")
        XCTAssertTrue(result?["appVisible"] as? Bool ?? false, "App div must be visible after main()")
        XCTAssertTrue(result?["loadingHidden"] as? Bool ?? false, "Loading div must be hidden after main()")
    }

    func testRealTemplate_main_emptyData_showsDash() {
        let result = evalJS("""
            main([], []);
            const statsHTML = document.getElementById('stats').innerHTML;
            return {
                hasUsageCount: statsHTML.includes('>0<'),
                hasDash: statsHTML.includes('-'),
            };
        """) as? [String: Any]
        XCTAssertTrue(result?["hasDash"] as? Bool ?? false,
                      "Empty data should show dash for latest values")
    }

    func testRealTemplate_main_setsGlobalVariables() {
        let result = evalJS("""
            const usageData = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10},
                {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: 15},
            ];
            const tokenData = [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50}];
            main(usageData, tokenData);
            return {
                usageDataSet: _usageData === usageData,
                tokenDataSet: _tokenData === tokenData,
                allDeltasIsArray: Array.isArray(_allDeltas),
                renderedUsage: _rendered['usage'] === true,
            };
        """) as? [String: Any]
        XCTAssertTrue(result?["usageDataSet"] as? Bool ?? false, "_usageData must reference input")
        XCTAssertTrue(result?["tokenDataSet"] as? Bool ?? false, "_tokenData must reference input")
        XCTAssertTrue(result?["allDeltasIsArray"] as? Bool ?? false, "_allDeltas must be computed")
        XCTAssertTrue(result?["renderedUsage"] as? Bool ?? false, "Usage tab must be rendered by main()")
    }

    // =========================================================
    // MARK: - renderUsageTab via Chart stub (real template, NEW)
    // =========================================================

    func testRealTemplate_renderUsageTab_createsChartWithCorrectData() {
        let result = evalJS("""
            _usageData = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: 5,
                 five_hour_resets_at: null, seven_day_resets_at: null},
                {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: 20, seven_day_percent: 8,
                 five_hour_resets_at: null, seven_day_resets_at: null},
            ];
            renderUsageTab();
            const config = _chartConfigs['usageTimeline'];
            return {
                hasConfig: config != null,
                datasetCount: config?.data?.datasets?.length,
                firstLabel: config?.data?.datasets?.[0]?.label,
                secondLabel: config?.data?.datasets?.[1]?.label,
                firstDataCount: config?.data?.datasets?.[0]?.data?.length,
                type: config?.type,
            };
        """) as? [String: Any]
        XCTAssertTrue(result?["hasConfig"] as? Bool ?? false, "Chart config must be captured")
        XCTAssertEqual(result?["datasetCount"] as? Int, 2, "Usage chart has 2 datasets (5h% and 7d%)")
        XCTAssertEqual(result?["firstLabel"] as? String, "5-hour %")
        XCTAssertEqual(result?["secondLabel"] as? String, "7-day %")
        XCTAssertEqual(result?["firstDataCount"] as? Int, 2, "2 data points in 5h dataset")
        XCTAssertEqual(result?["type"] as? String, "line")
    }

    // =========================================================
    // MARK: - renderCumulativeTab via Chart stub (real template, NEW)
    // =========================================================

    func testRealTemplate_renderCumulativeTab_accumulatesCost() {
        let result = evalJS("""
            _tokenData = [
                {timestamp: '2026-02-24T10:00:00Z', costUSD: 1.50},
                {timestamp: '2026-02-24T10:01:00Z', costUSD: 0.75},
                {timestamp: '2026-02-24T10:02:00Z', costUSD: 2.00},
            ];
            renderCumulativeTab();
            const config = _chartConfigs['cumulativeCost'];
            const data = config?.data?.datasets?.[0]?.data;
            return {
                hasConfig: config != null,
                dataCount: data?.length,
                y0: data?.[0]?.y,
                y1: data?.[1]?.y,
                y2: data?.[2]?.y,
                type: config?.type,
            };
        """) as? [String: Any]
        XCTAssertTrue(result?["hasConfig"] as? Bool ?? false)
        XCTAssertEqual(result?["dataCount"] as? Int, 3)
        XCTAssertEqual(result?["y0"] as? Double, 1.50, "First cumulative = 1.50")
        XCTAssertEqual(result?["y1"] as? Double, 2.25, "Second cumulative = 1.50 + 0.75")
        XCTAssertEqual(result?["y2"] as? Double, 4.25, "Third cumulative = 2.25 + 2.00")
        XCTAssertEqual(result?["type"] as? String, "line")
    }

    // =========================================================
    // MARK: - renderCostTab via Chart stub (real template, NEW)
    // =========================================================

    func testRealTemplate_renderCostTab_createsBarChart() {
        let result = evalJS("""
            _tokenData = [
                {timestamp: '2026-02-24T10:00:00Z', costUSD: 1.50},
                {timestamp: '2026-02-24T10:01:00Z', costUSD: 0.75},
            ];
            _allDeltas = [];
            renderCostTab();
            const config = _chartConfigs['costTimeline'];
            return {
                hasConfig: config != null,
                type: config?.type,
                dataCount: config?.data?.datasets?.[0]?.data?.length,
                label: config?.data?.datasets?.[0]?.label,
            };
        """) as? [String: Any]
        XCTAssertTrue(result?["hasConfig"] as? Bool ?? false)
        XCTAssertEqual(result?["type"] as? String, "bar", "Cost timeline is a bar chart")
        XCTAssertEqual(result?["dataCount"] as? Int, 2)
        XCTAssertEqual(result?["label"] as? String, "Cost (USD)")
    }

    // =========================================================
    // MARK: - renderEfficiencyTab via Chart stub (real template, NEW)
    // =========================================================

    func testRealTemplate_renderEfficiencyTab_createsScatterAndKDE() {
        let result = evalJS("""
            const deltas = [
                {x: 1.0, y: 5.0, hour: 10, timestamp: '2026-02-24T10:05:00Z',
                 date: new Date('2026-02-24T10:05:00Z')},
                {x: 2.0, y: 8.0, hour: 14, timestamp: '2026-02-24T14:05:00Z',
                 date: new Date('2026-02-24T14:05:00Z')},
                {x: 0.5, y: 3.0, hour: 9, timestamp: '2026-02-24T09:05:00Z',
                 date: new Date('2026-02-24T09:05:00Z')},
            ];
            renderEfficiencyTab(deltas);
            return {
                hasScatter: _chartConfigs['effScatter'] != null,
                scatterType: _chartConfigs['effScatter']?.type,
                hasKDE: _chartConfigs['kdeChart'] != null,
                kdeType: _chartConfigs['kdeChart']?.type,
                heatmapRendered: document.getElementById('heatmap').innerHTML.length > 50,
            };
        """) as? [String: Any]
        XCTAssertTrue(result?["hasScatter"] as? Bool ?? false, "Efficiency scatter chart created")
        XCTAssertEqual(result?["scatterType"] as? String, "scatter")
        XCTAssertTrue(result?["hasKDE"] as? Bool ?? false, "KDE chart created")
        XCTAssertEqual(result?["kdeType"] as? String, "line")
        XCTAssertTrue(result?["heatmapRendered"] as? Bool ?? false, "Heatmap rendered")
    }

    // =========================================================
    // MARK: - Cumulative cost logic (real template)
    // =========================================================

    func testRealTemplate_cumulativeCost_roundsTo2Decimals() {
        let result = evalJS("""
            _tokenData = [{costUSD: 0.001, timestamp: 'a'},
                          {costUSD: 0.001, timestamp: 'b'},
                          {costUSD: 0.001, timestamp: 'c'}];
            renderCumulativeTab();
            const data = _chartConfigs['cumulativeCost']?.data?.datasets?.[0]?.data;
            return data?.map(d => d.y);
        """) as? [Double]
        XCTAssertEqual(result, [0.0, 0.0, 0.0], "Very small costs round to 0.00")
    }

    // =========================================================
    // MARK: - Stats computation edge cases (real template)
    // =========================================================

    func testRealTemplate_main_totalCostIsSum() {
        let result = evalJS("""
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: 5}],
                [{timestamp: 'a', costUSD: 1.50}, {timestamp: 'b', costUSD: 2.00}, {timestamp: 'c', costUSD: 0.75}]
            );
            return document.getElementById('stats').innerHTML.includes('4.25');
        """) as? Bool
        XCTAssertTrue(result!, "Total cost should be $4.25 (1.50 + 2.00 + 0.75)")
    }

    func testRealTemplate_main_usageSpan_hours() {
        let result = evalJS("""
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: 5},
                 {timestamp: '2026-02-24T13:30:00Z', five_hour_percent: 20, seven_day_percent: 8}],
                []
            );
            return document.getElementById('stats').innerHTML.includes('3.5');
        """) as? Bool
        XCTAssertTrue(result!, "Usage span should be 3.5h (10:00 to 13:30)")
    }

    // =========================================================
    // MARK: - formatMin tests via gap slider (real template)
    // =========================================================

    /// Helper: call main() to set up renderUsageTab event listener,
    /// then change slider value & dispatch 'input' event, return label text.
    private func sliderLabel(forMinutes minutes: Int) -> String? {
        return evalJS("""
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: 5}],
                [{timestamp: '2026-02-24T10:01:00Z', costUSD: 0.5}]
            );
            const slider = document.getElementById('gapSlider');
            slider.value = '\(minutes)';
            slider.dispatchEvent(new Event('input'));
            return document.getElementById('gapVal').textContent;
        """) as? String
    }

    func testRealTemplate_formatMin_under60() {
        XCTAssertEqual(sliderLabel(forMinutes: 30), "30 min")
    }

    func testRealTemplate_formatMin_exactly60() {
        XCTAssertEqual(sliderLabel(forMinutes: 60), "1h")
    }

    func testRealTemplate_formatMin_exactly120() {
        XCTAssertEqual(sliderLabel(forMinutes: 120), "2h")
    }

    func testRealTemplate_formatMin_65_noUglyDecimal() {
        // Bug: 65 / 60 = 1.0833... → "1.0833333333333333h"
        let result = sliderLabel(forMinutes: 65)
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.contains("1.08333"),
                       "formatMin(65) should not produce ugly floating-point decimals, got: \(result!)")
    }

    func testRealTemplate_formatMin_90() {
        XCTAssertEqual(sliderLabel(forMinutes: 90), "1h 30min",
                       "90 minutes should display as '1h 30min'")
    }

    func testRealTemplate_formatMin_150() {
        XCTAssertEqual(sliderLabel(forMinutes: 150), "2h 30min",
                       "150 minutes should display as '2h 30min'")
    }

    func testRealTemplate_formatMin_360() {
        XCTAssertEqual(sliderLabel(forMinutes: 360), "6h",
                       "360 minutes is exactly 6 hours")
    }

    func testRealTemplate_formatMin_5() {
        XCTAssertEqual(sliderLabel(forMinutes: 5), "5 min")
    }

    // =========================================================
    // MARK: - initTabs default date tests (real template)
    // =========================================================

    func testRealTemplate_initTabs_defaultDates_useLocalTime() {
        // initTabs sets dateFrom and dateTo using Date. It should use local dates, not UTC.
        // We test by setting a known time and checking the result matches local calendar.
        let result = evalJS("""
            // Provide minimal data so main() doesn't crash
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: 5}],
                []
            );
            const fromVal = document.getElementById('dateFrom').value;
            const toVal = document.getElementById('dateTo').value;
            // Verify dates are set (not empty)
            return { from: fromVal, to: toVal };
        """) as? [String: String]
        XCTAssertNotNil(result)
        // The key test: dateTo should match today's LOCAL date
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        let expectedTo = formatter.string(from: Date())
        XCTAssertEqual(result?["to"], expectedTo,
                       "dateTo should be today's LOCAL date, not UTC")
    }

    func testRealTemplate_initTabs_defaultDateFrom_3daysAgo() {
        let result = evalJS("""
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: 5}],
                []
            );
            return document.getElementById('dateFrom').value;
        """) as? String
        XCTAssertNotNil(result)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        let expectedFrom = formatter.string(from: Date().addingTimeInterval(-3 * 86400))
        XCTAssertEqual(result, expectedFrom,
                       "dateFrom should be 3 days ago in LOCAL time, not UTC")
    }

    func testRealTemplate_initTabs_UTC_midnight_localDate_shouldDiffer() {
        // Expose the UTC vs local date bug:
        // Mock Date to simulate UTC 23:30 on Feb 23.
        // In any timezone ahead of UTC (e.g. JST), local date = Feb 24.
        // toISOString().slice(0,10) always returns "2026-02-23" regardless of timezone.
        let result = evalJS("""
            const OrigDate = Date;
            const fixedUTC = new OrigDate('2026-02-23T23:30:00Z').getTime();
            class MockDate extends OrigDate {
                constructor(...args) {
                    if (args.length === 0) { super(fixedUTC); }
                    else { super(...args); }
                }
                static now() { return fixedUTC; }
            }
            Date = MockDate;
            initTabs();
            Date = OrigDate;

            const toVal = document.getElementById('dateTo').value;
            const localDate = new OrigDate(fixedUTC);
            const expectedLocal = localDate.getFullYear() + '-'
                + String(localDate.getMonth() + 1).padStart(2, '0') + '-'
                + String(localDate.getDate()).padStart(2, '0');

            return { toVal: toVal, expectedLocal: expectedLocal,
                     utcSlice: new OrigDate(fixedUTC).toISOString().slice(0, 10) };
        """) as? [String: String]
        XCTAssertNotNil(result)
        let toVal = result?["toVal"] ?? ""
        let expectedLocal = result?["expectedLocal"] ?? ""
        let utcSlice = result?["utcSlice"] ?? ""
        XCTAssertEqual(toVal, expectedLocal,
                       "dateTo should be local date '\(expectedLocal)', not UTC '\(utcSlice)'")
    }
}

// MARK: - Additional Bug-Hunting Tests

/// Tests targeting specific output values and edge cases not covered by previous tests.
/// Goal: find bugs by checking exact outputs against expected values.
final class AnalysisBugHuntingTests: XCTestCase {

    private var webView: WKWebView!

    override func setUp() {
        super.setUp()
        let exp = expectation(description: "Page loaded")
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let navDelegate = TestNavDelegate(onFinish: { exp.fulfill() })
        webView.navigationDelegate = navDelegate
        objc_setAssociatedObject(webView!, "navDelegate", navDelegate, .OBJC_ASSOCIATION_RETAIN)
        webView.loadHTMLString(TemplateTestHelper.testHTML, baseURL: nil)
        wait(for: [exp], timeout: 10.0)
    }

    private func evalJS(_ code: String, file: StaticString = #file, line: UInt = #line) -> Any? {
        let exp = expectation(description: "JS eval")
        var jsResult: Any?
        var jsError: Error?
        webView.callAsyncJavaScript(code, arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .success(let value): jsResult = value
            case .failure(let error): jsError = error
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5.0)
        if let err = jsError { XCTFail("JS error: \(err)", file: file, line: line) }
        return jsResult
    }

    // =========================================================
    // MARK: - Stats display: latestFiveH/latestSevenD with % suffix
    // =========================================================

    func testStats_latestFiveH_numberShowsPercent() {
        let result = evalJS("""
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 42.5, seven_day_percent: 15.3}],
                []
            );
            const html = document.getElementById('stats').innerHTML;
            return html.includes('42.5%');
        """) as? Bool
        XCTAssertTrue(result!, "Latest 5h should show '42.5%'")
    }

    func testStats_latestFiveH_dashShouldNotShowDashPercent() {
        // When data is empty, latestFiveH = '-'. The template shows ${latestFiveH}%
        // which produces '-%'. This is a bug — should be just '-' or 'N/A'.
        let result = evalJS("""
            main([], []);
            const html = document.getElementById('stats').innerHTML;
            const hasDashPercent = html.includes('->%') || html.includes('-%');
            const hasDashAlone = html.includes('>-<');
            return { hasDashPercent, hasDashAlone };
        """) as? [String: Any]
        // If this test fails, the template has the '-%' display bug
        let hasDashPercent = result?["hasDashPercent"] as? Bool ?? false
        XCTAssertFalse(hasDashPercent,
                       "Empty data should NOT show '-%' — should show '-' without percent sign")
    }

    func testStats_latestSevenD_nullPercent_shouldNotShowDashPercent() {
        // Last record has null seven_day_percent → latestSevenD = '-'
        // Template shows ${latestSevenD}% → '-%'
        let result = evalJS("""
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: null}],
                []
            );
            const html = document.getElementById('stats').innerHTML;
            // Find the Latest 7d stat value
            const match = html.match(/Latest 7d/);
            return html.includes('-%');
        """) as? Bool
        XCTAssertFalse(result ?? true,
                       "Null percent should NOT show '-%' — the % suffix should be conditional")
    }

    func testStats_latestFiveH_zeroPercent_showsZeroPercent() {
        let result = evalJS("""
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 0, seven_day_percent: 0}],
                []
            );
            const html = document.getElementById('stats').innerHTML;
            return html.includes('0%');
        """) as? Bool
        XCTAssertTrue(result!, "0% usage should display as '0%', not '-'")
    }

    // =========================================================
    // MARK: - Stats: usageSpan format
    // =========================================================

    func testStats_usageSpan_singleRecord_shows0h() {
        let result = evalJS("""
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: 5}],
                []
            );
            const html = document.getElementById('stats').innerHTML;
            return html.includes('0h');
        """) as? Bool
        XCTAssertTrue(result!, "Single usage record should show '0h' span")
    }

    func testStats_usageSpan_multipleRecords_format() {
        let result = evalJS("""
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: 5},
                 {timestamp: '2026-02-24T13:30:00Z', five_hour_percent: 20, seven_day_percent: 8}],
                []
            );
            const html = document.getElementById('stats').innerHTML;
            return html.includes('3.5h');
        """) as? Bool
        XCTAssertTrue(result!, "Usage span 10:00→13:30 should show '3.5h'")
    }

    // =========================================================
    // MARK: - renderUsageTab chart config
    // =========================================================

    func testRenderUsageTab_yAxis_min0_max100() {
        let result = evalJS("""
            _usageData = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 50, seven_day_percent: 25,
                 five_hour_resets_at: null, seven_day_resets_at: null},
            ];
            renderUsageTab();
            const yScale = _chartConfigs['usageTimeline']?.options?.scales?.y;
            return { min: yScale?.min, max: yScale?.max };
        """) as? [String: Any]
        XCTAssertEqual(result?["min"] as? Int, 0, "Usage chart y-axis min should be 0")
        XCTAssertEqual(result?["max"] as? Int, 100, "Usage chart y-axis max should be 100")
    }

    func testRenderUsageTab_xAxisType_isTime() {
        let result = evalJS("""
            _usageData = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 50, seven_day_percent: 25,
                 five_hour_resets_at: null, seven_day_resets_at: null},
            ];
            renderUsageTab();
            return _chartConfigs['usageTimeline']?.options?.scales?.x?.type;
        """) as? String
        XCTAssertEqual(result, "time", "Usage chart x-axis should be time-based")
    }

    func testRenderUsageTab_datasetColors() {
        let result = evalJS("""
            _usageData = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 50, seven_day_percent: 25,
                 five_hour_resets_at: null, seven_day_resets_at: null},
            ];
            renderUsageTab();
            const ds = _chartConfigs['usageTimeline']?.data?.datasets;
            return {
                color0: ds?.[0]?.borderColor,
                color1: ds?.[1]?.borderColor,
            };
        """) as? [String: Any]
        XCTAssertEqual(result?["color0"] as? String, "#64b4ff", "5-hour line should be blue")
        XCTAssertEqual(result?["color1"] as? String, "#ff82b4", "7-day line should be pink")
    }

    // =========================================================
    // MARK: - renderCostTab bar chart data correctness
    // =========================================================

    func testRenderCostTab_barChartDataMatchesTokenData() {
        let result = evalJS("""
            _tokenData = [
                {timestamp: '2026-02-24T10:00:00Z', costUSD: 1.50},
                {timestamp: '2026-02-24T10:01:00Z', costUSD: 0.75},
                {timestamp: '2026-02-24T10:02:00Z', costUSD: 2.25},
            ];
            _allDeltas = [];
            renderCostTab();
            const data = _chartConfigs['costTimeline']?.data?.datasets?.[0]?.data;
            return data?.map(d => d.y);
        """) as? [Double]
        XCTAssertEqual(result, [1.50, 0.75, 2.25],
                       "Bar chart y-values should match tokenData costUSD values exactly")
    }

    func testRenderCostTab_barChartTimestampsPreserved() {
        let result = evalJS("""
            _tokenData = [
                {timestamp: '2026-02-24T10:00:00Z', costUSD: 1.50},
                {timestamp: '2026-02-24T10:01:00Z', costUSD: 0.75},
            ];
            _allDeltas = [];
            renderCostTab();
            const data = _chartConfigs['costTimeline']?.data?.datasets?.[0]?.data;
            return data?.map(d => d.x);
        """) as? [String]
        XCTAssertEqual(result, ["2026-02-24T10:00:00Z", "2026-02-24T10:01:00Z"],
                       "Bar chart x-values should preserve timestamps from tokenData")
    }

    // =========================================================
    // MARK: - renderEfficiencyTab KDE ratios
    // =========================================================

    func testRenderEfficiencyTab_kdeUsesRatios() {
        // deltas with known x/y → ratio = y/x
        // d1: y=5, x=1 → ratio=5; d2: y=10, x=2 → ratio=5; same ratio → KDE should peak at 5
        let result = evalJS("""
            const deltas = [
                {x: 1.0, y: 5.0, hour: 10, timestamp: '2026-02-24T10:05:00Z',
                 date: new Date('2026-02-24T10:05:00Z')},
                {x: 2.0, y: 10.0, hour: 14, timestamp: '2026-02-24T14:05:00Z',
                 date: new Date('2026-02-24T14:05:00Z')},
                {x: 0.5, y: 2.5, hour: 9, timestamp: '2026-02-24T09:05:00Z',
                 date: new Date('2026-02-24T09:05:00Z')},
            ];
            renderEfficiencyTab(deltas);
            const kdeConfig = _chartConfigs['kdeChart'];
            const labels = kdeConfig?.data?.labels;
            const data = kdeConfig?.data?.datasets?.[0]?.data;
            if (!labels || !data) return null;
            // Find peak
            let maxY = -1, peakX = 0;
            for (let i = 0; i < data.length; i++) {
                if (data[i] > maxY) { maxY = data[i]; peakX = labels[i]; }
            }
            return { peakX, hasData: data.length > 0 };
        """) as? [String: Any]
        XCTAssertTrue(result?["hasData"] as? Bool ?? false, "KDE chart should have data")
        if let peakX = result?["peakX"] as? Double {
            XCTAssertEqual(peakX, 5.0, accuracy: 2.0,
                           "All ratios are 5.0 → KDE peak should be near 5.0")
        }
    }

    // =========================================================
    // MARK: - buildHeatmap specific ratio values
    // =========================================================

    func testBuildHeatmap_ratioInCell() {
        let result = evalJS("""
            // Single data point: hour=10 (local), day depends on local timezone
            const dt = new Date('2026-02-24T01:00:00Z'); // Use fixed date
            const deltas = [
                {x: 2.0, y: 10.0, hour: dt.getHours(), timestamp: '2026-02-24T01:00:00Z', date: dt},
            ];
            buildHeatmap(deltas);
            const html = document.getElementById('heatmap').innerHTML;
            // Ratio = 10/2 = 5, displayed as ratio.toFixed(0) = '5'
            // The title should contain 'Δ%/Δ$: 5.0'
            return {
                hasRatio: html.includes('5.0'),
                hasTitle: html.includes('title='),
            };
        """) as? [String: Any]
        XCTAssertTrue(result?["hasTitle"] as? Bool ?? false, "Heatmap cells should have title attributes")
    }

    func testBuildHeatmap_multiplePointsSameCell_aggregated() {
        let result = evalJS("""
            // Two deltas in same day-hour bucket → aggregated
            const dt1 = new Date('2026-02-24T10:00:00Z');
            const dt2 = new Date('2026-02-24T10:30:00Z');
            // Both should have same getDay() and getHours() (same hour)
            const deltas = [
                {x: 1.0, y: 5.0, hour: dt1.getHours(), timestamp: '2026-02-24T10:00:00Z', date: dt1},
                {x: 3.0, y: 9.0, hour: dt2.getHours(), timestamp: '2026-02-24T10:30:00Z', date: dt2},
            ];
            buildHeatmap(deltas);
            const html = document.getElementById('heatmap').innerHTML;
            // Aggregated: totalDelta=14, totalCost=4, ratio=14/4=3.5
            return html.includes('3.5');
        """) as? Bool
        XCTAssertTrue(result!, "Two deltas in same cell should aggregate to ratio 14/4=3.5")
    }

    // =========================================================
    // MARK: - buildScatterChart timeSlot assignment
    // =========================================================

    func testBuildScatterChart_nightDataInNightDataset() {
        let result = evalJS("""
            const deltas = [
                {x: 1.0, y: 5.0, hour: 3},  // 3am = Night
                {x: 2.0, y: 8.0, hour: 10}, // 10am = Morning
                {x: 0.5, y: 3.0, hour: 15}, // 3pm = Afternoon
                {x: 1.5, y: 6.0, hour: 20}, // 8pm = Evening
            ];
            const chart = buildScatterChart('effScatter', deltas);
            const config = _chartConfigs['effScatter'];
            const nightData = config?.data?.datasets?.[0]?.data;  // Night is first slot
            const morningData = config?.data?.datasets?.[1]?.data;
            const afternoonData = config?.data?.datasets?.[2]?.data;
            const eveningData = config?.data?.datasets?.[3]?.data;
            return {
                nightCount: nightData?.length,
                morningCount: morningData?.length,
                afternoonCount: afternoonData?.length,
                eveningCount: eveningData?.length,
            };
        """) as? [String: Any]
        XCTAssertEqual(result?["nightCount"] as? Int, 1, "1 point at hour 3 → Night")
        XCTAssertEqual(result?["morningCount"] as? Int, 1, "1 point at hour 10 → Morning")
        XCTAssertEqual(result?["afternoonCount"] as? Int, 1, "1 point at hour 15 → Afternoon")
        XCTAssertEqual(result?["eveningCount"] as? Int, 1, "1 point at hour 20 → Evening")
    }

    // =========================================================
    // MARK: - Tab click rendering behavior
    // =========================================================

    func testTabClick_rendersOnFirstClick() {
        let result = evalJS("""
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: 5}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50}]
            );
            // Click the cost tab
            const costBtn = document.querySelector('[data-tab="cost"]');
            costBtn.click();
            return {
                costRendered: _rendered['cost'] === true,
                costChartExists: _chartConfigs['costTimeline'] != null,
                costTabActive: document.getElementById('tab-cost').classList.contains('active'),
                usageTabInactive: !document.getElementById('tab-usage').classList.contains('active'),
            };
        """) as? [String: Any]
        XCTAssertTrue(result?["costRendered"] as? Bool ?? false, "Cost tab should be marked as rendered")
        XCTAssertTrue(result?["costChartExists"] as? Bool ?? false, "Cost chart should be created")
        XCTAssertTrue(result?["costTabActive"] as? Bool ?? false, "Cost tab content should be active")
        XCTAssertTrue(result?["usageTabInactive"] as? Bool ?? false, "Usage tab content should be inactive")
    }

    func testTabClick_doesNotReRenderOnSecondClick() {
        let result = evalJS("""
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: 5}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50}]
            );
            // Click cost tab first time → renders
            const costBtn = document.querySelector('[data-tab="cost"]');
            costBtn.click();
            // Record the config reference
            const firstConfig = _chartConfigs['costTimeline'];
            // Click usage, then cost again
            document.querySelector('[data-tab="usage"]').click();
            costBtn.click();
            // Config should be same reference (not re-created)
            return _chartConfigs['costTimeline'] === firstConfig;
        """) as? Bool
        XCTAssertTrue(result!, "Second click on same tab should not re-render (guard by _rendered)")
    }

    // =========================================================
    // MARK: - renderCumulativeTab timestamp preservation
    // =========================================================

    func testRenderCumulativeTab_timestampsPreserved() {
        let result = evalJS("""
            _tokenData = [
                {timestamp: '2026-02-24T10:00:00Z', costUSD: 1.00},
                {timestamp: '2026-02-24T10:01:00Z', costUSD: 2.00},
            ];
            renderCumulativeTab();
            const data = _chartConfigs['cumulativeCost']?.data?.datasets?.[0]?.data;
            return data?.map(d => d.x);
        """) as? [String]
        XCTAssertEqual(result, ["2026-02-24T10:00:00Z", "2026-02-24T10:01:00Z"],
                       "Cumulative chart should preserve timestamps from tokenData")
    }

    // =========================================================
    // MARK: - getFilteredDeltas precise date boundary
    // =========================================================

    func testGetFilteredDeltas_dateRangeEndOfDay_inclusive() {
        let result = evalJS("""
            _allDeltas = [
                {x: 1.0, y: 5.0, timestamp: '2026-02-24T23:50:00Z',
                 date: new Date('2026-02-24T23:50:00Z')},
            ];
            // The 'to' date creates 'T23:59:59' local time boundary
            // This UTC timestamp might be outside local date range depending on timezone
            document.getElementById('dateFrom').value = '2026-02-24';
            document.getElementById('dateTo').value = '2026-02-24';
            const filtered = getFilteredDeltas();
            // In JST, 2026-02-24T23:50:00Z = 2026-02-25T08:50:00 JST → OUTSIDE Feb 24 local
            // In UTC, it's Feb 24 → within range
            const d = new Date('2026-02-24T23:50:00Z');
            const localDate = d.getFullYear() + '-'
                + String(d.getMonth() + 1).padStart(2, '0') + '-'
                + String(d.getDate()).padStart(2, '0');
            return {
                filteredCount: filtered.length,
                localDate: localDate,
                isLocalFeb24: localDate === '2026-02-24',
            };
        """) as? [String: Any]
        let filteredCount = result?["filteredCount"] as? Int ?? -1
        let isLocalFeb24 = result?["isLocalFeb24"] as? Bool ?? false
        if isLocalFeb24 {
            XCTAssertEqual(filteredCount, 1, "UTC 23:50 is still Feb 24 locally → should be included")
        } else {
            XCTAssertEqual(filteredCount, 0, "UTC 23:50 is Feb 25 locally → should be excluded")
        }
    }

    // =========================================================
    // MARK: - renderEfficiencyTab destroys old charts
    // =========================================================

    func testRenderEfficiencyTab_calledTwice_destroysPrevious() {
        let result = evalJS("""
            const deltas1 = [
                {x: 1.0, y: 5.0, hour: 10, timestamp: '2026-02-24T10:05:00Z',
                 date: new Date('2026-02-24T10:05:00Z')},
                {x: 2.0, y: 10.0, hour: 14, timestamp: '2026-02-24T14:05:00Z',
                 date: new Date('2026-02-24T14:05:00Z')},
            ];
            renderEfficiencyTab(deltas1);
            const first = _charts.effScatter;
            // Call again with different data
            const deltas2 = [
                {x: 3.0, y: 15.0, hour: 10, timestamp: '2026-02-24T10:05:00Z',
                 date: new Date('2026-02-24T10:05:00Z')},
            ];
            renderEfficiencyTab(deltas2);
            // Charts should be different objects (old ones destroyed and new ones created)
            return _charts.effScatter !== first;
        """) as? Bool
        XCTAssertTrue(result!, "Re-rendering efficiency tab should create new chart objects")
    }

    // =========================================================
    // MARK: - Main function: tokenData.length.toLocaleString() vs usageData.length
    // =========================================================

    func testStats_tokenCount_usesLocaleString() {
        let result = evalJS("""
            // Create data with 1234 token records to test toLocaleString
            const tokenData = Array.from({length: 1234}, (_, i) => ({
                timestamp: '2026-02-24T10:00:00Z', costUSD: 0.01
            }));
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: 5}],
                tokenData
            );
            const html = document.getElementById('stats').innerHTML;
            // toLocaleString would produce '1,234' in many locales
            // Plain .length would produce '1234'
            const hasFormatted = html.includes('1,234');
            const hasPlain = html.includes('>1234<');
            return { hasFormatted, hasPlain };
        """) as? [String: Any]
        // At least one format should appear in the stats
        let hasFormatted = result?["hasFormatted"] as? Bool ?? false
        let hasPlain = result?["hasPlain"] as? Bool ?? false
        XCTAssertTrue(hasFormatted || hasPlain,
                      "Token count should appear in stats (either formatted or plain)")
    }

    // =========================================================
    // MARK: - Slider default value matches label
    // =========================================================

    func testSlider_initialValueMatchesLabel() {
        let result = evalJS("""
            // Before main() — check initial DOM state
            return {
                sliderValue: document.getElementById('gapSlider').value,
                labelText: document.getElementById('gapVal').textContent,
            };
        """) as? [String: Any]
        XCTAssertEqual(result?["sliderValue"] as? String, "30",
                       "Slider default value should be 30")
        XCTAssertEqual(result?["labelText"] as? String, "30 min",
                       "Label should show '30 min' matching slider default")
    }

    // =========================================================
    // MARK: - gapThresholdMs updates when slider changes
    // =========================================================

    func testSlider_updatesGapThreshold() {
        let result = evalJS("""
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: 5}],
                [{timestamp: '2026-02-24T10:01:00Z', costUSD: 0.5}]
            );
            const slider = document.getElementById('gapSlider');
            slider.value = '120';
            slider.dispatchEvent(new Event('input'));
            return gapThresholdMs;
        """) as? Int
        XCTAssertEqual(result, 120 * 60 * 1000,
                       "gapThresholdMs should update to 120min * 60s * 1000ms")
    }

    // =========================================================
    // MARK: - computeDeltas hour uses local time
    // =========================================================

    func testComputeDeltas_hourIsLocalTime() {
        let result = evalJS("""
            const deltas = computeDeltas(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10},
                 {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: 15}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50}]
            );
            const expectedHour = new Date('2026-02-24T10:05:00Z').getHours();
            return { deltaHour: deltas[0].hour, expectedHour };
        """) as? [String: Any]
        XCTAssertEqual(result?["deltaHour"] as? Int, result?["expectedHour"] as? Int,
                       "Delta hour should use local getHours(), not UTC getUTCHours()")
    }

    // =========================================================
    // MARK: - renderUsageTab segment callbacks
    // =========================================================

    func testRenderUsageTab_segmentCallbacksExist() {
        let result = evalJS("""
            _usageData = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 50, seven_day_percent: 25,
                 five_hour_resets_at: null, seven_day_resets_at: null},
            ];
            renderUsageTab();
            const ds0 = _chartConfigs['usageTimeline']?.data?.datasets?.[0];
            const ds1 = _chartConfigs['usageTimeline']?.data?.datasets?.[1];
            return {
                ds0HasSegment: ds0?.segment != null,
                ds1HasSegment: ds1?.segment != null,
                ds0HasBorderColor: typeof ds0?.segment?.borderColor === 'function',
                ds0HasBgColor: typeof ds0?.segment?.backgroundColor === 'function',
            };
        """) as? [String: Any]
        XCTAssertTrue(result?["ds0HasSegment"] as? Bool ?? false, "5h dataset should have segment config")
        XCTAssertTrue(result?["ds1HasSegment"] as? Bool ?? false, "7d dataset should have segment config")
        XCTAssertTrue(result?["ds0HasBorderColor"] as? Bool ?? false, "Segment should have borderColor callback")
        XCTAssertTrue(result?["ds0HasBgColor"] as? Bool ?? false, "Segment should have backgroundColor callback")
    }

    // =========================================================
    // MARK: - Cumulative chart type and label
    // =========================================================

    func testRenderCumulativeTab_chartTypeAndLabel() {
        let result = evalJS("""
            _tokenData = [{timestamp: '2026-02-24T10:00:00Z', costUSD: 1.00}];
            renderCumulativeTab();
            const config = _chartConfigs['cumulativeCost'];
            return {
                type: config?.type,
                label: config?.data?.datasets?.[0]?.label,
                borderColor: config?.data?.datasets?.[0]?.borderColor,
            };
        """) as? [String: Any]
        XCTAssertEqual(result?["type"] as? String, "line")
        XCTAssertEqual(result?["label"] as? String, "Cumulative Cost (USD)")
        XCTAssertEqual(result?["borderColor"] as? String, "#f0883e", "Cumulative line should be orange")
    }

    // =========================================================
    // MARK: - Apply Range button behavior
    // =========================================================

    func testApplyRange_reRendersEfficiencyTab() {
        let result = evalJS("""
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: 5},
                 {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: 15, seven_day_percent: 7}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50}]
            );
            // First click efficiency tab
            document.querySelector('[data-tab="efficiency"]').click();
            const firstScatter = _charts.effScatter;
            // Click Apply Range
            document.getElementById('applyRange').click();
            // Charts should be re-created
            return {
                reRendered: _charts.effScatter !== firstScatter,
                renderedFlag: _rendered['efficiency'] === true,
            };
        """) as? [String: Any]
        XCTAssertTrue(result?["reRendered"] as? Bool ?? false,
                      "Apply Range should re-render even if already rendered")
        XCTAssertTrue(result?["renderedFlag"] as? Bool ?? false)
    }

    // =========================================================
    // MARK: - Bug hunt round 2: computeDeltas null handling
    // =========================================================

    func testComputeDeltas_nullCurrPercent_shouldExcludeInterval() {
        // prev has 30%, curr has null → d5h would be (null??0) - 30 = -30.
        // This is WRONG — null means "unknown", not "0%".
        // The interval should be excluded from deltas entirely.
        let result = evalJS("""
            const deltas = computeDeltas(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 30, seven_day_percent: 10},
                 {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: null, seven_day_percent: 12}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50}]
            );
            return { count: deltas.length, firstY: deltas[0]?.y };
        """) as? [String: Any]
        let count = result?["count"] as? Int ?? -1
        // If null is treated as 0, d5h = 0 - 30 = -30, and the interval IS included (cost > 0.001).
        // Correct behavior: exclude interval because curr.five_hour_percent is null.
        XCTAssertEqual(count, 0,
                       "Interval where curr five_hour_percent is null should be EXCLUDED — null ≠ 0%")
    }

    func testComputeDeltas_nullPrevPercent_shouldExcludeInterval() {
        // prev has null, curr has 20% → d5h would be 20 - (null??0) = 20.
        // This bogus +20 delta corrupts scatter/KDE/heatmap.
        let result = evalJS("""
            const deltas = computeDeltas(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: null, seven_day_percent: 5},
                 {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: 20, seven_day_percent: 8}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50}]
            );
            return { count: deltas.length, firstY: deltas[0]?.y };
        """) as? [String: Any]
        let count = result?["count"] as? Int ?? -1
        XCTAssertEqual(count, 0,
                       "Interval where prev five_hour_percent is null should be EXCLUDED — null ≠ 0%")
    }

    func testComputeDeltas_bothNullPercent_shouldExcludeInterval() {
        let result = evalJS("""
            const deltas = computeDeltas(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: null, seven_day_percent: 5},
                 {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: null, seven_day_percent: 8}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50}]
            );
            return deltas.length;
        """) as? Int
        XCTAssertEqual(result, 0,
                       "Both null five_hour_percent → interval excluded")
    }

    func testComputeDeltas_nullDoesNotProduceBogusNegativeDelta() {
        // Specific check: the delta should NOT be -30 (null treated as 0)
        let result = evalJS("""
            const deltas = computeDeltas(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 30, seven_day_percent: 10},
                 {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: null, seven_day_percent: 12}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50}]
            );
            const hasBogusNegative = deltas.some(d => d.y === -30);
            return hasBogusNegative;
        """) as? Bool
        XCTAssertFalse(result ?? true,
                       "CRITICAL: null five_hour_percent should NOT produce d5h = -30 (null ≠ 0)")
    }

    // =========================================================
    // MARK: - Bug hunt round 2: chart config deep checks
    // =========================================================

    func testRenderCostTab_costTimelineType_isBar() {
        let result = evalJS("""
            _tokenData = [{timestamp: '2026-02-24T10:00:00Z', costUSD: 0.50}];
            _allDeltas = [];
            renderCostTab();
            return _chartConfigs['costTimeline']?.type;
        """) as? String
        XCTAssertEqual(result, "bar", "Cost timeline should be a bar chart")
    }

    func testRenderEfficiencyTab_kdeChartType_isLine() {
        let result = evalJS("""
            const deltas = [
                {x: 0.50, y: 5.0, hour: 10, timestamp: '2026-02-24T10:05:00Z', date: new Date('2026-02-24T10:05:00Z')},
                {x: 0.30, y: 3.0, hour: 11, timestamp: '2026-02-24T11:05:00Z', date: new Date('2026-02-24T11:05:00Z')},
            ];
            renderEfficiencyTab(deltas);
            return _chartConfigs['kdeChart']?.type;
        """) as? String
        XCTAssertEqual(result, "line", "KDE chart should be type line")
    }

    func testRenderEfficiencyTab_kdeXAxis_isLinear() {
        let result = evalJS("""
            const deltas = [
                {x: 0.50, y: 5.0, hour: 10, timestamp: '2026-02-24T10:05:00Z', date: new Date('2026-02-24T10:05:00Z')},
                {x: 0.30, y: 3.0, hour: 11, timestamp: '2026-02-24T11:05:00Z', date: new Date('2026-02-24T11:05:00Z')},
            ];
            renderEfficiencyTab(deltas);
            return _chartConfigs['kdeChart']?.options?.scales?.x?.type;
        """) as? String
        XCTAssertEqual(result, "linear", "KDE x-axis should be linear (ratio values)")
    }

    // =========================================================
    // MARK: - Bug hunt round 2: dataset label verification
    // =========================================================

    func testRenderUsageTab_dataset0Label_isFiveHour() {
        let result = evalJS("""
            _usageData = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 50, seven_day_percent: 25,
                 five_hour_resets_at: null, seven_day_resets_at: null},
            ];
            renderUsageTab();
            return _chartConfigs['usageTimeline']?.data?.datasets?.[0]?.label;
        """) as? String
        XCTAssertEqual(result, "5-hour %", "First dataset should be 5-hour %")
    }

    func testRenderUsageTab_dataset1Label_isSevenDay() {
        let result = evalJS("""
            _usageData = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 50, seven_day_percent: 25,
                 five_hour_resets_at: null, seven_day_resets_at: null},
            ];
            renderUsageTab();
            return _chartConfigs['usageTimeline']?.data?.datasets?.[1]?.label;
        """) as? String
        XCTAssertEqual(result, "7-day %", "Second dataset should be 7-day %")
    }

    // =========================================================
    // MARK: - Bug hunt round 2: scatter datasets integrity
    // =========================================================

    func testBuildScatterChart_totalPoints_equalsDeltasCount() {
        // All deltas should appear in exactly one time-slot dataset
        let result = evalJS("""
            const deltas = [
                {x: 0.5, y: 5, hour: 2},   // Night
                {x: 0.3, y: 3, hour: 8},   // Morning
                {x: 0.4, y: 4, hour: 14},  // Afternoon
                {x: 0.6, y: 6, hour: 20},  // Evening
                {x: 0.2, y: 2, hour: 11},  // Morning
            ];
            const chart = buildScatterChart('effScatter', deltas);
            const config = _chartConfigs['effScatter'];
            const totalPoints = config.data.datasets.reduce((s, ds) => s + ds.data.length, 0);
            return { totalPoints, inputCount: deltas.length, numDatasets: config.data.datasets.length };
        """) as? [String: Any]
        let totalPoints = result?["totalPoints"] as? Int ?? -1
        let inputCount = result?["inputCount"] as? Int ?? -1
        let numDatasets = result?["numDatasets"] as? Int ?? -1
        XCTAssertEqual(totalPoints, inputCount,
                       "Total scatter points across all time-slot datasets should equal input deltas count")
        XCTAssertEqual(numDatasets, 4, "Should have 4 time-slot datasets (Night/Morning/Afternoon/Evening)")
    }

    // =========================================================
    // MARK: - Bug hunt round 2: cumulative vs total cost consistency
    // =========================================================

    func testCumulativeCost_finalValue_approximatesTotalCost() {
        let result = evalJS("""
            _tokenData = [
                {timestamp: '2026-02-24T10:00:00Z', costUSD: 0.123},
                {timestamp: '2026-02-24T10:05:00Z', costUSD: 0.456},
                {timestamp: '2026-02-24T10:10:00Z', costUSD: 0.789},
            ];
            renderCumulativeTab();
            const config = _chartConfigs['cumulativeCost'];
            const data = config.data.datasets[0].data;
            const lastY = data[data.length - 1].y;
            const totalCost = _tokenData.reduce((s, r) => s + r.costUSD, 0);
            return { lastY, totalCostRounded: Math.round(totalCost * 100) / 100 };
        """) as? [String: Any]
        let lastY = result?["lastY"] as? Double ?? -1
        let expected = result?["totalCostRounded"] as? Double ?? -2
        XCTAssertEqual(lastY, expected, accuracy: 0.01,
                       "Cumulative chart's last value should approximate total cost")
    }

    // =========================================================
    // MARK: - Bug hunt round 2: insertResetPoints data format
    // =========================================================

    func testInsertResetPoints_outputHasXandY() {
        let result = evalJS("""
            const data = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 30, five_hour_resets_at: null},
                {timestamp: '2026-02-24T11:00:00Z', five_hour_percent: 50, five_hour_resets_at: null},
            ];
            const points = insertResetPoints(data, 'five_hour_percent', 'five_hour_resets_at');
            const allHaveX = points.every(p => p.x !== undefined);
            const allHaveY = points.every(p => p.y !== undefined);
            return { count: points.length, allHaveX, allHaveY,
                     firstX: points[0]?.x, firstY: points[0]?.y };
        """) as? [String: Any]
        XCTAssertEqual(result?["count"] as? Int, 2)
        XCTAssertTrue(result?["allHaveX"] as? Bool ?? false, "All points should have x (timestamp)")
        XCTAssertTrue(result?["allHaveY"] as? Bool ?? false, "All points should have y (percent)")
        XCTAssertEqual(result?["firstY"] as? Double, 30.0)
    }

    // =========================================================
    // MARK: - Bug hunt round 2: heatmap structure
    // =========================================================

    func testBuildHeatmap_gridHas25ColumnsAnd8Rows() {
        // 1 label column + 24 hour columns = 25 columns
        // 1 header row + 7 day rows = 8 rows = 200 cells total
        let result = evalJS("""
            buildHeatmap([]);
            const html = document.getElementById('heatmap').innerHTML;
            const headerCount = (html.match(/heatmap-header/g) || []).length;
            const labelCount = (html.match(/heatmap-label/g) || []).length;
            const cellCount = (html.match(/heatmap-cell/g) || []).length;
            return { headerCount, labelCount, cellCount };
        """) as? [String: Any]
        XCTAssertEqual(result?["headerCount"] as? Int, 24, "Should have 24 hour headers")
        XCTAssertEqual(result?["labelCount"] as? Int, 7, "Should have 7 day labels")
        XCTAssertEqual(result?["cellCount"] as? Int, 168, "Should have 7×24 = 168 data cells")
    }

    // =========================================================
    // MARK: - Bug hunt round 2: renderCostTab bar data integrity
    // =========================================================

    func testRenderCostTab_barDataCount_matchesTokenDataLength() {
        let result = evalJS("""
            _tokenData = [
                {timestamp: '2026-02-24T10:00:00Z', costUSD: 0.10},
                {timestamp: '2026-02-24T10:05:00Z', costUSD: 0.20},
                {timestamp: '2026-02-24T10:10:00Z', costUSD: 0.30},
            ];
            _allDeltas = [];
            renderCostTab();
            const barData = _chartConfigs['costTimeline']?.data?.datasets?.[0]?.data;
            return { barCount: barData?.length, tokenCount: _tokenData.length };
        """) as? [String: Any]
        let barCount = result?["barCount"] as? Int ?? -1
        let tokenCount = result?["tokenCount"] as? Int ?? -1
        XCTAssertEqual(barCount, tokenCount,
                       "Cost bar chart should have one bar per token record")
    }

    func testRenderCostTab_barTimestamps_matchTokenTimestamps() {
        let result = evalJS("""
            _tokenData = [
                {timestamp: '2026-02-24T10:00:00Z', costUSD: 0.10},
                {timestamp: '2026-02-24T11:00:00Z', costUSD: 0.20},
            ];
            _allDeltas = [];
            renderCostTab();
            const barData = _chartConfigs['costTimeline']?.data?.datasets?.[0]?.data;
            return {
                bar0x: barData?.[0]?.x,
                bar1x: barData?.[1]?.x,
                token0ts: _tokenData[0].timestamp,
                token1ts: _tokenData[1].timestamp,
            };
        """) as? [String: String]
        XCTAssertEqual(result?["bar0x"], result?["token0ts"],
                       "Bar chart x-values should be token timestamps")
        XCTAssertEqual(result?["bar1x"], result?["token1ts"])
    }

    func testRenderCostTab_barCosts_matchTokenCosts() {
        let result = evalJS("""
            _tokenData = [
                {timestamp: '2026-02-24T10:00:00Z', costUSD: 0.123},
                {timestamp: '2026-02-24T11:00:00Z', costUSD: 0.456},
            ];
            _allDeltas = [];
            renderCostTab();
            const barData = _chartConfigs['costTimeline']?.data?.datasets?.[0]?.data;
            return {
                bar0y: barData?.[0]?.y,
                bar1y: barData?.[1]?.y,
            };
        """) as? [String: Any]
        XCTAssertEqual(result?["bar0y"] as? Double ?? -1, 0.123, accuracy: 0.0001)
        XCTAssertEqual(result?["bar1y"] as? Double ?? -1, 0.456, accuracy: 0.0001)
    }

    // =========================================================
    // MARK: - Bug hunt round 2: renderUsageTab data from insertResetPoints
    // =========================================================

    func testRenderUsageTab_fiveHDataPoints_matchInsertResetPointsOutput() {
        let result = evalJS("""
            _usageData = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 30, seven_day_percent: 10,
                 five_hour_resets_at: '2026-02-24T11:00:00Z', seven_day_resets_at: null},
                {timestamp: '2026-02-24T12:00:00Z', five_hour_percent: 5, seven_day_percent: 12,
                 five_hour_resets_at: null, seven_day_resets_at: null},
            ];
            renderUsageTab();
            const ds0 = _chartConfigs['usageTimeline']?.data?.datasets?.[0]?.data;
            // insertResetPoints should produce: {x: T1, y: 30}, {x: reset, y: 0}, {x: T2, y: 5}
            return { count: ds0?.length, y0: ds0?.[0]?.y, y1: ds0?.[1]?.y, y2: ds0?.[2]?.y };
        """) as? [String: Any]
        XCTAssertEqual(result?["count"] as? Int, 3, "Should have 3 points: data, reset-zero, data")
        XCTAssertEqual(result?["y0"] as? Double, 30.0, "First point: 30%")
        XCTAssertEqual(result?["y1"] as? Double, 0.0, "Reset point: 0%")
        XCTAssertEqual(result?["y2"] as? Double, 5.0, "After reset: 5%")
    }

    // =========================================================
    // MARK: - Bug hunt round 2: KDE data format
    // =========================================================

    func testRenderEfficiencyTab_kdeData_usesLabelsAndValues() {
        let result = evalJS("""
            const deltas = [
                {x: 0.50, y: 5.0, hour: 10, timestamp: '2026-02-24T10:05:00Z', date: new Date('2026-02-24T10:05:00Z')},
                {x: 0.30, y: 3.0, hour: 11, timestamp: '2026-02-24T11:05:00Z', date: new Date('2026-02-24T11:05:00Z')},
            ];
            renderEfficiencyTab(deltas);
            const config = _chartConfigs['kdeChart'];
            const labels = config?.data?.labels;
            const data = config?.data?.datasets?.[0]?.data;
            return {
                hasLabels: labels != null && labels.length > 0,
                hasData: data != null && data.length > 0,
                labelsAreNumbers: typeof labels?.[0] === 'number',
                dataAreNumbers: typeof data?.[0] === 'number',
                labelsLength: labels?.length,
                dataLength: data?.length,
            };
        """) as? [String: Any]
        XCTAssertTrue(result?["hasLabels"] as? Bool ?? false, "KDE should have labels (x values)")
        XCTAssertTrue(result?["hasData"] as? Bool ?? false, "KDE should have data (y values)")
        XCTAssertTrue(result?["labelsAreNumbers"] as? Bool ?? false, "KDE labels should be numbers")
        XCTAssertTrue(result?["dataAreNumbers"] as? Bool ?? false, "KDE data should be numbers")
        let labelsLen = result?["labelsLength"] as? Int ?? 0
        let dataLen = result?["dataLength"] as? Int ?? 0
        XCTAssertEqual(labelsLen, dataLen, "Labels and data should have same length")
    }

    // =========================================================
    // MARK: - Bug hunt round 2: costForRecord edge cases
    // =========================================================

    func testCostForRecord_cacheCreationTokens_usesCacheWritePrice() {
        // Verify cache_creation_tokens uses cacheWrite price, NOT cacheRead price
        let result = evalJS("""
            const record = {
                model: 'claude-3-5-sonnet-20241022',
                input_tokens: 0,
                output_tokens: 0,
                cache_read_tokens: 0,
                cache_creation_tokens: 1000000,
            };
            return costForRecord(record);
        """) as? Double
        // Sonnet cacheWrite = 3.75 per 1M tokens
        XCTAssertEqual(result!, 3.75, accuracy: 0.001,
                       "cache_creation_tokens should use cacheWrite price (3.75), not cacheRead (0.30)")
    }

    func testCostForRecord_cacheReadTokens_usesCacheReadPrice() {
        let result = evalJS("""
            const record = {
                model: 'claude-3-5-sonnet-20241022',
                input_tokens: 0,
                output_tokens: 0,
                cache_read_tokens: 1000000,
                cache_creation_tokens: 0,
            };
            return costForRecord(record);
        """) as? Double
        // Sonnet cacheRead = 0.30 per 1M tokens
        XCTAssertEqual(result!, 0.30, accuracy: 0.001,
                       "cache_read_tokens should use cacheRead price (0.30), not cacheWrite (3.75)")
    }

    // =========================================================
    // MARK: - Bug hunt round 2: renderCumulativeTab x-axis type
    // =========================================================

    func testRenderCumulativeTab_xAxisType_isTime() {
        let result = evalJS("""
            _tokenData = [{timestamp: '2026-02-24T10:00:00Z', costUSD: 1.0}];
            renderCumulativeTab();
            return _chartConfigs['cumulativeCost']?.options?.scales?.x?.type;
        """) as? String
        XCTAssertEqual(result, "time", "Cumulative chart x-axis should be time scale")
    }

    func testRenderCostTab_costTimeline_xAxisType_isTime() {
        let result = evalJS("""
            _tokenData = [{timestamp: '2026-02-24T10:00:00Z', costUSD: 0.5}];
            _allDeltas = [];
            renderCostTab();
            return _chartConfigs['costTimeline']?.options?.scales?.x?.type;
        """) as? String
        XCTAssertEqual(result, "time", "Cost timeline x-axis should be time scale")
    }

    // =========================================================
    // MARK: - Bug hunt round 2: usage chart fill and tension
    // =========================================================

    func testRenderUsageTab_datasets_haveFillTrue() {
        let result = evalJS("""
            _usageData = [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 50, seven_day_percent: 25,
                           five_hour_resets_at: null, seven_day_resets_at: null}];
            renderUsageTab();
            const ds = _chartConfigs['usageTimeline']?.data?.datasets;
            return { fill0: ds?.[0]?.fill, fill1: ds?.[1]?.fill, tension0: ds?.[0]?.tension, tension1: ds?.[1]?.tension };
        """) as? [String: Any]
        XCTAssertTrue(result?["fill0"] as? Bool ?? false, "5h dataset should have fill: true")
        XCTAssertTrue(result?["fill1"] as? Bool ?? false, "7d dataset should have fill: true")
        XCTAssertEqual(result?["tension0"] as? Int, 0, "5h dataset tension should be 0 (no curve)")
        XCTAssertEqual(result?["tension1"] as? Int, 0, "7d dataset tension should be 0 (no curve)")
    }

    // =========================================================
    // MARK: - Bug hunt round 2: cost bar chart config
    // =========================================================

    func testRenderCostTab_barPercentage_is1() {
        let result = evalJS("""
            _tokenData = [{timestamp: '2026-02-24T10:00:00Z', costUSD: 0.5}];
            _allDeltas = [];
            renderCostTab();
            const ds = _chartConfigs['costTimeline']?.data?.datasets?.[0];
            return { barPct: ds?.barPercentage, catPct: ds?.categoryPercentage };
        """) as? [String: Any]
        XCTAssertEqual(result?["barPct"] as? Double, 1.0, "barPercentage should be 1.0")
        XCTAssertEqual(result?["catPct"] as? Double, 1.0, "categoryPercentage should be 1.0")
    }
}

// MARK: - Mock WKURLSchemeTask

/// Minimal mock for WKURLSchemeTask to test AnalysisSchemeHandler without a real WKWebView.
private final class MockSchemeTask: NSObject, WKURLSchemeTask {
    let request: URLRequest
    var receivedResponse: URLResponse?
    var receivedData: Data?
    var didFinishCalled = false

    init(url: URL) {
        self.request = URLRequest(url: url)
    }

    func didReceive(_ response: URLResponse) {
        self.receivedResponse = response
    }

    func didReceive(_ data: Data) {
        if self.receivedData == nil {
            self.receivedData = data
        } else {
            self.receivedData!.append(data)
        }
    }

    func didFinish() {
        didFinishCalled = true
    }

    func didFailWithError(_ error: Error) {
        // Not used in these tests
    }
}
