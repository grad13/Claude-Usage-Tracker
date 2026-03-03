import XCTest
@testable import ClaudeUsageTracker

final class CostEstimatorTests: XCTestCase {

    // MARK: - Helpers

    private func makeRecord(
        model: String = "claude-sonnet-4-6",
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheReadTokens: Int = 0,
        cacheCreationTokens: Int = 0,
        timestamp: Date = Date()
    ) -> TokenRecord {
        TokenRecord(
            timestamp: timestamp,
            requestId: UUID().uuidString,
            model: model,
            speed: "standard",
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheCreationTokens: cacheCreationTokens,
            webSearchRequests: 0
        )
    }

    // MARK: - Per-Record Cost

    func testCostOpus() {
        // Opus: input=$15/1M, output=$75/1M
        let record = makeRecord(
            model: "claude-opus-4-6",
            inputTokens: 1_000_000,
            outputTokens: 1_000_000
        )
        let cost = CostEstimator.cost(for: record)
        XCTAssertEqual(cost, 15.0 + 75.0, accuracy: 0.001, "Opus: 1M input + 1M output = $90")
    }

    func testCostSonnet() {
        // Sonnet: input=$3/1M, output=$15/1M
        let record = makeRecord(
            model: "claude-sonnet-4-6",
            inputTokens: 1_000_000,
            outputTokens: 1_000_000
        )
        let cost = CostEstimator.cost(for: record)
        XCTAssertEqual(cost, 3.0 + 15.0, accuracy: 0.001, "Sonnet: 1M input + 1M output = $18")
    }

    func testCostHaiku() {
        // Haiku: input=$0.80/1M, output=$4/1M
        let record = makeRecord(
            model: "claude-haiku-4-5",
            inputTokens: 1_000_000,
            outputTokens: 1_000_000
        )
        let cost = CostEstimator.cost(for: record)
        XCTAssertEqual(cost, 0.80 + 4.0, accuracy: 0.001, "Haiku: 1M input + 1M output = $4.80")
    }

    func testCacheReadDiscount() {
        // Sonnet: cache_read=$0.30/1M (=0.1x of input $3/1M)
        let record = makeRecord(
            model: "claude-sonnet-4-6",
            cacheReadTokens: 1_000_000
        )
        let cost = CostEstimator.cost(for: record)
        XCTAssertEqual(cost, 0.30, accuracy: 0.001, "Cache read should be 0.1x input price")
    }

    func testCacheWriteCost() {
        // Sonnet: cache_write=$3.75/1M (=1.25x of input $3/1M)
        let record = makeRecord(
            model: "claude-sonnet-4-6",
            cacheCreationTokens: 1_000_000
        )
        let cost = CostEstimator.cost(for: record)
        XCTAssertEqual(cost, 3.75, accuracy: 0.001, "Cache write should be 1.25x input price")
    }

    func testCombinedCost() {
        // All token types for Sonnet
        let record = makeRecord(
            model: "claude-sonnet-4-6",
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            cacheReadTokens: 1_000_000,
            cacheCreationTokens: 1_000_000
        )
        let cost = CostEstimator.cost(for: record)
        let expected = 3.0 + 15.0 + 0.30 + 3.75  // input + output + cacheRead + cacheWrite
        XCTAssertEqual(cost, expected, accuracy: 0.001, "Combined cost should sum all token types")
    }

    // MARK: - Window Filter

    func testWindowFilter() {
        let now = Date()
        let withinWindow = makeRecord(
            inputTokens: 1000,
            outputTokens: 500,
            timestamp: now.addingTimeInterval(-3600)  // 1 hour ago
        )
        let outsideWindow = makeRecord(
            inputTokens: 1000,
            outputTokens: 500,
            timestamp: now.addingTimeInterval(-6 * 3600)  // 6 hours ago
        )

        let summary = CostEstimator.estimate(records: [withinWindow, outsideWindow], windowHours: 5.0, now: now)
        XCTAssertEqual(summary.recordCount, 1, "Only records within 5-hour window should be included")
    }

