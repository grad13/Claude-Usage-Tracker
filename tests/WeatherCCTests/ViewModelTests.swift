import XCTest
import WebKit
import WeatherCCShared
@testable import WeatherCC

// MARK: - ViewModelTests

@MainActor
final class ViewModelTests: XCTestCase {

    var stubFetcher: StubUsageFetcher!
    var settingsStore: InMemorySettingsStore!
    var usageStore: InMemoryUsageStore!
    var snapshotWriter: InMemorySnapshotWriter!
    var widgetReloader: InMemoryWidgetReloader!
    var tokenSync: InMemoryTokenSync!
    var loginItemManager: InMemoryLoginItemManager!

    override func setUp() {
        super.setUp()
        stubFetcher = StubUsageFetcher()
        settingsStore = InMemorySettingsStore()
        usageStore = InMemoryUsageStore()
        snapshotWriter = InMemorySnapshotWriter()
        widgetReloader = InMemoryWidgetReloader()
        tokenSync = InMemoryTokenSync()
        loginItemManager = InMemoryLoginItemManager()
    }

    func makeVM() -> UsageViewModel {
        UsageViewModel(
            fetcher: stubFetcher,
            settingsStore: settingsStore,
            usageStore: usageStore,
            snapshotWriter: snapshotWriter,
            widgetReloader: widgetReloader,
            tokenSync: tokenSync,
            loginItemManager: loginItemManager
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

    // MARK: - statusText Rounding

    func testStatusText_rounding() {
        let vm = makeVM()
        vm.fiveHourPercent = 99.5
        vm.sevenDayPercent = 0.4
        XCTAssertEqual(vm.statusText, "5h: 100% / 7d: 0%")
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

    // MARK: - timeProgress Clamping

    func testTimeProgress_clampedToZero() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(10 * 3600)
        let progress = UsageViewModel.timeProgress(
            resetsAt: resetsAt, windowSeconds: 5 * 3600, now: now
        )
        XCTAssertEqual(progress, 0.0, accuracy: 0.01)
    }

    // MARK: - timeProgress Edge Cases

    func testTimeProgress_resetsAtEqualsNow() {
        let now = Date()
        let progress = UsageViewModel.timeProgress(
            resetsAt: now, windowSeconds: 5 * 3600, now: now
        )
        XCTAssertEqual(progress, 1.0, accuracy: 0.01)
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

    // MARK: - Snapshot: init behavior (SQLite-based)

    /// init does NOT call saveAfterFetch — state row is only created on first successful fetch.
    func testInit_doesNotCallSaveAfterFetch() {
        usageStore.historyToReturn = []
        let vm = makeVM()

        let done = expectation(description: "init completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 2.0)

        XCTAssertTrue(snapshotWriter.savedFetches.isEmpty,
            "init must NOT call saveAfterFetch — data is not yet available")
        _ = vm
    }

    /// init → fetchPredict → updatePredict(nil, nil) is called.
    func testInit_callsUpdatePredict() {
        let vm = makeVM()

        let done = expectation(description: "init completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 2.0)

        XCTAssertFalse(snapshotWriter.savedPredicts.isEmpty,
            "init → fetchPredict should call updatePredict")
        let predict = snapshotWriter.savedPredicts.last!
        XCTAssertNil(predict.fiveHourCost, "No JSONL data → predict should be nil")
        XCTAssertNil(predict.sevenDayCost)
        _ = vm
    }
}
