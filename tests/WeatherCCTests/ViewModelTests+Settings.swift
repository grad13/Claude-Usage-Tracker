import XCTest
@testable import WeatherCC

// MARK: - ViewModelTests + Settings

extension ViewModelTests {

    // MARK: - toggleStartAtLogin

    func testToggleStartAtLogin_callsRegister() {
        let vm = makeVM()
        XCTAssertFalse(vm.settings.startAtLogin) // default is false
        vm.toggleStartAtLogin()
        XCTAssertTrue(vm.settings.startAtLogin)
        XCTAssertEqual(loginItemManager.enabledCallCount, 1,
            "toggleStartAtLogin ON must call setEnabled(true)")
        XCTAssertEqual(loginItemManager.lastEnabled, true)
    }

    func testToggleStartAtLogin_callsUnregister() {
        settingsStore.current.startAtLogin = true
        let vm = makeVM()
        // init calls syncLoginItem → register
        let registerBefore = loginItemManager.enabledCallCount
        vm.toggleStartAtLogin()
        XCTAssertFalse(vm.settings.startAtLogin)
        XCTAssertEqual(loginItemManager.disabledCallCount, 1,
            "toggleStartAtLogin OFF must call setEnabled(false)")
        // register count should not increase from toggle
        XCTAssertEqual(loginItemManager.enabledCallCount, registerBefore)
    }

    func testToggleStartAtLogin_persists() {
        let vm = makeVM()
        vm.toggleStartAtLogin()
        XCTAssertTrue(settingsStore.current.startAtLogin,
            "Toggled value should be persisted to settings store")
    }

    func testToggleStartAtLogin_registerFails_revertsSettingAndSetsError() {
        let vm = makeVM()
        loginItemManager.shouldThrow = NSError(
            domain: "SMAppServiceErrorDomain", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Operation not permitted"])
        vm.toggleStartAtLogin()
        // Setting must revert to false (original value) because register failed.
        XCTAssertFalse(vm.settings.startAtLogin,
            "Setting must revert when SMAppService.register() fails")
        XCTAssertFalse(settingsStore.current.startAtLogin,
            "Reverted setting must be persisted")
        XCTAssertNotNil(vm.error,
            "Error must be surfaced to user, not silently swallowed")
    }

    func testInit_syncLoginItem_registersWhenSettingIsTrue() {
        settingsStore.current.startAtLogin = true
        let vm = makeVM()
        XCTAssertEqual(loginItemManager.enabledCallCount, 1,
            "init must call setEnabled(true) when startAtLogin is true")
        _ = vm
    }

    func testInit_syncLoginItem_failure_revertsSettingAndSetsError() {
        settingsStore.current.startAtLogin = true
        loginItemManager.shouldThrow = NSError(
            domain: "SMAppServiceErrorDomain", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Operation not permitted"])
        let vm = makeVM()

        let done = expectation(description: "init")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 2.0)

        XCTAssertFalse(vm.settings.startAtLogin,
            "init must revert startAtLogin when register fails")
        XCTAssertFalse(settingsStore.current.startAtLogin,
            "Reverted setting must be persisted")
        XCTAssertNotNil(vm.error,
            "init login item failure must be surfaced as error")
    }

    // MARK: - setRefreshInterval

    func testSetRefreshInterval() {
        let vm = makeVM()
        vm.setRefreshInterval(minutes: 20)
        XCTAssertEqual(vm.settings.refreshIntervalMinutes, 20)
    }

    func testSetRefreshInterval_persists() {
        let vm = makeVM()
        vm.setRefreshInterval(minutes: 42)
        XCTAssertEqual(settingsStore.current.refreshIntervalMinutes, 42,
                       "Interval should be persisted to settings store")
    }

    // MARK: - Settings Methods (verify they persist to injected store, NOT production)

    func testSetShowHourlyGraph() {
        let vm = makeVM()
        vm.setShowHourlyGraph(false)
        XCTAssertFalse(vm.settings.showHourlyGraph)
        XCTAssertFalse(settingsStore.current.showHourlyGraph,
                       "Should persist to injected store")
    }

    func testSetShowWeeklyGraph() {
        let vm = makeVM()
        vm.setShowWeeklyGraph(false)
        XCTAssertFalse(vm.settings.showWeeklyGraph)
        XCTAssertFalse(settingsStore.current.showWeeklyGraph,
                       "Should persist to injected store")
    }

    func testSetChartWidth() {
        let vm = makeVM()
        vm.setChartWidth(72)
        XCTAssertEqual(vm.settings.chartWidth, 72)
        XCTAssertEqual(settingsStore.current.chartWidth, 72,
                       "Should persist to injected store")
    }

    func testSetHourlyColorPreset() {
        let vm = makeVM()
        vm.setHourlyColorPreset(.green)
        XCTAssertEqual(vm.settings.hourlyColorPreset, .green)
        XCTAssertEqual(settingsStore.current.hourlyColorPreset, .green,
                       "Should persist to injected store")
    }

    func testSetWeeklyColorPreset() {
        let vm = makeVM()
        vm.setWeeklyColorPreset(.purple)
        XCTAssertEqual(vm.settings.weeklyColorPreset, .purple)
        XCTAssertEqual(settingsStore.current.weeklyColorPreset, .purple,
                       "Should persist to injected store")
    }
}
