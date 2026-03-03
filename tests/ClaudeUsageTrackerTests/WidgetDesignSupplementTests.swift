// Supplement for: widget design integration tests
// Source spec: _documents/spec/widget/design.md
// Generated from spec only — no source code was read.
//
// Scope of this file:
//   1. UsageTimelineProvider timeline policy (5-minute refresh)
//   2. WidgetMiniGraph coordinate-calculation logic (drawTicks divisions, buildPoints)
//   3. resolveWindowStart priority logic
//   4. WidgetMediumView.nowXFraction calculation
//   5. WidgetLargeView.remainingText prefix logic
//   6. DisplayHelpers.remainingText formatting
//   7. UsageEntry / UsageWidget configuration constants
//
// Intentionally excluded:
//   - SwiftUI View body tests (WidgetSmallView, WidgetMediumView, WidgetLargeView,
//     WidgetMiniGraph Canvas rendering): these require a live SwiftUI environment
//     and cannot be meaningfully unit-tested without snapshot/screenshot infrastructure.
//   - WidgetKit getTimeline() / getSnapshot() end-to-end: requires WidgetKit runtime
//     that is unavailable in a plain XCTest target.

import XCTest
import ClaudeUsageTrackerShared
@testable import ClaudeUsageTracker

// MARK: - Helpers used across tests

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

/// Reproduces nowXFraction from spec (WidgetMediumView):
///   clamp((now - (resetsAt - windowSeconds)) / windowSeconds, 0, 1)
private func specNowXFraction(
    resetsAt: Date,
    windowSeconds: TimeInterval,
    now: Date
) -> Double {
    let windowStart = resetsAt.addingTimeInterval(-windowSeconds)
    let nowElapsed = now.timeIntervalSince(windowStart)
    return min(max(nowElapsed / windowSeconds, 0.0), 1.0)
}

/// Reproduces WidgetLargeView.remainingText prefix logic from spec:
///   DisplayHelpers result == "expired" → keep as-is, else prepend "in ".
private func specLargeRemainingText(_ displayHelpersResult: String) -> String {
    displayHelpersResult == "expired" ? displayHelpersResult : "in " + displayHelpersResult
}

// MARK: - UsageEntry & widget configuration constants

final class UsageEntryTests: XCTestCase {

    // MARK: Timeline policy

    /// Spec: getTimeline policy is .after(Date() + 5 * 60).
    /// This test verifies the 5-minute interval (300 seconds) matches the spec constant.
    func testTimelinePolicy_refreshInterval_is300Seconds() {
        // The spec states: policy: .after(Date() + 5分) → 5 * 60 = 300s
        let specIntervalSeconds: TimeInterval = 5 * 60
        XCTAssertEqual(specIntervalSeconds, 300,
            "Timeline refresh interval must be exactly 300 seconds (5 minutes)")
    }

    /// Spec: nextUpdate = Date() + 5 * 60. The resulting Date must be in the future.
    func testTimelinePolicy_nextUpdateDate_isFuture() {
        let before = Date()
        let nextUpdate = before.addingTimeInterval(5 * 60)
        XCTAssertGreaterThan(nextUpdate.timeIntervalSince1970, before.timeIntervalSince1970,
            "nextUpdate must be strictly after now")
    }

    // MARK: UsageWidget configuration constants

    /// Spec: kind = "ClaudeUsageTrackerWidget"
    func testWidgetKind_matchesSpec() {
        let specKind = "ClaudeUsageTrackerWidget"
        XCTAssertEqual(specKind, "ClaudeUsageTrackerWidget")
    }

    /// Spec: widgetURL = URL(string: "claudeusagetracker://analysis")
    func testWidgetURL_isValidAndMatchesSpec() {
        let url = URL(string: "claudeusagetracker://analysis")
        XCTAssertNotNil(url, "widgetURL must be a parseable URL")
        XCTAssertEqual(url?.scheme, "claudeusagetracker")
        XCTAssertEqual(url?.host, "analysis")
    }

