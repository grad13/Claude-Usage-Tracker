// meta: updated=2026-08-12 checked=-
import Foundation
import WebKit
import ClaudeUsageTrackerShared

extension UsageViewModel {
    enum PopupSessionOutcome: Equatable {
        case sessionAccepted
        case noValidSession
        case cancelled
    }

    enum SignOutOutcome: Equatable {
        case completed
        case cancelled
    }
}

@MainActor
private final class SessionOperationState {
    weak var owner: UsageViewModel?

    var cookieCheckTask: Task<Void, Never>?
    var loginPollTask: Task<Void, Never>?
    var popupLoginTask: Task<Void, Never>?
    var popupClosedTask: Task<Void, Never>?

    var popupLoginCompletion: (@MainActor (UsageViewModel.PopupSessionOutcome) -> Void)?
    var popupClosedCompletion: (@MainActor (UsageViewModel.PopupSessionOutcome) -> Void)?
    var signOutCompletion: (@MainActor (UsageViewModel.SignOutOutcome) -> Void)?

    var popupLoginID: UInt64 = 0
    var popupClosedID: UInt64 = 0
    var signOutID: UInt64 = 0
    var cookieCheckID: UInt64 = 0
    var loginPollID: UInt64 = 0
    var loginTimerToken = UUID()
    var isSigningOut = false

    init(owner: UsageViewModel) {
        self.owner = owner
    }

    func cancelCookieCheck() {
        cookieCheckTask?.cancel()
        cookieCheckTask = nil
        cookieCheckID &+= 1
    }

    func finishCookieCheck(id: UInt64) {
        guard cookieCheckID == id else { return }
        cookieCheckTask = nil
    }

    func cancelLoginPollCheck() {
        loginPollTask?.cancel()
        loginPollTask = nil
        loginPollID &+= 1
    }

    func finishLoginPollCheck(id: UInt64) {
        guard loginPollID == id else { return }
        loginPollTask = nil
    }

    func cancelPopupLogin() {
        popupLoginTask?.cancel()
        popupLoginTask = nil
        popupLoginID &+= 1
        let completion = popupLoginCompletion
        popupLoginCompletion = nil
        completion?(.cancelled)
    }

    func finishPopupLogin(
        id: UInt64,
        outcome: UsageViewModel.PopupSessionOutcome
    ) {
        guard popupLoginID == id else { return }
        popupLoginTask = nil
        let completion = popupLoginCompletion
        popupLoginCompletion = nil
        completion?(outcome)
    }

    func cancelPopupClosed() {
        popupClosedTask?.cancel()
        popupClosedTask = nil
        popupClosedID &+= 1
        let completion = popupClosedCompletion
        popupClosedCompletion = nil
        completion?(.cancelled)
    }

    func finishPopupClosed(
        id: UInt64,
        outcome: UsageViewModel.PopupSessionOutcome
    ) {
        guard popupClosedID == id else { return }
        popupClosedTask = nil
        let completion = popupClosedCompletion
        popupClosedCompletion = nil
        completion?(outcome)
    }

    func cancelFiniteSessionOperations() {
        cancelCookieCheck()
        cancelLoginPollCheck()
        loginTimerToken = UUID()
        cancelPopupLogin()
        cancelPopupClosed()
    }

    func beginSignOut(
        completion: (@MainActor (UsageViewModel.SignOutOutcome) -> Void)?
    ) -> UInt64 {
        signOutID &+= 1
        let previousCompletion = signOutCompletion
        signOutCompletion = completion
        isSigningOut = true
        previousCompletion?(.cancelled)
        return signOutID
    }

    func finishSignOut(id: UInt64, outcome: UsageViewModel.SignOutOutcome) {
        guard signOutID == id else { return }
        isSigningOut = false
        let completion = signOutCompletion
        signOutCompletion = nil
        completion?(outcome)
    }
}

@MainActor
private enum SessionOperationRegistry {
    private static var states: [ObjectIdentifier: SessionOperationState] = [:]

    static func state(for owner: UsageViewModel) -> SessionOperationState {
        states = states.filter { $0.value.owner != nil }
        let key = ObjectIdentifier(owner)
        if let state = states[key] {
            return state
        }
        let state = SessionOperationState(owner: owner)
        states[key] = state
        return state
    }
}

private func deleteCookies(
    _ cookies: [HTTPCookie],
    at index: Int = 0,
    from store: WKHTTPCookieStore,
    completion: @escaping () -> Void
) {
    guard index < cookies.count else {
        completion()
        return
    }
    store.delete(cookies[index]) {
        deleteCookies(cookies, at: index + 1, from: store, completion: completion)
    }
}

