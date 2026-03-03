import XCTest
import WebKit
import SQLite3
@testable import ClaudeUsageTracker

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
