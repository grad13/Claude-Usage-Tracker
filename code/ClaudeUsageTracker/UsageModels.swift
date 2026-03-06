// meta: created=2026-03-06 updated=2026-03-06 checked=-
import Foundation

struct UsageResult {
    var fiveHourPercent: Double?
    var sevenDayPercent: Double?
    var fiveHourResetsAt: Date?
    var sevenDayResetsAt: Date?
    var fiveHourStatus: Int?       // 0=within_limit, 1=approaching_limit, 2=exceeded_limit
    var sevenDayStatus: Int?
    var fiveHourLimit: Double?
    var fiveHourRemaining: Double?
    var sevenDayLimit: Double?
    var sevenDayRemaining: Double?
    var rawJSON: String?
}

enum UsageFetchError: LocalizedError {
    case scriptFailed(String)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .scriptFailed(let msg):
            if msg.lowercased().contains("missing organization") {
                return "Session expired. Please sign in again."
            }
            if msg.lowercased().contains("http 401") || msg.lowercased().contains("http 403") {
                return "Access denied. Please sign in again."
            }
            return msg
        case .decodingFailed: return "Failed to decode usage data"
        }
    }

    /// Raw diagnostic message for logging (not shown to user)
    var diagnosticMessage: String {
        switch self {
        case .scriptFailed(let msg): return msg
        case .decodingFailed: return "decodingFailed"
        }
    }

    /// Whether this error indicates an authentication problem
    var isAuthError: Bool {
        switch self {
        case .scriptFailed(let msg):
            let lower = msg.lowercased()
            return lower.contains("missing organization")
                || lower.contains("http 401")
                || lower.contains("http 403")
        case .decodingFailed:
            return false
        }
    }
}
