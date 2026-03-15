// meta: created=2026-03-04 updated=2026-03-14 checked=never
import Foundation
import os

/// Read-only access to widget snapshot data via file I/O (App Group container).
/// The main app writes via UsageViewModel.applyResult(); this type only reads.
public enum UsageReader {

    private static let log = Logger(subsystem: "grad13.claudeusagetracker", category: "UsageReader")

    /// Load a UsageSnapshot from the App Group container file.
    public static func load() -> UsageSnapshot? {
        guard let url = AppGroupConfig.snapshotURL else {
            log.warning("load: snapshotURL is nil")
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            log.warning("load: no snapshot file at \(url.path)")
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