    // MARK: - Empty Records

    func testEmptyRecords() {
        let summary = CostEstimator.estimateAll(records: [])
        XCTAssertEqual(summary.totalCost, 0.0, accuracy: 0.001)
        XCTAssertEqual(summary.recordCount, 0)
        XCTAssertNil(summary.oldestRecord)
        XCTAssertNil(summary.newestRecord)
    }

    // MARK: - Token Breakdown

    func testTokenBreakdown() {
        let r1 = makeRecord(inputTokens: 100, outputTokens: 200, cacheReadTokens: 300, cacheCreationTokens: 400)
        let r2 = makeRecord(inputTokens: 50, outputTokens: 60, cacheReadTokens: 70, cacheCreationTokens: 80)

        let summary = CostEstimator.estimateAll(records: [r1, r2])
        XCTAssertEqual(summary.tokenBreakdown.inputTokens, 150)
        XCTAssertEqual(summary.tokenBreakdown.outputTokens, 260)
        XCTAssertEqual(summary.tokenBreakdown.cacheReadTokens, 370)
        XCTAssertEqual(summary.tokenBreakdown.cacheCreationTokens, 480)
    }

    // MARK: - Model Prefix Matching

    func testUnknownModelDefaultsToSonnet() {
        let record = makeRecord(model: "some-unknown-model", inputTokens: 1_000_000)
        let cost = CostEstimator.cost(for: record)
        XCTAssertEqual(cost, 3.0, accuracy: 0.001, "Unknown model should use Sonnet pricing")
    }

    // MARK: - Date Range

    func testOldestNewestRecord() {
        let now = Date()
        let r1 = makeRecord(timestamp: now.addingTimeInterval(-7200))
        let r2 = makeRecord(timestamp: now.addingTimeInterval(-3600))
        let r3 = makeRecord(timestamp: now)

        let summary = CostEstimator.estimateAll(records: [r2, r1, r3])
        XCTAssertEqual(summary.oldestRecord, r1.timestamp)
        XCTAssertEqual(summary.newestRecord, r3.timestamp)
    }

    // MARK: - Window Boundary

    func testWindowBoundary_exactCutoff() {
        let now = Date()
        // Record exactly at cutoff (5 hours ago). >= means it should be included.
        let atCutoff = makeRecord(inputTokens: 1000, timestamp: now.addingTimeInterval(-5 * 3600))
        let summary = CostEstimator.estimate(records: [atCutoff], windowHours: 5.0, now: now)
        XCTAssertEqual(summary.recordCount, 1, "Record exactly at cutoff should be included (>=)")
    }

    // MARK: - Model Prefix Edge Cases

    func testModelPrefix_opusWithoutVersion() {
        let record = makeRecord(model: "claude-opus", inputTokens: 1_000_000)
        let cost = CostEstimator.cost(for: record)
        XCTAssertEqual(cost, 15.0, accuracy: 0.001, "claude-opus (no version) should use Opus pricing")
    }

    // MARK: - Estimate Empty

    func testEstimateWithWindow_emptyRecords() {
        let summary = CostEstimator.estimate(records: [], windowHours: 5.0)
        XCTAssertEqual(summary.totalCost, 0.0, accuracy: 0.001)
        XCTAssertEqual(summary.recordCount, 0)
        XCTAssertNil(summary.oldestRecord)
        XCTAssertNil(summary.newestRecord)
    }

    // MARK: - Single Record Date Range

    func testSingleRecord_oldestEqualsNewest() {
        let now = Date()
        let record = makeRecord(timestamp: now)
        let summary = CostEstimator.estimateAll(records: [record])
        XCTAssertEqual(summary.oldestRecord, summary.newestRecord,
                       "Single record: oldest should equal newest")
    }

    // MARK: - Zero Tokens

