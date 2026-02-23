import XCTest
@testable import WeatherCC

final class JSONLParserTests: XCTestCase {

    // MARK: - Single Record

    func testParseSingleRecord() {
        let line = """
        {"type":"assistant","requestId":"req_001","timestamp":"2026-02-16T10:00:00.000Z","message":{"model":"claude-sonnet-4-6","usage":{"speed":"standard","input_tokens":100,"output_tokens":200,"cache_read_input_tokens":500,"cache_creation_input_tokens":50,"server_tool_use":{"web_search_requests":1}}}}
        """
        let records = JSONLParser.parseLines([line])
        XCTAssertEqual(records.count, 1)

        let r = records[0]
        XCTAssertEqual(r.requestId, "req_001")
        XCTAssertEqual(r.model, "claude-sonnet-4-6")
        XCTAssertEqual(r.speed, "standard")
        XCTAssertEqual(r.inputTokens, 100)
        XCTAssertEqual(r.outputTokens, 200)
        XCTAssertEqual(r.cacheReadTokens, 500)
        XCTAssertEqual(r.cacheCreationTokens, 50)
        XCTAssertEqual(r.webSearchRequests, 1)
    }

    // MARK: - Filter Non-Assistant

    func testParseSkipsNonAssistant() {
        let lines = [
            #"{"type":"user","requestId":"req_u1","timestamp":"2026-02-16T10:00:00Z","message":{"usage":{"input_tokens":10,"output_tokens":20}}}"#,
            #"{"type":"system","requestId":"req_s1","timestamp":"2026-02-16T10:00:00Z","message":{"usage":{"input_tokens":10,"output_tokens":20}}}"#,
        ]
        let records = JSONLParser.parseLines(lines)
        XCTAssertEqual(records.count, 0, "Non-assistant records should be skipped")
    }

    // MARK: - Filter No Usage

    func testParseSkipsNoUsage() {
        let line = #"{"type":"assistant","requestId":"req_002","timestamp":"2026-02-16T10:00:00Z","message":{"model":"claude-sonnet-4-6"}}"#
        let records = JSONLParser.parseLines([line])
        XCTAssertEqual(records.count, 0, "Assistant records without usage should be skipped")
    }

    // MARK: - Deduplication

    func testDeduplicateByRequestId() {
        let lines = [
            #"{"type":"assistant","requestId":"req_dup","timestamp":"2026-02-16T10:00:00Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":100,"output_tokens":50}}}"#,
            #"{"type":"assistant","requestId":"req_dup","timestamp":"2026-02-16T10:00:01Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":100,"output_tokens":200}}}"#,
            #"{"type":"assistant","requestId":"req_dup","timestamp":"2026-02-16T10:00:02Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":100,"output_tokens":150}}}"#,
        ]
        let records = JSONLParser.parseLines(lines)
        XCTAssertEqual(records.count, 1, "Same requestId should be deduplicated to one record")
        XCTAssertEqual(records[0].outputTokens, 200, "Should keep record with highest output_tokens")
    }

    // MARK: - Invalid JSON

    func testParseInvalidJSON() {
        let lines = [
            "this is not json",
            "{invalid json}",
            "",
        ]
        let records = JSONLParser.parseLines(lines)
        XCTAssertEqual(records.count, 0, "Invalid JSON lines should be silently skipped")
    }

    // MARK: - Empty Input

    func testParseEmptyLines() {
        let records = JSONLParser.parseLines([])
        XCTAssertEqual(records.count, 0, "Empty input should return empty array")
    }

    // MARK: - Timestamp Parsing

    func testParseTimestampWithoutFractionalSeconds() {
        let line = #"{"type":"assistant","requestId":"req_ts","timestamp":"2026-02-16T10:00:00Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":10,"output_tokens":20}}}"#
        let records = JSONLParser.parseLines([line])
        XCTAssertEqual(records.count, 1, "ISO 8601 without fractional seconds should parse")
    }

    func testParseTimestampWithFractionalSeconds() {
        let line = #"{"type":"assistant","requestId":"req_ts2","timestamp":"2026-02-16T10:00:00.408Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":10,"output_tokens":20}}}"#
        let records = JSONLParser.parseLines([line])
        XCTAssertEqual(records.count, 1, "ISO 8601 with fractional seconds should parse")
    }

    // MARK: - File I/O

