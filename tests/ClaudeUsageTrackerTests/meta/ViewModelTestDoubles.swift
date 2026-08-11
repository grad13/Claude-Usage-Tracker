// meta: updated=2026-08-11 checked=-
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
    var weeklySessionToReturn: UsageStore.WeeklySession?
    var dailyUsageToReturn: Double?
    func save(_ result: UsageResult) { savedResults.append(result) }
    func loadHistory(windowSeconds: TimeInterval) -> [UsageStore.DataPoint] { historyToReturn }
    func loadCurrentWeeklySession() -> UsageStore.WeeklySession? { weeklySessionToReturn }
    func loadDailyUsage(since: Date) -> Double? { dailyUsageToReturn }
}

final class InMemoryWidgetReloader: WidgetReloading {
    var reloadCount = 0
    func reloadAllTimelines() { reloadCount += 1 }
}

@MainActor
final class StubUsageFetcher: UsageFetching {
    var fetchResult: Result<UsageResult, Error> = .success(UsageResult())
    var scriptedFetchResults: [Result<UsageResult, Error>] = []
    var hasValidSessionResult = false
    var fetchCallCount = 0
    var hasValidSessionCallCount = 0
    var shouldSuspendFetch = false
    var onFetch: ((Int) -> Void)?
    var onFetchReturn: (() -> Void)?
    var onHasValidSession: (() -> Void)?
    private var pendingFetchContinuations: [CheckedContinuation<UsageResult, Error>] = []

    nonisolated init() {}

    var pendingFetchCount: Int { pendingFetchContinuations.count }

    func fetch(from webView: WKWebView) async throws -> UsageResult {
        fetchCallCount += 1
        onFetch?(fetchCallCount)
        defer { onFetchReturn?() }
        if shouldSuspendFetch {
            return try await withCheckedThrowingContinuation { continuation in
                pendingFetchContinuations.append(continuation)
            }
        }
        let result = scriptedFetchResults.isEmpty
            ? fetchResult
            : scriptedFetchResults.removeFirst()
        return try result.get()
    }

    func hasValidSession(using webView: WKWebView) async -> Bool {
        hasValidSessionCallCount += 1
        onHasValidSession?()
        return hasValidSessionResult
    }

    func resumeNextFetch(with result: Result<UsageResult, Error>) {
        precondition(!pendingFetchContinuations.isEmpty, "No suspended fetch to resume")
        let continuation = pendingFetchContinuations.removeFirst()
        continuation.resume(with: result)
    }
}

@MainActor
final class ManualSleeper {
    private var continuations: [CheckedContinuation<Void, Error>] = []
    private(set) var requestedDelays: [TimeInterval] = []
    var onSleep: ((TimeInterval) -> Void)?
    var onSleepReturn: (() -> Void)?

    var pendingCount: Int { continuations.count }

    func sleep(for delay: TimeInterval) async throws {
        requestedDelays.append(delay)
        defer { onSleepReturn?() }
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
            onSleep?(delay)
        }
    }

    func resumeNext() {
        precondition(!continuations.isEmpty, "No suspended sleep to resume")
        continuations.removeFirst().resume()
    }

    func cancelNext() {
        precondition(!continuations.isEmpty, "No suspended sleep to cancel")
        continuations.removeFirst().resume(throwing: CancellationError())
    }
}

@MainActor
final class ManualViewModelTimer: ViewModelTimer {
    let timeInterval: TimeInterval
    let repeats: Bool
    private(set) var isValid = true
    private let handler: @MainActor () -> Void

    init(
        timeInterval: TimeInterval,
        repeats: Bool,
        handler: @escaping @MainActor () -> Void
    ) {
        self.timeInterval = timeInterval
        self.repeats = repeats
        self.handler = handler
    }

    func fire() {
        guard isValid else { return }
        handler()
        if !repeats {
            invalidate()
        }
    }

    func invalidate() {
        isValid = false
    }
}

@MainActor
final class ManualViewModelTimerScheduler: ViewModelTimerScheduling {
    private(set) var timers: [ManualViewModelTimer] = []

    nonisolated init() {}

    var validTimers: [ManualViewModelTimer] {
        timers.filter(\.isValid)
    }

    func schedule(
        interval: TimeInterval,
        repeats: Bool,
        handler: @escaping @MainActor () -> Void
    ) -> any ViewModelTimer {
        let timer = ManualViewModelTimer(
            timeInterval: interval,
            repeats: repeats,
            handler: handler
        )
        timers.append(timer)
        return timer
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
        alertChecker: MockAlertChecker = MockAlertChecker(),
        startLifecycle: Bool = true,
        sleeper: @escaping UsageViewModel.Sleeper = { delay in
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        },
        timerScheduler: any ViewModelTimerScheduling = FoundationViewModelTimerScheduler(),
        now: @escaping () -> Date = Date.init
    ) -> UsageViewModel {
        UsageViewModel(
            fetcher: fetcher,
            settingsStore: settingsStore,
            usageStore: usageStore,
            widgetReloader: widgetReloader,
            loginItemManager: loginItemManager,
            alertChecker: alertChecker,
            webViewConfiguration: testWebViewConfig(),
            startLifecycle: startLifecycle,
            sleeper: sleeper,
            timerScheduler: timerScheduler,
            now: now
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
        rawJSON: String? = nil,
        resetTimesObservedAt: Date? = nil
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
            rawJSON: rawJSON,
            resetTimesObservedAt: resetTimesObservedAt
        )
    }
}
