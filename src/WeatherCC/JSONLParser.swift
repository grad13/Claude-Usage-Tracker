// meta: created=2026-02-21 updated=2026-02-21 checked=never
import Foundation

struct TokenRecord {
    let timestamp: Date
    let requestId: String
    let model: String
    let speed: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
    let webSearchRequests: Int
}

enum JSONLParser {

    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let dateFormatterNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Public

    /// Parse all JSONL files in a directory.
    /// - Parameter maxAge: Skip files older than this interval (nil = no filter)
    static func parseDirectory(_ directory: URL, maxAge: TimeInterval? = nil) -> [TokenRecord] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let cutoff: Date? = maxAge.map { Date().addingTimeInterval(-$0) }
        var allRecords: [TokenRecord] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }
            if let cutoff,
               let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
               let modDate = values.contentModificationDate,
               modDate < cutoff {
                continue
            }
            let records = parseFile(fileURL)
            allRecords.append(contentsOf: records)
        }

        return deduplicate(allRecords)
    }

    static func parseLines(_ lines: [String]) -> [TokenRecord] {
        var records: [TokenRecord] = []
        for line in lines {
            if let record = parseLine(line) {
                records.append(record)
            }
        }
        return deduplicate(records)
    }

    // MARK: - File Parsing

    static func parseFile(_ url: URL) -> [TokenRecord] {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else { return [] }

        var records: [TokenRecord] = []
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let record = parseLine(trimmed) {
                records.append(record)
            }
        }
        return records
    }

    // MARK: - Line Parsing

    private static func parseLine(_ line: String) -> TokenRecord? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        guard json["type"] as? String == "assistant" else { return nil }
        guard let requestId = json["requestId"] as? String else { return nil }
        guard let message = json["message"] as? [String: Any] else { return nil }
        guard let usage = message["usage"] as? [String: Any] else { return nil }

        guard let timestamp = parseTimestamp(json["timestamp"] as? String) else { return nil }
        let model = message["model"] as? String ?? "unknown"

        return TokenRecord(
            timestamp: timestamp,
            requestId: requestId,
            model: model,
            speed: usage["speed"] as? String ?? "standard",
            inputTokens: usage["input_tokens"] as? Int ?? 0,
            outputTokens: usage["output_tokens"] as? Int ?? 0,
            cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0,
            cacheCreationTokens: usage["cache_creation_input_tokens"] as? Int ?? 0,
            webSearchRequests: (usage["server_tool_use"] as? [String: Any])?["web_search_requests"] as? Int ?? 0
        )
    }

    private static func parseTimestamp(_ string: String?) -> Date? {
        guard let string else { return nil }
        return dateFormatter.date(from: string) ?? dateFormatterNoFraction.date(from: string)
    }

    // MARK: - Deduplication

    private static func deduplicate(_ records: [TokenRecord]) -> [TokenRecord] {
        var bestByRequestId: [String: TokenRecord] = [:]

        for record in records {
            if let existing = bestByRequestId[record.requestId] {
                if record.outputTokens >= existing.outputTokens {
                    bestByRequestId[record.requestId] = record
                }
            } else {
                bestByRequestId[record.requestId] = record
            }
        }

        return Array(bestByRequestId.values).sorted { $0.timestamp < $1.timestamp }
    }
}
