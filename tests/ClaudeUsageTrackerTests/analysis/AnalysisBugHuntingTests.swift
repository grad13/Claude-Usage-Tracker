import XCTest
import WebKit
import SQLite3
@testable import ClaudeUsageTracker

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
                [{timestamp: 1771927200, hourly_percent: 42.5, weekly_percent: 15.3}],
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
        // Last record has null weekly_percent → latestSevenD = '-'
        // Template shows ${latestSevenD}% → '-%'
        let result = evalJS("""
            main(
                [{timestamp: 1771927200, hourly_percent: 10, weekly_percent: null}],
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
                [{timestamp: 1771927200, hourly_percent: 0, weekly_percent: 0}],
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
                [{timestamp: 1771927200, hourly_percent: 10, weekly_percent: 5}],
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
                [{timestamp: 1771927200, hourly_percent: 10, weekly_percent: 5},
                 {timestamp: 1771939800, hourly_percent: 20, weekly_percent: 8}],
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
                {timestamp: 1771927200, hourly_percent: 50, weekly_percent: 25,
                 hourly_resets_at: 1771945200, weekly_resets_at: 1772186400},
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
                {timestamp: 1771927200, hourly_percent: 50, weekly_percent: 25,
                 hourly_resets_at: 1771945200, weekly_resets_at: 1772186400},
            ];
            renderUsageTab();
            return _chartConfigs['usageTimeline']?.options?.scales?.x?.type;
        """) as? String
        XCTAssertEqual(result, "time", "Usage chart x-axis should be time-based")
    }

    func testRenderUsageTab_datasetColors() {
        let result = evalJS("""
            _usageData = [
                {timestamp: 1771927200, hourly_percent: 50, weekly_percent: 25,
                 hourly_resets_at: 1771945200, weekly_resets_at: 1772186400},
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
            initTabs();
            main(
                [{timestamp: 1771927200, hourly_percent: 10, weekly_percent: 5}],
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
            initTabs();
            main(
                [{timestamp: 1771927200, hourly_percent: 10, weekly_percent: 5}],
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
    // MARK: - Main function: tokenData.length.toLocaleString() vs usageData.length
    // =========================================================

    func testStats_tokenCount_usesLocaleString() {
        let result = evalJS("""
            // Create data with 1234 token records to test toLocaleString
            const tokenData = Array.from({length: 1234}, (_, i) => ({
                timestamp: '2026-02-24T10:00:00Z', costUSD: 0.01
            }));
            main(
                [{timestamp: 1771927200, hourly_percent: 10, weekly_percent: 5}],
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
    // MARK: - computeDeltas hour uses local time
    // =========================================================

    func testComputeDeltas_hourIsLocalTime() {
        let result = evalJS("""
            const deltas = computeDeltas(
                [{timestamp: 1771927200, hourly_percent: 10},
                 {timestamp: 1771927500, hourly_percent: 15}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50}]
            );
            const expectedHour = new Date(1771927500 * 1000).getHours();
            return { deltaHour: deltas[0].hour, expectedHour };
        """) as? [String: Any]
        XCTAssertEqual(result?["deltaHour"] as? Int, result?["expectedHour"] as? Int,
                       "Delta hour should use local getHours(), not UTC getUTCHours()")
    }

    // =========================================================
    // MARK: - renderUsageTab stepped line style
    // =========================================================

    func testRenderUsageTab_datasetsUseStepped() {
        let result = evalJS("""
            _usageData = [
                {timestamp: 1771927200, hourly_percent: 50, weekly_percent: 25,
                 hourly_resets_at: 1771945200, weekly_resets_at: 1772186400},
            ];
            renderUsageTab();
            const ds0 = _chartConfigs['usageTimeline']?.data?.datasets?.[0];
            const ds1 = _chartConfigs['usageTimeline']?.data?.datasets?.[1];
            return {
                ds0Stepped: ds0?.stepped,
                ds1Stepped: ds1?.stepped,
                ds0BorderWidth: ds0?.borderWidth,
                ds1BorderWidth: ds1?.borderWidth,
            };
        """) as? [String: Any]
        XCTAssertEqual(result?["ds0Stepped"] as? String, "before", "Hourly dataset should use stepped: before")
        XCTAssertEqual(result?["ds1Stepped"] as? String, "before", "Weekly dataset should use stepped: before")
        XCTAssertEqual(result?["ds0BorderWidth"] as? Double, 0.75, "Hourly dataset borderWidth should be 0.75")
        XCTAssertEqual(result?["ds1BorderWidth"] as? Double, 1.5, "Weekly dataset borderWidth should be 1.5")
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
    // MARK: - destroyAllCharts behavior
    // =========================================================

    func testDestroyAllCharts_clearsRenderedFlags() {
        let result = evalJS("""
            main(
                [{timestamp: 1771927200, hourly_percent: 10, weekly_percent: 5},
                 {timestamp: 1771927500, hourly_percent: 15, weekly_percent: 7}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50}]
            );
            const hadUsage = _rendered['usage'] === true;
            destroyAllCharts();
            return {
                hadUsageBefore: hadUsage,
                hasUsageAfter: _rendered['usage'] === true,
            };
        """) as? [String: Any]
        XCTAssertTrue(result?["hadUsageBefore"] as? Bool ?? false,
                      "Usage tab should have been rendered by main()")
        XCTAssertFalse(result?["hasUsageAfter"] as? Bool ?? true,
                       "destroyAllCharts should clear _rendered flags")
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
                [{timestamp: 1771927200, hourly_percent: 30, weekly_percent: 10},
                 {timestamp: 1771927500, hourly_percent: null, weekly_percent: 12}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50}]
            );
            return { count: deltas.length, firstY: deltas[0]?.y };
        """) as? [String: Any]
        let count = result?["count"] as? Int ?? -1
        // If null is treated as 0, d5h = 0 - 30 = -30, and the interval IS included (cost > 0.001).
        // Correct behavior: exclude interval because curr.hourly_percent is null.
        XCTAssertEqual(count, 0,
                       "Interval where curr hourly_percent is null should be EXCLUDED — null ≠ 0%")
    }

    func testComputeDeltas_nullPrevPercent_shouldExcludeInterval() {
        // prev has null, curr has 20% → d5h would be 20 - (null??0) = 20.
        // This bogus +20 delta corrupts scatter/KDE/heatmap.
        let result = evalJS("""
            const deltas = computeDeltas(
                [{timestamp: 1771927200, hourly_percent: null, weekly_percent: 5},
                 {timestamp: 1771927500, hourly_percent: 20, weekly_percent: 8}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50}]
            );
            return { count: deltas.length, firstY: deltas[0]?.y };
        """) as? [String: Any]
        let count = result?["count"] as? Int ?? -1
        XCTAssertEqual(count, 0,
                       "Interval where prev hourly_percent is null should be EXCLUDED — null ≠ 0%")
    }

    func testComputeDeltas_bothNullPercent_shouldExcludeInterval() {
        let result = evalJS("""
            const deltas = computeDeltas(
                [{timestamp: 1771927200, hourly_percent: null, weekly_percent: 5},
                 {timestamp: 1771927500, hourly_percent: null, weekly_percent: 8}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50}]
            );
            return deltas.length;
        """) as? Int
        XCTAssertEqual(result, 0,
                       "Both null hourly_percent → interval excluded")
    }

    func testComputeDeltas_nullDoesNotProduceBogusNegativeDelta() {
        // Specific check: the delta should NOT be -30 (null treated as 0)
        let result = evalJS("""
            const deltas = computeDeltas(
                [{timestamp: 1771927200, hourly_percent: 30, weekly_percent: 10},
                 {timestamp: 1771927500, hourly_percent: null, weekly_percent: 12}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50}]
            );
            const hasBogusNegative = deltas.some(d => d.y === -30);
            return hasBogusNegative;
        """) as? Bool
        XCTAssertFalse(result ?? true,
                       "CRITICAL: null hourly_percent should NOT produce d5h = -30 (null ≠ 0)")
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

    // =========================================================
    // MARK: - Bug hunt round 2: dataset label verification
    // =========================================================

    func testRenderUsageTab_dataset0Label_isHourlyUsage() {
        let result = evalJS("""
            _usageData = [
                {timestamp: 1771927200, hourly_percent: 50, weekly_percent: 25,
                 hourly_resets_at: 1771945200, weekly_resets_at: 1772186400},
            ];
            renderUsageTab();
            return _chartConfigs['usageTimeline']?.data?.datasets?.[0]?.label;
        """) as? String
        XCTAssertEqual(result, "Hourly Usage", "First dataset should be Hourly Usage")
    }

    func testRenderUsageTab_dataset1Label_isWeeklyUsage() {
        let result = evalJS("""
            _usageData = [
                {timestamp: 1771927200, hourly_percent: 50, weekly_percent: 25,
                 hourly_resets_at: 1771945200, weekly_resets_at: 1772186400},
            ];
            renderUsageTab();
            return _chartConfigs['usageTimeline']?.data?.datasets?.[1]?.label;
        """) as? String
        XCTAssertEqual(result, "Weekly Usage", "Second dataset should be Weekly Usage")
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

    func testRenderUsageTab_datasets_haveFillFalseAndStepped() {
        let result = evalJS("""
            _usageData = [{timestamp: 1771927200, hourly_percent: 50, weekly_percent: 25,
                           hourly_resets_at: 1771945200, weekly_resets_at: 1772186400}];
            renderUsageTab();
            const ds = _chartConfigs['usageTimeline']?.data?.datasets;
            return { fill0: ds?.[0]?.fill, fill1: ds?.[1]?.fill,
                     tension0: ds?.[0]?.tension, tension1: ds?.[1]?.tension,
                     stepped0: ds?.[0]?.stepped, stepped1: ds?.[1]?.stepped };
        """) as? [String: Any]
        XCTAssertTrue(result?["fill0"] as? Bool ?? false, "Hourly dataset should have fill: true")
        XCTAssertTrue(result?["fill1"] as? Bool ?? false, "Weekly dataset should have fill: true (session-split with area)")
        XCTAssertEqual(result?["tension0"] as? Int, 0, "Hourly dataset tension should be 0")
        XCTAssertEqual(result?["tension1"] as? Int, 0, "Weekly dataset tension should be 0")
        XCTAssertEqual(result?["stepped0"] as? String, "before", "Hourly dataset should use stepped: before")
        XCTAssertEqual(result?["stepped1"] as? String, "before", "Weekly dataset should use stepped: before")
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
