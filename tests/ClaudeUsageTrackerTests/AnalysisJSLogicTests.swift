import XCTest
import WebKit
@testable import ClaudeUsageTracker

// MARK: - JS Logic Tests (WKWebView execution)

/// Tests JS functions by EXECUTING them in a real WKWebView.
/// Each test loads the pure JS functions (no Chart.js CDN dependency),
/// calls them with known inputs via callAsyncJavaScript, and verifies outputs.
/// This catches logic bugs that string-matching tests cannot detect.
final class AnalysisJSLogicTests: AnalysisJSTestCase {

    // =========================================================
    // MARK: - pricingForModel
    // =========================================================

    func testPricingForModel_opusFullName() {
        let result = evalJS("""
            const p = pricingForModel('claude-opus-4-20250514');
            return {input: p.input, output: p.output, cacheWrite: p.cacheWrite, cacheRead: p.cacheRead};
        """) as? [String: Any]
        XCTAssertEqual(result?["input"] as? Double, 15.0)
        XCTAssertEqual(result?["output"] as? Double, 75.0)
        XCTAssertEqual(result?["cacheWrite"] as? Double, 18.75)
        XCTAssertEqual(result?["cacheRead"] as? Double, 1.50)
    }

    func testPricingForModel_sonnetFullName() {
        let result = evalJS("""
            const p = pricingForModel('claude-sonnet-4-20250514');
            return {input: p.input, output: p.output, cacheWrite: p.cacheWrite, cacheRead: p.cacheRead};
        """) as? [String: Any]
        XCTAssertEqual(result?["input"] as? Double, 3.0)
        XCTAssertEqual(result?["output"] as? Double, 15.0)
        XCTAssertEqual(result?["cacheWrite"] as? Double, 3.75)
        XCTAssertEqual(result?["cacheRead"] as? Double, 0.30)
    }

    func testPricingForModel_haikuFullName() {
        let result = evalJS("""
            const p = pricingForModel('claude-haiku-4-20250101');
            return {input: p.input, output: p.output, cacheWrite: p.cacheWrite, cacheRead: p.cacheRead};
        """) as? [String: Any]
        XCTAssertEqual(result?["input"] as? Double, 0.80)
        XCTAssertEqual(result?["output"] as? Double, 4.0)
        XCTAssertEqual(result?["cacheWrite"] as? Double, 1.0)
        XCTAssertEqual(result?["cacheRead"] as? Double, 0.08)
    }

    func testPricingForModel_unknownModel_defaultsToSonnet() {
        let result = evalJS("""
            const p = pricingForModel('some-unknown-model-v9');
            return {input: p.input, output: p.output};
        """) as? [String: Any]
        XCTAssertEqual(result?["input"] as? Double, 3.0)
        XCTAssertEqual(result?["output"] as? Double, 15.0)
    }

    func testPricingForModel_opusPrefixOnly() {
        // "claude-opus" without version should still match opus
        let result = evalJS("""
            return pricingForModel('claude-opus').input;
        """) as? Double
        XCTAssertEqual(result, 15.0)
    }

    // =========================================================
    // MARK: - costForRecord
    // =========================================================

    func testCostForRecord_sonnet_1MInput() {
        let result = evalJS("""
            return costForRecord({
                model: 'claude-sonnet-4-20250514',
                input_tokens: 1000000, output_tokens: 0,
                cache_read_tokens: 0, cache_creation_tokens: 0
            });
        """) as? Double
        // 1M * 3.0 / 1M = $3.00
        XCTAssertEqual(result!, 3.0, accuracy: 0.001)
    }

    func testCostForRecord_opus_1MOutput() {
        let result = evalJS("""
            return costForRecord({
                model: 'claude-opus-4-20250514',
                input_tokens: 0, output_tokens: 1000000,
                cache_read_tokens: 0, cache_creation_tokens: 0
            });
        """) as? Double
        // 1M * 75.0 / 1M = $75.00
        XCTAssertEqual(result!, 75.0, accuracy: 0.001)
    }

    func testCostForRecord_haiku_mixedTokens() {
        let result = evalJS("""
            return costForRecord({
                model: 'claude-haiku-4-20250101',
                input_tokens: 500000, output_tokens: 200000,
                cache_read_tokens: 1000000, cache_creation_tokens: 300000
            });
        """) as? Double
        // 0.5M * 0.80 + 0.2M * 4.0 + 1.0M * 0.08 + 0.3M * 1.0
        // = 0.40 + 0.80 + 0.08 + 0.30 = 1.58
        XCTAssertEqual(result!, 1.58, accuracy: 0.001)
    }

