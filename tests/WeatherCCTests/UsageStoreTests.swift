import XCTest
import SQLite3
@testable import WeatherCC

final class UsageStoreTests: XCTestCase {

    private var tmpDir: URL!
    private var store: UsageStore!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("UsageStoreTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        store = UsageStore(dbPath: tmpDir.appendingPathComponent("usage.db").path)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    private func makeResult(
        fiveHourPercent: Double? = nil,
        sevenDayPercent: Double? = nil,
        fiveHourResetsAt: Date? = nil,
        sevenDayResetsAt: Date? = nil
    ) -> UsageResult {
        UsageResult(
            fiveHourPercent: fiveHourPercent,
            sevenDayPercent: sevenDayPercent,
            fiveHourResetsAt: fiveHourResetsAt,
            sevenDayResetsAt: sevenDayResetsAt,
            fiveHourStatus: nil,
            sevenDayStatus: nil,
            fiveHourLimit: nil,
            fiveHourRemaining: nil,
            sevenDayLimit: nil,
            sevenDayRemaining: nil,
            rawJSON: nil
        )
    }

    // MARK: - Save

    func testSave_createsDBFile() {
        store.save(makeResult(fiveHourPercent: 42.0))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.dbPath))
    }

    func testSave_insertsRow() {
        store.save(makeResult(fiveHourPercent: 10.0))
        let history = store.loadAllHistory()
        XCTAssertEqual(history.count, 1)
    }

    func testSave_multipleRows() {
        store.save(makeResult(fiveHourPercent: 10.0))
        store.save(makeResult(fiveHourPercent: 20.0))
        store.save(makeResult(fiveHourPercent: 30.0))
        let history = store.loadAllHistory()
        XCTAssertEqual(history.count, 3)
    }

    func testSave_allColumnsStored() {
        // Use exact hour so normalizeResetsAt returns the same epoch
        let resetsAt = Date(timeIntervalSince1970: 1_740_024_000) // 2025-02-20 02:00:00 UTC
        let result = makeResult(
            fiveHourPercent: 42.5,
            sevenDayPercent: 15.3,
            fiveHourResetsAt: resetsAt,
            sevenDayResetsAt: resetsAt
        )
        store.save(result)
        let history = store.loadAllHistory()
        XCTAssertEqual(history.count, 1)

        let dp = history[0]
        XCTAssertEqual(dp.fiveHourPercent!, 42.5, accuracy: 0.01)
        XCTAssertEqual(dp.sevenDayPercent!, 15.3, accuracy: 0.01)
        XCTAssertNotNil(dp.fiveHourResetsAt)
        XCTAssertNotNil(dp.sevenDayResetsAt)
    }

    func testSave_bothPercentsNil_skipped() {
        store.save(makeResult()) // all nil → should be skipped
        let history = store.loadAllHistory()
        XCTAssertEqual(history.count, 0,
                       "Rows with both percents nil should not be saved")
    }

    func testSave_onePercentNil_otherValid_saved() {
        store.save(makeResult(fiveHourPercent: nil, sevenDayPercent: 10.0))
        let history = store.loadAllHistory()
        XCTAssertEqual(history.count, 1,
                       "Row with at least one non-nil percent should be saved")
        XCTAssertNil(history[0].fiveHourPercent)
        XCTAssertEqual(history[0].sevenDayPercent, 10.0)
    }

    // MARK: - Session Tables

    func testSave_createsSessionTables() {
        let resetsAt = Date(timeIntervalSince1970: 1_740_024_000)
        store.save(makeResult(fiveHourPercent: 10.0, fiveHourResetsAt: resetsAt, sevenDayResetsAt: resetsAt))

        var db: OpaquePointer?
        guard sqlite3_open(store.dbPath, &db) == SQLITE_OK else {
            XCTFail("Failed to open DB")
            return
        }
        defer { sqlite3_close(db) }

        // Verify both session tables exist
        for table in ["hourly_sessions", "weekly_sessions"] {
            var stmt: OpaquePointer?
            let sql = "SELECT COUNT(*) FROM \(table)"
            XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &stmt, nil), SQLITE_OK, "\(table) should exist")
            sqlite3_finalize(stmt)
        }
    }

    func testSave_insertsHourlySession() {
        let resetsAt = Date(timeIntervalSince1970: 1_740_024_000) // exact hour
        store.save(makeResult(fiveHourPercent: 10.0, fiveHourResetsAt: resetsAt))

        var db: OpaquePointer?
        guard sqlite3_open(store.dbPath, &db) == SQLITE_OK else {
            XCTFail("Failed to open DB")
            return
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM hourly_sessions", -1, &stmt, nil)
        sqlite3_step(stmt)
        XCTAssertEqual(sqlite3_column_int(stmt, 0), 1, "Should have 1 hourly session")
        sqlite3_finalize(stmt)
    }

    func testSave_sameSession_deduplicates() {
        let hour = Date(timeIntervalSince1970: 1_740_024_000) // exact hour
        // Two saves with same session hour
        store.save(makeResult(fiveHourPercent: 10.0, fiveHourResetsAt: hour))
        store.save(makeResult(fiveHourPercent: 20.0, fiveHourResetsAt: hour))

        var db: OpaquePointer?
        guard sqlite3_open(store.dbPath, &db) == SQLITE_OK else {
            XCTFail("Failed to open DB")
            return
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM hourly_sessions", -1, &stmt, nil)
        sqlite3_step(stmt)
        XCTAssertEqual(sqlite3_column_int(stmt, 0), 1, "Same hour → 1 session row")
        sqlite3_finalize(stmt)

        // But usage_log should have 2 rows
        let history = store.loadAllHistory()
        XCTAssertEqual(history.count, 2)
    }

    func testSave_differentSession_separate() {
        let hour1 = Date(timeIntervalSince1970: 1_740_024_000) // 02:00 UTC
        let hour2 = Date(timeIntervalSince1970: 1_740_042_000) // 07:00 UTC
        store.save(makeResult(fiveHourPercent: 10.0, fiveHourResetsAt: hour1))
        store.save(makeResult(fiveHourPercent: 20.0, fiveHourResetsAt: hour2))

        var db: OpaquePointer?
        guard sqlite3_open(store.dbPath, &db) == SQLITE_OK else {
            XCTFail("Failed to open DB")
            return
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM hourly_sessions", -1, &stmt, nil)
        sqlite3_step(stmt)
        XCTAssertEqual(sqlite3_column_int(stmt, 0), 2, "Different hours → 2 session rows")
        sqlite3_finalize(stmt)
    }

    // MARK: - normalizeResetsAt

    func testNormalizeResetsAt_secondBoundary() {
        // 13:59:59.939 and 14:00:00.082 → both should normalize to 14:00:00
        let before = Date(timeIntervalSince1970: 1_740_405_599.939) // 13:59:59.939
        let after = Date(timeIntervalSince1970: 1_740_405_600.082)  // 14:00:00.082
        XCTAssertEqual(store.normalizeResetsAt(before), store.normalizeResetsAt(after),
                       "Second-boundary jitter should normalize to same hour")
        // Both should be 14:00:00 = 1740405600
        XCTAssertEqual(store.normalizeResetsAt(before), 1_740_405_600)
    }

    func testNormalizeResetsAt_exactHour() {
        let exact = Date(timeIntervalSince1970: 1_740_024_000) // 02:00:00.000
        XCTAssertEqual(store.normalizeResetsAt(exact), 1_740_024_000,
                       "Exact hour should normalize to itself")
    }

    // MARK: - Load All History

    func testLoadAllHistory_empty() {
        let history = store.loadAllHistory()
        XCTAssertEqual(history.count, 0)
    }

    func testLoadAllHistory_orderedByTimestamp() {
        store.save(makeResult(fiveHourPercent: 10.0))
        usleep(1_100_000) // 1.1s gap for unique epoch seconds
        store.save(makeResult(fiveHourPercent: 20.0))
        usleep(1_100_000)
        store.save(makeResult(fiveHourPercent: 30.0))

        let history = store.loadAllHistory()
        XCTAssertEqual(history.count, 3)
        for i in 1..<history.count {
            XCTAssertTrue(history[i].timestamp >= history[i-1].timestamp,
                          "History should be ordered by timestamp ASC")
        }
    }

    func testLoadAllHistory_resetsAtParsed() {
        // Use exact hour so normalizeResetsAt returns the same value
        let resetsAt = Date(timeIntervalSince1970: 1_740_024_000) // 2025-02-20 02:00:00 UTC
        store.save(makeResult(fiveHourPercent: 10.0, fiveHourResetsAt: resetsAt, sevenDayResetsAt: resetsAt))

        let history = store.loadAllHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertNotNil(history[0].fiveHourResetsAt)
        XCTAssertNotNil(history[0].sevenDayResetsAt)
        XCTAssertEqual(history[0].fiveHourResetsAt!.timeIntervalSince1970,
                       resetsAt.timeIntervalSince1970, accuracy: 0.0)
    }

    func testLoadAllHistory_joinsSessionData() {
        let hourlyResets = Date(timeIntervalSince1970: 1_740_024_000)
        let weeklyResets = Date(timeIntervalSince1970: 1_740_096_000)
        store.save(makeResult(fiveHourPercent: 42.0, sevenDayPercent: 15.0,
                              fiveHourResetsAt: hourlyResets, sevenDayResetsAt: weeklyResets))

        let history = store.loadAllHistory()
        XCTAssertEqual(history.count, 1)
        let dp = history[0]
        XCTAssertEqual(dp.fiveHourResetsAt!.timeIntervalSince1970, 1_740_024_000, accuracy: 0.0)
        XCTAssertEqual(dp.sevenDayResetsAt!.timeIntervalSince1970, 1_740_096_000, accuracy: 0.0)
    }

    // MARK: - Load History (windowed)

    func testLoadHistory_windowFilter() {
        store.save(makeResult(fiveHourPercent: 50.0))

        let recent = store.loadHistory(windowSeconds: 3600)
        XCTAssertEqual(recent.count, 1)

        let none = store.loadHistory(windowSeconds: 0)
        XCTAssertLessThanOrEqual(none.count, 1)
    }

    func testLoadHistory_emptyDB() {
        let history = store.loadHistory(windowSeconds: 3600)
        XCTAssertEqual(history.count, 0)
    }

    func testLoadHistory_epochComparison() {
        store.save(makeResult(fiveHourPercent: 50.0))

        // 1-hour window should include it
        let recent = store.loadHistory(windowSeconds: 3600)
        XCTAssertEqual(recent.count, 1)

        // Verify timestamp is a valid recent epoch (within last minute)
        let now = Date().timeIntervalSince1970
        let ts = recent[0].timestamp.timeIntervalSince1970
        XCTAssertTrue(abs(now - ts) < 60, "Timestamp should be recent epoch, got \(ts)")
    }

    // MARK: - Timestamp epoch round-trip

    func testTimestamp_epochRoundTrip() {
        store.save(makeResult(fiveHourPercent: 42.0))

        let history = store.loadAllHistory()
        XCTAssertEqual(history.count, 1)
        let ts = history[0].timestamp.timeIntervalSince1970
        let now = Date().timeIntervalSince1970
        // Timestamp should be within 1 second of now (epoch seconds precision)
        XCTAssertEqual(ts, now, accuracy: 1.0, "Epoch round-trip should preserve second precision")
    }

    // MARK: - Migration (old schema → new)

    func testMigration_oldSchemaToNew() {
        let dbPath = tmpDir.appendingPathComponent("migrate_test.db").path

        // Create old schema DB
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            XCTFail("Failed to create old schema DB")
            return
        }

        let oldSchema = """
            CREATE TABLE usage_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                five_hour_percent REAL,
                seven_day_percent REAL,
                five_hour_resets_at TEXT,
                seven_day_resets_at TEXT,
                CHECK (five_hour_percent IS NOT NULL OR seven_day_percent IS NOT NULL)
            );
            """
        sqlite3_exec(db, oldSchema, nil, nil, nil)

        let insertSQL = """
            INSERT INTO usage_log (timestamp, five_hour_percent, seven_day_percent,
                five_hour_resets_at, seven_day_resets_at) VALUES (?, ?, ?, ?, ?);
            """
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil)

        // Note: sqlite3_bind_text with Swift string literal stores empty string.
        // Must use NSString.utf8String for correct binding.

        // Row 1: jittered resets_at (13:59:59.939)
        sqlite3_bind_text(stmt, 1, ("2026-02-26T13:40:37.061Z" as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 2, 16.0)
        sqlite3_bind_double(stmt, 3, 45.0)
        sqlite3_bind_text(stmt, 4, ("2026-02-26T13:59:59.939Z" as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, ("2026-02-27T07:59:59.500Z" as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
        sqlite3_reset(stmt)

        // Row 2: same session, different jitter (14:00:00.082)
        sqlite3_bind_text(stmt, 1, ("2026-02-26T13:41:36.973Z" as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 2, 16.0)
        sqlite3_bind_double(stmt, 3, 45.0)
        sqlite3_bind_text(stmt, 4, ("2026-02-26T14:00:00.082Z" as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, ("2026-02-27T08:00:00.300Z" as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
        sqlite3_reset(stmt)

        // Row 3: different hourly session (23:00)
        sqlite3_bind_text(stmt, 1, ("2026-02-26T19:00:05.123Z" as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 2, 5.0)
        sqlite3_bind_double(stmt, 3, 46.0)
        sqlite3_bind_text(stmt, 4, ("2026-02-26T23:00:01.234Z" as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, ("2026-02-27T08:00:00.100Z" as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)

        sqlite3_finalize(stmt)
        sqlite3_close(db)

        // Create UsageStore → triggers migration
        let migratedStore = UsageStore(dbPath: dbPath)

        let history = migratedStore.loadAllHistory()
        XCTAssertEqual(history.count, 3)

        // Data integrity
        XCTAssertEqual(history[0].fiveHourPercent, 16.0)
        XCTAssertEqual(history[0].sevenDayPercent, 45.0)
        XCTAssertNotNil(history[0].fiveHourResetsAt)
        XCTAssertNotNil(history[0].sevenDayResetsAt)

        // Jitter normalization: rows 0 and 1 have same hourly session
        XCTAssertEqual(history[0].fiveHourResetsAt, history[1].fiveHourResetsAt,
                       "Same session with jitter should have identical resets_at after migration")

        // Row 2 has different hourly session
        XCTAssertNotEqual(history[0].fiveHourResetsAt, history[2].fiveHourResetsAt,
                          "Different hourly sessions should have different resets_at")

        // All rows share the same weekly session
        XCTAssertEqual(history[0].sevenDayResetsAt, history[1].sevenDayResetsAt)
        XCTAssertEqual(history[1].sevenDayResetsAt, history[2].sevenDayResetsAt)

        // Backup was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbPath + ".bak"),
                      "Migration should create .bak backup")
    }

    // MARK: - Migration Idempotency

    func testMigration_newSchemaNotMigrated() {
        // Save with new schema, then create another store pointing to same DB
        store.save(makeResult(fiveHourPercent: 10.0))
        store.save(makeResult(fiveHourPercent: 20.0))

        // Creating a new store on the same DB should NOT trigger migration
        let store2 = UsageStore(dbPath: store.dbPath)
        let history = store2.loadAllHistory()
        XCTAssertEqual(history.count, 2, "New schema DB should not be re-migrated")
        // No .bak should exist
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.dbPath + ".bak"),
                       "New schema DB should not create a backup")
    }

    // MARK: - loadHistory does NOT return resets_at (documented behavior)

    func testLoadHistory_doesNotReturnResetsAt() {
        let resetsAt = Date(timeIntervalSince1970: 1_740_024_000)
        store.save(makeResult(fiveHourPercent: 50.0, fiveHourResetsAt: resetsAt, sevenDayResetsAt: resetsAt))

        let windowed = store.loadHistory(windowSeconds: 3600)
        XCTAssertEqual(windowed.count, 1)
        XCTAssertNil(windowed[0].fiveHourResetsAt,
                     "loadHistory does not select resets_at columns (documented limitation)")
        XCTAssertNil(windowed[0].sevenDayResetsAt)
    }

    // MARK: - Sequential Saves

    func testSave_sequentialSavesAccumulate() {
        for i in 0..<10 {
            store.save(makeResult(fiveHourPercent: Double(i * 10)))
            usleep(5_000)
        }
        let history = store.loadAllHistory()
        XCTAssertEqual(history.count, 10, "10 sequential saves should produce 10 rows")
    }

    // MARK: - Extreme Values

    func testSave_extremeValues() {
        store.save(makeResult(fiveHourPercent: 0.0, sevenDayPercent: 0.0))
        store.save(makeResult(fiveHourPercent: 100.0, sevenDayPercent: 100.0))
        store.save(makeResult(fiveHourPercent: 150.0, sevenDayPercent: 200.0))

        let history = store.loadAllHistory()
        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history[0].fiveHourPercent, 0.0)
        XCTAssertEqual(history[1].fiveHourPercent, 100.0)
        XCTAssertEqual(history[2].fiveHourPercent, 150.0, "Values >100% should be stored as-is")
    }

    // MARK: - Both Percents Nil

    func testSave_bothPercentsNil_doesNotInsert() {
        store.save(makeResult())
        let history = store.loadAllHistory()
        XCTAssertEqual(history.count, 0,
                       "Both percents nil → row should be skipped")
    }

    // MARK: - Save with invalid path

    func testSave_invalidPath_silentlyFails() {
        let badStore = UsageStore(dbPath: "/dev/null/impossible/usage.db")
        badStore.save(makeResult(fiveHourPercent: 42.0))
        let history = badStore.loadAllHistory()
        XCTAssertEqual(history.count, 0, "Save to invalid path should silently fail")
    }

    // MARK: - loadHistory with negative windowSeconds

    func testLoadHistory_negativeWindow() {
        store.save(makeResult(fiveHourPercent: 50.0))
        let history = store.loadHistory(windowSeconds: -3600)
        XCTAssertEqual(history.count, 0, "Negative window should return no records")
    }

    // MARK: - loadAllHistory on invalid DB path

    func testLoadAllHistory_invalidPath_returnsEmpty() {
        let badStore = UsageStore(dbPath: "/dev/null/impossible/usage.db")
        let history = badStore.loadAllHistory()
        XCTAssertEqual(history.count, 0,
                       "loadAllHistory with invalid DB path should return empty array")
    }

    // MARK: - loadAllHistory on corrupt DB file

    func testLoadAllHistory_corruptDB_returnsEmpty() throws {
        store.save(makeResult(fiveHourPercent: 42.0))
        XCTAssertEqual(store.loadAllHistory().count, 1)

        try "NOT A SQLITE FILE".write(toFile: store.dbPath, atomically: true, encoding: .utf8)

        let history = store.loadAllHistory()
        XCTAssertEqual(history.count, 0,
                       "Corrupt DB should return empty array, not crash")
    }

    // MARK: - NULL percent rows

    func testLoadHistory_includesRowsWithPartialNilPercents() {
        store.save(makeResult(fiveHourPercent: nil, sevenDayPercent: 10.0))
        usleep(1_100_000)
        store.save(makeResult(fiveHourPercent: 26.0, sevenDayPercent: 54.0))

        let history = store.loadHistory(windowSeconds: 3600)
        XCTAssertEqual(history.count, 2)
        XCTAssertNil(history[0].fiveHourPercent)
        XCTAssertEqual(history[0].sevenDayPercent, 10.0)
        XCTAssertEqual(history[1].fiveHourPercent, 26.0)
    }

    func testLoadAllHistory_mixedNilAndValid() {
        store.save(makeResult(fiveHourPercent: nil, sevenDayPercent: 10.0))
        usleep(1_100_000)
        store.save(makeResult(fiveHourPercent: 25.0, sevenDayPercent: nil))
        usleep(1_100_000)
        store.save(makeResult(fiveHourPercent: 30.0, sevenDayPercent: 50.0))

        let history = store.loadAllHistory()
        XCTAssertEqual(history.count, 3)

        XCTAssertNil(history[0].fiveHourPercent)
        XCTAssertEqual(history[0].sevenDayPercent, 10.0)

        XCTAssertEqual(history[1].fiveHourPercent, 25.0)
        XCTAssertNil(history[1].sevenDayPercent)

        XCTAssertEqual(history[2].fiveHourPercent, 30.0)
        XCTAssertEqual(history[2].sevenDayPercent, 50.0)
    }
}
