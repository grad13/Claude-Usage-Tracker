// meta: created=2026-03-07 updated=2026-03-07 checked=never
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
}
