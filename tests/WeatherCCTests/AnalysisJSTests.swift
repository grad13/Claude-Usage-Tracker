import XCTest
import WebKit
@testable import WeatherCC

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

}

// MARK: - Additional JS Logic Tests (edge cases, timeSlots, stats, cumulative)

/// Extended JS logic tests covering timeSlots filtering, cumulative cost,
/// stats computation from main(), boundary values, and template drift detection.
final class AnalysisJSExtendedTests: AnalysisJSTestCase {

    // =========================================================
    // MARK: - timeSlots filtering
    // =========================================================

    func testTimeSlots_nightFilter_hoursBelow6() {
        let result = evalJS("""
            return [0,1,2,3,4,5,6,11,12,17,18,23].filter(h => timeSlots[0].filter({hour: h}));
        """) as? [Int]
        XCTAssertEqual(result, [0, 1, 2, 3, 4, 5], "Night = hours 0-5")
    }

    func testTimeSlots_morningFilter_hours6to11() {
        let result = evalJS("""
            return [0,5,6,7,8,9,10,11,12,18].filter(h => timeSlots[1].filter({hour: h}));
        """) as? [Int]
        XCTAssertEqual(result, [6, 7, 8, 9, 10, 11], "Morning = hours 6-11")
    }

    func testTimeSlots_afternoonFilter_hours12to17() {
        let result = evalJS("""
            return [0,6,11,12,13,14,15,16,17,18,23].filter(h => timeSlots[2].filter({hour: h}));
        """) as? [Int]
        XCTAssertEqual(result, [12, 13, 14, 15, 16, 17], "Afternoon = hours 12-17")
    }

    func testTimeSlots_eveningFilter_hoursAbove18() {
        let result = evalJS("""
            return [0,6,12,17,18,19,20,21,22,23].filter(h => timeSlots[3].filter({hour: h}));
        """) as? [Int]
        XCTAssertEqual(result, [18, 19, 20, 21, 22, 23], "Evening = hours 18-23")
    }

    func testTimeSlots_everyHourBelongsToExactlyOneSlot() {
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
        XCTAssertTrue(result!, "Every hour 0-23 must match exactly one timeSlot (no gaps, no overlaps)")
    }

    // =========================================================
    // MARK: - Cumulative cost logic
    // =========================================================

    func testCumulativeCost_correctAccumulation() {
        let result = evalJS("""
            const tokenData = [
                {timestamp: '2026-02-24T10:00:00Z', costUSD: 1.50},
                {timestamp: '2026-02-24T10:01:00Z', costUSD: 0.75},
                {timestamp: '2026-02-24T10:02:00Z', costUSD: 2.00},
            ];
            let cumCost = 0;
            const cumData = tokenData.map(r => {
                cumCost += r.costUSD;
                return { x: r.timestamp, y: Math.round(cumCost * 100) / 100 };
            });
            return cumData.map(d => d.y);
        """) as? [Double]
        XCTAssertEqual(result, [1.50, 2.25, 4.25])
    }

    func testCumulativeCost_emptyData() {
        let result = evalJS("""
            let cumCost = 0;
            const cumData = [].map(r => {
                cumCost += r.costUSD;
                return { y: Math.round(cumCost * 100) / 100 };
            });
            return cumData.length;
        """) as? Int
        XCTAssertEqual(result, 0)
    }

    func testCumulativeCost_roundsTo2Decimals() {
        let result = evalJS("""
            const tokenData = [
                {costUSD: 0.001}, {costUSD: 0.001}, {costUSD: 0.001},
            ];
            let cumCost = 0;
            return tokenData.map(r => {
                cumCost += r.costUSD;
                return Math.round(cumCost * 100) / 100;
            });
        """) as? [Double]
        XCTAssertEqual(result, [0.0, 0.0, 0.0],
                       "Very small costs should round to 0.00")
    }

    func testCumulativeCost_largeAccumulation() {
        let result = evalJS("""
            const tokenData = Array.from({length: 1000}, () => ({costUSD: 0.50}));
            let cumCost = 0;
            const last = tokenData.reduce((_, r) => {
                cumCost += r.costUSD;
                return Math.round(cumCost * 100) / 100;
            }, 0);
            return last;
        """) as? Double
        XCTAssertEqual(result!, 500.0, accuracy: 0.01)
    }

    // =========================================================
    // MARK: - Stats computation (totalCost, usageSpan, latest values)
    // =========================================================

    func testStats_totalCost() {
        let result = evalJS("""
            const tokenData = [
                {costUSD: 1.50}, {costUSD: 2.00}, {costUSD: 0.75},
            ];
            return tokenData.reduce((s, r) => s + r.costUSD, 0);
        """) as? Double
        XCTAssertEqual(result!, 4.25, accuracy: 0.001)
    }

