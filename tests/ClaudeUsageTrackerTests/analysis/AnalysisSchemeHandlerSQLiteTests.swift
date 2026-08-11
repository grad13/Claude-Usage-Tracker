// meta: updated=2026-08-11 checked=-
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

    private func createExactUsageDb(at path: String) {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        guard let db else { return }
        defer { sqlite3_close(db) }

        let sql = """
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
                five_hour_resets_at REAL,
                seven_day_resets_at REAL,
                resets_at_observed_at REAL,
                CHECK (hourly_percent IS NOT NULL OR weekly_percent IS NOT NULL)
            );
            INSERT INTO hourly_sessions (id, resets_at) VALUES (1, 1786453200);
            INSERT INTO weekly_sessions (id, resets_at) VALUES (1, 1787058000);
            INSERT INTO usage_log (
                timestamp, hourly_percent, weekly_percent,
                hourly_session_id, weekly_session_id,
                five_hour_resets_at, seven_day_resets_at, resets_at_observed_at
            ) VALUES (
                1786450000, 42.5, 18.25, 1, 1,
                1786451696.625, 1787023269.125, 1786449123.875
            );
            """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
    }

    // MARK: - JSON data correctness

    func testUsageJson_returnsCorrectData() {
        let usagePath = tmpDir.appendingPathComponent("usage.db").path
        AnalysisTestDB.createUsageDb(at: usagePath, rows: [
            (1771927200, 25.5, 12.3),
            (1771927500, 80.0, 45.0),
        ])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,
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

    func testUsageJson_exactSchemaPreservesResetAndObservationSubseconds() {
        let usagePath = tmpDir.appendingPathComponent("usage-exact.db").path
        createExactUsageDb(at: usagePath)

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,
            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "cut://usage.json")!)
        handler.webView(WKWebView(), start: task)

        let json = try! JSONSerialization.jsonObject(with: task.receivedData!) as! [[String: Any]]
        let row = try! XCTUnwrap(json.first)
        XCTAssertEqual(row["hourly_resets_at"] as! Double,
                       1_786_451_696.625, accuracy: 0.000_001)
        XCTAssertEqual(row["weekly_resets_at"] as! Double,
                       1_787_023_269.125, accuracy: 0.000_001)
        XCTAssertEqual(row["hourly_resets_at_observed_at"] as! Double,
                       1_786_449_123.875, accuracy: 0.000_001)
        XCTAssertEqual(row["weekly_resets_at_observed_at"] as! Double,
                       1_786_449_123.875, accuracy: 0.000_001)
        XCTAssertEqual(row["resets_at_observed_at"] as! Double,
                       1_786_449_123.875, accuracy: 0.000_001)
    }

    func testMetaJson_prefersExactResetsAndKeepsNormalizedSessionIdentity() {
        let usagePath = tmpDir.appendingPathComponent("usage-exact-meta.db").path
        createExactUsageDb(at: usagePath)

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,
            htmlProvider: { "<html></html>" }
        )
        let task = MockSchemeTask(url: URL(string: "cut://meta.json")!)
        handler.webView(WKWebView(), start: task)

        let json = try! JSONSerialization.jsonObject(with: task.receivedData!) as! [String: Any]
        XCTAssertEqual(json["latestSevenDayResetsAt"] as! Double,
                       1_787_023_269.125, accuracy: 0.000_001)
        XCTAssertEqual(json["latestSevenDayResetsAtObservedAt"] as! Double,
                       1_786_449_123.875, accuracy: 0.000_001)

        let weekly = try! XCTUnwrap((json["weeklySessions"] as? [[String: Any]])?.first)
        XCTAssertEqual(weekly["resets_at"] as! Double,
                       1_787_023_269.125, accuracy: 0.000_001)
        XCTAssertEqual(weekly["normalized_resets_at"] as? Int, 1_787_058_000)
        XCTAssertEqual(weekly["resets_at_observed_at"] as! Double,
                       1_786_449_123.875, accuracy: 0.000_001)

        let hourly = try! XCTUnwrap((json["hourlySessions"] as? [[String: Any]])?.first)
        XCTAssertEqual(hourly["resets_at"] as! Double,
                       1_786_451_696.625, accuracy: 0.000_001)
        XCTAssertEqual(hourly["normalized_resets_at"] as? Int, 1_786_453_200)
        XCTAssertEqual(hourly["resets_at_observed_at"] as! Double,
                       1_786_449_123.875, accuracy: 0.000_001)
    }

    // MARK: - Empty DB returns empty JSON array

    func testEmptyDb_returnsEmptyJsonArray() {
        let usagePath = tmpDir.appendingPathComponent("usage.db").path
        AnalysisTestDB.createUsageDb(at: usagePath, rows: [])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,
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
        AnalysisTestDB.createUsageDb(at: usagePath, rows: [])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,
            htmlProvider: { AnalysisExporter.htmlTemplate }
        )
        let task = MockSchemeTask(url: URL(string: "cut://analysis.html")!)
        handler.webView(WKWebView(), start: task)

        let html = String(data: task.receivedData!, encoding: .utf8)!
        // The served HTML must be the full template, not truncated or corrupted
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(html.hasSuffix("</html>\n") || html.hasSuffix("</html>"))
        XCTAssertTrue(html.contains("cut://usage.json"))
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

        // Create 1000 rows — similar to real production data (5-min intervals)
        let baseEpoch = 1771927200
        var rows: [(Int, Double, Double)] = []
        for i in 0..<1000 {
            rows.append((baseEpoch + i * 300, Double(i % 100), Double(i % 50)))
        }
        AnalysisTestDB.createUsageDb(at: usagePath, rows: rows)

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,
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
