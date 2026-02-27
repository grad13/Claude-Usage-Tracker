import XCTest
@testable import WeatherCC

/// Tests for AlertChecker Weekly/Hourly alert logic.
/// Decision table: spec/data/alert.md sections 3.1 and 3.2.
final class AlertCheckerTests: XCTestCase {

    private var mockSender: MockNotificationSender!
    private var mockStore: InMemoryUsageStore!
    private var checker: AlertChecker!

    private let epochA = Date(timeIntervalSince1970: 1740405600) // 2025-02-24 14:00:00 UTC (normalized)
    private let epochB = Date(timeIntervalSince1970: 1740420000) // 2025-02-24 18:00:00 UTC (normalized)

    override func setUp() {
        super.setUp()
        mockSender = MockNotificationSender()
        mockStore = InMemoryUsageStore()
        checker = AlertChecker(notificationSender: mockSender, usageStore: mockStore)
    }

    private func makeResult(
        fiveHourPercent: Double? = nil,
        sevenDayPercent: Double? = nil,
        fiveHourResetsAt: Date? = nil,
        sevenDayResetsAt: Date? = nil
    ) -> UsageResult {
        var r = UsageResult()
        r.fiveHourPercent = fiveHourPercent
        r.sevenDayPercent = sevenDayPercent
        r.fiveHourResetsAt = fiveHourResetsAt
        r.sevenDayResetsAt = sevenDayResetsAt
        return r
    }

    private func makeSettings(
        weeklyEnabled: Bool = false, weeklyThreshold: Int = 20,
        hourlyEnabled: Bool = false, hourlyThreshold: Int = 20
    ) -> AppSettings {
        var s = AppSettings()
        s.weeklyAlertEnabled = weeklyEnabled
        s.weeklyAlertThreshold = weeklyThreshold
        s.hourlyAlertEnabled = hourlyEnabled
        s.hourlyAlertThreshold = hourlyThreshold
        return s
    }

    // MARK: - Weekly Alert (WA-01 to WA-07)

