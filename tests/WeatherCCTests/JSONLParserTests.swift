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
}
