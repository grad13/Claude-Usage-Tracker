---
Created: 2026-02-26
Updated: 2026-03-07
Checked: -
Deprecated: -
Format: spec-v2.1
Source: code/ClaudeUsageTracker/MiniUsageGraph.swift
---

# Specification: MiniUsageGraph

## 0. Meta

| Source | Runtime |
|--------|---------|
| code/ClaudeUsageTracker/MiniUsageGraph.swift | Swift |

| Field | Value |
|-------|-------|
| Related | code/ClaudeUsageTracker/UsageStore.swift (DataPoint) |
| Test Type | Unit |

## 1. Contract (Swift)

> AI Instruction: Treat this type definition as the single source of truth. Use it for mocks and test types.

```swift
/// Mini usage graph for the menu bar (SwiftUI Canvas-based)
struct MiniUsageGraph: View {
    // --- Input properties ---
    let history: [UsageStore.DataPoint]   // Array of usage data points (chronological order)
    let windowSeconds: TimeInterval       // Time window to display (in seconds)
    let resetsAt: Date?                   // Reset time (if nil, uses history.first.timestamp as reference)
    let areaColor: Color                  // Area fill color
    let areaOpacity: Double               // Area fill opacity
    let divisions: Int                    // Number of time division markers
    let chartWidth: CGFloat               // Chart width
    let isLoggedIn: Bool                  // Login state (affects background color)

    // --- Environment ---
    @Environment(\.colorScheme) private var colorScheme

    // --- Computed color properties (colorScheme-dependent) ---
    // bgColor:          dark=#121212, light=#E8E8E8 (logged-in)
    //                   dark=#3A1010, light=#FFCCCC (signed-out)
    // tickColor:        dark=white 0.07, light=black 0.1
    // usageLineColor:   dark=white 0.3,  light=black 0.3
    // noDataFill:       dark=white 0.06, light=black 0.06

    // --- Output ---
    // body: Canvas (.frame(width: chartWidth, height: 18))
}
```

### Dependent Type

```swift
// UsageStore.DataPoint (code/ClaudeUsageTracker/UsageStore.swift)
struct DataPoint {
    let timestamp: Date
    let fiveHourPercent: Double?
    let sevenDayPercent: Double?
    let fiveHourResetsAt: Date?
    let sevenDayResetsAt: Date?
}
```

## 2. State

No state transitions. MiniUsageGraph is a pure rendering view with no internal state. It only performs Canvas drawing from its input properties.

## 3. Logic (Decision Table)

### 3.1 usageValue(from:) — Usage Value Selection

> AI Instruction: Generate a Unit Test for each row as a parameterized test (per-case test method or loop).

| Case ID | windowSeconds | DataPoint.fiveHourPercent | DataPoint.sevenDayPercent | Expected | Notes |
|---------|---------------|---------------------------|---------------------------|----------|-------|
| UV-01 | 18000 (5h) | 50.0 | 80.0 | 50.0 | Exactly 5h → fiveHourPercent |
| UV-02 | 18001 (5h+1s) | 50.0 | 80.0 | 50.0 | Threshold is `5*3600+1 = 18001`. 18001 or below → fiveHour |
| UV-03 | 18002 (5h+2s) | 50.0 | 80.0 | 80.0 | Above 18001 → sevenDayPercent |
| UV-04 | 604800 (7d) | 50.0 | 80.0 | 80.0 | 7-day window → sevenDayPercent |
| UV-05 | 3600 (1h) | nil | 80.0 | nil | fiveHourPercent is nil → nil |
| UV-06 | 86400 (1d) | 50.0 | nil | nil | sevenDayPercent is nil → nil |

### 3.2 xPosition(for:windowStart:) — X Coordinate Normalization

| Case ID | timestamp - windowStart | windowSeconds | Expected | Notes |
|---------|-------------------------|---------------|----------|-------|
| XP-01 | 0s | 3600 | 0.0 | Window start |
| XP-02 | 1800s | 3600 | 0.5 | Midpoint |
| XP-03 | 3600s | 3600 | 1.0 | Window end |
| XP-04 | -100s | 3600 | 0.0 | Before window → clamped to 0 |
| XP-05 | 7200s | 3600 | 1.0 | After window → clamped to 1 |

