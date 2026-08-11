// meta: updated=2026-03-16 06:52 checked=2026-03-03 00:00
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

    /// Called from applyResult() after usageStore.save(). Synchronous compatibility wrapper.
    /// Notification sending remains fire-and-forget for production callers.
    func checkAlerts(result: UsageResult, settings: AppSettings) {
        let notifications = selectedNotifications(result: result, settings: settings)
        Task { await send(notifications) }
    }

    /// Evaluates every alert and returns only after all selected sends have completed.
    /// The returned count is zero for every no-send path.
    @discardableResult
    func checkAlertsAndWait(result: UsageResult, settings: AppSettings) async -> Int {
        let notifications = selectedNotifications(result: result, settings: settings)
        return await send(notifications)
    }

    private struct SelectedNotification {
        let title: String
        let body: String
        let identifier: String
    }

    private func selectedNotifications(
        result: UsageResult,
        settings: AppSettings
    ) -> [SelectedNotification] {
        [
            weeklyAlert(result: result, settings: settings),
            hourlyAlert(result: result, settings: settings),
            dailyAlert(result: result, settings: settings),
        ].compactMap { $0 }
    }

    private func send(_ notifications: [SelectedNotification]) async -> Int {
        for notification in notifications {
            await notificationSender.send(
                title: notification.title,
                body: notification.body,
                identifier: notification.identifier
            )
        }
        return notifications.count
    }

    // MARK: - Weekly & Hourly Alerts

    private func weeklyAlert(result: UsageResult, settings: AppSettings) -> SelectedNotification? {
        thresholdAlert(
            kind: .weekly, isEnabled: settings.weeklyAlertEnabled,
            percent: result.sevenDayPercent, resetsAt: result.sevenDayResetsAt,
            threshold: settings.weeklyAlertThreshold, titleLabel: "Weekly"
        )
    }

    private func hourlyAlert(result: UsageResult, settings: AppSettings) -> SelectedNotification? {
        thresholdAlert(
            kind: .hourly, isEnabled: settings.hourlyAlertEnabled,
            percent: result.fiveHourPercent, resetsAt: result.fiveHourResetsAt,
            threshold: settings.hourlyAlertThreshold, titleLabel: "Hourly"
        )
    }

    private func thresholdAlert(
        kind: AlertKind, isEnabled: Bool,
        percent: Double?, resetsAt: Date?,
        threshold: Int, titleLabel: String
    ) -> SelectedNotification? {
        guard isEnabled else { return nil }
        guard let percent, let resetsAt else { return nil }

        let remaining = 100.0 - percent
        guard remaining <= Double(threshold) else { return nil }

        let normalized = normalizeResetsAt(resetsAt)
        guard lastNotifiedResetsAt[kind] != normalized else { return nil }

        lastNotifiedResetsAt[kind] = normalized

        let title = "ClaudeUsageTracker: \(titleLabel) Alert"
        let body = String(format: "\(titleLabel) usage at %.0f%% — %.0f%% remaining", percent, remaining)
        let identifier = "claudeusagetracker-\(kind.rawValue)"
        return SelectedNotification(title: title, body: body, identifier: identifier)
    }

    // MARK: - Daily Alert

    private func dailyAlert(result: UsageResult, settings: AppSettings) -> SelectedNotification? {
        guard settings.dailyAlertEnabled else { return nil }
        guard result.sevenDayPercent != nil else { return nil }

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
            guard let resetsAt = result.sevenDayResetsAt else { return nil }
            let normalized = normalizeResetsAt(resetsAt)
            periodKey = String(normalized)
            // Session start = resetsAt - 7 days
            since = Date(timeIntervalSince1970: TimeInterval(normalized) - 7 * 24 * 3600)
        }

        // Check duplicate
        guard lastDailyNotifiedKey != periodKey else { return nil }

        // Query usage
        guard let dailyUsage = usageStore.loadDailyUsage(since: since) else { return nil }
        guard dailyUsage >= Double(settings.dailyAlertThreshold) else { return nil }

        lastDailyNotifiedKey = periodKey

        let title = "ClaudeUsageTracker: Daily Alert"
        let suffix = settings.dailyAlertDefinition == .calendar ? "today" : "this session period"
        let body = String(format: "Used %.0f%% %@ (threshold: %d%%)", dailyUsage, suffix, settings.dailyAlertThreshold)
        return SelectedNotification(
            title: title,
            body: body,
            identifier: "claudeusagetracker-daily"
        )
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
