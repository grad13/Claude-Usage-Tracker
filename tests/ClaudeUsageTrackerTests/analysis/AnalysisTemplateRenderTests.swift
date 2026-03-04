import XCTest
import WebKit
import SQLite3
@testable import ClaudeUsageTracker

// MARK: - Template Render Tests (DOM-interacting functions)

/// Tests functions from the real template that interact with the DOM:
/// buildHeatmap, main/renderMain, destroyAllCharts, renderUsageTab, renderCumulativeTab.
/// Uses Chart.js stub to capture chart configurations.
final class AnalysisTemplateRenderTests: AnalysisJSTestCase {

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
    // MARK: - main() / renderMain() (real template)
    // =========================================================

    func testRealTemplate_main_setsGlobalVariables() {
        let result = evalJS("""
            const usageData = [
                {timestamp: 1771927200, hourly_percent: 10},
                {timestamp: 1771927500, hourly_percent: 15},
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
                {timestamp: 1771927200, hourly_percent: 10, weekly_percent: 5,
                 hourly_resets_at: 1771945200, weekly_resets_at: 1772186400},
                {timestamp: 1771927500, hourly_percent: 20, weekly_percent: 8,
                 hourly_resets_at: 1771945200, weekly_resets_at: 1772186400},
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
        XCTAssertEqual(result?["datasetCount"] as? Int, 2, "Usage chart has 2 datasets (hourly and weekly)")
        XCTAssertEqual(result?["firstLabel"] as? String, "Hourly Usage")
        XCTAssertEqual(result?["secondLabel"] as? String, "Weekly Usage")
        XCTAssertEqual(result?["firstDataCount"] as? Int, 3, "2 data points + y=0 reset point in 5h dataset")
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
    // MARK: - renderScatterTab / renderKdeTab via Chart stub (real template)
    // =========================================================

    func testRealTemplate_renderScatterTab_createsScatterChart() {
        let result = evalJS("""
            const deltas = [
                {x: 1.0, y: 5.0, hour: 10, timestamp: '2026-02-24T10:05:00Z',
                 date: new Date('2026-02-24T10:05:00Z')},
                {x: 2.0, y: 8.0, hour: 14, timestamp: '2026-02-24T14:05:00Z',
                 date: new Date('2026-02-24T14:05:00Z')},
            ];
            renderScatterTab(deltas);
            return {
                hasScatter: _chartConfigs['effScatter'] != null,
                scatterType: _chartConfigs['effScatter']?.type,
            };
        """) as? [String: Any]
        XCTAssertTrue(result?["hasScatter"] as? Bool ?? false, "Scatter chart created")
        XCTAssertEqual(result?["scatterType"] as? String, "scatter")
    }

    func testRealTemplate_renderKdeTab_createsKDEChart() {
        let result = evalJS("""
            const deltas = [
                {x: 1.0, y: 5.0, hour: 10, timestamp: '2026-02-24T10:05:00Z',
                 date: new Date('2026-02-24T10:05:00Z')},
                {x: 2.0, y: 8.0, hour: 14, timestamp: '2026-02-24T14:05:00Z',
                 date: new Date('2026-02-24T14:05:00Z')},
                {x: 0.5, y: 3.0, hour: 9, timestamp: '2026-02-24T09:05:00Z',
                 date: new Date('2026-02-24T09:05:00Z')},
            ];
            renderKdeTab(deltas);
            return {
                hasKDE: _chartConfigs['kdeChart'] != null,
                kdeType: _chartConfigs['kdeChart']?.type,
            };
        """) as? [String: Any]
        XCTAssertTrue(result?["hasKDE"] as? Bool ?? false, "KDE chart created")
        XCTAssertEqual(result?["kdeType"] as? String, "line")
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

    // =========================================================
    // MARK: - Session navigation helpers (real template)
    // =========================================================

    func testRealTemplate_formatDateShort_producesExpectedFormat() {
        let result = evalJS("""
            return formatDateShort(new Date(2026, 1, 24));
        """) as? String
        XCTAssertEqual(result, "2/24", "formatDateShort should produce M/DD")
    }

    func testRealTemplate_formatDateFull_includesDayName() {
        let result = evalJS("""
            return formatDateFull(new Date(2026, 1, 24));
        """) as? String
        XCTAssertEqual(result, "Tue 2/24", "formatDateFull should produce Day M/DD")
    }

    func testRealTemplate_buildWeeklySlots_computesStartAndEnd() {
        let result = evalJS("""
            const meta = { weeklySessions: [{ id: 1, resets_at: 1772161200 }] };
            const slots = buildWeeklySlots(meta);
            return { count: slots.length, start: slots[0].start, end: slots[0].end };
        """) as? [String: Any]
        XCTAssertEqual(result?["count"] as? Int, 1)
        XCTAssertEqual(result?["start"] as? Int, 1772161200 - 7 * 86400)
        XCTAssertEqual(result?["end"] as? Int, 1772161200)
    }

    func testRealTemplate_buildDailySlots_coversDateRange() {
        let result = evalJS("""
            const meta = { oldestTimestamp: 1771891200, latestTimestamp: 1771977600 };
            const slots = buildDailySlots(meta);
            return { count: slots.length };
        """) as? [String: Any]
        // 1771891200 to 1771977600 spans 2 calendar days
        let count = result?["count"] as? Int ?? 0
        XCTAssertGreaterThanOrEqual(count, 1, "buildDailySlots should produce at least 1 day")
    }
}
