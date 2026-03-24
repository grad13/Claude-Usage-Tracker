// meta: updated=2026-03-06 14:45 checked=-
// Tests for: JS function logic in analysis.html (loaded via AnalysisExporter.htmlTemplate)
// Source spec: spec/analysis/analysis-exporter.md
// Generated: 2026-03-06
//
// Covers:
//   - BW-01~BW-05: buildWeeklySessions — session splitting and reset point insertion
//   - BH-01~BH-04: buildHourlySessions — hourly session splitting
//   - MN-01~MN-02: renderMain — summary display
//
// Note: spec defines insertResetPoints, isGapSegment, formatMin but these functions
// do not exist in the actual code. Reset logic is inline in buildWeeklySessions/
// buildHourlySessions. Gap slider feature is not implemented. Spec needs update.

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

// MARK: - renderMain (MN-01~MN-02)

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
}
