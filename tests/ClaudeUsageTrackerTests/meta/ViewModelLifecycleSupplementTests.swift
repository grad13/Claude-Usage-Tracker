// meta: updated=2026-03-06 09:14 checked=-
// Supplement for: tests/ClaudeUsageTrackerTests/ViewModelTests.swift
// Source spec: _documents/spec/meta/viewmodel-lifecycle.md
// Covers: startAutoRefresh / restartAutoRefresh timer control, fetchSilently() vs fetch() diff

import XCTest
import WebKit
import ClaudeUsageTrackerShared
@testable import ClaudeUsageTracker

// MARK: - ViewModelLifecycleSupplementTests

@MainActor
final class ViewModelLifecycleSupplementTests: XCTestCase {

    var stubFetcher: StubUsageFetcher!
    var settingsStore: InMemorySettingsStore!
    var usageStore: InMemoryUsageStore!
    var widgetReloader: InMemoryWidgetReloader!
    var loginItemManager: InMemoryLoginItemManager!
    var alertChecker: MockAlertChecker!

    override func setUp() {
        super.setUp()
        stubFetcher = StubUsageFetcher()
        settingsStore = InMemorySettingsStore()
        usageStore = InMemoryUsageStore()
        widgetReloader = InMemoryWidgetReloader()
        loginItemManager = InMemoryLoginItemManager()
        alertChecker = MockAlertChecker()
    }

    func makeVM(
        timerScheduler: any ViewModelTimerScheduling = ManualViewModelTimerScheduler()
    ) -> UsageViewModel {
        ViewModelTestFactory.makeVM(
            fetcher: stubFetcher,
            settingsStore: settingsStore,
            usageStore: usageStore,
            widgetReloader: widgetReloader,
            loginItemManager: loginItemManager,
            alertChecker: alertChecker,
            startLifecycle: false,
            sleeper: { _ in },
            timerScheduler: timerScheduler
        )
    }

    // MARK: - startAutoRefresh: double-start prevention

    /// startAutoRefresh called twice must not create two timers.
    /// The injected scheduler makes timer ownership directly observable.
    func testStartAutoRefresh_doublyInvoked_doesNotDoubleFireOnTick() {
        var settings = AppSettings()
        settings.refreshIntervalMinutes = 1
        settingsStore.save(settings)

        let scheduler = ManualViewModelTimerScheduler()
        let vm = makeVM(timerScheduler: scheduler)
        vm.isLoggedIn = true
        vm.isAutoRefreshEnabled = true

        vm.startAutoRefresh()
        vm.startAutoRefresh() // second call must be a no-op

        XCTAssertEqual(scheduler.validTimers.count, 1,
                       "startAutoRefresh must keep exactly one refresh timer")
        XCTAssertEqual(scheduler.validTimers.first?.timeInterval, 60)
    }

    // MARK: - startAutoRefresh: disabled when refreshIntervalMinutes == 0

    /// When refreshIntervalMinutes is 0, startAutoRefresh must not schedule a timer.
    func testStartAutoRefresh_intervalZero_noTimerCreated() {
        var settings = AppSettings()
        settings.refreshIntervalMinutes = 0
        settingsStore.save(settings)

        let scheduler = ManualViewModelTimerScheduler()
        let vm = makeVM(timerScheduler: scheduler)
        vm.isLoggedIn = true
        vm.isAutoRefreshEnabled = true

        vm.startAutoRefresh()

        XCTAssertTrue(scheduler.timers.isEmpty,
                      "refreshIntervalMinutes == 0 must suppress timer creation")
    }

    // MARK: - startAutoRefresh: tick skipped when isAutoRefreshEnabled == false

    /// Spec: timer tick skips fetch when isAutoRefreshEnabled == false.
    /// The manual timer fires the tick without waiting for wall-clock time.
    func testStartAutoRefresh_tick_skipsWhenAutoRefreshDisabled() {
        var settings = AppSettings()
        settings.refreshIntervalMinutes = 1
        settingsStore.save(settings)

        let scheduler = ManualViewModelTimerScheduler()
        let vm = makeVM(timerScheduler: scheduler)
        vm.isLoggedIn = true
        vm.isAutoRefreshEnabled = false // disabled: tick must skip fetch

        vm.startAutoRefresh()
        XCTAssertEqual(scheduler.validTimers.count, 1)
        scheduler.validTimers[0].fire()

        XCTAssertEqual(stubFetcher.fetchCallCount, 0,
                       "Timer tick must skip fetch when isAutoRefreshEnabled == false")
    }

    // MARK: - restartAutoRefresh: invalidates existing timer and creates a new one

