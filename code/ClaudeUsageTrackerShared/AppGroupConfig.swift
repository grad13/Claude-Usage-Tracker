// meta: created=2026-02-21 updated=2026-02-24 checked=2026-03-03
import Foundation

public enum AppGroupConfig {
    public static let groupId = "group.grad13.claudeusagetracker"
    public static let appName = "ClaudeUsageTracker"

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId)
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
