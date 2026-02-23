import XCTest
@testable import WeatherCC

final class TokenStoreTests: XCTestCase {

    private var tmpDir: URL!
    private var store: TokenStore!
    private var jsonlDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStoreTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        store = TokenStore(dbPath: tmpDir.appendingPathComponent("tokens.db").path)

        jsonlDir = tmpDir.appendingPathComponent("jsonl")
        try! FileManager.default.createDirectory(at: jsonlDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    private func writeJSONLFile(name: String, lines: [String]) -> URL {
        let url = jsonlDir.appendingPathComponent(name)
        let content = lines.joined(separator: "\n")
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeAssistantLine(
        requestId: String,
        timestamp: String = "2026-02-22T10:00:00.000Z",
        model: String = "claude-sonnet-4-6",
        inputTokens: Int = 100,
        outputTokens: Int = 200
    ) -> String {
        return """
        {"type":"assistant","requestId":"\(requestId)","timestamp":"\(timestamp)","message":{"model":"\(model)","usage":{"input_tokens":\(inputTokens),"output_tokens":\(outputTokens),"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
        """
    }

    // MARK: - Sync

    func testSync_createsTablesOnEmptyDB() {
        let _ = writeJSONLFile(name: "test.jsonl", lines: [
            makeAssistantLine(requestId: "req_001")
        ])
        store.sync(directories: [jsonlDir])

        let records = store.loadAll()
        XCTAssertEqual(records.count, 1)
    }

    func testSync_insertsRecords() {
        let _ = writeJSONLFile(name: "test.jsonl", lines: [
            makeAssistantLine(requestId: "req_001", timestamp: "2026-02-22T10:00:00.000Z"),
            makeAssistantLine(requestId: "req_002", timestamp: "2026-02-22T11:00:00.000Z"),
            makeAssistantLine(requestId: "req_003", timestamp: "2026-02-22T12:00:00.000Z"),
        ])
        store.sync(directories: [jsonlDir])

        let records = store.loadAll()
        XCTAssertEqual(records.count, 3)
    }

    func testSync_upsertKeepsHigherOutput() {
        let _ = writeJSONLFile(name: "file1.jsonl", lines: [
            makeAssistantLine(requestId: "req_dup", outputTokens: 50),
        ])
        let _ = writeJSONLFile(name: "file2.jsonl", lines: [
            makeAssistantLine(requestId: "req_dup", outputTokens: 200),
        ])
        store.sync(directories: [jsonlDir])

        let records = store.loadAll()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].outputTokens, 200, "Should keep record with higher output_tokens")
    }

    func testSync_skipsAlreadyProcessed() {
        let _ = writeJSONLFile(name: "test.jsonl", lines: [
            makeAssistantLine(requestId: "req_001"),
        ])
        store.sync(directories: [jsonlDir])
        XCTAssertEqual(store.loadAll().count, 1)

        // Sync again without modifying file
        store.sync(directories: [jsonlDir])
        XCTAssertEqual(store.loadAll().count, 1, "Should not re-process unchanged file")
    }

    func testSync_reprocessesModifiedFile() {
        let url = writeJSONLFile(name: "test.jsonl", lines: [
            makeAssistantLine(requestId: "req_001"),
        ])
        store.sync(directories: [jsonlDir])
        XCTAssertEqual(store.loadAll().count, 1)

        // Modify file (add a record, update mtime)
        sleep(2) // ensure mtime changes (filesystem granularity)
        let newContent = [
            makeAssistantLine(requestId: "req_001"),
            makeAssistantLine(requestId: "req_002", timestamp: "2026-02-22T11:00:00.000Z"),
        ].joined(separator: "\n")
        try! newContent.write(to: url, atomically: true, encoding: .utf8)

        store.sync(directories: [jsonlDir])
        XCTAssertEqual(store.loadAll().count, 2, "Should re-process modified file")
    }

    // MARK: - Query

    func testLoadAll_empty() {
        // Need to create tables first by syncing empty dir
        store.sync(directories: [])
        let records = store.loadAll()
        XCTAssertEqual(records.count, 0)
    }

