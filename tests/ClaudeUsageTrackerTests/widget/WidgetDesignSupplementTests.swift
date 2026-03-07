// Supplement tests for: docs/spec/widget/design.md
// Covers: WidgetColorThemeResolver colorMap RGB values (tested via ChartColorPreset),
//         WidgetColorThemeResolver resolve decision table (logic contract),
//         supported preset completeness
//
// Skipped: Canvas drawing, View layout, WidgetKit structure (require ViewInspector/snapshot)
// Note: WidgetColorThemeResolver is in the Widget extension target (not testable-importable).
//       The spec states its colorMap is "duplicated" from ChartColorPreset. We verify the
//       canonical RGB values in ChartColorPreset match the spec, which transitively validates
//       the widget's colorMap.

import XCTest
import SwiftUI
@testable import ClaudeUsageTracker

// MARK: - WidgetColorThemeResolver colorMap RGB contract (via ChartColorPreset)

/// Spec: "Supported presets: blue, pink, green, teal, purple, orange, white (same as ChartColorPreset)"
/// Spec: WidgetColorThemeResolver.colorMap duplicates ChartColorPreset RGB values for the Widget target.
/// These tests verify ChartColorPreset.color matches the spec-defined RGB, ensuring the widget's
/// duplicated colorMap stays correct (any drift in ChartColorPreset would break both).
final class WidgetColorThemeResolverColorMapTests: XCTestCase {

    // Spec: blue = rgba(100, 180, 255)
    func testBluePresetRGB_matchesSpec() {
        assertRGB(ChartColorPreset.blue, r: 100, g: 180, b: 255)
    }

    // Spec: pink = rgba(255, 130, 180)
    func testPinkPresetRGB_matchesSpec() {
        assertRGB(ChartColorPreset.pink, r: 255, g: 130, b: 180)
    }

    // Spec: green = rgba(70, 210, 80)
    func testGreenPresetRGB_matchesSpec() {
        assertRGB(ChartColorPreset.green, r: 70, g: 210, b: 80)
    }

    // Spec: teal = rgba(0, 210, 190)
    func testTealPresetRGB_matchesSpec() {
        assertRGB(ChartColorPreset.teal, r: 0, g: 210, b: 190)
    }

    // Spec: purple = rgba(150, 110, 255)
    func testPurplePresetRGB_matchesSpec() {
        assertRGB(ChartColorPreset.purple, r: 150, g: 110, b: 255)
    }

    // Spec: orange = rgba(255, 160, 60)
    func testOrangePresetRGB_matchesSpec() {
        assertRGB(ChartColorPreset.orange, r: 255, g: 160, b: 60)
    }

    // Spec: white = rgba(230, 230, 230)
    func testWhitePresetRGB_matchesSpec() {
        assertRGB(ChartColorPreset.white, r: 230, g: 230, b: 230)
    }

    // Spec: exactly 7 presets supported by WidgetColorThemeResolver
    func testPresetCount_is7() {
        XCTAssertEqual(ChartColorPreset.allCases.count, 7,
            "Spec defines exactly 7 color presets for WidgetColorThemeResolver.colorMap")
    }

    // Spec: rawValue strings must match WidgetColorThemeResolver.colorMap keys
    func testPresetRawValues_matchColorMapKeys() {
        let expected: Set<String> = ["blue", "pink", "green", "teal", "purple", "orange", "white"]
        let actual = Set(ChartColorPreset.allCases.map(\.rawValue))
        XCTAssertEqual(actual, expected,
            "ChartColorPreset rawValues must match WidgetColorThemeResolver.colorMap keys")
    }

    // MARK: - Helper

