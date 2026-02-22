import XCTest
import WeatherCCShared

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

    // MARK: - percentTextShowsBelow

    func testShowsBelow_nearTop() {
        // markerY = 5, topMargin = 14 → near top, should show below
        XCTAssertTrue(DisplayHelpers.percentTextShowsBelow(markerY: 5, graphHeight: 60))
    }

    func testShowsBelow_lowerHalf() {
        // markerY = 40 (> 60*0.5=30), NOT near top → should show above (false)
        XCTAssertFalse(DisplayHelpers.percentTextShowsBelow(markerY: 40, graphHeight: 60))
    }

    func testShowsBelow_upperHalf() {
        // markerY = 25 (<= 60*0.5=30), not near top (25 > 14) → shows below
        XCTAssertTrue(DisplayHelpers.percentTextShowsBelow(markerY: 25, graphHeight: 60))
    }

    func testShowsBelow_exactMiddle() {
        // markerY = 30, h*0.5 = 30 → markerY <= h*0.5 → shows below
        XCTAssertTrue(DisplayHelpers.percentTextShowsBelow(markerY: 30, graphHeight: 60))
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
}
