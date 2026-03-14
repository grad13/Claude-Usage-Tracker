// meta: created=2026-03-04 updated=2026-03-14 checked=never
import Foundation
import os

/// Read-only access to widget snapshot data via UserDefaults (App Group).
/// The main app writes via UsageViewModel.applyResult(); this type only reads.
public enum UsageReader {

    private static let log = Logger(subsystem: "grad13.claudeusagetracker", category: "UsageReader")

    public static let snapshotKey = "widgetSnapshot"

    /// Load a UsageSnapshot from UserDefaults for widget display.
    public static func load() -> UsageSnapshot? {
        guard let defaults = AppGroupConfig.sharedDefaults else {
            log.warning("load: sharedDefaults is nil")
            return nil
        }
        guard let data = defaults.data(forKey: snapshotKey) else {
            log.warning("load: no snapshot data in UserDefaults")
            return nil
        }
        do {
            let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: data)
            log.info("load: 5h=\(snapshot.fiveHourPercent ?? -1) 7d=\(snapshot.sevenDayPercent ?? -1) loggedIn=\(snapshot.isLoggedIn)")
            return snapshot
        } catch {
            log.error("load: decode error: \(error.localizedDescription)")
            return nil
        }
    }
}