    func testWA01_weeklyDisabled_skips() {
        let result = makeResult(sevenDayPercent: 85, sevenDayResetsAt: epochA)
        let settings = makeSettings(weeklyEnabled: false, weeklyThreshold: 20)
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 0, "WA-01: disabled → skip")
    }

    func testWA02_weeklyPercentNil_skips() {
        let result = makeResult(sevenDayPercent: nil, sevenDayResetsAt: epochA)
        let settings = makeSettings(weeklyEnabled: true, weeklyThreshold: 20)
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 0, "WA-02: percent nil → skip")
    }

    func testWA03_weeklyResetsAtNil_skips() {
        let result = makeResult(sevenDayPercent: 85, sevenDayResetsAt: nil)
        let settings = makeSettings(weeklyEnabled: true, weeklyThreshold: 20)
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 0, "WA-03: resets_at nil → skip")
    }

    func testWA04_weeklyAboveThreshold_skips() {
        let result = makeResult(sevenDayPercent: 75, sevenDayResetsAt: epochA)
        let settings = makeSettings(weeklyEnabled: true, weeklyThreshold: 20)
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 0, "WA-04: remaining 25% > threshold 20% → skip")
    }

    func testWA05_weeklyBelowThreshold_notifies() {
        let result = makeResult(sevenDayPercent: 85, sevenDayResetsAt: epochA)
        let settings = makeSettings(weeklyEnabled: true, weeklyThreshold: 20)
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 1, "WA-05: remaining 15% <= 20% → notify")
        XCTAssertEqual(mockSender.sendRecords[0].identifier, "weathercc-weekly")
        XCTAssertTrue(mockSender.sendRecords[0].title.contains("Weekly"))
    }

    func testWA06_weeklySameSession_skips() {
        let result = makeResult(sevenDayPercent: 85, sevenDayResetsAt: epochA)
        let settings = makeSettings(weeklyEnabled: true, weeklyThreshold: 20)
        // First check: notify
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 1)

        // Second check same session: skip
        let result2 = makeResult(sevenDayPercent: 90, sevenDayResetsAt: epochA)
        checker.checkAlerts(result: result2, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 1, "WA-06: same session → skip")
    }

    func testWA07_weeklyNewSession_notifies() {
        let result = makeResult(sevenDayPercent: 85, sevenDayResetsAt: epochA)
        let settings = makeSettings(weeklyEnabled: true, weeklyThreshold: 20)
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 1)

        // New session (different resets_at): should re-notify
        let result2 = makeResult(sevenDayPercent: 85, sevenDayResetsAt: epochB)
        checker.checkAlerts(result: result2, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 2, "WA-07: new session → notify again")
    }

    // MARK: - Hourly Alert (HA-01 to HA-07)

    func testHA01_hourlyDisabled_skips() {
        let result = makeResult(fiveHourPercent: 90, fiveHourResetsAt: epochA)
        let settings = makeSettings(hourlyEnabled: false, hourlyThreshold: 20)
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 0, "HA-01: disabled → skip")
    }

    func testHA02_hourlyPercentNil_skips() {
        let result = makeResult(fiveHourPercent: nil, fiveHourResetsAt: epochA)
        let settings = makeSettings(hourlyEnabled: true, hourlyThreshold: 20)
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 0, "HA-02: percent nil → skip")
    }

    func testHA03_hourlyResetsAtNil_skips() {
        let result = makeResult(fiveHourPercent: 90, fiveHourResetsAt: nil)
        let settings = makeSettings(hourlyEnabled: true, hourlyThreshold: 20)
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 0, "HA-03: resets_at nil → skip")
    }

    func testHA04_hourlyAboveThreshold_skips() {
        let result = makeResult(fiveHourPercent: 75, fiveHourResetsAt: epochA)
        let settings = makeSettings(hourlyEnabled: true, hourlyThreshold: 20)
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 0, "HA-04: remaining 25% > 20% → skip")
    }

    func testHA05_hourlyBelowThreshold_notifies() {
        let result = makeResult(fiveHourPercent: 85, fiveHourResetsAt: epochA)
        let settings = makeSettings(hourlyEnabled: true, hourlyThreshold: 20)
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 1, "HA-05: remaining 15% <= 20% → notify")
        XCTAssertEqual(mockSender.sendRecords[0].identifier, "weathercc-hourly")
        XCTAssertTrue(mockSender.sendRecords[0].title.contains("Hourly"))
    }

    func testHA06_hourlySameSession_skips() {
        let result = makeResult(fiveHourPercent: 85, fiveHourResetsAt: epochA)
        let settings = makeSettings(hourlyEnabled: true, hourlyThreshold: 20)
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 1)

        let result2 = makeResult(fiveHourPercent: 95, fiveHourResetsAt: epochA)
        checker.checkAlerts(result: result2, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 1, "HA-06: same session → skip")
    }

    func testHA07_hourlyNewSession_notifies() {
        let result = makeResult(fiveHourPercent: 85, fiveHourResetsAt: epochA)
        let settings = makeSettings(hourlyEnabled: true, hourlyThreshold: 20)
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 1)

        let result2 = makeResult(fiveHourPercent: 85, fiveHourResetsAt: epochB)
        checker.checkAlerts(result: result2, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 2, "HA-07: new session → notify again")
    }

    // MARK: - Notification Content

    func testWeeklyNotification_bodyFormat() {
        let result = makeResult(sevenDayPercent: 85, sevenDayResetsAt: epochA)
        let settings = makeSettings(weeklyEnabled: true, weeklyThreshold: 20)
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords[0].title, "WeatherCC: Weekly Alert")
        XCTAssertEqual(mockSender.sendRecords[0].body, "Weekly usage at 85% — 15% remaining")
    }

    func testHourlyNotification_bodyFormat() {
        let result = makeResult(fiveHourPercent: 90, fiveHourResetsAt: epochA)
        let settings = makeSettings(hourlyEnabled: true, hourlyThreshold: 20)
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords[0].title, "WeatherCC: Hourly Alert")
        XCTAssertEqual(mockSender.sendRecords[0].body, "Hourly usage at 90% — 10% remaining")
    }

    // MARK: - Edge: both alerts simultaneously

    func testBothAlertsCanFireSimultaneously() {
        let result = makeResult(
            fiveHourPercent: 90, sevenDayPercent: 85,
            fiveHourResetsAt: epochA, sevenDayResetsAt: epochA
        )
        let settings = makeSettings(
            weeklyEnabled: true, weeklyThreshold: 20,
            hourlyEnabled: true, hourlyThreshold: 20
        )
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 2, "Both weekly and hourly should fire")
        let identifiers = Set(mockSender.sendRecords.map(\.identifier))
        XCTAssertTrue(identifiers.contains("weathercc-weekly"))
        XCTAssertTrue(identifiers.contains("weathercc-hourly"))
    }

    // MARK: - Edge: threshold boundary (exactly equal)

    func testWeekly_exactlyAtThreshold_notifies() {
        // remaining = 100 - 80 = 20, threshold = 20 → should notify (<=)
        let result = makeResult(sevenDayPercent: 80, sevenDayResetsAt: epochA)
        let settings = makeSettings(weeklyEnabled: true, weeklyThreshold: 20)
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 1, "Exactly at threshold → notify")
    }

    func testWeekly_justAboveThreshold_skips() {
        // remaining = 100 - 79 = 21, threshold = 20 → should skip (>)
        let result = makeResult(sevenDayPercent: 79, sevenDayResetsAt: epochA)
        let settings = makeSettings(weeklyEnabled: true, weeklyThreshold: 20)
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 0, "Just above threshold → skip")
    }

    // MARK: - Daily Alert (DA-01 to DA-10)

    private func makeDailySettings(
        enabled: Bool = true, threshold: Int = 15, definition: DailyAlertDefinition = .calendar
    ) -> AppSettings {
        var s = AppSettings()
        s.dailyAlertEnabled = enabled
        s.dailyAlertThreshold = threshold
        s.dailyAlertDefinition = definition
        return s
    }

    func testDA01_dailyDisabled_skips() {
        mockStore.dailyUsageToReturn = 20.0
        let result = makeResult(sevenDayPercent: 50, sevenDayResetsAt: epochA)
        let settings = makeDailySettings(enabled: false)
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 0, "DA-01: disabled → skip")
    }

    func testDA02_dailyPercentNil_skips() {
        mockStore.dailyUsageToReturn = 20.0
        let result = makeResult(sevenDayPercent: nil, sevenDayResetsAt: epochA)
        let settings = makeDailySettings()
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 0, "DA-02: percent nil → skip")
    }

    func testDA03_dailyNoData_skips() {
        mockStore.dailyUsageToReturn = nil
        let result = makeResult(sevenDayPercent: 50, sevenDayResetsAt: epochA)
        let settings = makeDailySettings()
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 0, "DA-03: no data → skip")
    }

    func testDA04_dailyBelowThreshold_skips() {
        mockStore.dailyUsageToReturn = 10.0
        let result = makeResult(sevenDayPercent: 50, sevenDayResetsAt: epochA)
        let settings = makeDailySettings(threshold: 15)
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 0, "DA-04: usage 10% < threshold 15% → skip")
    }

    func testDA05_dailyCalendar_aboveThreshold_notifies() {
        mockStore.dailyUsageToReturn = 18.0
        let result = makeResult(sevenDayPercent: 50, sevenDayResetsAt: epochA)
        let settings = makeDailySettings(threshold: 15, definition: .calendar)
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 1, "DA-05: usage 18% >= 15% → notify")
        XCTAssertEqual(mockSender.sendRecords[0].identifier, "weathercc-daily")
        XCTAssertTrue(mockSender.sendRecords[0].body.contains("today"))
    }

    func testDA06_dailyCalendar_sameDateDuplicate_skips() {
        mockStore.dailyUsageToReturn = 18.0
        let result = makeResult(sevenDayPercent: 50, sevenDayResetsAt: epochA)
        let settings = makeDailySettings(threshold: 15, definition: .calendar)
        // First check
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 1)

        // Second check same day
        mockStore.dailyUsageToReturn = 20.0
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 1, "DA-06: same date → skip")
    }

    func testDA08_dailySession_aboveThreshold_notifies() {
        mockStore.dailyUsageToReturn = 18.0
        let result = makeResult(sevenDayPercent: 50, sevenDayResetsAt: epochA)
        let settings = makeDailySettings(threshold: 15, definition: .session)
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 1, "DA-08: session-based, usage >= threshold → notify")
        XCTAssertTrue(mockSender.sendRecords[0].body.contains("session period"))
    }

    func testDA09_dailySession_sameDuplicate_skips() {
        mockStore.dailyUsageToReturn = 18.0
        let result = makeResult(sevenDayPercent: 50, sevenDayResetsAt: epochA)
        let settings = makeDailySettings(threshold: 15, definition: .session)
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 1)

        mockStore.dailyUsageToReturn = 20.0
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 1, "DA-09: same session → skip")
    }

    func testDA10_dailySession_newSession_notifies() {
        mockStore.dailyUsageToReturn = 18.0
        let result = makeResult(sevenDayPercent: 50, sevenDayResetsAt: epochA)
        let settings = makeDailySettings(threshold: 15, definition: .session)
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 1)

        // New session
        let result2 = makeResult(sevenDayPercent: 50, sevenDayResetsAt: epochB)
        checker.checkAlerts(result: result2, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 2, "DA-10: new session → notify again")
    }

    // MARK: - Daily: session definition with nil resets_at

    func testDailySession_nilResetsAt_skips() {
        mockStore.dailyUsageToReturn = 18.0
        let result = makeResult(sevenDayPercent: 50, sevenDayResetsAt: nil)
        let settings = makeDailySettings(threshold: 15, definition: .session)
        checker.checkAlerts(result: result, settings: settings)
        waitForNotifications()
        XCTAssertEqual(mockSender.sendRecords.count, 0, "Session-based with nil resets_at → skip")
    }

    // MARK: - Helpers

    /// Wait briefly for Task {} fire-and-forget to complete
    private func waitForNotifications() {
        let exp = expectation(description: "notifications")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        wait(for: [exp], timeout: 2.0)
    }
}
