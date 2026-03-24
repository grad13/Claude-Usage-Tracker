// meta: updated=2026-03-06 18:11 checked=-
// Tests for DisplayHelpers marker text positioning logic
// Split from: widget/WidgetMiniGraphCalcTests.swift (S6: responsibility separation)

import XCTest
import ClaudeUsageTrackerShared

// MARK: - WidgetMiniGraph marker text positioning logic
// Tests call DisplayHelpers (Shared module) directly — no spec re-implementation.

final class MarkerTextPositioningTests: XCTestCase {

    // MARK: - percentTextShowsBelow (percent-based: > 80% → below)

    func testMarkerTextPosition_above80_placedBelow() {
        XCTAssertTrue(DisplayHelpers.percentTextShowsBelow(percent: 90))
    }

    func testMarkerTextPosition_exactly80_placedAbove() {
        XCTAssertFalse(DisplayHelpers.percentTextShowsBelow(percent: 80))
    }

    func testMarkerTextPosition_below80_placedAbove() {
        XCTAssertFalse(DisplayHelpers.percentTextShowsBelow(percent: 47))
    }

    // MARK: - percentTextAnchorX (horizontal anchor)
    // Rule: x < margin(16) → 0 (leading); x > width-margin → 1 (trailing); else → 0.5 (center)

    func testMarkerTextAnchor_nearLeftEdge_isLeading() {
        XCTAssertEqual(DisplayHelpers.percentTextAnchorX(markerX: 10, graphWidth: 100), 0)
    }

    func testMarkerTextAnchor_atLeftMarginBoundary_isLeading() {
        // x = 15 < 16 → leading (0)
        XCTAssertEqual(DisplayHelpers.percentTextAnchorX(markerX: 15, graphWidth: 100), 0)
    }

    func testMarkerTextAnchor_justInsideLeftMargin_isCenter() {
        // x = 16 is NOT < 16 → check right; 16 < 84 → center (0.5)
        XCTAssertEqual(DisplayHelpers.percentTextAnchorX(markerX: 16, graphWidth: 100), 0.5)
    }

    func testMarkerTextAnchor_nearRightEdge_isTrailing() {
        XCTAssertEqual(DisplayHelpers.percentTextAnchorX(markerX: 90, graphWidth: 100), 1)
    }

    func testMarkerTextAnchor_atRightMarginBoundary_isTrailing() {
        // x = 85, width = 100 → 85 > 84 → trailing (1)
        XCTAssertEqual(DisplayHelpers.percentTextAnchorX(markerX: 85, graphWidth: 100), 1)
    }

    func testMarkerTextAnchor_middleOfGraph_isCenter() {
        XCTAssertEqual(DisplayHelpers.percentTextAnchorX(markerX: 50, graphWidth: 100), 0.5)
    }
}
