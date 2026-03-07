// Supplement tests for: JS function logic in analysis.html (loaded via AnalysisExporter.htmlTemplate)
// Source spec: spec/analysis/analysis-exporter.md
// Analysis: tests/.tests-from-spec/analysis/analysis-exporter.md
// Generated: 2026-03-07
//
// Covers gaps not tested in AnalysisExporterJSLogicTests.swift:
//   - findNearest: binary search for nearest data point (5 cases)
//   - formatDateShort: short date formatting (3 cases)
//   - formatDateFull: full date formatting with day name (3 cases)
//   - buildSessionSlots: session-based slot construction (4 cases)
//   - buildCalendarSlots: calendrical slot construction (4 cases)
//   - timeXScale: time axis configuration (3 cases)
//
// NOT covered (reason):
//   - insertResetPoints RP-01~08: function does not exist in code (inline in buildWeeklySessions/buildHourlySessions)
//   - isGapSegment GS-01~05: function does not exist in code (gap slider not implemented)
//   - formatMin FM-01~06: function does not exist in code (gap slider not implemented)
//   - switchMode, updateNavUI, navigateTo, initNavigation: require nav DOM elements not in test harness + async fetch
//   - createStripePattern: requires real canvas 2D context, returns CanvasPattern (not serializable)

import XCTest
import WebKit
@testable import ClaudeUsageTracker

// MARK: - findNearest (FN-01~FN-05)

final class AnalysisFindNearestTests: AnalysisJSTestCase {

    // FN-01: Exact match returns that point
    func testFN01_exactMatch_returnsPoint() {
        let result = evalJS("""
            const data = [
                {x: 1000000, y: 10},
                {x: 2000000, y: 20},
                {x: 3000000, y: 30}
            ];
            const found = findNearest(data, 2000000);
            return JSON.stringify(found);
            """)
        guard let jsonStr = result as? String,
              let dict = try? JSONSerialization.jsonObject(with: Data(jsonStr.utf8)) as? [String: Any] else {
            XCTFail("Failed to parse result"); return
        }
        XCTAssertEqual(dict["x"] as? Double, 2000000)
        XCTAssertEqual(dict["y"] as? Double, 20)
    }

    // FN-02: Empty array returns null
    func testFN02_emptyArray_returnsNull() {
        let result = evalJS("""
            return findNearest([], 1000000);
            """)
        XCTAssertTrue(result is NSNull, "findNearest on empty array should return null (NSNull)")
    }

    // FN-03: Target beyond 600000ms threshold returns null
    func testFN03_beyondThreshold_returnsNull() {
        let result = evalJS("""
            const data = [{x: 1000000, y: 10}];
            return findNearest(data, 1700000);
            """)
        // Distance = 700000 > 600000 threshold
        XCTAssertTrue(result is NSNull, "Distance 700000ms exceeds 600000ms threshold -> null (NSNull)")
    }

    // FN-04: Target within threshold returns nearest point
    func testFN04_withinThreshold_returnsNearest() {
        let result = evalJS("""
            const data = [{x: 1000000, y: 10}];
            const found = findNearest(data, 1500000);
            return JSON.stringify(found);
            """)
        // Distance = 500000 < 600000 threshold
        guard let jsonStr = result as? String,
              let dict = try? JSONSerialization.jsonObject(with: Data(jsonStr.utf8)) as? [String: Any] else {
            XCTFail("Failed to parse result"); return
        }
        XCTAssertEqual(dict["x"] as? Double, 1000000)
        XCTAssertEqual(dict["y"] as? Double, 10)
    }

    // FN-05: Between two points, returns the closer one
    func testFN05_betweenTwoPoints_returnsCloser() {
        let result = evalJS("""
            const data = [
                {x: 1000000, y: 10},
                {x: 2000000, y: 20}
            ];
            const found = findNearest(data, 1300000);
            return JSON.stringify(found);
            """)
        // Distance to first: 300000, distance to second: 700000 (but second > threshold)
        // Closer to first
        guard let jsonStr = result as? String,
              let dict = try? JSONSerialization.jsonObject(with: Data(jsonStr.utf8)) as? [String: Any] else {
            XCTFail("Failed to parse result"); return
        }
        XCTAssertEqual(dict["x"] as? Double, 1000000, "Should return the closer point")
    }
}

