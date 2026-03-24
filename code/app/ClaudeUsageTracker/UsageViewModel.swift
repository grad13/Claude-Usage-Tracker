// meta: updated=2026-03-16 06:52 checked=2026-02-26 00:00
import Foundation
import WebKit
import Combine
import ServiceManagement
import ClaudeUsageTrackerShared

@MainActor
final class UsageViewModel: ObservableObject, WebViewCoordinatorDelegate {
    @Published var fiveHourPercent: Double?
    @Published var sevenDayPercent: Double?
    @Published var fiveHourResetsAt: Date?
    @Published var sevenDayResetsAt: Date?
    @Published var error: String?
    @Published var isFetching = false
    @Published var isLoggedIn = false
    @Published var settings: AppSettings
    @Published var popupWebView: WKWebView?
    @Published var fiveHourHistory: [UsageStore.DataPoint] = []
    @Published var sevenDayHistory: [UsageStore.DataPoint] = []
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
    var refreshTimer: Timer?
    var loginPollTimer: Timer?
    /// Controls auto-refresh eligibility. nil=undetermined, true=enabled, false=disabled (auth error).
    var isAutoRefreshEnabled: Bool?
    /// Throttle usage-page redirects to prevent infinite loops.
    var lastRedirectAt: Date?
    /// Current retry count for fetchSilently (reset on success or after max retries).
    private var retryCount = 0
    private static let maxRetries = 3
    private static let retryDelays: [TimeInterval] = [30, 60, 120]

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
        webViewConfiguration: WKWebViewConfiguration? = nil
    ) {
        self.fetcher = fetcher
        self.settingsStore = settingsStore
        self.usageStore = usageStore
        self.widgetReloader = widgetReloader
        self.loginItemManager = loginItemManager
        self.alertChecker = alertChecker

        let config = webViewConfiguration ?? {
            let c = WKWebViewConfiguration()
            // Use app-specific persistent data store to avoid macOS TCC prompt
            // ("ClaudeUsageTracker would like to access data from other apps")
            // .default() shares data with Safari/other WebKit apps → triggers prompt every launch.
            // forIdentifier: creates an isolated persistent store scoped to this app.
            let storeId = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!
            c.websiteDataStore = WKWebsiteDataStore(forIdentifier: storeId)
            c.preferences.javaScriptCanOpenWindowsAutomatically = true
            return c
        }()
        self.webView = WKWebView(frame: .zero, configuration: config)
        self.settings = settingsStore.load()

        let coord = WebViewCoordinator(viewModel: self)
        self.coordinator = coord
        webView.navigationDelegate = coord
        webView.uiDelegate = coord

        reloadHistory()

        // Daily backups (3-day retention) for SQLite databases
        SQLiteBackup.perform(dbPath: (usageStore as? UsageStore)?.dbPath ?? "")

        syncLoginItem()
        startCookieObservation()

        // Restore cookies from App Group backup, then load page
        Task { [weak self] in
            guard let self else { return }
            let restored = await self.restoreSessionCookies()
            self.debug("init: cookieRestore=\(restored)")
            self.loadUsagePage()
            self.startLoginPolling()
        }
    }

    // MARK: - Page Ready (called by coordinator when claude.ai page finishes loading)

    func handlePageReady() {
        let currentURL = webView.url?.absoluteString ?? "nil"
        debug("handlePageReady: url=\(currentURL)")
        Task {
            let isLoggedIn = await fetcher.hasValidSession(using: webView)
            debug("handlePageReady: hasValidSession=\(isLoggedIn)")
            guard isLoggedIn else {
                debug("handlePageReady: no session, skipping")
                return
            }
            self.isLoggedIn = true
            loginPollTimer?.invalidate()
            loginPollTimer = nil
            startAutoRefresh()
            backupSessionCookies()

            if !isOnUsagePage() {
                debug("handlePageReady: not on usage page, redirecting")
                guard canRedirect() else {
                    debug("handlePageReady: redirect cooldown active")
                    return
                }
                lastRedirectAt = Date()
                loadUsagePage()
                return
            }

            debug("handlePageReady: on usage page, fetching")
            fetchSilently()
        }
    }

    // MARK: - Fetch

    /// Manual fetch triggered by user (Refresh button). Always runs regardless of isAutoRefreshEnabled.
    func fetch() {
        guard !isFetching else { return }
        isFetching = true
        error = nil

        Task {
            do {
                let result = try await fetcher.fetch(from: webView)
                applyResult(result)
                isLoggedIn = true
                isAutoRefreshEnabled = true
                startAutoRefresh()
            } catch {
                if let fetchError = error as? UsageFetchError {
                    NSLog("[ClaudeUsageTracker] fetch error: %@", fetchError.diagnosticMessage)
                    if fetchError.isAuthError {
                        isAutoRefreshEnabled = false
                        isLoggedIn = false
                        self.error = nil
                    } else {
                        self.error = error.localizedDescription
                    }
                } else {
                    self.error = error.localizedDescription
                }
            }
            isFetching = false
        }
    }

    /// Automatic fetch (launch, after login, auto-refresh)
    func fetchSilently() {
        guard !isFetching else {
            debug("fetchSilently: already fetching, skipping")
            return
        }
        isFetching = true
        debug("fetchSilently: starting fetch")

        Task {
            do {
                let result = try await fetcher.fetch(from: webView)
                debug("fetchSilently: success 5h=\(result.fiveHourPercent ?? -1) 7d=\(result.sevenDayPercent ?? -1)")
                applyResult(result)
                isLoggedIn = true
                isAutoRefreshEnabled = true
                error = nil
                retryCount = 0
                startAutoRefresh()
                backupSessionCookies()
            } catch {
                let isAuthError = (error as? UsageFetchError)?.isAuthError == true
                if let fetchError = error as? UsageFetchError {
                    debug("fetchSilently: error=\(fetchError.diagnosticMessage)")
                    if isAuthError { isAutoRefreshEnabled = false }
                } else {
                    debug("fetchSilently: error=\(error)")
                }
                if isLoggedIn {
                    self.error = error.localizedDescription
                }

                // Retry on non-auth errors with exponential backoff
                if !isAuthError && retryCount < Self.maxRetries {
                    let delay = Self.retryDelays[retryCount]
                    retryCount += 1
                    debug("fetchSilently: scheduling retry \(retryCount)/\(Self.maxRetries) in \(delay)s")
                    isFetching = false
                    try? await Task.sleep(for: .seconds(delay))
                    fetchSilently()
                    return
                }
                retryCount = 0
            }
            isFetching = false
        }
    }

    func applyResult(_ result: UsageResult) {
        // Phase 1: Update @Published state
        fiveHourPercent = result.fiveHourPercent
        sevenDayPercent = result.sevenDayPercent
        fiveHourResetsAt = result.fiveHourResetsAt
        sevenDayResetsAt = result.sevenDayResetsAt

        // Phase 2: Persist to DB + reload history
        usageStore.save(result)
        reloadHistory()

        // Phase 2.5: Write snapshot file to App Group container for widget
        writeWidgetSnapshot(result: result, isLoggedIn: true)

        // Phase 3: Evaluate alert thresholds
        alertChecker.checkAlerts(result: result, settings: settings)

        // Phase 4: Notify widget to reload (reads from same usage.db)
        widgetReloader.reloadAllTimelines()

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

    func isOnUsagePage() -> Bool {
        guard let url = webView.url else { return false }
        return url.host == Self.targetHost
    }

    func canRedirect() -> Bool {
        guard let lastRedirectAt else { return true }
        return Date().timeIntervalSince(lastRedirectAt) > 5
    }

    func reloadHistory() {
        fiveHourHistory = usageStore.loadHistory(windowSeconds: 5 * 3600)
        sevenDayHistory = usageStore.loadHistory(windowSeconds: 7 * 24 * 3600)
    }

    // MARK: - Auto Refresh

    func startAutoRefresh() {
        guard refreshTimer == nil else { return }
        guard settings.refreshIntervalMinutes > 0 else { return }
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: refreshInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.isAutoRefreshEnabled != false else { return }
                self.fetch()
            }
        }
    }

    func restartAutoRefresh() {
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
            fiveHourResetsAt: result.fiveHourResetsAt,
            sevenDayResetsAt: result.sevenDayResetsAt,
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