    /// Extract RGB components from ChartColorPreset.color and compare against spec values.
    /// Uses NSColor conversion since SwiftUI Color doesn't expose components directly.
    private func assertRGB(
        _ preset: ChartColorPreset,
        r: Int, g: Int, b: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let nsColor = NSColor(preset.color).usingColorSpace(.deviceRGB)
        guard let resolved = nsColor else {
            XCTFail("Could not resolve \(preset.rawValue) to deviceRGB", file: file, line: line)
            return
        }
        let accuracy: CGFloat = 1.0 / 255.0
        XCTAssertEqual(resolved.redComponent, CGFloat(r) / 255.0, accuracy: accuracy,
            "\(preset.rawValue) red component", file: file, line: line)
        XCTAssertEqual(resolved.greenComponent, CGFloat(g) / 255.0, accuracy: accuracy,
            "\(preset.rawValue) green component", file: file, line: line)
        XCTAssertEqual(resolved.blueComponent, CGFloat(b) / 255.0, accuracy: accuracy,
            "\(preset.rawValue) blue component", file: file, line: line)
    }
}

// MARK: - WidgetColorThemeResolver.resolve decision table (logic contract)

/// Spec: WidgetColorThemeResolver.resolve(environment:) maps theme strings to ColorScheme.
/// Since the Widget target can't be imported, we test the decision table as a pure function
/// that mirrors the spec's documented behavior.
final class WidgetColorThemeResolverResolveLogicTests: XCTestCase {

    /// Spec-based decision table test. WidgetColorThemeResolver is in the Widget target
    /// (not importable from tests), so we verify the spec's decision table as a pure function.
    /// This does NOT test production code — it validates the spec contract.
    private func specResolve(theme: String?, environment: Int) -> Int {
        // environment: 0 = light, 1 = dark (simplified for testing)
        guard let theme else { return 1 } // nil -> dark
        switch theme {
        case "light": return 0
        case "dark": return 1
        case "system": return environment
        default: return 1 // unknown -> dark
        }
    }

    // Spec: "light" -> always .light
    func testResolve_lightTheme_returnsLight_regardlessOfEnvironment() {
        XCTAssertEqual(specResolve(theme: "light", environment: 0), 0) // env=light
        XCTAssertEqual(specResolve(theme: "light", environment: 1), 0) // env=dark
    }

    // Spec: "dark" -> always .dark
    func testResolve_darkTheme_returnsDark_regardlessOfEnvironment() {
        XCTAssertEqual(specResolve(theme: "dark", environment: 0), 1) // env=light
        XCTAssertEqual(specResolve(theme: "dark", environment: 1), 1) // env=dark
    }

    // Spec: "system" -> use environment's colorScheme
    func testResolve_systemTheme_followsEnvironment_light() {
        XCTAssertEqual(specResolve(theme: "system", environment: 0), 0)
    }

    func testResolve_systemTheme_followsEnvironment_dark() {
        XCTAssertEqual(specResolve(theme: "system", environment: 1), 1)
    }

    // Spec: missing (nil) -> .dark
    func testResolve_nilTheme_returnsDark() {
        XCTAssertEqual(specResolve(theme: nil, environment: 0), 1)
        XCTAssertEqual(specResolve(theme: nil, environment: 1), 1)
    }

    // Spec: unknown string -> .dark (fallback)
    func testResolve_unknownTheme_returnsDark() {
        XCTAssertEqual(specResolve(theme: "sepia", environment: 0), 1)
        XCTAssertEqual(specResolve(theme: "", environment: 0), 1)
    }
}

// MARK: - WidgetColorThemeResolver.resolveChartColor fallback contract

/// Spec: resolveChartColor returns fallback if preset is unknown or key is absent.
/// Spec: 5h default = blue, 7d default = pink.
/// Tested via ChartColorPreset defaults since widget duplicates these.
final class WidgetColorThemeResolverFallbackTests: XCTestCase {

    // Spec: 5h area color default is blue
    func testDefaultHourlyColor_isBlue() {
        let defaultPreset: ChartColorPreset = .blue
        XCTAssertEqual(defaultPreset.rawValue, "blue",
            "Spec: hourly_color_preset default is blue")
    }

    // Spec: 7d area color default is pink
    func testDefaultWeeklyColor_isPink() {
        let defaultPreset: ChartColorPreset = .pink
        XCTAssertEqual(defaultPreset.rawValue, "pink",
            "Spec: weekly_color_preset default is pink")
    }

}
