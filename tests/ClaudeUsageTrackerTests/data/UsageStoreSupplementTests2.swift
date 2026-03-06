// Supplement 2 for: docs/spec/data/usage-store.md
// Covers: checkIntegrity() corruption recovery, withDatabase double-Optional resolution
// Skipped: shared singleton test-env path (static let, not unit-testable)
import XCTest
import SQLite3
@testable import ClaudeUsageTracker

final class UsageStoreSupplementTests2: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("UsageStoreSupplementTests2-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    private func makeStore(filename: String = "usage.db") -> UsageStore {
        UsageStore(dbPath: tmpDir.appendingPathComponent(filename).path)
    }

    private func makeResult(
        fiveHourPercent: Double? = nil,
        sevenDayPercent: Double? = nil,
        fiveHourResetsAt: Date? = nil,
        sevenDayResetsAt: Date? = nil
    ) -> UsageResult {
        UsageResultFactory.make(
            fiveHourPercent: fiveHourPercent,
            sevenDayPercent: sevenDayPercent,
            fiveHourResetsAt: fiveHourResetsAt,
            sevenDayResetsAt: sevenDayResetsAt
        )
    }

    // MARK: - checkIntegrity: DB file does not exist -> no-op

    func testCheckIntegrity_noDBFile_noSideEffects() {
        // Spec: "DB file does not exist -> no-op (will be created on first write)"
        // Creating a UsageStore with a non-existent DB path should not create any files
        let dbPath = tmpDir.appendingPathComponent("nonexistent.db").path
        let _ = UsageStore(dbPath: dbPath)

        // The DB file should not be created by init alone (only on first write)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dbPath),
                       "checkIntegrity should not create the DB file when it doesn't exist")
    }

    // MARK: - checkIntegrity: healthy DB -> no-op

    func testCheckIntegrity_healthyDB_notRenamed() {
        // First create a valid DB by saving data
        let store = makeStore()
        store.save(makeResult(fiveHourPercent: 42.0))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.dbPath))

        // Creating a new UsageStore pointing to the same healthy DB should not rename it
        let store2 = UsageStore(dbPath: store.dbPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store2.dbPath),
                      "Healthy DB should not be renamed")
        let corruptPath = store.dbPath + ".corrupt"
        XCTAssertFalse(FileManager.default.fileExists(atPath: corruptPath),
                       "No .corrupt file should exist for a healthy DB")

        // Data should still be readable
        let history = store2.loadAllHistory()
        XCTAssertEqual(history.count, 1, "Data should be preserved in healthy DB")
    }

    // MARK: - checkIntegrity: corrupt DB -> rename to .corrupt

    func testCheckIntegrity_corruptDB_renamedToCorrupt() throws {
        let dbPath = tmpDir.appendingPathComponent("usage.db").path
        let corruptPath = dbPath + ".corrupt"

        // Write garbage to simulate a corrupt DB
        try "THIS IS NOT A SQLITE DATABASE".write(
            toFile: dbPath, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbPath))

        // Init triggers checkIntegrity which should detect corruption
        let _ = UsageStore(dbPath: dbPath)

        // Original DB should be gone (renamed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dbPath),
                       "Corrupt DB file should be renamed away")
        // .corrupt file should exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: corruptPath),
                      "Corrupt DB should be renamed to .corrupt")
    }

    // MARK: - checkIntegrity: WAL and SHM files deleted alongside corrupt DB

    func testCheckIntegrity_corruptDB_deletesWALAndSHM() throws {
        let dbPath = tmpDir.appendingPathComponent("usage.db").path
        let walPath = dbPath + "-wal"
        let shmPath = dbPath + "-shm"

        // Create corrupt DB and auxiliary files
        try "CORRUPT".write(toFile: dbPath, atomically: true, encoding: .utf8)
        try "WAL DATA".write(toFile: walPath, atomically: true, encoding: .utf8)
        try "SHM DATA".write(toFile: shmPath, atomically: true, encoding: .utf8)

        XCTAssertTrue(FileManager.default.fileExists(atPath: walPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: shmPath))

        // Init triggers checkIntegrity
        let _ = UsageStore(dbPath: dbPath)

        // WAL and SHM should be deleted
        XCTAssertFalse(FileManager.default.fileExists(atPath: walPath),
                       "WAL file should be deleted when DB is corrupt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: shmPath),
                       "SHM file should be deleted when DB is corrupt")
    }

    // MARK: - checkIntegrity: existing .corrupt file is replaced

    func testCheckIntegrity_existingCorruptFile_replacedByNewCorrupt() throws {
        let dbPath = tmpDir.appendingPathComponent("usage.db").path
        let corruptPath = dbPath + ".corrupt"

        // Create an old .corrupt file
        let oldContent = "OLD CORRUPT FILE"
        try oldContent.write(toFile: corruptPath, atomically: true, encoding: .utf8)

        // Create a new corrupt DB with different content
        let newContent = "NEW CORRUPT DB CONTENT"
        try newContent.write(toFile: dbPath, atomically: true, encoding: .utf8)

        // Init triggers checkIntegrity: should remove old .corrupt, rename new corrupt DB
        let _ = UsageStore(dbPath: dbPath)

        XCTAssertTrue(FileManager.default.fileExists(atPath: corruptPath),
                      ".corrupt file should exist after recovery")
        let resultContent = try String(contentsOfFile: corruptPath, encoding: .utf8)
        XCTAssertEqual(resultContent, newContent,
                       "Old .corrupt should be replaced by the newly corrupt DB")
    }

    // MARK: - checkIntegrity: fresh DB created on next write after recovery

    func testCheckIntegrity_afterRecovery_freshDBCreatedOnWrite() throws {
        let dbPath = tmpDir.appendingPathComponent("usage.db").path

        // Write corrupt data
        try "NOT SQLITE".write(toFile: dbPath, atomically: true, encoding: .utf8)

        // Init detects corruption and renames the file
        let store = UsageStore(dbPath: dbPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dbPath),
                       "Corrupt DB should have been renamed")

        // Save data -> should create a fresh DB via CREATE TABLE IF NOT EXISTS
        store.save(makeResult(fiveHourPercent: 99.0))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbPath),
                      "Fresh DB should be created on first write after recovery")

        // Verify the fresh DB is functional
        let history = store.loadAllHistory()
        XCTAssertEqual(history.count, 1, "Fresh DB should contain the newly saved data")
        XCTAssertEqual(history[0].fiveHourPercent, 99.0)
    }

    // MARK: - withDatabase: loadAllHistory returns [] on DB open failure

    func testLoadAllHistory_dbOpenFailure_returnsEmptyArray() {
        // Spec: withDatabase returns nil on open failure -> ?? [] yields empty array
        let store = UsageStore(dbPath: "/nonexistent/path/that/cannot/be/opened/usage.db")
        let result = store.loadAllHistory()
        XCTAssertTrue(result.isEmpty, "DB open failure should return empty array via ?? []")
    }

    // MARK: - withDatabase: loadHistory returns [] on DB open failure

    func testLoadHistory_dbOpenFailure_returnsEmptyArray() {
        // Spec: withDatabase returns nil on open failure -> ?? [] yields empty array
        let store = UsageStore(dbPath: "/nonexistent/path/that/cannot/be/opened/usage.db")
        let result = store.loadHistory(windowSeconds: 3600)
        XCTAssertTrue(result.isEmpty, "DB open failure should return empty array via ?? []")
    }

    // MARK: - withDatabase: loadDailyUsage returns nil on DB open failure

    func testLoadDailyUsage_dbOpenFailure_returnsNil() {
        // Spec: withDatabase returns nil -> loadDailyUsage returns nil
        // This is distinct from "insufficient data" nil (< 2 records)
        let store = UsageStore(dbPath: "/nonexistent/path/that/cannot/be/opened/usage.db")
        let result = store.loadDailyUsage(since: Date(timeIntervalSinceNow: -3600))
        XCTAssertNil(result, "DB open failure should return nil")
    }

    // MARK: - withDatabase: save silently fails on DB open failure (no crash)

    func testSave_dbOpenFailure_doesNotCrash() {
        // Spec: save does not use the return value of withDatabase
        // This test verifies no crash occurs (the assertion is that it completes)
        let store = UsageStore(dbPath: "/nonexistent/path/that/cannot/be/opened/usage.db")
        store.save(makeResult(fiveHourPercent: 42.0))
        // If we reach here without crash, the test passes
    }
}