// MARK: - formatDateShort (FDS-01~FDS-03)

final class AnalysisFormatDateShortTests: AnalysisJSTestCase {

    // FDS-01: Standard date — month/day with zero-padded day
    func testFDS01_standardDate_formatted() {
        let result = evalJS("""
            return formatDateShort(new Date(2026, 0, 5));
            """)
        // January = month 0, getMonth()+1 = 1, day = 05
        XCTAssertEqual(result as? String, "1/05")
    }

    // FDS-02: Double-digit month and day
    func testFDS02_doubleDigitMonthDay() {
        let result = evalJS("""
            return formatDateShort(new Date(2026, 11, 25));
            """)
        // December = month 11, getMonth()+1 = 12, day = 25
        XCTAssertEqual(result as? String, "12/25")
    }

    // FDS-03: Single-digit day is zero-padded
    func testFDS03_singleDigitDay_zeroPadded() {
        let result = evalJS("""
            return formatDateShort(new Date(2026, 2, 1));
            """)
        // March = month 2, getMonth()+1 = 3, day = 01
        XCTAssertEqual(result as? String, "3/01")
    }
}

// MARK: - formatDateFull (FDF-01~FDF-03)

final class AnalysisFormatDateFullTests: AnalysisJSTestCase {

    // FDF-01: Includes day-of-week abbreviation
    func testFDF01_includesDayOfWeek() {
        let result = evalJS("""
            return formatDateFull(new Date(2026, 2, 7));
            """)
        // 2026-03-07 is a Saturday
        XCTAssertEqual(result as? String, "Sat 3/07")
    }

    // FDF-02: Sunday
    func testFDF02_sunday() {
        let result = evalJS("""
            return formatDateFull(new Date(2026, 2, 8));
            """)
        // 2026-03-08 is a Sunday
        XCTAssertEqual(result as? String, "Sun 3/08")
    }

    // FDF-03: Monday with double-digit month
    func testFDF03_mondayDoubleDigitMonth() {
        let result = evalJS("""
            return formatDateFull(new Date(2026, 11, 7));
            """)
        // 2026-12-07 is a Monday
        XCTAssertEqual(result as? String, "Mon 12/07")
    }
}

// MARK: - buildSessionSlots (BSS-01~BSS-04)

final class AnalysisBuildSessionSlotsTests: AnalysisJSTestCase {

    // BSS-01: Single session — returns one slot with correct start/end
    func testBSS01_singleSession_oneSlot() {
        let result = evalJS("""
            const sessions = [{id: 1, resets_at: 1000}];
            const slots = buildSessionSlots(sessions, 600, (s, e) => 'label');
            return JSON.stringify(slots);
            """)
        guard let jsonStr = result as? String,
              let slots = try? JSONSerialization.jsonObject(with: Data(jsonStr.utf8)) as? [[String: Any]] else {
            XCTFail("Failed to parse result"); return
        }
        XCTAssertEqual(slots.count, 1)
        // start = resets_at - intervalSec = 1000 - 600 = 400
        XCTAssertEqual(slots[0]["start"] as? Double, 400)
        // end = resets_at = 1000
        XCTAssertEqual(slots[0]["end"] as? Double, 1000)
    }

    // BSS-02: Multiple sessions — returns correct number of slots
    func testBSS02_multipleSessions_correctCount() {
        let result = evalJS("""
            const sessions = [
                {id: 1, resets_at: 1000},
                {id: 2, resets_at: 2000},
                {id: 3, resets_at: 3000}
            ];
            return buildSessionSlots(sessions, 600, (s, e) => 'x').length;
            """)
        XCTAssertEqual(result as? Int, 3)
    }

    // BSS-03: Null/undefined sessions — returns empty array
    func testBSS03_nullSessions_emptyArray() {
        let result = evalJS("""
            return buildSessionSlots(null, 600, (s, e) => 'x').length;
            """)
        XCTAssertEqual(result as? Int, 0)
    }

    // BSS-04: labelFn receives Date objects from start/end
    func testBSS04_labelFn_receivesDateObjects() {
        let result = evalJS("""
            const sessions = [{id: 1, resets_at: 86400}];
            const slots = buildSessionSlots(sessions, 3600, (s, e) => {
                return s.constructor.name + '|' + e.constructor.name;
            });
            return slots[0].label;
            """)
        XCTAssertEqual(result as? String, "Date|Date",
                       "labelFn should receive Date objects for start and end")
    }
}

