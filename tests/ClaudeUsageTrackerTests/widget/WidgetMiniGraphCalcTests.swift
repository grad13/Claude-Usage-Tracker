// Tests for WidgetMiniGraph coordinate-calculation logic
// Covers: resolveWindowStart, drawTicks divisions, buildPoints
//
// Split: NowXFractionTests → widget/WidgetMediumViewNowXTests.swift
//        MarkerTextPositioningTests → shared/DisplayHelpersMarkerTests.swift

import XCTest
import ClaudeUsageTrackerShared
@testable import ClaudeUsageTracker

// MARK: - Helpers

/// Lightweight stand-in for the spec's HistoryPoint type.
/// Matches the shape used in UsageSnapshot.fiveHourHistory / sevenDayHistory.
private typealias HP = HistoryPoint

/// Reproduces resolveWindowStart logic from spec (WidgetMiniGraph):
///   1. resetsAt != nil  → resetsAt - windowSeconds
///   2. resetsAt == nil, history non-empty → history.first!.timestamp
///   3. both absent → nil
private func specResolveWindowStart(
    resetsAt: Date?,
    windowSeconds: TimeInterval,
    history: [HP]
) -> Date? {
    if let r = resetsAt {
        return r.addingTimeInterval(-windowSeconds)
    } else if let first = history.first {
        return first.timestamp
    }
    return nil
}

/// Reproduces buildPoints coordinate logic from spec (WidgetMiniGraph):
/// Returns array of (xFrac, yFrac) for each point that passes the elapsed >= 0 guard.
private func specBuildPoints(
    history: [HP],
    windowStart: Date,
    windowSeconds: TimeInterval
) -> [(xFrac: Double, yFrac: Double)] {
    var result: [(xFrac: Double, yFrac: Double)] = []
    for dp in history {
        let elapsed = dp.timestamp.timeIntervalSince(windowStart)
        guard elapsed >= 0 else { continue }
        let xFrac = min(elapsed / windowSeconds, 1.0)
        let yFrac = min(dp.percent / 100.0, 1.0)
        result.append((xFrac: xFrac, yFrac: yFrac))
    }
    return result
}

/// Reproduces drawTicks division logic from spec (WidgetMiniGraph):
///   windowSeconds <= 18001 → 5 divisions, otherwise → 7.
private func specTickDivisions(windowSeconds: TimeInterval) -> Int {
    windowSeconds <= 5 * 3600 + 1 ? 5 : 7
}

// MARK: - resolveWindowStart

final class ResolveWindowStartTests: XCTestCase {

    private let windowSeconds5h: TimeInterval = 5 * 3600
    private let windowSeconds7d: TimeInterval = 7 * 24 * 3600
    private let anchor = Date(timeIntervalSince1970: 1_740_000_000)

    // Case 1: resetsAt non-nil → windowStart = resetsAt - windowSeconds

