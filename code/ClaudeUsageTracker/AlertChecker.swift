// meta: created=2026-02-27 updated=2026-02-27 checked=never
import Foundation

final class AlertChecker {
    static let shared = AlertChecker()

    enum AlertKind: String {
        case weekly, hourly, daily
    }

    private let notificationSender: any NotificationSending
    private let usageStore: any UsageStoring

    // Duplicate notification prevention (in-memory).
    // key = AlertKind, value = normalizeResetsAt epoch for the session that was notified.
    private(set) var lastNotifiedResetsAt: [AlertKind: Int] = [:]

    // Daily alert duplicate prevention key.
    // Calendar-based: date string "2026-02-27". Session-based: String(normalizedResetsAt).
    private(set) var lastDailyNotifiedKey: String?

    init(
        notificationSender: any NotificationSending = DefaultNotificationSender(),
        usageStore: any UsageStoring = UsageStore.shared
    ) {
        self.notificationSender = notificationSender
        self.usageStore = usageStore
    }

    /// Called from applyResult() after usageStore.save(). Synchronous method.
    /// Notification sending is fire-and-forget via Task {}.
    func checkAlerts(result: UsageResult, settings: AppSettings) {
        checkWeeklyAlert(result: result, settings: settings)
        checkHourlyAlert(result: result, settings: settings)
        checkDailyAlert(result: result, settings: settings)
    }

    // MARK: - Weekly Alert

    private func checkWeeklyAlert(result: UsageResult, settings: AppSettings) {
        guard settings.weeklyAlertEnabled else { return }
        guard let percent = result.sevenDayPercent else { return }
        guard let resetsAt = result.sevenDayResetsAt else { return }

        let remaining = 100.0 - percent
        guard remaining <= Double(settings.weeklyAlertThreshold) else { return }

        let normalized = normalizeResetsAt(resetsAt)
        guard lastNotifiedResetsAt[.weekly] != normalized else { return }

        lastNotifiedResetsAt[.weekly] = normalized

        let title = "ClaudeUsageTracker: Weekly Alert"
        let body = String(format: "Weekly usage at %.0f%% — %.0f%% remaining", percent, remaining)
        Task { await notificationSender.send(title: title, body: body, identifier: "claudeusagetracker-weekly") }
    }

    // MARK: - Hourly Alert

    private func checkHourlyAlert(result: UsageResult, settings: AppSettings) {
        guard settings.hourlyAlertEnabled else { return }
        guard let percent = result.fiveHourPercent else { return }
        guard let resetsAt = result.fiveHourResetsAt else { return }

        let remaining = 100.0 - percent
        guard remaining <= Double(settings.hourlyAlertThreshold) else { return }

        let normalized = normalizeResetsAt(resetsAt)
        guard lastNotifiedResetsAt[.hourly] != normalized else { return }

        lastNotifiedResetsAt[.hourly] = normalized

        let title = "ClaudeUsageTracker: Hourly Alert"
        let body = String(format: "Hourly usage at %.0f%% — %.0f%% remaining", percent, remaining)
        Task { await notificationSender.send(title: title, body: body, identifier: "claudeusagetracker-hourly") }
    }

    // MARK: - Daily Alert

    private func checkDailyAlert(result: UsageResult, settings: AppSettings) {
        guard settings.dailyAlertEnabled else { return }
        guard result.sevenDayPercent != nil else { return }

        // Determine the period start and duplicate-prevention key
        let periodKey: String
        let since: Date

        switch settings.dailyAlertDefinition {
        case .calendar:
            let today = Calendar.current.startOfDay(for: Date())
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            periodKey = formatter.string(from: today)
            since = today
        case .session:
            guard let resetsAt = result.sevenDayResetsAt else { return }
            let normalized = normalizeResetsAt(resetsAt)
            periodKey = String(normalized)
            // Session start = resetsAt - 7 days
            since = Date(timeIntervalSince1970: TimeInterval(normalized) - 7 * 24 * 3600)
        }

        // Check duplicate
        guard lastDailyNotifiedKey != periodKey else { return }

        // Query usage
        guard let dailyUsage = usageStore.loadDailyUsage(since: since) else { return }
        guard dailyUsage >= Double(settings.dailyAlertThreshold) else { return }

        lastDailyNotifiedKey = periodKey

        let title = "ClaudeUsageTracker: Daily Alert"
        let suffix = settings.dailyAlertDefinition == .calendar ? "today" : "this session period"
        let body = String(format: "Used %.0f%% %@ (threshold: %d%%)", dailyUsage, suffix, settings.dailyAlertThreshold)
        Task { await notificationSender.send(title: title, body: body, identifier: "claudeusagetracker-daily") }
    }

    // MARK: - Helpers

    private func normalizeResetsAt(_ date: Date) -> Int {
        let epoch = Int(date.timeIntervalSince1970)
        return ((epoch + 1800) / 3600) * 3600
    }
}

// MARK: - DefaultAlertChecker

struct DefaultAlertChecker: AlertChecking {
    func checkAlerts(result: UsageResult, settings: AppSettings) {
        AlertChecker.shared.checkAlerts(result: result, settings: settings)
    }
}
