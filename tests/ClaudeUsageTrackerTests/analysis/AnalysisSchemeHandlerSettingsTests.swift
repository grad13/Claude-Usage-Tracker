// meta: updated=2026-03-07 05:54 checked=-
// Tests for: AnalysisSchemeHandler settingsProvider integration
// Source spec: spec/analysis/analysis-scheme-handler.md
// Generated: 2026-03-07
//
// Covers:
//   - UT-M11: meta.json includes settings key with color/theme data
//   - UT-M12: custom settingsProvider reflected in meta.json response

import XCTest
import WebKit
import SQLite3
@testable import ClaudeUsageTracker

final class AnalysisSchemeHandlerSettingsTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: UT-M11: meta.json with data includes settings key

    func testMetaJson_withData_includesSettings() {
        let usagePath = tmpDir.appendingPathComponent("usage-m11.db").path
        AnalysisTestDB.createUsageDb(at: usagePath, rows: [
            (1771900000, 10.0, 5.0),
        ])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,
            htmlProvider: { "<html></html>" },
            settingsProvider: {
                ["hourly_color": "#64b4ff", "weekly_color": "#ff82b4", "color_theme": "dark"]
            }
        )
        let task = MockSchemeTask(url: URL(string: "cut://meta.json")!)
        handler.webView(WKWebView(), start: task)

        XCTAssertTrue(task.didFinishCalled)
        guard let data = task.receivedData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("UT-M11: meta.json body must be a valid JSON object")
            return
        }

        guard let settings = json["settings"] as? [String: String] else {
            XCTFail("UT-M11: settings key must be a dictionary of strings")
            return
        }
        XCTAssertEqual(settings["hourly_color"], "#64b4ff")
        XCTAssertEqual(settings["weekly_color"], "#ff82b4")
        XCTAssertEqual(settings["color_theme"], "dark")
    }

    // MARK: UT-M12: custom settingsProvider is reflected in response

    func testMetaJson_customSettingsProvider_reflected() {
        let usagePath = tmpDir.appendingPathComponent("usage-m12.db").path
        AnalysisTestDB.createUsageDb(at: usagePath, rows: [
            (1771900000, 10.0, 5.0),
        ])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,
            htmlProvider: { "<html></html>" },
            settingsProvider: {
                ["hourly_color": "#46d250", "weekly_color": "#ffa03c", "color_theme": "light"]
            }
        )
        let task = MockSchemeTask(url: URL(string: "cut://meta.json")!)
        handler.webView(WKWebView(), start: task)

        guard let data = task.receivedData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let settings = json["settings"] as? [String: String] else {
            XCTFail("UT-M12: meta.json must contain settings from custom provider")
            return
        }
        XCTAssertEqual(settings["hourly_color"], "#46d250",
                       "UT-M12: custom hourly_color must be reflected")
        XCTAssertEqual(settings["weekly_color"], "#ffa03c",
                       "UT-M12: custom weekly_color must be reflected")
        XCTAssertEqual(settings["color_theme"], "light",
                       "UT-M12: custom color_theme must be reflected")
    }

    // MARK: Settings not included when result is empty

    func testMetaJson_emptyResult_noSettings() {
        let usagePath = tmpDir.appendingPathComponent("usage-empty.db").path
        AnalysisTestDB.createUsageDb(at: usagePath, rows: [])

        let handler = AnalysisSchemeHandler(
            usageDbPath: usagePath,
            htmlProvider: { "<html></html>" },
            settingsProvider: {
                ["hourly_color": "#64b4ff", "weekly_color": "#ff82b4", "color_theme": "dark"]
            }
        )
        let task = MockSchemeTask(url: URL(string: "cut://meta.json")!)
        handler.webView(WKWebView(), start: task)

        let body = String(data: task.receivedData ?? Data(), encoding: .utf8)
        XCTAssertEqual(body, "{}",
                       "Settings must not be included when result is empty (no usage data, no sessions)")
    }
}
