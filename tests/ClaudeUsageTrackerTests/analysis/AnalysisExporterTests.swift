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

    func testHtmlTemplate_fetchesTokensJson() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("cut://tokens.json"),
                      "JS must fetch tokens JSON from cut:// scheme handler")
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

    func testHtmlTemplate_containsLoadDataFunction() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("async function loadData"))
    }

    func testHtmlTemplate_containsMainFunction() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("function renderMain(usageData, tokenData)"))
        XCTAssertTrue(html.contains("const main = renderMain"))
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

    func testHtmlTemplate_selectsRequiredTokenColumns() {
        let html = AnalysisExporter.htmlTemplate
        for col in ["model", "input_tokens", "output_tokens",
                     "cache_read_tokens", "cache_creation_tokens"] {
            XCTAssertTrue(html.contains(col),
                          "Token query must select \(col)")
        }
    }

    // MARK: - UI tabs

    func testHtmlTemplate_hasSixTabs() {
        let html = AnalysisExporter.htmlTemplate
        for tab in ["usage", "cost", "scatter", "kde", "heatmap", "cumulative"] {
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
        XCTAssertTrue(html.contains("id=\"globalFrom\""))
        XCTAssertTrue(html.contains("id=\"globalTo\""))
        XCTAssertTrue(html.contains("id=\"applyGlobal\""))
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