    func testAllZeroTokens() {
        let record = makeRecord()  // all tokens default to 0
        let cost = CostEstimator.cost(for: record)
        XCTAssertEqual(cost, 0.0, accuracy: 0.001, "All zero tokens should cost $0")
    }

    // MARK: - Mixed Model Summary

    func testMixedModelSummary() {
        let opusRecord = makeRecord(model: "claude-opus-4-6", inputTokens: 1_000_000)
        let haikuRecord = makeRecord(model: "claude-haiku-4-5", inputTokens: 1_000_000)

        let summary = CostEstimator.estimateAll(records: [opusRecord, haikuRecord])
        // Opus input: $15, Haiku input: $0.80
        XCTAssertEqual(summary.totalCost, 15.0 + 0.80, accuracy: 0.001,
                       "Mixed-model summary should sum per-record costs correctly")
        XCTAssertEqual(summary.recordCount, 2)
    }

    // MARK: - Just Outside Window

    func testWindowBoundary_justOutside() {
        let now = Date()
        // 1 second before cutoff (just outside)
        let record = makeRecord(inputTokens: 1000, timestamp: now.addingTimeInterval(-5 * 3600 - 1))
        let summary = CostEstimator.estimate(records: [record], windowHours: 5.0, now: now)
        XCTAssertEqual(summary.recordCount, 0, "Record 1 second before cutoff should be excluded")
    }

    // MARK: - Large Token Count

    func testLargeTokenCount() {
        // 100 billion tokens — verify no overflow or unexpected behavior
        let record = makeRecord(
            model: "claude-sonnet-4-6",
            inputTokens: 100_000_000_000,
            outputTokens: 100_000_000_000
        )
        let cost = CostEstimator.cost(for: record)
        // input: 100B / 1M * $3 = $300,000; output: 100B / 1M * $15 = $1,500,000
        XCTAssertEqual(cost, 1_800_000.0, accuracy: 1.0,
                       "Very large token count should compute without overflow")
    }

    // MARK: - Haiku Model Prefix Without Version

    func testModelPrefix_haikuWithoutVersion() {
        let record = makeRecord(model: "claude-haiku", inputTokens: 1_000_000)
        let cost = CostEstimator.cost(for: record)
        XCTAssertEqual(cost, 0.80, accuracy: 0.001, "claude-haiku (no version) should use Haiku pricing")
    }

    // MARK: - pricingForModel edge cases

    func testPricingForModel_claudeUnknownSubtype() {
        // "claude-random" starts with "claude-" but doesn't match opus/haiku
        // hasPrefix("claude-opus") → false, hasPrefix("claude-haiku") → false → falls through to sonnet
        let record = makeRecord(model: "claude-random-model", inputTokens: 1_000_000)
        let cost = CostEstimator.cost(for: record)
        XCTAssertEqual(cost, 3.0, accuracy: 0.001,
                       "Unknown claude- prefix should default to Sonnet pricing")
    }

    func testPricingForModel_emptyString() {
        let record = makeRecord(model: "", inputTokens: 1_000_000)
        let cost = CostEstimator.cost(for: record)
        XCTAssertEqual(cost, 3.0, accuracy: 0.001,
                       "Empty model string should default to Sonnet pricing")
    }

    // MARK: - estimateAll verifies oldest/newest with more records

    func testEstimateAll_oldestNewestWithThreeRecords() {
        let now = Date()
        let records = [
            makeRecord(timestamp: now.addingTimeInterval(-7200)),
            makeRecord(timestamp: now.addingTimeInterval(-3600)),
            makeRecord(timestamp: now),
        ]
        let summary = CostEstimator.estimateAll(records: records)
        XCTAssertEqual(summary.oldestRecord!.timeIntervalSince1970,
                       records[0].timestamp.timeIntervalSince1970, accuracy: 0.01)
        XCTAssertEqual(summary.newestRecord!.timeIntervalSince1970,
                       records[2].timestamp.timeIntervalSince1970, accuracy: 0.01)
    }
}
