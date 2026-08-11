// meta: updated=2026-08-11 checked=-
import Foundation
import WebKit
import Combine
import ServiceManagement
import ClaudeUsageTrackerShared

@MainActor
protocol ViewModelTimer: AnyObject {
    var timeInterval: TimeInterval { get }
    var isValid: Bool { get }
    func invalidate()
}

@MainActor
private final class WeakUsageViewModelBox {
    private weak var value: UsageViewModel?

    init(_ value: UsageViewModel) {
        self.value = value
    }

    func withValue<Result>(_ body: (UsageViewModel) -> Result) -> Result? {
        guard let value else { return nil }
        return body(value)
    }
}

private enum PageReadyDecision {
    case terminal(UsageViewModel.PageReadyOutcome)
    case fetch(UInt64)
}

private enum SilentFetchDecision {
    case terminal(UsageViewModel.FetchOutcome)
    case retry(after: TimeInterval)
}

extension Timer: ViewModelTimer {}

protocol ViewModelTimerScheduling {
    @MainActor
    func schedule(
        interval: TimeInterval,
        repeats: Bool,
        handler: @escaping @MainActor () -> Void
    ) -> any ViewModelTimer
}

struct FoundationViewModelTimerScheduler: ViewModelTimerScheduling {
    @MainActor
    func schedule(
        interval: TimeInterval,
        repeats: Bool,
        handler: @escaping @MainActor () -> Void
    ) -> any ViewModelTimer {
        Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats) { _ in
            MainActor.assumeIsolated {
                handler()
            }
        }
    }
}

@MainActor
private final class OperationTerminal<Outcome> {
    private var didFinish = false
    private let completion: (@MainActor (Outcome) -> Void)?

    init(completion: (@MainActor (Outcome) -> Void)?) {
        self.completion = completion
    }

    func finish(_ outcome: Outcome) {
        guard !didFinish else { return }
        didFinish = true
        completion?(outcome)
    }
}

@MainActor
final class UsageViewModel: ObservableObject, WebViewCoordinatorDelegate {
    typealias Sleeper = @MainActor (TimeInterval) async throws -> Void

    enum FetchOutcome: Equatable {
        case success
        case failure
        case authenticationRequired
        case busy
        case cancelled
    }

    enum PageReadyOutcome: Equatable {
        case noSession
        case redirected
        case cooldownSuppressed
        case fetch(FetchOutcome)
        case cancelled
    }

    @Published var fiveHourPercent: Double?
    @Published var sevenDayPercent: Double?
    @Published var fiveHourResetsAt: Date?
    @Published var sevenDayResetsAt: Date?
    var fiveHourResetsAtObservedAt: Date? = nil
    var sevenDayResetsAtObservedAt: Date? = nil
    @Published var error: String?
    @Published var isFetching = false
    @Published var isLoggedIn = false
    @Published var settings: AppSettings
    @Published var popupWebView: WKWebView?
    @Published var fiveHourHistory: [UsageStore.DataPoint] = []
    @Published var sevenDayHistory: [UsageStore.DataPoint] = []
    /// Start of the current weekly session (from DB). Nil if no session exists yet.
    /// Used by the 7d chart to render only the current session's data.
    @Published var sevenDayStartedAt: Date?
    static let usageURL = URL(string: "https://claude.ai")!
    static let targetHost = "claude.ai"
    let webView: WKWebView
    let fetcher: any UsageFetching
    let settingsStore: any SettingsStoring
    let usageStore: any UsageStoring
    let widgetReloader: any WidgetReloading
    let loginItemManager: any LoginItemManaging
    let alertChecker: any AlertChecking
    var coordinator: WebViewCoordinator?
    var cookieObserver: CookieChangeObserver?
    var refreshTimer: (any ViewModelTimer)?
    var loginPollTimer: (any ViewModelTimer)?
    /// Controls auto-refresh eligibility. nil=undetermined, true=enabled, false=disabled (auth error).
    var isAutoRefreshEnabled: Bool?
    /// Throttle usage-page redirects to prevent infinite loops.
    var lastRedirectAt: Date?
    private static let maxRetries = 3
    private static let retryDelays: [TimeInterval] = [30, 60, 120]
    let sleeper: Sleeper
    let timerScheduler: any ViewModelTimerScheduling
    let now: () -> Date
    private var lifecycleGeneration: UInt64 = 0
    private var fetchOperationID: UInt64 = 0
    private var activeFetchOperationID: UInt64?
    private var fetchTask: Task<Void, Never>?
    private var fetchTerminal: OperationTerminal<FetchOutcome>?
    private var pageReadyTask: Task<Void, Never>?
    private var pageReadyTerminal: OperationTerminal<PageReadyOutcome>?
    private var pageReadyFetchOperationID: UInt64?
    private var refreshTimerToken = UUID()

