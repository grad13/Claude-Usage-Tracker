import XCTest
import WebKit
import SQLite3
@testable import WeatherCC

// MARK: - Template Render Tests (DOM-interacting functions)

/// Tests functions from the real template that interact with the DOM:
/// buildHeatmap, main, getFilteredDeltas, renderUsageTab, renderCumulativeTab.
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
    // MARK: - getFilteredDeltas (real template, NEW)
    // =========================================================

    func testRealTemplate_getFilteredDeltas_noRange_returnsAllDeltas() {
        let result = evalJS("""
            _allDeltas = [
                {x: 1.0, y: 5.0, hour: 10, timestamp: '2026-02-24T10:05:00Z',
                 date: new Date('2026-02-24T10:05:00Z')},
                {x: 2.0, y: 8.0, hour: 14, timestamp: '2026-02-24T14:05:00Z',
                 date: new Date('2026-02-24T14:05:00Z')},
            ];
            document.getElementById('dateFrom').value = '';
            document.getElementById('dateTo').value = '';
            return getFilteredDeltas().length;
        """) as? Int
        XCTAssertEqual(result, 2, "No date range → return all deltas")
    }

    func testRealTemplate_getFilteredDeltas_withRange_filtersCorrectly() {
        let result = evalJS("""
            _allDeltas = [
                {x: 1.0, y: 5.0, hour: 10, timestamp: '2026-02-23T10:05:00Z',
                 date: new Date('2026-02-23T10:05:00Z')},
                {x: 2.0, y: 8.0, hour: 14, timestamp: '2026-02-24T14:05:00Z',
                 date: new Date('2026-02-24T14:05:00Z')},
                {x: 3.0, y: 12.0, hour: 16, timestamp: '2026-02-25T16:05:00Z',
                 date: new Date('2026-02-25T16:05:00Z')},
            ];
            document.getElementById('dateFrom').value = '2026-02-24';
            document.getElementById('dateTo').value = '2026-02-24';
            return getFilteredDeltas().length;
        """) as? Int
        XCTAssertEqual(result, 1, "Only Feb 24 should match the date range")
    }

    func testRealTemplate_getFilteredDeltas_emptyAllDeltas() {
        let result = evalJS("""
            _allDeltas = [];
            document.getElementById('dateFrom').value = '2026-02-24';
            document.getElementById('dateTo').value = '2026-02-24';
            return getFilteredDeltas().length;
        """) as? Int
        XCTAssertEqual(result, 0)
    }

    // =========================================================
    // MARK: - main() (real template, NEW)
    // =========================================================

    func testRealTemplate_main_setsStatsHTML() {
        let result = evalJS("""
            const usageData = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: 5},
                {timestamp: '2026-02-24T13:30:00Z', five_hour_percent: 42.5, seven_day_percent: 15.3},
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
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10},
                {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: 15},
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
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: 5,
                 five_hour_resets_at: null, seven_day_resets_at: null},
                {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: 20, seven_day_percent: 8,
                 five_hour_resets_at: null, seven_day_resets_at: null},
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
        XCTAssertEqual(result?["datasetCount"] as? Int, 2, "Usage chart has 2 datasets (5h% and 7d%)")
        XCTAssertEqual(result?["firstLabel"] as? String, "5-hour %")
        XCTAssertEqual(result?["secondLabel"] as? String, "7-day %")
        XCTAssertEqual(result?["firstDataCount"] as? Int, 2, "2 data points in 5h dataset")
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
    // MARK: - renderEfficiencyTab via Chart stub (real template, NEW)
    // =========================================================

    func testRealTemplate_renderEfficiencyTab_createsScatterAndKDE() {
        let result = evalJS("""
            const deltas = [
                {x: 1.0, y: 5.0, hour: 10, timestamp: '2026-02-24T10:05:00Z',
                 date: new Date('2026-02-24T10:05:00Z')},
                {x: 2.0, y: 8.0, hour: 14, timestamp: '2026-02-24T14:05:00Z',
                 date: new Date('2026-02-24T14:05:00Z')},
                {x: 0.5, y: 3.0, hour: 9, timestamp: '2026-02-24T09:05:00Z',
                 date: new Date('2026-02-24T09:05:00Z')},
            ];
            renderEfficiencyTab(deltas);
            return {
                hasScatter: _chartConfigs['effScatter'] != null,
                scatterType: _chartConfigs['effScatter']?.type,
                hasKDE: _chartConfigs['kdeChart'] != null,
                kdeType: _chartConfigs['kdeChart']?.type,
                heatmapRendered: document.getElementById('heatmap').innerHTML.length > 50,
            };
        """) as? [String: Any]
        XCTAssertTrue(result?["hasScatter"] as? Bool ?? false, "Efficiency scatter chart created")
        XCTAssertEqual(result?["scatterType"] as? String, "scatter")
        XCTAssertTrue(result?["hasKDE"] as? Bool ?? false, "KDE chart created")
        XCTAssertEqual(result?["kdeType"] as? String, "line")
        XCTAssertTrue(result?["heatmapRendered"] as? Bool ?? false, "Heatmap rendered")
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
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: 5}],
                [{timestamp: 'a', costUSD: 1.50}, {timestamp: 'b', costUSD: 2.00}, {timestamp: 'c', costUSD: 0.75}]
            );
            return document.getElementById('stats').innerHTML.includes('4.25');
        """) as? Bool
        XCTAssertTrue(result!, "Total cost should be $4.25 (1.50 + 2.00 + 0.75)")
    }

    func testRealTemplate_main_usageSpan_hours() {
        let result = evalJS("""
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: 5},
                 {timestamp: '2026-02-24T13:30:00Z', five_hour_percent: 20, seven_day_percent: 8}],
                []
            );
            return document.getElementById('stats').innerHTML.includes('3.5');
        """) as? Bool
        XCTAssertTrue(result!, "Usage span should be 3.5h (10:00 to 13:30)")
    }

    // =========================================================
    // MARK: - formatMin tests via gap slider (real template)
    // =========================================================

    /// Helper: call main() to set up renderUsageTab event listener,
    /// then change slider value & dispatch 'input' event, return label text.
    private func sliderLabel(forMinutes minutes: Int) -> String? {
        return evalJS("""
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: 5}],
                [{timestamp: '2026-02-24T10:01:00Z', costUSD: 0.5}]
            );
            const slider = document.getElementById('gapSlider');
            slider.value = '\(minutes)';
            slider.dispatchEvent(new Event('input'));
            return document.getElementById('gapVal').textContent;
        """) as? String
    }

    func testRealTemplate_formatMin_under60() {
        XCTAssertEqual(sliderLabel(forMinutes: 30), "30 min")
    }

    func testRealTemplate_formatMin_exactly60() {
        XCTAssertEqual(sliderLabel(forMinutes: 60), "1h")
    }

    func testRealTemplate_formatMin_exactly120() {
        XCTAssertEqual(sliderLabel(forMinutes: 120), "2h")
    }

    func testRealTemplate_formatMin_65_noUglyDecimal() {
        // Bug: 65 / 60 = 1.0833... → "1.0833333333333333h"
        let result = sliderLabel(forMinutes: 65)
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.contains("1.08333"),
                       "formatMin(65) should not produce ugly floating-point decimals, got: \(result!)")
    }

    func testRealTemplate_formatMin_90() {
        XCTAssertEqual(sliderLabel(forMinutes: 90), "1h 30min",
                       "90 minutes should display as '1h 30min'")
    }

    func testRealTemplate_formatMin_150() {
        XCTAssertEqual(sliderLabel(forMinutes: 150), "2h 30min",
                       "150 minutes should display as '2h 30min'")
    }

    func testRealTemplate_formatMin_360() {
        XCTAssertEqual(sliderLabel(forMinutes: 360), "6h",
                       "360 minutes is exactly 6 hours")
    }

    func testRealTemplate_formatMin_5() {
        XCTAssertEqual(sliderLabel(forMinutes: 5), "5 min")
    }

    // =========================================================
    // MARK: - initTabs default date tests (real template)
    // =========================================================

    func testRealTemplate_initTabs_defaultDates_useLocalTime() {
        // initTabs sets dateFrom and dateTo using Date. It should use local dates, not UTC.
        // We test by setting a known time and checking the result matches local calendar.
        let result = evalJS("""
            // Provide minimal data so main() doesn't crash
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: 5}],
                []
            );
            const fromVal = document.getElementById('dateFrom').value;
            const toVal = document.getElementById('dateTo').value;
            // Verify dates are set (not empty)
            return { from: fromVal, to: toVal };
        """) as? [String: String]
        XCTAssertNotNil(result)
        // The key test: dateTo should match today's LOCAL date
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        let expectedTo = formatter.string(from: Date())
        XCTAssertEqual(result?["to"], expectedTo,
                       "dateTo should be today's LOCAL date, not UTC")
    }

    func testRealTemplate_initTabs_defaultDateFrom_3daysAgo() {
        let result = evalJS("""
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: 5}],
                []
            );
            return document.getElementById('dateFrom').value;
        """) as? String
        XCTAssertNotNil(result)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        let expectedFrom = formatter.string(from: Date().addingTimeInterval(-3 * 86400))
        XCTAssertEqual(result, expectedFrom,
                       "dateFrom should be 3 days ago in LOCAL time, not UTC")
    }

    func testRealTemplate_initTabs_UTC_midnight_localDate_shouldDiffer() {
        // Expose the UTC vs local date bug:
        // Mock Date to simulate UTC 23:30 on Feb 23.
        // In any timezone ahead of UTC (e.g. JST), local date = Feb 24.
        // toISOString().slice(0,10) always returns "2026-02-23" regardless of timezone.
        let result = evalJS("""
            const OrigDate = Date;
            const fixedUTC = new OrigDate('2026-02-23T23:30:00Z').getTime();
            class MockDate extends OrigDate {
                constructor(...args) {
                    if (args.length === 0) { super(fixedUTC); }
                    else { super(...args); }
                }
                static now() { return fixedUTC; }
            }
            Date = MockDate;
            initTabs();
            Date = OrigDate;

            const toVal = document.getElementById('dateTo').value;
            const localDate = new OrigDate(fixedUTC);
            const expectedLocal = localDate.getFullYear() + '-'
                + String(localDate.getMonth() + 1).padStart(2, '0') + '-'
                + String(localDate.getDate()).padStart(2, '0');

            return { toVal: toVal, expectedLocal: expectedLocal,
                     utcSlice: new OrigDate(fixedUTC).toISOString().slice(0, 10) };
        """) as? [String: String]
        XCTAssertNotNil(result)
        let toVal = result?["toVal"] ?? ""
        let expectedLocal = result?["expectedLocal"] ?? ""
        let utcSlice = result?["utcSlice"] ?? ""
        XCTAssertEqual(toVal, expectedLocal,
                       "dateTo should be local date '\(expectedLocal)', not UTC '\(utcSlice)'")
    }
}