// MARK: - Cookie Observation, Login Polling, Popup, Sign Out

extension UsageViewModel {

    // MARK: - Cookie Observation

    func startCookieObservation() {
        guard cookieObserver == nil else { return }
        let observer = CookieChangeObserver { [weak self] in
            Task { @MainActor [weak self] in
                self?.startCookieSessionCheck()
            }
        }
        cookieObserver = observer
        webView.configuration.websiteDataStore.httpCookieStore.add(observer)
    }

    private func startCookieSessionCheck() {
        let state = SessionOperationRegistry.state(for: self)
        guard !state.isSigningOut else { return }
        state.cancelCookieCheck()
        state.cookieCheckID &+= 1
        let operationID = state.cookieCheckID

        let generation = currentLifecycleGeneration
        let fetcher = self.fetcher
        let webView = self.webView
        state.cookieCheckTask = Task { @MainActor [state] in
            let hasSession = await fetcher.hasValidSession(using: webView)
            defer { state.finishCookieCheck(id: operationID) }
            guard !Task.isCancelled,
                  state.cookieCheckID == operationID,
                  let owner = state.owner,
                  owner.isCurrentLifecycleGeneration(generation),
                  !state.isSigningOut else { return }
            owner.debug("cookieChange: hasSession=\(hasSession) isLoggedIn=\(owner.isLoggedIn)")
            if hasSession {
                owner.handleSessionDetected()
            }
        }
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
        lastRedirectAt = now()
        loadUsagePage()
    }

    // MARK: - Login Polling (fallback for SPA navigation that doesn't trigger didFinish)

    func startLoginPolling() {
        guard loginPollTimer == nil else { return }
        debug("startLoginPolling: starting 3s interval poll")

        let generation = currentLifecycleGeneration
        let state = SessionOperationRegistry.state(for: self)
        let token = UUID()
        state.loginTimerToken = token
        loginPollTimer = timerScheduler.schedule(interval: 3, repeats: true) { [weak self, weak state] in
            guard let self, let state else { return }
            guard state.loginTimerToken == token,
                  !state.isSigningOut,
                  self.isCurrentLifecycleGeneration(generation),
                  self.loginPollTimer?.isValid == true else { return }
            self.startLoginPollCheck(generation: generation, token: token)
        }
    }

    private func startLoginPollCheck(generation: UInt64, token: UUID) {
        let state = SessionOperationRegistry.state(for: self)
        guard state.loginTimerToken == token, !state.isSigningOut else { return }
        guard fiveHourPercent == nil || sevenDayPercent == nil else { return }
        state.cancelLoginPollCheck()
        state.loginPollID &+= 1
        let operationID = state.loginPollID

        let fetcher = self.fetcher
        let webView = self.webView
        state.loginPollTask = Task { @MainActor [state] in
            let hasSession = await fetcher.hasValidSession(using: webView)
            defer { state.finishLoginPollCheck(id: operationID) }
            guard !Task.isCancelled,
                  state.loginPollID == operationID,
                  state.loginTimerToken == token,
                  !state.isSigningOut,
                  let owner = state.owner,
                  owner.isCurrentLifecycleGeneration(generation),
                  owner.loginPollTimer?.isValid == true else { return }
            guard hasSession else { return }
            if !owner.isLoggedIn {
                owner.debug("loginPoll: session detected!")
                owner.handleSessionDetected()
            } else {
                owner.debug("loginPoll: retrying loadUsagePage (logged in but no data)")
                owner.lastRedirectAt = nil
                owner.loadUsagePage()
            }
        }
    }

    // MARK: - Popup

    /// Called by WebViewCoordinator when a popup finishes loading.
    func checkPopupLogin() {
        checkPopupLogin(completion: nil)
    }

    func checkPopupLogin(
        completion: (@MainActor (PopupSessionOutcome) -> Void)?
    ) {
        let state = SessionOperationRegistry.state(for: self)
        state.cancelPopupLogin()
        state.popupLoginID &+= 1
        let operationID = state.popupLoginID
        state.popupLoginCompletion = completion

        let generation = currentLifecycleGeneration
        let fetcher = self.fetcher
        let webView = self.webView
        let sleeper = self.sleeper
        state.popupLoginTask = Task { @MainActor [state] in
            let hasSession = await fetcher.hasValidSession(using: webView)
            guard !Task.isCancelled,
                  state.popupLoginID == operationID,
                  !state.isSigningOut,
                  let owner = state.owner,
                  owner.isCurrentLifecycleGeneration(generation) else {
                state.finishPopupLogin(id: operationID, outcome: .cancelled)
                return
            }
            guard hasSession else {
                state.finishPopupLogin(id: operationID, outcome: .noValidSession)
                return
            }

            do {
                try await sleeper(0.5)
            } catch {
                state.finishPopupLogin(id: operationID, outcome: .cancelled)
                return
            }
            guard !Task.isCancelled,
                  state.popupLoginID == operationID,
                  !state.isSigningOut,
                  let owner = state.owner,
                  owner.isCurrentLifecycleGeneration(generation) else {
                state.finishPopupLogin(id: operationID, outcome: .cancelled)
                return
            }

            owner.closePopupView()
            owner.handleSessionDetected()
            state.finishPopupLogin(id: operationID, outcome: .sessionAccepted)
        }
    }

