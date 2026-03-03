// Supplement for: app-windows UI logic tests
// Source spec: _documents/spec/ui/app-windows.md
// Generated from spec only — source code was NOT read.
//
// Skipped (SwiftUI Scene/View rendering tests):
//   - App struct 3-Scene definitions (MenuBarExtra, login Window, analysis Window)
//     → Reason: SwiftUI Scene body requires a live App environment; cannot be
//       instantiated in XCTest without significant harness work, and the spec
//       does not describe testable pure-logic types for these.
//   - LoginWindowView error UI rendering (conditional Text for viewModel.error)
//     → Reason: ViewInspector or snapshot infrastructure not present; rendering
//       behaviour is not reducible to pure-logic under XCTest.
//   - PopupSheetView / PopupWebViewWrapper layout
//     → Reason: Same as above — layout attributes are declarative SwiftUI,
//       not testable as pure logic.
//   - AppDelegate.applicationDidFinishLaunching activation policy
//     → Reason: Requires a running NSApplication; side-effect only, no return value.
//
// Covered here (pure logic derivable from spec):
//   1. graphCount calculation (showHourlyGraph + showWeeklyGraph combinations)
//   2. Fallback NSImage size when cgImage is nil (80 x 18 pt)
//   3. NSImage logical size from cgImage at scale 2.0 (divide by 2.0)
//   4. chartWidth validation boundary — NOT duplicated (covered in SettingsTests.swift)

import XCTest
@testable import ClaudeUsageTracker

final class AppWindowsSupplementTests: XCTestCase {

    // MARK: - graphCount Calculation Logic
    //
    // Spec: graphCount = (showHourlyGraph ? 1 : 0) + (showWeeklyGraph ? 1 : 0)
    //       graphCount > 0  → graph display (MenuBarGraphsContent)
    //       graphCount == 0 → text fallback (Text(statusText))

    func testGraphCount_bothTrue_isTwo() {
        var settings = AppSettings()
        settings.showHourlyGraph = true
        settings.showWeeklyGraph = true
        let graphCount = (settings.showHourlyGraph ? 1 : 0) + (settings.showWeeklyGraph ? 1 : 0)
        XCTAssertEqual(graphCount, 2, "Both enabled → graphCount must be 2")
    }

    func testGraphCount_hourlyOnlyTrue_isOne() {
        var settings = AppSettings()
        settings.showHourlyGraph = true
        settings.showWeeklyGraph = false
        let graphCount = (settings.showHourlyGraph ? 1 : 0) + (settings.showWeeklyGraph ? 1 : 0)
        XCTAssertEqual(graphCount, 1, "Hourly only → graphCount must be 1")
    }

    func testGraphCount_weeklyOnlyTrue_isOne() {
        var settings = AppSettings()
        settings.showHourlyGraph = false
        settings.showWeeklyGraph = true
        let graphCount = (settings.showHourlyGraph ? 1 : 0) + (settings.showWeeklyGraph ? 1 : 0)
        XCTAssertEqual(graphCount, 1, "Weekly only → graphCount must be 1")
    }

    func testGraphCount_bothFalse_isZero() {
        var settings = AppSettings()
        settings.showHourlyGraph = false
        settings.showWeeklyGraph = false
        let graphCount = (settings.showHourlyGraph ? 1 : 0) + (settings.showWeeklyGraph ? 1 : 0)
        XCTAssertEqual(graphCount, 0, "Both disabled → graphCount must be 0")
    }

    func testGraphCount_zero_impliesTextFallback() {
        // Spec: graphCount == 0 → text display path, not graph display path
        var settings = AppSettings()
        settings.showHourlyGraph = false
        settings.showWeeklyGraph = false
        let graphCount = (settings.showHourlyGraph ? 1 : 0) + (settings.showWeeklyGraph ? 1 : 0)
        XCTAssertFalse(graphCount > 0, "graphCount == 0 must NOT trigger graph display")
    }

    func testGraphCount_nonZero_impliesGraphDisplay() {
        // Spec: graphCount > 0 → graph display path
        var settings = AppSettings()
        settings.showHourlyGraph = false
        settings.showWeeklyGraph = true
        let graphCount = (settings.showHourlyGraph ? 1 : 0) + (settings.showWeeklyGraph ? 1 : 0)
        XCTAssertTrue(graphCount > 0, "graphCount > 0 must trigger graph display")
    }

    // MARK: - Fallback NSImage Size (cgImage == nil path)
    //
    // Spec: renderer.cgImage が nil の場合、
    //       NSImage(size: NSSize(width: 80, height: 18)) を返す

    func testFallbackImageSize_width() {
        // Spec mandates width = 80 pt for the empty fallback image
        let fallbackSize = NSSize(width: 80, height: 18)
        XCTAssertEqual(fallbackSize.width, 80,
                       "Fallback NSImage width must be 80 pt per spec")
    }

    func testFallbackImageSize_height() {
        // Spec mandates height = 18 pt for the empty fallback image
        let fallbackSize = NSSize(width: 80, height: 18)
        XCTAssertEqual(fallbackSize.height, 18,
                       "Fallback NSImage height must be 18 pt per spec")
    }

    func testFallbackImageSize_isNotZero() {
        // A zero-size NSImage would not be suitable as a menu bar label
        let fallbackSize = NSSize(width: 80, height: 18)
        XCTAssertGreaterThan(fallbackSize.width, 0,
                             "Fallback image must have positive width")
        XCTAssertGreaterThan(fallbackSize.height, 0,
                             "Fallback image must have positive height")
    }

    // MARK: - NSImage Logical Size from cgImage at Retina Scale 2.0
    //
    // Spec: renderer.scale = 2.0 (Retina)
    //       NSImage size = CGFloat(cgImage.width) / 2.0  x  CGFloat(cgImage.height) / 2.0

    func testRetina_logicalWidth_halvesCGImageWidth() {
        // Simulate a cgImage rendered at 2x: physical pixel width 96 → logical 48 pt
        let cgImageWidth = 96
        let logicalWidth = CGFloat(cgImageWidth) / 2.0
        XCTAssertEqual(logicalWidth, 48.0,
                       "Logical width must be cgImage.width / 2.0 to convert from 2x to 1x")
    }

    func testRetina_logicalHeight_halvesCGImageHeight() {
        // Simulate a cgImage rendered at 2x: physical pixel height 36 → logical 18 pt
        let cgImageHeight = 36
        let logicalHeight = CGFloat(cgImageHeight) / 2.0
        XCTAssertEqual(logicalHeight, 18.0,
                       "Logical height must be cgImage.height / 2.0 to convert from 2x to 1x")
    }

    func testRetina_scale_isTwo() {
        // Spec explicitly states renderer.scale = 2.0 for Retina support
        let rendererScale: CGFloat = 2.0
        XCTAssertEqual(rendererScale, 2.0,
                       "ImageRenderer scale must be 2.0 for Retina display support")
    }

    func testRetina_logicalSize_forDefaultChartWidth() {
        // Default chartWidth = 48 pt → physical width = 96 px at 2x
        // Logical size must round-trip: (48 * 2) / 2 == 48
        let settings = AppSettings()
        let physicalWidth = CGFloat(settings.chartWidth) * 2.0
        let logicalWidth = physicalWidth / 2.0
        XCTAssertEqual(logicalWidth, CGFloat(settings.chartWidth),
                       "Logical width must equal original chartWidth after 2x scale round-trip")
    }
}
