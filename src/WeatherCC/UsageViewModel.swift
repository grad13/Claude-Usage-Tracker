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

    private static let usageURL = URL(string: "https://claude.ai")!
    private static let targetHost = "claude.ai"
    let webView: WKWebView
    private let settingsStore: any SettingsStoring
    private let usageStore: any UsageStoring
    private let snapshotWriter: any SnapshotWriting
    private let tokenSync: any TokenSyncing
    private var coordinator: WebViewCoordinator?
    private var cookieObserver: CookieChangeObserver?
    private var refreshTimer: Timer?
    private var loginPollTimer: Timer?
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

    static let logURL: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("WeatherCC-debug.log")
        // Clear log on launch
        try? "".write(to: url, atomically: true, encoding: .utf8)
        return url
    }()

    func debug(_ message: String) {
        NSLog("[WeatherCC] %@", message)
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: Self.logURL) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? line.write(to: Self.logURL, atomically: false, encoding: .utf8)
        }
    }

    private var refreshInterval: TimeInterval {
        TimeInterval(settings.refreshIntervalMinutes) * 60
    }

    init(
        settingsStore: any SettingsStoring = SettingsStore.shared,
        usageStore: any UsageStoring = UsageStore.shared,
        snapshotWriter: any SnapshotWriting = DefaultSnapshotWriter(),
        tokenSync: any TokenSyncing = TokenStore.shared
    ) {
        self.settingsStore = settingsStore
        self.usageStore = usageStore
        self.snapshotWriter = snapshotWriter
        self.tokenSync = tokenSync

        let config = WKWebViewConfiguration()
        // Use app-specific persistent data store to avoid macOS TCC prompt
        // ("WeatherCC would like to access data from other apps")
        // .default() shares data with Safari/other WebKit apps → triggers prompt every launch.
        // forIdentifier: creates an isolated persistent store scoped to this app.
        let storeId = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: storeId)
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        self.webView = WKWebView(frame: .zero, configuration: config)
        self.settings = settingsStore.load()

        let coord = WebViewCoordinator(viewModel: self)
        self.coordinator = coord
        webView.navigationDelegate = coord
        webView.uiDelegate = coord

        reloadHistory()
        fetchPredict()
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
            let isLoggedIn = await UsageFetcher.hasValidSession(using: webView)
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
                backupSessionCookies()
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
        usageStore.save(result)
        reloadHistory()
        fetchPredict()
    }

    // MARK: - Predict (JSONL cost estimation)

    private func fetchPredict() {
        let ts = self.tokenSync
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
            ts.sync(directories: dirs)
            let cutoff = Date().addingTimeInterval(-8 * 24 * 3600)
            let allRecords = ts.loadRecords(since: cutoff)

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
        // Disabled: accessing ~/.claude/projects triggers macOS TCC prompt
        // ("would like to access data from other apps") because it belongs to Claude CLI.
        // Predict feature requires user-granted file access (NSOpenPanel) to work with sandbox.
        // TODO: Re-enable when Predict feature is properly integrated with file access consent.
        return []
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
        snapshotWriter.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func reloadHistory() {
        fiveHourHistory = usageStore.loadHistory(windowSeconds: 5 * 3600)
        sevenDayHistory = usageStore.loadHistory(windowSeconds: 7 * 24 * 3600)
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
        return url.host == Self.targetHost
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
                self.debug("cookieChange: fired")
                let hasSession = await UsageFetcher.hasValidSession(using: self.webView)
                self.debug("cookieChange: hasSession=\(hasSession) isLoggedIn=\(self.isLoggedIn)")
                if hasSession {
                    self.handleSessionDetected()
                }
            }
        }
        self.cookieObserver = observer
        webView.configuration.websiteDataStore.httpCookieStore.add(observer)
    }

    /// Called when a valid session is detected (from cookie observer, login poll, or popup close).
    private func handleSessionDetected() {
        guard !isLoggedIn else { return }
        debug("handleSessionDetected: transitioning to logged-in state")
        isLoggedIn = true
        isAutoRefreshEnabled = nil
        loginPollTimer?.invalidate()
        loginPollTimer = nil
        backupSessionCookies()
        startAutoRefresh()
        guard canRedirect() else { return }
        lastRedirectAt = Date()
        loadUsagePage()
    }

    // MARK: - Login Polling (fallback for SPA navigation that doesn't trigger didFinish)

    private func startLoginPolling() {
        guard loginPollTimer == nil else { return }
        debug("startLoginPolling: starting 3s interval poll")
        loginPollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isLoggedIn else { return }
                let hasSession = await UsageFetcher.hasValidSession(using: self.webView)
                if hasSession {
                    self.debug("loginPoll: session detected!")
                    self.handleSessionDetected()
                }
            }
        }
    }

    // MARK: - Cookie Backup/Restore (survives app reinstall via App Group)

    private static let cookieBackupName = "session-cookies.json"

    private struct CookieData: Codable {
        let name: String
        let value: String
        let domain: String
        let path: String
        let expiresDate: Double?
        let isSecure: Bool
    }

    /// Save claude.ai cookies to App Group so they survive app reinstall.
    private func backupSessionCookies() {
        Task {
            let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            let claudeCookies = cookies.filter { $0.domain.hasSuffix("claude.ai") }
            guard !claudeCookies.isEmpty else { return }

            let backups = claudeCookies.map { CookieData(
                name: $0.name, value: $0.value, domain: $0.domain, path: $0.path,
                expiresDate: $0.expiresDate?.timeIntervalSince1970, isSecure: $0.isSecure
            )}

            guard let container = AppGroupConfig.containerURL else { return }
            let dir = container
                .appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent(AppGroupConfig.appName, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(backups) {
                try? data.write(to: dir.appendingPathComponent(Self.cookieBackupName))
                debug("backupCookies: saved \(claudeCookies.count) cookies")
            }
        }
    }

    /// Restore claude.ai cookies from App Group backup into WebView data store.
    private func restoreSessionCookies() async -> Bool {
        guard let container = AppGroupConfig.containerURL else { return false }
        let url = container
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(AppGroupConfig.appName, isDirectory: true)
            .appendingPathComponent(Self.cookieBackupName)
        guard let data = try? Data(contentsOf: url),
              let backups = try? JSONDecoder().decode([CookieData].self, from: data) else { return false }

        let now = Date()
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        var count = 0
        for backup in backups {
            // Skip expired cookies
            if let exp = backup.expiresDate, Date(timeIntervalSince1970: exp) <= now { continue }
            var props: [HTTPCookiePropertyKey: Any] = [
                .name: backup.name,
                .value: backup.value,
                .domain: backup.domain,
                .path: backup.path,
            ]
            if let exp = backup.expiresDate {
                props[.expires] = Date(timeIntervalSince1970: exp)
            }
            if backup.isSecure { props[.secure] = "TRUE" }
            if let cookie = HTTPCookie(properties: props) {
                await cookieStore.setCookie(cookie)
                count += 1
            }
        }
        debug("restoreCookies: restored \(count)/\(backups.count) cookies")
        return count > 0
    }

    // MARK: - Popup

    func closePopup() {
        popupWebView?.stopLoading()
        popupWebView = nil
    }

    /// Called when OAuth popup closes. Check session since SPA navigation may not trigger didFinish.
    func handlePopupClosed() {
        debug("handlePopupClosed: checking session")
        Task {
            // Wait briefly for cookies to propagate
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let hasSession = await UsageFetcher.hasValidSession(using: webView)
            debug("handlePopupClosed: hasSession=\(hasSession)")
            if hasSession {
                handleSessionDetected()
            }
        }
    }

    // MARK: - Settings

    func setRefreshInterval(minutes: Int) {
        settings.refreshIntervalMinutes = minutes
        settingsStore.save(settings)
        restartAutoRefresh()
    }

    func toggleStartAtLogin() {
        settings.startAtLogin.toggle()
        settingsStore.save(settings)
        syncLoginItem()
    }

    func setShowHourlyGraph(_ show: Bool) {
        settings.showHourlyGraph = show
        settingsStore.save(settings)
    }

    func setShowWeeklyGraph(_ show: Bool) {
        settings.showWeeklyGraph = show
        settingsStore.save(settings)
    }

    func setChartWidth(_ width: Int) {
        settings.chartWidth = width
        settingsStore.save(settings)
    }

    func setHourlyColorPreset(_ preset: ChartColorPreset) {
        settings.hourlyColorPreset = preset
        settingsStore.save(settings)
    }

    func setWeeklyColorPreset(_ preset: ChartColorPreset) {
        settings.weeklyColorPreset = preset
        settingsStore.save(settings)
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
            viewModel.handlePopupClosed()
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
