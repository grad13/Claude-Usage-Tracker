// Tests for: MiniUsageGraph pure logic (usageValue, fillEndFrac)
// Source spec: spec/ui/mini-usage-graph.md
// Generated: 2026-03-06
//
// Covers:
//   - UV-01~UV-06: usageValue(from:) — windowSeconds-based percent selection
//   - FE-01~FE-03: fillEndFrac — fill end position determination

import XCTest
@testable import ClaudeUsageTracker

// MARK: - usageValue (UV-01~UV-06)

final class MiniUsageGraphUsageValueTests: XCTestCase {

    private func makeGraph(windowSeconds: TimeInterval) -> MiniUsageGraph {
        MiniUsageGraph(
            history: [],
            windowSeconds: windowSeconds,
            resetsAt: nil,
            areaColor: .blue,
            areaOpacity: 0.5,
            divisions: 4,
            chartWidth: 100,
            isLoggedIn: true
        )
    }

    private func makeDataPoint(fiveHour: Double?, sevenDay: Double?) -> UsageStore.DataPoint {
        UsageStore.DataPoint(
            timestamp: Date(),
            fiveHourPercent: fiveHour,
            sevenDayPercent: sevenDay,
            fiveHourResetsAt: nil,
            sevenDayResetsAt: nil
        )
    }

    /// UV-01: windowSeconds=18000 (5h) → fiveHourPercent
    func testUV01_exactlyFiveHours_returnsFiveHourPercent() {
        let graph = makeGraph(windowSeconds: 18000)
        let dp = makeDataPoint(fiveHour: 50.0, sevenDay: 80.0)
        XCTAssertEqual(graph.usageValue(from: dp), 50.0)
    }

    /// UV-02: windowSeconds=18001 (5h+1s, threshold boundary) → fiveHourPercent
    func testUV02_thresholdBoundary_returnsFiveHourPercent() {
        let graph = makeGraph(windowSeconds: 18001)
        let dp = makeDataPoint(fiveHour: 50.0, sevenDay: 80.0)
        XCTAssertEqual(graph.usageValue(from: dp), 50.0)
    }

    /// UV-03: windowSeconds=18002 (above threshold) → sevenDayPercent
    func testUV03_aboveThreshold_returnsSevenDayPercent() {
        let graph = makeGraph(windowSeconds: 18002)
        let dp = makeDataPoint(fiveHour: 50.0, sevenDay: 80.0)
        XCTAssertEqual(graph.usageValue(from: dp), 80.0)
    }

    /// UV-04: windowSeconds=604800 (7d) → sevenDayPercent
    func testUV04_sevenDayWindow_returnsSevenDayPercent() {
        let graph = makeGraph(windowSeconds: 604800)
        let dp = makeDataPoint(fiveHour: 50.0, sevenDay: 80.0)
        XCTAssertEqual(graph.usageValue(from: dp), 80.0)
    }

    /// UV-05: windowSeconds=3600 (1h), fiveHourPercent is nil → nil
    func testUV05_fiveHourNil_returnsNil() {
        let graph = makeGraph(windowSeconds: 3600)
        let dp = makeDataPoint(fiveHour: nil, sevenDay: 80.0)
        XCTAssertNil(graph.usageValue(from: dp))
    }

    /// UV-06: windowSeconds=86400 (1d), sevenDayPercent is nil → nil
    func testUV06_sevenDayNil_returnsNil() {
        let graph = makeGraph(windowSeconds: 86400)
        let dp = makeDataPoint(fiveHour: 50.0, sevenDay: nil)
        XCTAssertNil(graph.usageValue(from: dp))
    }
}

// MARK: - fillEndFrac (FE-01~FE-03)

final class MiniUsageGraphFillEndFracTests: XCTestCase {

    private func makeGraph(windowSeconds: TimeInterval) -> MiniUsageGraph {
        MiniUsageGraph(
            history: [],
            windowSeconds: windowSeconds,
            resetsAt: nil,
            areaColor: .blue,
            areaOpacity: 0.5,
            divisions: 4,
            chartWidth: 100,
            isLoggedIn: true
        )
    }

    /// FE-01: resetsAt is set → fillEndFrac = max(resetFrac, lastPointFrac)
    func testFE01_resetsAtSet_extendsToResetTime() {
        let graph = makeGraph(windowSeconds: 3600)
        let windowStart = Date(timeIntervalSince1970: 1000)
        let resetsAt = Date(timeIntervalSince1970: 1000 + 3600) // window end
        let now = Date(timeIntervalSince1970: 1000 + 1800)       // midpoint

        let result = graph.fillEndFrac(
            resetsAt: resetsAt,
            windowStart: windowStart,
            now: now,
            lastPointFrac: 0.5
        )
        // resetFrac = 3600/3600 = 1.0, lastPointFrac = 0.5 → max = 1.0
        XCTAssertEqual(result, 1.0, accuracy: 0.001)
    }

    /// FE-01b: resetsAt < lastPoint → uses lastPointFrac
    func testFE01b_resetsAtBeforeLastPoint_usesLastPointFrac() {
        let graph = makeGraph(windowSeconds: 3600)
        let windowStart = Date(timeIntervalSince1970: 1000)
        let resetsAt = Date(timeIntervalSince1970: 1000 + 1800) // 0.5 frac
        let now = Date(timeIntervalSince1970: 1000 + 2700)

        let result = graph.fillEndFrac(
            resetsAt: resetsAt,
            windowStart: windowStart,
            now: now,
            lastPointFrac: 0.8
        )
        // resetFrac = 0.5, lastPointFrac = 0.8 → max = 0.8
        XCTAssertEqual(result, 0.8, accuracy: 0.001)
    }

    /// FE-02: resetsAt=nil, now > lastPoint → nowFrac
    func testFE02_noResets_nowBeyondLastPoint_usesNowFrac() {
        let graph = makeGraph(windowSeconds: 3600)
        let windowStart = Date(timeIntervalSince1970: 1000)
        let now = Date(timeIntervalSince1970: 1000 + 2700) // 0.75 frac

        let result = graph.fillEndFrac(
            resetsAt: nil,
            windowStart: windowStart,
            now: now,
            lastPointFrac: 0.5
        )
        // nowFrac = 2700/3600 = 0.75, lastPointFrac = 0.5 → max = 0.75
        XCTAssertEqual(result, 0.75, accuracy: 0.001)
    }

    /// FE-03: resetsAt=nil, now < lastPoint → lastPointFrac
    func testFE03_noResets_nowBeforeLastPoint_usesLastPointFrac() {
        let graph = makeGraph(windowSeconds: 3600)
        let windowStart = Date(timeIntervalSince1970: 1000)
        let now = Date(timeIntervalSince1970: 1000 + 900) // 0.25 frac

        let result = graph.fillEndFrac(
            resetsAt: nil,
            windowStart: windowStart,
            now: now,
            lastPointFrac: 0.8
        )
        // nowFrac = 0.25, lastPointFrac = 0.8 → max = 0.8
        XCTAssertEqual(result, 0.8, accuracy: 0.001)
    }
}
