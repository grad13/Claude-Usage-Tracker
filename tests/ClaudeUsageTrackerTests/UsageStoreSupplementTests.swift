// Supplement for: tests/ClaudeUsageTrackerTests/UsageStoreTests.swift
import XCTest
import SQLite3
@testable import ClaudeUsageTracker

final class UsageStoreSupplementTests: XCTestCase {

    private var tmpDir: URL!
    private var store: UsageStore!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("UsageStoreSupplementTests-\(UUID().uuidString)")
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

    // MARK: - loadDailyUsage: < 2 records returns nil

    func testLoadDailyUsage_noRecords_returnsNil() {
        // Spec: "対象期間のレコードが2件未満" → nil
        let since = Date(timeIntervalSinceNow: -3600)
        let result = store.loadDailyUsage(since: since)
        XCTAssertNil(result, "0 records in period should return nil")
    }

    func testLoadDailyUsage_oneRecord_returnsNil() {
        // Spec: "対象期間のレコードが2件未満" → nil (1件でも同様)
        let since = Date(timeIntervalSinceNow: -3600)
        store.save(makeResult(sevenDayPercent: 10.0))
        let result = store.loadDailyUsage(since: since)
        XCTAssertNil(result, "1 record in period should return nil")
    }

    // MARK: - loadDailyUsage: single session, two records