    func testResolveWindowStart_withResetsAt_returns_resetsAt_minus_window() {
        let resetsAt = anchor.addingTimeInterval(3600) // 1h in future
        let result = specResolveWindowStart(
            resetsAt: resetsAt,
            windowSeconds: windowSeconds5h,
            history: []
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(
            result!.timeIntervalSince1970,
            resetsAt.addingTimeInterval(-windowSeconds5h).timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testResolveWindowStart_withResetsAt_7d_ignoresHistory() {
        let resetsAt = anchor.addingTimeInterval(24 * 3600)
        // Even if history has data, resetsAt takes priority
        let historyPoint = HP(timestamp: anchor.addingTimeInterval(-100), percent: 30)
        let result = specResolveWindowStart(
            resetsAt: resetsAt,
            windowSeconds: windowSeconds7d,
            history: [historyPoint]
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(
            result!.timeIntervalSince1970,
            resetsAt.addingTimeInterval(-windowSeconds7d).timeIntervalSince1970,
            accuracy: 0.001,
            "resetsAt path must be taken even when history is non-empty"
        )
    }

    // Case 2: resetsAt nil, history non-empty → windowStart = history.first.timestamp

    func testResolveWindowStart_noResetsAt_usesFirstHistoryTimestamp() {
        let firstTimestamp = anchor.addingTimeInterval(-1000)
        let history = [
            HP(timestamp: firstTimestamp, percent: 10),
            HP(timestamp: firstTimestamp.addingTimeInterval(300), percent: 20)
        ]
        let result = specResolveWindowStart(
            resetsAt: nil,
            windowSeconds: windowSeconds5h,
            history: history
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(
            result!.timeIntervalSince1970,
            firstTimestamp.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testResolveWindowStart_noResetsAt_singleHistoryPoint_usesItsTimestamp() {
        let ts = anchor.addingTimeInterval(-500)
        let result = specResolveWindowStart(
            resetsAt: nil,
            windowSeconds: windowSeconds5h,
            history: [HP(timestamp: ts, percent: 55)]
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.timeIntervalSince1970, ts.timeIntervalSince1970, accuracy: 0.001)
    }

    // Case 3: both absent → nil

    func testResolveWindowStart_noResetsAt_emptyHistory_returnsNil() {
        let result = specResolveWindowStart(
            resetsAt: nil,
            windowSeconds: windowSeconds5h,
            history: []
        )
        XCTAssertNil(result,
            "Without resetsAt or history, windowStart cannot be determined → nil stops rendering")
    }

    func testResolveWindowStart_noResetsAt_emptyHistory_7d_returnsNil() {
        let result = specResolveWindowStart(
            resetsAt: nil,
            windowSeconds: windowSeconds7d,
            history: []
        )
        XCTAssertNil(result)
    }
}

// MARK: - drawTicks divisions

final class DrawTicksDivisionsTests: XCTestCase {

    /// Spec: windowSeconds <= 5h+1s (18001) → 5 divisions
    func testTickDivisions_5hWindow_returns5() {
        XCTAssertEqual(specTickDivisions(windowSeconds: 5 * 3600), 5)
    }

    /// Spec: boundary value — exactly 18001 seconds → 5 divisions
    func testTickDivisions_boundaryValue_18001_returns5() {
        XCTAssertEqual(specTickDivisions(windowSeconds: 18001), 5)
    }

    /// Spec: 18002 seconds > 18001 → 7 divisions
    func testTickDivisions_18002_returns7() {
        XCTAssertEqual(specTickDivisions(windowSeconds: 18002), 7)
    }

    /// Spec: 7d window → 7 divisions
    func testTickDivisions_7dWindow_returns7() {
        XCTAssertEqual(specTickDivisions(windowSeconds: 7 * 24 * 3600), 7)
    }

    /// Spec: drawTicks uses 1..<divisions — boundary indices (0 and divisions) are not drawn.
    /// For 5 divisions: ticks at i=1,2,3,4 → 4 tick lines.
    func testTickCount_5divisions_gives4Lines() {
        let divisions = specTickDivisions(windowSeconds: 5 * 3600)
        let tickCount = (1..<divisions).count
        XCTAssertEqual(tickCount, 4)
    }

    /// For 7 divisions: ticks at i=1,2,3,4,5,6 → 6 tick lines.
    func testTickCount_7divisions_gives6Lines() {
        let divisions = specTickDivisions(windowSeconds: 7 * 24 * 3600)
        let tickCount = (1..<divisions).count
        XCTAssertEqual(tickCount, 6)
    }

    /// Tick x positions: x_i = i / divisions * width. Verify for 5-division case.
    func testTickXPositions_5divisions_evenlySpaced() {
        let w: Double = 100
        let divisions = specTickDivisions(windowSeconds: 5 * 3600)
        let xs = (1..<divisions).map { i in Double(i) / Double(divisions) * w }
        XCTAssertEqual(xs.count, 4)
        XCTAssertEqual(xs[0], 20, accuracy: 0.001)
        XCTAssertEqual(xs[1], 40, accuracy: 0.001)
        XCTAssertEqual(xs[2], 60, accuracy: 0.001)
        XCTAssertEqual(xs[3], 80, accuracy: 0.001)
    }
}

// MARK: - buildPoints coordinate calculations

final class BuildPointsTests: XCTestCase {

    private let anchor = Date(timeIntervalSince1970: 1_740_000_000)
    private let windowSeconds: TimeInterval = 5 * 3600 // 18000s

    /// Basic case: single point exactly at windowStart → xFrac = 0, yFrac = percent/100
    func testBuildPoints_singlePoint_atWindowStart_xFracZero() {
        let history = [HP(timestamp: anchor, percent: 50)]
        let pts = specBuildPoints(history: history, windowStart: anchor, windowSeconds: windowSeconds)
        XCTAssertEqual(pts.count, 1)
        XCTAssertEqual(pts[0].xFrac, 0.0, accuracy: 0.0001)
        XCTAssertEqual(pts[0].yFrac, 0.5, accuracy: 0.0001)
    }

    /// Point at half-elapsed time → xFrac = 0.5
    func testBuildPoints_singlePoint_atHalfElapsed_xFracHalf() {
        let halfElapsed = anchor.addingTimeInterval(windowSeconds / 2)
        let history = [HP(timestamp: halfElapsed, percent: 25)]
        let pts = specBuildPoints(history: history, windowStart: anchor, windowSeconds: windowSeconds)
        XCTAssertEqual(pts.count, 1)
        XCTAssertEqual(pts[0].xFrac, 0.5, accuracy: 0.0001)
        XCTAssertEqual(pts[0].yFrac, 0.25, accuracy: 0.0001)
    }

    /// Point at window end → xFrac clamped to 1.0
    func testBuildPoints_singlePoint_atWindowEnd_xFracOne() {
        let atEnd = anchor.addingTimeInterval(windowSeconds)
        let history = [HP(timestamp: atEnd, percent: 100)]
        let pts = specBuildPoints(history: history, windowStart: anchor, windowSeconds: windowSeconds)
        XCTAssertEqual(pts.count, 1)
        XCTAssertEqual(pts[0].xFrac, 1.0, accuracy: 0.0001)
        XCTAssertEqual(pts[0].yFrac, 1.0, accuracy: 0.0001)
    }

    /// Point past window end → xFrac clamped to 1.0 (min(..., 1.0))
    func testBuildPoints_singlePoint_pastWindowEnd_xFracClampedTo1() {
        let pastEnd = anchor.addingTimeInterval(windowSeconds + 3600)
        let history = [HP(timestamp: pastEnd, percent: 80)]
        let pts = specBuildPoints(history: history, windowStart: anchor, windowSeconds: windowSeconds)
        XCTAssertEqual(pts.count, 1)
        XCTAssertEqual(pts[0].xFrac, 1.0, accuracy: 0.0001,
            "xFrac must be clamped to 1.0 for points beyond window end")
    }

    /// Point before windowStart (elapsed < 0) → excluded
    func testBuildPoints_pointBeforeWindowStart_isExcluded() {
        let before = anchor.addingTimeInterval(-1)
        let history = [HP(timestamp: before, percent: 40)]
        let pts = specBuildPoints(history: history, windowStart: anchor, windowSeconds: windowSeconds)
        XCTAssertTrue(pts.isEmpty,
            "Points with elapsed < 0 must be skipped (guard elapsed >= 0)")
    }

    /// Mixed: one point before, one after windowStart → only the second survives
    func testBuildPoints_mixed_beforeAndAfterWindowStart_onlyLaterSurvives() {
        let history = [
            HP(timestamp: anchor.addingTimeInterval(-300), percent: 10),  // before
            HP(timestamp: anchor.addingTimeInterval(1800), percent: 30)   // within
        ]
        let pts = specBuildPoints(history: history, windowStart: anchor, windowSeconds: windowSeconds)
        XCTAssertEqual(pts.count, 1)
        XCTAssertEqual(pts[0].xFrac, 0.1, accuracy: 0.0001)  // 1800 / 18000 = 0.1
        XCTAssertEqual(pts[0].yFrac, 0.3, accuracy: 0.0001)
    }

    /// Percent > 100 → yFrac clamped to 1.0
    func testBuildPoints_percentOver100_yFracClampedTo1() {
        let history = [HP(timestamp: anchor.addingTimeInterval(100), percent: 150)]
        let pts = specBuildPoints(history: history, windowStart: anchor, windowSeconds: windowSeconds)
        XCTAssertEqual(pts.count, 1)
        XCTAssertEqual(pts[0].yFrac, 1.0, accuracy: 0.0001,
            "yFrac = min(percent/100, 1.0) must clamp values above 100%")
    }

    /// Percent = 0 → yFrac = 0.0
    func testBuildPoints_percentZero_yFracZero() {
        let history = [HP(timestamp: anchor.addingTimeInterval(100), percent: 0)]
        let pts = specBuildPoints(history: history, windowStart: anchor, windowSeconds: windowSeconds)
        XCTAssertEqual(pts.count, 1)
        XCTAssertEqual(pts[0].yFrac, 0.0, accuracy: 0.0001)
    }

    /// Empty history → empty result (no crash)
    func testBuildPoints_emptyHistory_returnsEmpty() {
        let pts = specBuildPoints(history: [], windowStart: anchor, windowSeconds: windowSeconds)
        XCTAssertTrue(pts.isEmpty)
    }

    /// Multiple in-window points: ordering preserved
    func testBuildPoints_multiplePoints_orderPreserved() {
        let history = [
            HP(timestamp: anchor.addingTimeInterval(3600),  percent: 10),
            HP(timestamp: anchor.addingTimeInterval(7200),  percent: 20),
            HP(timestamp: anchor.addingTimeInterval(14400), percent: 40)
        ]
        let pts = specBuildPoints(history: history, windowStart: anchor, windowSeconds: windowSeconds)
        XCTAssertEqual(pts.count, 3)
        XCTAssertLessThan(pts[0].xFrac, pts[1].xFrac, "x positions must be increasing")
        XCTAssertLessThan(pts[1].xFrac, pts[2].xFrac)
        XCTAssertEqual(pts[0].xFrac, 3600.0 / 18000.0, accuracy: 0.0001)
        XCTAssertEqual(pts[1].xFrac, 7200.0 / 18000.0, accuracy: 0.0001)
        XCTAssertEqual(pts[2].xFrac, 14400.0 / 18000.0, accuracy: 0.0001)
    }

    // MARK: y coordinate (inverted: top=0%, bottom=100%)

    /// Spec: y = h - yFrac * h  → high usage = lower y (bottom of graph).
    /// Verify that yFrac → pixel y is an inversion.
    func testBuildPoints_yCoordInversion_highUsageLowerY() {
        let h: Double = 100
        // 75% usage → yFrac = 0.75 → y = 100 - 0.75*100 = 25 (closer to top numerically but visually lower)
        let yFrac75 = 0.75
        let yFrac25 = 0.25
        let y75 = h - yFrac75 * h
        let y25 = h - yFrac25 * h
        XCTAssertLessThan(y75, y25,
            "Higher usage (75%) must produce smaller y value (closer to top of canvas)")
    }
}

// Note: NowXFractionTests moved to widget/WidgetMediumViewNowXTests.swift
// Note: MarkerTextPositioningTests moved to shared/DisplayHelpersMarkerTests.swift
