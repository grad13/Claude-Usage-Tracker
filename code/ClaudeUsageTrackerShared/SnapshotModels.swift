// meta: created=2026-02-21 updated=2026-03-06 checked=2026-03-03
import Foundation

public struct UsageSnapshot: Codable {
    public let timestamp: Date
    public let fiveHourPercent: Double?
    public let sevenDayPercent: Double?
    public let fiveHourResetsAt: Date?
    public let sevenDayResetsAt: Date?
    public let fiveHourHistory: [HistoryPoint]
    public let sevenDayHistory: [HistoryPoint]
    public let isLoggedIn: Bool

    public init(
        timestamp: Date,
        fiveHourPercent: Double?,
        sevenDayPercent: Double?,
        fiveHourResetsAt: Date?,
        sevenDayResetsAt: Date?,
        fiveHourHistory: [HistoryPoint],
        sevenDayHistory: [HistoryPoint],
        isLoggedIn: Bool
    ) {
        self.timestamp = timestamp
        self.fiveHourPercent = fiveHourPercent
        self.sevenDayPercent = sevenDayPercent
        self.fiveHourResetsAt = fiveHourResetsAt
        self.sevenDayResetsAt = sevenDayResetsAt
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
