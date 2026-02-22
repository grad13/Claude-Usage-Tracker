// meta: created=2026-02-21 updated=2026-02-21 checked=never
import Foundation
import WebKit
import Combine
import ServiceManagement
import WidgetKit
import WeatherCCShared

@MainActor
final class UsageViewModel: ObservableObject {
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
    @Published var predictFiveHourCost: Double?
    @Published var predictSevenDayCost: Double?

    private static let usageURL = URL(string: "https://claude.ai/settings/usage")!
    private static let targetHost = "claude.ai"
    let webView: WKWebView
    private var coordinator: WebViewCoordinator?
    private var cookieObserver: CookieChangeObserver?
    private var refreshTimer: Timer?
    /// Controls auto-refresh eligibility. nil=undetermined, true=enabled, false=disabled (auth error).
    private var isAutoRefreshEnabled: Bool?
    /// Throttle usage-page redirects to prevent infinite loops.
    private var lastRedirectAt: Date?

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

    func debug(_ message: String) {
        NSLog("[WeatherCC] %@", message)
    }

    private var refreshInterval: TimeInterval {
        TimeInterval(settings.refreshIntervalMinutes) * 60
    }

    init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        self.webView = WKWebView(frame: .zero, configuration: config)
        self.settings = SettingsStore.load()

        let coord = WebViewCoordinator(viewModel: self)
        self.coordinator = coord
        webView.navigationDelegate = coord
        webView.uiDelegate = coord

