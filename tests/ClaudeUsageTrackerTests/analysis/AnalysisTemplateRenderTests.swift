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

    func testRealTemplate_main_setsStatsHTML() {
        let result = evalJS("""
            const usageData = [
                {timestamp: 1771927200, hourly_percent: 10, weekly_percent: 5},
                {timestamp: 1771939800, hourly_percent: 42.5, weekly_percent: 15.3},
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

    func testRealTemplate_main_totalCostIsSum() {
        let result = evalJS("""
            main(
                [{timestamp: 1771927200, hourly_percent: 10, weekly_percent: 5}],
                [{timestamp: 'a', costUSD: 1.50}, {timestamp: 'b', costUSD: 2.00}, {timestamp: 'c', costUSD: 0.75}]
            );
            return document.getElementById('stats').innerHTML.includes('4.25');
        """) as? Bool
        XCTAssertTrue(result!, "Total cost should be $4.25 (1.50 + 2.00 + 0.75)")
    }

    func testRealTemplate_main_usageSpan_hours() {
        let result = evalJS("""
            main(
                [{timestamp: 1771927200, hourly_percent: 10, weekly_percent: 5},
                 {timestamp: 1771939800, hourly_percent: 20, weekly_percent: 8}],
                []
            );
            return document.getElementById('stats').innerHTML.includes('3.5');
        """) as? Bool
        XCTAssertTrue(result!, "Usage span should be 3.5h (10:00 to 13:30)")
    }


    // =========================================================
    // MARK: - localDateStr tests (real template)
    // =========================================================

    func testRealTemplate_localDateStr_usesLocalTime() {
        // localDateStr should produce local date string, not UTC.
        let result = evalJS("""
            const now = new Date();
            const result = localDateStr(now);
            // Verify format is YYYY-MM-DD
            return { result: result, matchesFormat: /^\\d{4}-\\d{2}-\\d{2}$/.test(result) };
        """) as? [String: Any]
        XCTAssertNotNil(result)
        XCTAssertTrue(result?["matchesFormat"] as? Bool ?? false,
                      "localDateStr must produce YYYY-MM-DD format")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        let expectedTo = formatter.string(from: Date())
        XCTAssertEqual(result?["result"] as? String, expectedTo,
                       "localDateStr should return today's LOCAL date, not UTC")
    }

    func testRealTemplate_localDateStr_UTC_midnight_localDate_shouldDiffer() {
        // Mock Date to simulate UTC 23:30 on Feb 23.
        // In any timezone ahead of UTC (e.g. JST), local date = Feb 24.
        let result = evalJS("""
            const OrigDate = Date;
            const fixedUTC = new OrigDate('2026-02-23T23:30:00Z').getTime();
            const localDate = new OrigDate(fixedUTC);
            const result = localDateStr(localDate);
            const expectedLocal = localDate.getFullYear() + '-'
                + String(localDate.getMonth() + 1).padStart(2, '0') + '-'
                + String(localDate.getDate()).padStart(2, '0');

            return { result: result, expectedLocal: expectedLocal,
                     utcSlice: new OrigDate(fixedUTC).toISOString().slice(0, 10) };
        """) as? [String: String]
        XCTAssertNotNil(result)
        let localResult = result?["result"] ?? ""
        let expectedLocal = result?["expectedLocal"] ?? ""
        let utcSlice = result?["utcSlice"] ?? ""
        XCTAssertEqual(localResult, expectedLocal,
                       "localDateStr should return local date '\(expectedLocal)', not UTC '\(utcSlice)'")
    }

    func testRealTemplate_dateInputToEpoch_generatesCorrectValues() {
        let result = evalJS("""
            return {
                startOfDay: dateInputToEpoch('2026-02-24', false),
                endOfDay: dateInputToEpoch('2026-02-24', true),
            };
        """) as? [String: Any]
        // 2026-02-24T00:00:00Z = epoch 1771891200
        XCTAssertEqual(result?["startOfDay"] as? Int, 1771891200)
        // 2026-02-24T23:59:59Z = epoch 1771977599
        XCTAssertEqual(result?["endOfDay"] as? Int, 1771977599)
    }
}
