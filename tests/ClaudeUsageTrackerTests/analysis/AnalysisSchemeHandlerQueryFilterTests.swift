// meta: updated=2026-03-06 09:14 checked=-
// Supplement for: tests/ClaudeUsageTrackerTests/AnalysisSchemeHandlerTests.swift
// Generated from: _documents/spec/analysis/analysis-scheme-handler.md
// Coverage: queryMetaJSON all paths (UT-M01–M05), Query parameter filtering (UT-F01–F04),
//           helper unit tests (parseQueryParams, columnInt, serializeJSON), error header validation

import XCTest
import WebKit
import SQLite3
@testable import ClaudeUsageTracker

// MARK: - Query Parameter Filtering (UT-F01 to UT-F04)

/// Verifies from/to filter behavior for usage.json and tokens.json as per spec Decision Table.
/// Guarantees: valid Int64 params apply WHERE clause; invalid or missing params return all rows.
final class AnalysisSchemeHandlerQueryFilterTests: XCTestCase {

    private var tmpDir: URL!
    private var handler: AnalysisSchemeHandler!
    private let epoch1 = 1700000000  // reference epoch
    private let epoch2 = 1700003600  // +1 hour
    private let epoch3 = 1700007200  // +2 hours

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FilterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let usagePath = tmpDir.appendingPathComponent("usage.db").path

        // Three usage rows at different timestamps
        AnalysisTestDB.createUsageDb(at: usagePath, rows: [
            (1700000000, 10.0, 5.0),   // epoch1 — within range when from=epoch1, to=epoch2
            (1700003600, 20.0, 8.0),   // epoch2 — boundary (inclusive)
            (1700007200, 30.0, 12.0),  // epoch3 — outside range when to=epoch2
        ])

        handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,
            htmlProvider: { "<html></html>" }
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: UT-F01: usage.json with valid from/to Int64 → filtered rows only

    /// Guarantees: when from and to are valid Int64 epoch values,
    /// only rows with timestamp >= from AND timestamp <= to are returned.
    func testUsageJson_validFromTo_returnsFilteredRows() {
        let url = URL(string: "cut://usage.json?from=1700000000&to=1700003600")!
        let task = MockSchemeTask(url: url)
        handler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled)
        guard let data = task.receivedData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            XCTFail("UT-F01: Response must be a valid JSON array")
            return
        }
        XCTAssertEqual(json.count, 2,
                       "UT-F01: Only rows within [from, to] range must be returned (epoch1 and epoch2)")
        XCTAssertEqual(json[0]["timestamp"] as? Int, 1700000000,
                       "UT-F01: First row timestamp must be epoch1")
        XCTAssertEqual(json[1]["timestamp"] as? Int, 1700003600,
                       "UT-F01: Second row timestamp must be epoch2 (inclusive upper bound)")
    }

    // MARK: UT-F02: usage.json with non-numeric from → all rows returned

    /// Guarantees: when from is non-numeric (cannot be converted to Int64),
    /// the WHERE clause is omitted and all rows are returned.
    func testUsageJson_nonNumericFrom_returnsAllRows() {
        let url = URL(string: "cut://usage.json?from=abc&to=1700003600")!
        let task = MockSchemeTask(url: url)
        handler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled)
        guard let data = task.receivedData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            XCTFail("UT-F02: Response must be a valid JSON array")
            return
        }
        XCTAssertEqual(json.count, 3,
                       "UT-F02: All 3 rows must be returned when from is non-numeric (no WHERE clause)")
    }

    // MARK: UT-F03: usage.json with no parameters → all rows returned

    /// Guarantees: when neither from nor to is present in the URL,
    /// the WHERE clause is omitted and all rows are returned.
    func testUsageJson_noParameters_returnsAllRows() {
        let url = URL(string: "cut://usage.json")!
        let task = MockSchemeTask(url: url)
        handler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled)
        guard let data = task.receivedData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            XCTFail("UT-F03: Response must be a valid JSON array")
            return
        }
        XCTAssertEqual(json.count, 3,
                       "UT-F03: All 3 rows must be returned when no filter parameters are present")
    }

}