    func testParseFile_validFile() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("JSONLParserTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let content = """
        {"type":"assistant","requestId":"req_f1","timestamp":"2026-02-16T10:00:00.000Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":100,"output_tokens":200}}}
        {"type":"assistant","requestId":"req_f2","timestamp":"2026-02-16T11:00:00.000Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":50,"output_tokens":100}}}
        """
        let file = tmpDir.appendingPathComponent("test.jsonl")
        try content.write(to: file, atomically: true, encoding: .utf8)

        let records = JSONLParser.parseFile(file)
        XCTAssertEqual(records.count, 2)
    }

    func testParseFile_emptyFile() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("JSONLParserTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let file = tmpDir.appendingPathComponent("empty.jsonl")
        try "".write(to: file, atomically: true, encoding: .utf8)

        let records = JSONLParser.parseFile(file)
        XCTAssertEqual(records.count, 0)
    }

    func testParseFile_nonexistentFile() {
        let file = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).jsonl")
        let records = JSONLParser.parseFile(file)
        XCTAssertEqual(records.count, 0)
    }

    func testParseFile_mixedValidInvalid() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("JSONLParserTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let content = """
        {"type":"assistant","requestId":"req_ok","timestamp":"2026-02-16T10:00:00.000Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":100,"output_tokens":200}}}
        invalid json line
        {"type":"user","requestId":"req_u","timestamp":"2026-02-16T10:00:00.000Z","message":{}}
        {"type":"assistant","requestId":"req_ok2","timestamp":"2026-02-16T11:00:00.000Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":50,"output_tokens":100}}}
        """
        let file = tmpDir.appendingPathComponent("mixed.jsonl")
        try content.write(to: file, atomically: true, encoding: .utf8)

        let records = JSONLParser.parseFile(file)
        XCTAssertEqual(records.count, 2, "Only valid assistant records should be parsed")
    }

    // MARK: - Edge Cases

    func testParseLines_missingModel() {
        let line = #"{"type":"assistant","requestId":"req_nm","timestamp":"2026-02-16T10:00:00.000Z","message":{"usage":{"input_tokens":10,"output_tokens":20}}}"#
        let records = JSONLParser.parseLines([line])
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].model, "unknown", "Missing model should default to 'unknown'")
    }

    func testParseLines_missingSpeed() {
        let line = #"{"type":"assistant","requestId":"req_ns","timestamp":"2026-02-16T10:00:00.000Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":10,"output_tokens":20}}}"#
        let records = JSONLParser.parseLines([line])
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].speed, "standard", "Missing speed should default to 'standard'")
    }

    func testParseLines_webSearchRequests() {
        let line = #"{"type":"assistant","requestId":"req_ws","timestamp":"2026-02-16T10:00:00.000Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":10,"output_tokens":20,"server_tool_use":{"web_search_requests":3}}}}"#
        let records = JSONLParser.parseLines([line])
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].webSearchRequests, 3)
    }

    func testParseLines_missingRequestId() {
        let line = #"{"type":"assistant","timestamp":"2026-02-16T10:00:00.000Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":10,"output_tokens":20}}}"#
        let records = JSONLParser.parseLines([line])
        XCTAssertEqual(records.count, 0, "Missing requestId should be skipped")
    }

    func testParseLines_missingTimestamp() {
        let line = #"{"type":"assistant","requestId":"req_nots","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":10,"output_tokens":20}}}"#
        let records = JSONLParser.parseLines([line])
        XCTAssertEqual(records.count, 0, "Missing timestamp should be skipped")
    }

    func testParseLines_missingMessage() {
        let line = #"{"type":"assistant","requestId":"req_nomsg","timestamp":"2026-02-16T10:00:00.000Z"}"#
        let records = JSONLParser.parseLines([line])
        XCTAssertEqual(records.count, 0, "Missing message key should be skipped")
    }

    // MARK: - parseDirectory

    private func makeTestDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("JSONLParserDirTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeFile(_ dir: URL, name: String, content: String) throws {
        let file = dir.appendingPathComponent(name)
        try content.write(to: file, atomically: true, encoding: .utf8)
    }

    private let sampleLine1 = #"{"type":"assistant","requestId":"req_d1","timestamp":"2026-02-16T10:00:00.000Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":100,"output_tokens":200}}}"#
    private let sampleLine2 = #"{"type":"assistant","requestId":"req_d2","timestamp":"2026-02-16T11:00:00.000Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":50,"output_tokens":100}}}"#

    func testParseDirectory_basic() throws {
        let dir = try makeTestDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeFile(dir, name: "a.jsonl", content: sampleLine1)
        try writeFile(dir, name: "b.jsonl", content: sampleLine2)

        let records = JSONLParser.parseDirectory(dir)
        XCTAssertEqual(records.count, 2, "Should parse all .jsonl files in directory")
    }

    func testParseDirectory_ignoresNonJsonl() throws {
        let dir = try makeTestDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeFile(dir, name: "data.jsonl", content: sampleLine1)
        try writeFile(dir, name: "data.txt", content: sampleLine2)
        try writeFile(dir, name: "data.json", content: sampleLine2)

        let records = JSONLParser.parseDirectory(dir)
        XCTAssertEqual(records.count, 1, "Should only parse .jsonl files")
    }

    func testParseDirectory_emptyDirectory() throws {
        let dir = try makeTestDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let records = JSONLParser.parseDirectory(dir)
        XCTAssertEqual(records.count, 0, "Empty directory should return empty array")
    }

    func testParseDirectory_nonexistentDirectory() {
        let dir = URL(fileURLWithPath: "/tmp/nonexistent-dir-\(UUID().uuidString)")
        let records = JSONLParser.parseDirectory(dir)
        XCTAssertEqual(records.count, 0, "Non-existent directory should return empty array")
    }

    func testParseDirectory_crossFileDeduplication() throws {
        let dir = try makeTestDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Same requestId in two different files, different output_tokens
        let line_low = #"{"type":"assistant","requestId":"req_cross","timestamp":"2026-02-16T10:00:00.000Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":100,"output_tokens":50}}}"#
        let line_high = #"{"type":"assistant","requestId":"req_cross","timestamp":"2026-02-16T10:00:01.000Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":100,"output_tokens":300}}}"#

        try writeFile(dir, name: "file1.jsonl", content: line_low)
        try writeFile(dir, name: "file2.jsonl", content: line_high)

        let records = JSONLParser.parseDirectory(dir)
        XCTAssertEqual(records.count, 1, "Same requestId across files should be deduplicated")
        XCTAssertEqual(records[0].outputTokens, 300, "Should keep record with higher output_tokens")
    }

    func testParseDirectory_skipsHiddenFiles() throws {
        let dir = try makeTestDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeFile(dir, name: "visible.jsonl", content: sampleLine1)
        try writeFile(dir, name: ".hidden.jsonl", content: sampleLine2)

        let records = JSONLParser.parseDirectory(dir)
        XCTAssertEqual(records.count, 1, "Hidden files should be skipped")
        XCTAssertEqual(records[0].requestId, "req_d1")
    }

    func testParseDirectory_maxAgeFilter() throws {
        let dir = try makeTestDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let recentFile = dir.appendingPathComponent("recent.jsonl")
        try sampleLine1.write(to: recentFile, atomically: true, encoding: .utf8)

        let oldFile = dir.appendingPathComponent("old.jsonl")
        try sampleLine2.write(to: oldFile, atomically: true, encoding: .utf8)

        // Set old file's modification date to 2 days ago
        let twoDaysAgo = Date().addingTimeInterval(-2 * 24 * 3600)
        try FileManager.default.setAttributes(
            [.modificationDate: twoDaysAgo], ofItemAtPath: oldFile.path
        )

        // maxAge = 1 day — should skip old file
        let records = JSONLParser.parseDirectory(dir, maxAge: 24 * 3600)
        XCTAssertEqual(records.count, 1, "Files older than maxAge should be skipped")
        XCTAssertEqual(records[0].requestId, "req_d1")
    }

    func testParseDirectory_recursesSubdirectories() throws {
        let dir = try makeTestDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // File in root
        try writeFile(dir, name: "root.jsonl", content: sampleLine1)

        // File in nested subdirectory
        let subdir = dir.appendingPathComponent("sub/deep")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try sampleLine2.write(
            to: subdir.appendingPathComponent("nested.jsonl"),
            atomically: true, encoding: .utf8
        )

        let records = JSONLParser.parseDirectory(dir)
        XCTAssertEqual(records.count, 2, "Should recurse into subdirectories")
    }

    // MARK: - parseLine: missing token keys default to 0

    func testParseLines_missingTokenKeys() {
        // usage block with only input_tokens — all others should default to 0
        let line = #"{"type":"assistant","requestId":"req_deftoken","timestamp":"2026-02-16T10:00:00.000Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":42}}}"#
        let records = JSONLParser.parseLines([line])
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].inputTokens, 42)
        XCTAssertEqual(records[0].outputTokens, 0, "Missing output_tokens should default to 0")
        XCTAssertEqual(records[0].cacheReadTokens, 0, "Missing cache_read should default to 0")
        XCTAssertEqual(records[0].cacheCreationTokens, 0, "Missing cache_creation should default to 0")
        XCTAssertEqual(records[0].webSearchRequests, 0, "Missing web_search should default to 0")
    }

    // MARK: - parseLine: invalid timestamp value

    func testParseLines_invalidTimestampValue() {
        let line = #"{"type":"assistant","requestId":"req_badts","timestamp":"not-a-date","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":10,"output_tokens":20}}}"#
        let records = JSONLParser.parseLines([line])
        XCTAssertEqual(records.count, 0, "Invalid timestamp value should cause line to be skipped")
    }

    // MARK: - Deduplication: equal outputTokens

    func testDeduplicateEqualOutputTokens() {
        let lines = [
            #"{"type":"assistant","requestId":"req_eq","timestamp":"2026-02-16T10:00:00Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":100,"output_tokens":200}}}"#,
            #"{"type":"assistant","requestId":"req_eq","timestamp":"2026-02-16T10:00:01Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":999,"output_tokens":200}}}"#,
        ]
        let records = JSONLParser.parseLines(lines)
        XCTAssertEqual(records.count, 1, "Equal outputTokens should deduplicate")
        // >= means the later-encountered record wins
        XCTAssertEqual(records[0].inputTokens, 999,
                       "Equal outputTokens: later record should win (>= condition)")
    }

    // MARK: - server_tool_use exists but web_search_requests missing

    func testParseLines_serverToolUseWithoutWebSearch() {
        let line = #"{"type":"assistant","requestId":"req_stu","timestamp":"2026-02-16T10:00:00.000Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":10,"output_tokens":20,"server_tool_use":{}}}}"#
        let records = JSONLParser.parseLines([line])
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].webSearchRequests, 0,
                       "server_tool_use without web_search_requests should default to 0")
    }
}