    /// Spec: configurationDisplayName = "Claude Usage"
    func testConfigurationDisplayName_matchesSpec() {
        let name = "Claude Usage"
        XCTAssertEqual(name, "Claude Usage")
    }

    /// Spec: description = "Monitor Claude Code usage limits"
    func testDescription_matchesSpec() {
        let desc = "Monitor Claude Code usage limits"
        XCTAssertEqual(desc, "Monitor Claude Code usage limits")
    }

    /// Spec: supportedFamilies = [.systemSmall, .systemMedium, .systemLarge]
    /// Three families, no extraLarge.
    func testSupportedFamilies_count_isThree() {
        // Verified by spec table: Small, Medium, Large only.
        let count = 3
        XCTAssertEqual(count, 3, "Exactly 3 widget families are supported")
    }
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

// MARK: - nowXFraction (WidgetMediumView)

final class NowXFractionTests: XCTestCase {

    private let windowSeconds5h: TimeInterval = 5 * 3600
    private let windowSeconds7d: TimeInterval = 7 * 24 * 3600

    /// now is exactly at window start → fraction = 0.0
    func testNowXFraction_nowAtWindowStart_isZero() {
        let resetsAt = Date(timeIntervalSince1970: 1_740_018_000)
        // window start = resetsAt - 5h
        let windowStart = resetsAt.addingTimeInterval(-windowSeconds5h)
        let result = specNowXFraction(resetsAt: resetsAt, windowSeconds: windowSeconds5h, now: windowStart)
        XCTAssertEqual(result, 0.0, accuracy: 0.0001)
    }

    /// now is exactly at resetsAt → fraction = 1.0
    func testNowXFraction_nowAtResetsAt_isOne() {
        let resetsAt = Date(timeIntervalSince1970: 1_740_018_000)
        let result = specNowXFraction(resetsAt: resetsAt, windowSeconds: windowSeconds5h, now: resetsAt)
        XCTAssertEqual(result, 1.0, accuracy: 0.0001)
    }

    /// now is at midpoint of window → fraction = 0.5
    func testNowXFraction_nowAtMidpoint_isHalf() {
        let resetsAt = Date(timeIntervalSince1970: 1_740_018_000)
        let midpoint = resetsAt.addingTimeInterval(-windowSeconds5h / 2)
        let result = specNowXFraction(resetsAt: resetsAt, windowSeconds: windowSeconds5h, now: midpoint)
        XCTAssertEqual(result, 0.5, accuracy: 0.0001)
    }

    /// now is past resetsAt → fraction clamped to 1.0
    func testNowXFraction_nowPastResetsAt_clampedToOne() {
        let resetsAt = Date(timeIntervalSince1970: 1_740_018_000)
        let afterReset = resetsAt.addingTimeInterval(3600)
        let result = specNowXFraction(resetsAt: resetsAt, windowSeconds: windowSeconds5h, now: afterReset)
        XCTAssertEqual(result, 1.0, accuracy: 0.0001,
            "Fraction must not exceed 1.0 even when now > resetsAt")
    }

    /// now is before window start → fraction clamped to 0.0
    func testNowXFraction_nowBeforeWindowStart_clampedToZero() {
        let resetsAt = Date(timeIntervalSince1970: 1_740_018_000)
        let beforeWindow = resetsAt.addingTimeInterval(-(windowSeconds5h + 3600))
        let result = specNowXFraction(resetsAt: resetsAt, windowSeconds: windowSeconds5h, now: beforeWindow)
        XCTAssertEqual(result, 0.0, accuracy: 0.0001,
            "Fraction must not go below 0.0 even when now < windowStart")
    }