    var statusText: String {
        let fiveH = fiveHourPercent.map { String(format: "%.0f%%", $0) } ?? "--"
        let sevenD = sevenDayPercent.map { String(format: "%.0f%%", $0) } ?? "--"
        return "5h: \(fiveH) / 7d: \(sevenD)"
    }

    // MARK: - Time Progress (for menu bar graph x-axis)

    static func timeProgress(resetsAt: Date?, windowSeconds: TimeInterval, now: Date = Date()) -> Double {
        guard let resetsAt else { return 0.0 }
        let elapsed = windowSeconds - resetsAt.timeIntervalSince(now)
        return min(max(elapsed / windowSeconds, 0.0), 1.0)
    }

    var fiveHourTimeProgress: Double {
        Self.timeProgress(resetsAt: fiveHourResetsAt, windowSeconds: 5 * 3600)
    }

    var sevenDayTimeProgress: Double {
        Self.timeProgress(resetsAt: sevenDayResetsAt, windowSeconds: 7 * 24 * 3600)
    }

    // MARK: - Remaining Time Text (for dropdown display)

    func remainingTimeText(for resetsAt: Date?) -> String? {
        guard let resetsAt else { return nil }
        return DisplayHelpers.remainingText(until: resetsAt)
    }

    var fiveHourRemainingText: String? {
        remainingTimeText(for: fiveHourResetsAt)
    }

    var sevenDayRemainingText: String? {
        remainingTimeText(for: sevenDayResetsAt)
    }

    var refreshInterval: TimeInterval {
        TimeInterval(settings.refreshIntervalMinutes) * 60
    }

    init(
        fetcher: any UsageFetching = DefaultUsageFetcher(),
        settingsStore: any SettingsStoring = SettingsStore.shared,
        usageStore: any UsageStoring = UsageStore.shared,
        widgetReloader: any WidgetReloading = DefaultWidgetReloader(),
        loginItemManager: any LoginItemManaging = DefaultLoginItemManager(),
        alertChecker: any AlertChecking = DefaultAlertChecker(),
        webViewConfiguration: WKWebViewConfiguration? = nil,
        startLifecycle: Bool = true,
        sleeper: @escaping Sleeper = { delay in
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        },
        timerScheduler: any ViewModelTimerScheduling = FoundationViewModelTimerScheduler(),
        now: @escaping () -> Date = Date.init
    ) {
        self.fetcher = fetcher
        self.settingsStore = settingsStore
        self.usageStore = usageStore
        self.widgetReloader = widgetReloader
        self.loginItemManager = loginItemManager
        self.alertChecker = alertChecker
        self.sleeper = sleeper
        self.timerScheduler = timerScheduler
        self.now = now

        Self.markLaunch()

        let config = webViewConfiguration ?? {
            let c = WKWebViewConfiguration()
            // Use default data store — managed by macOS cookied daemon which reliably
            // flushes cookies to disk during shutdown (survives PC reboot).
            // forIdentifier: used WebKit Network Process (XPC) which could lose cookies
            // on shutdown due to incomplete flush. Sandbox OFF avoids TCC prompts.
            c.websiteDataStore = .default()
            c.preferences.javaScriptCanOpenWindowsAutomatically = true
            return c
        }()
        self.webView = WKWebView(frame: .zero, configuration: config)
        self.settings = settingsStore.load()

        let coord = WebViewCoordinator(viewModel: self) { [weak self] finishedURL in
            self?.handlePageReady(finishedURL: finishedURL)
        }
        self.coordinator = coord
        webView.navigationDelegate = coord
        webView.uiDelegate = coord

        reloadHistory()

        // Daily backups (3-day retention) for SQLite databases
        SQLiteBackup.perform(dbPath: (usageStore as? UsageStore)?.dbPath ?? "")

        syncLoginItem()
        if startLifecycle {
            startCookieObservation()

            // .default() DataStore auto-loads persisted cookies — no restore needed
            loadUsagePage()
            startLoginPolling()
        }
    }