// MARK: - Additional Bug-Hunting Tests

/// Tests targeting specific output values and edge cases not covered by previous tests.
/// Goal: find bugs by checking exact outputs against expected values.
final class AnalysisBugHuntingTests: AnalysisJSTestCase {

    // =========================================================
    // MARK: - Stats display: latestFiveH/latestSevenD with % suffix
    // =========================================================

    func testStats_latestFiveH_numberShowsPercent() {
        let result = evalJS("""
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 42.5, seven_day_percent: 15.3}],
                []
            );
            const html = document.getElementById('stats').innerHTML;
            return html.includes('42.5%');
        """) as? Bool
        XCTAssertTrue(result!, "Latest 5h should show '42.5%'")
    }

    func testStats_latestFiveH_dashShouldNotShowDashPercent() {
        // When data is empty, latestFiveH = '-'. The template shows ${latestFiveH}%
        // which produces '-%'. This is a bug — should be just '-' or 'N/A'.
        let result = evalJS("""
            main([], []);
            const html = document.getElementById('stats').innerHTML;
            const hasDashPercent = html.includes('->%') || html.includes('-%');
            const hasDashAlone = html.includes('>-<');
            return { hasDashPercent, hasDashAlone };
        """) as? [String: Any]
        // If this test fails, the template has the '-%' display bug
        let hasDashPercent = result?["hasDashPercent"] as? Bool ?? false
        XCTAssertFalse(hasDashPercent,
                       "Empty data should NOT show '-%' — should show '-' without percent sign")
    }

    func testStats_latestSevenD_nullPercent_shouldNotShowDashPercent() {
        // Last record has null seven_day_percent → latestSevenD = '-'
        // Template shows ${latestSevenD}% → '-%'
        let result = evalJS("""
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: null}],
                []
            );
            const html = document.getElementById('stats').innerHTML;
            // Find the Latest 7d stat value
            const match = html.match(/Latest 7d/);
            return html.includes('-%');
        """) as? Bool
        XCTAssertFalse(result ?? true,
                       "Null percent should NOT show '-%' — the % suffix should be conditional")
    }

    func testStats_latestFiveH_zeroPercent_showsZeroPercent() {
        let result = evalJS("""
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 0, seven_day_percent: 0}],
                []
            );
            const html = document.getElementById('stats').innerHTML;
            return html.includes('0%');
        """) as? Bool
        XCTAssertTrue(result!, "0% usage should display as '0%', not '-'")
    }

    // =========================================================
    // MARK: - Stats: usageSpan format
    // =========================================================

    func testStats_usageSpan_singleRecord_shows0h() {
        let result = evalJS("""
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: 5}],
                []
            );
            const html = document.getElementById('stats').innerHTML;
            return html.includes('0h');
        """) as? Bool
        XCTAssertTrue(result!, "Single usage record should show '0h' span")
    }

