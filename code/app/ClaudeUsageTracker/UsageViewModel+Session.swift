// meta: updated=2026-04-19 02:25 checked=2026-02-26 00:00
import Foundation
import WebKit
import ClaudeUsageTrackerShared

// MARK: - Cookie Observation, Login Polling, Popup, Sign Out

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
    /// loginPollTimer is intentionally NOT stopped here — only applyResult stops it,
    /// so that page-load / fetch failures after cookie detection can still be retried by polling.
    func handleSessionDetected() {
        guard !isLoggedIn else { return }
        debug("handleSessionDetected: transitioning to logged-in state")
        isLoggedIn = true
        isAutoRefreshEnabled = nil
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
                guard let self else { return }
                // Fully recovered — applyResult will stop the timer; ignore stragglers.
                if self.fiveHourPercent != nil && self.sevenDayPercent != nil { return }
                let hasSession = await self.fetcher.hasValidSession(using: self.webView)
                if !hasSession { return }  // No cookie → wait
                if !self.isLoggedIn {
                    self.debug("loginPoll: session detected!")
                    self.handleSessionDetected()
                } else {
                    // Logged in but no data yet → reissue page load (network may have failed)
                    self.debug("loginPoll: retrying loadUsagePage (logged in but no data)")
                    self.lastRedirectAt = nil  // clear canRedirect() cooldown
                    self.loadUsagePage()
                }
            }
        }
    }

    // MARK: - Popup

    /// Called by WebViewCoordinator when a popup finishes loading.
    func checkPopupLogin() {
        Task {
            let isLoggedIn = await fetcher.hasValidSession(using: webView)
            if isLoggedIn {
                try? await Task.sleep(nanoseconds: 500_000_000)
                closePopup()
                handleSessionDetected()
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
        error = nil

        // Write logged-out snapshot file to App Group container for widget
        let logoutSnapshot = UsageSnapshot(
            timestamp: Date(),
            fiveHourPercent: nil,
            sevenDayPercent: nil,
            fiveHourResetsAt: nil,
            sevenDayResetsAt: nil,
            fiveHourHistory: [],
            sevenDayHistory: [],
            isLoggedIn: false
        )
        if let data = try? JSONEncoder().encode(logoutSnapshot),
           let url = AppGroupConfig.snapshotURL {
            try? data.write(to: url, options: .atomic)
        }

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
                // Stage 3: Reload usage page and restart login detection
                Task { @MainActor in
                    self?.loadUsagePage()
                    self?.startLoginPolling()
                }
            }
        }
    }
}
