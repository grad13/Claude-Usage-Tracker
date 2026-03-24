// meta: updated=2026-03-04 16:54 checked=-
import XCTest
import ClaudeUsageTrackerShared

final class DisplayHelpersTests: XCTestCase {

    // MARK: - remainingText

    func testRemainingText_days() {
        let now = Date()
        let target = now.addingTimeInterval(3 * 24 * 3600 + 5 * 3600 + 30)
        XCTAssertEqual(DisplayHelpers.remainingText(until: target, now: now), "3d 5h")
    }

    func testRemainingText_hours() {
        let now = Date()
        let target = now.addingTimeInterval(2 * 3600 + 15 * 60 + 30)
        XCTAssertEqual(DisplayHelpers.remainingText(until: target, now: now), "2h 15m")
    }

    func testRemainingText_minutesOnly() {
        let now = Date()
        let target = now.addingTimeInterval(19 * 60 + 30)
        XCTAssertEqual(DisplayHelpers.remainingText(until: target, now: now), "19m")
    }

    func testRemainingText_expired() {
        let now = Date()
        let target = now.addingTimeInterval(-100)
        XCTAssertEqual(DisplayHelpers.remainingText(until: target, now: now), "expired")
    }

    func testRemainingText_zero() {
        let now = Date()
        // Exactly 0 seconds remaining → expired (guard remaining > 0)
        XCTAssertEqual(DisplayHelpers.remainingText(until: now, now: now), "expired")
    }

    func testRemainingText_justUnderOneHour() {
        let now = Date()
        let target = now.addingTimeInterval(59 * 60 + 59)
        XCTAssertEqual(DisplayHelpers.remainingText(until: target, now: now), "59m")
    }

    // MARK: - percentTextShowsBelow (percent-based: > 80% → below)

    func testShowsBelow_above80() {
        XCTAssertTrue(DisplayHelpers.percentTextShowsBelow(percent: 81))
    }

    func testShowsBelow_exactly80() {
        XCTAssertFalse(DisplayHelpers.percentTextShowsBelow(percent: 80))
    }

    func testShowsBelow_below80() {
        XCTAssertFalse(DisplayHelpers.percentTextShowsBelow(percent: 47))
    }

    func testShowsBelow_zero() {
        XCTAssertFalse(DisplayHelpers.percentTextShowsBelow(percent: 0))
    }

    // MARK: - percentTextAnchorX

    func testAnchorX_leftEdge() {
        // markerX = 5 < margin(16) → leading (0)
        XCTAssertEqual(DisplayHelpers.percentTextAnchorX(markerX: 5, graphWidth: 140), 0)
    }

    func testAnchorX_rightEdge() {
        // markerX = 130 > 140 - 16 = 124 → trailing (1)
        XCTAssertEqual(DisplayHelpers.percentTextAnchorX(markerX: 130, graphWidth: 140), 1)
    }

    func testAnchorX_center() {
        // markerX = 70, well within margins → center (0.5)
        XCTAssertEqual(DisplayHelpers.percentTextAnchorX(markerX: 70, graphWidth: 140), 0.5)
    }

    func testAnchorX_exactLeftMargin() {
        // markerX = 16, NOT < 16 → center (0.5)
        XCTAssertEqual(DisplayHelpers.percentTextAnchorX(markerX: 16, graphWidth: 140), 0.5)
    }

    func testAnchorX_exactRightMargin() {
        // markerX = 124, NOT > 124 → center (0.5)
        XCTAssertEqual(DisplayHelpers.percentTextAnchorX(markerX: 124, graphWidth: 140), 0.5)
    }

    // MARK: - remainingText Boundary Cases

    func testRemainingText_exactly24Hours() {
        let now = Date()
        let target = now.addingTimeInterval(24 * 3600)
        // hours=24, >= 24 → "1d 0h"
        XCTAssertEqual(DisplayHelpers.remainingText(until: target, now: now), "1d 0h")
    }

    func testRemainingText_exactly1Hour() {
        let now = Date()
        let target = now.addingTimeInterval(3600)
        XCTAssertEqual(DisplayHelpers.remainingText(until: target, now: now), "1h 0m")
    }

    func testRemainingText_1Second() {
        let now = Date()
        let target = now.addingTimeInterval(1)
        // Int(1) / 3600 = 0 hours, Int(1) % 3600 / 60 = 0 minutes
        XCTAssertEqual(DisplayHelpers.remainingText(until: target, now: now), "0m")
    }

    func testRemainingText_veryLarge() {
        let now = Date()
        let target = now.addingTimeInterval(365 * 24 * 3600) // 1 year
        let text = DisplayHelpers.remainingText(until: target, now: now)
        XCTAssertTrue(text.hasSuffix("h"), "Very large time should produce 'Xd Xh' format")
        XCTAssertTrue(text.contains("d"))
    }

    func testShowsBelow_100percent() {
        XCTAssertTrue(DisplayHelpers.percentTextShowsBelow(percent: 100))
    }

    // MARK: - Non-default margin for anchorX

    func testAnchorX_customMargin() {
        // Custom margin = 30
        // markerX = 25 < 30 → leading (0)
        XCTAssertEqual(DisplayHelpers.percentTextAnchorX(markerX: 25, graphWidth: 140, margin: 30), 0)
        // markerX = 115 > 140 - 30 = 110 → trailing (1)
        XCTAssertEqual(DisplayHelpers.percentTextAnchorX(markerX: 115, graphWidth: 140, margin: 30), 1)
        // markerX = 70, within margins → center (0.5)
        XCTAssertEqual(DisplayHelpers.percentTextAnchorX(markerX: 70, graphWidth: 140, margin: 30), 0.5)
    }

    // MARK: - Edge case: zero/very small graphHeight/graphWidth

    func testShowsBelow_boundaryJustAbove80() {
        XCTAssertTrue(DisplayHelpers.percentTextShowsBelow(percent: 80.1))
    }

    func testAnchorX_verySmallGraphWidth() {
        // graphWidth = 10, margin = 16 → graphWidth - margin = -6
        // markerX = 5 < 16 → leading (0)
        XCTAssertEqual(DisplayHelpers.percentTextAnchorX(markerX: 5, graphWidth: 10), 0)
    }

    // MARK: - Sub-second remaining

    func testRemainingText_halfSecond() {
        let now = Date()
        let target = now.addingTimeInterval(0.5)
        // remaining = 0.5 > 0 → passes guard. Int(0.5) = 0 → hours=0, minutes=0 → "0m"
        XCTAssertEqual(DisplayHelpers.remainingText(until: target, now: now), "0m",
                       "Sub-second remaining (0.5s) rounds down to 0 total seconds → 0m")
    }

    // MARK: - Negative markerY / markerX

    func testShowsBelow_negativePercent() {
        XCTAssertFalse(DisplayHelpers.percentTextShowsBelow(percent: -5))
    }

    func testAnchorX_negativeMarkerX() {
        // -10 < margin(16) → leading (0)
        XCTAssertEqual(DisplayHelpers.percentTextAnchorX(markerX: -10, graphWidth: 140), 0,
                       "Negative markerX should return leading anchor (0)")
    }
}