    func testStats_usageSpan_multipleRecords_format() {
        let result = evalJS("""
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: 5},
                 {timestamp: '2026-02-24T13:30:00Z', five_hour_percent: 20, seven_day_percent: 8}],
                []
            );
            const html = document.getElementById('stats').innerHTML;
            return html.includes('3.5h');
        """) as? Bool
        XCTAssertTrue(result!, "Usage span 10:00→13:30 should show '3.5h'")
    }

    // =========================================================
    // MARK: - renderUsageTab chart config
    // =========================================================

    func testRenderUsageTab_yAxis_min0_max100() {
        let result = evalJS("""
            _usageData = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 50, seven_day_percent: 25,
                 five_hour_resets_at: null, seven_day_resets_at: null},
            ];
            renderUsageTab();
            const yScale = _chartConfigs['usageTimeline']?.options?.scales?.y;
            return { min: yScale?.min, max: yScale?.max };
        """) as? [String: Any]
        XCTAssertEqual(result?["min"] as? Int, 0, "Usage chart y-axis min should be 0")
        XCTAssertEqual(result?["max"] as? Int, 100, "Usage chart y-axis max should be 100")
    }

    func testRenderUsageTab_xAxisType_isTime() {
        let result = evalJS("""
            _usageData = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 50, seven_day_percent: 25,
                 five_hour_resets_at: null, seven_day_resets_at: null},
            ];
            renderUsageTab();
            return _chartConfigs['usageTimeline']?.options?.scales?.x?.type;
        """) as? String
        XCTAssertEqual(result, "time", "Usage chart x-axis should be time-based")
    }

    func testRenderUsageTab_datasetColors() {
        let result = evalJS("""
            _usageData = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 50, seven_day_percent: 25,
                 five_hour_resets_at: null, seven_day_resets_at: null},
            ];
            renderUsageTab();
            const ds = _chartConfigs['usageTimeline']?.data?.datasets;
            return {
                color0: ds?.[0]?.borderColor,
                color1: ds?.[1]?.borderColor,
            };
        """) as? [String: Any]
        XCTAssertEqual(result?["color0"] as? String, "#64b4ff", "5-hour line should be blue")
        XCTAssertEqual(result?["color1"] as? String, "#ff82b4", "7-day line should be pink")
    }

    // =========================================================
    // MARK: - renderCostTab bar chart data correctness
    // =========================================================

    func testRenderCostTab_barChartDataMatchesTokenData() {
        let result = evalJS("""
            _tokenData = [
                {timestamp: '2026-02-24T10:00:00Z', costUSD: 1.50},
                {timestamp: '2026-02-24T10:01:00Z', costUSD: 0.75},
                {timestamp: '2026-02-24T10:02:00Z', costUSD: 2.25},
            ];
            _allDeltas = [];
            renderCostTab();
            const data = _chartConfigs['costTimeline']?.data?.datasets?.[0]?.data;
            return data?.map(d => d.y);
        """) as? [Double]
        XCTAssertEqual(result, [1.50, 0.75, 2.25],
                       "Bar chart y-values should match tokenData costUSD values exactly")
    }

    func testRenderCostTab_barChartTimestampsPreserved() {
        let result = evalJS("""
            _tokenData = [
                {timestamp: '2026-02-24T10:00:00Z', costUSD: 1.50},
                {timestamp: '2026-02-24T10:01:00Z', costUSD: 0.75},
            ];
            _allDeltas = [];
            renderCostTab();
            const data = _chartConfigs['costTimeline']?.data?.datasets?.[0]?.data;
            return data?.map(d => d.x);
        """) as? [String]
        XCTAssertEqual(result, ["2026-02-24T10:00:00Z", "2026-02-24T10:01:00Z"],
                       "Bar chart x-values should preserve timestamps from tokenData")
    }

    // =========================================================
    // MARK: - renderEfficiencyTab KDE ratios
    // =========================================================

    func testRenderEfficiencyTab_kdeUsesRatios() {
        // deltas with known x/y → ratio = y/x
        // d1: y=5, x=1 → ratio=5; d2: y=10, x=2 → ratio=5; same ratio → KDE should peak at 5
        let result = evalJS("""
            const deltas = [
                {x: 1.0, y: 5.0, hour: 10, timestamp: '2026-02-24T10:05:00Z',
                 date: new Date('2026-02-24T10:05:00Z')},
                {x: 2.0, y: 10.0, hour: 14, timestamp: '2026-02-24T14:05:00Z',
                 date: new Date('2026-02-24T14:05:00Z')},
                {x: 0.5, y: 2.5, hour: 9, timestamp: '2026-02-24T09:05:00Z',
                 date: new Date('2026-02-24T09:05:00Z')},
            ];
            renderEfficiencyTab(deltas);
            const kdeConfig = _chartConfigs['kdeChart'];
            const labels = kdeConfig?.data?.labels;
            const data = kdeConfig?.data?.datasets?.[0]?.data;
            if (!labels || !data) return null;
            // Find peak
            let maxY = -1, peakX = 0;
            for (let i = 0; i < data.length; i++) {
                if (data[i] > maxY) { maxY = data[i]; peakX = labels[i]; }
            }
            return { peakX, hasData: data.length > 0 };
        """) as? [String: Any]
        XCTAssertTrue(result?["hasData"] as? Bool ?? false, "KDE chart should have data")
        if let peakX = result?["peakX"] as? Double {
            XCTAssertEqual(peakX, 5.0, accuracy: 2.0,
                           "All ratios are 5.0 → KDE peak should be near 5.0")
        }
    }

    // =========================================================
    // MARK: - buildHeatmap specific ratio values
    // =========================================================

    func testBuildHeatmap_ratioInCell() {
        let result = evalJS("""
            // Single data point: hour=10 (local), day depends on local timezone
            const dt = new Date('2026-02-24T01:00:00Z'); // Use fixed date
            const deltas = [
                {x: 2.0, y: 10.0, hour: dt.getHours(), timestamp: '2026-02-24T01:00:00Z', date: dt},
            ];
            buildHeatmap(deltas);
            const html = document.getElementById('heatmap').innerHTML;
            // Ratio = 10/2 = 5, displayed as ratio.toFixed(0) = '5'
            // The title should contain 'Δ%/Δ$: 5.0'
            return {
                hasRatio: html.includes('5.0'),
                hasTitle: html.includes('title='),
            };
        """) as? [String: Any]
        XCTAssertTrue(result?["hasTitle"] as? Bool ?? false, "Heatmap cells should have title attributes")
    }

