import XCTest
import ClaudeUsageTrackerShared
@testable import ClaudeUsageTracker

// MARK: - ViewModelTests + Fetch / SignOut / Snapshot / Widget

extension ViewModelTests {

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

    // MARK: - signOut clears predict

    func testSignOut_clearsPredictCost() {
        let vm = makeVM()
        vm.predictFiveHourCost = 1.23
        vm.predictSevenDayCost = 4.56
        vm.signOut()
        XCTAssertNil(vm.predictFiveHourCost, "signOut should clear predictFiveHourCost")
        XCTAssertNil(vm.predictSevenDayCost, "signOut should clear predictSevenDayCost")
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
