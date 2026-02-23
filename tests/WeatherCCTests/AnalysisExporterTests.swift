import XCTest
@testable import WeatherCC

final class AnalysisExporterTests: XCTestCase {

    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - usageDataJSON

    func testUsageDataJSON_empty() {
        let json = AnalysisExporter.usageDataJSON(from: [])
        XCTAssertEqual(json, "[]")
    }

    func testUsageDataJSON_singlePoint() throws {
        let ts = iso.date(from: "2026-02-22T10:00:00.000Z")!
        let dp = UsageStore.DataPoint(
            timestamp: ts,
            fiveHourPercent: 42.5,
            sevenDayPercent: 15.0
        )
        let json = AnalysisExporter.usageDataJSON(from: [dp])
        let data = json.data(using: .utf8)!
        let array = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]

        XCTAssertEqual(array.count, 1)
        XCTAssertEqual(array[0]["five_hour_percent"] as? Double, 42.5)
        XCTAssertEqual(array[0]["seven_day_percent"] as? Double, 15.0)
        XCTAssertNotNil(array[0]["timestamp"] as? String)
    }

    func testUsageDataJSON_nullPercent() throws {
        let ts = iso.date(from: "2026-02-22T10:00:00.000Z")!
        let dp = UsageStore.DataPoint(
            timestamp: ts,
            fiveHourPercent: nil,
            sevenDayPercent: nil
        )
        let json = AnalysisExporter.usageDataJSON(from: [dp])
        let data = json.data(using: .utf8)!
        let array = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]

        XCTAssertEqual(array.count, 1)
        XCTAssertTrue(array[0]["five_hour_percent"] is NSNull,
                      "nil percent should be serialized as null")
        XCTAssertTrue(array[0]["seven_day_percent"] is NSNull)
    }

    func testUsageDataJSON_resetsAtIncluded() throws {
        let ts = iso.date(from: "2026-02-22T10:00:00.000Z")!
        let resetsAt = iso.date(from: "2026-02-22T15:00:00.000Z")!
        let dp = UsageStore.DataPoint(
            timestamp: ts,
            fiveHourPercent: 50.0,
            sevenDayPercent: 20.0,
            fiveHourResetsAt: resetsAt,
            sevenDayResetsAt: resetsAt
        )
        let json = AnalysisExporter.usageDataJSON(from: [dp])
        let data = json.data(using: .utf8)!
        let array = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]

        XCTAssertNotNil(array[0]["five_hour_resets_at"] as? String)
        XCTAssertNotNil(array[0]["seven_day_resets_at"] as? String)
    }

    func testUsageDataJSON_resetsAtNull() throws {
        let ts = iso.date(from: "2026-02-22T10:00:00.000Z")!
        let dp = UsageStore.DataPoint(
            timestamp: ts,
            fiveHourPercent: 50.0,
            sevenDayPercent: 20.0,
            fiveHourResetsAt: nil,
            sevenDayResetsAt: nil
        )
        let json = AnalysisExporter.usageDataJSON(from: [dp])
        let data = json.data(using: .utf8)!
        let array = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]

        XCTAssertTrue(array[0]["five_hour_resets_at"] is NSNull)
        XCTAssertTrue(array[0]["seven_day_resets_at"] is NSNull)
    }

    // MARK: - tokenDataJSON

    func testTokenDataJSON_empty() {
        let json = AnalysisExporter.tokenDataJSON(from: [])
        XCTAssertEqual(json, "[]")
    }

    func testTokenDataJSON_costCalculated() throws {
        let record = TokenRecord(
            timestamp: iso.date(from: "2026-02-22T10:00:00.000Z")!,
            requestId: "req_001",
            model: "claude-sonnet-4-6",
            speed: "standard",
            inputTokens: 1_000_000,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            webSearchRequests: 0
        )
        let json = AnalysisExporter.tokenDataJSON(from: [record])
        let data = json.data(using: .utf8)!
        let array = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]

        XCTAssertEqual(array.count, 1)
        let cost = array[0]["costUSD"] as? Double ?? 0
        let expected = CostEstimator.cost(for: record)
        XCTAssertEqual(cost, expected, accuracy: 0.001,
                       "costUSD should match CostEstimator.cost()")
    }

    // MARK: - usageDataJSON Multiple Points

    func testUsageDataJSON_multiplePoints() throws {
        let ts1 = iso.date(from: "2026-02-22T10:00:00.000Z")!
        let ts2 = iso.date(from: "2026-02-22T11:00:00.000Z")!
        let ts3 = iso.date(from: "2026-02-22T12:00:00.000Z")!
        let points = [
            UsageStore.DataPoint(timestamp: ts1, fiveHourPercent: 10.0, sevenDayPercent: 5.0),
            UsageStore.DataPoint(timestamp: ts2, fiveHourPercent: 20.0, sevenDayPercent: 8.0),
            UsageStore.DataPoint(timestamp: ts3, fiveHourPercent: 30.0, sevenDayPercent: 12.0),
        ]
        let json = AnalysisExporter.usageDataJSON(from: points)
        let data = json.data(using: .utf8)!
        let array = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]

        XCTAssertEqual(array.count, 3, "Should have 3 entries")
        XCTAssertEqual(array[0]["five_hour_percent"] as? Double, 10.0)
        XCTAssertEqual(array[2]["five_hour_percent"] as? Double, 30.0)
    }

    // MARK: - tokenDataJSON Multiple Records

    func testTokenDataJSON_multipleRecords() throws {
        let records = [
            TokenRecord(timestamp: iso.date(from: "2026-02-22T10:00:00.000Z")!,
                        requestId: "req_m1", model: "claude-sonnet-4-6", speed: "standard",
                        inputTokens: 100, outputTokens: 200,
                        cacheReadTokens: 0, cacheCreationTokens: 0, webSearchRequests: 0),
            TokenRecord(timestamp: iso.date(from: "2026-02-22T11:00:00.000Z")!,
                        requestId: "req_m2", model: "claude-opus-4-6", speed: "standard",
                        inputTokens: 500, outputTokens: 1000,
                        cacheReadTokens: 0, cacheCreationTokens: 0, webSearchRequests: 0),
        ]
        let json = AnalysisExporter.tokenDataJSON(from: records)
        let data = json.data(using: .utf8)!
        let array = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]

        XCTAssertEqual(array.count, 2)
    }

    // MARK: - tokenDataJSON Timestamp Format

    func testTokenDataJSON_timestampIsISO8601() throws {
        let record = TokenRecord(
            timestamp: iso.date(from: "2026-02-22T10:00:00.000Z")!,
            requestId: "req_ts", model: "claude-sonnet-4-6", speed: "standard",
            inputTokens: 10, outputTokens: 20,
            cacheReadTokens: 0, cacheCreationTokens: 0, webSearchRequests: 0
        )
        let json = AnalysisExporter.tokenDataJSON(from: [record])
        let data = json.data(using: .utf8)!
        let array = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]

        let ts = array[0]["timestamp"] as? String
        XCTAssertNotNil(ts)
        XCTAssertTrue(ts!.contains("T"), "Timestamp should be ISO 8601 format")
        XCTAssertTrue(ts!.hasSuffix("Z"), "Timestamp should end with Z")
    }

    // MARK: - tokenDataJSON Zero Tokens

    // MARK: - Special Float Values

    func testUsageDataJSON_nanProducesInvalidJSON() throws {
        let ts = iso.date(from: "2026-02-22T10:00:00.000Z")!
        let dp = UsageStore.DataPoint(
            timestamp: ts,
            fiveHourPercent: Double.nan,
            sevenDayPercent: Double.infinity
        )
        let json = AnalysisExporter.usageDataJSON(from: [dp])
        // NaN/Infinity produce "nan"/"inf" in Swift String interpolation,
        // which is NOT valid JSON. Document this known issue.
        let data = json.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: data)
        // This test documents the current behavior: NaN/Inf produces invalid JSON
        // If this test starts PASSING (parsed != nil), it means the bug was fixed
        XCTAssertNil(parsed,
                     "NaN/Infinity in DataPoint produces invalid JSON (known issue)")
    }

    func testTokenDataJSON_zeroTokens() throws {
        let record = TokenRecord(
            timestamp: iso.date(from: "2026-02-22T10:00:00.000Z")!,
            requestId: "req_zero", model: "claude-sonnet-4-6", speed: "standard",
            inputTokens: 0, outputTokens: 0,
            cacheReadTokens: 0, cacheCreationTokens: 0, webSearchRequests: 0
        )
        let json = AnalysisExporter.tokenDataJSON(from: [record])
        let data = json.data(using: .utf8)!
        let array = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]

        XCTAssertEqual(array.count, 1)
        XCTAssertEqual(array[0]["costUSD"] as? Double, 0.0,
                       "All zero tokens should produce costUSD = 0")
    }

    // MARK: - Mixed null/non-null resets_at

    func testUsageDataJSON_mixedResetsAt() throws {
        let ts = iso.date(from: "2026-02-22T10:00:00.000Z")!
        let resetsAt = iso.date(from: "2026-02-22T15:00:00.000Z")!
        let dp = UsageStore.DataPoint(
            timestamp: ts,
            fiveHourPercent: 50.0,
            sevenDayPercent: 20.0,
            fiveHourResetsAt: resetsAt,
            sevenDayResetsAt: nil   // one nil, one not
        )
        let json = AnalysisExporter.usageDataJSON(from: [dp])
        let data = json.data(using: .utf8)!
        let array = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]

        XCTAssertEqual(array.count, 1)
        XCTAssertNotNil(array[0]["five_hour_resets_at"] as? String,
                        "Non-nil resets_at should be a string")
        XCTAssertTrue(array[0]["seven_day_resets_at"] is NSNull,
                      "Nil resets_at should be null")
    }

    // MARK: - tokenDataJSON: small cost values produce valid JSON

    // MARK: - tokenDataJSON: verify all expected keys present

    func testTokenDataJSON_allExpectedKeysPresent() throws {
        let record = TokenRecord(
            timestamp: iso.date(from: "2026-02-22T10:00:00.000Z")!,
            requestId: "req_keys", model: "claude-sonnet-4-6", speed: "standard",
            inputTokens: 1000, outputTokens: 2000,
            cacheReadTokens: 500, cacheCreationTokens: 100, webSearchRequests: 2
        )
        let json = AnalysisExporter.tokenDataJSON(from: [record])
        let data = json.data(using: .utf8)!
        let array = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]

        XCTAssertEqual(array.count, 1)
        let entry = array[0]
        // tokenDataJSON only includes timestamp and costUSD
        XCTAssertNotNil(entry["timestamp"] as? String, "Should have timestamp key")
        XCTAssertNotNil(entry["costUSD"] as? Double, "Should have costUSD key")
        // Verify no extra unexpected keys
        XCTAssertEqual(entry.count, 2, "tokenDataJSON should only have timestamp and costUSD")
    }

    // MARK: - usageDataJSON: verify all expected keys present

    func testUsageDataJSON_allExpectedKeysPresent() throws {
        let ts = iso.date(from: "2026-02-22T10:00:00.000Z")!
        let resetsAt = iso.date(from: "2026-02-22T15:00:00.000Z")!
        let dp = UsageStore.DataPoint(
            timestamp: ts,
            fiveHourPercent: 42.5,
            sevenDayPercent: 15.0,
            fiveHourResetsAt: resetsAt,
            sevenDayResetsAt: resetsAt
        )
        let json = AnalysisExporter.usageDataJSON(from: [dp])
        let data = json.data(using: .utf8)!
        let array = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]

        XCTAssertEqual(array.count, 1)
        let entry = array[0]
        XCTAssertEqual(entry.count, 5,
                       "usageDataJSON should have 5 keys: timestamp, five_hour_percent, seven_day_percent, five_hour_resets_at, seven_day_resets_at")
    }

    func testTokenDataJSON_smallCostIsValidJSON() throws {
        // 1 input token for Haiku: $0.80 / 1M = $0.0000008
        let record = TokenRecord(
            timestamp: iso.date(from: "2026-02-22T10:00:00.000Z")!,
            requestId: "req_tiny", model: "claude-haiku-4-5", speed: "standard",
            inputTokens: 1, outputTokens: 0,
            cacheReadTokens: 0, cacheCreationTokens: 0, webSearchRequests: 0
        )
        let json = AnalysisExporter.tokenDataJSON(from: [record])
        let data = json.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        XCTAssertNotNil(parsed, "Very small cost should still produce valid JSON")
        if let array = parsed {
            let cost = array[0]["costUSD"] as? Double ?? -1
            XCTAssertTrue(cost > 0 && cost < 0.001, "Cost should be positive but tiny")
        }
    }
}