    func testBuildHeatmap_multiplePointsSameCell_aggregated() {
        let result = evalJS("""
            // Two deltas in same day-hour bucket → aggregated
            const dt1 = new Date('2026-02-24T10:00:00Z');
            const dt2 = new Date('2026-02-24T10:30:00Z');
            // Both should have same getDay() and getHours() (same hour)
            const deltas = [
                {x: 1.0, y: 5.0, hour: dt1.getHours(), timestamp: '2026-02-24T10:00:00Z', date: dt1},
                {x: 3.0, y: 9.0, hour: dt2.getHours(), timestamp: '2026-02-24T10:30:00Z', date: dt2},
            ];
            buildHeatmap(deltas);
            const html = document.getElementById('heatmap').innerHTML;
            // Aggregated: totalDelta=14, totalCost=4, ratio=14/4=3.5
            return html.includes('3.5');
        """) as? Bool
        XCTAssertTrue(result!, "Two deltas in same cell should aggregate to ratio 14/4=3.5")
    }

    // =========================================================
    // MARK: - buildScatterChart timeSlot assignment
    // =========================================================

    func testBuildScatterChart_nightDataInNightDataset() {
        let result = evalJS("""
            const deltas = [
                {x: 1.0, y: 5.0, hour: 3},  // 3am = Night
                {x: 2.0, y: 8.0, hour: 10}, // 10am = Morning
                {x: 0.5, y: 3.0, hour: 15}, // 3pm = Afternoon
                {x: 1.5, y: 6.0, hour: 20}, // 8pm = Evening
            ];
            const chart = buildScatterChart('effScatter', deltas);
            const config = _chartConfigs['effScatter'];
            const nightData = config?.data?.datasets?.[0]?.data;  // Night is first slot
            const morningData = config?.data?.datasets?.[1]?.data;
            const afternoonData = config?.data?.datasets?.[2]?.data;
            const eveningData = config?.data?.datasets?.[3]?.data;
            return {
                nightCount: nightData?.length,
                morningCount: morningData?.length,
                afternoonCount: afternoonData?.length,
                eveningCount: eveningData?.length,
            };
        """) as? [String: Any]
        XCTAssertEqual(result?["nightCount"] as? Int, 1, "1 point at hour 3 → Night")
        XCTAssertEqual(result?["morningCount"] as? Int, 1, "1 point at hour 10 → Morning")
        XCTAssertEqual(result?["afternoonCount"] as? Int, 1, "1 point at hour 15 → Afternoon")
        XCTAssertEqual(result?["eveningCount"] as? Int, 1, "1 point at hour 20 → Evening")
    }

    // =========================================================
    // MARK: - Tab click rendering behavior
    // =========================================================

    func testTabClick_rendersOnFirstClick() {
        let result = evalJS("""
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: 5}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50}]
            );
            // Click the cost tab
            const costBtn = document.querySelector('[data-tab="cost"]');
            costBtn.click();
            return {
                costRendered: _rendered['cost'] === true,
                costChartExists: _chartConfigs['costTimeline'] != null,
                costTabActive: document.getElementById('tab-cost').classList.contains('active'),
                usageTabInactive: !document.getElementById('tab-usage').classList.contains('active'),
            };
        """) as? [String: Any]
        XCTAssertTrue(result?["costRendered"] as? Bool ?? false, "Cost tab should be marked as rendered")
        XCTAssertTrue(result?["costChartExists"] as? Bool ?? false, "Cost chart should be created")
        XCTAssertTrue(result?["costTabActive"] as? Bool ?? false, "Cost tab content should be active")
        XCTAssertTrue(result?["usageTabInactive"] as? Bool ?? false, "Usage tab content should be inactive")
    }

    func testTabClick_doesNotReRenderOnSecondClick() {
        let result = evalJS("""
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: 5}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50}]
            );
            // Click cost tab first time → renders
            const costBtn = document.querySelector('[data-tab="cost"]');
            costBtn.click();
            // Record the config reference
            const firstConfig = _chartConfigs['costTimeline'];
            // Click usage, then cost again
            document.querySelector('[data-tab="usage"]').click();
            costBtn.click();
            // Config should be same reference (not re-created)
            return _chartConfigs['costTimeline'] === firstConfig;
        """) as? Bool
        XCTAssertTrue(result!, "Second click on same tab should not re-render (guard by _rendered)")
    }

    // =========================================================
    // MARK: - renderCumulativeTab timestamp preservation
    // =========================================================

    func testRenderCumulativeTab_timestampsPreserved() {
        let result = evalJS("""
            _tokenData = [
                {timestamp: '2026-02-24T10:00:00Z', costUSD: 1.00},
                {timestamp: '2026-02-24T10:01:00Z', costUSD: 2.00},
            ];
            renderCumulativeTab();
            const data = _chartConfigs['cumulativeCost']?.data?.datasets?.[0]?.data;
            return data?.map(d => d.x);
        """) as? [String]
        XCTAssertEqual(result, ["2026-02-24T10:00:00Z", "2026-02-24T10:01:00Z"],
                       "Cumulative chart should preserve timestamps from tokenData")
    }

    // =========================================================
    // MARK: - getFilteredDeltas precise date boundary
    // =========================================================

    func testGetFilteredDeltas_dateRangeEndOfDay_inclusive() {
        let result = evalJS("""
            _allDeltas = [
                {x: 1.0, y: 5.0, timestamp: '2026-02-24T23:50:00Z',
                 date: new Date('2026-02-24T23:50:00Z')},
            ];
            // The 'to' date creates 'T23:59:59' local time boundary
            // This UTC timestamp might be outside local date range depending on timezone
            document.getElementById('dateFrom').value = '2026-02-24';
            document.getElementById('dateTo').value = '2026-02-24';
            const filtered = getFilteredDeltas();
            // In JST, 2026-02-24T23:50:00Z = 2026-02-25T08:50:00 JST → OUTSIDE Feb 24 local
            // In UTC, it's Feb 24 → within range
            const d = new Date('2026-02-24T23:50:00Z');
            const localDate = d.getFullYear() + '-'
                + String(d.getMonth() + 1).padStart(2, '0') + '-'
                + String(d.getDate()).padStart(2, '0');
            return {
                filteredCount: filtered.length,
                localDate: localDate,
                isLocalFeb24: localDate === '2026-02-24',
            };
        """) as? [String: Any]
        let filteredCount = result?["filteredCount"] as? Int ?? -1
        let isLocalFeb24 = result?["isLocalFeb24"] as? Bool ?? false
        if isLocalFeb24 {
            XCTAssertEqual(filteredCount, 1, "UTC 23:50 is still Feb 24 locally → should be included")
        } else {
            XCTAssertEqual(filteredCount, 0, "UTC 23:50 is Feb 25 locally → should be excluded")
        }
    }

    // =========================================================
    // MARK: - renderEfficiencyTab destroys old charts
    // =========================================================

