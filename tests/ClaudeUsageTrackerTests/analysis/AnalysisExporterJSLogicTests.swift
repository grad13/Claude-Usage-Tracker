// meta: updated=2026-08-11 checked=-
// Tests for: JS function logic in analysis.html (loaded via AnalysisExporter.htmlTemplate)
// Source spec: spec/analysis/analysis-exporter.md
// Generated: 2026-03-06
//
// Covers:
//   - BW-01~BW-05: buildWeeklySessions — session splitting and reset point insertion
//   - BH-01~BH-04: buildHourlySessions — hourly session splitting
//   - HT-01~HT-04: buildHourlyTimelineData — time-gap-only fill continuity
//   - MN-01~MN-03: renderMain — summary display and one Hourly filled dataset
//
// Reset/session metadata logic remains in buildWeeklySessions/buildHourlySessions;
// Hourly visual continuity is independently modeled by buildHourlyTimelineData.

import XCTest
import WebKit
@testable import ClaudeUsageTracker

// MARK: - Helper

private func parseSessions(_ result: Any?) -> [[[String: Any]]]? {
    guard let jsonStr = result as? String,
          let arr = try? JSONSerialization.jsonObject(
              with: Data(jsonStr.utf8)) as? [[[String: Any]]] else {
        return nil
    }
    return arr
}

// MARK: - buildWeeklySessions (BW-01~BW-05)

final class AnalysisBuildWeeklySessionsTests: AnalysisJSTestCase {

    // BW-01: Single session — all records have same weekly_resets_at
    func testBW01_singleSession_groupedTogether() {
        let result = evalJS("""
            const data = [
                {timestamp: 1000, hourly_percent: null, weekly_percent: 30, hourly_resets_at: null, weekly_resets_at: 2000},
                {timestamp: 1100, hourly_percent: null, weekly_percent: 40, hourly_resets_at: null, weekly_resets_at: 2000},
                {timestamp: 1200, hourly_percent: null, weekly_percent: 50, hourly_resets_at: null, weekly_resets_at: 2000}
            ];
            const sessions = buildWeeklySessions(data);
            return JSON.stringify(sessions.map(s => s.data.map(p => ({x: p.x, y: p.y}))));
            """)
        guard let sessions = parseSessions(result) else {
            XCTFail("Failed to parse result"); return
        }
        XCTAssertEqual(sessions.count, 1, "All records share weekly_resets_at=2000 → 1 session")
        // 3 data points + 1 zero point at resets_at
        XCTAssertEqual(sessions[0].count, 4)
        // Last point should be zero at resets_at * 1000
        XCTAssertEqual(sessions[0].last?["x"] as? Double, 2000 * 1000)
        XCTAssertEqual(sessions[0].last?["y"] as? Double, 0.0)
    }

    // BW-02: Two sessions — different weekly_resets_at splits into 2 sessions
    func testBW02_twoSessions_splitByResetsAt() {
        let result = evalJS("""
            const data = [
                {timestamp: 1000, hourly_percent: null, weekly_percent: 30, hourly_resets_at: null, weekly_resets_at: 2000},
                {timestamp: 1100, hourly_percent: null, weekly_percent: 40, hourly_resets_at: null, weekly_resets_at: 2000},
                {timestamp: 3000, hourly_percent: null, weekly_percent: 10, hourly_resets_at: null, weekly_resets_at: 4000},
                {timestamp: 3100, hourly_percent: null, weekly_percent: 20, hourly_resets_at: null, weekly_resets_at: 4000}
            ];
            const sessions = buildWeeklySessions(data);
            return sessions.length;
            """)
        XCTAssertEqual(result as? Int, 2, "Different weekly_resets_at → 2 sessions")
    }

    // BW-03: weekly_percent null → row skipped
    func testBW03_weeklyPercentNull_rowSkipped() {
        let result = evalJS("""
            const data = [
                {timestamp: 1000, hourly_percent: 50, weekly_percent: null, hourly_resets_at: null, weekly_resets_at: 2000},
                {timestamp: 1100, hourly_percent: null, weekly_percent: 40, hourly_resets_at: null, weekly_resets_at: 2000}
            ];
            const sessions = buildWeeklySessions(data);
            return sessions[0].data.length;
            """)
        // null weekly_percent row skipped; 1 data + 1 zero = 2
        XCTAssertEqual(result as? Int, 2)
    }

