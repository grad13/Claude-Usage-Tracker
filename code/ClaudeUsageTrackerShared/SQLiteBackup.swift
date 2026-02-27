// meta: created=2026-02-24 updated=2026-02-24 checked=never
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
        var db: OpaquePointer?
        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
            sqlite3_close(db)
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

    private static func dateStamp(from date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: date)
    }

    /// Delete "{dbName}-YYYY-MM-DD.bak" files older than retentionDays.
    private static func purge(directory: URL, dbName: String, retentionDays: Int) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: directory.path) else { return }

        let prefix = "\(dbName)-"
        let suffix = ".bak"
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: calendar.startOfDay(for: Date()))!

        let dateParser = DateFormatter()
        dateParser.dateFormat = "yyyy-MM-dd"
        dateParser.timeZone = .current

        for file in files {
            guard file.hasPrefix(prefix), file.hasSuffix(suffix) else { continue }
            let dateStr = String(file.dropFirst(prefix.count).dropLast(suffix.count))
            guard let fileDate = dateParser.date(from: dateStr) else { continue }
            if fileDate < cutoff {
                let url = directory.appendingPathComponent(file)
                try? fm.removeItem(at: url)
                log.info("purge: deleted \(file)")
            }
        }
    }
}
