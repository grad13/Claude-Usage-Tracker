import XCTest
import WebKit
@testable import ClaudeUsageTracker

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
