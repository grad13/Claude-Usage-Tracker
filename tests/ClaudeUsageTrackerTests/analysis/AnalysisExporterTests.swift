// meta: updated=2026-03-06 09:49 checked=-
import XCTest
@testable import ClaudeUsageTracker

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
        XCTAssertTrue(html.contains("<title>ClaudeUsageTracker"))
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

    // MARK: - JSON loading via fetch from cut:// scheme

    func testHtmlTemplate_fetchesUsageJson() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("cut://usage.json"),
                      "JS must fetch usage JSON from cut:// scheme handler")
    }

    func testHtmlTemplate_containsFetchJSONFunction() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("fetchJSON"),
                      "JS must have fetchJSON helper to load data via cut:// scheme")
    }

    func testHtmlTemplate_doesNotUseBase64Injection() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertFalse(html.contains("__USAGE_DB_B64"),
                       "DB loading should use fetch, not base64 injection")
    }

    // MARK: - JS data processing functions

    func testHtmlTemplate_containsLoadDataFunction() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("async function loadData"))
    }

    func testHtmlTemplate_containsMainFunction() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("function renderMain"))
    }

    // MARK: - JSON property keys (column names used as JS property accessors)

    func testHtmlTemplate_selectsRequiredUsageColumns() {
        let html = AnalysisExporter.htmlTemplate
        for col in ["timestamp", "hourly_percent", "weekly_percent",
                     "hourly_resets_at"] {
            XCTAssertTrue(html.contains(col),
                          "Usage query must select \(col)")
        }
    }

    // MARK: - UI elements

    func testHtmlTemplate_hasUsageChartCanvas() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("id=\"usageTimeline\""),
                      "Canvas 'usageTimeline' must exist for Chart.js")
    }

    func testHtmlTemplate_hasSessionNavControls() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("data-mode=\"sessionWeekly\""))
        XCTAssertTrue(html.contains("data-mode=\"calDay\""))
        XCTAssertTrue(html.contains("id=\"navPrev\""))
        XCTAssertTrue(html.contains("id=\"navNext\""))
        XCTAssertTrue(html.contains("id=\"sessionSelect\""))
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
}