    /// restartAutoRefresh must invalidate any existing timer and, when isLoggedIn == true,
    /// start a new one. The scheduler exposes both timer identities and validity.
    func testRestartAutoRefresh_replacesExistingTimer() {
        var settings = AppSettings()
        settings.refreshIntervalMinutes = 1
        settingsStore.save(settings)

        let scheduler = ManualViewModelTimerScheduler()
        let vm = makeVM(timerScheduler: scheduler)
        vm.isLoggedIn = true
        vm.isAutoRefreshEnabled = true

        // Start initial timer.
        vm.startAutoRefresh()
        let firstTimer = scheduler.validTimers[0]

        // Restart via setRefreshInterval (calls restartAutoRefresh internally per spec).
        vm.setRefreshInterval(minutes: 2)

        // After restart the settings must reflect the new interval.
        XCTAssertEqual(vm.settings.refreshIntervalMinutes, 2,
                       "setRefreshInterval must persist the new interval")

        XCTAssertFalse(firstTimer.isValid)
        XCTAssertEqual(scheduler.validTimers.count, 1)
        XCTAssertEqual(scheduler.validTimers[0].timeInterval, 120)
    }

    // MARK: - restartAutoRefresh: does NOT start timer when isLoggedIn == false

    /// Spec: restartAutoRefresh → isLoggedIn == true → startAutoRefresh().
    /// When isLoggedIn == false, no new timer is started.
    func testRestartAutoRefresh_loggedOut_doesNotStartTimer() {
        var settings = AppSettings()
        settings.refreshIntervalMinutes = 1
        settingsStore.save(settings)

        let scheduler = ManualViewModelTimerScheduler()
        let vm = makeVM(timerScheduler: scheduler)
        vm.isLoggedIn = false
        vm.isAutoRefreshEnabled = true

        // restartAutoRefresh is invoked by setRefreshInterval.
        vm.setRefreshInterval(minutes: 1)

        XCTAssertTrue(scheduler.timers.isEmpty,
                      "restartAutoRefresh must not start a timer when logged out")
    }

    // MARK: - fetchSilently vs fetch(): error assignment gated on isLoggedIn

    /// Spec: fetchSilently sets self.error only when isLoggedIn == true.
    /// When isLoggedIn == false, a fetch error must be silently dropped.
    func testFetchSilently_loggedOut_doesNotSetError() {
        struct TestError: Error {}
        stubFetcher.fetchResult = .failure(TestError())

        let vm = makeVM()
        vm.isLoggedIn = false

        let done = expectation(description: "fetchSilently completes")
        vm.fetchSilently { outcome in
            XCTAssertEqual(outcome, .failure)
            done.fulfill()
        }
        wait(for: [done], timeout: 3.0)

        XCTAssertNil(vm.error,
                     "fetchSilently must not set error when isLoggedIn == false")
        _ = vm
    }

    /// Spec: fetchSilently sets self.error when isLoggedIn == true and fetch fails.
    func testFetchSilently_loggedIn_setsErrorOnFailure() {
        struct TestError: LocalizedError {
            var errorDescription: String? { "fetch failed" }
        }
        stubFetcher.fetchResult = .failure(TestError())

        let vm = makeVM()
        vm.isLoggedIn = true

        let done = expectation(description: "error becomes non-nil")
        vm.fetchSilently { outcome in
            XCTAssertEqual(outcome, .failure)
            done.fulfill()
        }
        wait(for: [done], timeout: 2.0)

        XCTAssertNotNil(vm.error,
                        "fetchSilently must set error when isLoggedIn == true and fetch fails")
        _ = vm
    }

    // MARK: - fetchSilently vs fetch(): authentication error disables auto-refresh

    /// Spec: both fetch() and fetchSilently() set isAutoRefreshEnabled = false on auth error.
    /// Auth error requires UsageFetchError with isAuthError == true (e.g., "Missing organization").
    func testFetchSilently_authError_disablesAutoRefresh() {
        // Must use UsageFetchError with isAuthError == true
        stubFetcher.fetchResult = .failure(UsageFetchError.scriptFailed("Missing organization"))

        let vm = makeVM()
        vm.isLoggedIn = true
        vm.isAutoRefreshEnabled = true

        let done = expectation(description: "isAutoRefreshEnabled becomes false")
        vm.fetchSilently { outcome in
            XCTAssertEqual(outcome, .authenticationRequired)
            done.fulfill()
        }
        wait(for: [done], timeout: 2.0)

        XCTAssertEqual(vm.isAutoRefreshEnabled, false,
                       "fetchSilently must set isAutoRefreshEnabled = false on auth error")
        _ = vm
    }

    // MARK: - fetch() vs fetchSilently(): fetch() always sets error regardless of login state

    /// Spec: fetch() always sets self.error on failure (no isLoggedIn guard).
    /// This distinguishes it from fetchSilently().
    func testFetch_loggedOut_setsErrorOnFailure() {
        struct TestError: LocalizedError {
            var errorDescription: String? { "manual fetch failed" }
        }
        stubFetcher.fetchResult = .failure(TestError())

        let vm = makeVM()
        vm.isLoggedIn = false

        let done = expectation(description: "error becomes non-nil")
        vm.fetch { outcome in
            XCTAssertEqual(outcome, .failure)
            done.fulfill()
        }
        wait(for: [done], timeout: 2.0)

        XCTAssertNotNil(vm.error,
                        "fetch() must always set error on failure, regardless of isLoggedIn")
        _ = vm
    }
}
