// meta: created=2026-02-21 updated=2026-03-15 checked=2026-03-03
import Foundation

public enum AppGroupConfig {
    public static let groupId = "group.grad13.claudeusagetracker"
    public static let appName = "ClaudeUsageTracker"

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId)
    }

    /// Read a string value from settings.json in the App Group container.
    public static func settingsString(forKey key: String) -> String? {
        guard let container = containerURL else { return nil }
        let settingsURL = container
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict[key] as? String
    }

    /// Read an integer value from settings.json in the App Group container.
    public static func settingsInt(forKey key: String) -> Int? {
        guard let container = containerURL else { return nil }
        let settingsURL = container
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict[key] as? Int
    }

    /// JSON file URL for widget snapshot (shared between app and widget).
    /// Located in the same directory as usage.db.
    public static var snapshotURL: URL? {
        guard let container = containerURL else { return nil }
        return container
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("widget-snapshot.json")
    }

    /// SQLite DB path for UsageStore (shared between app and widget).
    /// Returns String (not URL) because SQLite3 C API requires a path string.
    public static var usageDBPath: String? {
        guard let container = containerURL else { return nil }
        let dir = container
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
        return dir.appendingPathComponent("usage.db").path
    }

}
