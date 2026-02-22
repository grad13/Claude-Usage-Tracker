// meta: created=2026-02-21 updated=2026-02-21 checked=never
import Foundation

public enum AppGroupConfig {
    public static let groupId = "group.grad13.weathercc"
    public static let appName = "WeatherCC"

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId)
    }

    public static var snapshotURL: URL? {
        guard let container = containerURL else { return nil }
        let dir = container
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
        return dir.appendingPathComponent("snapshot.json")
    }
}
