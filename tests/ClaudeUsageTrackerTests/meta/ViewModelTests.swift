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
    func testWebView_usesAppSpecificDataStore() {
        let vm = UsageViewModel(webViewConfiguration: nil)
        let store = vm.webView.configuration.websiteDataStore
        XCTAssertNotEqual(store, WKWebsiteDataStore.default(),
                          "WebView should NOT use .default() (causes TCC prompt for cross-app data access)")
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