    // MARK: - Page Ready (called by coordinator when claude.ai page finishes loading)

    func handlePageReady() {
        startPageReadyOperation(finishedURL: webView.url, completion: nil)
    }

    func handlePageReady(finishedURL: URL) {
        startPageReadyOperation(finishedURL: finishedURL, completion: nil)
    }

    func handlePageReady(
        finishedURL: URL?,
        completion: @escaping @MainActor (PageReadyOutcome) -> Void
    ) {
        startPageReadyOperation(finishedURL: finishedURL, completion: completion)
    }

    private func startPageReadyOperation(
        finishedURL: URL?,
        completion: (@MainActor (PageReadyOutcome) -> Void)?
    ) {
        cancelPageReadyOperation()

        let generation = lifecycleGeneration
        let terminal = OperationTerminal(completion: completion)
        let owner = WeakUsageViewModelBox(self)
        let fetcher = self.fetcher
        let webView = self.webView
        let sleeper = self.sleeper
        pageReadyTerminal = terminal
        debug("handlePageReady: url=\(finishedURL?.absoluteString ?? "nil")")

        pageReadyTask = Task {
            let outcome = await Self.performPageReady(
                owner: owner,
                fetcher: fetcher,
                webView: webView,
                sleeper: sleeper,
                finishedURL: finishedURL,
                generation: generation
            )
            let isCurrent = owner.withValue { viewModel in
                guard viewModel.pageReadyTerminal === terminal else { return false }
                viewModel.pageReadyTask = nil
                viewModel.pageReadyTerminal = nil
                return true
            }
            terminal.finish(isCurrent == true ? outcome : .cancelled)
        }
    }

    private static func performPageReady(
        owner: WeakUsageViewModelBox,
        fetcher: any UsageFetching,
        webView: WKWebView,
        sleeper: @escaping Sleeper,
        finishedURL: URL?,
        generation: UInt64
    ) async -> PageReadyOutcome {
        let hasSession = await fetcher.hasValidSession(using: webView)
        let decision = owner.withValue { viewModel -> PageReadyDecision in
            guard viewModel.isCurrent(generation) else { return .terminal(.cancelled) }
            viewModel.debug("handlePageReady: hasValidSession=\(hasSession)")
            guard hasSession else {
                viewModel.debug("handlePageReady: no session, skipping")
                return .terminal(.noSession)
            }

            viewModel.isLoggedIn = true
            viewModel.startAutoRefresh()

            guard viewModel.isOnUsagePage(finishedURL) else {
                viewModel.debug("handlePageReady: not on usage page, redirecting")
                guard viewModel.canRedirect() else {
                    viewModel.debug("handlePageReady: redirect cooldown active")
                    return .terminal(.cooldownSuppressed)
                }
                viewModel.lastRedirectAt = viewModel.now()
                viewModel.loadUsagePage()
                return .terminal(.redirected)
            }

            viewModel.debug("handlePageReady: on usage page, fetching")
            guard let operationID = viewModel.beginFetchOperation() else {
                return .terminal(.fetch(.busy))
            }
            viewModel.pageReadyFetchOperationID = operationID
            return .fetch(operationID)
        }
        guard let decision else { return .cancelled }
        switch decision {
        case .terminal(let outcome):
            return outcome
        case .fetch(let operationID):
            let outcome = await performSilentFetch(
                owner: owner,
                fetcher: fetcher,
                webView: webView,
                sleeper: sleeper,
                operationID: operationID,
                generation: generation
            )
            owner.withValue { viewModel in
                viewModel.finishFetchOperation(operationID)
                if viewModel.pageReadyFetchOperationID == operationID {
                    viewModel.pageReadyFetchOperationID = nil
                }
            }
            return .fetch(outcome)
        }
    }

    // MARK: - Fetch

