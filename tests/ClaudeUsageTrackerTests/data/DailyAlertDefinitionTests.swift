// meta: updated=2026-03-06 18:11 checked=-
// Tests for DailyAlertDefinition enum values
// Split from: ui/MenuContentSupplementTests.swift (S6: responsibility separation)

import XCTest
@testable import ClaudeUsageTracker

final class DailyAlertDefinitionTests: XCTestCase {

    // Guarantees: Day Definition submenu has exactly two options as specified.

    func testCalendarIsDefault() {
        XCTAssertEqual(AppSettings().dailyAlertDefinition, .calendar,
            "Default day definition must be .calendar (Calendar (midnight))")
    }

    func testAllCasesMatchSpec() {
        // Spec: Calendar (midnight) = .calendar, Session-based = .session
        let allCases = DailyAlertDefinition.allCases
        XCTAssertEqual(allCases.count, 2,
            "DailyAlertDefinition must have exactly 2 cases: .calendar and .session")
        XCTAssertTrue(allCases.contains(.calendar))
        XCTAssertTrue(allCases.contains(.session))
    }
}
