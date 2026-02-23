import XCTest
import WebKit
import WeatherCCShared
@testable import WeatherCC

// MARK: - In-Memory Test Implementations

final class InMemorySettingsStore: SettingsStoring {
    var current = AppSettings()
    func load() -> AppSettings { current }
    func save(_ settings: AppSettings) { current = settings }
}

final class InMemoryUsageStore: UsageStoring {
    var savedResults: [UsageResult] = []
    var historyToReturn: [UsageStore.DataPoint] = []
    func save(_ result: UsageResult) { savedResults.append(result) }
    func loadHistory(windowSeconds: TimeInterval) -> [UsageStore.DataPoint] { historyToReturn }
}

final class InMemorySnapshotWriter: SnapshotWriting {
    var savedSnapshots: [UsageSnapshot] = []
    func save(_ snapshot: UsageSnapshot) { savedSnapshots.append(snapshot) }
}

final class InMemoryTokenSync: TokenSyncing, @unchecked Sendable {
    func sync(directories: [URL]) {}
    func loadRecords(since cutoff: Date) -> [TokenRecord] { [] }
}

// MARK: - ViewModelTests

@MainActor
final class ViewModelTests: XCTestCase {

    private var settingsStore: InMemorySettingsStore!
    private var usageStore: InMemoryUsageStore!
    private var snapshotWriter: InMemorySnapshotWriter!
    private var tokenSync: InMemoryTokenSync!

    override func setUp() {
        super.setUp()
        settingsStore = InMemorySettingsStore()
        usageStore = InMemoryUsageStore()
        snapshotWriter = InMemorySnapshotWriter()
        tokenSync = InMemoryTokenSync()
    }

    private func makeVM() -> UsageViewModel {
        UsageViewModel(
            settingsStore: settingsStore,
            usageStore: usageStore,
            snapshotWriter: snapshotWriter,
            tokenSync: tokenSync
        )
    }

    // MARK: - statusText

    func testStatusText_noData() {
        let vm = makeVM()
        XCTAssertEqual(vm.statusText, "5h: -- / 7d: --")
    }

    func testStatusText_withData() {
        let vm = makeVM()
        vm.fiveHourPercent = 42.7
        vm.sevenDayPercent = 15.3
        XCTAssertEqual(vm.statusText, "5h: 43% / 7d: 15%")
    }

    func testStatusText_partialData_fiveHourOnly() {
        let vm = makeVM()
        vm.fiveHourPercent = 8.0
        XCTAssertEqual(vm.statusText, "5h: 8% / 7d: --")
    }

    func testStatusText_partialData_sevenDayOnly() {
        let vm = makeVM()
        vm.sevenDayPercent = 6.0
        XCTAssertEqual(vm.statusText, "5h: -- / 7d: 6%")
    }

    // MARK: - toggleStartAtLogin

    func testToggleStartAtLogin() {
        let vm = makeVM()
        let before = vm.settings.startAtLogin
        vm.toggleStartAtLogin()
        XCTAssertNotEqual(vm.settings.startAtLogin, before, "toggleStartAtLogin should flip the value")
    }

