// meta: updated=2026-03-07 08:17 checked=-
// Supplement 2 for: app-windows UI spec
// Source spec: docs/spec/ui/app-windows.md
//
// Skipped (require ViewInspector or live App):
//   - Text fallback font (.system(size: 11, weight: .medium)) and color (colorScheme-adaptive)
//     -> Inline SwiftUI modifiers, not extractable as constants
//   - MiniUsageGraph fixed parameters (areaOpacity 0.7/0.65, divisions 5/7)
//     -> Inline in MenuBarLabel view body, not extracted as testable constants
//   - Window IDs, default sizes, AppDelegate activation policy
//     -> Require live App environment
//   - LoginWindowView error UI, PopupSheetView layout/dismiss
//     -> Require ViewInspector
//
// Covered here:
//   1. ChartColorPreset RGB values via hexString (all 7 presets)

import XCTest
@testable import ClaudeUsageTracker

final class AppWindowsSupplementTests2: XCTestCase {

    // MARK: - ChartColorPreset RGB values (spec table: exact RGB per preset)

    func testBlueRGB() {
        // Spec: blue = (100, 180, 255)
        XCTAssertEqual(ChartColorPreset.blue.hexString, "#64b4ff")
    }

    func testPinkRGB() {
        // Spec: pink = (255, 130, 180)
        XCTAssertEqual(ChartColorPreset.pink.hexString, "#ff82b4")
    }

    func testGreenRGB() {
        // Spec: green = (70, 210, 80)
        XCTAssertEqual(ChartColorPreset.green.hexString, "#46d250")
    }

    func testTealRGB() {
        // Spec: teal = (0, 210, 190)
        XCTAssertEqual(ChartColorPreset.teal.hexString, "#00d2be")
    }

    func testPurpleRGB() {
        // Spec: purple = (150, 110, 255)
        XCTAssertEqual(ChartColorPreset.purple.hexString, "#966eff")
    }

    func testOrangeRGB() {
        // Spec: orange = (255, 160, 60)
        XCTAssertEqual(ChartColorPreset.orange.hexString, "#ffa03c")
    }

    func testWhiteRGB() {
        // Spec: white = (230, 230, 230)
        XCTAssertEqual(ChartColorPreset.white.hexString, "#e6e6e6")
    }
}