    // BW-04: weekly_resets_at null → row skipped
    func testBW04_resetsAtNull_rowSkipped() {
        let result = evalJS("""
            const data = [
                {timestamp: 1000, hourly_percent: null, weekly_percent: 30, hourly_resets_at: null, weekly_resets_at: null},
                {timestamp: 1100, hourly_percent: null, weekly_percent: 40, hourly_resets_at: null, weekly_resets_at: 2000}
            ];
            const sessions = buildWeeklySessions(data);
            const totalPoints = sessions.reduce((sum, s) => sum + s.data.length, 0);
            return totalPoints;
            """)
        // First row has null weekly_resets_at → skipped. Only second row + zero point = 2
        XCTAssertEqual(result as? Int, 2)
    }

    // BW-05: Empty data → empty sessions
    func testBW05_emptyData_emptySessions() {
        let result = evalJS("""
            return buildWeeklySessions([]).length;
            """)
        XCTAssertEqual(result as? Int, 0)
    }
}

// MARK: - buildHourlySessions (BH-01~BH-04)

final class AnalysisBuildHourlySessionsTests: AnalysisJSTestCase {

    // BH-01: Single hourly session — zero point appended at resets_at
    func testBH01_singleSession_zeroPointAppended() {
        let result = evalJS("""
            const data = [
                {timestamp: 1000, hourly_percent: 30, weekly_percent: null, hourly_resets_at: 2000, weekly_resets_at: null},
                {timestamp: 1100, hourly_percent: 40, weekly_percent: null, hourly_resets_at: 2000, weekly_resets_at: null}
            ];
            const sessions = buildHourlySessions(data);
            return JSON.stringify({
                count: sessions.length,
                points: sessions[0].data.length,
                lastY: sessions[0].data[sessions[0].data.length - 1].y
            });
            """)
        guard let jsonStr = result as? String,
              let dict = try? JSONSerialization.jsonObject(with: Data(jsonStr.utf8)) as? [String: Any] else {
            XCTFail("Failed to parse result"); return
        }
        XCTAssertEqual(dict["count"] as? Int, 1)
        XCTAssertEqual(dict["points"] as? Int, 3, "2 data + 1 zero point at resets_at")
        XCTAssertEqual(dict["lastY"] as? Double, 0.0, "Last point should be zero at resets_at")
    }

    // BH-02: hourly_percent null → row skipped
    func testBH02_hourlyPercentNull_rowSkipped() {
        let result = evalJS("""
            const data = [
                {timestamp: 1000, hourly_percent: null, weekly_percent: 50, hourly_resets_at: 2000, weekly_resets_at: null},
                {timestamp: 1100, hourly_percent: 40, weekly_percent: null, hourly_resets_at: 2000, weekly_resets_at: null}
            ];
            const sessions = buildHourlySessions(data);
            const totalPoints = sessions.reduce((sum, s) => sum + s.data.length, 0);
            return totalPoints;
            """)
        XCTAssertEqual(result as? Int, 2, "null hourly_percent skipped; 1 data + 1 zero = 2")
    }

    // BH-03: hourly_resets_at null → row skipped (idle period between sessions)
    func testBH03_resetsAtNull_rowSkipped() {
        let result = evalJS("""
            const data = [
                {timestamp: 1000, hourly_percent: 30, weekly_percent: null, hourly_resets_at: null, weekly_resets_at: null}
            ];
            return buildHourlySessions(data).length;
            """)
        XCTAssertEqual(result as? Int, 0, "null hourly_resets_at → row skipped, no sessions")
    }

    // BH-04: Two sessions split by different hourly_resets_at
    func testBH04_twoSessions_splitByResetsAt() {
        let result = evalJS("""
            const data = [
                {timestamp: 1000, hourly_percent: 30, weekly_percent: null, hourly_resets_at: 2000, weekly_resets_at: null},
                {timestamp: 3000, hourly_percent: 10, weekly_percent: null, hourly_resets_at: 4000, weekly_resets_at: null}
            ];
            return buildHourlySessions(data).length;
            """)
        XCTAssertEqual(result as? Int, 2, "Different hourly_resets_at → 2 sessions")
    }
}

