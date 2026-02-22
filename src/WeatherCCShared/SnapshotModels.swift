// meta: created=2026-02-21 updated=2026-02-21 checked=never
import Foundation

public struct UsageSnapshot: Codable {
    public let timestamp: Date
    // Actual (Phase 1)
    public let fiveHourPercent: Double?
    public let sevenDayPercent: Double?
    public let fiveHourResetsAt: Date?
    public let sevenDayResetsAt: Date?
    public let fiveHourHistory: [HistoryPoint]
    public let sevenDayHistory: [HistoryPoint]
    public let isLoggedIn: Bool
    // Predict (Phase 3)
    public let predictFiveHourCost: Double?
    public let predictSevenDayCost: Double?

    public init(
        timestamp: Date,
        fiveHourPercent: Double?,
        sevenDayPercent: Double?,
        fiveHourResetsAt: Date?,
        sevenDayResetsAt: Date?,
        fiveHourHistory: [HistoryPoint],
        sevenDayHistory: [HistoryPoint],
        isLoggedIn: Bool,
        predictFiveHourCost: Double?,
        predictSevenDayCost: Double?
    ) {
        self.timestamp = timestamp
        self.fiveHourPercent = fiveHourPercent
        self.sevenDayPercent = sevenDayPercent
        self.fiveHourResetsAt = fiveHourResetsAt
        self.sevenDayResetsAt = sevenDayResetsAt
        self.fiveHourHistory = fiveHourHistory
        self.sevenDayHistory = sevenDayHistory
        self.isLoggedIn = isLoggedIn
        self.predictFiveHourCost = predictFiveHourCost
        self.predictSevenDayCost = predictSevenDayCost
    }

    public static let placeholder = UsageSnapshot(
        timestamp: Date(),
        fiveHourPercent: 45.0,
        sevenDayPercent: 20.0,
        fiveHourResetsAt: Date().addingTimeInterval(2.5 * 3600),
        sevenDayResetsAt: Date().addingTimeInterval(3 * 24 * 3600),
        fiveHourHistory: [],
        sevenDayHistory: [],
        isLoggedIn: true,
        predictFiveHourCost: nil,
        predictSevenDayCost: nil
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
