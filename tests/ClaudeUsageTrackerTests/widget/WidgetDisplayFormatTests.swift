// meta: updated=2026-03-06 18:36 checked=-
// Supplement for: widget design integration tests
// Source spec: _documents/spec/widget/design.md
//
// Scope:
//   1. GraphCalc.remainingTextWithPrefix logic
//   2. DisplayHelpers.remainingText formatting

import XCTest
import ClaudeUsageTrackerShared

// MARK: - WidgetLargeView remainingText prefix logic

final class LargeViewRemainingTextTests: XCTestCase {

    func testRemainingText_expired_noPrefix() {
        XCTAssertEqual(GraphCalc.remainingTextWithPrefix("expired"), "expired",
            "'expired' must be returned as-is without 'in ' prefix")
    }

    func testRemainingText_hours_getsInPrefix() {
        XCTAssertEqual(GraphCalc.remainingTextWithPrefix("2h 35m"), "in 2h 35m")
    }

    func testRemainingText_days_getsInPrefix() {
        XCTAssertEqual(GraphCalc.remainingTextWithPrefix("4d 21h"), "in 4d 21h")
    }

    func testRemainingText_minutes_getsInPrefix() {
        XCTAssertEqual(GraphCalc.remainingTextWithPrefix("19m"), "in 19m")
    }

    func testRemainingText_largeDisplayFormat_resets_in() {
        let largeText = "resets " + GraphCalc.remainingTextWithPrefix("2h 35m")
        XCTAssertEqual(largeText, "resets in 2h 35m")
    }

    func testRemainingText_expiredFullDisplay_noIn() {
        let largeText = "resets " + GraphCalc.remainingTextWithPrefix("expired")
        XCTAssertEqual(largeText, "resets expired")
    }
}

// MARK: - DisplayHelpers.remainingText formatting

final class DisplayHelpersRemainingTextTests: XCTestCase {

    func testRemainingText_4days21hours() {
        let now = Date()
        let interval: TimeInterval = (4 * 24 + 21) * 3600
        let future = now.addingTimeInterval(interval)
        let result = DisplayHelpers.remainingText(until: future, now: now)
        XCTAssertEqual(result, "4d 21h")
    }

    func testRemainingText_exactly24hours() {
        let now = Date()
        let future = now.addingTimeInterval(24 * 3600)
        let result = DisplayHelpers.remainingText(until: future, now: now)
        XCTAssertEqual(result, "1d 0h")
    }

    func testRemainingText_2hours35minutes() {
        let now = Date()
        let interval: TimeInterval = 2 * 3600 + 35 * 60
        let future = now.addingTimeInterval(interval)
        let result = DisplayHelpers.remainingText(until: future, now: now)
        XCTAssertEqual(result, "2h 35m")
    }

    func testRemainingText_exactly1hour() {
        let now = Date()
        let future = now.addingTimeInterval(3600)
        let result = DisplayHelpers.remainingText(until: future, now: now)
        XCTAssertEqual(result, "1h 0m")
    }

    func testRemainingText_19minutes_noZeroHourPrefix() {
        let now = Date()
        let future = now.addingTimeInterval(19 * 60)
        let result = DisplayHelpers.remainingText(until: future, now: now)
        XCTAssertEqual(result, "19m")
    }

    func testRemainingText_1minute() {
        let now = Date()
        let future = now.addingTimeInterval(60)
        let result = DisplayHelpers.remainingText(until: future, now: now)
        XCTAssertEqual(result, "1m")
    }

    func testRemainingText_expired_pastDate() {
        let now = Date()
        let past = now.addingTimeInterval(-1)
        let result = DisplayHelpers.remainingText(until: past, now: now)
        XCTAssertEqual(result, "expired")
    }

    func testRemainingText_doesNotReturn0hPrefix() {
        let now = Date()
        let future = now.addingTimeInterval(19 * 60 + 30)
        let result = DisplayHelpers.remainingText(until: future, now: now)
        XCTAssertFalse(result.hasPrefix("0h"))
    }
}