    /// Manual fetch triggered by user (Refresh button). Always runs regardless of isAutoRefreshEnabled.
    func fetch(completion: (@MainActor (FetchOutcome) -> Void)? = nil) {
        let terminal = OperationTerminal(completion: completion)
        guard let operationID = beginFetchOperation() else {
            terminal.finish(.busy)
            return
        }
        error = nil
        let generation = lifecycleGeneration
        let owner = WeakUsageViewModelBox(self)
        let fetcher = self.fetcher
        let webView = self.webView
        fetchTerminal = terminal

        fetchTask = Task {
            let outcome = await Self.performManualFetch(
                owner: owner,
                fetcher: fetcher,
                webView: webView,
                operationID: operationID,
                generation: generation
            )
            let isCurrent = owner.withValue { viewModel in
                viewModel.finishFetchOperation(operationID)
                guard viewModel.fetchTerminal === terminal else { return false }
                viewModel.fetchTerminal = nil
                return true
            }
            terminal.finish(isCurrent == true ? outcome : .cancelled)
        }
    }

    /// Automatic fetch (launch, after login, auto-refresh)
    func fetchSilently(completion: (@MainActor (FetchOutcome) -> Void)? = nil) {
        let terminal = OperationTerminal(completion: completion)
        guard let operationID = beginFetchOperation() else {
            debug("fetchSilently: already fetching, skipping")
            terminal.finish(.busy)
            return
        }
        let generation = lifecycleGeneration
        let owner = WeakUsageViewModelBox(self)
        let fetcher = self.fetcher
        let webView = self.webView
        let sleeper = self.sleeper
        fetchTerminal = terminal
        debug("fetchSilently: starting fetch")

        fetchTask = Task {
            let outcome = await Self.performSilentFetch(
                owner: owner,
                fetcher: fetcher,
                webView: webView,
                sleeper: sleeper,
                operationID: operationID,
                generation: generation
            )
            let isCurrent = owner.withValue { viewModel in
                viewModel.finishFetchOperation(operationID)
                guard viewModel.fetchTerminal === terminal else { return false }
                viewModel.fetchTerminal = nil
                return true
            }
            terminal.finish(isCurrent == true ? outcome : .cancelled)
        }
    }

    private static func performManualFetch(
        owner: WeakUsageViewModelBox,
        fetcher: any UsageFetching,
        webView: WKWebView,
        operationID: UInt64,
        generation: UInt64
    ) async -> FetchOutcome {
        do {
            let result = try await fetcher.fetch(from: webView)
            return owner.withValue { viewModel in
                guard viewModel.isCurrent(generation, operationID: operationID) else {
                    return .cancelled
                }
                viewModel.applyResult(result)
                viewModel.isLoggedIn = true
                viewModel.isAutoRefreshEnabled = true
                viewModel.startAutoRefresh()
                return .success
            } ?? .cancelled
        } catch {
            return owner.withValue { viewModel in
                guard viewModel.isCurrent(generation, operationID: operationID) else {
                    return .cancelled
                }
                if let fetchError = error as? UsageFetchError {
                    NSLog("[ClaudeUsageTracker] fetch error: %@", fetchError.diagnosticMessage)
                    if fetchError.isAuthError {
                        viewModel.isAutoRefreshEnabled = false
                        viewModel.isLoggedIn = false
                        viewModel.error = nil
                        return .authenticationRequired
                    }
                }
                viewModel.error = error.localizedDescription
                return .failure
            } ?? .cancelled
        }
    }

