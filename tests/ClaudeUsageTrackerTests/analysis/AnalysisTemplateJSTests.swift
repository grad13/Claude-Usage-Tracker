import XCTest
import WebKit
@testable import ClaudeUsageTracker

// MARK: - Real Template JS Tests

/// Tests JS functions by extracting and executing them from the REAL AnalysisExporter.htmlTemplate.
/// This catches bugs that the copied-JS tests (AnalysisJSLogicTests) cannot detect.
/// If someone changes a function in the template, these tests will run the changed code.
final class AnalysisTemplateJSTests: AnalysisJSTestCase {

    // =========================================================
    // MARK: - Template extraction verification
    // =========================================================

    func testTemplateExtraction_allFunctionsAvailable() {
        let result = evalJS("""
            return {
                pricingForModel: typeof pricingForModel === 'function',
                costForRecord: typeof costForRecord === 'function',
                computeKDE: typeof computeKDE === 'function',
                computeDeltas: typeof computeDeltas === 'function',
                buildHeatmap: typeof buildHeatmap === 'function',
                buildScatterChart: typeof buildScatterChart === 'function',
                main: typeof main === 'function',
                renderMain: typeof renderMain === 'function',
                destroyAllCharts: typeof destroyAllCharts === 'function',
                formatDateShort: typeof formatDateShort === 'function',
                formatDateFull: typeof formatDateFull === 'function',
                initNavigation: typeof initNavigation === 'function',
                buildWeeklySlots: typeof buildWeeklySlots === 'function',
                buildDailySlots: typeof buildDailySlots === 'function',
                navigateTo: typeof navigateTo === 'function',
                renderUsageTab: typeof renderUsageTab === 'function',
                renderCostTab: typeof renderCostTab === 'function',
                renderCumulativeTab: typeof renderCumulativeTab === 'function',
                renderScatterTab: typeof renderScatterTab === 'function',
                renderKdeTab: typeof renderKdeTab === 'function',
                renderHeatmapTab: typeof renderHeatmapTab === 'function',
                renderTab: typeof renderTab === 'function',
                initTabs: typeof initTabs === 'function',
                timeSlots: Array.isArray(timeSlots),
                MODEL_PRICING: typeof MODEL_PRICING === 'object',
            };
        """) as? [String: Any]
        XCTAssertNotNil(result, "evalJS must return a result — template extraction failed")
        for (key, value) in result ?? [:] {
            XCTAssertEqual(value as? Bool, true,
                           "\(key) must exist in extracted template JS")
        }
    }

    func testTemplateExtraction_globalVariablesDefined() {
        let result = evalJS("""
            return {
                hasCharts: typeof _charts === 'object',
                hasRendered: typeof _rendered === 'object',
            };
        """) as? [String: Any]
        XCTAssertEqual(result?["hasCharts"] as? Bool, true)
        XCTAssertEqual(result?["hasRendered"] as? Bool, true)
    }

    // =========================================================
    // MARK: - pricingForModel (real template)
    // =========================================================

    func testRealTemplate_pricingForModel_opus() {
        let result = evalJS("""
            const p = pricingForModel('claude-opus-4-20250514');
            return {input: p.input, output: p.output, cacheWrite: p.cacheWrite, cacheRead: p.cacheRead};
        """) as? [String: Any]
        XCTAssertEqual(result?["input"] as? Double, 15.0)
        XCTAssertEqual(result?["output"] as? Double, 75.0)
        XCTAssertEqual(result?["cacheWrite"] as? Double, 18.75)
        XCTAssertEqual(result?["cacheRead"] as? Double, 1.50)
    }

    func testRealTemplate_pricingForModel_sonnet() {
        let result = evalJS("""
            const p = pricingForModel('claude-sonnet-4-20250514');
            return {input: p.input, output: p.output, cacheWrite: p.cacheWrite, cacheRead: p.cacheRead};
        """) as? [String: Any]
        XCTAssertEqual(result?["input"] as? Double, 3.0)
        XCTAssertEqual(result?["output"] as? Double, 15.0)
        XCTAssertEqual(result?["cacheWrite"] as? Double, 3.75)
        XCTAssertEqual(result?["cacheRead"] as? Double, 0.30)
    }

    func testRealTemplate_pricingForModel_haiku() {
        let result = evalJS("""
            const p = pricingForModel('claude-haiku-4-20250101');
            return {input: p.input, output: p.output, cacheWrite: p.cacheWrite, cacheRead: p.cacheRead};
        """) as? [String: Any]
        XCTAssertEqual(result?["input"] as? Double, 0.80)
        XCTAssertEqual(result?["output"] as? Double, 4.0)
        XCTAssertEqual(result?["cacheWrite"] as? Double, 1.0)
        XCTAssertEqual(result?["cacheRead"] as? Double, 0.08)
    }

