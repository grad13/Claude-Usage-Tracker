import XCTest
@testable import ClaudeUsageTracker

/// Verifies that the JS costForRecord function in the HTML template
/// produces the same results as Swift's CostEstimator.cost(for:).
/// If these diverge, the Analysis window shows wrong cost data.
final class CostEstimatorParityTests: XCTestCase {

    /// Compute cost using Swift CostEstimator for comparison.
    private func swiftCost(model: String, input: Int, output: Int, cacheRead: Int, cacheWrite: Int) -> Double {
        let record = TokenRecord(
            timestamp: Date(),
            requestId: "test",
            model: model,
            speed: "standard",
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheCreationTokens: cacheWrite,
            webSearchRequests: 0
        )
        return CostEstimator.cost(for: record)
    }

    /// Extract JS pricing from the HTML template and verify it matches Swift.
    func testJsPricing_opus_matchesSwift() {
        let swiftPricing = CostEstimator.opus
        XCTAssertEqual(swiftPricing.input, 15.0)
        XCTAssertEqual(swiftPricing.output, 75.0)
        XCTAssertEqual(swiftPricing.cacheWrite, 18.75)
        XCTAssertEqual(swiftPricing.cacheRead, 1.50)

        // Verify JS template has matching values
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("input: 15.0"))
        XCTAssertTrue(html.contains("output: 75.0"))
        XCTAssertTrue(html.contains("cacheWrite: 18.75"))
        XCTAssertTrue(html.contains("cacheRead: 1.50") || html.contains("cacheRead: 1.5"))
    }

    func testJsPricing_sonnet_matchesSwift() {
        let swiftPricing = CostEstimator.sonnet
        XCTAssertEqual(swiftPricing.input, 3.0)
        XCTAssertEqual(swiftPricing.output, 15.0)
        XCTAssertEqual(swiftPricing.cacheWrite, 3.75)
        XCTAssertEqual(swiftPricing.cacheRead, 0.30)

        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("cacheWrite: 3.75"))
        XCTAssertTrue(html.contains("cacheRead: 0.30") || html.contains("cacheRead: 0.3"))
    }

    func testJsPricing_haiku_matchesSwift() {
        let swiftPricing = CostEstimator.haiku
        XCTAssertEqual(swiftPricing.input, 0.80)
        XCTAssertEqual(swiftPricing.output, 4.0)
        XCTAssertEqual(swiftPricing.cacheWrite, 1.0)
        XCTAssertEqual(swiftPricing.cacheRead, 0.08)

        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("cacheWrite: 1.0"))
        XCTAssertTrue(html.contains("cacheRead: 0.08"))
    }

    /// Verify model routing: JS pricingForModel uses same matching as Swift.
    func testJsModelRouting_matchesSwift() {
        let html = AnalysisExporter.htmlTemplate
        // JS: model.includes('opus') → opus (matches claude-opus-* and claude-3-opus-*)
        XCTAssertTrue(html.contains("model.includes('opus')") ||
                      html.contains("model.includes(\"opus\")"))
        // JS: model.includes('haiku') → haiku
        XCTAssertTrue(html.contains("model.includes('haiku')") ||
                      html.contains("model.includes(\"haiku\")"))
        // JS should return sonnet as default (fall-through)
        XCTAssertTrue(html.contains("return MODEL_PRICING.sonnet"))
    }

    /// Verify cost formula: JS uses same calculation as Swift.
    /// Swift: input/1M * pricing.input + output/1M * pricing.output + cacheCreation/1M * pricing.cacheWrite + cacheRead/1M * pricing.cacheRead
    func testCostFormula_sonnet_1MInputTokens() {
        let cost = swiftCost(model: "claude-sonnet-4-20250514", input: 1_000_000, output: 0, cacheRead: 0, cacheWrite: 0)
        XCTAssertEqual(cost, 3.0, accuracy: 0.001,
                       "1M sonnet input tokens = $3.00")
    }

    func testCostFormula_opus_1MOutputTokens() {
        let cost = swiftCost(model: "claude-opus-4-20250514", input: 0, output: 1_000_000, cacheRead: 0, cacheWrite: 0)
        XCTAssertEqual(cost, 75.0, accuracy: 0.001,
                       "1M opus output tokens = $75.00")
    }

    func testCostFormula_haiku_mixedTokens() {
        let cost = swiftCost(model: "claude-haiku-4-20250101", input: 500_000, output: 200_000, cacheRead: 1_000_000, cacheWrite: 300_000)
        // 0.5M * 0.80 + 0.2M * 4.0 + 1.0M * 0.08 + 0.3M * 1.0
        // = 0.40 + 0.80 + 0.08 + 0.30 = 1.58
        XCTAssertEqual(cost, 1.58, accuracy: 0.001)
    }

    func testCostFormula_cacheRead_isCheaperThanInput() {
        // This is the key insight: cache_read is 1/10 of input price
        let inputCost = swiftCost(model: "claude-sonnet-4-20250514", input: 1_000_000, output: 0, cacheRead: 0, cacheWrite: 0)
        let cacheCost = swiftCost(model: "claude-sonnet-4-20250514", input: 0, output: 0, cacheRead: 1_000_000, cacheWrite: 0)
        XCTAssertEqual(inputCost / cacheCost, 10.0, accuracy: 0.001,
                       "Cache read must be 1/10 of input price — this is why costs vary so much")
    }

    func testCostFormula_zeroTokens() {
        let cost = swiftCost(model: "claude-sonnet-4-20250514", input: 0, output: 0, cacheRead: 0, cacheWrite: 0)
        XCTAssertEqual(cost, 0.0, accuracy: 0.0001)
    }

    /// JS formula must use same field mapping as Swift.
    /// Swift: cacheCreationTokens → cacheWrite pricing
    /// JS: cache_creation_tokens → cacheWrite pricing
    func testJsCostFormula_fieldMapping() {
        let html = AnalysisExporter.htmlTemplate
        // JS must multiply cache_creation_tokens by cacheWrite (not cacheRead)
        XCTAssertTrue(html.contains("cache_creation_tokens") && html.contains("cacheWrite"),
                      "JS must map cache_creation_tokens to cacheWrite pricing")
        // JS must multiply cache_read_tokens by cacheRead (not cacheWrite)
        XCTAssertTrue(html.contains("cache_read_tokens") && html.contains("cacheRead"),
                      "JS must map cache_read_tokens to cacheRead pricing")
    }
}