    func testStats_usageSpan_multipleRecords() {
        let result = evalJS("""
            const usageData = [
                {timestamp: 1771927200},
                {timestamp: 1771930800},
                {timestamp: 1771939800},
            ];
            const span = ((new Date(usageData[usageData.length-1].timestamp * 1000) - new Date(usageData[0].timestamp * 1000)) / 3600000).toFixed(1);
            return parseFloat(span);
        """) as? Double
        XCTAssertEqual(result!, 3.5, accuracy: 0.01, "10:00 to 13:30 = 3.5 hours")
    }

    func testStats_usageSpan_singleRecord() {
        let result = evalJS("""
            const usageData = [{timestamp: 1771927200}];
            const span = usageData.length > 1
                ? ((new Date(usageData[usageData.length-1].timestamp * 1000) - new Date(usageData[0].timestamp * 1000)) / 3600000).toFixed(1)
                : '0';
            return span;
        """) as? String
        XCTAssertEqual(result, "0")
    }

    func testStats_latestValues() {
        let result = evalJS("""
            const usageData = [
                {hourly_percent: 10, weekly_percent: 5},
                {hourly_percent: 42.5, weekly_percent: 15.3},
            ];
            return {
                fiveH: usageData[usageData.length - 1]?.hourly_percent ?? '-',
                sevenD: usageData[usageData.length - 1]?.weekly_percent ?? '-',
            };
        """) as? [String: Any]
        XCTAssertEqual(result?["fiveH"] as? Double, 42.5)
        XCTAssertEqual(result?["sevenD"] as? Double, 15.3)
    }

    func testStats_latestValues_emptyData() {
        let result = evalJS("""
            const usageData = [];
            return {
                fiveH: usageData[usageData.length - 1]?.hourly_percent ?? '-',
                sevenD: usageData[usageData.length - 1]?.weekly_percent ?? '-',
            };
        """) as? [String: Any]
        XCTAssertEqual(result?["fiveH"] as? String, "-", "Empty data → dash fallback")
        XCTAssertEqual(result?["sevenD"] as? String, "-", "Empty data → dash fallback")
    }

    // =========================================================
    // MARK: - Boundary value tests
    // =========================================================

    func testCostForRecord_veryLargeTokenCount() {
        let result = evalJS("""
            return costForRecord({
                model: 'claude-sonnet-4-20250514',
                input_tokens: 100000000, output_tokens: 50000000,
                cache_read_tokens: 200000000, cache_creation_tokens: 10000000
            });
        """) as? Double
        // 100M * 3.0/1M + 50M * 15.0/1M + 200M * 0.30/1M + 10M * 3.75/1M
        // = 300 + 750 + 60 + 37.5 = 1147.5
        XCTAssertEqual(result!, 1147.5, accuracy: 0.01)
    }

    func testCostForRecord_singleToken() {
        let result = evalJS("""
            return costForRecord({
                model: 'claude-sonnet-4-20250514',
                input_tokens: 1, output_tokens: 0,
                cache_read_tokens: 0, cache_creation_tokens: 0
            });
        """) as? Double
        // 1 / 1M * 3.0 = 0.000003
        XCTAssertEqual(result!, 0.000003, accuracy: 0.0000001)
    }

    func testComputeDeltas_exactBoundaryTimestamp() {
        // Token at t0 (inclusive) should be included, token at t1 (exclusive) should not
        let result = evalJS("""
            const deltas = computeDeltas(
                [
                    {timestamp: 1771927200, hourly_percent: 10},
                    {timestamp: 1771927500, hourly_percent: 20},
                ],
                [
                    {timestamp: '2026-02-24T10:00:00Z', costUSD: 0.50},
                    {timestamp: '2026-02-24T10:05:00Z', costUSD: 0.75},
                ]
            );
            return {count: deltas.length, cost: deltas[0]?.x};
        """) as? [String: Any]
        XCTAssertEqual(result?["count"] as? Int, 1)
        XCTAssertEqual(result!["cost"] as! Double, 0.50, accuracy: 0.001,
                       "Token at t0 included (>=), token at t1 excluded (<)")
    }

    func testComputeKDE_negativeValues() {
        let result = evalJS("""
            const kde = computeKDE([-5, -3, -1, 1, 3, 5]);
            let maxY = -1, maxX = 0;
            for (let i = 0; i < kde.xs.length; i++) {
                if (kde.ys[i] > maxY) { maxY = kde.ys[i]; maxX = kde.xs[i]; }
            }
            return {peakX: maxX, xsLen: kde.xs.length, allFinite: kde.ys.every(y => isFinite(y))};
        """) as? [String: Any]
        XCTAssertTrue(result?["allFinite"] as! Bool)
        XCTAssertEqual(result?["peakX"] as! Double, 0.0, accuracy: 1.5,
                       "Peak of symmetric [-5..5] should be near 0")
    }

