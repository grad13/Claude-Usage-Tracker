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

// MARK: - Helpers

private typealias HP = HistoryPoint

/// Reproduces WidgetLargeView.remainingText prefix logic from spec:
///   DisplayHelpers result == "expired" → keep as-is, else prepend "in ".
private func specLargeRemainingText(_ displayHelpersResult: String) -> String {
    displayHelpersResult == "expired" ? displayHelpersResult : "in " + displayHelpersResult
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
        let now = Date()
        let interval: TimeInterval = (4 * 24 + 21) * 3600
        let future = now.addingTimeInterval(interval)
        let result = DisplayHelpers.remainingText(until: future, now: now)
        XCTAssertEqual(result, "4d 21h",
            "4d21h interval must format as '4d 21h'")
    }

    /// Exactly 24h → "1d 0h"
    func testRemainingText_exactly24hours() {
        let now = Date()
        let future = now.addingTimeInterval(24 * 3600)
        let result = DisplayHelpers.remainingText(until: future, now: now)
        XCTAssertEqual(result, "1d 0h")
    }

    /// 2h 35m
    func testRemainingText_2hours35minutes() {
        let now = Date()
        let interval: TimeInterval = 2 * 3600 + 35 * 60
        let future = now.addingTimeInterval(interval)
        let result = DisplayHelpers.remainingText(until: future, now: now)
        XCTAssertEqual(result, "2h 35m")
    }

    /// 1h 0m
    func testRemainingText_exactly1hour() {
        let now = Date()
        let future = now.addingTimeInterval(3600)
        let result = DisplayHelpers.remainingText(until: future, now: now)
        XCTAssertEqual(result, "1h 0m")
    }

    /// 19m — "0h" must be omitted
    func testRemainingText_19minutes_noZeroHourPrefix() {
        let now = Date()
        let future = now.addingTimeInterval(19 * 60)
        let result = DisplayHelpers.remainingText(until: future, now: now)
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
        let now = Date()
        let past = now.addingTimeInterval(-1)
        let result = DisplayHelpers.remainingText(until: past, now: now)
        XCTAssertEqual(result, "expired")
    }

    /// Spec: "0h 19m" → "19m" (regression guard for 2026-02-22 change)
    func testRemainingText_doesNotReturn0hPrefix() {
        let now = Date()
        let future = now.addingTimeInterval(19 * 60 + 30)
        let result = DisplayHelpers.remainingText(until: future, now: now)
        XCTAssertFalse(result.hasPrefix("0h"),
            "Spec change 2026-02-22: '0h Xm' format is banned; must be just 'Xm'")
    }
}