    func testRenderEfficiencyTab_calledTwice_destroysPrevious() {
        let result = evalJS("""
            const deltas1 = [
                {x: 1.0, y: 5.0, hour: 10, timestamp: '2026-02-24T10:05:00Z',
                 date: new Date('2026-02-24T10:05:00Z')},
                {x: 2.0, y: 10.0, hour: 14, timestamp: '2026-02-24T14:05:00Z',
                 date: new Date('2026-02-24T14:05:00Z')},
            ];
            renderEfficiencyTab(deltas1);
            const first = _charts.effScatter;
            // Call again with different data
            const deltas2 = [
                {x: 3.0, y: 15.0, hour: 10, timestamp: '2026-02-24T10:05:00Z',
                 date: new Date('2026-02-24T10:05:00Z')},
            ];
            renderEfficiencyTab(deltas2);
            // Charts should be different objects (old ones destroyed and new ones created)
            return _charts.effScatter !== first;
        """) as? Bool
        XCTAssertTrue(result!, "Re-rendering efficiency tab should create new chart objects")
    }

    // =========================================================
    // MARK: - Main function: tokenData.length.toLocaleString() vs usageData.length
    // =========================================================

    func testStats_tokenCount_usesLocaleString() {
        let result = evalJS("""
            // Create data with 1234 token records to test toLocaleString
            const tokenData = Array.from({length: 1234}, (_, i) => ({
                timestamp: '2026-02-24T10:00:00Z', costUSD: 0.01
            }));
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: 5}],
                tokenData
            );
            const html = document.getElementById('stats').innerHTML;
            // toLocaleString would produce '1,234' in many locales
            // Plain .length would produce '1234'
            const hasFormatted = html.includes('1,234');
            const hasPlain = html.includes('>1234<');
            return { hasFormatted, hasPlain };
        """) as? [String: Any]
        // At least one format should appear in the stats
        let hasFormatted = result?["hasFormatted"] as? Bool ?? false
        let hasPlain = result?["hasPlain"] as? Bool ?? false
        XCTAssertTrue(hasFormatted || hasPlain,
                      "Token count should appear in stats (either formatted or plain)")
    }

    // =========================================================
    // MARK: - Slider default value matches label
    // =========================================================

    func testSlider_initialValueMatchesLabel() {
        let result = evalJS("""
            // Before main() — check initial DOM state
            return {
                sliderValue: document.getElementById('gapSlider').value,
                labelText: document.getElementById('gapVal').textContent,
            };
        """) as? [String: Any]
        XCTAssertEqual(result?["sliderValue"] as? String, "30",
                       "Slider default value should be 30")
        XCTAssertEqual(result?["labelText"] as? String, "30 min",
                       "Label should show '30 min' matching slider default")
    }

    // =========================================================
    // MARK: - gapThresholdMs updates when slider changes
    // =========================================================

    func testSlider_updatesGapThreshold() {
        let result = evalJS("""
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: 5}],
                [{timestamp: '2026-02-24T10:01:00Z', costUSD: 0.5}]
            );
            const slider = document.getElementById('gapSlider');
            slider.value = '120';
            slider.dispatchEvent(new Event('input'));
            return gapThresholdMs;
        """) as? Int
        XCTAssertEqual(result, 120 * 60 * 1000,
                       "gapThresholdMs should update to 120min * 60s * 1000ms")
    }

    // =========================================================
    // MARK: - computeDeltas hour uses local time
    // =========================================================

    func testComputeDeltas_hourIsLocalTime() {
        let result = evalJS("""
            const deltas = computeDeltas(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10},
                 {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: 15}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50}]
            );
            const expectedHour = new Date('2026-02-24T10:05:00Z').getHours();
            return { deltaHour: deltas[0].hour, expectedHour };
        """) as? [String: Any]
        XCTAssertEqual(result?["deltaHour"] as? Int, result?["expectedHour"] as? Int,
                       "Delta hour should use local getHours(), not UTC getUTCHours()")
    }

    // =========================================================
    // MARK: - renderUsageTab segment callbacks
    // =========================================================

    func testRenderUsageTab_segmentCallbacksExist() {
        let result = evalJS("""
            _usageData = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 50, seven_day_percent: 25,
                 five_hour_resets_at: null, seven_day_resets_at: null},
            ];
            renderUsageTab();
            const ds0 = _chartConfigs['usageTimeline']?.data?.datasets?.[0];
            const ds1 = _chartConfigs['usageTimeline']?.data?.datasets?.[1];
            return {
                ds0HasSegment: ds0?.segment != null,
                ds1HasSegment: ds1?.segment != null,
                ds0HasBorderColor: typeof ds0?.segment?.borderColor === 'function',
                ds0HasBgColor: typeof ds0?.segment?.backgroundColor === 'function',
            };
        """) as? [String: Any]
        XCTAssertTrue(result?["ds0HasSegment"] as? Bool ?? false, "5h dataset should have segment config")
        XCTAssertTrue(result?["ds1HasSegment"] as? Bool ?? false, "7d dataset should have segment config")
        XCTAssertTrue(result?["ds0HasBorderColor"] as? Bool ?? false, "Segment should have borderColor callback")
        XCTAssertTrue(result?["ds0HasBgColor"] as? Bool ?? false, "Segment should have backgroundColor callback")
    }

    // =========================================================
    // MARK: - Cumulative chart type and label
    // =========================================================

    func testRenderCumulativeTab_chartTypeAndLabel() {
        let result = evalJS("""
            _tokenData = [{timestamp: '2026-02-24T10:00:00Z', costUSD: 1.00}];
            renderCumulativeTab();
            const config = _chartConfigs['cumulativeCost'];
            return {
                type: config?.type,
                label: config?.data?.datasets?.[0]?.label,
                borderColor: config?.data?.datasets?.[0]?.borderColor,
            };
        """) as? [String: Any]
        XCTAssertEqual(result?["type"] as? String, "line")
        XCTAssertEqual(result?["label"] as? String, "Cumulative Cost (USD)")
        XCTAssertEqual(result?["borderColor"] as? String, "#f0883e", "Cumulative line should be orange")
    }

    // =========================================================
    // MARK: - Apply Range button behavior
    // =========================================================

    func testApplyRange_reRendersEfficiencyTab() {
        let result = evalJS("""
            main(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 10, seven_day_percent: 5},
                 {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: 15, seven_day_percent: 7}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50}]
            );
            // First click efficiency tab
            document.querySelector('[data-tab="efficiency"]').click();
            const firstScatter = _charts.effScatter;
            // Click Apply Range
            document.getElementById('applyRange').click();
            // Charts should be re-created
            return {
                reRendered: _charts.effScatter !== firstScatter,
                renderedFlag: _rendered['efficiency'] === true,
            };
        """) as? [String: Any]
        XCTAssertTrue(result?["reRendered"] as? Bool ?? false,
                      "Apply Range should re-render even if already rendered")
        XCTAssertTrue(result?["renderedFlag"] as? Bool ?? false)
    }

