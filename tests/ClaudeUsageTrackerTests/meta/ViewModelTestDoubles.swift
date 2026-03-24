// meta: updated=2026-03-14 11:31 checked=-
import XCTest
import WebKit
import ClaudeUsageTrackerShared
@testable import ClaudeUsageTracker

// MARK: - In-Memory Test Implementations

final class InMemorySettingsStore: SettingsStoring {
    var current = AppSettings()
    func load() -> AppSettings { current }
    func save(_ settings: AppSettings) { current = settings }
}

final class InMemoryUsageStore: UsageStoring {
    var savedResults: [UsageResult] = []
    var historyToReturn: [UsageStore.DataPoint] = []
    var dailyUsageToReturn: Double?
    func save(_ result: UsageResult) { savedResults.append(result) }
    func loadHistory(windowSeconds: TimeInterval) -> [UsageStore.DataPoint] { historyToReturn }
    func loadDailyUsage(since: Date) -> Double? { dailyUsageToReturn }
}

final class InMemoryWidgetReloader: WidgetReloading {
    var reloadCount = 0
    func reloadAllTimelines() { reloadCount += 1 }
}

final class StubUsageFetcher: UsageFetching {
    var fetchResult: Result<UsageResult, Error> = .success(UsageResult())
    var hasValidSessionResult = false
    var fetchCallCount = 0
    var hasValidSessionCallCount = 0

    @MainActor func fetch(from webView: WKWebView) async throws -> UsageResult {
        fetchCallCount += 1
        return try fetchResult.get()
    }
    @MainActor func hasValidSession(using webView: WKWebView) async -> Bool {
        hasValidSessionCallCount += 1
        return hasValidSessionResult
    }
}

final class InMemoryLoginItemManager: LoginItemManaging {
    var enabledCallCount = 0
    var disabledCallCount = 0
    var lastEnabled: Bool?
    var shouldThrow: Error?

    func setEnabled(_ enabled: Bool) throws {
        if let error = shouldThrow { throw error }
        lastEnabled = enabled
        if enabled { enabledCallCount += 1 }
        else { disabledCallCount += 1 }
    }
}

final class MockNotificationSender: NotificationSending, @unchecked Sendable {
    struct SendRecord {
        let title: String
        let body: String
        let identifier: String
    }

    private let lock = NSLock()
    private var _sendRecords: [SendRecord] = []
    var sendRecords: [SendRecord] {
        lock.lock()
        defer { lock.unlock() }
        return _sendRecords
    }
    var authorizationResult = true
    private var _requestAuthorizationCallCount = 0
    var requestAuthorizationCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _requestAuthorizationCallCount
    }

    func requestAuthorization() async -> Bool {
        lock.lock()
        _requestAuthorizationCallCount += 1
        lock.unlock()
        return authorizationResult
    }

    func send(title: String, body: String, identifier: String) async {
        lock.lock()
        _sendRecords.append(SendRecord(title: title, body: body, identifier: identifier))
        lock.unlock()
    }
}

final class MockAlertChecker: AlertChecking {
    struct CheckRecord {
        let result: UsageResult
        let settings: AppSettings
    }

    var checkRecords: [CheckRecord] = []

    func checkAlerts(result: UsageResult, settings: AppSettings) {
        checkRecords.append(CheckRecord(result: result, settings: settings))
    }
}

// MARK: - Test Factories

enum ViewModelTestFactory {
    /// Non-persistent config so tests never touch the real WKWebsiteDataStore.
    @MainActor private static func testWebViewConfig() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        return config
    }

    @MainActor static func makeVM(
        fetcher: StubUsageFetcher = StubUsageFetcher(),
        settingsStore: InMemorySettingsStore = InMemorySettingsStore(),
        usageStore: InMemoryUsageStore = InMemoryUsageStore(),
        widgetReloader: InMemoryWidgetReloader = InMemoryWidgetReloader(),
        loginItemManager: InMemoryLoginItemManager = InMemoryLoginItemManager(),
        alertChecker: MockAlertChecker = MockAlertChecker()
    ) -> UsageViewModel {
        UsageViewModel(
            fetcher: fetcher,
            settingsStore: settingsStore,
            usageStore: usageStore,
            widgetReloader: widgetReloader,
            loginItemManager: loginItemManager,
            alertChecker: alertChecker,
            webViewConfiguration: testWebViewConfig()
        )
    }
}

enum UsageResultFactory {
    static func make(
        fiveHourPercent: Double? = nil,
        sevenDayPercent: Double? = nil,
        fiveHourResetsAt: Date? = nil,
        sevenDayResetsAt: Date? = nil,
        fiveHourStatus: Int? = nil,
        sevenDayStatus: Int? = nil,
        fiveHourLimit: Double? = nil,
        fiveHourRemaining: Double? = nil,
        sevenDayLimit: Double? = nil,
        sevenDayRemaining: Double? = nil,
        rawJSON: String? = nil
    ) -> UsageResult {
        UsageResult(
            fiveHourPercent: fiveHourPercent,
            sevenDayPercent: sevenDayPercent,
            fiveHourResetsAt: fiveHourResetsAt,
            sevenDayResetsAt: sevenDayResetsAt,
            fiveHourStatus: fiveHourStatus,
            sevenDayStatus: sevenDayStatus,
            fiveHourLimit: fiveHourLimit,
            fiveHourRemaining: fiveHourRemaining,
            sevenDayLimit: sevenDayLimit,
            sevenDayRemaining: sevenDayRemaining,
            rawJSON: rawJSON
        )
    }
}
