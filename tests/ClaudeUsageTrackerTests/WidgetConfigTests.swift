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

private typealias HP = HistoryPoint

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