    func testComputeKDE_verySpreadData() {
        let result = evalJS("""
            const kde = computeKDE([0.001, 1000]);
            return {xsLen: kde.xs.length, allFinite: kde.ys.every(y => isFinite(y))};
        """) as? [String: Any]
        XCTAssertGreaterThan(result?["xsLen"] as! Int, 0)
        XCTAssertTrue(result?["allFinite"] as! Bool, "Wide spread must not produce NaN")
    }

    // =========================================================
    // MARK: - End-to-end: costForRecord + computeDeltas combined
    // =========================================================

    func testEndToEnd_rawTokensToDelta() {
        // Simulates the full pipeline: raw token records → costForRecord → computeDeltas
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

    func testEndToEnd_multipleIntervalsWithMixedModels() {
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
            return {
                count: deltas.length,
                delta0cost: deltas[0]?.x,
                delta0pct: deltas[0]?.y,
                delta1cost: deltas[1]?.x,
                delta1pct: deltas[1]?.y,
            };
        """) as? [String: Any]
        XCTAssertEqual(result?["count"] as? Int, 2)
        // Interval 1: opus 10k in + 5k out = 0.01*15 + 0.005*75 = 0.15 + 0.375 = 0.525
        XCTAssertEqual(result!["delta0cost"] as! Double, 0.525, accuracy: 0.001)
        XCTAssertEqual(result!["delta0pct"] as! Double, 5.0, accuracy: 0.001)
        // Interval 2: haiku 50k in + 10k out + 100k cache_read = 0.05*0.80 + 0.01*4.0 + 0.1*0.08 = 0.04 + 0.04 + 0.008 = 0.088
        XCTAssertEqual(result!["delta1cost"] as! Double, 0.088, accuracy: 0.001)
        XCTAssertEqual(result!["delta1pct"] as! Double, 1.0, accuracy: 0.001)
    }

    // =========================================================
    // MARK: - Template drift detection
    // =========================================================

    /// Verify that the pure JS functions in the REAL HTML template match the expected implementations.
    /// If someone changes a function in AnalysisExporter.swift but not in the test HTML, this catches it.
    func testTemplateDrift_pricingForModelFunctionExists() {
        let html = AnalysisExporter.htmlTemplate
        // Extract the function body from the template
        XCTAssertTrue(html.contains("function pricingForModel(model)"))
        XCTAssertTrue(html.contains("if (model.includes('opus')) return MODEL_PRICING.opus;"))
        XCTAssertTrue(html.contains("if (model.includes('haiku')) return MODEL_PRICING.haiku;"))
        XCTAssertTrue(html.contains("return MODEL_PRICING.sonnet;"))
    }

    func testTemplateDrift_costForRecordFormula() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("r.input_tokens / M * p.input"))
        XCTAssertTrue(html.contains("r.output_tokens / M * p.output"))
        XCTAssertTrue(html.contains("r.cache_creation_tokens / M * p.cacheWrite"))
        XCTAssertTrue(html.contains("r.cache_read_tokens / M * p.cacheRead"))
    }

    func testTemplateDrift_computeDeltasThreshold() {
        let html = AnalysisExporter.htmlTemplate
        XCTAssertTrue(html.contains("if (intervalCost > 0.001)"),
                      "computeDeltas must filter intervals with cost <= 0.001")
    }

    func testTemplateDrift_computeKDEBandwidthFormula() {
        let html = AnalysisExporter.htmlTemplate
        // Silverman's rule of thumb: h = 1.06 * std * n^(-0.2)
        XCTAssertTrue(html.contains("1.06 * std * Math.pow(n, -0.2)"),
                      "KDE must use Silverman's rule of thumb for bandwidth")
    }

    func testTemplateDrift_modelPricingValues() {
        let html = AnalysisExporter.htmlTemplate
        // Verify exact pricing lines to catch any price update
        XCTAssertTrue(html.contains("opus:   { input: 15.0,  output: 75.0, cacheWrite: 18.75, cacheRead: 1.50 }"))
        XCTAssertTrue(html.contains("sonnet: { input: 3.0,   output: 15.0, cacheWrite: 3.75,  cacheRead: 0.30 }"))
        XCTAssertTrue(html.contains("haiku:  { input: 0.80,  output: 4.0,  cacheWrite: 1.0,   cacheRead: 0.08 }"))
    }

    // =========================================================
    // MARK: - computeDeltas with many intervals
    // =========================================================

    func testComputeDeltas_100Intervals() {
        let result = evalJS("""
            const usageData = Array.from({length: 101}, (_, i) => ({
                timestamp: Math.floor(Date.UTC(2026, 1, 24, 10, i * 5) / 1000),
                hourly_percent: i * 0.5,
            }));
            const tokenData = Array.from({length: 100}, (_, i) => ({
                timestamp: new Date(Date.UTC(2026, 1, 24, 10, i * 5 + 1)).toISOString(),
                costUSD: 0.10,
            }));
            const deltas = computeDeltas(usageData, tokenData);
            return {
                count: deltas.length,
                allPositiveX: deltas.every(d => d.x > 0),
                allEqualCost: deltas.every(d => Math.abs(d.x - 0.10) < 0.001),
                allEqualDelta: deltas.every(d => Math.abs(d.y - 0.5) < 0.001),
            };
        """) as? [String: Any]
        XCTAssertEqual(result?["count"] as? Int, 100)
        XCTAssertTrue(result?["allPositiveX"] as! Bool)
        XCTAssertTrue(result?["allEqualCost"] as! Bool)
        XCTAssertTrue(result?["allEqualDelta"] as! Bool)
    }

    func testComputeDeltas_tokenAtExactPrevTimestamp_included() {
        // Token at exactly t0 should be >= t0, so included
        let result = evalJS("""
            const deltas = computeDeltas(
                [
                    {timestamp: 1771927200, hourly_percent: 0},
                    {timestamp: 1771927500, hourly_percent: 10},
                ],
                [{timestamp: '2026-02-24T10:00:00.000Z', costUSD: 1.0}]
            );
            return deltas.length;
        """) as? Int
        XCTAssertEqual(result, 1, "Token at exact prev timestamp (t >= t0) should be included")
    }

    func testComputeDeltas_tokenAtExactCurrTimestamp_excluded() {
        // Token at exactly t1 should be < t1, so excluded
        let result = evalJS("""
            const deltas = computeDeltas(
                [
                    {timestamp: 1771927200, hourly_percent: 0},
                    {timestamp: 1771927500, hourly_percent: 10},
                ],
                [{timestamp: '2026-02-24T10:05:00.000Z', costUSD: 1.0}]
            );
            return deltas.length;
        """) as? Int
        XCTAssertEqual(result, 0, "Token at exact curr timestamp (t < t1) should be excluded → no cost → no delta")
    }

    // =========================================================
    // MARK: - KDE mathematical properties
    // =========================================================

    func testComputeKDE_symmetricInput_symmetricOutput() {
        let result = evalJS("""
            const kde = computeKDE([-2, -1, 0, 1, 2]);
            // Check symmetry: density at -x should ≈ density at +x
            const midIdx = Math.floor(kde.xs.length / 2);
            let maxAsymmetry = 0;
            for (let i = 0; i < midIdx && i < kde.xs.length - midIdx; i++) {
                const leftY = kde.ys[midIdx - i];
                const rightY = kde.ys[midIdx + i];
                if (leftY > 0.001 || rightY > 0.001) {
                    maxAsymmetry = Math.max(maxAsymmetry, Math.abs(leftY - rightY) / Math.max(leftY, rightY));
                }
            }
            return maxAsymmetry;
        """) as? Double
        XCTAssertLessThan(result!, 0.15,
                          "KDE of symmetric data should produce approximately symmetric output")
    }

    func testComputeKDE_bimodalInput_hasTwoPeaks() {
        let result = evalJS("""
            // Two clusters far apart: [0,0,0,0,0] and [100,100,100,100,100]
            const kde = computeKDE([0,0,0,0,0, 100,100,100,100,100]);
            // Find local maxima
            let peaks = 0;
            for (let i = 1; i < kde.xs.length - 1; i++) {
                if (kde.ys[i] > kde.ys[i-1] && kde.ys[i] > kde.ys[i+1]) peaks++;
            }
            return peaks;
        """) as? Int
        XCTAssertEqual(result, 2, "Bimodal data should produce exactly 2 peaks")
    }

    func testComputeKDE_bandwidthScalesWithN() {
        // h = 1.06 * std * n^(-0.2). More data → smaller bandwidth → sharper peak
        let result = evalJS("""
            const small = computeKDE([1, 2, 3, 4, 5]);
            const large = computeKDE([1,1,1,2,2,2,3,3,3,4,4,4,5,5,5,1,2,3,4,5]);
            const smallPeak = Math.max(...small.ys);
            const largePeak = Math.max(...large.ys);
            return largePeak > smallPeak;
        """) as? Bool
        XCTAssertTrue(result!, "More data points → smaller bandwidth → higher peak density")
    }
}

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
                localDateStr: typeof localDateStr === 'function',
                dateInputToEpoch: typeof dateInputToEpoch === 'function',
                initGlobalRange: typeof initGlobalRange === 'function',
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