    func testCostForRecord_zeroTokens() {
        let result = evalJS("""
            return costForRecord({
                model: 'claude-sonnet-4-20250514',
                input_tokens: 0, output_tokens: 0,
                cache_read_tokens: 0, cache_creation_tokens: 0
            });
        """) as? Double
        XCTAssertEqual(result!, 0.0, accuracy: 0.0001)
    }

    func testCostForRecord_cacheReadIs10xCheaperThanInput() {
        let inputCost = evalJS("""
            return costForRecord({
                model: 'claude-sonnet-4-20250514',
                input_tokens: 1000000, output_tokens: 0,
                cache_read_tokens: 0, cache_creation_tokens: 0
            });
        """) as! Double
        let cacheCost = evalJS("""
            return costForRecord({
                model: 'claude-sonnet-4-20250514',
                input_tokens: 0, output_tokens: 0,
                cache_read_tokens: 1000000, cache_creation_tokens: 0
            });
        """) as! Double
        // cache_read is 1/10 of input price (the key insight for cost variation)
        XCTAssertEqual(inputCost / cacheCost, 10.0, accuracy: 0.001)
    }

    /// Verify JS costForRecord matches Swift CostEstimator.cost(for:) exactly.
    func testCostForRecord_matchesSwiftCostEstimator() {
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
                           "JS/Swift cost mismatch for \(model) inp=\(inp) out=\(out) cR=\(cacheR) cW=\(cacheW)")
        }
    }

    // =========================================================
    // MARK: - computeKDE
    // =========================================================

    func testComputeKDE_singleValue_returnsEmpty() {
        let result = evalJS("""
            const kde = computeKDE([5.0]);
            return {xsLen: kde.xs.length, ysLen: kde.ys.length};
        """) as? [String: Any]
        // n < 2 → empty
        XCTAssertEqual(result?["xsLen"] as? Int, 0)
        XCTAssertEqual(result?["ysLen"] as? Int, 0)
    }

    func testComputeKDE_emptyArray_returnsEmpty() {
        let result = evalJS("""
            const kde = computeKDE([]);
            return {xsLen: kde.xs.length, ysLen: kde.ys.length};
        """) as? [String: Any]
        XCTAssertEqual(result?["xsLen"] as? Int, 0)
        XCTAssertEqual(result?["ysLen"] as? Int, 0)
    }

    func testComputeKDE_twoValues_returnsNonEmpty() {
        let result = evalJS("""
            const kde = computeKDE([1.0, 2.0]);
            return {xsLen: kde.xs.length, ysLen: kde.ys.length};
        """) as? [String: Any]
        let xsLen = result?["xsLen"] as! Int
        let ysLen = result?["ysLen"] as! Int
        XCTAssertGreaterThan(xsLen, 0)
        XCTAssertEqual(xsLen, ysLen, "xs and ys must have same length")
    }

    func testComputeKDE_outputLength_isAbout200() {
        let result = evalJS("""
            return computeKDE([1, 2, 3, 4, 5]).xs.length;
        """) as? Int
        // step = (hi - lo) / 200 → approximately 200 points
        XCTAssertGreaterThanOrEqual(result!, 190)
        XCTAssertLessThanOrEqual(result!, 210)
    }

    func testComputeKDE_densitiesAreNonNegative() {
        let result = evalJS("""
            const kde = computeKDE([1, 2, 3, 4, 5]);
            return kde.ys.every(y => y >= 0);
        """) as? Bool
        XCTAssertTrue(result!, "KDE density must be non-negative everywhere")
    }

    func testComputeKDE_peakNearMean() {
        // Symmetric data [1, 2, 3, 4, 5] → mean = 3, peak should be near x=3
        let result = evalJS("""
            const kde = computeKDE([1, 2, 3, 4, 5]);
            let maxY = -1, maxX = 0;
            for (let i = 0; i < kde.xs.length; i++) {
                if (kde.ys[i] > maxY) { maxY = kde.ys[i]; maxX = kde.xs[i]; }
            }
            return {peakX: maxX, peakY: maxY};
        """) as? [String: Any]
        let peakX = result?["peakX"] as! Double
        // Peak should be near the mean (3.0), within ±1
        XCTAssertEqual(peakX, 3.0, accuracy: 1.0,
                       "KDE peak for [1,2,3,4,5] should be near 3.0")
        let peakY = result?["peakY"] as! Double
        XCTAssertGreaterThan(peakY, 0.0)
    }

    func testComputeKDE_densityIntegral_isApproximatelyOne() {
        // The integral of a proper PDF should be approximately 1.0
        let result = evalJS("""
            const kde = computeKDE([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
            let integral = 0;
            for (let i = 1; i < kde.xs.length; i++) {
                const dx = kde.xs[i] - kde.xs[i-1];
                integral += (kde.ys[i] + kde.ys[i-1]) / 2 * dx;
            }
            return integral;
        """) as? Double
        // Trapezoidal integration of a KDE should be close to 1.0
        XCTAssertEqual(result!, 1.0, accuracy: 0.15,
                       "KDE integral should approximate 1.0 (proper probability density)")
    }

    func testComputeKDE_identicalValues_doesNotCrash() {
        // All same values → variance = 0, std = 0 → code uses || 1 fallback
        let result = evalJS("""
            const kde = computeKDE([5, 5, 5, 5, 5]);
            return {xsLen: kde.xs.length, allFinite: kde.ys.every(y => isFinite(y))};
        """) as? [String: Any]
        XCTAssertGreaterThan(result?["xsLen"] as! Int, 0)
        XCTAssertTrue(result?["allFinite"] as! Bool,
                      "KDE must not produce NaN/Infinity for identical values")
    }

    // =========================================================
    // MARK: - computeDeltas
    // =========================================================

    func testComputeDeltas_emptyUsage_returnsEmpty() {
        let result = evalJS("""
            return computeDeltas([], [{timestamp: '2026-02-24T10:00:00Z', costUSD: 1.0}]).length;
        """) as? Int
        XCTAssertEqual(result, 0)
    }

    func testComputeDeltas_singleUsage_returnsEmpty() {
        let result = evalJS("""
            return computeDeltas(
                [{timestamp: 1771927200, hourly_percent: 10}],
                [{timestamp: '2026-02-24T10:00:00Z', costUSD: 1.0}]
            ).length;
        """) as? Int
        XCTAssertEqual(result, 0, "Need at least 2 usage points to compute a delta")
    }

    func testComputeDeltas_twoUsageWithTokens_returnsOneDelta() {
        let result = evalJS("""
            const deltas = computeDeltas(
                [
                    {timestamp: 1771927200, hourly_percent: 10},
                    {timestamp: 1771927500, hourly_percent: 15},
                ],
                [
                    {timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50},
                ]
            );
            // getHours() returns local time, so compute expected hour in JS too
            const expectedHour = new Date(1771927500 * 1000).getHours();
            return {
                length: deltas.length,
                x: deltas[0].x,
                y: deltas[0].y,
                hour: deltas[0].hour,
                expectedHour: expectedHour,
            };
        """) as? [String: Any]
        XCTAssertEqual(result?["length"] as? Int, 1)
        XCTAssertEqual(result!["x"] as! Double, 0.50, accuracy: 0.001,
                       "x = intervalCost")
        XCTAssertEqual(result!["y"] as! Double, 5.0, accuracy: 0.001,
                       "y = d5h = 15 - 10 = 5")
        XCTAssertEqual(result?["hour"] as? Int, result?["expectedHour"] as? Int,
                       "hour should match getHours() of curr timestamp (local timezone)")
    }

    func testComputeDeltas_filtersOutLowCostIntervals() {
        // intervalCost <= 0.001 should be excluded
        let result = evalJS("""
            const deltas = computeDeltas(
                [
                    {timestamp: 1771927200, hourly_percent: 10},
                    {timestamp: 1771927500, hourly_percent: 20},
                ],
                [
                    {timestamp: '2026-02-24T10:02:00Z', costUSD: 0.0005},
                ]
            );
            return deltas.length;
        """) as? Int
        XCTAssertEqual(result, 0,
                       "Intervals with cost <= 0.001 must be filtered out")
    }

    func testComputeDeltas_noTokensInInterval_excluded() {
        // Token is outside the usage interval → intervalCost = 0 → excluded
        let result = evalJS("""
            const deltas = computeDeltas(
                [
                    {timestamp: 1771927200, hourly_percent: 10},
                    {timestamp: 1771927500, hourly_percent: 20},
                ],
                [
                    {timestamp: '2026-02-24T09:00:00Z', costUSD: 5.0},
                ]
            );
            return deltas.length;
        """) as? Int
        XCTAssertEqual(result, 0,
                       "Token outside usage interval → no cost → excluded")
    }

    func testComputeDeltas_multipleTokensInInterval_summed() {
        let result = evalJS("""
            const deltas = computeDeltas(
                [
                    {timestamp: 1771927200, hourly_percent: 10},
                    {timestamp: 1771927800, hourly_percent: 30},
                ],
                [
                    {timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50},
                    {timestamp: '2026-02-24T10:05:00Z', costUSD: 1.00},
                    {timestamp: '2026-02-24T10:08:00Z', costUSD: 0.25},
                ]
            );
            return {x: deltas[0].x, y: deltas[0].y};
        """) as? [String: Any]
        XCTAssertEqual(result!["x"] as! Double, 1.75, accuracy: 0.001,
                       "x = sum of costs in interval: 0.50 + 1.00 + 0.25")
        XCTAssertEqual(result!["y"] as! Double, 20.0, accuracy: 0.001,
                       "y = 30 - 10 = 20")
    }

    func testComputeDeltas_nullHourlyPercent_skipped() {
        let result = evalJS("""
            const deltas = computeDeltas(
                [
                    {timestamp: 1771927200, hourly_percent: null},
                    {timestamp: 1771927500, hourly_percent: 10},
                ],
                [
                    {timestamp: '2026-02-24T10:02:00Z', costUSD: 1.0},
                ]
            );
            return deltas.length;
        """) as? Int
        // Intervals with null hourly_percent should be skipped entirely
        XCTAssertEqual(result, 0, "Null prev percent → interval skipped, no bogus delta")
    }

    func testComputeDeltas_negativeDelta_preserved() {
        // Usage can decrease (e.g. after reset window slides)
        let result = evalJS("""
            const deltas = computeDeltas(
                [
                    {timestamp: 1771927200, hourly_percent: 50},
                    {timestamp: 1771927500, hourly_percent: 20},
                ],
                [
                    {timestamp: '2026-02-24T10:02:00Z', costUSD: 0.50},
                ]
            );
            return deltas[0].y;
        """) as? Double
        XCTAssertEqual(result!, -30.0, accuracy: 0.001,
                       "Negative delta (usage decrease) must be preserved")
    }

    // =========================================================
    // MARK: - pricingForModel — old model name formats (claude-3-*)
    // =========================================================

    func testPricingForModel_claude3Opus() {
        // Claude 3 Opus model ID: claude-3-opus-20240229
        // Should return opus pricing (input: $15), not default sonnet ($3)
        let result = evalJS("""
            return pricingForModel('claude-3-opus-20240229').input;
        """) as? Double
        XCTAssertEqual(result, 15.0,
                       "claude-3-opus should use opus pricing ($15/M input), not sonnet ($3)")
    }

    func testPricingForModel_claude35Haiku() {
        // Claude 3.5 Haiku model ID: claude-3-5-haiku-20241022
        // Should return haiku pricing (input: $0.80), not default sonnet ($3)
        let result = evalJS("""
            return pricingForModel('claude-3-5-haiku-20241022').input;
        """) as? Double
        XCTAssertEqual(result, 0.80,
                       "claude-3-5-haiku should use haiku pricing ($0.80/M input), not sonnet ($3)")
    }

    func testPricingForModel_claude3Haiku() {
        let result = evalJS("""
            return pricingForModel('claude-3-haiku-20240307').input;
        """) as? Double
        XCTAssertEqual(result, 0.80,
                       "claude-3-haiku should use haiku pricing ($0.80/M input)")
    }

    func testPricingForModel_claude35Sonnet() {
        // Claude 3.5 Sonnet should correctly fall through to sonnet pricing
        let result = evalJS("""
            return pricingForModel('claude-3-5-sonnet-20241022').input;
        """) as? Double
        XCTAssertEqual(result, 3.0,
                       "claude-3-5-sonnet should use sonnet pricing ($3/M input)")
    }

    // =========================================================
    // MARK: - costForRecord — old model names produce correct costs
    // =========================================================

    func testCostForRecord_claude3Opus_usesOpusPricing() {
        let result = evalJS("""
            return costForRecord({
                model: 'claude-3-opus-20240229',
                input_tokens: 1000000, output_tokens: 0,
                cache_read_tokens: 0, cache_creation_tokens: 0
            });
        """) as? Double
        // Should be opus: 1M * $15/M = $15, not sonnet: 1M * $3/M = $3
        XCTAssertEqual(result!, 15.0, accuracy: 0.001,
                       "claude-3-opus 1M input should cost $15 (opus), not $3 (sonnet)")
    }

    func testCostForRecord_claude35Haiku_usesHaikuPricing() {
        let result = evalJS("""
            return costForRecord({
                model: 'claude-3-5-haiku-20241022',
                input_tokens: 1000000, output_tokens: 0,
                cache_read_tokens: 0, cache_creation_tokens: 0
            });
        """) as? Double
        // Should be haiku: 1M * $0.80/M = $0.80, not sonnet: $3
        XCTAssertEqual(result!, 0.80, accuracy: 0.001,
                       "claude-3-5-haiku 1M input should cost $0.80 (haiku), not $3 (sonnet)")
    }

    // =========================================================
    // MARK: - Swift CostEstimator — old model name matching
    // =========================================================

    func testSwiftPricingForModel_claude3Opus() {
        let pricing = CostEstimator.pricingForModel("claude-3-opus-20240229")
        XCTAssertEqual(pricing.input, 15.0,
                       "Swift: claude-3-opus should use opus pricing ($15/M input)")
    }

    func testSwiftPricingForModel_claude35Haiku() {
        let pricing = CostEstimator.pricingForModel("claude-3-5-haiku-20241022")
        XCTAssertEqual(pricing.input, 0.80,
                       "Swift: claude-3-5-haiku should use haiku pricing ($0.80/M input)")
    }

    func testSwiftPricingForModel_claude3Haiku() {
        let pricing = CostEstimator.pricingForModel("claude-3-haiku-20240307")
        XCTAssertEqual(pricing.input, 0.80,
                       "Swift: claude-3-haiku should use haiku pricing ($0.80/M input)")
    }

    // =========================================================
    // MARK: - computeDeltas — token at exact boundary
    // =========================================================

    func testComputeDeltas_tokenAtExactT1_excludedFromInterval() {
        // Token at exactly t1 (the curr timestamp) should NOT be in interval [t0, t1)
        let result = evalJS("""
            const deltas = computeDeltas(
                [
                    {timestamp: 1771927200, hourly_percent: 10},
                    {timestamp: 1771927500, hourly_percent: 20},
                    {timestamp: 1771927800, hourly_percent: 30},
                ],
                [
                    {timestamp: '2026-02-24T10:05:00Z', costUSD: 0.50},
                ]
            );
            // Token at 10:05 → interval [10:00, 10:05): t >= t0 && t < t1 → 10:05 is NOT < 10:05
            // Token should be in interval [10:05, 10:10): t >= 10:05 && t < 10:10 → YES
            return {
                count: deltas.length,
                firstX: deltas[0]?.x,
                secondX: deltas[1]?.x,
            };
        """) as? [String: Any]
        // First interval [10:00, 10:05) has no tokens → excluded (cost < 0.001)
        // Second interval [10:05, 10:10) has token $0.50 → included
        XCTAssertEqual(result?["count"] as? Int, 1,
                       "Only one interval should have cost > 0.001")
        XCTAssertEqual(result?["secondX"] as? Double ?? result?["firstX"] as? Double ?? 0,
                       0.50, accuracy: 0.001)
    }

    // =========================================================
    // MARK: - timeXScale
    // =========================================================

    func testTimeXScale_withMinMax_returnsMinMax() {
        let result = evalJS("""
            _xMin = 1709251200000;
            _xMax = 1709856000000;
            const cfg = timeXScale();
            return {type: cfg.type, min: cfg.min, max: cfg.max, hasMin: 'min' in cfg, hasMax: 'max' in cfg};
        """) as? [String: Any]
        XCTAssertEqual(result?["type"] as? String, "time")
        XCTAssertTrue(result?["hasMin"] as? Bool ?? false, "cfg should contain min")
        XCTAssertTrue(result?["hasMax"] as? Bool ?? false, "cfg should contain max")
        XCTAssertEqual(result?["min"] as? Double, 1709251200000)
        XCTAssertEqual(result?["max"] as? Double, 1709856000000)
    }

    func testTimeXScale_withNullMinMax_omitsMinMax() {
        let result = evalJS("""
            _xMin = null;
            _xMax = null;
            const cfg = timeXScale();
            return {type: cfg.type, hasMin: 'min' in cfg, hasMax: 'max' in cfg};
        """) as? [String: Any]
        XCTAssertEqual(result?["type"] as? String, "time")
        XCTAssertFalse(result?["hasMin"] as? Bool ?? true, "cfg should NOT contain min when _xMin is null")
        XCTAssertFalse(result?["hasMax"] as? Bool ?? true, "cfg should NOT contain max when _xMax is null")
    }

}
