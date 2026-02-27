// meta: created=2026-02-21 updated=2026-02-27 checked=never
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
}

// MARK: - Daily Alert Definition

enum DailyAlertDefinition: String, Codable, CaseIterable {
    case calendar = "calendar"  // Local timezone midnight boundary
    case session = "session"    // Weekly session boundary (resets_at based)
}

// MARK: - App Settings

struct AppSettings: Codable {
    var refreshIntervalMinutes: Int = 5
    var startAtLogin: Bool = false
    var showHourlyGraph: Bool = true
    var showWeeklyGraph: Bool = true
    var chartWidth: Int = 48
    var hourlyColorPreset: ChartColorPreset = .blue
    var weeklyColorPreset: ChartColorPreset = .pink

    // Alert settings
    var weeklyAlertEnabled: Bool = false
    var weeklyAlertThreshold: Int = 20   // Notify when remaining % <= threshold
    var hourlyAlertEnabled: Bool = false
    var hourlyAlertThreshold: Int = 20   // Notify when remaining % <= threshold
    var dailyAlertEnabled: Bool = false
    var dailyAlertThreshold: Int = 15    // Notify when daily usage % >= threshold
    var dailyAlertDefinition: DailyAlertDefinition = .calendar

    static let presets = [1, 2, 3, 5, 10, 20, 60]
    static let chartWidthPresets = [12, 24, 36, 48, 60, 72]

    /// Handle missing keys gracefully (e.g., upgrading from older settings files)
    init(from decoder: Decoder) throws {
        let defaults = AppSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        refreshIntervalMinutes = try container.decodeIfPresent(Int.self, forKey: .refreshIntervalMinutes) ?? defaults.refreshIntervalMinutes
        startAtLogin = try container.decodeIfPresent(Bool.self, forKey: .startAtLogin) ?? defaults.startAtLogin
        showHourlyGraph = try container.decodeIfPresent(Bool.self, forKey: .showHourlyGraph) ?? defaults.showHourlyGraph
        showWeeklyGraph = try container.decodeIfPresent(Bool.self, forKey: .showWeeklyGraph) ?? defaults.showWeeklyGraph
        chartWidth = try container.decodeIfPresent(Int.self, forKey: .chartWidth) ?? defaults.chartWidth
        hourlyColorPreset = try container.decodeIfPresent(ChartColorPreset.self, forKey: .hourlyColorPreset) ?? defaults.hourlyColorPreset
        weeklyColorPreset = try container.decodeIfPresent(ChartColorPreset.self, forKey: .weeklyColorPreset) ?? defaults.weeklyColorPreset
        weeklyAlertEnabled = try container.decodeIfPresent(Bool.self, forKey: .weeklyAlertEnabled) ?? defaults.weeklyAlertEnabled
        weeklyAlertThreshold = try container.decodeIfPresent(Int.self, forKey: .weeklyAlertThreshold) ?? defaults.weeklyAlertThreshold
        hourlyAlertEnabled = try container.decodeIfPresent(Bool.self, forKey: .hourlyAlertEnabled) ?? defaults.hourlyAlertEnabled
        hourlyAlertThreshold = try container.decodeIfPresent(Int.self, forKey: .hourlyAlertThreshold) ?? defaults.hourlyAlertThreshold
        dailyAlertEnabled = try container.decodeIfPresent(Bool.self, forKey: .dailyAlertEnabled) ?? defaults.dailyAlertEnabled
        dailyAlertThreshold = try container.decodeIfPresent(Int.self, forKey: .dailyAlertThreshold) ?? defaults.dailyAlertThreshold
        dailyAlertDefinition = try container.decodeIfPresent(DailyAlertDefinition.self, forKey: .dailyAlertDefinition) ?? defaults.dailyAlertDefinition
    }

    init() {}

    /// Validate and return a corrected copy. Negative values reset to default.
    func validated() -> AppSettings {
        var copy = self
        if copy.refreshIntervalMinutes < 0 {
            copy.refreshIntervalMinutes = AppSettings().refreshIntervalMinutes
        }
        if copy.chartWidth < 12 || copy.chartWidth > 120 {
            copy.chartWidth = AppSettings().chartWidth
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
            print("[Settings] Parse error, using defaults: \(error)")
            return AppSettings()
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
            print("[Settings] Failed to save: \(error)")
        }
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
    }
}
