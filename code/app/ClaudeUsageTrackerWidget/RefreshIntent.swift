// meta: updated=2026-03-16 06:52 checked=-
import AppIntents
import WidgetKit
import ClaudeUsageTrackerShared

struct RefreshIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Usage"

    func perform() async throws -> some IntentResult {
        RefreshState.markRefreshing()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

enum RefreshState {
    private static let key = "widget_refreshing_until"

    static func markRefreshing() {
        let until = Date().addingTimeInterval(1.5)
        UserDefaults(suiteName: AppGroupConfig.groupId)?.set(until.timeIntervalSince1970, forKey: key)
    }

    static var isRefreshing: Bool {
        guard let ts = UserDefaults(suiteName: AppGroupConfig.groupId)?.double(forKey: key), ts > 0 else {
            return false
        }
        return Date().timeIntervalSince1970 < ts
    }

    static var expiresAt: Date? {
        guard let ts = UserDefaults(suiteName: AppGroupConfig.groupId)?.double(forKey: key), ts > 0 else {
            return nil
        }
        let date = Date(timeIntervalSince1970: ts)
        return date > Date() ? date : nil
    }
}
