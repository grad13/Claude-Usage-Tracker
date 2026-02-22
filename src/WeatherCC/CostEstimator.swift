// meta: created=2026-02-21 updated=2026-02-21 checked=never
import Foundation

struct CostSummary {
    let totalCost: Double
    let tokenBreakdown: TokenBreakdown
    let recordCount: Int
    let oldestRecord: Date?
    let newestRecord: Date?
}

struct TokenBreakdown {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
}

enum CostEstimator {

    // MARK: - Model Pricing (USD per 1M tokens, Feb 2026)

    struct ModelPricing {
        let input: Double
        let output: Double
        let cacheWrite: Double
        let cacheRead: Double
    }

    static let opus = ModelPricing(input: 15.0, output: 75.0, cacheWrite: 18.75, cacheRead: 1.50)
    static let sonnet = ModelPricing(input: 3.0, output: 15.0, cacheWrite: 3.75, cacheRead: 0.30)
    static let haiku = ModelPricing(input: 0.80, output: 4.0, cacheWrite: 1.0, cacheRead: 0.08)

    // MARK: - Public

    static func estimate(records: [TokenRecord], windowHours: Double, now: Date = Date()) -> CostSummary {
        let cutoff = now.addingTimeInterval(-windowHours * 3600)
        let filtered = records.filter { $0.timestamp >= cutoff }
        return summarize(filtered)
    }

    static func estimateAll(records: [TokenRecord]) -> CostSummary {
        summarize(records)
    }

    // MARK: - Cost Calculation

    static func cost(for record: TokenRecord) -> Double {
        let pricing = pricingForModel(record.model)
        let perMillion = 1_000_000.0

        return Double(record.inputTokens) / perMillion * pricing.input
             + Double(record.outputTokens) / perMillion * pricing.output
             + Double(record.cacheCreationTokens) / perMillion * pricing.cacheWrite
             + Double(record.cacheReadTokens) / perMillion * pricing.cacheRead
    }

    // MARK: - Private

    static func pricingForModel(_ model: String) -> ModelPricing {
        if model.hasPrefix("claude-opus") { return opus }
        if model.hasPrefix("claude-haiku") { return haiku }
        return sonnet // default
    }

    private static func summarize(_ records: [TokenRecord]) -> CostSummary {
        var totalCost = 0.0
        var inputTokens = 0
        var outputTokens = 0
        var cacheReadTokens = 0
        var cacheCreationTokens = 0
        var oldest: Date?
        var newest: Date?

        for record in records {
            totalCost += cost(for: record)
            inputTokens += record.inputTokens
            outputTokens += record.outputTokens
            cacheReadTokens += record.cacheReadTokens
            cacheCreationTokens += record.cacheCreationTokens

            if oldest == nil || record.timestamp < oldest! {
                oldest = record.timestamp
            }
            if newest == nil || record.timestamp > newest! {
                newest = record.timestamp
            }
        }

        return CostSummary(
            totalCost: totalCost,
            tokenBreakdown: TokenBreakdown(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheReadTokens: cacheReadTokens,
                cacheCreationTokens: cacheCreationTokens
            ),
            recordCount: records.count,
            oldestRecord: oldest,
            newestRecord: newest
        )
    }
}