    func testLoadAll_orderedByTimestamp() {
        let _ = writeJSONLFile(name: "test.jsonl", lines: [
            makeAssistantLine(requestId: "req_003", timestamp: "2026-02-22T12:00:00.000Z"),
            makeAssistantLine(requestId: "req_001", timestamp: "2026-02-22T10:00:00.000Z"),
            makeAssistantLine(requestId: "req_002", timestamp: "2026-02-22T11:00:00.000Z"),
        ])
        store.sync(directories: [jsonlDir])

        let records = store.loadAll()
        XCTAssertEqual(records.count, 3)
        for i in 1..<records.count {
            XCTAssertTrue(records[i].timestamp >= records[i-1].timestamp,
                          "Records should be ordered by timestamp ASC")
        }
    }

    func testLoadRecords_sinceCutoff() {
        let _ = writeJSONLFile(name: "test.jsonl", lines: [
            makeAssistantLine(requestId: "req_old", timestamp: "2026-02-20T10:00:00.000Z"),
            makeAssistantLine(requestId: "req_new", timestamp: "2026-02-22T10:00:00.000Z"),
        ])
        store.sync(directories: [jsonlDir])

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let cutoff = iso.date(from: "2026-02-21T00:00:00.000Z")!

        let records = store.loadRecords(since: cutoff)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].requestId, "req_new")
    }

    func testSync_multipleDirectories() {
        let dir2 = tmpDir.appendingPathComponent("jsonl2")
        try! FileManager.default.createDirectory(at: dir2, withIntermediateDirectories: true)

        let _ = writeJSONLFile(name: "a.jsonl", lines: [
            makeAssistantLine(requestId: "req_a", timestamp: "2026-02-22T10:00:00.000Z"),
        ])
        let content = makeAssistantLine(requestId: "req_b", timestamp: "2026-02-22T11:00:00.000Z")
        try! content.write(to: dir2.appendingPathComponent("b.jsonl"), atomically: true, encoding: .utf8)

        store.sync(directories: [jsonlDir, dir2])
        XCTAssertEqual(store.loadAll().count, 2)
    }

    // MARK: - Load Before Sync (DB doesn't exist)

    func testLoadAll_beforeSync() {
        // DB file doesn't exist yet — should return empty, not crash
        let freshStore = TokenStore(dbPath: tmpDir.appendingPathComponent("fresh.db").path)
        let records = freshStore.loadAll()
        XCTAssertEqual(records.count, 0, "loadAll before any sync should return empty array")
    }

    func testLoadRecords_beforeSync() {
        let freshStore = TokenStore(dbPath: tmpDir.appendingPathComponent("fresh2.db").path)
        let records = freshStore.loadRecords(since: Date.distantPast)
        XCTAssertEqual(records.count, 0, "loadRecords before any sync should return empty array")
    }

    // MARK: - Sync with Empty Directory

    func testSync_emptyDirectory() {
        let emptyDir = tmpDir.appendingPathComponent("empty")
        try! FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)

        store.sync(directories: [emptyDir])
        let records = store.loadAll()
        XCTAssertEqual(records.count, 0, "Sync with empty directory should produce no records")
    }

    // MARK: - Web Search Requests (documented: NOT stored in DB)

    func testSync_upsertKeepsOldWhenNewIsLower() {
        let _ = writeJSONLFile(name: "high.jsonl", lines: [
            makeAssistantLine(requestId: "req_keep", outputTokens: 500),
        ])
        store.sync(directories: [jsonlDir])
        XCTAssertEqual(store.loadAll().count, 1)
        XCTAssertEqual(store.loadAll()[0].outputTokens, 500)

        // Add a second file with same requestId but lower outputTokens
        sleep(2) // ensure different mtime
        let _ = writeJSONLFile(name: "low.jsonl", lines: [
            makeAssistantLine(requestId: "req_keep", outputTokens: 100),
        ])
        store.sync(directories: [jsonlDir])
        let records = store.loadAll()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].outputTokens, 500,
                       "Upsert should keep the OLD record when new has lower outputTokens")
    }

    func testSync_upsertEqualOutputTokensNewWins() {
        let _ = writeJSONLFile(name: "first.jsonl", lines: [
            makeAssistantLine(requestId: "req_eq", inputTokens: 100, outputTokens: 200),
        ])
        store.sync(directories: [jsonlDir])

        sleep(2)
        let _ = writeJSONLFile(name: "second.jsonl", lines: [
            makeAssistantLine(requestId: "req_eq", inputTokens: 999, outputTokens: 200),
        ])
        store.sync(directories: [jsonlDir])
        let records = store.loadAll()
        XCTAssertEqual(records.count, 1)
        // >= means equal output_tokens → new record wins
        XCTAssertEqual(records[0].inputTokens, 999,
                       "Equal outputTokens: new record should replace old (>= condition)")
    }

    func testSync_webSearchRequestsNotPreserved() {
        // token_records table has no web_search_requests column
        // Records loaded from DB always have webSearchRequests = 0
        let line = #"{"type":"assistant","requestId":"req_ws","timestamp":"2026-02-22T10:00:00.000Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":10,"output_tokens":20,"server_tool_use":{"web_search_requests":5}}}}"#
        let file = jsonlDir.appendingPathComponent("ws.jsonl")
        try! line.write(to: file, atomically: true, encoding: .utf8)

        store.sync(directories: [jsonlDir])
        let records = store.loadAll()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].webSearchRequests, 0,
                       "web_search_requests is not stored in DB (documented limitation)")
    }

    // MARK: - loadRecords Boundary

    func testLoadRecords_exactCutoff() {
        let _ = writeJSONLFile(name: "test.jsonl", lines: [
            makeAssistantLine(requestId: "req_at", timestamp: "2026-02-22T10:00:00.000Z"),
            makeAssistantLine(requestId: "req_after", timestamp: "2026-02-22T10:00:01.000Z"),
            makeAssistantLine(requestId: "req_before", timestamp: "2026-02-22T09:59:59.000Z"),
        ])
        store.sync(directories: [jsonlDir])

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let cutoff = iso.date(from: "2026-02-22T10:00:00.000Z")!

        let records = store.loadRecords(since: cutoff)
        // >= cutoff, so req_at and req_after should be included
        XCTAssertEqual(records.count, 2,
                       "Record exactly at cutoff should be included (>=)")
        let ids = Set(records.map { $0.requestId })
        XCTAssertTrue(ids.contains("req_at"))
        XCTAssertTrue(ids.contains("req_after"))
        XCTAssertFalse(ids.contains("req_before"))
    }

    // MARK: - Speed Hardcoded

    func testLoadAll_speedIsAlwaysStandard() {
        let _ = writeJSONLFile(name: "test.jsonl", lines: [
            makeAssistantLine(requestId: "req_speed"),
        ])
        store.sync(directories: [jsonlDir])
        let records = store.loadAll()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].speed, "standard",
                       "speed is hardcoded to 'standard' when loaded from DB")
    }

    // MARK: - Sync with invalid path (directory creation failure)

    func testSync_invalidPath_silentlyFails() {
        let badStore = TokenStore(dbPath: "/dev/null/impossible/tokens.db")
        // Should not crash
        badStore.sync(directories: [jsonlDir])
        let records = badStore.loadAll()
        XCTAssertEqual(records.count, 0, "Sync with invalid DB path should silently fail")
    }

    // MARK: - Sync with file URL as directory (enumerator returns nil)

    func testSync_fileURLAsDirectory_skipped() {
        // Create a regular file and pass it as a "directory"
        let fileURL = tmpDir.appendingPathComponent("notADir.jsonl")
        try! "dummy".write(to: fileURL, atomically: true, encoding: .utf8)

        // Also provide the real jsonl dir with 1 record
        let _ = writeJSONLFile(name: "real.jsonl", lines: [
            makeAssistantLine(requestId: "req_real"),
        ])

        // Sync with both: file URL (enumerator returns nil → continue) + real dir
        store.sync(directories: [fileURL, jsonlDir])
        let records = store.loadAll()
        XCTAssertEqual(records.count, 1,
                       "File URL should be skipped (enumerator nil), real dir should work")
    }

    // MARK: - Load from corrupt DB file

    func testLoadAll_corruptDB() throws {
        // Write garbage to the DB file path
        let dbPath = tmpDir.appendingPathComponent("corrupt.db").path
        let corruptStore = TokenStore(dbPath: dbPath)

        // First create valid DB with data
        let _ = writeJSONLFile(name: "test.jsonl", lines: [
            makeAssistantLine(requestId: "req_001"),
        ])
        corruptStore.sync(directories: [jsonlDir])
        XCTAssertEqual(corruptStore.loadAll().count, 1)

        // Now corrupt the DB by overwriting with garbage
        try "THIS IS NOT A SQLITE DATABASE".write(
            toFile: dbPath, atomically: true, encoding: .utf8
        )

        // loadAll should return empty (sqlite3_open_v2 or prepare fails)
        let records = corruptStore.loadAll()
        XCTAssertEqual(records.count, 0,
                       "Corrupt DB should return empty array, not crash")
    }
}
