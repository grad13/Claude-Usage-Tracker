// meta: created=2026-02-27 updated=2026-03-04 checked=2026-03-03
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

    // MARK: - Weekly & Hourly Alerts

    private func checkWeeklyAlert(result: UsageResult, settings: AppSettings) {
        checkThresholdAlert(
            kind: .weekly, isEnabled: settings.weeklyAlertEnabled,
            percent: result.sevenDayPercent, resetsAt: result.sevenDayResetsAt,
            threshold: settings.weeklyAlertThreshold, titleLabel: "Weekly"
        )
    }

    private func checkHourlyAlert(result: UsageResult, settings: AppSettings) {
        checkThresholdAlert(
            kind: .hourly, isEnabled: settings.hourlyAlertEnabled,
            percent: result.fiveHourPercent, resetsAt: result.fiveHourResetsAt,
            threshold: settings.hourlyAlertThreshold, titleLabel: "Hourly"
        )
    }

    private func checkThresholdAlert(
        kind: AlertKind, isEnabled: Bool,
        percent: Double?, resetsAt: Date?,
        threshold: Int, titleLabel: String
    ) {
        guard isEnabled else { return }
        guard let percent, let resetsAt else { return }

        let remaining = 100.0 - percent
        guard remaining <= Double(threshold) else { return }

        let normalized = normalizeResetsAt(resetsAt)
        guard lastNotifiedResetsAt[kind] != normalized else { return }

        lastNotifiedResetsAt[kind] = normalized

        let title = "ClaudeUsageTracker: \(titleLabel) Alert"
        let body = String(format: "\(titleLabel) usage at %.0f%% — %.0f%% remaining", percent, remaining)
        let identifier = "claudeusagetracker-\(kind.rawValue)"
        Task { await notificationSender.send(title: title, body: body, identifier: identifier) }
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