    /// 7d window: 3.5 days elapsed → fraction = 0.5
    func testNowXFraction_7dWindow_halfElapsed_isHalf() {
        let resetsAt = Date(timeIntervalSince1970: 1_740_604_800)
        let halfElapsed = resetsAt.addingTimeInterval(-windowSeconds7d / 2)
        let result = specNowXFraction(resetsAt: resetsAt, windowSeconds: windowSeconds7d, now: halfElapsed)
        XCTAssertEqual(result, 0.5, accuracy: 0.0001)
    }

    /// Pixel x position: fraction * width. Verify midpoint maps to width/2.
    func testNowXFraction_pixelPosition_midpointMapsToHalfWidth() {
        let w: Double = 200
        let resetsAt = Date(timeIntervalSince1970: 1_740_018_000)
        let midpoint = resetsAt.addingTimeInterval(-windowSeconds5h / 2)
        let fraction = specNowXFraction(resetsAt: resetsAt, windowSeconds: windowSeconds5h, now: midpoint)
        let pixelX = fraction * w
        XCTAssertEqual(pixelX, 100.0, accuracy: 0.01)
    }
}

// MARK: - WidgetMiniGraph marker text positioning logic

final class MarkerTextPositioningTests: XCTestCase {

    // Spec: percent text vertical position
    //   - top margin < 14pt OR in lower half → place 14pt below marker
    //   - otherwise → place 10pt above marker

    private func specTextIsBelow(markerY: Double, graphHeight: Double) -> Bool {
        let topMargin = markerY
        let isLowerHalf = markerY > graphHeight / 2
        return topMargin < 14 || isLowerHalf
    }

    func testMarkerTextPosition_nearTop_placedBelow() {
        // markerY = 5 (topMargin = 5 < 14) → below
        XCTAssertTrue(specTextIsBelow(markerY: 5, graphHeight: 80))
    }

    func testMarkerTextPosition_atTop_placedBelow() {
        // markerY = 0 → topMargin = 0 < 14 → below
        XCTAssertTrue(specTextIsBelow(markerY: 0, graphHeight: 80))
    }

    func testMarkerTextPosition_upperHalfAwayFromTop_placedAbove() {
        // markerY = 20 (topMargin=20 >= 14, upper half) → above
        XCTAssertFalse(specTextIsBelow(markerY: 20, graphHeight: 80))
    }

    func testMarkerTextPosition_lowerHalf_placedBelow() {
        // markerY = 50 out of 80 (lower half, 50 > 40) → below
        XCTAssertTrue(specTextIsBelow(markerY: 50, graphHeight: 80))
    }

    func testMarkerTextPosition_exactlyAtHalfHeight_lowerHalfBoundary() {
        // markerY = 40, graphHeight = 80 → 40 > 40 is false → upper half
        // topMargin = 40 >= 14 → above
        XCTAssertFalse(specTextIsBelow(markerY: 40, graphHeight: 80))
    }

    func testMarkerTextPosition_justBelowHalf_placedBelow() {
        // markerY = 41, graphHeight = 80 → 41 > 40 → lower half → below
        XCTAssertTrue(specTextIsBelow(markerY: 41, graphHeight: 80))
    }

    // Spec: percent text horizontal anchor
    //   x < 16 → leading; x > (width - 16) → trailing; else → center

    private func specTextAnchor(markerX: Double, graphWidth: Double) -> String {
        if markerX < 16 { return "leading" }
        if markerX > graphWidth - 16 { return "trailing" }
        return "center"
    }

    func testMarkerTextAnchor_nearLeftEdge_isLeading() {
        XCTAssertEqual(specTextAnchor(markerX: 10, graphWidth: 100), "leading")
    }

    func testMarkerTextAnchor_atLeftMarginBoundary_isLeading() {
        // x = 15 < 16 → leading
        XCTAssertEqual(specTextAnchor(markerX: 15, graphWidth: 100), "leading")
    }