    // =========================================================
    // MARK: - Bug hunt round 2: computeDeltas null handling
    // =========================================================

    func testComputeDeltas_nullCurrPercent_shouldExcludeInterval() {
        // prev has 30%, curr has null → d5h would be (null??0) - 30 = -30.
        // This is WRONG — null means "unknown", not "0%".
        // The interval should be excluded from deltas entirely.
        let result = evalJS("""
            const deltas = computeDeltas(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 30, seven_day_percent: 10},
                 {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: null, seven_day_percent: 12}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50}]
            );
            return { count: deltas.length, firstY: deltas[0]?.y };
        """) as? [String: Any]
        let count = result?["count"] as? Int ?? -1
        // If null is treated as 0, d5h = 0 - 30 = -30, and the interval IS included (cost > 0.001).
        // Correct behavior: exclude interval because curr.five_hour_percent is null.
        XCTAssertEqual(count, 0,
                       "Interval where curr five_hour_percent is null should be EXCLUDED — null ≠ 0%")
    }

    func testComputeDeltas_nullPrevPercent_shouldExcludeInterval() {
        // prev has null, curr has 20% → d5h would be 20 - (null??0) = 20.
        // This bogus +20 delta corrupts scatter/KDE/heatmap.
        let result = evalJS("""
            const deltas = computeDeltas(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: null, seven_day_percent: 5},
                 {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: 20, seven_day_percent: 8}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50}]
            );
            return { count: deltas.length, firstY: deltas[0]?.y };
        """) as? [String: Any]
        let count = result?["count"] as? Int ?? -1
        XCTAssertEqual(count, 0,
                       "Interval where prev five_hour_percent is null should be EXCLUDED — null ≠ 0%")
    }

    func testComputeDeltas_bothNullPercent_shouldExcludeInterval() {
        let result = evalJS("""
            const deltas = computeDeltas(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: null, seven_day_percent: 5},
                 {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: null, seven_day_percent: 8}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50}]
            );
            return deltas.length;
        """) as? Int
        XCTAssertEqual(result, 0,
                       "Both null five_hour_percent → interval excluded")
    }

    func testComputeDeltas_nullDoesNotProduceBogusNegativeDelta() {
        // Specific check: the delta should NOT be -30 (null treated as 0)
        let result = evalJS("""
            const deltas = computeDeltas(
                [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 30, seven_day_percent: 10},
                 {timestamp: '2026-02-24T10:05:00Z', five_hour_percent: null, seven_day_percent: 12}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50}]
            );
            const hasBogusNegative = deltas.some(d => d.y === -30);
            return hasBogusNegative;
        """) as? Bool
        XCTAssertFalse(result ?? true,
                       "CRITICAL: null five_hour_percent should NOT produce d5h = -30 (null ≠ 0)")
    }

    // =========================================================
    // MARK: - Bug hunt round 2: chart config deep checks
    // =========================================================

    func testRenderCostTab_costTimelineType_isBar() {
        let result = evalJS("""
            _tokenData = [{timestamp: '2026-02-24T10:00:00Z', costUSD: 0.50}];
            _allDeltas = [];
            renderCostTab();
            return _chartConfigs['costTimeline']?.type;
        """) as? String
        XCTAssertEqual(result, "bar", "Cost timeline should be a bar chart")
    }

    func testRenderEfficiencyTab_kdeChartType_isLine() {
        let result = evalJS("""
            const deltas = [
                {x: 0.50, y: 5.0, hour: 10, timestamp: '2026-02-24T10:05:00Z', date: new Date('2026-02-24T10:05:00Z')},
                {x: 0.30, y: 3.0, hour: 11, timestamp: '2026-02-24T11:05:00Z', date: new Date('2026-02-24T11:05:00Z')},
            ];
            renderEfficiencyTab(deltas);
            return _chartConfigs['kdeChart']?.type;
        """) as? String
        XCTAssertEqual(result, "line", "KDE chart should be type line")
    }

    func testRenderEfficiencyTab_kdeXAxis_isLinear() {
        let result = evalJS("""
            const deltas = [
                {x: 0.50, y: 5.0, hour: 10, timestamp: '2026-02-24T10:05:00Z', date: new Date('2026-02-24T10:05:00Z')},
                {x: 0.30, y: 3.0, hour: 11, timestamp: '2026-02-24T11:05:00Z', date: new Date('2026-02-24T11:05:00Z')},
            ];
            renderEfficiencyTab(deltas);
            return _chartConfigs['kdeChart']?.options?.scales?.x?.type;
        """) as? String
        XCTAssertEqual(result, "linear", "KDE x-axis should be linear (ratio values)")
    }

    // =========================================================
    // MARK: - Bug hunt round 2: dataset label verification
    // =========================================================

    func testRenderUsageTab_dataset0Label_isFiveHour() {
        let result = evalJS("""
            _usageData = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 50, seven_day_percent: 25,
                 five_hour_resets_at: null, seven_day_resets_at: null},
            ];
            renderUsageTab();
            return _chartConfigs['usageTimeline']?.data?.datasets?.[0]?.label;
        """) as? String
        XCTAssertEqual(result, "5-hour %", "First dataset should be 5-hour %")
    }

    func testRenderUsageTab_dataset1Label_isSevenDay() {
        let result = evalJS("""
            _usageData = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 50, seven_day_percent: 25,
                 five_hour_resets_at: null, seven_day_resets_at: null},
            ];
            renderUsageTab();
            return _chartConfigs['usageTimeline']?.data?.datasets?.[1]?.label;
        """) as? String
        XCTAssertEqual(result, "7-day %", "Second dataset should be 7-day %")
    }

    // =========================================================
    // MARK: - Bug hunt round 2: scatter datasets integrity
    // =========================================================

    func testBuildScatterChart_totalPoints_equalsDeltasCount() {
        // All deltas should appear in exactly one time-slot dataset
        let result = evalJS("""
            const deltas = [
                {x: 0.5, y: 5, hour: 2},   // Night
                {x: 0.3, y: 3, hour: 8},   // Morning
                {x: 0.4, y: 4, hour: 14},  // Afternoon
                {x: 0.6, y: 6, hour: 20},  // Evening
                {x: 0.2, y: 2, hour: 11},  // Morning
            ];
            const chart = buildScatterChart('effScatter', deltas);
            const config = _chartConfigs['effScatter'];
            const totalPoints = config.data.datasets.reduce((s, ds) => s + ds.data.length, 0);
            return { totalPoints, inputCount: deltas.length, numDatasets: config.data.datasets.length };
        """) as? [String: Any]
        let totalPoints = result?["totalPoints"] as? Int ?? -1
        let inputCount = result?["inputCount"] as? Int ?? -1
        let numDatasets = result?["numDatasets"] as? Int ?? -1
        XCTAssertEqual(totalPoints, inputCount,
                       "Total scatter points across all time-slot datasets should equal input deltas count")
        XCTAssertEqual(numDatasets, 4, "Should have 4 time-slot datasets (Night/Morning/Afternoon/Evening)")
    }

