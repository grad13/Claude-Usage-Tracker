import XCTest
import SQLite3
import WeatherCCShared

final class SnapshotStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapshotStoreTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        SnapshotStore.dbPathOverride = tempDir.appendingPathComponent("snapshot.db").path
    }

    override func tearDown() {
        SnapshotStore.dbPathOverride = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Round-Trip

    func testSaveAfterFetch_load_roundTrip_allFields() {
        let now = Date(timeIntervalSince1970: 1740000000)
        SnapshotStore.saveAfterFetch(
            timestamp: now,
            fiveHourPercent: 55.5, sevenDayPercent: 22.2,
            fiveHourResetsAt: now.addingTimeInterval(3600),
            sevenDayResetsAt: now.addingTimeInterval(86400),
            isLoggedIn: true
        )
        // Also set predict values
        SnapshotStore.updatePredict(fiveHourCost: 3.14, sevenDayCost: 9.99)

        let loaded = SnapshotStore.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.fiveHourPercent, 55.5)
        XCTAssertEqual(loaded?.sevenDayPercent, 22.2)
        XCTAssertEqual(loaded?.isLoggedIn, true)
        XCTAssertEqual(loaded?.predictFiveHourCost, 3.14)
        XCTAssertEqual(loaded?.predictSevenDayCost, 9.99)
        XCTAssertNotNil(loaded?.fiveHourResetsAt)
        XCTAssertEqual(loaded!.fiveHourResetsAt!.timeIntervalSince1970,
                       now.addingTimeInterval(3600).timeIntervalSince1970, accuracy: 1)
        XCTAssertNotNil(loaded?.sevenDayResetsAt)
        XCTAssertEqual(loaded!.sevenDayResetsAt!.timeIntervalSince1970,
                       now.addingTimeInterval(86400).timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(loaded!.timestamp.timeIntervalSince1970,
                       now.timeIntervalSince1970, accuracy: 1)
    }

    func testSaveAfterFetch_load_nilOptionals() {
        let now = Date(timeIntervalSince1970: 1740000000)
        SnapshotStore.saveAfterFetch(
            timestamp: now,
            fiveHourPercent: nil, sevenDayPercent: nil,
            fiveHourResetsAt: nil, sevenDayResetsAt: nil,
            isLoggedIn: false
        )

        let loaded = SnapshotStore.load()
        XCTAssertNotNil(loaded)
        XCTAssertNil(loaded?.fiveHourPercent)
        XCTAssertNil(loaded?.sevenDayPercent)
        XCTAssertNil(loaded?.fiveHourResetsAt)
        XCTAssertNil(loaded?.sevenDayResetsAt)
        XCTAssertEqual(loaded?.isLoggedIn, false)
        XCTAssertNil(loaded?.predictFiveHourCost)
        XCTAssertNil(loaded?.predictSevenDayCost)
    }

    // MARK: - History

    func testSaveAfterFetch_insertsHistoryRow() {
        let now = Date()
        SnapshotStore.saveAfterFetch(
            timestamp: now,
            fiveHourPercent: 10.0, sevenDayPercent: 20.0,
            fiveHourResetsAt: nil, sevenDayResetsAt: nil,
            isLoggedIn: true
        )
        SnapshotStore.saveAfterFetch(
            timestamp: now.addingTimeInterval(300),
            fiveHourPercent: 15.0, sevenDayPercent: 25.0,
            fiveHourResetsAt: nil, sevenDayResetsAt: nil,
            isLoggedIn: true
        )

        let loaded = SnapshotStore.load()
        XCTAssertNotNil(loaded)
        // Both history points should be within the 5h window
        XCTAssertEqual(loaded!.fiveHourHistory.count, 2)
        XCTAssertEqual(loaded!.fiveHourHistory[0].percent, 10.0)
        XCTAssertEqual(loaded!.fiveHourHistory[1].percent, 15.0)
    }

    func testMultipleSaveAfterFetch_accumulatesHistory() {
        let now = Date()
        for i in 0..<5 {
            SnapshotStore.saveAfterFetch(
                timestamp: now.addingTimeInterval(Double(i) * 60),
                fiveHourPercent: Double(i * 10), sevenDayPercent: Double(i * 5),
                fiveHourResetsAt: nil, sevenDayResetsAt: nil,
                isLoggedIn: true
            )
        }

        // Verify history count via direct DB query
        let path = tempDir.appendingPathComponent("snapshot.db").path
        var db: OpaquePointer?
        sqlite3_open(path, &db)
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM snapshot_history;", -1, &stmt, nil)
        sqlite3_step(stmt)
        let count = sqlite3_column_int(stmt, 0)
        sqlite3_finalize(stmt)
        sqlite3_close(db)
        XCTAssertEqual(count, 5, "Should have 5 history rows")
    }

    // MARK: - Predict Preservation

    func testSaveAfterFetch_preservesPredictValues() {
        let now = Date()
        // First: save with data
        SnapshotStore.saveAfterFetch(
            timestamp: now,
            fiveHourPercent: 10.0, sevenDayPercent: 20.0,
            fiveHourResetsAt: nil, sevenDayResetsAt: nil,
            isLoggedIn: true
        )
        // Set predict values
        SnapshotStore.updatePredict(fiveHourCost: 5.0, sevenDayCost: 10.0)

        // Second saveAfterFetch should NOT overwrite predict values
        SnapshotStore.saveAfterFetch(
            timestamp: now.addingTimeInterval(300),
            fiveHourPercent: 15.0, sevenDayPercent: 25.0,
            fiveHourResetsAt: nil, sevenDayResetsAt: nil,
            isLoggedIn: true
        )

        let loaded = SnapshotStore.load()
        XCTAssertEqual(loaded?.predictFiveHourCost, 5.0,
                       "saveAfterFetch should preserve existing predict values")
        XCTAssertEqual(loaded?.predictSevenDayCost, 10.0)
        XCTAssertEqual(loaded?.fiveHourPercent, 15.0,
                       "Percent should be updated to new value")
    }

    // MARK: - updatePredict

    func testUpdatePredict_onlyChangesPredictFields() {
        let now = Date()
        SnapshotStore.saveAfterFetch(
            timestamp: now,
            fiveHourPercent: 50.0, sevenDayPercent: 75.0,
            fiveHourResetsAt: now.addingTimeInterval(3600),
            sevenDayResetsAt: now.addingTimeInterval(86400),
            isLoggedIn: true
        )

        SnapshotStore.updatePredict(fiveHourCost: 1.5, sevenDayCost: 3.0)

        let loaded = SnapshotStore.load()
        XCTAssertEqual(loaded?.fiveHourPercent, 50.0, "percent should not change")
        XCTAssertEqual(loaded?.sevenDayPercent, 75.0, "percent should not change")
        XCTAssertEqual(loaded?.isLoggedIn, true, "isLoggedIn should not change")
        XCTAssertEqual(loaded?.predictFiveHourCost, 1.5)
        XCTAssertEqual(loaded?.predictSevenDayCost, 3.0)
    }

    func testUpdatePredict_noStateRow_noError() {
        // DB doesn't exist yet; updatePredict should be a no-op (no crash)
        SnapshotStore.updatePredict(fiveHourCost: 1.0, sevenDayCost: 2.0)
        let loaded = SnapshotStore.load()
        XCTAssertNil(loaded, "No state row should exist")
    }

    // MARK: - clearOnSignOut

    func testClearOnSignOut_resetsStateKeepsHistory() {
        let now = Date()
        SnapshotStore.saveAfterFetch(
            timestamp: now,
            fiveHourPercent: 50.0, sevenDayPercent: 75.0,
            fiveHourResetsAt: nil, sevenDayResetsAt: nil,
            isLoggedIn: true
        )
        SnapshotStore.updatePredict(fiveHourCost: 1.0, sevenDayCost: 2.0)

        SnapshotStore.clearOnSignOut()

        let loaded = SnapshotStore.load()
        XCTAssertNotNil(loaded, "State row should still exist")
        XCTAssertEqual(loaded?.isLoggedIn, false)
        XCTAssertNil(loaded?.fiveHourPercent)
        XCTAssertNil(loaded?.sevenDayPercent)
        XCTAssertNil(loaded?.fiveHourResetsAt)
        XCTAssertNil(loaded?.sevenDayResetsAt)
        XCTAssertNil(loaded?.predictFiveHourCost)
        XCTAssertNil(loaded?.predictSevenDayCost)

        // History should be preserved
        let path = tempDir.appendingPathComponent("snapshot.db").path
        var db: OpaquePointer?
        sqlite3_open(path, &db)
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM snapshot_history;", -1, &stmt, nil)
        sqlite3_step(stmt)
        let count = sqlite3_column_int(stmt, 0)
        sqlite3_finalize(stmt)
        sqlite3_close(db)
        XCTAssertEqual(count, 1, "History should be preserved after sign out")
    }

    // MARK: - Load edge cases

    func testLoad_emptyDB_returnsNil() {
        // Trigger ensureDB to create tables but don't insert state
        SnapshotStore.saveAfterFetch(
            timestamp: Date(),
            fiveHourPercent: 10.0, sevenDayPercent: nil,
            fiveHourResetsAt: nil, sevenDayResetsAt: nil,
            isLoggedIn: true
        )
        // Delete the state row to simulate empty state
        let path = tempDir.appendingPathComponent("snapshot.db").path
        var db: OpaquePointer?
        sqlite3_open(path, &db)
        sqlite3_exec(db, "DELETE FROM snapshot_state;", nil, nil, nil)
        sqlite3_close(db)

        let loaded = SnapshotStore.load()
        XCTAssertNil(loaded, "Should return nil when no state row exists")
    }

    func testLoad_noDBFile_returnsNil() {
        // dbPathOverride points to temp dir but no DB file created yet
        let loaded = SnapshotStore.load()
        XCTAssertNil(loaded)
    }

    // MARK: - History window filtering

    func testLoad_historyWindowFiltering() {
        let now = Date()

        // Insert a point 6 hours ago (outside 5h window, inside 7d window)
        SnapshotStore.saveAfterFetch(
            timestamp: now.addingTimeInterval(-6 * 3600),
            fiveHourPercent: 10.0, sevenDayPercent: 20.0,
            fiveHourResetsAt: nil, sevenDayResetsAt: nil,
            isLoggedIn: true
        )
        // Insert a point 1 hour ago (inside both windows)
        SnapshotStore.saveAfterFetch(
            timestamp: now.addingTimeInterval(-3600),
            fiveHourPercent: 30.0, sevenDayPercent: 40.0,
            fiveHourResetsAt: nil, sevenDayResetsAt: nil,
            isLoggedIn: true
        )

        let loaded = SnapshotStore.load()
        XCTAssertNotNil(loaded)
        // 5h window: only the 1-hour-ago point
        XCTAssertEqual(loaded!.fiveHourHistory.count, 1)
        XCTAssertEqual(loaded!.fiveHourHistory[0].percent, 30.0)
        // 7d window: both points
        XCTAssertEqual(loaded!.sevenDayHistory.count, 2)
    }

    // MARK: - Large history

    func testLoad_largeHistory_1300Points() {
        let now = Date()
        // Insert 1300 points, 5 minutes apart (going back ~4.5 days)
        for i in 0..<1300 {
            SnapshotStore.saveAfterFetch(
                timestamp: now.addingTimeInterval(Double(-i) * 300),
                fiveHourPercent: Double(i % 100),
                sevenDayPercent: Double(i % 50),
                fiveHourResetsAt: nil, sevenDayResetsAt: nil,
                isLoggedIn: true
            )
        }

        let loaded = SnapshotStore.load()
        XCTAssertNotNil(loaded)
        // 5h = 18000s; 300s intervals → ~60 points in 5h window
        XCTAssertTrue(loaded!.fiveHourHistory.count > 50)
        XCTAssertTrue(loaded!.fiveHourHistory.count < 70)
        // 7d = 604800s; all 1300 points fit (~4.5 days < 7 days)
        XCTAssertEqual(loaded!.sevenDayHistory.count, 1300)
    }

    // MARK: - App Group availability

    func testAppGroupSnapshotDBPath_isNotNil() {
        // Reset override to check real path
        SnapshotStore.dbPathOverride = nil
        if AppGroupConfig.containerURL != nil {
            XCTAssertNotNil(AppGroupConfig.snapshotDBPath,
                            "App Group snapshot DB path should be available")
        }
        // Restore override for tearDown
        SnapshotStore.dbPathOverride = tempDir.appendingPathComponent("snapshot.db").path
    }

    // MARK: - Migration

    func testMigration_noJsonFile_noError() {
        // Simply creating and loading with no JSON file should work fine
        SnapshotStore.saveAfterFetch(
            timestamp: Date(),
            fiveHourPercent: 10.0, sevenDayPercent: 20.0,
            fiveHourResetsAt: nil, sevenDayResetsAt: nil,
            isLoggedIn: true
        )
        let loaded = SnapshotStore.load()
        XCTAssertNotNil(loaded)
    }

    // MARK: - Widget Pipeline Integration
    // UsageTimelineProvider.getTimeline() は SnapshotStore.load() を呼ぶだけ。
    // ここでは ViewModel の saveAfterFetch → Widget の load が正しく繋がることを検証する。

    /// saveAfterFetch → load で、ウィジェット描画に必要な全フィールドが揃うことを検証。
    /// WidgetMiniGraph は resetsAt OR history.first で windowStart を決定し、
    /// points 配列を構築して描画する。このテストは「描画できるデータ」が返ることを保証する。
    func testWidgetPipeline_saveAfterFetch_producesRenderableSnapshot() {
        let now = Date()
        let resetsAt5h = now.addingTimeInterval(2 * 3600) // 2時間後にリセット
        let resetsAt7d = now.addingTimeInterval(3 * 24 * 3600) // 3日後にリセット

        SnapshotStore.saveAfterFetch(
            timestamp: now,
            fiveHourPercent: 42.5, sevenDayPercent: 77.3,
            fiveHourResetsAt: resetsAt5h, sevenDayResetsAt: resetsAt7d,
            isLoggedIn: true
        )

        let snapshot = SnapshotStore.load()
        XCTAssertNotNil(snapshot, "Widget must receive non-nil snapshot after fetch")

        // WidgetMiniGraph の描画条件: resetsAt があるか、history が空でないこと
        // resetsAt があれば windowStart = resetsAt - windowSeconds で描画可能
        XCTAssertNotNil(snapshot!.fiveHourResetsAt,
            "Widget needs resetsAt to determine graph time window")
        XCTAssertNotNil(snapshot!.sevenDayResetsAt)

        // percent がないとテキスト表示 (e.g. "42.5%") が出ない
        XCTAssertNotNil(snapshot!.fiveHourPercent,
            "Widget needs percent to display usage text")
        XCTAssertNotNil(snapshot!.sevenDayPercent)

        // history にデータがないとグラフにポイントが描画されない
        XCTAssertFalse(snapshot!.fiveHourHistory.isEmpty,
            "Widget graph needs at least 1 history point")
        XCTAssertFalse(snapshot!.sevenDayHistory.isEmpty)

        // isLoggedIn=true で通常背景、false で赤背景
        XCTAssertTrue(snapshot!.isLoggedIn,
            "Widget must reflect logged-in state")
    }

    /// 複数回 saveAfterFetch → load で、5h/7d 両方の history が正しく蓄積されることを検証。
    func testWidgetPipeline_multipleFeatures_producesCompleteHistory() {
        let now = Date()
        // 5分間隔で10回のフェッチをシミュレート
        for i in 0..<10 {
            SnapshotStore.saveAfterFetch(
                timestamp: now.addingTimeInterval(Double(i) * 300),
                fiveHourPercent: Double(i * 5), sevenDayPercent: Double(i * 3),
                fiveHourResetsAt: now.addingTimeInterval(3 * 3600),
                sevenDayResetsAt: now.addingTimeInterval(5 * 24 * 3600),
                isLoggedIn: true
            )
        }

        let snapshot = SnapshotStore.load()
        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot!.fiveHourHistory.count, 10,
            "All 10 history points must be in 5h window")
        XCTAssertEqual(snapshot!.sevenDayHistory.count, 10,
            "All 10 history points must be in 7d window")

        // history は時系列順（ASC）で、最新が末尾
        XCTAssertEqual(snapshot!.fiveHourHistory.first!.percent, 0.0)
        XCTAssertEqual(snapshot!.fiveHourHistory.last!.percent, 45.0)

        // state は最新の値を反映
        XCTAssertEqual(snapshot!.fiveHourPercent, 45.0)
        XCTAssertEqual(snapshot!.sevenDayPercent, 27.0)
    }

    // MARK: - Widget Render Contract
    // ウィジェット View が描画する/しないの境界条件をテスト。
    // Widget View コード自体はテスト不可（extension target）だが、
    // SnapshotStore.load() が返すデータの形状で描画可否が決まる。

    /// DB が空 → load() returns nil → ウィジェットは "Not fetched yet" を表示。
    func testWidgetRenderContract_nilSnapshot_showsNotFetched() {
        // DB ファイルが存在しない状態
        let snapshot = SnapshotStore.load()
        XCTAssertNil(snapshot,
            "Empty DB must return nil → widget shows 'Not fetched yet'")
    }

    /// clearOnSignOut 後 → isLoggedIn==false → ウィジェットは赤背景を表示。
    func testWidgetRenderContract_loggedOut_hasRedBackground() {
        SnapshotStore.saveAfterFetch(
            timestamp: Date(),
            fiveHourPercent: 50.0, sevenDayPercent: 30.0,
            fiveHourResetsAt: nil, sevenDayResetsAt: nil,
            isLoggedIn: true
        )
        SnapshotStore.clearOnSignOut()

        let snapshot = SnapshotStore.load()
        XCTAssertNotNil(snapshot, "State row must exist after sign out")
        XCTAssertFalse(snapshot!.isLoggedIn,
            "Widget must see isLoggedIn=false → uses bgColorSignedOut (red)")
    }

    /// resetsAt=nil + history=[] → WidgetMiniGraph の windowStart が決定できず早期 return。
    func testWidgetRenderContract_noResetsAt_noHistory_graphNotRenderable() {
        SnapshotStore.saveAfterFetch(
            timestamp: Date(),
            fiveHourPercent: 50.0, sevenDayPercent: 30.0,
            fiveHourResetsAt: nil, sevenDayResetsAt: nil,
            isLoggedIn: true
        )

        let snapshot = SnapshotStore.load()
        XCTAssertNotNil(snapshot)

        // WidgetMiniGraph のロジック再現:
        // windowStart は resetsAt ?? history.first?.timestamp で決まる
        // 両方 nil/空 → 早期 return（グラフ描画なし）
        let fiveHourRenderable = snapshot!.fiveHourResetsAt != nil || !snapshot!.fiveHourHistory.isEmpty
        let sevenDayRenderable = snapshot!.sevenDayResetsAt != nil || !snapshot!.sevenDayHistory.isEmpty

        // resetsAt=nil だが history にはデータがある（saveAfterFetch が history を挿入するため）
        // → history.first で windowStart が決まり、描画は可能
        XCTAssertTrue(fiveHourRenderable,
            "saveAfterFetch always inserts history, so graph is renderable even without resetsAt")
    }

    /// 1時間前のデータ → load() の timestamp がその時刻を返す。
    /// ウィジェットはこの timestamp で「データがどれだけ古いか」を判定できる。
    func testWidgetPipeline_staleData_timestampIndicatesStaleness() {
        let oneHourAgo = Date().addingTimeInterval(-3600)
        SnapshotStore.saveAfterFetch(
            timestamp: oneHourAgo,
            fiveHourPercent: 25.0, sevenDayPercent: 15.0,
            fiveHourResetsAt: nil, sevenDayResetsAt: nil,
            isLoggedIn: true
        )

        let snapshot = SnapshotStore.load()
        XCTAssertNotNil(snapshot)
        let age = Date().timeIntervalSince(snapshot!.timestamp)
        XCTAssertGreaterThan(age, 3500, "Stale timestamp must be preserved (age ~3600s)")
        XCTAssertLessThan(age, 3700, "Timestamp must be accurate")
    }

    // MARK: - Concurrent read/write

    func testConcurrentReadWrite() {
        // Create initial data
        SnapshotStore.saveAfterFetch(
            timestamp: Date(),
            fiveHourPercent: 10.0, sevenDayPercent: 20.0,
            fiveHourResetsAt: nil, sevenDayResetsAt: nil,
            isLoggedIn: true
        )

        let exp = expectation(description: "concurrent")
        exp.expectedFulfillmentCount = 2

        // Writer thread: 100 inserts
        DispatchQueue.global().async {
            for i in 0..<100 {
                SnapshotStore.saveAfterFetch(
                    timestamp: Date(),
                    fiveHourPercent: Double(i), sevenDayPercent: Double(i),
                    fiveHourResetsAt: nil, sevenDayResetsAt: nil,
                    isLoggedIn: true
                )
            }
            exp.fulfill()
        }

        // Reader thread: 100 loads
        DispatchQueue.global().async {
            for _ in 0..<100 {
                _ = SnapshotStore.load()
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 10)
        let loaded = SnapshotStore.load()
        XCTAssertNotNil(loaded)
    }
}
