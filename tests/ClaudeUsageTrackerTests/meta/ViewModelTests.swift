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

    func testApplyResult_freshExactSevenDayResetIsNotOverwrittenByRoundedSession() {
        let roundedSessionReset = Date(timeIntervalSince1970: 1_787_025_600)
        let exactAPIReset = Date(timeIntervalSince1970: 1_787_023_269.125)
        let observedAt = Date(timeIntervalSince1970: 1_786_450_123.875)
        let point = UsageStore.DataPoint(
            timestamp: observedAt.addingTimeInterval(-60),
            fiveHourPercent: 20.0,
            sevenDayPercent: 10.0,
            sevenDayResetsAt: roundedSessionReset
        )
        usageStore.weeklySessionToReturn = UsageStore.WeeklySession(
            dataPoints: [point],
            startedAt: point.timestamp,
            resetsAt: roundedSessionReset
        )
        let vm = makeVM()
        XCTAssertEqual(vm.sevenDayResetsAt, roundedSessionReset,
                       "Initialization may use the normalized session as legacy fallback")

        vm.applyResult(UsageResultFactory.make(
            sevenDayPercent: 11.0,
            sevenDayResetsAt: exactAPIReset,
            resetTimesObservedAt: observedAt
        ))

        XCTAssertEqual(vm.sevenDayResetsAt, exactAPIReset,
                       "reloadHistory must not replace a fresh API value with session identity")
        XCTAssertEqual(vm.sevenDayResetsAtObservedAt, observedAt)
        XCTAssertEqual(usageStore.savedResults.last?.sevenDayResetsAt, exactAPIReset)
    }

    func testApplyResult_tracksObservationFreshnessIndependentlyPerWindow() {
        let vm = makeVM()
        let firstObservedAt = Date(timeIntervalSince1970: 200)
        let staleObservedAt = Date(timeIntervalSince1970: 100)
        let newerFiveHourObservedAt = Date(timeIntervalSince1970: 300)
        let initialFiveHourReset = Date(timeIntervalSince1970: 1_000)
        let initialSevenDayReset = Date(timeIntervalSince1970: 2_000)

        vm.applyResult(UsageResultFactory.make(
            fiveHourPercent: 10.0,
            sevenDayPercent: 20.0,
            fiveHourResetsAt: initialFiveHourReset,
            sevenDayResetsAt: initialSevenDayReset,
            resetTimesObservedAt: firstObservedAt
        ))
        vm.applyResult(UsageResultFactory.make(
            fiveHourPercent: 11.0,
            sevenDayPercent: 21.0,
            fiveHourResetsAt: Date(timeIntervalSince1970: 900),
            sevenDayResetsAt: Date(timeIntervalSince1970: 1_900),
            resetTimesObservedAt: staleObservedAt
        ))

        XCTAssertEqual(vm.fiveHourResetsAt, initialFiveHourReset)
        XCTAssertEqual(vm.sevenDayResetsAt, initialSevenDayReset)
        XCTAssertEqual(vm.fiveHourResetsAtObservedAt, firstObservedAt)
        XCTAssertEqual(vm.sevenDayResetsAtObservedAt, firstObservedAt)

        let newerFiveHourReset = Date(timeIntervalSince1970: 1_100)
        vm.applyResult(UsageResultFactory.make(
            fiveHourPercent: 12.0,
            sevenDayPercent: 22.0,
            fiveHourResetsAt: newerFiveHourReset,
            sevenDayResetsAt: nil,
            resetTimesObservedAt: newerFiveHourObservedAt
        ))

        XCTAssertEqual(vm.fiveHourResetsAt, newerFiveHourReset)
        XCTAssertEqual(vm.fiveHourResetsAtObservedAt, newerFiveHourObservedAt)
        XCTAssertEqual(vm.sevenDayResetsAt, initialSevenDayReset,
                       "Omitting 7d must retain its independently observed value")
        XCTAssertEqual(vm.sevenDayResetsAtObservedAt, firstObservedAt,
                       "A newer 5h observation must not relabel retained 7d data as fresh")
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
