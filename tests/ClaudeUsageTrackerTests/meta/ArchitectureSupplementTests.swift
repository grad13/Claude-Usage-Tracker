// meta: updated=2026-03-07 08:17 checked=-
import XCTest
@testable import ClaudeUsageTracker

// Supplement for: tests/ClaudeUsageTrackerTests/meta/ArchitectureViewModelStateTests.swift
// Spec: docs/spec/meta/architecture.md
//
// Coverage intent:
//   - Launch at Login (decision #13): SMAppService register/unregister via LoginItemManaging protocol
//   - Sign Out widget integration (decision #12): widgetReloader called during signOut
//
// Skip policy:
//   - Navigation Control (decision #8): decidePolicyFor is not implemented in WebViewCoordinator.
//     The spec describes pre/post login domain allow/deny rules, but no WKNavigationDelegate
//     policy method exists in the codebase. Cannot test non-existent code.
//   - Sign Out dataStore deletion (decision #12): WKWebsiteDataStore.removeData and
//     httpCookieStore.delete require WKWebView runtime. Only state resets and widget
//     integration are testable.

// MARK: - Launch at Login (Architecture Decision #13)
// spec: "Uses SMAppService.mainApp to toggle register/unregister."

@MainActor
final class ArchitectureLaunchAtLoginTests: XCTestCase {

    func makeVM(
        loginItemManager: InMemoryLoginItemManager = InMemoryLoginItemManager(),
        settingsStore: InMemorySettingsStore = InMemorySettingsStore()
    ) -> (UsageViewModel, InMemoryLoginItemManager, InMemorySettingsStore) {
        let vm = ViewModelTestFactory.makeVM(
            settingsStore: settingsStore,
            loginItemManager: loginItemManager
        )
        return (vm, loginItemManager, settingsStore)
    }

    // spec: "Uses SMAppService.mainApp to toggle register/unregister."
    // -> toggleStartAtLogin when OFF -> ON must call setEnabled(true) (register).
    func testToggleStartAtLogin_fromOffToOn_callsRegister() {
        let mgr = InMemoryLoginItemManager()
        let store = InMemorySettingsStore()
        store.current.startAtLogin = false
        let (vm, _, _) = makeVM(loginItemManager: mgr, settingsStore: store)

        vm.toggleStartAtLogin()

        XCTAssertEqual(
            mgr.lastEnabled, true,
            "toggleStartAtLogin OFF->ON must call setEnabled(true) — spec requires SMAppService.mainApp.register()"
        )
    }

    // spec: "Uses SMAppService.mainApp to toggle register/unregister."
    // -> toggleStartAtLogin when ON -> OFF must call setEnabled(false) (unregister).
    func testToggleStartAtLogin_fromOnToOff_callsUnregister() {
        let mgr = InMemoryLoginItemManager()
        let store = InMemorySettingsStore()
        store.current.startAtLogin = true
        let (vm, _, _) = makeVM(loginItemManager: mgr, settingsStore: store)

        // init calls syncLoginItem with startAtLogin=true, so reset counts
        mgr.enabledCallCount = 0
        mgr.disabledCallCount = 0

        vm.toggleStartAtLogin()

        XCTAssertEqual(
            mgr.lastEnabled, false,
            "toggleStartAtLogin ON->OFF must call setEnabled(false) — spec requires SMAppService.mainApp.unregister()"
        )
        XCTAssertEqual(
            mgr.disabledCallCount, 1,
            "unregister must be called exactly once"
        )
    }

    // spec: register/unregister toggle — failure must revert the setting.
    // -> If setEnabled throws, settings.startAtLogin must revert to its previous value.
    func testToggleStartAtLogin_failure_revertsSettingToOriginal() {
        let mgr = InMemoryLoginItemManager()
        let store = InMemorySettingsStore()
        store.current.startAtLogin = false
        let (vm, _, _) = makeVM(loginItemManager: mgr, settingsStore: store)

        mgr.shouldThrow = NSError(domain: "test", code: 1, userInfo: nil)
        vm.toggleStartAtLogin()

        XCTAssertFalse(
            vm.settings.startAtLogin,
            "On failure, startAtLogin must revert to original value (false) — UI must reflect actual system state"
        )
    }

    // spec: register/unregister toggle — failure must set error message.
    func testToggleStartAtLogin_failure_setsErrorMessage() {
        let mgr = InMemoryLoginItemManager()
        let store = InMemorySettingsStore()
        store.current.startAtLogin = false
        let (vm, _, _) = makeVM(loginItemManager: mgr, settingsStore: store)

        mgr.shouldThrow = NSError(domain: "test", code: 42, userInfo: nil)
        vm.toggleStartAtLogin()

        XCTAssertNotNil(
            vm.error,
            "On failure, error must be set so the user can see what went wrong"
        )
    }

    // spec: setting is persisted via settingsStore.save after toggle.
    func testToggleStartAtLogin_success_persistsSetting() {
        let mgr = InMemoryLoginItemManager()
        let store = InMemorySettingsStore()
        store.current.startAtLogin = false
        let (vm, _, _) = makeVM(loginItemManager: mgr, settingsStore: store)

        vm.toggleStartAtLogin()

        XCTAssertTrue(
            store.current.startAtLogin,
            "Toggled setting must be persisted via settingsStore.save()"
        )
    }
}

// MARK: - Sign Out State Reset (Architecture Decision #12)
// spec: "1. Delete all data types from webView.configuration.websiteDataStore
//        2. Retrieve all cookies via httpCookieStore.getAllCookies and delete each individually
//        3. Reload the usage page"
// Only state resets and widget integration are testable without WKWebView runtime.

@MainActor
final class ArchitectureSignOutStateTests: XCTestCase {

    // spec: signOut resets all usage data — fiveHourPercent, sevenDayPercent,
    //       fiveHourResetsAt, sevenDayResetsAt, error, isLoggedIn, isAutoRefreshEnabled.
    func testSignOut_resetsAllPublishedState() {
        let vm = ViewModelTestFactory.makeVM()
        vm.isLoggedIn = true
        vm.isAutoRefreshEnabled = true
        vm.fiveHourPercent = 50.0
        vm.sevenDayPercent = 30.0
        vm.fiveHourResetsAt = Date()
        vm.sevenDayResetsAt = Date()
        vm.error = "some error"

        vm.signOut()

        XCTAssertFalse(vm.isLoggedIn, "signOut must reset isLoggedIn to false")
        XCTAssertNil(vm.isAutoRefreshEnabled, "signOut must reset isAutoRefreshEnabled to nil (undetermined)")
        XCTAssertNil(vm.fiveHourPercent, "signOut must reset fiveHourPercent to nil")
        XCTAssertNil(vm.sevenDayPercent, "signOut must reset sevenDayPercent to nil")
        XCTAssertNil(vm.fiveHourResetsAt, "signOut must reset fiveHourResetsAt to nil")
        XCTAssertNil(vm.sevenDayResetsAt, "signOut must reset sevenDayResetsAt to nil")
        XCTAssertNil(vm.error, "signOut must reset error to nil")
    }

    // spec: Sign Out triggers widget reload so widget reflects signed-out state immediately.
    func testSignOut_triggersWidgetReload() {
        let reloader = InMemoryWidgetReloader()
        let vm = ViewModelTestFactory.makeVM(widgetReloader: reloader)
        vm.isLoggedIn = true

        vm.signOut()

        XCTAssertGreaterThanOrEqual(
            reloader.reloadCount, 1,
            "signOut must call widgetReloader.reloadAllTimelines() — widget must update to reflect signed-out state"
        )
    }
}
