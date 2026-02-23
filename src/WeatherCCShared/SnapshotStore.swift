// meta: created=2026-02-21 updated=2026-02-23 checked=never
import Foundation
import os

/// Shares UsageSnapshot between the main app and widget extension via App Group file.
/// Keychain is unreliable for macOS Widget extensions (sandbox restrictions).
public enum SnapshotStore {

    private static let log = Logger(subsystem: "grad13.weathercc", category: "SnapshotStore")

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func save(_ snapshot: UsageSnapshot) {
        guard let url = AppGroupConfig.snapshotURL else {
            log.error("save: App Group container not available")
            return
        }
        save(snapshot, to: url)
    }

    public static func load() -> UsageSnapshot? {
        guard let url = AppGroupConfig.snapshotURL else {
            log.error("load: App Group container not available")
            return nil
        }
        return load(from: url)
    }

    // MARK: - Testable overloads (explicit URL)

    public static func save(_ snapshot: UsageSnapshot, to url: URL) {
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
            log.info("save: \(data.count) bytes to \(url.lastPathComponent)")
        } catch {
            log.error("save: failed: \(error.localizedDescription)")
        }
    }

    public static func load(from url: URL) -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: url) else {
            log.error("load: file not found at \(url.lastPathComponent)")
            return nil
        }
        do {
            return try decoder.decode(UsageSnapshot.self, from: data)
        } catch {
            log.error("load: decode failed: \(error.localizedDescription)")
            return nil
        }
    }
}