// MARK: - buildCalendarSlots (BCS-01~BCS-04)

final class AnalysisBuildCalendarSlotsTests: AnalysisJSTestCase {

    // BCS-01: Empty meta (no timestamps) — returns empty array
    func testBCS01_emptyMeta_emptySlots() {
        let result = evalJS("""
            return buildCalendarSlots({}, 86400, (d) => 'x').length;
            """)
        XCTAssertEqual(result as? Int, 0)
    }

    // BCS-02: Single day range — at least one slot created
    func testBCS02_singleDayRange_oneSlot() {
        let result = evalJS("""
            // Both timestamps on the same day (2026-03-07 00:00:00 ~ 2026-03-07 12:00:00 UTC)
            const meta = {
                oldestTimestamp: 1772928000,
                latestTimestamp: 1772971200
            };
            const slots = buildCalendarSlots(meta, 86400, (d) => 'day');
            return slots.length;
            """)
        guard let count = result as? Int else {
            XCTFail("Expected integer result"); return
        }
        XCTAssertGreaterThanOrEqual(count, 1, "Single day range should produce at least 1 slot")
    }

    // BCS-03: Missing oldestTimestamp — returns empty
    func testBCS03_missingOldest_empty() {
        let result = evalJS("""
            return buildCalendarSlots({latestTimestamp: 1000}, 86400, (d) => 'x').length;
            """)
        XCTAssertEqual(result as? Int, 0)
    }

    // BCS-04: Missing latestTimestamp — returns empty
    func testBCS04_missingLatest_empty() {
        let result = evalJS("""
            return buildCalendarSlots({oldestTimestamp: 1000}, 86400, (d) => 'x').length;
            """)
        XCTAssertEqual(result as? Int, 0)
    }
}

// MARK: - timeXScale (TXS-01~TXS-03)

final class AnalysisTimeXScaleTests: AnalysisJSTestCase {

    // TXS-01: Default — no min/max set, returns config without min/max
    func testTXS01_default_noMinMax() {
        let result = evalJS("""
            _xMin = null;
            _xMax = null;
            const cfg = timeXScale();
            return JSON.stringify({
                type: cfg.type,
                hasMin: 'min' in cfg,
                hasMax: 'max' in cfg
            });
            """)
        guard let jsonStr = result as? String,
              let dict = try? JSONSerialization.jsonObject(with: Data(jsonStr.utf8)) as? [String: Any] else {
            XCTFail("Failed to parse result"); return
        }
        XCTAssertEqual(dict["type"] as? String, "time")
        XCTAssertEqual(dict["hasMin"] as? Bool, false, "null _xMin should not add min to config")
        XCTAssertEqual(dict["hasMax"] as? Bool, false, "null _xMax should not add max to config")
    }

    // TXS-02: With min/max set — config includes them
    func testTXS02_withMinMax_includedInConfig() {
        let result = evalJS("""
            _xMin = 1000;
            _xMax = 2000;
            const cfg = timeXScale();
            const result = JSON.stringify({min: cfg.min, max: cfg.max});
            _xMin = null; _xMax = null;
            return result;
            """)
        guard let jsonStr = result as? String,
              let dict = try? JSONSerialization.jsonObject(with: Data(jsonStr.utf8)) as? [String: Any] else {
            XCTFail("Failed to parse result"); return
        }
        XCTAssertEqual(dict["min"] as? Double, 1000)
        XCTAssertEqual(dict["max"] as? Double, 2000)
    }

    // TXS-03: Ticks and grid are disabled
    func testTXS03_ticksAndGridDisabled() {
        let result = evalJS("""
            const cfg = timeXScale();
            return JSON.stringify({
                ticksDisplay: cfg.ticks.display,
                gridDisplay: cfg.grid.display
            });
            """)
        guard let jsonStr = result as? String,
              let dict = try? JSONSerialization.jsonObject(with: Data(jsonStr.utf8)) as? [String: Any] else {
            XCTFail("Failed to parse result"); return
        }
        XCTAssertEqual(dict["ticksDisplay"] as? Bool, false)
        XCTAssertEqual(dict["gridDisplay"] as? Bool, false)
    }
}
