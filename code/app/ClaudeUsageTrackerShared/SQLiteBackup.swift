// meta: created=2026-02-24 updated=2026-03-04 checked=2026-03-03
import Foundation
import SQLite3
import os

/// Generic SQLite database backup utility.
/// Performs WAL checkpoint → date-stamped copy → old backup purge.
public enum SQLiteBackup {

    private static let log = Logger(subsystem: "grad13.claudeusagetracker", category: "SQLiteBackup")

    /// WAL checkpoint → date-stamped copy → purge old backups.
    /// - Parameters:
    ///   - dbPath: Path to the SQLite database file.
    ///   - retentionDays: Number of days to keep backups (default 3).
    public static func perform(dbPath: String, retentionDays: Int = 3) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dbPath) else { return }

        let dbURL = URL(fileURLWithPath: dbPath)
        let dir = dbURL.deletingLastPathComponent()
        let dbName = dbURL.deletingPathExtension().lastPathComponent

        // 1. Skip if today's backup already exists
        let today = dateStamp()
        let backupName = "\(dbName)-\(today).bak"
        let backupURL = dir.appendingPathComponent(backupName)
        guard !fm.fileExists(atPath: backupURL.path) else {
            log.info("perform: \(backupName) already exists, skipping")
            return
        }

        // 2. WAL checkpoint (flush WAL into main DB file)
        SQLiteHelper.withDatabase(path: dbPath) { db in
            var pnLog: Int32 = 0, pnCkpt: Int32 = 0
            let rc = sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_TRUNCATE, &pnLog, &pnCkpt)
            if rc != SQLITE_OK {
                log.warning("perform: WAL checkpoint returned \(rc)")
            }
        }

        // 3. Copy
        do {
            try fm.copyItem(at: dbURL, to: backupURL)
            log.info("perform: created \(backupName)")
        } catch {
            log.error("perform: copy failed: \(error.localizedDescription)")
            return
        }

        // 4. Purge old backups
        purge(directory: dir, dbName: dbName, retentionDays: retentionDays)
    }

    // MARK: - Private

    private static let dateStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    private static func dateStamp(from date: Date = Date()) -> String {
        dateStampFormatter.string(from: date)
    }

    /// Delete "{dbName}-YYYY-MM-DD.bak" files older than retentionDays.
    private static func purge(directory: URL, dbName: String, retentionDays: Int) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: directory.path) else { return }

        let prefix = "\(dbName)-"
        let suffix = ".bak"
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: calendar.startOfDay(for: Date())) else {
            log.error("purge: failed to compute cutoff date")
            return
        }

        for file in files {
            guard file.hasPrefix(prefix), file.hasSuffix(suffix) else { continue }
            let dateStr = String(file.dropFirst(prefix.count).dropLast(suffix.count))
            guard let fileDate = dateStampFormatter.date(from: dateStr) else { continue }
            if fileDate < cutoff {
                let url = directory.appendingPathComponent(file)
                try? fm.removeItem(at: url)
                log.info("purge: deleted \(file)")
            }
        }
    }
}
