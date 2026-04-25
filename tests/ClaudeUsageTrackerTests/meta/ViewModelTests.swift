// meta: updated=2026-03-14 11:31 checked=-
import XCTest
import WebKit
import ClaudeUsageTrackerShared
@testable import ClaudeUsageTracker

// MARK: - ViewModelTests

@MainActor
final class ViewModelTests: XCTestCase {

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

    func makeVM() -> UsageViewModel {
        ViewModelTestFactory.makeVM(
            fetcher: stubFetcher,
            settingsStore: settingsStore,
            usageStore: usageStore,
            widgetReloader: widgetReloader,
            loginItemManager: loginItemManager,
            alertChecker: alertChecker
        )
    }

    // MARK: - WebView Data Store

    // Note: These tests use production config (webViewConfiguration: nil) to verify
    // the real data store behavior. Test VMs use nonPersistent() to avoid destroying
    // real session cookies during signOut() calls.
    func testWebView_usesDefaultDataStore() {
        let vm = UsageViewModel(webViewConfiguration: nil)
        let store = vm.webView.configuration.websiteDataStore
        XCTAssertEqual(store, WKWebsiteDataStore.default(),
                       "WebView should use .default() (managed by cookied daemon, survives PC reboot)")
    }

    func testWebView_dataStoreIsPersistent() {
        let vm = UsageViewModel(webViewConfiguration: nil)
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
        // 5h chart still uses loadHistory; 7d switched to loadCurrentWeeklySession.
        usageStore.historyToReturn = [dp1, dp2]
        usageStore.weeklySessionToReturn = UsageStore.WeeklySession(
            dataPoints: [dp1, dp2],
            startedAt: dp1.timestamp,
            resetsAt: Date().addingTimeInterval(6 * 24 * 3600)
        )

        let vm = makeVM()
        XCTAssertEqual(vm.fiveHourHistory.count, 2,
                       "init should load 5h history from injected store")
        XCTAssertEqual(vm.sevenDayHistory.count, 2,
                       "init should load 7d history via loadCurrentWeeklySession")
    }

    func testInit_emptyHistory() {
        usageStore.historyToReturn = []
        let vm = makeVM()
        XCTAssertTrue(vm.fiveHourHistory.isEmpty)
        XCTAssertTrue(vm.sevenDayHistory.isEmpty)
    }

    // MARK: - Alert Integration

    func testApplyResult_callsAlertChecker() {
        var settings = AppSettings()
        settings.weeklyAlertEnabled = true
        settings.weeklyAlertThreshold = 20
        settingsStore.save(settings)

        let vm = makeVM()

        var result = UsageResult()
        result.sevenDayPercent = 85.0
        result.sevenDayResetsAt = Date()
        result.fiveHourPercent = 50.0
        result.fiveHourResetsAt = Date()

        vm.applyResult(result)

        XCTAssertEqual(alertChecker.checkRecords.count, 1)
        XCTAssertEqual(alertChecker.checkRecords[0].result.sevenDayPercent, 85.0)
        XCTAssertEqual(alertChecker.checkRecords[0].settings.weeklyAlertEnabled, true)
    }

    func testApplyResult_multipleCallsCheckAlertEachTime() {
        let vm = makeVM()
        var result = UsageResult()
        result.sevenDayPercent = 50.0

        vm.applyResult(result)
        vm.applyResult(result)
        vm.applyResult(result)

        XCTAssertEqual(alertChecker.checkRecords.count, 3)
        _ = vm
    }
}
