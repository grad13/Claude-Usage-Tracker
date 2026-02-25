// meta: created=2026-02-21 updated=2026-02-24 checked=never
import Foundation

public enum AppGroupConfig {
    public static let groupId = "C3WA2TT222.grad13.weathercc"
    public static let appName = "WeatherCC"

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId)
    }

    /// SQLite DB path for SnapshotStore (new).
    /// Returns String (not URL) because SQLite3 C API requires a path string.
    public static var snapshotDBPath: String? {
        guard let container = containerURL else { return nil }
        let dir = container
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
        return dir.appendingPathComponent("snapshot.db").path
    }

    /// Legacy JSON file URL — used only for migration.
    /// After migration, the file is renamed to snapshot.json.bak.
    public static var legacySnapshotURL: URL? {
        guard let container = containerURL else { return nil }
        let dir = container
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
        return dir.appendingPathComponent("snapshot.json")
    }
}