// MARK: - buildHourlyTimelineData (HT-01~HT-04)

final class AnalysisBuildHourlyTimelineTests: AnalysisJSTestCase {

    // HT-01: Alternating exact reset identities are metadata, not visual gaps.
    func testHT01_alternatingResetValuesEveryMinute_staysOneContinuousFill() {
        let result = evalJS("""
            const data = [];
            for (let i = 0; i < 24; i++) {
                data.push({
                    timestamp: 1000 + i * 60,
                    hourly_percent: 10 + i,
                    hourly_resets_at: i % 2 === 0 ? 9000 : 9001
                });
            }
            const timeline = buildHourlyTimelineData(data);
            renderMain(data);
            const datasets = _chartConfigs['usageTimeline'].data.datasets;
            const hourly = datasets.filter(ds => ds.borderColor === _hourlyColor);
            return JSON.stringify({
                inputPoints: data.length,
                timelinePoints: timeline.length,
                separators: timeline.filter(point => point.y === null).length,
                segments: timeline.length === 0 ? 0 : timeline.filter(point => point.y === null).length + 1,
                hourlyDatasetCount: hourly.length,
                containsLiteralNull: timeline.some(point => point === null),
                spanGaps: hourly[0]?.spanGaps,
                fill: hourly[0]?.fill
            });
            """)
        guard let jsonStr = result as? String,
              let dict = try? JSONSerialization.jsonObject(
                  with: Data(jsonStr.utf8)) as? [String: Any] else {
            XCTFail("Failed to parse result"); return
        }

        XCTAssertEqual(dict["inputPoints"] as? Int, 24)
        XCTAssertEqual(dict["timelinePoints"] as? Int, 24,
                       "Reset identity changes must not add skipped points")
        XCTAssertEqual(dict["separators"] as? Int, 0)
        XCTAssertEqual(dict["segments"] as? Int, 1,
                       "Minute-spaced samples must remain one time-contiguous fill")
        XCTAssertEqual(dict["hourlyDatasetCount"] as? Int, 1,
                       "Alternating resets must not create diagonal filled datasets")
        XCTAssertEqual(dict["containsLiteralNull"] as? Bool, false)
        XCTAssertEqual(dict["spanGaps"] as? Bool, false)
        XCTAssertEqual(dict["fill"] as? Bool, true)
    }

    // HT-02: Only a true elapsed-time gap receives one object-shaped separator.
    func testHT02_trueGap_createsExactlyOneParserSafeSeparator() {
        let result = evalJS("""
            const data = [
                {timestamp: 1000, hourly_percent: 30, hourly_resets_at: 8000},
                {timestamp: 1060, hourly_percent: 40, hourly_resets_at: 8001},
                {timestamp: 3000, hourly_percent: 10, hourly_resets_at: 8000},
                {timestamp: 3060, hourly_percent: 20, hourly_resets_at: 8001}
            ];
            const timeline = buildHourlyTimelineData(data);
            const separatorIndexes = timeline
                .map((point, index) => point.y === null ? index : -1)
                .filter(index => index >= 0);
            const separatorIndex = separatorIndexes[0] ?? -1;
            return JSON.stringify({
                separatorIndexes,
                segments: timeline.length === 0 ? 0 : separatorIndexes.length + 1,
                containsLiteralNull: timeline.some(point => point === null),
                allPointsHaveFiniteX: timeline.every(point =>
                    point !== null && Number.isFinite(point.x)
                ),
                beforeSeparatorX: timeline[separatorIndex - 1]?.x,
                separatorX: timeline[separatorIndex]?.x,
                separatorY: timeline[separatorIndex]?.y,
                afterSeparatorX: timeline[separatorIndex + 1]?.x
            });
            """)
        guard let jsonStr = result as? String,
              let dict = try? JSONSerialization.jsonObject(
                  with: Data(jsonStr.utf8)) as? [String: Any] else {
            XCTFail("Failed to parse result"); return
        }

        XCTAssertEqual(dict["separatorIndexes"] as? [Int], [2])
        XCTAssertEqual(dict["segments"] as? Int, 2)
        XCTAssertEqual(dict["containsLiteralNull"] as? Bool, false)
        XCTAssertEqual(dict["allPointsHaveFiniteX"] as? Bool, true)
        XCTAssertEqual(dict["beforeSeparatorX"] as? Double, 1_060_000)
        XCTAssertEqual(dict["separatorX"] as? Double, 2_030_000)
        XCTAssertTrue(dict.keys.contains("separatorY"),
                      "The parser-safe separator must serialize as y:null")
        XCTAssertEqual(dict["afterSeparatorX"] as? Double, 3_000_000)
    }