    func testRealTemplate_pricingForModel_unknownModel_defaultsToSonnet() {
        let result = evalJS("""
            const p = pricingForModel('some-unknown-model');
            return {input: p.input, output: p.output};
        """) as? [String: Any]
        XCTAssertEqual(result?["input"] as? Double, 3.0, "Unknown model defaults to sonnet")
        XCTAssertEqual(result?["output"] as? Double, 15.0)
    }

    // =========================================================
    // MARK: - costForRecord: JS vs Swift parity (real template)
    // =========================================================

    func testRealTemplate_costForRecord_matchesSwiftCostEstimator() {
        let testCases: [(String, Int, Int, Int, Int)] = [
            ("claude-sonnet-4-20250514", 150_000, 50_000, 800_000, 200_000),
            ("claude-opus-4-20250514", 1_000_000, 300_000, 500_000, 100_000),
            ("claude-haiku-4-20250101", 2_000_000, 100_000, 3_000_000, 50_000),
            ("claude-sonnet-4-20250514", 0, 0, 0, 0),
            ("claude-opus-4-20250514", 1, 1, 1, 1),
        ]
        for (model, inp, out, cacheR, cacheW) in testCases {
            let swiftCost = CostEstimator.cost(for: TokenRecord(
                timestamp: Date(), requestId: "t", model: model, speed: "standard",
                inputTokens: inp, outputTokens: out,
                cacheReadTokens: cacheR, cacheCreationTokens: cacheW,
                webSearchRequests: 0
            ))
            let jsCost = evalJS("""
                return costForRecord({
                    model: '\(model)',
                    input_tokens: \(inp), output_tokens: \(out),
                    cache_read_tokens: \(cacheR), cache_creation_tokens: \(cacheW)
                });
            """) as! Double
            XCTAssertEqual(jsCost, swiftCost, accuracy: 0.000001,
                           "JS/Swift cost mismatch for \(model) inp=\(inp) out=\(out)")
        }
    }

    func testRealTemplate_costForRecord_cacheReadIs10xCheaperThanInput() {
        let inputCost = evalJS("""
            return costForRecord({model: 'claude-sonnet-4-20250514',
                input_tokens: 1000000, output_tokens: 0, cache_read_tokens: 0, cache_creation_tokens: 0});
        """) as! Double
        let cacheCost = evalJS("""
            return costForRecord({model: 'claude-sonnet-4-20250514',
                input_tokens: 0, output_tokens: 0, cache_read_tokens: 1000000, cache_creation_tokens: 0});
        """) as! Double
        XCTAssertEqual(inputCost / cacheCost, 10.0, accuracy: 0.001)
    }

    // =========================================================
    // MARK: - computeDeltas (real template)
    // =========================================================

    func testRealTemplate_computeDeltas_basicDelta() {
        let result = evalJS("""
            const deltas = computeDeltas(
                [{timestamp: 1771927200, hourly_percent: 10},
                 {timestamp: 1771927500, hourly_percent: 15}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50}]
            );
            return {count: deltas.length, x: deltas[0].x, y: deltas[0].y};
        """) as? [String: Any]
        XCTAssertEqual(result?["count"] as? Int, 1)
        XCTAssertEqual(result!["x"] as! Double, 0.50, accuracy: 0.001)
        XCTAssertEqual(result!["y"] as! Double, 5.0, accuracy: 0.001)
    }

    func testRealTemplate_computeDeltas_filtersLowCost() {
        let result = evalJS("""
            return computeDeltas(
                [{timestamp: 1771927200, hourly_percent: 10},
                 {timestamp: 1771927500, hourly_percent: 20}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.0005}]
            ).length;
        """) as? Int
        XCTAssertEqual(result, 0, "Cost <= 0.001 must be filtered out")
    }

    func testRealTemplate_computeDeltas_sumsMultipleTokens() {
        let result = evalJS("""
            const deltas = computeDeltas(
                [{timestamp: 1771927200, hourly_percent: 10},
                 {timestamp: 1771927800, hourly_percent: 30}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50},
                 {timestamp: '2026-02-24T10:05:00Z', costUSD: 1.00},
                 {timestamp: '2026-02-24T10:08:00Z', costUSD: 0.25}]
            );
            return {x: deltas[0].x, y: deltas[0].y};
        """) as? [String: Any]
        XCTAssertEqual(result!["x"] as! Double, 1.75, accuracy: 0.001, "Sum of 0.50+1.00+0.25")
        XCTAssertEqual(result!["y"] as! Double, 20.0, accuracy: 0.001)
    }

