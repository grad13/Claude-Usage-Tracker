// generated: spec/ui/mini-usage-graph.md (spec-v2.1)
// source: MiniUsageGraph.swift
// DO NOT EDIT MANUALLY — regenerate from spec

import XCTest
@testable import ClaudeUsageTracker

/// Tests for MiniUsageGraph logic extracted from spec/ui/mini-usage-graph.md.
///
/// Canvas drawing itself is not tested here. These tests cover the pure
/// logic functions that are exercised during drawing:
///   - usageValue(from:windowSeconds:)       — 3.1 使用率の選択
///   - xPosition(for:windowStart:windowSeconds:chartWidth:) — 3.2 X 座標正規化
///   - windowStart(resetsAt:history:windowSeconds:)         — 3.3 windowStart 決定
///   - backgroundColor(isLoggedIn:)                         — 3.4 背景色の選択
///   - yFrac(usage:)                                        — 3.8 yFrac のクランプ
final class MiniUsageGraphTests: XCTestCase {

    // MARK: - Helpers

    /// Build a minimal DataPoint for injection into test cases.
    private func makeDataPoint(
        timestamp: Date = Date(),
        fiveHourPercent: Double? = nil,
        sevenDayPercent: Double? = nil,
        fiveHourResetsAt: Date? = nil,
        sevenDayResetsAt: Date? = nil
    ) -> MiniUsageGraph.DataPoint {
        MiniUsageGraph.DataPoint(
            timestamp: timestamp,
            fiveHourPercent: fiveHourPercent,
            sevenDayPercent: sevenDayPercent,
            fiveHourResetsAt: fiveHourResetsAt,
            sevenDayResetsAt: sevenDayResetsAt
        )
    }

    // MARK: - 3.1 usageValue — 使用率の選択

    /// UV-01: windowSeconds = 18000 (5h ちょうど) → fiveHourPercent を返す
    func testUsageValue_UV01_fiveHour_exact() {
        let dp = makeDataPoint(fiveHourPercent: 50.0, sevenDayPercent: 80.0)
        XCTAssertEqual(MiniUsageGraph.usageValue(from: dp, windowSeconds: 18000), 50.0)
    }

    /// UV-02: windowSeconds = 18001 (閾値ちょうど) → fiveHourPercent を返す（18001 以下は fiveHour）
    func testUsageValue_UV02_fiveHour_atThreshold() {
        let dp = makeDataPoint(fiveHourPercent: 50.0, sevenDayPercent: 80.0)
        XCTAssertEqual(MiniUsageGraph.usageValue(from: dp, windowSeconds: 18001), 50.0)
    }

    /// UV-03: windowSeconds = 18002 (閾値超過) → sevenDayPercent を返す
    func testUsageValue_UV03_sevenDay_aboveThreshold() {
        let dp = makeDataPoint(fiveHourPercent: 50.0, sevenDayPercent: 80.0)
        XCTAssertEqual(MiniUsageGraph.usageValue(from: dp, windowSeconds: 18002), 80.0)
    }

    /// UV-04: windowSeconds = 604800 (7日ウィンドウ) → sevenDayPercent を返す
    func testUsageValue_UV04_sevenDay_fullWindow() {
        let dp = makeDataPoint(fiveHourPercent: 50.0, sevenDayPercent: 80.0)
        XCTAssertEqual(MiniUsageGraph.usageValue(from: dp, windowSeconds: 604800), 80.0)
    }

    /// UV-05: windowSeconds = 3600 (1h) で fiveHourPercent が nil → nil
    func testUsageValue_UV05_fiveHourNil_returnsNil() {
        let dp = makeDataPoint(fiveHourPercent: nil, sevenDayPercent: 80.0)
        XCTAssertNil(MiniUsageGraph.usageValue(from: dp, windowSeconds: 3600))
    }

    /// UV-06: windowSeconds = 86400 (1d) で sevenDayPercent が nil → nil
    func testUsageValue_UV06_sevenDayNil_returnsNil() {
        let dp = makeDataPoint(fiveHourPercent: 50.0, sevenDayPercent: nil)
        XCTAssertNil(MiniUsageGraph.usageValue(from: dp, windowSeconds: 86400))
    }

    // MARK: - 3.2 xPosition — X 座標正規化

