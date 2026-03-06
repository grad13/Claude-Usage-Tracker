// Tests for ChartColorPreset enum display names
// Split from: ui/MenuContentSupplementTests.swift (S6: responsibility separation)

import XCTest
@testable import ClaudeUsageTracker

final class ChartColorPresetTests: XCTestCase {

    // Guarantees: color picker items show display names as specified.

    func testBlueDisplayName() {
        XCTAssertEqual(ChartColorPreset.blue.displayName, "Blue")
    }

    func testPinkDisplayName() {
        XCTAssertEqual(ChartColorPreset.pink.displayName, "Pink")
    }

    func testGreenDisplayName() {
        XCTAssertEqual(ChartColorPreset.green.displayName, "Green")
    }

    func testTealDisplayName() {
        XCTAssertEqual(ChartColorPreset.teal.displayName, "Teal")
    }

    func testPurpleDisplayName() {
        XCTAssertEqual(ChartColorPreset.purple.displayName, "Purple")
    }

    func testOrangeDisplayName() {
        XCTAssertEqual(ChartColorPreset.orange.displayName, "Orange")
    }

    func testWhiteDisplayName() {
        XCTAssertEqual(ChartColorPreset.white.displayName, "White")
    }

    func testAllCasesCount() {
        // Spec lists exactly 7 color presets.
        XCTAssertEqual(ChartColorPreset.allCases.count, 7,
            "ChartColorPreset must have exactly 7 cases as specified")
    }
}