    func testRealTemplate_computeDeltas_nullPercentSkipped() {
        let result = evalJS("""
            const deltas = computeDeltas(
                [{timestamp: 1771927200, hourly_percent: null},
                 {timestamp: 1771927500, hourly_percent: 10}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 1.0}]
            );
            return deltas.length;
        """) as? Int
        XCTAssertEqual(result, 0, "Null prev percent → interval skipped entirely")
    }

    func testRealTemplate_computeDeltas_negativeDelta() {
        let result = evalJS("""
            const deltas = computeDeltas(
                [{timestamp: 1771927200, hourly_percent: 50},
                 {timestamp: 1771927500, hourly_percent: 20}],
                [{timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50}]
            );
            return deltas[0].y;
        """) as? Double
        XCTAssertEqual(result!, -30.0, accuracy: 0.001, "Usage decrease preserved as negative delta")
    }

    func testRealTemplate_computeDeltas_tokenBoundary_t0Inclusive_t1Exclusive() {
        let result = evalJS("""
            const deltas = computeDeltas(
                [{timestamp: 1771927200, hourly_percent: 0},
                 {timestamp: 1771927500, hourly_percent: 10}],
                [{timestamp: '2026-02-24T10:00:00.000Z', costUSD: 0.50},
                 {timestamp: '2026-02-24T10:05:00.000Z', costUSD: 0.75}]
            );
            return {count: deltas.length, cost: deltas[0]?.x};
        """) as? [String: Any]
        XCTAssertEqual(result?["count"] as? Int, 1)
        XCTAssertEqual(result!["cost"] as! Double, 0.50, accuracy: 0.001,
                       "Token at t0 included (>=), token at t1 excluded (<)")
    }

    // =========================================================
    // MARK: - computeKDE (real template)
    // =========================================================

    func testRealTemplate_computeKDE_singleValue_returnsEmpty() {
        let result = evalJS("return computeKDE([5.0]).xs.length;") as? Int
        XCTAssertEqual(result, 0, "n < 2 → empty")
    }

    func testRealTemplate_computeKDE_twoValues_returnsNonEmpty() {
        let result = evalJS("""
            const kde = computeKDE([1.0, 2.0]);
            return {xsLen: kde.xs.length, ysLen: kde.ys.length};
        """) as? [String: Any]
        XCTAssertGreaterThan(result?["xsLen"] as! Int, 0)
        XCTAssertEqual(result?["xsLen"] as? Int, result?["ysLen"] as? Int)
    }

    func testRealTemplate_computeKDE_densityIntegral_isApproximatelyOne() {
        let result = evalJS("""
            const kde = computeKDE([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
            let integral = 0;
            for (let i = 1; i < kde.xs.length; i++) {
                const dx = kde.xs[i] - kde.xs[i-1];
                integral += (kde.ys[i] + kde.ys[i-1]) / 2 * dx;
            }
            return integral;
        """) as? Double
        XCTAssertEqual(result!, 1.0, accuracy: 0.15,
                       "KDE integral should approximate 1.0 (proper probability density)")
    }

    func testRealTemplate_computeKDE_identicalValues_doesNotCrash() {
        let result = evalJS("""
            const kde = computeKDE([5, 5, 5, 5, 5]);
            return {xsLen: kde.xs.length, allFinite: kde.ys.every(y => isFinite(y))};
        """) as? [String: Any]
        XCTAssertGreaterThan(result?["xsLen"] as! Int, 0)
        XCTAssertTrue(result?["allFinite"] as! Bool, "No NaN/Infinity for identical values")
    }

    func testRealTemplate_computeKDE_bimodal_hasTwoPeaks() {
        let result = evalJS("""
            const kde = computeKDE([0,0,0,0,0, 100,100,100,100,100]);
            let peaks = 0;
            for (let i = 1; i < kde.xs.length - 1; i++) {
                if (kde.ys[i] > kde.ys[i-1] && kde.ys[i] > kde.ys[i+1]) peaks++;
            }
            return peaks;
        """) as? Int
        XCTAssertEqual(result, 2, "Bimodal data should produce exactly 2 peaks")
    }

    // =========================================================
    // MARK: - timeSlots (real template)
    // =========================================================

