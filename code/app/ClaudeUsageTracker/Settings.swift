// meta: updated=2026-03-16 06:52 checked=2026-03-03 00:00
import Foundation
import SwiftUI
import ClaudeUsageTrackerShared

// MARK: - Chart Color Preset

enum ChartColorPreset: String, CaseIterable, Codable {
    case blue   = "blue"
    case pink   = "pink"
    case green  = "green"
    case teal   = "teal"
    case purple = "purple"
    case orange = "orange"
    case white  = "white"

    var color: Color {
        switch self {
        case .blue:   return Color(red: 100/255, green: 180/255, blue: 255/255)
        case .pink:   return Color(red: 255/255, green: 130/255, blue: 180/255)
        case .green:  return Color(red: 70/255, green: 210/255, blue: 80/255)
        case .teal:   return Color(red: 0/255, green: 210/255, blue: 190/255)
        case .purple: return Color(red: 150/255, green: 110/255, blue: 255/255)
        case .orange: return Color(red: 255/255, green: 160/255, blue: 60/255)
        case .white:  return Color(red: 230/255, green: 230/255, blue: 230/255)
        }
    }

    var displayName: String {
        switch self {
        case .blue:   return "Blue"
        case .pink:   return "Pink"
        case .green:  return "Green"
        case .teal:   return "Teal"
        case .purple: return "Purple"
        case .orange: return "Orange"
        case .white:  return "White"
        }
    }

    var hexString: String {
        let (r, g, b): (Int, Int, Int) = {
            switch self {
            case .blue:   return (100, 180, 255)
            case .pink:   return (255, 130, 180)
            case .green:  return (70, 210, 80)
            case .teal:   return (0, 210, 190)
            case .purple: return (150, 110, 255)
            case .orange: return (255, 160, 60)
            case .white:  return (230, 230, 230)
            }
        }()
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}

// MARK: - Graph Color Theme

enum GraphColorTheme: String, Codable, CaseIterable {
    case system = "system"
    case light  = "light"
    case dark   = "dark"

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    func resolvedColorScheme() -> ColorScheme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system:
            let appearance = NSApp.effectiveAppearance
            return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        }
    }
}

// MARK: - Daily Alert Definition

enum DailyAlertDefinition: String, Codable, CaseIterable {
    case calendar = "calendar"  // Local timezone midnight boundary
    case session = "session"    // Weekly session boundary (resets_at based)
}

// MARK: - App Settings

struct AppSettings: Codable {
    // Default values
    static let defaultRefreshInterval = 5
    static let defaultChartWidth = 48
    static let defaultWeeklyAlertThreshold = 20
    static let defaultHourlyAlertThreshold = 20
    static let defaultDailyAlertThreshold = 15

    // Validation bounds
    static let minChartWidth = 12
    static let maxChartWidth = 120

    var refreshIntervalMinutes: Int = defaultRefreshInterval
    var startAtLogin: Bool = false
    var showHourlyGraph: Bool = true
    var showWeeklyGraph: Bool = true
    var chartWidth: Int = defaultChartWidth
    var hourlyColorPreset: ChartColorPreset = .blue
    var weeklyColorPreset: ChartColorPreset = .pink
    var graphColorTheme: GraphColorTheme = .dark

    // Alert settings
    var weeklyAlertEnabled: Bool = false
    var weeklyAlertThreshold: Int = defaultWeeklyAlertThreshold
    var hourlyAlertEnabled: Bool = false
    var hourlyAlertThreshold: Int = defaultHourlyAlertThreshold
    var dailyAlertEnabled: Bool = false
    var dailyAlertThreshold: Int = defaultDailyAlertThreshold
    var dailyAlertDefinition: DailyAlertDefinition = .calendar

    static let presets = [1, 2, 3, 5, 10, 20, 60]
    static let chartWidthPresets = [12, 24, 36, 48, 60, 72]