    // HT-03: The threshold comparison is strict; equality is continuous.
    func testHT03_gapExactlyAtThreshold_staysContinuous() {
        let result = evalJS("""
            const timeline = buildHourlyTimelineData([
                {timestamp: 1000, hourly_percent: 30},
                {timestamp: 2800, hourly_percent: 40}
            ]);
            return JSON.stringify({
                points: timeline.length,
                separators: timeline.filter(point => point.y === null).length
            });
            """)
        guard let jsonStr = result as? String,
              let dict = try? JSONSerialization.jsonObject(
                  with: Data(jsonStr.utf8)) as? [String: Any] else {
            XCTFail("Failed to parse result"); return
        }

        XCTAssertEqual(dict["points"] as? Int, 2)
        XCTAssertEqual(dict["separators"] as? Int, 0)
    }

    // HT-04: Invalid rows are removed and valid rows are chronological.
    func testHT04_unorderedInputWithInvalidRows_filtersAndSorts() {
        let result = evalJS("""
            const timeline = buildHourlyTimelineData([
                {timestamp: 1120, hourly_percent: 30},
                {timestamp: null, hourly_percent: 99},
                {timestamp: 1000, hourly_percent: 10},
                {timestamp: 1060, hourly_percent: null},
                {timestamp: 1060, hourly_percent: 20}
            ]);
            return JSON.stringify(timeline);
            """)
        guard let jsonStr = result as? String,
              let points = try? JSONSerialization.jsonObject(
                  with: Data(jsonStr.utf8)) as? [[String: Any]] else {
            XCTFail("Failed to parse result"); return
        }

        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points.compactMap { $0["x"] as? Double },
                       [1_000_000, 1_060_000, 1_120_000])
        XCTAssertEqual(points.compactMap { $0["y"] as? Double }, [10, 20, 30])
    }
}

// MARK: - renderMain (MN-01~MN-03)

final class AnalysisRenderMainTests: AnalysisJSTestCase {

    // MN-01: 100 records → chart created (check _chartConfigs has entry for 'usageTimeline')
    func testMN01_hundredRecords_chartCreated() {
        let result = evalJS("""
            const data = [];
            for (let i = 0; i < 100; i++) {
                data.push({
                    timestamp: 1700000000 + i * 300,
                    hourly_percent: Math.random() * 100,
                    weekly_percent: Math.random() * 100,
                    hourly_resets_at: 1700000000 + 18000,
                    weekly_resets_at: 1700000000 + 604800
                });
            }
            renderMain(data);
            return _chartConfigs.hasOwnProperty('usageTimeline');
            """)
        XCTAssertEqual(result as? Bool, true,
                       "renderMain with 100 records should create a chart config for 'usageTimeline'")
    }

    // MN-02: 0 records → chart created but with empty data
    func testMN02_zeroRecords_chartCreatedEmpty() {
        let result = evalJS("""
            renderMain([]);
            const cfg = _chartConfigs['usageTimeline'];
            if (!cfg) return JSON.stringify({hasChart: false});
            const datasets = cfg.data.datasets;
            const totalPoints = datasets.reduce((sum, ds) => sum + ds.data.length, 0);
            return JSON.stringify({hasChart: true, totalPoints: totalPoints});
            """)
        guard let jsonStr = result as? String,
              let dict = try? JSONSerialization.jsonObject(
                  with: Data(jsonStr.utf8)) as? [String: Any] else {
            XCTFail("Failed to parse result"); return
        }
        XCTAssertEqual(dict["hasChart"] as? Bool, true,
                       "renderMain with 0 records should still create a chart")
        XCTAssertEqual(dict["totalPoints"] as? Int, 0,
                       "Chart datasets should have 0 data points when given empty data")
    }