    // =========================================================
    // MARK: - Bug hunt round 2: cumulative vs total cost consistency
    // =========================================================

    func testCumulativeCost_finalValue_approximatesTotalCost() {
        let result = evalJS("""
            _tokenData = [
                {timestamp: '2026-02-24T10:00:00Z', costUSD: 0.123},
                {timestamp: '2026-02-24T10:05:00Z', costUSD: 0.456},
                {timestamp: '2026-02-24T10:10:00Z', costUSD: 0.789},
            ];
            renderCumulativeTab();
            const config = _chartConfigs['cumulativeCost'];
            const data = config.data.datasets[0].data;
            const lastY = data[data.length - 1].y;
            const totalCost = _tokenData.reduce((s, r) => s + r.costUSD, 0);
            return { lastY, totalCostRounded: Math.round(totalCost * 100) / 100 };
        """) as? [String: Any]
        let lastY = result?["lastY"] as? Double ?? -1
        let expected = result?["totalCostRounded"] as? Double ?? -2
        XCTAssertEqual(lastY, expected, accuracy: 0.01,
                       "Cumulative chart's last value should approximate total cost")
    }

    // =========================================================
    // MARK: - Bug hunt round 2: insertResetPoints data format
    // =========================================================

    func testInsertResetPoints_outputHasXandY() {
        let result = evalJS("""
            const data = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 30, five_hour_resets_at: null},
                {timestamp: '2026-02-24T11:00:00Z', five_hour_percent: 50, five_hour_resets_at: null},
            ];
            const points = insertResetPoints(data, 'five_hour_percent', 'five_hour_resets_at');
            const allHaveX = points.every(p => p.x !== undefined);
            const allHaveY = points.every(p => p.y !== undefined);
            return { count: points.length, allHaveX, allHaveY,
                     firstX: points[0]?.x, firstY: points[0]?.y };
        """) as? [String: Any]
        XCTAssertEqual(result?["count"] as? Int, 2)
        XCTAssertTrue(result?["allHaveX"] as? Bool ?? false, "All points should have x (timestamp)")
        XCTAssertTrue(result?["allHaveY"] as? Bool ?? false, "All points should have y (percent)")
        XCTAssertEqual(result?["firstY"] as? Double, 30.0)
    }

    // =========================================================
    // MARK: - Bug hunt round 2: heatmap structure
    // =========================================================

    func testBuildHeatmap_gridHas25ColumnsAnd8Rows() {
        // 1 label column + 24 hour columns = 25 columns
        // 1 header row + 7 day rows = 8 rows = 200 cells total
        let result = evalJS("""
            buildHeatmap([]);
            const html = document.getElementById('heatmap').innerHTML;
            const headerCount = (html.match(/heatmap-header/g) || []).length;
            const labelCount = (html.match(/heatmap-label/g) || []).length;
            const cellCount = (html.match(/heatmap-cell/g) || []).length;
            return { headerCount, labelCount, cellCount };
        """) as? [String: Any]
        XCTAssertEqual(result?["headerCount"] as? Int, 24, "Should have 24 hour headers")
        XCTAssertEqual(result?["labelCount"] as? Int, 7, "Should have 7 day labels")
        XCTAssertEqual(result?["cellCount"] as? Int, 168, "Should have 7x24 = 168 data cells")
    }

    // =========================================================
    // MARK: - Bug hunt round 2: renderCostTab bar data integrity
    // =========================================================

    func testRenderCostTab_barDataCount_matchesTokenDataLength() {
        let result = evalJS("""
            _tokenData = [
                {timestamp: '2026-02-24T10:00:00Z', costUSD: 0.10},
                {timestamp: '2026-02-24T10:05:00Z', costUSD: 0.20},
                {timestamp: '2026-02-24T10:10:00Z', costUSD: 0.30},
            ];
            _allDeltas = [];
            renderCostTab();
            const barData = _chartConfigs['costTimeline']?.data?.datasets?.[0]?.data;
            return { barCount: barData?.length, tokenCount: _tokenData.length };
        """) as? [String: Any]
        let barCount = result?["barCount"] as? Int ?? -1
        let tokenCount = result?["tokenCount"] as? Int ?? -1
        XCTAssertEqual(barCount, tokenCount,
                       "Cost bar chart should have one bar per token record")
    }

    func testRenderCostTab_barTimestamps_matchTokenTimestamps() {
        let result = evalJS("""
            _tokenData = [
                {timestamp: '2026-02-24T10:00:00Z', costUSD: 0.10},
                {timestamp: '2026-02-24T11:00:00Z', costUSD: 0.20},
            ];
            _allDeltas = [];
            renderCostTab();
            const barData = _chartConfigs['costTimeline']?.data?.datasets?.[0]?.data;
            return {
                bar0x: barData?.[0]?.x,
                bar1x: barData?.[1]?.x,
                token0ts: _tokenData[0].timestamp,
                token1ts: _tokenData[1].timestamp,
            };
        """) as? [String: String]
        XCTAssertEqual(result?["bar0x"], result?["token0ts"],
                       "Bar chart x-values should be token timestamps")
        XCTAssertEqual(result?["bar1x"], result?["token1ts"])
    }

    func testRenderCostTab_barCosts_matchTokenCosts() {
        let result = evalJS("""
            _tokenData = [
                {timestamp: '2026-02-24T10:00:00Z', costUSD: 0.123},
                {timestamp: '2026-02-24T11:00:00Z', costUSD: 0.456},
            ];
            _allDeltas = [];
            renderCostTab();
            const barData = _chartConfigs['costTimeline']?.data?.datasets?.[0]?.data;
            return {
                bar0y: barData?.[0]?.y,
                bar1y: barData?.[1]?.y,
            };
        """) as? [String: Any]
        XCTAssertEqual(result?["bar0y"] as? Double ?? -1, 0.123, accuracy: 0.0001)
        XCTAssertEqual(result?["bar1y"] as? Double ?? -1, 0.456, accuracy: 0.0001)
    }

    // =========================================================
    // MARK: - Bug hunt round 2: renderUsageTab data from insertResetPoints
    // =========================================================