    func testToggleStartAtLogin_persists() {
        let vm = makeVM()
        let original = vm.settings.startAtLogin
        vm.toggleStartAtLogin()
        XCTAssertEqual(settingsStore.current.startAtLogin, !original,
                       "Toggled value should be persisted to settings store")
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

    // MARK: - WebView Data Store

    func testWebView_usesAppSpecificDataStore() {
        let vm = makeVM()
        let store = vm.webView.configuration.websiteDataStore
        XCTAssertNotEqual(store, WKWebsiteDataStore.default(),
                          "WebView should NOT use .default() (causes TCC prompt for cross-app data access)")
    }

    func testWebView_dataStoreIsPersistent() {
        let vm = makeVM()
        let store = vm.webView.configuration.websiteDataStore
        XCTAssertTrue(store.isPersistent,
                      "Data store must be persistent for cookie retention across restarts")
    }

    // MARK: - signOut

    func testSignOut_clearsState() {
        let vm = makeVM()
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
        let vm = makeVM()
        vm.isLoggedIn = true
        vm.signOut()
        XCTAssertFalse(vm.isLoggedIn, "signOut should set isLoggedIn to false")
    }

    // MARK: - timeProgress

    func testTimeProgress_midWindow() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3 * 3600)
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
        let resetsAt = now.addingTimeInterval(-100)
        let progress = UsageViewModel.timeProgress(
            resetsAt: resetsAt, windowSeconds: 5 * 3600, now: now
        )
        XCTAssertEqual(progress, 1.0)
    }

    func testTimeProgress_justStarted() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(5 * 3600)
        let progress = UsageViewModel.timeProgress(
            resetsAt: resetsAt, windowSeconds: 5 * 3600, now: now
        )
        XCTAssertEqual(progress, 0.0, accuracy: 0.01)
    }

    // MARK: - remainingTimeText

    func testRemainingTimeText_nilReturnsNil() {
        let vm = makeVM()
        XCTAssertNil(vm.remainingTimeText(for: nil))
    }

    func testRemainingTimeText_delegatesToDisplayHelpers() {
        let vm = makeVM()
        let resetsAt = Date().addingTimeInterval(2 * 3600 + 15 * 60 + 30)
        let text = vm.remainingTimeText(for: resetsAt)
        XCTAssertEqual(text, "2h 15m")
    }

    // MARK: - signOut clears predict

    func testSignOut_clearsPredictCost() {
        let vm = makeVM()
        vm.predictFiveHourCost = 1.23
        vm.predictSevenDayCost = 4.56
        vm.signOut()
        XCTAssertNil(vm.predictFiveHourCost, "signOut should clear predictFiveHourCost")
        XCTAssertNil(vm.predictSevenDayCost, "signOut should clear predictSevenDayCost")
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

    // MARK: - statusText Rounding

    func testStatusText_rounding() {
        let vm = makeVM()
        vm.fiveHourPercent = 99.5
        vm.sevenDayPercent = 0.4
        XCTAssertEqual(vm.statusText, "5h: 100% / 7d: 0%")
    }

    // MARK: - timeProgress Clamping

    func testTimeProgress_clampedToZero() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(10 * 3600)
        let progress = UsageViewModel.timeProgress(
            resetsAt: resetsAt, windowSeconds: 5 * 3600, now: now
        )
        XCTAssertEqual(progress, 0.0, accuracy: 0.01)
    }

    // MARK: - Computed Property: fiveHourTimeProgress / sevenDayTimeProgress

    func testFiveHourTimeProgress_usesResetsAt() {
        let vm = makeVM()
        XCTAssertEqual(vm.fiveHourTimeProgress, 0.0)
        vm.fiveHourResetsAt = Date().addingTimeInterval(3 * 3600)
        XCTAssertEqual(vm.fiveHourTimeProgress, 0.4, accuracy: 0.05)
    }

    func testSevenDayTimeProgress_usesResetsAt() {
        let vm = makeVM()
        XCTAssertEqual(vm.sevenDayTimeProgress, 0.0)
        vm.sevenDayResetsAt = Date().addingTimeInterval(3.5 * 24 * 3600)
        XCTAssertEqual(vm.sevenDayTimeProgress, 0.5, accuracy: 0.05)
    }

    // MARK: - closePopup

    func testClosePopup_clearsPopupWebView() {
        let vm = makeVM()
        let popup = WKWebView(frame: .zero)
        vm.popupWebView = popup
        XCTAssertNotNil(vm.popupWebView)
        vm.closePopup()
        XCTAssertNil(vm.popupWebView)
    }

    func testClosePopup_noPopup_doesNotCrash() {
        let vm = makeVM()
        XCTAssertNil(vm.popupWebView)
        vm.closePopup()
        XCTAssertNil(vm.popupWebView)
    }

    // MARK: - statusText Exact Boundaries

    func testStatusText_exactZeroPercent() {
        let vm = makeVM()
        vm.fiveHourPercent = 0.0
        vm.sevenDayPercent = 0.0
        XCTAssertEqual(vm.statusText, "5h: 0% / 7d: 0%")
    }

    func testStatusText_exactHundredPercent() {
        let vm = makeVM()
        vm.fiveHourPercent = 100.0
        vm.sevenDayPercent = 100.0
        XCTAssertEqual(vm.statusText, "5h: 100% / 7d: 100%")
    }

    // MARK: - timeProgress Edge Cases

    func testTimeProgress_resetsAtEqualsNow() {
        let now = Date()
        let progress = UsageViewModel.timeProgress(
            resetsAt: now, windowSeconds: 5 * 3600, now: now
        )
        XCTAssertEqual(progress, 1.0, accuracy: 0.01)
    }

    // MARK: - fiveHourRemainingText / sevenDayRemainingText

    func testFiveHourRemainingText_nil() {
        let vm = makeVM()
        XCTAssertNil(vm.fiveHourRemainingText)
    }

    func testSevenDayRemainingText_nil() {
        let vm = makeVM()
        XCTAssertNil(vm.sevenDayRemainingText)
    }

    func testFiveHourRemainingText_withDate() {
        let vm = makeVM()
        vm.fiveHourResetsAt = Date().addingTimeInterval(2 * 3600 + 30 * 60)
        let text = vm.fiveHourRemainingText
        XCTAssertNotNil(text)
        XCTAssertTrue(text!.contains("h"))
    }

    // MARK: - reloadHistory (via init → InMemoryUsageStore)

    func testInit_loadsHistoryFromStore() {
        let dp1 = UsageStore.DataPoint(
            timestamp: Date().addingTimeInterval(-3600),
            fiveHourPercent: 10.0, sevenDayPercent: 5.0
        )
        let dp2 = UsageStore.DataPoint(
            timestamp: Date(),
            fiveHourPercent: 20.0, sevenDayPercent: 10.0
        )
        usageStore.historyToReturn = [dp1, dp2]

        let vm = makeVM()
        XCTAssertEqual(vm.fiveHourHistory.count, 2,
                       "init should load history from injected store")
        XCTAssertEqual(vm.sevenDayHistory.count, 2)
    }

    func testInit_emptyHistory() {
        usageStore.historyToReturn = []
        let vm = makeVM()
        XCTAssertTrue(vm.fiveHourHistory.isEmpty)
        XCTAssertTrue(vm.sevenDayHistory.isEmpty)
    }

    // MARK: - Snapshot writing: compactMap filters NIL data points

    func testSnapshot_filtersNilFiveHourPercent() {
        let now = Date()
        usageStore.historyToReturn = [
            UsageStore.DataPoint(timestamp: now.addingTimeInterval(-120),
                                fiveHourPercent: nil, sevenDayPercent: 10.0),
            UsageStore.DataPoint(timestamp: now.addingTimeInterval(-60),
                                fiveHourPercent: 25.0, sevenDayPercent: nil),
            UsageStore.DataPoint(timestamp: now,
                                fiveHourPercent: 30.0, sevenDayPercent: 20.0),
        ]

        let vm = makeVM()
        // Wait for fetchPredict → writeSnapshot async task
        let expectation = expectation(description: "snapshot written")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        guard let snapshot = snapshotWriter.savedSnapshots.last else {
            XCTFail("Expected at least one snapshot to be written")
            return
        }

        // fiveHourHistory: should exclude the first dp (nil fiveHourPercent)
        XCTAssertEqual(snapshot.fiveHourHistory.count, 2,
                       "compactMap should filter out DataPoints with nil fiveHourPercent")
        XCTAssertEqual(snapshot.fiveHourHistory[0].percent, 25.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.fiveHourHistory[1].percent, 30.0, accuracy: 0.001)

        // sevenDayHistory: should exclude the second dp (nil sevenDayPercent)
        XCTAssertEqual(snapshot.sevenDayHistory.count, 2,
                       "compactMap should filter out DataPoints with nil sevenDayPercent")
        XCTAssertEqual(snapshot.sevenDayHistory[0].percent, 10.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.sevenDayHistory[1].percent, 20.0, accuracy: 0.001)
    }

    func testSnapshot_allNilPercents_emptyHistory() {
        usageStore.historyToReturn = [
            UsageStore.DataPoint(timestamp: Date(),
                                fiveHourPercent: nil, sevenDayPercent: nil),
        ]

        let vm = makeVM()
        let expectation = expectation(description: "snapshot written")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        guard let snapshot = snapshotWriter.savedSnapshots.last else {
            XCTFail("Expected snapshot")
            return
        }
        XCTAssertTrue(snapshot.fiveHourHistory.isEmpty,
                      "All nil fiveHourPercent → empty history")
        XCTAssertTrue(snapshot.sevenDayHistory.isEmpty,
                      "All nil sevenDayPercent → empty history")
    }

    // MARK: - Snapshot isLoggedIn state

    func testSnapshot_reflectsLoggedInState() {
        let vm = makeVM()
        // Initially not logged in
        let expectation = expectation(description: "snapshot written")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        guard let snapshot = snapshotWriter.savedSnapshots.last else {
            XCTFail("Expected snapshot")
            return
        }
        XCTAssertFalse(snapshot.isLoggedIn,
                       "Snapshot should reflect current isLoggedIn state")
    }

    // MARK: - sevenDayRemainingText with date

    func testSevenDayRemainingText_withDate() {
        let vm = makeVM()
        vm.sevenDayResetsAt = Date().addingTimeInterval(3 * 24 * 3600 + 2 * 3600)
        let text = vm.sevenDayRemainingText
        XCTAssertNotNil(text)
        XCTAssertTrue(text!.contains("d") || text!.contains("h"))
    }

    // MARK: - remainingTimeText: past date

    func testRemainingTimeText_pastDate() {
        let vm = makeVM()
        let text = vm.remainingTimeText(for: Date().addingTimeInterval(-100))
        // Past date: DisplayHelpers returns "0m" or similar
        XCTAssertNotNil(text, "Past date should still return a string, not nil")
    }
}