        reloadHistory()
        fetchPredict()
        syncLoginItem()
        startCookieObservation()
        loadUsagePage()
    }

    // MARK: - Page Ready (called by coordinator when claude.ai page finishes loading)

    func handlePageReady() {
        let currentURL = webView.url?.absoluteString ?? "nil"
        debug("handlePageReady: url=\(currentURL)")
        Task {
            let isLoggedIn = await UsageFetcher.hasValidSession(using: webView)
            debug("handlePageReady: hasValidSession=\(isLoggedIn)")
            guard isLoggedIn else {
                debug("handlePageReady: no session, skipping")
                return
            }
            self.isLoggedIn = true

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
                let result = try await UsageFetcher.fetch(from: webView)
                applyResult(result)
                isLoggedIn = true
                isAutoRefreshEnabled = true
                startAutoRefresh()
            } catch {
                self.error = error.localizedDescription
                if let fetchError = error as? UsageFetchError, fetchError.isAuthError {
                    isAutoRefreshEnabled = false
                }
            }
            isFetching = false
        }
    }

    /// Automatic fetch (launch, after login, auto-refresh)
    private func fetchSilently() {
        guard !isFetching else {
            debug("fetchSilently: already fetching, skipping")
            return
        }
        isFetching = true
        debug("fetchSilently: starting fetch")

        Task {
            do {
                let result = try await UsageFetcher.fetch(from: webView)
                debug("fetchSilently: success 5h=\(result.fiveHourPercent ?? -1) 7d=\(result.sevenDayPercent ?? -1)")
                applyResult(result)
                isLoggedIn = true
                isAutoRefreshEnabled = true
                error = nil
                startAutoRefresh()
            } catch {
                debug("fetchSilently: error=\(error)")
                if let fetchError = error as? UsageFetchError, fetchError.isAuthError {
                    isAutoRefreshEnabled = false
                }
                if isLoggedIn {
                    self.error = error.localizedDescription
                }
            }
            isFetching = false
        }
    }

    private func applyResult(_ result: UsageResult) {
        fiveHourPercent = result.fiveHourPercent
        sevenDayPercent = result.sevenDayPercent
        fiveHourResetsAt = result.fiveHourResetsAt
        sevenDayResetsAt = result.sevenDayResetsAt
        UsageStore.save(result)
        reloadHistory()
        fetchPredict()
    }

    // MARK: - Predict (JSONL cost estimation)

    private func fetchPredict() {
        Task.detached { [weak self] in
            let dirs = Self.claudeProjectsDirectories()
            guard !dirs.isEmpty else {
                await MainActor.run {
                    self?.predictFiveHourCost = nil
                    self?.predictSevenDayCost = nil
                    self?.writeSnapshot()
                }
                return
            }
            var allRecords: [TokenRecord] = []
            for dir in dirs {
                allRecords.append(contentsOf: JSONLParser.parseDirectory(dir))
            }
            let now = Date()
            let fiveH = CostEstimator.estimate(records: allRecords, windowHours: 5, now: now)
            let sevenD = CostEstimator.estimate(records: allRecords, windowHours: 168, now: now)

            await MainActor.run {
                self?.predictFiveHourCost = fiveH.totalCost > 0 ? fiveH.totalCost : nil
                self?.predictSevenDayCost = sevenD.totalCost > 0 ? sevenD.totalCost : nil
                self?.writeSnapshot()
            }
        }
    }

    private nonisolated static func claudeProjectsDirectories() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".claude/projects"),
            home.appendingPathComponent(".config/claude/projects")
        ]
        return candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Widget Snapshot

    private func writeSnapshot() {
        let snapshot = UsageSnapshot(
            timestamp: Date(),
            fiveHourPercent: fiveHourPercent,
            sevenDayPercent: sevenDayPercent,
            fiveHourResetsAt: fiveHourResetsAt,
            sevenDayResetsAt: sevenDayResetsAt,
            fiveHourHistory: fiveHourHistory.compactMap { dp in
                guard let p = dp.fiveHourPercent else { return nil }
                return HistoryPoint(timestamp: dp.timestamp, percent: p)
            },
            sevenDayHistory: sevenDayHistory.compactMap { dp in
                guard let p = dp.sevenDayPercent else { return nil }
                return HistoryPoint(timestamp: dp.timestamp, percent: p)
            },
            isLoggedIn: isLoggedIn,
            predictFiveHourCost: predictFiveHourCost,
            predictSevenDayCost: predictSevenDayCost
        )
        SnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func reloadHistory() {
        fiveHourHistory = UsageStore.loadHistory(windowSeconds: 5 * 3600)
        sevenDayHistory = UsageStore.loadHistory(windowSeconds: 7 * 24 * 3600)
    }

    // MARK: - Navigation

    private func loadUsagePage() {
        let request = URLRequest(
            url: Self.usageURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 60
        )
        webView.load(request)
    }

    private func isOnUsagePage() -> Bool {
        guard let url = webView.url else { return false }
        return url.host == Self.usageURL.host && url.path == Self.usageURL.path
    }

    private func canRedirect() -> Bool {
        guard let lastRedirectAt else { return true }
        return Date().timeIntervalSince(lastRedirectAt) > 5
    }

    // MARK: - Cookie Observation

    private func startCookieObservation() {
        let observer = CookieChangeObserver { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let hasSession = await UsageFetcher.hasValidSession(using: self.webView)
                self.debug("cookieChange: hasSession=\(hasSession) isLoggedIn=\(self.isLoggedIn)")
                guard hasSession else { return }
                guard !self.isOnUsagePage() else { return }
                guard self.canRedirect() else { return }
                self.debug("cookieChange: session detected, redirecting to usage page")
                self.isLoggedIn = true
                self.isAutoRefreshEnabled = nil
                self.lastRedirectAt = Date()
                self.loadUsagePage()
            }
        }
        self.cookieObserver = observer
        webView.configuration.websiteDataStore.httpCookieStore.add(observer)
    }

    // MARK: - Popup

    func closePopup() {
        popupWebView?.stopLoading()
        popupWebView = nil
    }

    // MARK: - Settings

    func setRefreshInterval(minutes: Int) {
        settings.refreshIntervalMinutes = minutes
        SettingsStore.save(settings)
        restartAutoRefresh()
    }

    func toggleStartAtLogin() {
        settings.startAtLogin.toggle()
        SettingsStore.save(settings)
        syncLoginItem()
    }

    func setShowHourlyGraph(_ show: Bool) {
        settings.showHourlyGraph = show
        SettingsStore.save(settings)
    }

    func setShowWeeklyGraph(_ show: Bool) {
        settings.showWeeklyGraph = show
        SettingsStore.save(settings)
    }

    func setChartWidth(_ width: Int) {
        settings.chartWidth = width
        SettingsStore.save(settings)
    }

    func setHourlyColorPreset(_ preset: ChartColorPreset) {
        settings.hourlyColorPreset = preset
        SettingsStore.save(settings)
    }

    func setWeeklyColorPreset(_ preset: ChartColorPreset) {
        settings.weeklyColorPreset = preset
        SettingsStore.save(settings)
    }

    func signOut() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        isLoggedIn = false
        isAutoRefreshEnabled = nil
        lastRedirectAt = nil
        fiveHourPercent = nil
        sevenDayPercent = nil
        fiveHourResetsAt = nil
        sevenDayResetsAt = nil
        predictFiveHourCost = nil
        predictSevenDayCost = nil
        error = nil

        let dataStore = webView.configuration.websiteDataStore
        // Stage 1: Remove all website data
        dataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: Date.distantPast
        ) { [weak self] in
            // Stage 2: Explicitly delete each cookie
            dataStore.httpCookieStore.getAllCookies { cookies in
                for cookie in cookies {
                    dataStore.httpCookieStore.delete(cookie)
                }
                // Stage 3: Reload usage page
                Task { @MainActor in
                    self?.loadUsagePage()
                }
            }
        }
    }

    // MARK: - Private

    private func syncLoginItem() {
        do {
            if settings.startAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("[WeatherCC] SMAppService error: \(error)")
        }
    }

    private func startAutoRefresh() {
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

    private func restartAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if isLoggedIn {
            startAutoRefresh()
        }
    }
}

// MARK: - WebView Coordinator (navigation + OAuth popup handling)

private final class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    private weak var viewModel: UsageViewModel?

    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let viewModel else { return }
        let url = webView.url?.absoluteString ?? "nil"

        // Popup: check login status, close if logged in
        if webView === viewModel.popupWebView {
            viewModel.debug("didFinish[popup]: url=\(url)")
            Task {
                let isLoggedIn = await UsageFetcher.hasValidSession(using: viewModel.webView)
                if isLoggedIn {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    viewModel.closePopup()
                }
            }
            return
        }

        viewModel.debug("didFinish[main]: url=\(url)")

        // Main WebView: notify ViewModel if on target host
        if let host = webView.url?.host, host == "claude.ai" {
            viewModel.handlePageReady()
        } else {
            viewModel.debug("didFinish[main]: host is not claude.ai, skipping")
        }
    }

    // MARK: OAuth Popup (sheet modal)

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let viewModel else { return nil }
        guard navigationAction.targetFrame == nil else { return nil }
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.navigationDelegate = self
        viewModel.popupWebView = popup
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard let viewModel else { return }
        if webView === viewModel.popupWebView {
            viewModel.closePopup()
        }
    }
}

// MARK: - Cookie Observer

private final class CookieChangeObserver: NSObject, WKHTTPCookieStoreObserver {
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        onChange()
    }
}
