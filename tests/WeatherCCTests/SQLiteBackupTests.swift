import XCTest
import SQLite3
import WeatherCCShared

final class SQLiteBackupTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SQLiteBackupTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func createTestDB(name: String = "test.db") -> String {
        let path = tempDir.appendingPathComponent(name).path
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            XCTFail("Failed to create test DB")
            return path
        }
        sqlite3_exec(db, "CREATE TABLE t (id INTEGER PRIMARY KEY);", nil, nil, nil)
        sqlite3_exec(db, "INSERT INTO t VALUES (1);", nil, nil, nil)
        sqlite3_close(db)
        return path
    }

    // MARK: - Tests

    func testPerform_createsBackupFile() {
        let dbPath = createTestDB()
        SQLiteBackup.perform(dbPath: dbPath)

        let fm = FileManager.default
        let files = try! fm.contentsOfDirectory(atPath: tempDir.path)
        let backups = files.filter { $0.hasSuffix(".bak") }
        XCTAssertEqual(backups.count, 1, "Should create exactly one backup")

        let today = todayStamp()
        XCTAssertTrue(backups[0].contains(today), "Backup should contain today's date")
    }

    func testPerform_skipsSameDayDuplicate() {
        let dbPath = createTestDB()
        SQLiteBackup.perform(dbPath: dbPath)
        SQLiteBackup.perform(dbPath: dbPath)

        let files = try! FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        let backups = files.filter { $0.hasSuffix(".bak") }
        XCTAssertEqual(backups.count, 1, "Should not create duplicate backup on same day")
    }

    func testPerform_deletesOldBackups() {
        let dbPath = createTestDB()

        // Manually create a 4-day-old backup
        let oldName = "test-\(dateStamp(daysAgo: 4)).bak"
        let oldURL = tempDir.appendingPathComponent(oldName)
        FileManager.default.createFile(atPath: oldURL.path, contents: Data("old".utf8))

        SQLiteBackup.perform(dbPath: dbPath, retentionDays: 3)

        let fm = FileManager.default
        XCTAssertFalse(fm.fileExists(atPath: oldURL.path), "4-day-old backup should be deleted")

        let files = try! fm.contentsOfDirectory(atPath: tempDir.path)
        let backups = files.filter { $0.hasSuffix(".bak") }
        XCTAssertEqual(backups.count, 1, "Only today's backup should remain")
    }

    func testPerform_keepsRecentBackups() {
        let dbPath = createTestDB()

        // Manually create a 2-day-old backup
        let recentName = "test-\(dateStamp(daysAgo: 2)).bak"
        let recentURL = tempDir.appendingPathComponent(recentName)
        FileManager.default.createFile(atPath: recentURL.path, contents: Data("recent".utf8))

        SQLiteBackup.perform(dbPath: dbPath, retentionDays: 3)

        XCTAssertTrue(FileManager.default.fileExists(atPath: recentURL.path),
                       "2-day-old backup should be kept (within 3-day retention)")
    }

    func testPerform_noDBFile_noError() {
        let nonexistent = tempDir.appendingPathComponent("does_not_exist.db").path
        // Should not crash
        SQLiteBackup.perform(dbPath: nonexistent)
    }

    // MARK: - Helpers

    private func todayStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: Date())
    }

    private func dateStamp(daysAgo: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return f.string(from: date)
    }
}
