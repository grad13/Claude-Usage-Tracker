import XCTest
import WebKit
@testable import WeatherCC

@MainActor
final class ViewModelTests: XCTestCase {

    // MARK: - statusText

    func testStatusText_noData() {
        let vm = UsageViewModel()
        XCTAssertEqual(vm.statusText, "5h: -- / 7d: --")
    }

    func testStatusText_withData() {
        let vm = UsageViewModel()
        vm.fiveHourPercent = 42.7
        vm.sevenDayPercent = 15.3
        XCTAssertEqual(vm.statusText, "5h: 43% / 7d: 15%")
    }

    func testStatusText_partialData_fiveHourOnly() {
        let vm = UsageViewModel()
        vm.fiveHourPercent = 8.0
        XCTAssertEqual(vm.statusText, "5h: 8% / 7d: --")
    }

    func testStatusText_partialData_sevenDayOnly() {
        let vm = UsageViewModel()
        vm.sevenDayPercent = 6.0
        XCTAssertEqual(vm.statusText, "5h: -- / 7d: 6%")
    }

    // MARK: - toggleStartAtLogin

    func testToggleStartAtLogin() {
        let vm = UsageViewModel()
        let before = vm.settings.startAtLogin
        vm.toggleStartAtLogin()
        XCTAssertNotEqual(vm.settings.startAtLogin, before, "toggleStartAtLogin should flip the value")
    }

    func testToggleStartAtLogin_persists() {
        let vm = UsageViewModel()
        let original = vm.settings.startAtLogin
        vm.toggleStartAtLogin()

        let loaded = SettingsStore.load()
        XCTAssertEqual(loaded.startAtLogin, !original, "Toggled value should be persisted to settings file")

        // Clean up: restore original
        vm.toggleStartAtLogin()
    }

    // MARK: - setRefreshInterval

    func testSetRefreshInterval() {
        let vm = UsageViewModel()
        vm.setRefreshInterval(minutes: 20)
        XCTAssertEqual(vm.settings.refreshIntervalMinutes, 20)
    }

    func testSetRefreshInterval_persists() {
        let vm = UsageViewModel()
        let original = vm.settings.refreshIntervalMinutes
        vm.setRefreshInterval(minutes: 42)

        let loaded = SettingsStore.load()
        XCTAssertEqual(loaded.refreshIntervalMinutes, 42)

        // Clean up: restore original
        vm.setRefreshInterval(minutes: original)
    }

    // MARK: - WebView Data Store

    func testWebView_usesDefaultDataStore() {
        let vm = UsageViewModel()
        let store = vm.webView.configuration.websiteDataStore
        // App Sandbox disabled + .default() for reliable cookie persistence across restarts
        XCTAssertEqual(store, WKWebsiteDataStore.default(),
                       "WebView should use .default() data store (App Sandbox disabled for persistence)")
    }

    func testWebView_dataStoreIsPersistent() {
        let vm = UsageViewModel()
        let store = vm.webView.configuration.websiteDataStore
        XCTAssertTrue(store.isPersistent,
                      "Data store must be persistent for cookie retention across restarts")
    }

    // MARK: - signOut

    func testSignOut_clearsState() {
        let vm = UsageViewModel()
        vm.fiveHourPercent = 50.0
        vm.sevenDayPercent = 30.0
        vm.fiveHourResetsAt = Date()
        vm.sevenDayResetsAt = Date()
        vm.isLoggedIn = true
        vm.error = "some error"

        vm.signOut()

        XCTAssertNil(vm.fiveHourPercent)
        XCTAssertNil(vm.sevenDayPercent)
        XCTAssertNil(vm.fiveHourResetsAt)
        XCTAssertNil(vm.sevenDayResetsAt)
        XCTAssertFalse(vm.isLoggedIn)
        XCTAssertNil(vm.error)
    }

    func testSignOut_setsLoggedInFalse() {
        let vm = UsageViewModel()
        vm.isLoggedIn = true
        vm.signOut()
        XCTAssertFalse(vm.isLoggedIn, "signOut should set isLoggedIn to false")
    }

    // MARK: - timeProgress

    func testTimeProgress_midWindow() {
        // 5h window, 3h remaining → elapsed 2h out of 5h → progress = 0.4
        let now = Date()
        let resetsAt = now.addingTimeInterval(3 * 3600) // 3h from now
        let progress = UsageViewModel.timeProgress(
            resetsAt: resetsAt, windowSeconds: 5 * 3600, now: now
        )
        XCTAssertEqual(progress, 0.4, accuracy: 0.01)
    }

    func testTimeProgress_nil() {
        let progress = UsageViewModel.timeProgress(
            resetsAt: nil, windowSeconds: 5 * 3600
        )
        XCTAssertEqual(progress, 0.0)
    }

    func testTimeProgress_expired() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(-100) // in the past
        let progress = UsageViewModel.timeProgress(
            resetsAt: resetsAt, windowSeconds: 5 * 3600, now: now
        )
        XCTAssertEqual(progress, 1.0)
    }

    func testTimeProgress_justStarted() {
        // Window just started: resetsAt is exactly windowSeconds from now
        let now = Date()
        let resetsAt = now.addingTimeInterval(5 * 3600)
        let progress = UsageViewModel.timeProgress(
            resetsAt: resetsAt, windowSeconds: 5 * 3600, now: now
        )
        XCTAssertEqual(progress, 0.0, accuracy: 0.01)
    }

    // MARK: - remainingTimeText (delegates to DisplayHelpers)

    func testRemainingTimeText_nilReturnsNil() {
        let vm = UsageViewModel()
        XCTAssertNil(vm.remainingTimeText(for: nil))
    }

    func testRemainingTimeText_delegatesToDisplayHelpers() {
        let vm = UsageViewModel()
        let resetsAt = Date().addingTimeInterval(2 * 3600 + 15 * 60 + 30)
        let text = vm.remainingTimeText(for: resetsAt)
        // Should match DisplayHelpers output (confirms delegation)
        XCTAssertEqual(text, "2h 15m")
    }
}