    func closePopup() {
        let state = SessionOperationRegistry.state(for: self)
        state.cancelPopupLogin()
        state.cancelPopupClosed()
        closePopupView()
    }

    private func closePopupView() {
        popupWebView?.stopLoading()
        popupWebView = nil
    }

    /// Called when OAuth popup closes. Check session since SPA navigation may not trigger didFinish.
    func handlePopupClosed() {
        handlePopupClosed(completion: nil)
    }

    func handlePopupClosed(
        completion: (@MainActor (PopupSessionOutcome) -> Void)?
    ) {
        debug("handlePopupClosed: checking session")
        let state = SessionOperationRegistry.state(for: self)
        state.cancelPopupLogin()
        state.cancelPopupClosed()
        state.popupClosedID &+= 1
        let operationID = state.popupClosedID
        state.popupClosedCompletion = completion

        let generation = currentLifecycleGeneration
        let fetcher = self.fetcher
        let webView = self.webView
        let sleeper = self.sleeper
        state.popupClosedTask = Task { @MainActor [state] in
            do {
                try await sleeper(1)
            } catch {
                state.finishPopupClosed(id: operationID, outcome: .cancelled)
                return
            }
            guard !Task.isCancelled,
                  state.popupClosedID == operationID,
                  !state.isSigningOut,
                  let owner = state.owner,
                  owner.isCurrentLifecycleGeneration(generation) else {
                state.finishPopupClosed(id: operationID, outcome: .cancelled)
                return
            }

            let hasSession = await fetcher.hasValidSession(using: webView)
            guard !Task.isCancelled,
                  state.popupClosedID == operationID,
                  !state.isSigningOut,
                  let owner = state.owner,
                  owner.isCurrentLifecycleGeneration(generation) else {
                state.finishPopupClosed(id: operationID, outcome: .cancelled)
                return
            }
            owner.debug("handlePopupClosed: hasSession=\(hasSession)")
            if hasSession {
                owner.handleSessionDetected()
                state.finishPopupClosed(id: operationID, outcome: .sessionAccepted)
            } else {
                state.finishPopupClosed(id: operationID, outcome: .noValidSession)
            }
        }
    }

    // MARK: - Sign Out

    func signOut(completion: (@MainActor () -> Void)? = nil) {
        startSignOut { outcome in
            if outcome == .completed {
                completion?()
            }
        }
    }

    func signOut(completion: @escaping @MainActor (SignOutOutcome) -> Void) {
        startSignOut(completion: completion)
    }

    private func startSignOut(
        completion: (@MainActor (SignOutOutcome) -> Void)?
    ) {
        invalidateAsyncOperations()

        let state = SessionOperationRegistry.state(for: self)
        state.cancelFiniteSessionOperations()
        let operationID = state.beginSignOut(completion: completion)
        let generation = currentLifecycleGeneration

        refreshTimer?.invalidate()
        refreshTimer = nil
        loginPollTimer?.invalidate()
        loginPollTimer = nil
        isLoggedIn = false
        isAutoRefreshEnabled = nil
        lastRedirectAt = nil
        fiveHourPercent = nil
        sevenDayPercent = nil
        fiveHourResetsAt = nil
        sevenDayResetsAt = nil
        fiveHourResetsAtObservedAt = nil
        sevenDayResetsAtObservedAt = nil
        error = nil

        let logoutSnapshot = UsageSnapshot(
            timestamp: now(),
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
        dataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: Date.distantPast
        ) { [state] in
            dataStore.httpCookieStore.getAllCookies { cookies in
                deleteCookies(cookies, from: dataStore.httpCookieStore) {
                    Task { @MainActor [state] in
                        guard state.signOutID == operationID,
                              let owner = state.owner,
                              owner.isCurrentLifecycleGeneration(generation) else {
                            state.finishSignOut(id: operationID, outcome: .cancelled)
                            return
                        }
                        owner.loadUsagePage()
                        owner.startLoginPolling()
                        state.finishSignOut(id: operationID, outcome: .completed)
                    }
                }
            }
        }
    }
}
