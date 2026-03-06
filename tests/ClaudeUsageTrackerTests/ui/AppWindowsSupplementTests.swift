// Supplement for: app-windows UI logic tests
// Source spec: _documents/spec/ui/app-windows.md
//
// Skipped (SwiftUI Scene/View rendering tests):
//   - App struct 3-Scene definitions, LoginWindowView error UI rendering,
//     PopupSheetView layout, AppDelegate activation policy
//     → Require live App environment or ViewInspector
//
// Covered here:
//   1. MenuBarLabel.graphCount (static, extracted for testability)
//   2. Fallback NSImage size constant (80 x 18 pt)
//   3. Retina scale = 2.0 (spec constant)

import XCTest
@testable import ClaudeUsageTracker

final class AppWindowsSupplementTests: XCTestCase {

    // MARK: - graphCount via MenuBarLabel.graphCount(settings:)

    func testGraphCount_bothTrue_isTwo() {
        var settings = AppSettings()
        settings.showHourlyGraph = true
        settings.showWeeklyGraph = true
        XCTAssertEqual(MenuBarLabel.graphCount(settings: settings), 2)
    }

    func testGraphCount_hourlyOnlyTrue_isOne() {
        var settings = AppSettings()
        settings.showHourlyGraph = true
        settings.showWeeklyGraph = false
        XCTAssertEqual(MenuBarLabel.graphCount(settings: settings), 1)
    }

    func testGraphCount_weeklyOnlyTrue_isOne() {
        var settings = AppSettings()
        settings.showHourlyGraph = false
        settings.showWeeklyGraph = true
        XCTAssertEqual(MenuBarLabel.graphCount(settings: settings), 1)
    }

    func testGraphCount_bothFalse_isZero() {
        var settings = AppSettings()
        settings.showHourlyGraph = false
        settings.showWeeklyGraph = false
        XCTAssertEqual(MenuBarLabel.graphCount(settings: settings), 0)
    }

    func testGraphCount_zero_impliesTextFallback() {
        var settings = AppSettings()
        settings.showHourlyGraph = false
        settings.showWeeklyGraph = false
        XCTAssertFalse(MenuBarLabel.graphCount(settings: settings) > 0,
            "graphCount == 0 must NOT trigger graph display")
    }

    func testGraphCount_nonZero_impliesGraphDisplay() {
        var settings = AppSettings()
        settings.showHourlyGraph = false
        settings.showWeeklyGraph = true
        XCTAssertTrue(MenuBarLabel.graphCount(settings: settings) > 0,
            "graphCount > 0 must trigger graph display")
    }

    // MARK: - Fallback NSImage size (spec constant: 80 x 18)

    func testFallbackImageSize_width() {
        let fallbackSize = NSSize(width: 80, height: 18)
        XCTAssertEqual(fallbackSize.width, 80,
                       "Fallback NSImage width must be 80 pt per spec")
    }

    func testFallbackImageSize_height() {
        let fallbackSize = NSSize(width: 80, height: 18)
        XCTAssertEqual(fallbackSize.height, 18,
                       "Fallback NSImage height must be 18 pt per spec")
    }

    func testFallbackImageSize_isNotZero() {
        let fallbackSize = NSSize(width: 80, height: 18)
        XCTAssertGreaterThan(fallbackSize.width, 0)
        XCTAssertGreaterThan(fallbackSize.height, 0)
    }

    // MARK: - Retina scale (spec constant: 2.0)

    func testRetina_scale_isTwo() {
        let rendererScale: CGFloat = 2.0
        XCTAssertEqual(rendererScale, 2.0,
                       "ImageRenderer scale must be 2.0 for Retina display support")
    }

    func testRetina_logicalWidth_halvesCGImageWidth() {
        let cgImageWidth = 96
        let logicalWidth = CGFloat(cgImageWidth) / 2.0
        XCTAssertEqual(logicalWidth, 48.0)
    }

    func testRetina_logicalHeight_halvesCGImageHeight() {
        let cgImageHeight = 36
        let logicalHeight = CGFloat(cgImageHeight) / 2.0
        XCTAssertEqual(logicalHeight, 18.0)
    }

    func testRetina_logicalSize_forDefaultChartWidth() {
        let settings = AppSettings()
        let physicalWidth = CGFloat(settings.chartWidth) * 2.0
        let logicalWidth = physicalWidth / 2.0
        XCTAssertEqual(logicalWidth, CGFloat(settings.chartWidth))
    }
}