### 3.3 windowStart Determination Logic

| Case ID | resetsAt | history | Expected windowStart | Notes |
|---------|----------|---------|----------------------|-------|
| WS-01 | Date(X) | any | X - windowSeconds | resetsAt takes priority |
| WS-02 | nil | [dp(T0), ...] | T0 | history.first.timestamp |
| WS-03 | nil | [] | (early return) | Drawing skipped |

### 3.4 Background Color Selection

| Case ID | isLoggedIn | colorScheme | Expected bg | Notes |
|---------|------------|-------------|-------------|-------|
| BG-01 | true | dark | #121212 | Normal dark |
| BG-02 | true | light | #E8E8E8 | Normal light |
| BG-03 | false | dark | #3A1010 | Signed-out dark |
| BG-04 | false | light | #FFCCCC | Signed-out light |

### 3.5 Canvas Drawing Elements

| Case ID | Condition | Drawing Content | Notes |
|---------|-----------|-----------------|-------|
| DR-01 | Always | Background rectangle | bgColor or bgColorSignedOut |
| DR-02 | divisions > 1 | Vertical time division lines (tickColor, 0.5pt) | 1..<divisions lines |
| DR-03 | points is non-empty && points[0].x > 1 (1pt threshold) | Gray fill for no-data interval (noDataFill) | From window start to first data point. 1px or less gap is ignored to avoid sub-pixel artifacts |
| DR-04 | points is non-empty | Past area fill (areaColor, areaOpacity) | Step-style polyline → bottom edge → close path |
| DR-05 | fillEndX > effectiveNowX + 1 (pixel coordinates, 1pt or more difference) | Future area fill (areaOpacity * 0.35) + hatching pattern (areaOpacity * 0.5) | Predicted region until reset |
| DR-06 | points is non-empty | Usage horizontal dashed line (usageLineColor, 0.5pt, dash [2,2]) | Drawn at the Y coordinate of the latest data point |
| DR-07 | points is empty | (early return) | Nothing is drawn |

### 3.6 Area Fill — Step Drawing Shape

| Case ID | points | Drawing Path Shape | Notes |
|---------|--------|-------------------|-------|
| ST-01 | [(x0,y0)] | Rectangle: (x0,h)→(x0,y0)→(effectiveNowX,y0)→(effectiveNowX,h) | Single point |
| ST-02 | [(x0,y0),(x1,y1)] | Step: maintains y0 from x0 to x1, then changes to y1 at x1 | 2-point step |
| ST-03 | Multiple points | Step-style connection between each pair (horizontal → vertical) | N-point step |

### 3.7 fillEndX Determination Logic

| Case ID | resetsAt | now vs points.last | Expected fillEndX | Notes |
|---------|----------|--------------------|--------------------|-------|
| FE-01 | Date(R) | any | max(resetX, points.last.x) | Extended to reset time |
| FE-02 | nil | Date() > rawPoints.last.timestamp | nowX | Extended to current time |
| FE-03 | nil | Date() < rawPoints.last.timestamp | points.last.x | Data end is beyond current time |

### 3.8 yFrac Clamping

| Case ID | usage (%) | Expected yFrac | Notes |
|---------|-----------|----------------|-------|
| YF-01 | 0.0 | 0.0 | Bottom edge |
| YF-02 | 50.0 | 0.5 | Center |
| YF-03 | 100.0 | 1.0 | Top edge |
| YF-04 | 150.0 | 1.0 | Above 100% → clamped to 1.0 |

## 4. Side Effects

No side effects. MiniUsageGraph is a pure rendering view that does not modify external state, perform network communication, or access storage.

The only external reference is the `Date()` call (to get the current time, used within Canvas drawing).

## 5. Notes

- Canvas is SwiftUI's immediate-mode drawing. The entire view is redrawn on every update
- Graph height is fixed at 18pt. Width is specified externally via the `chartWidth` parameter
- Step drawing (horizontal → vertical, rather than line interpolation) reflects the nature of usage changing in discrete steps
- The hatching pattern on the future region visually indicates "predicted/unconfirmed" data (spacing: 4pt, lineWidth: 0.5pt)
- The `windowSeconds <= 5 * 3600 + 1` threshold marks the boundary between the 5-hour and 7-day windows
