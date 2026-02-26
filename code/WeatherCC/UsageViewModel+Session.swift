// meta: created=2026-02-26 updated=2026-02-26 checked=2026-02-26
import Foundation
import WebKit
import WeatherCCShared

// MARK: - Cookie Observation, Login Polling, Cookie Backup/Restore, Popup, Sign Out

extension UsageViewModel {

    // MARK: - Cookie Observation

    func startCookieObservation() {
        let observer = CookieChangeObserver { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.debug("cookieChange: fired")
                let hasSession = await self.fetcher.hasValidSession(using: self.webView)
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
    func handleSessionDetected() {
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

    func startLoginPolling() {
        guard loginPollTimer == nil else { return }
        debug("startLoginPolling: starting 3s interval poll")
        loginPollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isLoggedIn else { return }
                let hasSession = await self.fetcher.hasValidSession(using: self.webView)
                if hasSession {
                    self.debug("loginPoll: session detected!")
                    self.handleSessionDetected()
                }
            }
        }
    }

    // MARK: - Cookie Backup/Restore (survives app reinstall via App Group)

    static let cookieBackupName = "session-cookies.json"

    struct CookieData: Codable {
        let name: String
        let value: String
        let domain: String
        let path: String
        let expiresDate: Double?
        let isSecure: Bool
    }

    /// Save claude.ai cookies to App Group so they survive app reinstall.
    func backupSessionCookies() {
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
    func restoreSessionCookies() async -> Bool {
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

    /// Called by WebViewCoordinator when a popup finishes loading.
    func checkPopupLogin() {
        Task {
            let isLoggedIn = await fetcher.hasValidSession(using: webView)
            if isLoggedIn {
                try? await Task.sleep(nanoseconds: 500_000_000)
                closePopup()
            }
        }
    }

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
            let hasSession = await fetcher.hasValidSession(using: webView)
            debug("handlePopupClosed: hasSession=\(hasSession)")
            if hasSession {
                handleSessionDetected()
            }
        }
    }

    // MARK: - Sign Out

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

        snapshotWriter.clearOnSignOut()
        widgetReloader.reloadAllTimelines()

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
}