    func testLoadDailyUsage_singleSession_twoRecords_returnsIncrease() {
        // Spec: 1セッション内 last - first の増加量を返す
        // Session A: [10%, 30%] → 30 - 10 = 20
        let since = Date(timeIntervalSinceNow: -3600)
        let sessionResets = Date(timeIntervalSince1970: 1_740_024_000) // exact hour
        store.save(makeResult(sevenDayPercent: 10.0, sevenDayResetsAt: sessionResets))
        store.save(makeResult(sevenDayPercent: 30.0, sevenDayResetsAt: sessionResets))
        let result = store.loadDailyUsage(since: since)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 20.0, accuracy: 0.01,
                       "Single session [10%, 30%] should yield 20% increase")
    }

    // MARK: - loadDailyUsage: session boundary detection and multi-session summation

    func testLoadDailyUsage_twoSessions_sumsEachSessionIncrease() {
        // Spec example:
        //   Session A: [10%, 20%, 30%] → 20%
        //   Session B: [5%, 15%]       → 10%
        //   合計: 30%
        let since = Date(timeIntervalSinceNow: -3600)
        let sessionA = Date(timeIntervalSince1970: 1_740_024_000) // hour N
        let sessionB = Date(timeIntervalSince1970: 1_740_042_000) // hour N+5
        store.save(makeResult(sevenDayPercent: 10.0, sevenDayResetsAt: sessionA))
        store.save(makeResult(sevenDayPercent: 20.0, sevenDayResetsAt: sessionA))
        store.save(makeResult(sevenDayPercent: 30.0, sevenDayResetsAt: sessionA))
        store.save(makeResult(sevenDayPercent: 5.0, sevenDayResetsAt: sessionB))
        store.save(makeResult(sevenDayPercent: 15.0, sevenDayResetsAt: sessionB))
        let result = store.loadDailyUsage(since: since)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 30.0, accuracy: 0.01,
                       "Two sessions A[10,20,30]+B[5,15] should sum to 30%")
    }

    // MARK: - loadDailyUsage: negative delta treated as 0

    func testLoadDailyUsage_decreasingWithinSession_treatedAsZero() {
        // Spec: "各セッション内: max(0, last - first) で増加量を計算（減少は 0 扱い）"
        let since = Date(timeIntervalSinceNow: -3600)
        let sessionResets = Date(timeIntervalSince1970: 1_740_024_000)
        store.save(makeResult(sevenDayPercent: 50.0, sevenDayResetsAt: sessionResets))
        store.save(makeResult(sevenDayPercent: 20.0, sevenDayResetsAt: sessionResets))
        let result = store.loadDailyUsage(since: since)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 0.0, accuracy: 0.01,
                       "Decrease within session (50→20) should yield 0, not negative")
    }

    // MARK: - loadDailyUsage: NULL weekly_resets_at treated as same session

    func testLoadDailyUsage_nullResetsAt_treatedAsSameSession() {
        // Spec: "weekly_resets_at が NULL のレコードも、NULL 同士は同一セッションとして扱う"
        let since = Date(timeIntervalSinceNow: -3600)
        // Save with nil sevenDayResetsAt (NULL in DB)
        store.save(makeResult(sevenDayPercent: 5.0, sevenDayResetsAt: nil))
        store.save(makeResult(sevenDayPercent: 25.0, sevenDayResetsAt: nil))
        let result = store.loadDailyUsage(since: since)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 20.0, accuracy: 0.01,
                       "NULL resets_at records should be grouped as one session")
    }

    // MARK: - loadDailyUsage: records before since are excluded

    func testLoadDailyUsage_recordsBeforeSince_excluded() {
        // Spec: WHERE u.timestamp >= ? — sinceより前のレコードはクエリに含まれない
        // Insert old record outside the window, then two recent records
        let oldResets = Date(timeIntervalSince1970: 1_740_024_000)
        let recentResets = Date(timeIntervalSince1970: 1_740_042_000)

        // Old record (before since): use a far-past store to simulate an older timestamp
        // We cannot control exact timestamp, so we use a wide-enough since to include only recent saves.
        // Save "old" record first (it will have an earlier timestamp).
        store.save(makeResult(sevenDayPercent: 80.0, sevenDayResetsAt: oldResets))
        usleep(1_100_000) // ensure different epoch seconds

        // "since" is set after the old record, just before the next saves
        let since = Date()
        usleep(100_000)

        store.save(makeResult(sevenDayPercent: 5.0, sevenDayResetsAt: recentResets))
        store.save(makeResult(sevenDayPercent: 15.0, sevenDayResetsAt: recentResets))

        let result = store.loadDailyUsage(since: since)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 10.0, accuracy: 0.01,
                       "Records before 'since' must be excluded; only [5,15] in window → 10%")
    }

    // MARK: - loadDailyUsage: rows without weekly_percent are excluded

    func testLoadDailyUsage_rowsWithoutWeeklyPercent_notCounted() {
        // Spec query: WHERE ... AND u.weekly_percent IS NOT NULL
        // Rows with only fiveHourPercent should be ignored
        let since = Date(timeIntervalSinceNow: -3600)
        // Only fiveHour rows → weekly_percent IS NULL → excluded from query → < 2 records → nil
        store.save(makeResult(fiveHourPercent: 10.0, sevenDayPercent: nil))
        store.save(makeResult(fiveHourPercent: 20.0, sevenDayPercent: nil))
        let result = store.loadDailyUsage(since: since)
        XCTAssertNil(result,
                     "Rows with NULL weekly_percent must be excluded; 0 qualifying rows → nil")
    }

    // MARK: - loadDailyUsage: mixed session delta and decrease across sessions

    func testLoadDailyUsage_threeSessionsMixedDeltas() {
        // Session A: [20%, 20%] → 0 (no change)
        // Session B: [50%, 30%] → max(0, 30-50) = 0 (decrease)
        // Session C: [10%, 40%] → 30
        // Total: 30%
        let since = Date(timeIntervalSinceNow: -3600)
        let sessionA = Date(timeIntervalSince1970: 1_740_024_000)
        let sessionB = Date(timeIntervalSince1970: 1_740_042_000)
        let sessionC = Date(timeIntervalSince1970: 1_740_060_000)
        store.save(makeResult(sevenDayPercent: 20.0, sevenDayResetsAt: sessionA))
        store.save(makeResult(sevenDayPercent: 20.0, sevenDayResetsAt: sessionA))
        store.save(makeResult(sevenDayPercent: 50.0, sevenDayResetsAt: sessionB))
        store.save(makeResult(sevenDayPercent: 30.0, sevenDayResetsAt: sessionB))
        store.save(makeResult(sevenDayPercent: 10.0, sevenDayResetsAt: sessionC))
        store.save(makeResult(sevenDayPercent: 40.0, sevenDayResetsAt: sessionC))
        let result = store.loadDailyUsage(since: since)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 30.0, accuracy: 0.01,
                       "A[20,20]=0 + B[50,30]=0 + C[10,40]=30 → total 30%")
    }
}