    /// XP-01: timestamp == windowStart → 0.0 (ウィンドウ開始)
    func testXPosition_XP01_windowStart_isZero() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let result = MiniUsageGraph.xPosition(
            for: base,
            windowStart: base,
            windowSeconds: 3600,
            chartWidth: 1.0
        )
        XCTAssertEqual(result, 0.0, accuracy: 1e-9)
    }

    /// XP-02: timestamp = windowStart + 1800s, windowSeconds = 3600 → 0.5 (中間点)
    func testXPosition_XP02_midpoint_isHalf() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let ts = base.addingTimeInterval(1800)
        let result = MiniUsageGraph.xPosition(
            for: ts,
            windowStart: base,
            windowSeconds: 3600,
            chartWidth: 1.0
        )
        XCTAssertEqual(result, 0.5, accuracy: 1e-9)
    }

    /// XP-03: timestamp = windowStart + 3600s (ウィンドウ終了) → 1.0
    func testXPosition_XP03_windowEnd_isOne() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let ts = base.addingTimeInterval(3600)
        let result = MiniUsageGraph.xPosition(
            for: ts,
            windowStart: base,
            windowSeconds: 3600,
            chartWidth: 1.0
        )
        XCTAssertEqual(result, 1.0, accuracy: 1e-9)
    }

    /// XP-04: timestamp = windowStart - 100s (ウィンドウ前) → 0.0 にクランプ
    func testXPosition_XP04_beforeWindow_clampedToZero() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let ts = base.addingTimeInterval(-100)
        let result = MiniUsageGraph.xPosition(
            for: ts,
            windowStart: base,
            windowSeconds: 3600,
            chartWidth: 1.0
        )
        XCTAssertEqual(result, 0.0, accuracy: 1e-9)
    }

    /// XP-05: timestamp = windowStart + 7200s (ウィンドウ後) → 1.0 にクランプ
    func testXPosition_XP05_afterWindow_clampedToOne() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let ts = base.addingTimeInterval(7200)
        let result = MiniUsageGraph.xPosition(
            for: ts,
            windowStart: base,
            windowSeconds: 3600,
            chartWidth: 1.0
        )
        XCTAssertEqual(result, 1.0, accuracy: 1e-9)
    }

    // MARK: - 3.3 windowStart の決定ロジック

    /// WS-01: resetsAt が指定されている → resetsAt - windowSeconds
    func testWindowStart_WS01_resetsAt_priority() {
        let resetsAt = Date(timeIntervalSinceReferenceDate: 10000)
        let windowSeconds: TimeInterval = 3600
        let dp = makeDataPoint(timestamp: Date(timeIntervalSinceReferenceDate: 0))
        let result = MiniUsageGraph.windowStart(
            resetsAt: resetsAt,
            history: [dp],
            windowSeconds: windowSeconds
        )
        XCTAssertEqual(result, resetsAt.addingTimeInterval(-windowSeconds))
    }

    /// WS-02: resetsAt = nil, history に要素あり → history.first.timestamp
    func testWindowStart_WS02_nil_resetsAt_uses_firstTimestamp() {
        let t0 = Date(timeIntervalSinceReferenceDate: 5000)
        let dp = makeDataPoint(timestamp: t0)
        let result = MiniUsageGraph.windowStart(
            resetsAt: nil,
            history: [dp],
            windowSeconds: 3600
        )
        XCTAssertEqual(result, t0)
    }

    /// WS-03: resetsAt = nil, history が空 → nil（描画スキップ）
    func testWindowStart_WS03_nil_resetsAt_emptyHistory_returnsNil() {
        let result = MiniUsageGraph.windowStart(
            resetsAt: nil,
            history: [],
            windowSeconds: 3600
        )
        XCTAssertNil(result)
    }

    // MARK: - 3.4 背景色の選択

    /// BG-01: isLoggedIn = true → bgColor (#121212)
    func testBackgroundColor_BG01_loggedIn_isDark() {
        let color = MiniUsageGraph.backgroundColor(isLoggedIn: true)
        // bgColor = #121212 → r=18/255, g=18/255, b=18/255
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        NSColor(color).usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 18.0 / 255.0, accuracy: 0.005)
        XCTAssertEqual(g, 18.0 / 255.0, accuracy: 0.005)
        XCTAssertEqual(b, 18.0 / 255.0, accuracy: 0.005)
    }

    /// BG-02: isLoggedIn = false → bgColorSignedOut (#3A1010)
    func testBackgroundColor_BG02_signedOut_isWarningColor() {
        let color = MiniUsageGraph.backgroundColor(isLoggedIn: false)
        // bgColorSignedOut = #3A1010 → r=58/255, g=16/255, b=16/255
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        NSColor(color).usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 58.0 / 255.0, accuracy: 0.005)
        XCTAssertEqual(g, 16.0 / 255.0, accuracy: 0.005)
        XCTAssertEqual(b, 16.0 / 255.0, accuracy: 0.005)
    }

    // MARK: - 3.8 yFrac のクランプ

    /// YF-01: usage = 0.0 → yFrac = 0.0 (下端)
    func testYFrac_YF01_zero() {
        XCTAssertEqual(MiniUsageGraph.yFrac(usage: 0.0), 0.0, accuracy: 1e-9)
    }

    /// YF-02: usage = 50.0 → yFrac = 0.5 (中央)
    func testYFrac_YF02_midpoint() {
        XCTAssertEqual(MiniUsageGraph.yFrac(usage: 50.0), 0.5, accuracy: 1e-9)
    }

    /// YF-03: usage = 100.0 → yFrac = 1.0 (上端)
    func testYFrac_YF03_full() {
        XCTAssertEqual(MiniUsageGraph.yFrac(usage: 100.0), 1.0, accuracy: 1e-9)
    }

    /// YF-04: usage = 150.0 (100% 超) → yFrac = 1.0 にクランプ
    func testYFrac_YF04_over100_clampedToOne() {
        XCTAssertEqual(MiniUsageGraph.yFrac(usage: 150.0), 1.0, accuracy: 1e-9)
    }
}
