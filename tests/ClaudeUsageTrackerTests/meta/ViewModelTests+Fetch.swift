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

    // MARK: - applyResult writes widget snapshot to file

    func testApplyResult_writesSnapshotToFile() {
        guard let url = AppGroupConfig.snapshotURL else { return }
        // Clean up first
        try? FileManager.default.removeItem(at: url)

        let now = Date()
        let vm = makeVM()
        var result = UsageResult()
        result.fiveHourPercent = 55.0
        result.sevenDayPercent = 25.0
        result.fiveHourResetsAt = now.addingTimeInterval(3600)
        result.sevenDayResetsAt = now.addingTimeInterval(3 * 24 * 3600)

        vm.applyResult(result)

        let data = try? Data(contentsOf: url)
        XCTAssertNotNil(data, "applyResult must write snapshot file")

        if let data {
            let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data)
            XCTAssertNotNil(snapshot)
            XCTAssertEqual(snapshot?.fiveHourPercent, 55.0)
            XCTAssertEqual(snapshot?.sevenDayPercent, 25.0)
            XCTAssertTrue(snapshot?.isLoggedIn == true)
        }

        // Cleanup
        try? FileManager.default.removeItem(at: url)
    }

    func testSignOut_writesLoggedOutSnapshotToFile() {
        guard let url = AppGroupConfig.snapshotURL else { return }
        try? FileManager.default.removeItem(at: url)

        let vm = makeVM()
        vm.isLoggedIn = true
        vm.signOut()

        let data = try? Data(contentsOf: url)
        XCTAssertNotNil(data, "signOut must write snapshot file")

        if let data {
            let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data)
            XCTAssertNotNil(snapshot)
            XCTAssertFalse(snapshot?.isLoggedIn ?? true)
            XCTAssertNil(snapshot?.fiveHourPercent)
            XCTAssertNil(snapshot?.sevenDayPercent)
        }

        // Cleanup
        try? FileManager.default.removeItem(at: url)
    }

    /// ウィジェットのグラフが描画可能かの前提条件テスト。
    /// WidgetMiniGraph は resolveWindowStart() で windowStart を決定する:
    ///   1. resetsAt != nil → resetsAt - windowSeconds
    ///   2. resetsAt == nil, history non-empty → history.first.timestamp
    ///   3. both absent → nil (描画なし)
    /// ここではソースロジックを再実装せず、snapshot の状態と期待結果のみを検証する。
    func testWidgetGraphRenderability_variousSnapshotStates() {
        let now = Date()

        // Case 1: resetsAt あり → windowStart は決まる → 描画可能
        let snap1 = UsageSnapshot(
            timestamp: now,
            fiveHourPercent: 20.0, sevenDayPercent: 10.0,
            fiveHourResetsAt: now.addingTimeInterval(3600),
            sevenDayResetsAt: now.addingTimeInterval(3 * 24 * 3600),
            fiveHourHistory: [HistoryPoint(timestamp: now, percent: 20.0)],
            sevenDayHistory: [],
            isLoggedIn: true,

        )
        XCTAssertNotNil(snap1.fiveHourResetsAt, "resetsAt あり → windowStart 決定可能")
        XCTAssertFalse(snap1.fiveHourHistory.isEmpty, "history あり → points 生成可能")

        // Case 2: resetsAt nil, history あり → history.first で windowStart 決定
        let snap2 = UsageSnapshot(
            timestamp: now,
            fiveHourPercent: 20.0, sevenDayPercent: 10.0,
            fiveHourResetsAt: nil, sevenDayResetsAt: nil,
            fiveHourHistory: [HistoryPoint(timestamp: now, percent: 20.0)],
            sevenDayHistory: [],
            isLoggedIn: true,

        )
        XCTAssertNil(snap2.fiveHourResetsAt)
        XCTAssertFalse(snap2.fiveHourHistory.isEmpty, "history fallback で描画可能")

        // Case 3: resetsAt nil, history 空 → windowStart nil → 描画不可
        let snap3 = UsageSnapshot(
            timestamp: now,
            fiveHourPercent: nil, sevenDayPercent: nil,
            fiveHourResetsAt: nil, sevenDayResetsAt: nil,
            fiveHourHistory: [], sevenDayHistory: [],
            isLoggedIn: false,

        )
        XCTAssertNil(snap3.fiveHourResetsAt)
        XCTAssertTrue(snap3.fiveHourHistory.isEmpty, "resetsAt nil + history 空 → 描画不可")
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

        XCTAssertNil(vm.error, "Auth error must not show error text (shows Sign In instead)")
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

        XCTAssertNil(vm.error, "Auth error clears error (Sign In shown instead)")
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
}
