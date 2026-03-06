// Tests for WidgetMediumView.nowXFraction calculation
// Split from: widget/WidgetMiniGraphCalcTests.swift (S6: responsibility separation)

import XCTest
@testable import ClaudeUsageTracker

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