    func testRealTemplate_timeSlots_everyHourMatchesExactlyOneSlot() {
        let result = evalJS("""
            const counts = [];
            for (let h = 0; h < 24; h++) {
                let matched = 0;
                for (const slot of timeSlots) {
                    if (slot.filter({hour: h})) matched++;
                }
                counts.push(matched);
            }
            return counts.every(c => c === 1);
        """) as? Bool
        XCTAssertTrue(result!, "Every hour 0-23 must match exactly one timeSlot")
    }

    func testRealTemplate_timeSlots_nightIsBefore6() {
        let result = evalJS("""
            return [0,5,6,12,18,23].filter(h => timeSlots[0].filter({hour: h}));
        """) as? [Int]
        XCTAssertEqual(result, [0, 5])
    }

    func testRealTemplate_timeSlots_morningIs6to11() {
        let result = evalJS("""
            return [0,5,6,11,12,18].filter(h => timeSlots[1].filter({hour: h}));
        """) as? [Int]
        XCTAssertEqual(result, [6, 11])
    }

    // =========================================================
    // MARK: - End-to-end pipeline (real template)
    // =========================================================

    func testRealTemplate_endToEnd_rawTokensToDelta() {
        let result = evalJS("""
            const rawTokens = [
                {timestamp: '2026-02-24T10:02:00Z', model: 'claude-sonnet-4-20250514',
                 input_tokens: 100000, output_tokens: 50000, cache_read_tokens: 0, cache_creation_tokens: 0},
            ];
            const tokenData = rawTokens.map(r => ({timestamp: r.timestamp, costUSD: costForRecord(r)}));
            const usageData = [
                {timestamp: 1771927200, hourly_percent: 10},
                {timestamp: 1771927500, hourly_percent: 15},
            ];
            const deltas = computeDeltas(usageData, tokenData);
            return {
                tokenCost: tokenData[0].costUSD,
                deltaCount: deltas.length,
                deltaX: deltas[0]?.x,
                deltaY: deltas[0]?.y,
            };
        """) as? [String: Any]
        // cost: 0.1M * 3.0 + 0.05M * 15.0 = 0.30 + 0.75 = 1.05
        XCTAssertEqual(result!["tokenCost"] as! Double, 1.05, accuracy: 0.001)
        XCTAssertEqual(result?["deltaCount"] as? Int, 1)
        XCTAssertEqual(result!["deltaX"] as! Double, 1.05, accuracy: 0.001)
        XCTAssertEqual(result!["deltaY"] as! Double, 5.0, accuracy: 0.001)
    }

    func testRealTemplate_endToEnd_mixedModels() {
        let result = evalJS("""
            const rawTokens = [
                {timestamp: '2026-02-24T10:01:00Z', model: 'claude-opus-4-20250514',
                 input_tokens: 10000, output_tokens: 5000, cache_read_tokens: 0, cache_creation_tokens: 0},
                {timestamp: '2026-02-24T10:06:00Z', model: 'claude-haiku-4-20250101',
                 input_tokens: 50000, output_tokens: 10000, cache_read_tokens: 100000, cache_creation_tokens: 0},
            ];
            const tokenData = rawTokens.map(r => ({timestamp: r.timestamp, costUSD: costForRecord(r)}));
            const usageData = [
                {timestamp: 1771927200, hourly_percent: 0},
                {timestamp: 1771927500, hourly_percent: 5},
                {timestamp: 1771927800, hourly_percent: 6},
            ];
            const deltas = computeDeltas(usageData, tokenData);
            return {count: deltas.length, d0cost: deltas[0]?.x, d0pct: deltas[0]?.y,
                    d1cost: deltas[1]?.x, d1pct: deltas[1]?.y};
        """) as? [String: Any]
        XCTAssertEqual(result?["count"] as? Int, 2)
        // opus: 10k*15/1M + 5k*75/1M = 0.15 + 0.375 = 0.525
        XCTAssertEqual(result!["d0cost"] as! Double, 0.525, accuracy: 0.001)
        XCTAssertEqual(result!["d0pct"] as! Double, 5.0, accuracy: 0.001)
        // haiku: 50k*0.80/1M + 10k*4.0/1M + 100k*0.08/1M = 0.04 + 0.04 + 0.008 = 0.088
        XCTAssertEqual(result!["d1cost"] as! Double, 0.088, accuracy: 0.001)
        XCTAssertEqual(result!["d1pct"] as! Double, 1.0, accuracy: 0.001)
    }
}
