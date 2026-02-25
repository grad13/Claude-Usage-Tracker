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
    struct FetchRecord {
        let timestamp: Date
        let fiveHourPercent: Double?
        let sevenDayPercent: Double?
        let fiveHourResetsAt: Date?
        let sevenDayResetsAt: Date?
        let isLoggedIn: Bool
    }
    struct PredictRecord {
        let fiveHourCost: Double?
        let sevenDayCost: Double?
    }

    var savedFetches: [FetchRecord] = []
    var savedPredicts: [PredictRecord] = []
    var signOutCount = 0

    func saveAfterFetch(
        timestamp: Date,
        fiveHourPercent: Double?, sevenDayPercent: Double?,
        fiveHourResetsAt: Date?, sevenDayResetsAt: Date?,
        isLoggedIn: Bool
    ) {
        savedFetches.append(FetchRecord(
            timestamp: timestamp,
            fiveHourPercent: fiveHourPercent,
            sevenDayPercent: sevenDayPercent,
            fiveHourResetsAt: fiveHourResetsAt,
            sevenDayResetsAt: sevenDayResetsAt,
            isLoggedIn: isLoggedIn
        ))
    }

    func updatePredict(fiveHourCost: Double?, sevenDayCost: Double?) {
        savedPredicts.append(PredictRecord(
            fiveHourCost: fiveHourCost,
            sevenDayCost: sevenDayCost
        ))
    }

    func clearOnSignOut() { signOutCount += 1 }
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

final class InMemoryLoginItemManager: LoginItemManaging {
    var enabledCallCount = 0
    var disabledCallCount = 0
    var lastEnabled: Bool?
    var shouldThrow: Error?

    func setEnabled(_ enabled: Bool) throws {
        if let error = shouldThrow { throw error }
        lastEnabled = enabled
        if enabled { enabledCallCount += 1 }
        else { disabledCallCount += 1 }
    }
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
    private var loginItemManager: InMemoryLoginItemManager!

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

    private func makeVM() -> UsageViewModel {
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

    // MARK: - signOut calls clearOnSignOut

    func testSignOut_callsClearOnSignOut() {
        let vm = makeVM()
        vm.isLoggedIn = true
        vm.fiveHourPercent = 42.0
        vm.sevenDayPercent = 18.0

        let initDone = expectation(description: "init done")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { initDone.fulfill() }
        wait(for: [initDone], timeout: 2.0)

        let countBefore = snapshotWriter.signOutCount
        vm.signOut()

        XCTAssertEqual(snapshotWriter.signOutCount, countBefore + 1,
            "signOut must call clearOnSignOut exactly once")
        _ = vm
    }

    // (writeSnapshot data flow tests removed — SQLite migration moved this logic to SnapshotStore)

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

    /// Every snapshot write (saveAfterFetch, updatePredict, clearOnSignOut) triggers reloadAllTimelines.
    func testReloadCount_matchesSnapshotWriteCount() {
        let vm = makeVM()
        let done = expectation(description: "init done")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 2.0)

        // After init: fetchPredict → updatePredict + reload
        let totalWrites = snapshotWriter.savedFetches.count
            + snapshotWriter.savedPredicts.count
            + snapshotWriter.signOutCount
        XCTAssertEqual(widgetReloader.reloadCount, totalWrites,
            "Each snapshot write must trigger exactly one reloadAllTimelines")
        _ = vm
    }

    // (writeSnapshot_afterFetch / init overwrite tests removed — SQLite handles this internally)

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

    /// 認証エラー時: エラーが設定され、isLoggedIn が true にならず、データが更新されないことを検証。
    /// isAutoRefreshEnabled = false も内部で設定されるが private のため直接検証不可。
    /// 認証エラーが正しく識別されることで、auto-refresh 無効化パスが通ることを間接的に保証する。
    func testFetch_authError_setsErrorAndDoesNotUpdateState() {
        stubFetcher.fetchResult = .failure(UsageFetchError.scriptFailed("HTTP 401"))

        let vm = makeVM()
        vm.fiveHourPercent = 99.0 // set existing value
        vm.fetch()

        let done = expectation(description: "fetch completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 2.0)

        XCTAssertNotNil(vm.error, "Auth error must surface as vm.error")
        XCTAssertTrue(vm.error!.contains("401"),
            "Error message must indicate auth failure")
        XCTAssertFalse(vm.isLoggedIn,
            "Auth error must NOT set isLoggedIn to true")
        XCTAssertEqual(vm.fiveHourPercent, 99.0,
            "Auth error must NOT update usage data (applyResult not called)")
    }

    /// 認証エラー後に成功 fetch → 状態が回復しデータが更新されることを検証。
    /// isAutoRefreshEnabled は false → true にリセットされる（private だが動作で保証）。
    func testFetch_authErrorThenSuccess_recoversState() {
        let now = Date()
        stubFetcher.fetchResult = .failure(UsageFetchError.scriptFailed("HTTP 401"))

        let vm = makeVM()
        vm.fetch()

        let authDone = expectation(description: "auth error fetch")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { authDone.fulfill() }
        wait(for: [authDone], timeout: 2.0)

        XCTAssertNotNil(vm.error)
        XCTAssertFalse(vm.isLoggedIn)

        // Now succeed
        stubFetcher.fetchResult = .success(UsageResult(
            fiveHourPercent: 30.0,
            sevenDayPercent: 15.0,
            fiveHourResetsAt: now.addingTimeInterval(3600),
            sevenDayResetsAt: now.addingTimeInterval(3 * 24 * 3600)
        ))
        vm.fetch()

        let successDone = expectation(description: "success fetch")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { successDone.fulfill() }
        wait(for: [successDone], timeout: 2.0)

        XCTAssertNil(vm.error, "Successful fetch after auth error must clear error")
        XCTAssertTrue(vm.isLoggedIn, "Successful fetch must set isLoggedIn to true")
        XCTAssertEqual(vm.fiveHourPercent, 30.0, "Data must be updated after recovery")
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

    /// fetch() 成功後に saveAfterFetch + updatePredict が呼ばれることを検証。
    func testFetch_success_callsSaveAfterFetchThenUpdatePredict() {
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

        let fetchCountBefore = snapshotWriter.savedFetches.count
        let predictCountBefore = snapshotWriter.savedPredicts.count
        vm.fetch()

        let fetchDone = expectation(description: "fetch")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { fetchDone.fulfill() }
        wait(for: [fetchDone], timeout: 2.0)

        // applyResult → saveAfterFetch
        XCTAssertGreaterThan(snapshotWriter.savedFetches.count, fetchCountBefore,
            "Successful fetch must call saveAfterFetch")
        let fetch = snapshotWriter.savedFetches.last!
        XCTAssertEqual(fetch.fiveHourPercent, 25.0)
        XCTAssertEqual(fetch.sevenDayPercent, 10.0)
        XCTAssertTrue(fetch.isLoggedIn)
        XCTAssertNotNil(fetch.fiveHourResetsAt)
        XCTAssertNotNil(fetch.sevenDayResetsAt)

        // fetchPredict → updatePredict
        XCTAssertGreaterThan(snapshotWriter.savedPredicts.count, predictCountBefore,
            "Successful fetch must also call updatePredict (via fetchPredict)")
        _ = vm
    }
}
