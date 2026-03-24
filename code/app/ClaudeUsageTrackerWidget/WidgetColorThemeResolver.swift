// meta: updated=2026-03-16 06:52 checked=-
import SwiftUI
import ClaudeUsageTrackerShared

enum WidgetColorThemeResolver {
    /// Resolve the effective ColorScheme based on the graph_color_theme setting.
    /// - "light" → always .light
    /// - "dark" → always .dark
    /// - "system" or missing → use the environment's colorScheme
    static func resolve(environment: ColorScheme) -> ColorScheme {
        guard let theme = AppGroupConfig.settingsString(forKey: "graph_color_theme") else {
            return .dark
        }
        switch theme {
        case "light": return .light
        case "dark": return .dark
        case "system": return environment
        default: return .dark
        }
    }

    /// Resolve chart color from settings.json color preset.
    /// Returns fallback if the key is missing or the preset name is unknown.
    static func resolveChartColor(forKey key: String, default fallback: Color) -> Color {
        guard let preset = AppGroupConfig.settingsString(forKey: key),
              let rgb = colorMap[preset] else {
            return fallback
        }
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    private static let colorMap: [String: (r: Double, g: Double, b: Double)] = [
        "blue":   (100/255, 180/255, 255/255),
        "pink":   (255/255, 130/255, 180/255),
        "green":  (70/255,  210/255, 80/255),
        "teal":   (0/255,   210/255, 190/255),
        "purple": (150/255, 110/255, 255/255),
        "orange": (255/255, 160/255, 60/255),
        "white":  (230/255, 230/255, 230/255),
    ]
}
