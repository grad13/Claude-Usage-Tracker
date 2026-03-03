// Supplement for: tests/ClaudeUsageTrackerTests/ViewModelTests+Settings.swift

import XCTest
@testable import ClaudeUsageTracker

extension ViewModelTests {

    // MARK: - setWeeklyAlertEnabled

    func testSetWeeklyAlertEnabled() {
        let vm = makeVM()
        vm.setWeeklyAlertEnabled(true)
        XCTAssertTrue(vm.settings.weeklyAlertEnabled)
        XCTAssertTrue(settingsStore.current.weeklyAlertEnabled,
                      "Should persist to injected store")
    }

    // MARK: - setWeeklyAlertThreshold

    func testSetWeeklyAlertThreshold() {
        let vm = makeVM()
        vm.setWeeklyAlertThreshold(50)
        XCTAssertEqual(vm.settings.weeklyAlertThreshold, 50)
        XCTAssertEqual(settingsStore.current.weeklyAlertThreshold, 50,
                       "Should persist to injected store")
    }

    // MARK: - setHourlyAlertEnabled

    func testSetHourlyAlertEnabled() {
        let vm = makeVM()
        vm.setHourlyAlertEnabled(true)
        XCTAssertTrue(vm.settings.hourlyAlertEnabled)
        XCTAssertTrue(settingsStore.current.hourlyAlertEnabled,
                      "Should persist to injected store")
    }

    // MARK: - setHourlyAlertThreshold

    func testSetHourlyAlertThreshold() {
        let vm = makeVM()
        vm.setHourlyAlertThreshold(50)
        XCTAssertEqual(vm.settings.hourlyAlertThreshold, 50)
        XCTAssertEqual(settingsStore.current.hourlyAlertThreshold, 50,
                       "Should persist to injected store")
    }

    // MARK: - setDailyAlertEnabled

    func testSetDailyAlertEnabled() {
        let vm = makeVM()
        vm.setDailyAlertEnabled(true)
        XCTAssertTrue(vm.settings.dailyAlertEnabled)
        XCTAssertTrue(settingsStore.current.dailyAlertEnabled,
                      "Should persist to injected store")
    }

    // MARK: - setDailyAlertThreshold

    func testSetDailyAlertThreshold() {
        let vm = makeVM()
        vm.setDailyAlertThreshold(30)
        XCTAssertEqual(vm.settings.dailyAlertThreshold, 30)
        XCTAssertEqual(settingsStore.current.dailyAlertThreshold, 30,
                       "Should persist to injected store")
    }

    // MARK: - setDailyAlertDefinition

    func testSetDailyAlertDefinition() {
        let vm = makeVM()
        vm.setDailyAlertDefinition(.session)
        XCTAssertEqual(vm.settings.dailyAlertDefinition, .session)
        XCTAssertEqual(settingsStore.current.dailyAlertDefinition, .session,
                       "Should persist to injected store")
    }
}