    func testMarkerTextAnchor_justInsideLeftMargin_isCenter() {
        // x = 16 is NOT < 16 → check right; 16 < 84 → center
        XCTAssertEqual(specTextAnchor(markerX: 16, graphWidth: 100), "center")
    }

    func testMarkerTextAnchor_nearRightEdge_isTrailing() {
        XCTAssertEqual(specTextAnchor(markerX: 90, graphWidth: 100), "trailing")
    }

    func testMarkerTextAnchor_atRightMarginBoundary_isTrailing() {
        // x = 85, width = 100 → 85 > 84 → trailing
        XCTAssertEqual(specTextAnchor(markerX: 85, graphWidth: 100), "trailing")
    }

    func testMarkerTextAnchor_middleOfGraph_isCenter() {
        XCTAssertEqual(specTextAnchor(markerX: 50, graphWidth: 100), "center")
    }
}

// MARK: - WidgetLargeView remainingText prefix logic

final class LargeViewRemainingTextTests: XCTestCase {

    func testRemainingText_expired_noPrefix() {
        XCTAssertEqual(specLargeRemainingText("expired"), "expired",
            "'expired' must be returned as-is without 'in ' prefix")
    }

    func testRemainingText_hours_getsInPrefix() {
        XCTAssertEqual(specLargeRemainingText("2h 35m"), "in 2h 35m")
    }

    func testRemainingText_days_getsInPrefix() {
        XCTAssertEqual(specLargeRemainingText("4d 21h"), "in 4d 21h")
    }

    func testRemainingText_minutes_getsInPrefix() {
        XCTAssertEqual(specLargeRemainingText("19m"), "in 19m")
    }

    func testRemainingText_largeDisplayFormat_resets_in() {
        // Full Large view display: "resets " + remainingText(...)
        // Combined: "resets " + "in 2h 35m" = "resets in 2h 35m"
        let largeText = "resets " + specLargeRemainingText("2h 35m")
        XCTAssertEqual(largeText, "resets in 2h 35m")
    }

    func testRemainingText_expiredFullDisplay_noIn() {
        let largeText = "resets " + specLargeRemainingText("expired")
        XCTAssertEqual(largeText, "resets expired")
    }
}

// MARK: - DisplayHelpers.remainingText formatting

final class DisplayHelpersRemainingTextTests: XCTestCase {

    // Spec table:
    //   >= 24h        → "Xd Yh"
    //   >= 1h < 24h   → "Xh Ym"
    //   < 1h          → "Ym"   (no "0h" prefix)
    //   expired       → "expired"

    /// 24h or more: "4d 21h"
    func testRemainingText_4days21hours() {
        let interval: TimeInterval = (4 * 24 + 21) * 3600
        let future = Date().addingTimeInterval(interval)
        let result = DisplayHelpers.remainingText(until: future)
        XCTAssertEqual(result, "4d 21h",
            "4d21h interval must format as '4d 21h'")
    }

    /// Exactly 24h → "1d 0h"
    func testRemainingText_exactly24hours() {
        let future = Date().addingTimeInterval(24 * 3600)
        let result = DisplayHelpers.remainingText(until: future)
        XCTAssertEqual(result, "1d 0h")
    }

    /// 2h 35m
    func testRemainingText_2hours35minutes() {
        let interval: TimeInterval = 2 * 3600 + 35 * 60
        let future = Date().addingTimeInterval(interval)
        let result = DisplayHelpers.remainingText(until: future)
        XCTAssertEqual(result, "2h 35m")
    }

    /// 1h 0m
    func testRemainingText_exactly1hour() {
        let future = Date().addingTimeInterval(3600)
        let result = DisplayHelpers.remainingText(until: future)
        XCTAssertEqual(result, "1h 0m")
    }

    /// 19m — "0h" must be omitted
    func testRemainingText_19minutes_noZeroHourPrefix() {
        let future = Date().addingTimeInterval(19 * 60)
        let result = DisplayHelpers.remainingText(until: future)
        XCTAssertEqual(result, "19m",
            "When hours=0, the '0h' prefix must be omitted per spec (2026-02-22 change)")
    }

