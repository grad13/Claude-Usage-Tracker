// meta: updated=2026-04-25 05:00 checked=-
import Foundation

public struct UsageSnapshot: Codable {
    public let timestamp: Date
    public let fiveHourPercent: Double?
    public let sevenDayPercent: Double?
    public let fiveHourResetsAt: Date?
    public let sevenDayResetsAt: Date?
    /// Start of the current weekly session. When non-nil the 7d chart uses
    /// [sevenDayStartedAt, sevenDayResetsAt] as its window bounds, avoiding
    /// cross-session rendering. Nil when no session exists yet (graceful
    /// fallback to legacy `resetsAt - 7d` behavior).
    public let sevenDayStartedAt: Date?
    public let fiveHourHistory: [HistoryPoint]
    public let sevenDayHistory: [HistoryPoint]
    public let isLoggedIn: Bool

    public init(
        timestamp: Date,
        fiveHourPercent: Double?,
        sevenDayPercent: Double?,
        fiveHourResetsAt: Date?,
        sevenDayResetsAt: Date?,
        sevenDayStartedAt: Date? = nil,
        fiveHourHistory: [HistoryPoint],
        sevenDayHistory: [HistoryPoint],
        isLoggedIn: Bool
    ) {
        self.timestamp = timestamp
        self.fiveHourPercent = fiveHourPercent
        self.sevenDayPercent = sevenDayPercent
        self.fiveHourResetsAt = fiveHourResetsAt
        self.sevenDayResetsAt = sevenDayResetsAt
        self.sevenDayStartedAt = sevenDayStartedAt
        self.fiveHourHistory = fiveHourHistory
        self.sevenDayHistory = sevenDayHistory
        self.isLoggedIn = isLoggedIn
    }

    public static let placeholder = UsageSnapshot(
        timestamp: Date(),
        fiveHourPercent: 45.0,
        sevenDayPercent: 20.0,
        fiveHourResetsAt: Date().addingTimeInterval(2.5 * 3600),
        sevenDayResetsAt: Date().addingTimeInterval(3 * 24 * 3600),
        sevenDayStartedAt: Date().addingTimeInterval(-4 * 24 * 3600),
        fiveHourHistory: [],
        sevenDayHistory: [],
        isLoggedIn: true
    )
}

public struct HistoryPoint: Codable {
    public let timestamp: Date
    public let percent: Double

    public init(timestamp: Date, percent: Double) {
        self.timestamp = timestamp
        self.percent = percent
    }
}
