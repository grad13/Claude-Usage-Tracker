// Tests for GraphCalc.nowXFraction calculation
// Split from: widget/WidgetMiniGraphCalcTests.swift (S6: responsibility separation)

import XCTest
import ClaudeUsageTrackerShared

// MARK: - nowXFraction (WidgetMediumView)

final class NowXFractionTests: XCTestCase {

    private let windowSeconds5h: TimeInterval = 5 * 3600
    private let windowSeconds7d: TimeInterval = 7 * 24 * 3600

    func testNowXFraction_nowAtWindowStart_isZero() {
        let resetsAt = Date(timeIntervalSince1970: 1_740_018_000)
        let windowStart = resetsAt.addingTimeInterval(-windowSeconds5h)
        let result = GraphCalc.nowXFraction(resetsAt: resetsAt, windowSeconds: windowSeconds5h, now: windowStart)
        XCTAssertEqual(Double(result), 0.0, accuracy: 0.0001)
    }

    func testNowXFraction_nowAtResetsAt_isOne() {
        let resetsAt = Date(timeIntervalSince1970: 1_740_018_000)
        let result = GraphCalc.nowXFraction(resetsAt: resetsAt, windowSeconds: windowSeconds5h, now: resetsAt)
        XCTAssertEqual(Double(result), 1.0, accuracy: 0.0001)
    }

    func testNowXFraction_nowAtMidpoint_isHalf() {
        let resetsAt = Date(timeIntervalSince1970: 1_740_018_000)
        let midpoint = resetsAt.addingTimeInterval(-windowSeconds5h / 2)
        let result = GraphCalc.nowXFraction(resetsAt: resetsAt, windowSeconds: windowSeconds5h, now: midpoint)
        XCTAssertEqual(Double(result), 0.5, accuracy: 0.0001)
    }

    func testNowXFraction_nowPastResetsAt_clampedToOne() {
        let resetsAt = Date(timeIntervalSince1970: 1_740_018_000)
        let afterReset = resetsAt.addingTimeInterval(3600)
        let result = GraphCalc.nowXFraction(resetsAt: resetsAt, windowSeconds: windowSeconds5h, now: afterReset)
        XCTAssertEqual(Double(result), 1.0, accuracy: 0.0001,
            "Fraction must not exceed 1.0 even when now > resetsAt")
    }

    func testNowXFraction_nowBeforeWindowStart_clampedToZero() {
        let resetsAt = Date(timeIntervalSince1970: 1_740_018_000)
        let beforeWindow = resetsAt.addingTimeInterval(-(windowSeconds5h + 3600))
        let result = GraphCalc.nowXFraction(resetsAt: resetsAt, windowSeconds: windowSeconds5h, now: beforeWindow)
        XCTAssertEqual(Double(result), 0.0, accuracy: 0.0001,
            "Fraction must not go below 0.0 even when now < windowStart")
    }

    func testNowXFraction_7dWindow_halfElapsed_isHalf() {
        let resetsAt = Date(timeIntervalSince1970: 1_740_604_800)
        let halfElapsed = resetsAt.addingTimeInterval(-windowSeconds7d / 2)
        let result = GraphCalc.nowXFraction(resetsAt: resetsAt, windowSeconds: windowSeconds7d, now: halfElapsed)
        XCTAssertEqual(Double(result), 0.5, accuracy: 0.0001)
    }

    func testNowXFraction_pixelPosition_midpointMapsToHalfWidth() {
        let w: Double = 200
        let resetsAt = Date(timeIntervalSince1970: 1_740_018_000)
        let midpoint = resetsAt.addingTimeInterval(-windowSeconds5h / 2)
        let fraction = GraphCalc.nowXFraction(resetsAt: resetsAt, windowSeconds: windowSeconds5h, now: midpoint)
        let pixelX = Double(fraction) * w
        XCTAssertEqual(pixelX, 100.0, accuracy: 0.01)
    }
}