    /// Handle missing keys gracefully (e.g., upgrading from older settings files)
    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        refreshIntervalMinutes = try container.decodeIfPresent(Int.self, forKey: .refreshIntervalMinutes) ?? Self.defaultRefreshInterval
        startAtLogin = try container.decodeIfPresent(Bool.self, forKey: .startAtLogin) ?? false
        showHourlyGraph = try container.decodeIfPresent(Bool.self, forKey: .showHourlyGraph) ?? true
        showWeeklyGraph = try container.decodeIfPresent(Bool.self, forKey: .showWeeklyGraph) ?? true
        chartWidth = try container.decodeIfPresent(Int.self, forKey: .chartWidth) ?? Self.defaultChartWidth
        hourlyColorPreset = try container.decodeIfPresent(ChartColorPreset.self, forKey: .hourlyColorPreset) ?? .blue
        weeklyColorPreset = try container.decodeIfPresent(ChartColorPreset.self, forKey: .weeklyColorPreset) ?? .pink
        graphColorTheme = try container.decodeIfPresent(GraphColorTheme.self, forKey: .graphColorTheme) ?? .dark
        weeklyAlertEnabled = try container.decodeIfPresent(Bool.self, forKey: .weeklyAlertEnabled) ?? false
        weeklyAlertThreshold = try container.decodeIfPresent(Int.self, forKey: .weeklyAlertThreshold) ?? Self.defaultWeeklyAlertThreshold
        hourlyAlertEnabled = try container.decodeIfPresent(Bool.self, forKey: .hourlyAlertEnabled) ?? false
        hourlyAlertThreshold = try container.decodeIfPresent(Int.self, forKey: .hourlyAlertThreshold) ?? Self.defaultHourlyAlertThreshold
        dailyAlertEnabled = try container.decodeIfPresent(Bool.self, forKey: .dailyAlertEnabled) ?? false
        dailyAlertThreshold = try container.decodeIfPresent(Int.self, forKey: .dailyAlertThreshold) ?? Self.defaultDailyAlertThreshold
        dailyAlertDefinition = try container.decodeIfPresent(DailyAlertDefinition.self, forKey: .dailyAlertDefinition) ?? .calendar
    }

    init() {}

    /// Validate and return a corrected copy. Negative values reset to default.
    func validated() -> AppSettings {
        var copy = self
        if copy.refreshIntervalMinutes < 0 {
            copy.refreshIntervalMinutes = Self.defaultRefreshInterval
        }
        if copy.chartWidth < Self.minChartWidth || copy.chartWidth > Self.maxChartWidth {
            copy.chartWidth = Self.defaultChartWidth
        }
        copy.weeklyAlertThreshold = max(1, min(100, copy.weeklyAlertThreshold))
        copy.hourlyAlertThreshold = max(1, min(100, copy.hourlyAlertThreshold))
        copy.dailyAlertThreshold = max(1, min(100, copy.dailyAlertThreshold))
        return copy
    }
}

final class SettingsStore {

    let fileURL: URL
    private let dirURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.dirURL = fileURL.deletingLastPathComponent()
    }

    static let shared: SettingsStore = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            let tmpDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("ClaudeUsageTracker-test-shared")
            try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            return SettingsStore(fileURL: tmpDir.appendingPathComponent("settings.json"))
        }
        #endif
        guard let container = AppGroupConfig.containerURL else {
            fatalError("[SettingsStore] App Group container not available")
        }
        let dir = container
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(AppGroupConfig.appName, isDirectory: true)
        return SettingsStore(fileURL: dir.appendingPathComponent("settings.json"))
    }()

    // MARK: - Static convenience (delegates to shared)

    static func load() -> AppSettings { shared.load() }
    static func save(_ settings: AppSettings) { shared.save(settings) }

    // MARK: - Instance Methods

    func load() -> AppSettings {
        ensureDirectory()

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let defaults = AppSettings()
            save(defaults)
            return defaults
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let settings = try decoder.decode(AppSettings.self, from: data)
            return settings.validated()
        } catch {
            NSLog("[ClaudeUsageTracker] Settings parse error, using defaults: %@", "\(error)")
            let bakURL = fileURL.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: bakURL)
            try? FileManager.default.moveItem(at: fileURL, to: bakURL)
            let defaults = AppSettings()
            save(defaults)
            return defaults
        }
    }

    func save(_ settings: AppSettings) {
        ensureDirectory()

        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[ClaudeUsageTracker] Settings save error: %@", "\(error)")
        }
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
    }
}