    private static func performSilentFetch(
        owner: WeakUsageViewModelBox,
        fetcher: any UsageFetching,
        webView: WKWebView,
        sleeper: @escaping Sleeper,
        operationID: UInt64,
        generation: UInt64
    ) async -> FetchOutcome {
        for attempt in 0...Self.maxRetries {
            guard owner.withValue({ $0.isCurrent(generation, operationID: operationID) }) == true else {
                return .cancelled
            }
            do {
                let result = try await fetcher.fetch(from: webView)
                return owner.withValue { viewModel in
                    guard viewModel.isCurrent(generation, operationID: operationID) else {
                        return .cancelled
                    }
                    viewModel.debug("fetchSilently: success 5h=\(result.fiveHourPercent ?? -1) 7d=\(result.sevenDayPercent ?? -1)")
                    viewModel.applyResult(result)
                    viewModel.isLoggedIn = true
                    viewModel.isAutoRefreshEnabled = true
                    viewModel.error = nil
                    viewModel.startAutoRefresh()
                    return .success
                } ?? .cancelled
            } catch {
                let decision = owner.withValue { viewModel -> SilentFetchDecision in
                    guard viewModel.isCurrent(generation, operationID: operationID) else {
                        return .terminal(.cancelled)
                    }
                    let isAuthError = (error as? UsageFetchError)?.isAuthError == true
                    if let fetchError = error as? UsageFetchError {
                        viewModel.debug("fetchSilently: error=\(fetchError.diagnosticMessage)")
                        if isAuthError {
                            viewModel.isAutoRefreshEnabled = false
                        }
                    } else {
                        viewModel.debug("fetchSilently: error=\(error)")
                    }
                    if viewModel.isLoggedIn {
                        viewModel.error = error.localizedDescription
                    }
                    if isAuthError {
                        return .terminal(.authenticationRequired)
                    }
                    guard attempt < Self.maxRetries else {
                        return .terminal(.failure)
                    }

                    let delay = Self.retryDelays[attempt]
                    viewModel.debug("fetchSilently: scheduling retry \(attempt + 1)/\(Self.maxRetries) in \(delay)s")
                    return .retry(after: delay)
                } ?? .terminal(.cancelled)

                switch decision {
                case .terminal(let outcome):
                    return outcome
                case .retry(let delay):
                    do {
                        try await sleeper(delay)
                    } catch {
                        return .cancelled
                    }
                }
                guard owner.withValue({ $0.isCurrent(generation, operationID: operationID) }) == true else {
                    return .cancelled
                }
            }
        }
        return .failure
    }

    private func beginFetchOperation() -> UInt64? {
        guard activeFetchOperationID == nil, !isFetching else { return nil }
        fetchOperationID &+= 1
        activeFetchOperationID = fetchOperationID
        isFetching = true
        return fetchOperationID
    }

    private func finishFetchOperation(_ operationID: UInt64) {
        guard activeFetchOperationID == operationID else { return }
        activeFetchOperationID = nil
        fetchTask = nil
        isFetching = false
    }

    private func isCurrent(_ generation: UInt64, operationID: UInt64? = nil) -> Bool {
        guard !Task.isCancelled, lifecycleGeneration == generation else { return false }
        guard let operationID else { return true }
        return activeFetchOperationID == operationID
    }

    var currentLifecycleGeneration: UInt64 {
        lifecycleGeneration
    }

    func isCurrentLifecycleGeneration(_ generation: UInt64) -> Bool {
        lifecycleGeneration == generation
    }

    func invalidateAsyncOperations() {
        lifecycleGeneration &+= 1
        refreshTimerToken = UUID()
        fetchTask?.cancel()
        fetchTask = nil
        fetchTerminal?.finish(.cancelled)
        fetchTerminal = nil
        activeFetchOperationID = nil
        isFetching = false
        cancelPageReadyOperation()
    }

    private func cancelPageReadyOperation() {
        pageReadyTask?.cancel()
        pageReadyTask = nil
        pageReadyTerminal?.finish(.cancelled)
        pageReadyTerminal = nil
        if let operationID = pageReadyFetchOperationID {
            finishFetchOperation(operationID)
            pageReadyFetchOperationID = nil
        }
    }

    func applyResult(_ result: UsageResult) {
        var observedResult = result
        let observedAt = result.resetTimesObservedAt ?? Date()
        observedResult.resetTimesObservedAt = observedAt

        // Phase 1: Update @Published state
        fiveHourPercent = result.fiveHourPercent
        sevenDayPercent = result.sevenDayPercent
        if let exact = result.fiveHourResetsAt,
           fiveHourResetsAtObservedAt.map({ observedAt >= $0 }) ?? true {
            fiveHourResetsAt = exact
            fiveHourResetsAtObservedAt = observedAt
        }
        if let exact = result.sevenDayResetsAt,
           sevenDayResetsAtObservedAt.map({ observedAt >= $0 }) ?? true {
            sevenDayResetsAt = exact
            sevenDayResetsAtObservedAt = observedAt
        }

        // Phase 2: Persist to DB + reload history
        usageStore.save(observedResult)
        reloadHistory()

        // Phase 2.5: Write snapshot file to App Group container for widget
        writeWidgetSnapshot(result: observedResult, isLoggedIn: true)

        // Phase 3: Evaluate alert thresholds
        alertChecker.checkAlerts(result: observedResult, settings: settings)

        // Phase 4: Notify widget to reload (reads from same usage.db)
        widgetReloader.reloadAllTimelines()

        // Phase 5: Stop login polling — data fetch fully succeeded.
        // This is the SOLE place the timer is invalidated; intermediate steps
        // (handleSessionDetected, handlePageReady) keep it alive so failures retry.
        loginPollTimer?.invalidate()
        loginPollTimer = nil
    }

