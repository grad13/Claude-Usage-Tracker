// meta: updated=2026-04-09 21:45 checked=-
import Foundation
import ClaudeUsageTrackerShared

extension UsageViewModel {
    static let logURL: URL = {
        // Use App Group container so logs survive PC restart (unlike /tmp or /var/folders)
        if let container = AppGroupConfig.containerURL {
            let dir = container
                .appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent(AppGroupConfig.appName, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("debug.log")
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeUsageTracker-debug.log")
    }()

    /// Write a launch separator (not clearing old logs) so we can compare across restarts.
    static func markLaunch() {
        let separator = "\n========== LAUNCH \(ISO8601DateFormatter().string(from: Date())) ==========\n"
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(separator.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? separator.write(to: logURL, atomically: false, encoding: .utf8)
        }
    }

    func debug(_ message: String) {
        NSLog("[ClaudeUsageTracker] %@", message)
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: Self.logURL) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? line.write(to: Self.logURL, atomically: false, encoding: .utf8)
        }
    }
}