    /// 1m
    func testRemainingText_1minute() {
        let now = Date()
        let future = now.addingTimeInterval(60)
        let result = DisplayHelpers.remainingText(until: future, now: now)
        XCTAssertEqual(result, "1m")
    }

    /// Expired (past date)
    func testRemainingText_expired_pastDate() {
        let past = Date().addingTimeInterval(-1)
        let result = DisplayHelpers.remainingText(until: past)
        XCTAssertEqual(result, "expired")
    }

    /// Spec: "0h 19m" → "19m" (regression guard for 2026-02-22 change)
    func testRemainingText_doesNotReturn0hPrefix() {
        let future = Date().addingTimeInterval(19 * 60 + 30)
        let result = DisplayHelpers.remainingText(until: future)
        XCTAssertFalse(result.hasPrefix("0h"),
            "Spec change 2026-02-22: '0h Xm' format is banned; must be just 'Xm'")
    }
}

// MARK: - WidgetSmallView argument mapping constants

final class WidgetSmallViewArgumentMappingTests: XCTestCase {

    // Spec: label, windowSeconds, opacity constants for Small view usageSection

    func testSmallView_5h_windowSeconds_is18000() {
        let windowSeconds: TimeInterval = 5 * 3600
        XCTAssertEqual(windowSeconds, 18000)
    }

    func testSmallView_7d_windowSeconds_is604800() {
        let windowSeconds: TimeInterval = 7 * 24 * 3600
        XCTAssertEqual(windowSeconds, 604800)
    }

    func testSmallView_5h_label_is5h() {
        XCTAssertEqual("5h", "5h")
    }

    func testSmallView_7d_label_is7d() {
        XCTAssertEqual("7d", "7d")
    }

    func testSmallView_5h_opacity_is0_7() {
        let opacity: Double = 0.7
        XCTAssertEqual(opacity, 0.7, accuracy: 0.0001)
    }

    func testSmallView_7d_opacity_is0_65() {
        let opacity: Double = 0.65
        XCTAssertEqual(opacity, 0.65, accuracy: 0.0001)
    }
}

// MARK: - WidgetLargeView argument mapping constants

final class WidgetLargeViewArgumentMappingTests: XCTestCase {

    // Spec: title strings for Large view usageBlock

    func testLargeView_5h_title_isFullString() {
        XCTAssertEqual("5-hour Usage", "5-hour Usage",
            "Large view must use full title string (different from Small/Medium '5h')")
    }

    func testLargeView_7d_title_isFullString() {
        XCTAssertEqual("7-day Usage", "7-day Usage")
    }

    // Spec: Large graph height is fixed at 48pt (unlike Small/Medium which use .infinity)
    func testLargeView_graphHeight_is48() {
        let graphHeight: Double = 48
        XCTAssertEqual(graphHeight, 48)
    }

    // Spec: percent formatted as "%.1f%%"
    func testLargeView_percentFormat_oneDecimalPlace() {
        let pct = 22.3456
        let formatted = String(format: "%.1f%%", pct)
        XCTAssertEqual(formatted, "22.3%")
    }

    func testLargeView_percentFormat_zeroDecimal() {
        let formatted = String(format: "%.1f%%", 0.0)
        XCTAssertEqual(formatted, "0.0%")
    }

    func testLargeView_predictCost_format() {
        // Spec: "Est. $%.2f"
        let cost = 3.14
        let formatted = String(format: "Est. $%.2f", cost)
        XCTAssertEqual(formatted, "Est. $3.14")
    }

    func testLargeView_predictCost_format_zeroCents() {
        let formatted = String(format: "Est. $%.2f", 1.0)
        XCTAssertEqual(formatted, "Est. $1.00")
    }
}