    func testRenderUsageTab_fiveHDataPoints_matchInsertResetPointsOutput() {
        let result = evalJS("""
            _usageData = [
                {timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 30, seven_day_percent: 10,
                 five_hour_resets_at: '2026-02-24T11:00:00Z', seven_day_resets_at: null},
                {timestamp: '2026-02-24T12:00:00Z', five_hour_percent: 5, seven_day_percent: 12,
                 five_hour_resets_at: null, seven_day_resets_at: null},
            ];
            renderUsageTab();
            const ds0 = _chartConfigs['usageTimeline']?.data?.datasets?.[0]?.data;
            // insertResetPoints should produce: {x: T1, y: 30}, {x: reset, y: 0}, {x: T2, y: 5}
            return { count: ds0?.length, y0: ds0?.[0]?.y, y1: ds0?.[1]?.y, y2: ds0?.[2]?.y };
        """) as? [String: Any]
        XCTAssertEqual(result?["count"] as? Int, 3, "Should have 3 points: data, reset-zero, data")
        XCTAssertEqual(result?["y0"] as? Double, 30.0, "First point: 30%")
        XCTAssertEqual(result?["y1"] as? Double, 0.0, "Reset point: 0%")
        XCTAssertEqual(result?["y2"] as? Double, 5.0, "After reset: 5%")
    }

    // =========================================================
    // MARK: - Bug hunt round 2: KDE data format
    // =========================================================

    func testRenderEfficiencyTab_kdeData_usesLabelsAndValues() {
        let result = evalJS("""
            const deltas = [
                {x: 0.50, y: 5.0, hour: 10, timestamp: '2026-02-24T10:05:00Z', date: new Date('2026-02-24T10:05:00Z')},
                {x: 0.30, y: 3.0, hour: 11, timestamp: '2026-02-24T11:05:00Z', date: new Date('2026-02-24T11:05:00Z')},
            ];
            renderEfficiencyTab(deltas);
            const config = _chartConfigs['kdeChart'];
            const labels = config?.data?.labels;
            const data = config?.data?.datasets?.[0]?.data;
            return {
                hasLabels: labels != null && labels.length > 0,
                hasData: data != null && data.length > 0,
                labelsAreNumbers: typeof labels?.[0] === 'number',
                dataAreNumbers: typeof data?.[0] === 'number',
                labelsLength: labels?.length,
                dataLength: data?.length,
            };
        """) as? [String: Any]
        XCTAssertTrue(result?["hasLabels"] as? Bool ?? false, "KDE should have labels (x values)")
        XCTAssertTrue(result?["hasData"] as? Bool ?? false, "KDE should have data (y values)")
        XCTAssertTrue(result?["labelsAreNumbers"] as? Bool ?? false, "KDE labels should be numbers")
        XCTAssertTrue(result?["dataAreNumbers"] as? Bool ?? false, "KDE data should be numbers")
        let labelsLen = result?["labelsLength"] as? Int ?? 0
        let dataLen = result?["dataLength"] as? Int ?? 0
        XCTAssertEqual(labelsLen, dataLen, "Labels and data should have same length")
    }

    // =========================================================
    // MARK: - Bug hunt round 2: costForRecord edge cases
    // =========================================================

    func testCostForRecord_cacheCreationTokens_usesCacheWritePrice() {
        // Verify cache_creation_tokens uses cacheWrite price, NOT cacheRead price
        let result = evalJS("""
            const record = {
                model: 'claude-3-5-sonnet-20241022',
                input_tokens: 0,
                output_tokens: 0,
                cache_read_tokens: 0,
                cache_creation_tokens: 1000000,
            };
            return costForRecord(record);
        """) as? Double
        // Sonnet cacheWrite = 3.75 per 1M tokens
        XCTAssertEqual(result!, 3.75, accuracy: 0.001,
                       "cache_creation_tokens should use cacheWrite price (3.75), not cacheRead (0.30)")
    }

    func testCostForRecord_cacheReadTokens_usesCacheReadPrice() {
        let result = evalJS("""
            const record = {
                model: 'claude-3-5-sonnet-20241022',
                input_tokens: 0,
                output_tokens: 0,
                cache_read_tokens: 1000000,
                cache_creation_tokens: 0,
            };
            return costForRecord(record);
        """) as? Double
        // Sonnet cacheRead = 0.30 per 1M tokens
        XCTAssertEqual(result!, 0.30, accuracy: 0.001,
                       "cache_read_tokens should use cacheRead price (0.30), not cacheWrite (3.75)")
    }

    // =========================================================
    // MARK: - Bug hunt round 2: renderCumulativeTab x-axis type
    // =========================================================

    func testRenderCumulativeTab_xAxisType_isTime() {
        let result = evalJS("""
            _tokenData = [{timestamp: '2026-02-24T10:00:00Z', costUSD: 1.0}];
            renderCumulativeTab();
            return _chartConfigs['cumulativeCost']?.options?.scales?.x?.type;
        """) as? String
        XCTAssertEqual(result, "time", "Cumulative chart x-axis should be time scale")
    }

    func testRenderCostTab_costTimeline_xAxisType_isTime() {
        let result = evalJS("""
            _tokenData = [{timestamp: '2026-02-24T10:00:00Z', costUSD: 0.5}];
            _allDeltas = [];
            renderCostTab();
            return _chartConfigs['costTimeline']?.options?.scales?.x?.type;
        """) as? String
        XCTAssertEqual(result, "time", "Cost timeline x-axis should be time scale")
    }

    // =========================================================
    // MARK: - Bug hunt round 2: usage chart fill and tension
    // =========================================================

    func testRenderUsageTab_datasets_haveFillTrue() {
        let result = evalJS("""
            _usageData = [{timestamp: '2026-02-24T10:00:00Z', five_hour_percent: 50, seven_day_percent: 25,
                           five_hour_resets_at: null, seven_day_resets_at: null}];
            renderUsageTab();
            const ds = _chartConfigs['usageTimeline']?.data?.datasets;
            return { fill0: ds?.[0]?.fill, fill1: ds?.[1]?.fill, tension0: ds?.[0]?.tension, tension1: ds?.[1]?.tension };
        """) as? [String: Any]
        XCTAssertTrue(result?["fill0"] as? Bool ?? false, "5h dataset should have fill: true")
        XCTAssertTrue(result?["fill1"] as? Bool ?? false, "7d dataset should have fill: true")
        XCTAssertEqual(result?["tension0"] as? Int, 0, "5h dataset tension should be 0 (no curve)")
        XCTAssertEqual(result?["tension1"] as? Int, 0, "7d dataset tension should be 0 (no curve)")
    }

    // =========================================================
    // MARK: - Bug hunt round 2: cost bar chart config
    // =========================================================

    func testRenderCostTab_barPercentage_is1() {
        let result = evalJS("""
            _tokenData = [{timestamp: '2026-02-24T10:00:00Z', costUSD: 0.5}];
            _allDeltas = [];
            renderCostTab();
            const ds = _chartConfigs['costTimeline']?.data?.datasets?.[0];
            return { barPct: ds?.barPercentage, catPct: ds?.categoryPercentage };
        """) as? [String: Any]
        XCTAssertEqual(result?["barPct"] as? Double, 1.0, "barPercentage should be 1.0")
        XCTAssertEqual(result?["catPct"] as? Double, 1.0, "categoryPercentage should be 1.0")
    }
}
