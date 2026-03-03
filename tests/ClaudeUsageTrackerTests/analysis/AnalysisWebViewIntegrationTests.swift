import XCTest
import WebKit
import SQLite3
@testable import ClaudeUsageTracker

// MARK: - WKWebView Integration Tests

/// Actually loads HTML in a WKWebView with the scheme handler and verifies
/// JavaScript can fetch JSON data via cut:// scheme handler.
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

        webView.load(URLRequest(url: URL(string: "cut://analysis.html")!))
        return (webView, navExpectation)
    }

    /// WKWebView with scheme handler can load HTML and execute JS fetch() against cut:// JSON URLs.
    /// This is the actual runtime path. If this test passes, the Analysis window works.
    func testWKWebView_canFetchJsonViaSchemeHandler() {
        let usagePath = tmpDir.appendingPathComponent("usage.db").path
        let tokensPath = tmpDir.appendingPathComponent("tokens.db").path
        AnalysisTestDB.createUsageDb(at: usagePath, rows: [
            (1771927200, 42.5, 15.0),
            (1771927500, 55.0, 20.0),
        ])
        AnalysisTestDB.createTokensDb(at: tokensPath)

        let (webView, navExp) = loadWebView(usagePath: usagePath, tokensPath: tokensPath) {
            "<!DOCTYPE html><html><body></body></html>"
        }
        if XCTWaiter.wait(for: [navExp], timeout: 5.0) == .timedOut {
            XCTFail("WKWebView page load timed out")
        }

        let jsExp = expectation(description: "JS executed")
        let jsCode = """
            const res = await fetch('cut://usage.json');
            const json = await res.json();
            return {ok: res.ok, status: res.status, count: json.length, firstHourly: json[0]?.hourly_percent};
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
                               "fetch('cut://usage.json') must return ok:true")
                XCTAssertEqual(dict["status"] as? Int, 200)
                XCTAssertEqual(dict["count"] as? Int, 2)
                XCTAssertEqual(dict["firstHourly"] as? Double, 42.5)
            case .failure(let error):
                XCTFail("JS failed: \(error)")
            }
            jsExp.fulfill()
        }
        if XCTWaiter.wait(for: [jsExp], timeout: 5.0) == .timedOut {
            XCTFail("JS fetch timed out")
        }
    }

    /// In WKWebView, custom scheme 404 causes fetch() to throw TypeError (not return status 404).
    /// This matches the actual runtime behavior — the HTML template's fetchJSON() uses try/catch → null.
    func testWKWebView_unknownPath_fetchThrows() {
        let usagePath = tmpDir.appendingPathComponent("usage.db").path
        let tokensPath = tmpDir.appendingPathComponent("tokens.db").path
        AnalysisTestDB.createUsageDb(at: usagePath, rows: [])
        AnalysisTestDB.createTokensDb(at: tokensPath)

        let (webView, navExp) = loadWebView(usagePath: usagePath, tokensPath: tokensPath) {
            "<!DOCTYPE html><html><body></body></html>"
        }
        if XCTWaiter.wait(for: [navExp], timeout: 5.0) == .timedOut {
            XCTFail("WKWebView page load timed out")
        }

        let jsExp = expectation(description: "JS executed")
        let jsCode = """
            try {
                await fetch('cut://nonexistent.db');
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
        if XCTWaiter.wait(for: [jsExp], timeout: 5.0) == .timedOut {
            XCTFail("JS fetch timed out")
        }
    }

}
