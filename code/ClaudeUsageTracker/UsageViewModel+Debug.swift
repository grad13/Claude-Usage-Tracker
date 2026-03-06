// meta: created=2026-03-06 updated=2026-03-06 checked=-
import Foundation

extension UsageViewModel {
    static let logURL: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeUsageTracker-debug.log")
        // Clear log on launch
        try? "".write(to: url, atomically: true, encoding: .utf8)
        return url
    }()

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