    // MARK: - Navigation

    func loadUsagePage() {
        let request = URLRequest(
            url: Self.usageURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 60
        )
        webView.load(request)
    }

    func isOnUsagePage(_ finishedURL: URL? = nil) -> Bool {
        guard let url = finishedURL ?? webView.url else { return false }
        return url.host == Self.targetHost
    }

    func canRedirect() -> Bool {
        guard let lastRedirectAt else { return true }
        return now().timeIntervalSince(lastRedirectAt) > 5
    }

    func reloadHistory() {
        fiveHourHistory = usageStore.loadHistory(windowSeconds: 5 * 3600)
        if fiveHourResetsAt == nil,
           let latest = fiveHourHistory.last(where: { $0.fiveHourResetsAtObservedAt != nil })
                ?? fiveHourHistory.last(where: { $0.fiveHourResetsAt != nil }) {
            fiveHourResetsAt = latest.fiveHourResetsAt
            fiveHourResetsAtObservedAt = latest.fiveHourResetsAtObservedAt
        }
        if let session = usageStore.loadCurrentWeeklySession() {
            sevenDayHistory = session.dataPoints
            sevenDayStartedAt = session.startedAt
            // A fresh fetch already populated the exact value. The DB value is only
            // restart/legacy fallback and may be a normalized session identity.
            if sevenDayResetsAt == nil {
                sevenDayResetsAt = session.resetsAt
                sevenDayResetsAtObservedAt = session.dataPoints
                    .last(where: { $0.sevenDayResetsAtObservedAt != nil })?
                    .sevenDayResetsAtObservedAt
            }
        } else {
            sevenDayHistory = []
            sevenDayStartedAt = nil
            // sevenDayResetsAt: leave as-is (may be API-provided for the current fetch
            // before the first save creates a session row).
        }
    }

    // MARK: - Auto Refresh

    func startAutoRefresh() {
        guard refreshTimer == nil else { return }
        guard settings.refreshIntervalMinutes > 0 else { return }
        let generation = lifecycleGeneration
        let token = UUID()
        refreshTimerToken = token
        refreshTimer = timerScheduler.schedule(interval: refreshInterval, repeats: true) { [weak self] in
            guard let self else { return }
            guard self.lifecycleGeneration == generation else { return }
            guard self.refreshTimerToken == token else { return }
            guard self.isAutoRefreshEnabled != false else { return }
            self.fetch()
        }
    }

    func restartAutoRefresh() {
        refreshTimerToken = UUID()
        refreshTimer?.invalidate()
        refreshTimer = nil
        if isLoggedIn {
            startAutoRefresh()
        }
    }

    // MARK: - Widget Snapshot

    func writeWidgetSnapshot(result: UsageResult, isLoggedIn: Bool) {
        let snapshot = UsageSnapshot(
            timestamp: Date(),
            fiveHourPercent: result.fiveHourPercent,
            sevenDayPercent: result.sevenDayPercent,
            fiveHourResetsAt: fiveHourResetsAt,
            sevenDayResetsAt: sevenDayResetsAt,
            fiveHourResetsAtObservedAt: fiveHourResetsAtObservedAt,
            sevenDayResetsAtObservedAt: sevenDayResetsAtObservedAt,
            sevenDayStartedAt: sevenDayStartedAt,
            fiveHourHistory: fiveHourHistory.map { HistoryPoint(timestamp: $0.timestamp, percent: $0.fiveHourPercent ?? 0) },
            sevenDayHistory: sevenDayHistory.map { HistoryPoint(timestamp: $0.timestamp, percent: $0.sevenDayPercent ?? 0) },
            isLoggedIn: isLoggedIn
        )
        if let data = try? JSONEncoder().encode(snapshot),
           let url = AppGroupConfig.snapshotURL {
            try? data.write(to: url, options: .atomic)
        }
    }
}
