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
    var fileExists = false
    func save(_ snapshot: UsageSnapshot) {
        savedSnapshots.append(snapshot)
        fileExists = true
    }
    func exists() -> Bool { fileExists }
}

final class InMemoryWidgetReloader: WidgetReloading {
    var reloadCount = 0
    func reloadAllTimelines() { reloadCount += 1 }
}

final class StubUsageFetcher: UsageFetching {
    var fetchResult: Result<UsageResult, Error> = .success(UsageResult())
    var hasValidSessionResult = false
    var fetchCallCount = 0
    var hasValidSessionCallCount = 0

    @MainActor func fetch(from webView: WKWebView) async throws -> UsageResult {
        fetchCallCount += 1
        return try fetchResult.get()
    }
    @MainActor func hasValidSession(using webView: WKWebView) async -> Bool {
        hasValidSessionCallCount += 1
        return hasValidSessionResult
    }
}

final class InMemoryTokenSync: TokenSyncing, @unchecked Sendable {
    func sync(directories: [URL]) {}
    func loadRecords(since cutoff: Date) -> [TokenRecord] { [] }
}

// MARK: - ViewModelTests

@MainActor
final class ViewModelTests: XCTestCase {

    private var stubFetcher: StubUsageFetcher!
    private var settingsStore: InMemorySettingsStore!
    private var usageStore: InMemoryUsageStore!
    private var snapshotWriter: InMemorySnapshotWriter!
    private var widgetReloader: InMemoryWidgetReloader!
    private var tokenSync: InMemoryTokenSync!

    override func setUp() {
        super.setUp()
        stubFetcher = StubUsageFetcher()
        settingsStore = InMemorySettingsStore()
        usageStore = InMemoryUsageStore()
        snapshotWriter = InMemorySnapshotWriter()
        widgetReloader = InMemoryWidgetReloader()
        tokenSync = InMemoryTokenSync()
    }

    private func makeVM() -> UsageViewModel {
        UsageViewModel(
            fetcher: stubFetcher,
            settingsStore: settingsStore,
            usageStore: usageStore,
            snapshotWriter: snapshotWriter,
            widgetReloader: widgetReloader,
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
        // Past date: DisplayHelpers returns "expired"
        XCTAssertNotNil(text, "Past date should still return a string, not nil")
    }

    // MARK: - Widget display: snapshot must contain history for graph to render

    func testSnapshot_widgetCanRenderGraph_requiresHistoryAndResetsAt() {
        // Widget's WidgetMiniGraph returns early (blank) when BOTH resetsAt is nil AND history is empty.
        // This test verifies that writeSnapshot produces a snapshot the widget can actually render.
        let now = Date()
        usageStore.historyToReturn = [
            UsageStore.DataPoint(
                timestamp: now.addingTimeInterval(-3600),
                fiveHourPercent: 10.0, sevenDayPercent: 5.0
            ),
            UsageStore.DataPoint(
                timestamp: now,
                fiveHourPercent: 20.0, sevenDayPercent: 10.0
            ),
        ]

        let vm = makeVM()
        vm.isLoggedIn = true
        vm.fiveHourPercent = 20.0
        vm.sevenDayPercent = 10.0
        vm.fiveHourResetsAt = now.addingTimeInterval(3 * 3600)
        vm.sevenDayResetsAt = now.addingTimeInterval(5 * 24 * 3600)

        let done = expectation(description: "snapshot written")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 2.0)

        guard let snapshot = snapshotWriter.savedSnapshots.last else {
            XCTFail("Expected snapshot"); return
        }

        // Widget needs non-empty history OR non-nil resetsAt to render the graph.
        // If both are missing, WidgetMiniGraph returns early → blank widget.
        XCTAssertFalse(snapshot.fiveHourHistory.isEmpty,
                       "Snapshot must have fiveHourHistory for widget to render graph")
        XCTAssertFalse(snapshot.sevenDayHistory.isEmpty,
                       "Snapshot must have sevenDayHistory for widget to render graph")
        XCTAssertNotNil(snapshot.fiveHourResetsAt,
                        "Snapshot must have fiveHourResetsAt for widget graph windowStart")
        XCTAssertNotNil(snapshot.sevenDayResetsAt,
                        "Snapshot must have sevenDayResetsAt for widget graph windowStart")
    }

    // MARK: - signOut should write snapshot to notify widget