    // MN-03: A true time gap remains empty inside one parser-safe filled dataset.
    func testMN03_trueTimeGap_oneDatasetWithNoLineOrFillBridge() {
        let result = evalJS("""
            const data = [
                {timestamp: 1000, hourly_percent: 30, weekly_percent: null, hourly_resets_at: 2000, weekly_resets_at: null},
                {timestamp: 1100, hourly_percent: 40, weekly_percent: null, hourly_resets_at: 2001, weekly_resets_at: null},
                {timestamp: 3000, hourly_percent: 10, weekly_percent: null, hourly_resets_at: 4000, weekly_resets_at: null},
                {timestamp: 3100, hourly_percent: 20, weekly_percent: null, hourly_resets_at: 4001, weekly_resets_at: null}
            ];
            renderMain(data);
            const datasets = _chartConfigs['usageTimeline'].data.datasets;
            const hourly = datasets.filter(ds => ds.borderColor === _hourlyColor);
            const hourlyData = hourly[0]?.data ?? [];
            const separatorIndexes = hourlyData
                .map((point, index) => point?.y === null ? index : -1)
                .filter(index => index >= 0);
            const separatorIndex = separatorIndexes[0] ?? -1;
            const parsedHourlyData = _chartParsedData['usageTimeline'][datasets.indexOf(hourly[0])];
            return JSON.stringify({
                hourlyDatasetCount: hourly.length,
                filled: hourly[0]?.fill,
                spanGaps: hourly[0]?.spanGaps,
                stepped: hourly[0]?.stepped,
                separatorIndexes,
                containsLiteralNull: hourlyData.some(point => point === null),
                allPointsHaveFiniteX: hourlyData.every(point =>
                    point !== null && Number.isFinite(point.x)
                ),
                parsedSeparatorY: parsedHourlyData[separatorIndex].y,
                beforeSeparatorX: separatorIndex > 0 ? hourlyData[separatorIndex - 1].x : null,
                separatorX: separatorIndex >= 0 ? hourlyData[separatorIndex].x : null,
                afterSeparatorX: separatorIndex >= 0 ? hourlyData[separatorIndex + 1].x : null
            });
            """)
        guard let jsonStr = result as? String,
              let dict = try? JSONSerialization.jsonObject(
                  with: Data(jsonStr.utf8)) as? [String: Any] else {
            XCTFail("Failed to parse result"); return
        }

        XCTAssertEqual(dict["hourlyDatasetCount"] as? Int, 1,
                       "Hourly fill must use exactly one dataset, regardless of reset identity")
        XCTAssertEqual(dict["filled"] as? Bool, true)
        XCTAssertEqual(dict["spanGaps"] as? Bool, false,
                       "Chart.js must not span the parser-safe skipped point")
        XCTAssertEqual(dict["stepped"] as? String, "before")
        XCTAssertEqual(dict["separatorIndexes"] as? [Int], [2],
                       "The true time gap must create exactly one skipped point")
        XCTAssertEqual(dict["containsLiteralNull"] as? Bool, false,
                       "Literal null crashes Chart.js's object-data parser before drawing")
        XCTAssertEqual(dict["allPointsHaveFiniteX"] as? Bool, true,
                       "Every Chart.js object-data item must provide a finite x value")
        XCTAssertTrue(dict.keys.contains("parsedSeparatorY"),
                      "The Chart.js parser contract must retain the separator as y:null")
        XCTAssertEqual(dict["beforeSeparatorX"] as? Double, 1_100_000,
                       "The last chronological sample must remain before the gap")
        XCTAssertEqual(dict["separatorX"] as? Double, 2_050_000,
                       "The skipped point must sit inside the real session gap")
        XCTAssertEqual(dict["afterSeparatorX"] as? Double, 3_000_000,
                       "spanGaps:false must leave the true gap without a line/fill bridge")
    }
}
