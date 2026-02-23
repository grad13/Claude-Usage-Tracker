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
        sevenDayResetsAt: Date? = nil,
        fiveHourStatus: Int? = nil,
        sevenDayStatus: Int? = nil,
        fiveHourLimit: Double? = nil,
        fiveHourRemaining: Double? = nil,
        sevenDayLimit: Double? = nil,
        sevenDayRemaining: Double? = nil,
        rawJSON: String? = nil
    ) -> UsageResult {
        UsageResult(
            fiveHourPercent: fiveHourPercent,
            sevenDayPercent: sevenDayPercent,
            fiveHourResetsAt: fiveHourResetsAt,
            sevenDayResetsAt: sevenDayResetsAt,
            fiveHourStatus: fiveHourStatus,
            sevenDayStatus: sevenDayStatus,
            fiveHourLimit: fiveHourLimit,
            fiveHourRemaining: fiveHourRemaining,
            sevenDayLimit: sevenDayLimit,
            sevenDayRemaining: sevenDayRemaining,
            rawJSON: rawJSON
        )
    }

    // MARK: - Save

    func testSave_createsDBFile() {
        let result = makeResult(fiveHourPercent: 42.0)
        store.save(result)
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
        let resetsAt = Date(timeIntervalSince1970: 1_740_000_000) // fixed date
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

    func testSave_nullableColumnsHandled() {
        store.save(makeResult()) // all nil
        let history = store.loadAllHistory()
        XCTAssertEqual(history.count, 1)

        let dp = history[0]
        XCTAssertNil(dp.fiveHourPercent)
        XCTAssertNil(dp.sevenDayPercent)
        XCTAssertNil(dp.fiveHourResetsAt)
        XCTAssertNil(dp.sevenDayResetsAt)
    }

    // MARK: - Load All History

    func testLoadAllHistory_empty() {
        let history = store.loadAllHistory()
        XCTAssertEqual(history.count, 0)
    }

    func testLoadAllHistory_orderedByTimestamp() {
        // Save 3 records (they'll get sequential timestamps since save uses Date())
        store.save(makeResult(fiveHourPercent: 10.0))
        usleep(10_000) // 10ms gap for unique timestamps
        store.save(makeResult(fiveHourPercent: 20.0))
        usleep(10_000)
        store.save(makeResult(fiveHourPercent: 30.0))

        let history = store.loadAllHistory()
        XCTAssertEqual(history.count, 3)
        // Verify ascending order
        for i in 1..<history.count {
            XCTAssertTrue(history[i].timestamp >= history[i-1].timestamp,
                          "History should be ordered by timestamp ASC")
        }
    }

    func testLoadAllHistory_resetsAtParsed() {
        let resetsAt = Date(timeIntervalSince1970: 1_740_000_000)
        store.save(makeResult(fiveHourResetsAt: resetsAt, sevenDayResetsAt: resetsAt))

        let history = store.loadAllHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertNotNil(history[0].fiveHourResetsAt)
        XCTAssertNotNil(history[0].sevenDayResetsAt)
        // Allow 1 second tolerance for ISO 8601 formatting roundtrip
        XCTAssertEqual(history[0].fiveHourResetsAt!.timeIntervalSince1970,
                       resetsAt.timeIntervalSince1970, accuracy: 1.0)
    }

    // MARK: - Load History (windowed)

    func testLoadHistory_windowFilter() {
        // Save one record (it gets "now" as timestamp)
        store.save(makeResult(fiveHourPercent: 50.0))

        // 1-hour window should include it (just saved)
        let recent = store.loadHistory(windowSeconds: 3600)
        XCTAssertEqual(recent.count, 1)

        // 0-second window should exclude it (cutoff is now)
        let none = store.loadHistory(windowSeconds: 0)
        XCTAssertEqual(none.count, 0)
    }

    func testLoadHistory_emptyDB() {
        let history = store.loadHistory(windowSeconds: 3600)
        XCTAssertEqual(history.count, 0)
    }

    // MARK: - Migration Idempotency

    func testMigration_addColumnsIdempotent() {
        // Save twice to trigger CREATE TABLE + ALTER TABLE migrations twice
        store.save(makeResult(fiveHourPercent: 10.0))
        store.save(makeResult(fiveHourPercent: 20.0))

        let history = store.loadAllHistory()
        XCTAssertEqual(history.count, 2, "Multiple saves should not fail due to duplicate ALTER TABLE")
    }

    // MARK: - loadHistory does NOT return resets_at (documented behavior)

    func testLoadHistory_doesNotReturnResetsAt() {
        let resetsAt = Date(timeIntervalSince1970: 1_740_000_000)
        store.save(makeResult(fiveHourPercent: 50.0, fiveHourResetsAt: resetsAt, sevenDayResetsAt: resetsAt))

        let windowed = store.loadHistory(windowSeconds: 3600)
        XCTAssertEqual(windowed.count, 1)
        // loadHistory's SQL only selects timestamp, five_hour_percent, seven_day_percent
        // resets_at is NOT included (unlike loadAllHistory)
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
        store.save(makeResult(fiveHourPercent: 150.0, sevenDayPercent: 200.0)) // >100%

        let history = store.loadAllHistory()
        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history[0].fiveHourPercent, 0.0)
        XCTAssertEqual(history[1].fiveHourPercent, 100.0)
        XCTAssertEqual(history[2].fiveHourPercent, 150.0, "Values >100% should be stored as-is")
    }

    // MARK: - Both Percents Nil

    func testSave_bothPercentsNil() {
        store.save(makeResult()) // both nil
        let history = store.loadAllHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertNil(history[0].fiveHourPercent)
        XCTAssertNil(history[0].sevenDayPercent)
    }

    // MARK: - Verify all columns stored via direct SQL

    func testSave_statusLimitRemainingRawJSON_storedInDB() {
        let result = makeResult(
            fiveHourPercent: 42.0,
            sevenDayPercent: 15.0,
            fiveHourStatus: 1,
            sevenDayStatus: 2,
            fiveHourLimit: 50.0,
            fiveHourRemaining: 8.0,
            sevenDayLimit: 200.0,
            sevenDayRemaining: 185.0,
            rawJSON: #"{"test":"data"}"#
        )
        store.save(result)

        // Read back via direct SQLite to verify columns that loadAllHistory doesn't select
        var db: OpaquePointer?
        guard sqlite3_open(store.dbPath, &db) == SQLITE_OK else {
            XCTFail("Failed to open DB")
            return
        }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT five_hour_status, seven_day_status,
                   five_hour_limit, five_hour_remaining,
                   seven_day_limit, seven_day_remaining,
                   raw_json
            FROM usage_log ORDER BY id DESC LIMIT 1;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            XCTFail("Failed to prepare statement")
            return
        }
        defer { sqlite3_finalize(stmt) }

        XCTAssertEqual(sqlite3_step(stmt), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(stmt, 0), 1, "five_hour_status")
        XCTAssertEqual(sqlite3_column_int(stmt, 1), 2, "seven_day_status")
        XCTAssertEqual(sqlite3_column_double(stmt, 2), 50.0, accuracy: 0.01, "five_hour_limit")
        XCTAssertEqual(sqlite3_column_double(stmt, 3), 8.0, accuracy: 0.01, "five_hour_remaining")
        XCTAssertEqual(sqlite3_column_double(stmt, 4), 200.0, accuracy: 0.01, "seven_day_limit")
        XCTAssertEqual(sqlite3_column_double(stmt, 5), 185.0, accuracy: 0.01, "seven_day_remaining")
        let rawJSON = sqlite3_column_text(stmt, 6).map { String(cString: $0) }
        XCTAssertEqual(rawJSON, #"{"test":"data"}"#, "raw_json")
    }

    func testSave_statusLimitRemainingRawJSON_nilStoredAsNull() {
        store.save(makeResult()) // all nil

        var db: OpaquePointer?
        guard sqlite3_open(store.dbPath, &db) == SQLITE_OK else {
            XCTFail("Failed to open DB")
            return
        }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT five_hour_status, seven_day_status,
                   five_hour_limit, five_hour_remaining,
                   seven_day_limit, seven_day_remaining,
                   raw_json
            FROM usage_log ORDER BY id DESC LIMIT 1;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            XCTFail("Failed to prepare statement")
            return
        }
        defer { sqlite3_finalize(stmt) }

        XCTAssertEqual(sqlite3_step(stmt), SQLITE_ROW)
        for col: Int32 in 0..<7 {
            XCTAssertEqual(sqlite3_column_type(stmt, col), SQLITE_NULL,
                           "Column \(col) should be NULL when input is nil")
        }
    }

    // MARK: - Save with invalid path (directory creation failure)

    func testSave_invalidPath_silentlyFails() {
        // /dev/null/impossible cannot be created as a directory
        let badStore = UsageStore(dbPath: "/dev/null/impossible/usage.db")
        badStore.save(makeResult(fiveHourPercent: 42.0))
        // Should not crash — silently fails
        let history = badStore.loadAllHistory()
        XCTAssertEqual(history.count, 0, "Save to invalid path should silently fail")
    }

    // MARK: - loadHistory with negative windowSeconds

    func testLoadHistory_negativeWindow() {
        store.save(makeResult(fiveHourPercent: 50.0))
        // Negative window: cutoff is in the future → no records should match
        let history = store.loadHistory(windowSeconds: -3600)
        XCTAssertEqual(history.count, 0, "Negative window should return no records")
    }

    // MARK: - loadAllHistory skips unparseable timestamps

    func testLoadAllHistory_unparsableTimestamp_skipped() {
        // First save a valid record to create the DB and table
        store.save(makeResult(fiveHourPercent: 42.0))
        XCTAssertEqual(store.loadAllHistory().count, 1)

        // Insert a row with a garbage timestamp via direct SQL
        var db: OpaquePointer?
        guard sqlite3_open(store.dbPath, &db) == SQLITE_OK else {
            XCTFail("Failed to open DB")
            return
        }
        defer { sqlite3_close(db) }

        let sql = "INSERT INTO usage_log (timestamp, five_hour_percent) VALUES ('not-a-date', 99.9);"
        sqlite3_exec(db, sql, nil, nil, nil)

        // loadAllHistory should skip the unparseable row
        let history = store.loadAllHistory()
        XCTAssertEqual(history.count, 1,
                       "Row with unparseable timestamp should be skipped (guard continue)")
        XCTAssertEqual(history[0].fiveHourPercent, 42.0)
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
        // First save valid data
        store.save(makeResult(fiveHourPercent: 42.0))
        XCTAssertEqual(store.loadAllHistory().count, 1)

        // Corrupt the DB
        try "NOT A SQLITE FILE".write(toFile: store.dbPath, atomically: true, encoding: .utf8)

        // loadAllHistory should fail gracefully
        let history = store.loadAllHistory()
        XCTAssertEqual(history.count, 0,
                       "Corrupt DB should return empty array, not crash")
    }
}
