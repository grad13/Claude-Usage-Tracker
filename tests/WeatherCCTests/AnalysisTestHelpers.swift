import XCTest
import WebKit
import SQLite3
@testable import WeatherCC

// MARK: - TestNavDelegate

/// WKNavigationDelegate for waiting on page load completion in tests.
final class TestNavDelegate: NSObject, WKNavigationDelegate {
    private let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onFinish() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onFinish() }
}

// MARK: - MockSchemeTask

/// Minimal mock for WKURLSchemeTask to test AnalysisSchemeHandler without a real WKWebView.
final class MockSchemeTask: NSObject, WKURLSchemeTask {
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

// MARK: - AnalysisTestDB

/// Shared SQLite database creation helpers used across multiple test files.
enum AnalysisTestDB {

    /// Create a real SQLite usage.db with the normalized 3-table schema.
    /// Tuple: (epoch timestamp, hourly_percent, weekly_percent).
    /// Session tables are created but left empty (LEFT JOIN returns NULL for resets_at).
    static func createUsageDb(at path: String, rows: [(Int, Double, Double)]) {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            XCTFail("Failed to create test usage.db")
            return
        }
        defer { sqlite3_close(db) }

        let createSQL = """
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
        sqlite3_exec(db, createSQL, nil, nil, nil)

        for (ts, hourly, weekly) in rows {
            let insertSQL = "INSERT INTO usage_log (timestamp, hourly_percent, weekly_percent) VALUES (?, ?, ?);"
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, Int64(ts))
            sqlite3_bind_double(stmt, 2, hourly)
            sqlite3_bind_double(stmt, 3, weekly)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    /// Create a real SQLite tokens.db with the same schema as TokenStore.
    static func createTokensDb(at path: String, rows: [(String, String, String, Int, Int, Int, Int)]) {
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

    /// Create a real SQLite tokens.db with schema only (no rows).
    static func createTokensDb(at path: String) {
        createTokensDb(at: path, rows: [])
    }
}

// MARK: - AnalysisJSTestCase

/// Base XCTestCase subclass with WKWebView + evalJS setup for JS logic tests.
/// Loads the TemplateTestHelper.testHTML and provides evalJS for executing JS.
class AnalysisJSTestCase: XCTestCase {

    var webView: WKWebView!
    var navExpectation: XCTestExpectation!

    override func setUp() {
        super.setUp()
        let exp = expectation(description: "Page loaded")
        navExpectation = exp
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let navDelegate = TestNavDelegate(onFinish: { exp.fulfill() })
        webView.navigationDelegate = navDelegate
        objc_setAssociatedObject(webView!, "navDelegate", navDelegate, .OBJC_ASSOCIATION_RETAIN)
        webView.loadHTMLString(TemplateTestHelper.testHTML, baseURL: nil)
        if XCTWaiter.wait(for: [exp], timeout: 10.0) == .timedOut {
            XCTFail("WKWebView page load timed out — TemplateTestHelper.testHTML may have a script error")
        }
    }

    override func tearDown() {
        webView = nil
        super.tearDown()
    }

    func evalJS(_ code: String, file: StaticString = #file, line: UInt = #line) -> Any? {
        // Wrap in try/catch so undefined function calls fail immediately instead of hanging
        let wrapped = """
            try {
                \(code)
            } catch (e) {
                throw new Error('evalJS caught: ' + e.message);
            }
            """
        let exp = expectation(description: "JS eval")
        var jsResult: Any?
        var jsError: Error?
        webView.callAsyncJavaScript(wrapped, arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .success(let value): jsResult = value
            case .failure(let error): jsError = error
            }
            exp.fulfill()
        }
        let waiterResult = XCTWaiter.wait(for: [exp], timeout: 5.0)
        if waiterResult == .timedOut {
            XCTFail("evalJS timed out — JS likely references an undefined function or variable", file: file, line: line)
            return nil
        }
        if let err = jsError { XCTFail("JS error: \(err)", file: file, line: line) }
        return jsResult
    }
}

// MARK: - Template JS Extraction Helper

/// Extracts JS functions from the ACTUAL AnalysisExporter.htmlTemplate for testing.
/// Unlike the copied-JS tests above (AnalysisJSLogicTests/AnalysisJSExtendedTests),
/// these tests run against the REAL template code. If someone changes the template,
/// the tests automatically exercise the changed code.
enum TemplateTestHelper {
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
        let iifeMarker = "// ============================================================\n// Entry point:"
        if let iifeRange = jsCode.range(of: iifeMarker) {
            jsCode = String(jsCode[..<iifeRange.lowerBound])
        }

        return """
        <!DOCTYPE html><html><head></head><body>
        <div id="loading">Loading...</div>
        <div id="app" style="display:none;">
            <div class="date-range" id="globalRange">
                <input type="date" id="globalFrom">
                <input type="date" id="globalTo">
                <button class="preset-btn" data-days="7">7d</button>
                <button class="preset-btn" data-days="30">30d</button>
                <button class="preset-btn" data-days="0">All</button>
                <button id="applyGlobal">Apply</button>
            </div>
            <div class="stats" id="stats"></div>
            <div class="tab-bar">
                <button class="tab-btn active" data-tab="usage">Usage</button>
                <button class="tab-btn" data-tab="cost">Cost</button>
                <button class="tab-btn" data-tab="scatter">Scatter</button>
                <button class="tab-btn" data-tab="kde">KDE</button>
                <button class="tab-btn" data-tab="heatmap">Heatmap</button>
                <button class="tab-btn" data-tab="cumulative">Cumulative</button>
            </div>
            <div class="tab-content active" id="tab-usage">
                <canvas id="usageTimeline"></canvas>
            </div>
            <div class="tab-content" id="tab-cost">
                <canvas id="costTimeline"></canvas>
                <canvas id="costScatter"></canvas>
            </div>
            <div class="tab-content" id="tab-scatter">
                <canvas id="effScatter"></canvas>
            </div>
            <div class="tab-content" id="tab-kde">
                <canvas id="kdeChart"></canvas>
            </div>
            <div class="tab-content" id="tab-heatmap">
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
            static register() {}
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