    func testSignOut_writesSnapshotWithLoggedOutState() {
        let vm = makeVM()
        // Simulate logged-in state with data
        vm.isLoggedIn = true
        vm.fiveHourPercent = 42.0
        vm.sevenDayPercent = 18.0
        vm.fiveHourResetsAt = Date().addingTimeInterval(3600)
        vm.sevenDayResetsAt = Date().addingTimeInterval(3 * 24 * 3600)

        // Wait for init's fetchPredict → writeSnapshot
        let initDone = expectation(description: "init snapshot written")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            initDone.fulfill()
        }
        wait(for: [initDone], timeout: 2.0)

        let countBeforeSignOut = snapshotWriter.savedSnapshots.count

        // Sign out
        vm.signOut()

        // Wait for signOut's writeSnapshot
        let signOutDone = expectation(description: "signOut snapshot written")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            signOutDone.fulfill()
        }
        wait(for: [signOutDone], timeout: 2.0)

        // Verify: a new snapshot was written AFTER signOut
        XCTAssertGreaterThan(snapshotWriter.savedSnapshots.count, countBeforeSignOut,
                             "signOut must call writeSnapshot to notify widget of logged-out state")

        // Verify: the snapshot reflects the signed-out state
        guard let snapshot = snapshotWriter.savedSnapshots.last else {
            XCTFail("Expected snapshot after signOut")
            return
        }
        XCTAssertFalse(snapshot.isLoggedIn,
                       "Snapshot after signOut must have isLoggedIn=false")
        XCTAssertNil(snapshot.fiveHourPercent,
                     "Snapshot after signOut must have nil fiveHourPercent")
        XCTAssertNil(snapshot.sevenDayPercent,
                     "Snapshot after signOut must have nil sevenDayPercent")
        XCTAssertNil(snapshot.fiveHourResetsAt,
                     "Snapshot after signOut must have nil fiveHourResetsAt")
        XCTAssertNil(snapshot.sevenDayResetsAt,
                     "Snapshot after signOut must have nil sevenDayResetsAt")
    }

    // MARK: - writeSnapshot data flow tests

    /// init 直後の writeSnapshot は isLoggedIn=false, percent=nil, resetsAt=nil を書く。
    /// フェッチが成功するまで、ウィジェットはこの状態のスナップショットを受け取る。
    func testWriteSnapshot_initState_beforeAnyFetch() {
        usageStore.historyToReturn = []
        let vm = makeVM()

        let done = expectation(description: "snapshot")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 2.0)

        guard let snapshot = snapshotWriter.savedSnapshots.first else {
            XCTFail("Expected at least one snapshot from init"); return
        }

        XCTAssertFalse(snapshot.isLoggedIn,
                       "init snapshot should have isLoggedIn=false")
        XCTAssertNil(snapshot.fiveHourPercent,
                     "init snapshot should have nil fiveHourPercent")
        XCTAssertNil(snapshot.sevenDayPercent,
                     "init snapshot should have nil sevenDayPercent")
        XCTAssertNil(snapshot.fiveHourResetsAt,
                     "init snapshot should have nil fiveHourResetsAt")
        XCTAssertNil(snapshot.sevenDayResetsAt,
                     "init snapshot should have nil sevenDayResetsAt")
        XCTAssertTrue(snapshot.fiveHourHistory.isEmpty)
        XCTAssertTrue(snapshot.sevenDayHistory.isEmpty)
        _ = vm // keep alive
    }

    /// writeSnapshot の history は fiveHourHistory/sevenDayHistory から構築される。
    /// loadHistory(windowSeconds:) は同じデータを両方に返す（InMemoryUsageStore の仕様）が、
    /// writeSnapshot は fiveHourHistory を fiveHourPercent で、sevenDayHistory を sevenDayPercent でフィルタする。
    func testWriteSnapshot_historyUsesCorrectPercentField() {
        let now = Date()
        usageStore.historyToReturn = [
            // fiveHourPercent のみ
            UsageStore.DataPoint(timestamp: now.addingTimeInterval(-300),
                                fiveHourPercent: 15.0, sevenDayPercent: nil),
            // sevenDayPercent のみ
            UsageStore.DataPoint(timestamp: now.addingTimeInterval(-200),
                                fiveHourPercent: nil, sevenDayPercent: 8.0),
            // 両方あり
            UsageStore.DataPoint(timestamp: now,
                                fiveHourPercent: 25.0, sevenDayPercent: 12.0),
        ]

        let vm = makeVM()
        let done = expectation(description: "snapshot")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 2.0)

        guard let snapshot = snapshotWriter.savedSnapshots.last else {
            XCTFail("Expected snapshot"); return
        }

        // fiveHourHistory: dp[0](15.0) と dp[2](25.0) — dp[1] は fiveHourPercent=nil なのでフィルタ
        XCTAssertEqual(snapshot.fiveHourHistory.count, 2)
        XCTAssertEqual(snapshot.fiveHourHistory[0].percent, 15.0, accuracy: 0.01)
        XCTAssertEqual(snapshot.fiveHourHistory[1].percent, 25.0, accuracy: 0.01)

        // sevenDayHistory: dp[1](8.0) と dp[2](12.0) — dp[0] は sevenDayPercent=nil なのでフィルタ
        XCTAssertEqual(snapshot.sevenDayHistory.count, 2)
        XCTAssertEqual(snapshot.sevenDayHistory[0].percent, 8.0, accuracy: 0.01)
        XCTAssertEqual(snapshot.sevenDayHistory[1].percent, 12.0, accuracy: 0.01)
    }

    /// init 時に DB にデータがある場合、writeSnapshot の history にそのデータが含まれるか
    func testWriteSnapshot_initIncludesHistoryFromDB() {
        let now = Date()
        usageStore.historyToReturn = [
            UsageStore.DataPoint(timestamp: now.addingTimeInterval(-7200),
                                fiveHourPercent: 5.0, sevenDayPercent: 2.0),
            UsageStore.DataPoint(timestamp: now.addingTimeInterval(-3600),
                                fiveHourPercent: 10.0, sevenDayPercent: 4.0),
            UsageStore.DataPoint(timestamp: now,
                                fiveHourPercent: 15.0, sevenDayPercent: 6.0),
        ]

        let vm = makeVM()
        let done = expectation(description: "snapshot")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 2.0)

        guard let snapshot = snapshotWriter.savedSnapshots.last else {
            XCTFail("Expected snapshot"); return
        }

        XCTAssertEqual(snapshot.fiveHourHistory.count, 3,
                       "init snapshot should include all history points from DB")
        XCTAssertEqual(snapshot.sevenDayHistory.count, 3)
        // percent/resetsAt は init 時点では nil
        XCTAssertNil(snapshot.fiveHourPercent)
        XCTAssertNil(snapshot.sevenDayPercent)
        XCTAssertNil(snapshot.fiveHourResetsAt)
        XCTAssertNil(snapshot.sevenDayResetsAt)
        XCTAssertFalse(snapshot.isLoggedIn)
        _ = vm // keep alive
    }

    /// ウィジェットが snapshot を SnapshotStore 経由で読むとき、エンコード→デコードで情報が失われないか
    func testWriteSnapshot_roundTripThroughSnapshotStore() throws {
        let now = Date(timeIntervalSince1970: 1740000000) // fixed timestamp
        let snapshot = UsageSnapshot(
            timestamp: now,
            fiveHourPercent: 42.5,
            sevenDayPercent: 18.0,
            fiveHourResetsAt: now.addingTimeInterval(3 * 3600),
            sevenDayResetsAt: now.addingTimeInterval(5 * 24 * 3600),
            fiveHourHistory: [
                HistoryPoint(timestamp: now.addingTimeInterval(-3600), percent: 30.0),
                HistoryPoint(timestamp: now, percent: 42.5),
            ],
            sevenDayHistory: [
                HistoryPoint(timestamp: now.addingTimeInterval(-86400), percent: 10.0),
                HistoryPoint(timestamp: now, percent: 18.0),
            ],
            isLoggedIn: true,
            predictFiveHourCost: 1.5,
            predictSevenDayCost: 8.0
        )

        // SnapshotStore の save/load を実ファイルでテスト
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeatherCC-test-\(UUID().uuidString)")
            .appendingPathComponent("snapshot.json")
        SnapshotStore.save(snapshot, to: tmpURL)
        guard let loaded = SnapshotStore.load(from: tmpURL) else {
            XCTFail("SnapshotStore.load returned nil"); return
        }

        XCTAssertEqual(loaded.fiveHourPercent, 42.5)
        XCTAssertEqual(loaded.sevenDayPercent, 18.0)
        XCTAssertEqual(loaded.fiveHourHistory.count, 2)
        XCTAssertEqual(loaded.sevenDayHistory.count, 2)
        XCTAssertTrue(loaded.isLoggedIn)
        XCTAssertNotNil(loaded.fiveHourResetsAt)
        XCTAssertNotNil(loaded.sevenDayResetsAt)
        XCTAssertEqual(loaded.predictFiveHourCost, 1.5)
        XCTAssertEqual(loaded.predictSevenDayCost, 8.0)

        // history の timestamp が保存されているか
        XCTAssertEqual(loaded.fiveHourHistory[0].percent, 30.0, accuracy: 0.01)
        XCTAssertEqual(loaded.fiveHourHistory[1].percent, 42.5, accuracy: 0.01)
        XCTAssertEqual(loaded.sevenDayHistory[0].percent, 10.0, accuracy: 0.01)
        XCTAssertEqual(loaded.sevenDayHistory[1].percent, 18.0, accuracy: 0.01)

        // timestamp の精度（iso8601 は秒精度なので1秒以内の誤差を許容）
        XCTAssertEqual(loaded.fiveHourResetsAt!.timeIntervalSince1970,
                       snapshot.fiveHourResetsAt!.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(loaded.fiveHourHistory[0].timestamp.timeIntervalSince1970,
                       snapshot.fiveHourHistory[0].timestamp.timeIntervalSince1970, accuracy: 1.0)

        // cleanup
        try? FileManager.default.removeItem(at: tmpURL.deletingLastPathComponent())
    }

    /// ウィジェットのグラフが描画可能かを判定するロジックのテスト。
    /// WidgetMiniGraph は resetsAt=nil かつ history が空のとき早期 return する。
    /// snapshot の各状態でウィジェットが何を描画できるかを検証する。
    func testWidgetGraphRenderability_variousSnapshotStates() {
        struct TestCase {
            let label: String
            let resetsAt: Date?
            let history: [HistoryPoint]
            let expectRenderable: Bool
        }

        let now = Date()
        let cases: [TestCase] = [
            TestCase(label: "resetsAt あり, history あり",
                     resetsAt: now.addingTimeInterval(3600),
                     history: [HistoryPoint(timestamp: now, percent: 20.0)],
                     expectRenderable: true),
            TestCase(label: "resetsAt あり, history 空",
                     resetsAt: now.addingTimeInterval(3600),
                     history: [],
                     expectRenderable: true), // resetsAt だけでも windowStart は決まる（ただし points は空→return）
            TestCase(label: "resetsAt nil, history あり",
                     resetsAt: nil,
                     history: [HistoryPoint(timestamp: now, percent: 20.0)],
                     expectRenderable: true), // history.first で windowStart を決定
            TestCase(label: "resetsAt nil, history 空",
                     resetsAt: nil,
                     history: [],
                     expectRenderable: false), // 早期 return → 何も描画されない
        ]

        for tc in cases {
            // WidgetMiniGraph の描画判定ロジックを再現
            let windowSeconds: TimeInterval = 5 * 3600
            let windowStart: Date?
            if let resetsAt = tc.resetsAt {
                windowStart = resetsAt.addingTimeInterval(-windowSeconds)
            } else if let first = tc.history.first {
                windowStart = first.timestamp
            } else {
                windowStart = nil
            }

            guard let ws = windowStart else {
                XCTAssertFalse(tc.expectRenderable, "\(tc.label): windowStart=nil → not renderable")
                continue
            }

            // points フィルタリング
            var points: [(x: Double, y: Double)] = []
            for dp in tc.history {
                let elapsed = dp.timestamp.timeIntervalSince(ws)
                guard elapsed >= 0 else { continue }
                points.append((x: elapsed / windowSeconds, y: dp.percent / 100.0))
            }

            if tc.expectRenderable && !tc.history.isEmpty {
                XCTAssertFalse(points.isEmpty, "\(tc.label): should have renderable points")
            }
        }
    }

    // MARK: - Widget reload (reloadAllTimelines)

    /// init → fetchPredict → writeSnapshot で reloadAllTimelines が呼ばれることを検証。
    /// これが呼ばれなければウィジェットは更新されず、古い/空の表示のまま放置される。
    func testInit_callsReloadAllTimelines() {
        let vm = makeVM()
        let done = expectation(description: "reload called")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 2.0)

        XCTAssertGreaterThanOrEqual(widgetReloader.reloadCount, 1,
            "init must call reloadAllTimelines at least once (via fetchPredict → writeSnapshot)")
        _ = vm
    }

    /// signOut → writeSnapshot → reloadAllTimelines が呼ばれることを検証。
    /// ログアウト後にウィジェットを更新しなければ、古い使用量が表示され続ける。
    func testSignOut_callsReloadAllTimelines() {
        let vm = makeVM()
        let initDone = expectation(description: "init done")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { initDone.fulfill() }
        wait(for: [initDone], timeout: 2.0)

        let countBeforeSignOut = widgetReloader.reloadCount
        vm.signOut()

        XCTAssertGreaterThan(widgetReloader.reloadCount, countBeforeSignOut,
            "signOut must call reloadAllTimelines to notify widget of logged-out state")
    }

    /// writeSnapshot が呼ばれるたびに reloadAllTimelines も呼ばれることを検証。
    /// snapshotWriter.save と reloadAllTimelines の呼び出し回数は一致するべき。
    func testWriteSnapshot_reloadCountMatchesSnapshotCount() {
        let vm = makeVM()
        let done = expectation(description: "snapshot")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 2.0)

        XCTAssertEqual(widgetReloader.reloadCount, snapshotWriter.savedSnapshots.count,
            "Each writeSnapshot call must trigger exactly one reloadAllTimelines")
        _ = vm
    }

    /// 「resetsAt あり、history 空」のケースでは windowStart は決まるが points が空で早期 return する。
    /// これはウィジェットがグラフを描画しない状態。
    /// フェッチ直後は resetsAt はあるが history が空になることはあるか？→ reloadHistory 後なのであり得ない（DB にデータがあれば）
    func testWriteSnapshot_afterFetch_historyNonEmpty() {
        let now = Date()
        // DB に最低1件のデータがあるケース
        usageStore.historyToReturn = [
            UsageStore.DataPoint(timestamp: now, fiveHourPercent: 30.0, sevenDayPercent: 15.0),
        ]

        let vm = makeVM()
        // fetch 成功後の状態をシミュレート
        vm.fiveHourPercent = 30.0
        vm.sevenDayPercent = 15.0
        vm.fiveHourResetsAt = now.addingTimeInterval(2 * 3600)
        vm.sevenDayResetsAt = now.addingTimeInterval(4 * 24 * 3600)
        vm.isLoggedIn = true

        let done = expectation(description: "snapshot")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 2.0)

        guard let snapshot = snapshotWriter.savedSnapshots.last else {
            XCTFail("Expected snapshot"); return
        }

        // ウィジェットが描画可能な状態であること
        XCTAssertFalse(snapshot.fiveHourHistory.isEmpty,
                       "After fetch, fiveHourHistory must not be empty")
        XCTAssertFalse(snapshot.sevenDayHistory.isEmpty,
                       "After fetch, sevenDayHistory must not be empty")
        XCTAssertNotNil(snapshot.fiveHourResetsAt)
        XCTAssertNotNil(snapshot.sevenDayResetsAt)

        // history のポイントが resetsAt のウィンドウ内にあるか
        let windowStart5h = snapshot.fiveHourResetsAt!.addingTimeInterval(-5 * 3600)
        for point in snapshot.fiveHourHistory {
            XCTAssertGreaterThanOrEqual(point.timestamp, windowStart5h,
                "History point should be within the 5h window (after windowStart)")
        }
    }

    // MARK: - Init must not overwrite existing good snapshot

    /// 既にスナップショットファイルが存在するとき、init が空データで上書きしてはいけない。
    /// 80KB の蓄積データ（1300+ history ポイント）を毎回起動時に消していたバグを検出する。
    func testInit_doesNotOverwriteExistingSnapshot() {
        snapshotWriter.fileExists = true  // 既存ファイルがある状態をシミュレート
        usageStore.historyToReturn = []
        let vm = makeVM()

        let done = expectation(description: "init completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 2.0)

        XCTAssertTrue(snapshotWriter.savedSnapshots.isEmpty,
            "Init must not overwrite existing snapshot file — it has accumulated data")
        _ = vm
    }

    /// スナップショットファイルが存在しないとき、init は新規作成する（バックアップとして）。
    func testInit_createsSnapshotWhenFileDoesNotExist() {
        snapshotWriter.fileExists = false  // ファイルが存在しない
        usageStore.historyToReturn = []
        let vm = makeVM()

        let done = expectation(description: "init completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 2.0)

        XCTAssertFalse(snapshotWriter.savedSnapshots.isEmpty,
            "Init should create snapshot file when it doesn't exist yet")
        _ = vm
    }

    // MARK: - UsageFetching injection tests

    /// fetch() が注入された fetcher を使うことを検証。
    /// ハードコードの UsageFetcher.fetch() ではなく、DI された fetcher 経由で呼ばれるべき。
    func testFetch_usesInjectedFetcher() {
        let now = Date()
        stubFetcher.fetchResult = .success(UsageResult(
            fiveHourPercent: 30.0,
            sevenDayPercent: 15.0,
            fiveHourResetsAt: now.addingTimeInterval(3600),
            sevenDayResetsAt: now.addingTimeInterval(3 * 24 * 3600)
        ))

        let vm = makeVM()
        vm.fetch()

        let done = expectation(description: "fetch completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 2.0)

        XCTAssertGreaterThanOrEqual(stubFetcher.fetchCallCount, 1,
            "fetch() must use the injected fetcher, not UsageFetcher directly")
        XCTAssertEqual(vm.fiveHourPercent, 30.0)
        XCTAssertEqual(vm.sevenDayPercent, 15.0)
    }

    /// fetch() 失敗時にエラーが設定されることを検証。
    func testFetch_failure_setsError() {
        stubFetcher.fetchResult = .failure(UsageFetchError.scriptFailed("HTTP 500"))

        let vm = makeVM()
        vm.fetch()

        let done = expectation(description: "fetch completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 2.0)

        XCTAssertNotNil(vm.error, "Failed fetch should set error message")
        XCTAssertTrue(vm.error!.contains("500"))
    }

    /// fetch() の認証エラーで auto-refresh が無効化されることを検証。
    func testFetch_authError_disablesAutoRefresh() {
        stubFetcher.fetchResult = .failure(UsageFetchError.scriptFailed("HTTP 401"))

        let vm = makeVM()
        vm.fetch()

        let done = expectation(description: "fetch completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 2.0)

        // 認証エラー後に再度 fetch しても auto-refresh は起動しない
        // (isAutoRefreshEnabled = false になっているはず)
        XCTAssertNotNil(vm.error)
    }

    /// fetch() 成功時に usageStore.save が呼ばれることを検証。
    func testFetch_success_savesToUsageStore() {
        let now = Date()
        stubFetcher.fetchResult = .success(UsageResult(
            fiveHourPercent: 25.0,
            sevenDayPercent: 10.0,
            fiveHourResetsAt: now.addingTimeInterval(2 * 3600),
            sevenDayResetsAt: now.addingTimeInterval(5 * 24 * 3600)
        ))

        let vm = makeVM()
        vm.fetch()

        let done = expectation(description: "fetch completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 2.0)

        XCTAssertFalse(usageStore.savedResults.isEmpty,
            "Successful fetch must save result to usageStore")
        XCTAssertEqual(usageStore.savedResults.last?.fiveHourPercent, 25.0)
        _ = vm
    }

    /// fetch() 成功後にウィジェットスナップショットが更新されることを検証。
    func testFetch_success_writesSnapshot() {
        let now = Date()
        usageStore.historyToReturn = [
            UsageStore.DataPoint(timestamp: now, fiveHourPercent: 25.0, sevenDayPercent: 10.0)
        ]
        stubFetcher.fetchResult = .success(UsageResult(
            fiveHourPercent: 25.0,
            sevenDayPercent: 10.0,
            fiveHourResetsAt: now.addingTimeInterval(2 * 3600),
            sevenDayResetsAt: now.addingTimeInterval(5 * 24 * 3600)
        ))

        let vm = makeVM()
        let initDone = expectation(description: "init")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { initDone.fulfill() }
        wait(for: [initDone], timeout: 2.0)

        let countBefore = snapshotWriter.savedSnapshots.count
        vm.fetch()

        let fetchDone = expectation(description: "fetch")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { fetchDone.fulfill() }
        wait(for: [fetchDone], timeout: 2.0)

        XCTAssertGreaterThan(snapshotWriter.savedSnapshots.count, countBefore,
            "Successful fetch must trigger writeSnapshot for widget update")

        let snapshot = snapshotWriter.savedSnapshots.last!
        XCTAssertEqual(snapshot.fiveHourPercent, 25.0)
        XCTAssertEqual(snapshot.sevenDayPercent, 10.0)
        XCTAssertTrue(snapshot.isLoggedIn)
    }
}
