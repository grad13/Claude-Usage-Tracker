---
Created: 2026-02-22
Updated: 2026-03-16
Checked: -
Deprecated: -
Format: spec-v2.1
Source: code/app/ClaudeUsageTrackerWidget/UsageWidget.swift, code/app/ClaudeUsageTrackerWidget/WidgetMediumView.swift, code/app/ClaudeUsageTrackerWidget/WidgetMiniGraph.swift, code/app/ClaudeUsageTrackerWidget/WidgetColorThemeResolver.swift, code/app/ClaudeUsageTrackerWidget/RefreshIntent.swift
---

# Widget Design Specification

## 0. Meta

| Source | Runtime |
|--------|---------|
| code/app/ClaudeUsageTrackerWidget/UsageWidget.swift | macOS |
| code/app/ClaudeUsageTrackerWidget/WidgetMediumView.swift | macOS |
| code/app/ClaudeUsageTrackerWidget/WidgetMiniGraph.swift | macOS |
| code/app/ClaudeUsageTrackerWidget/WidgetColorThemeResolver.swift | macOS |
| code/app/ClaudeUsageTrackerWidget/RefreshIntent.swift | macOS |

| Field | Value |
|-------|-------|
| Related | spec/meta/architecture.md |
| Test Type | - |

## Overview

A macOS WidgetKit Medium-size widget. Displays two usage rate graphs (5h and 7d) side by side, with a diagnostic footer row showing update time, next refresh countdown, and a manual refresh button.

Only `.systemMedium` is supported. Small and Large sizes were removed in v1.1.0 (no usage).

## Layout Structure

```
+---------------------------------------+
| [5h Graph]  [gap 8pt]  [7d Graph]     |
| [remaining]            [remaining]    |
|     update 15:30  Next 2m  ↻          |
+---------------------------------------+
```

Outer frame: `VStack(spacing: 0)`:
1. Graph area: `HStack(spacing: 8)` containing two usage sections
2. Footer row: diagnostic info + refresh button (18pt height)

Each usage section is a VStack (spacing: 3pt):
1. Graph (Canvas, fills available space via maxWidth/maxHeight)
2. Remaining time text (12pt-tall row, centered at the marker's x-coordinate)

## Graph (WidgetMiniGraph)

### Background

- Logged in: `#121212`
- Not logged in: `#3A1010` (dark red tint)

### Time Division Lines

- 5h graph: 5 divisions
- 7d graph: 7 divisions
- Color: `white.opacity(0.07)`, line width 0.5pt

### Area Fill

- Step interpolation (staircase) -- usage rate is constant between measurements
- Extends horizontally from the last data point to `min(current time, reset time)` (usage is monotonically non-decreasing until reset, so the last fetched value persists)
- If `resetsAt == nil`, extends to the current time
- 5h: Resolved from `settings.json` `hourly_color_preset` (default: blue = `rgba(100, 180, 255)`) opacity 0.7
- 7d: Resolved from `settings.json` `weekly_color_preset` (default: pink = `rgba(255, 130, 180)`) opacity 0.65
- Color resolution is handled by `WidgetColorThemeResolver.resolveChartColor(forKey:default:)`

### Usage Rate Line (Dashed)

- Drawn across the full graph width at the y-position of the current usage rate
- Color: `white.opacity(0.3)`
- Line width 0.5pt, dash `[2, 2]`

### Label (Top Left)

- Drawn inside the graph Canvas at position `(4, 4)` (top left)
- Font: system 9pt medium
- Color: `white.opacity(0.5)`
- Text: "5h" / "7d"

### Marker (Current Value Position)

Displayed at the x-coordinate of the current time and y-coordinate of the current usage rate.

- **Filled circle (inner)**: radius `2.5 * 2/3 ~ 1.67pt`, white
- **Outer ring**: radius `5pt`, `white.opacity(0.6)`, line width 1pt
- **Percent text**: font system 9pt semibold, `white.opacity(0.8)`
  - No decimals (e.g., "9%", "22%")
  - Vertical position:
    - Within 14pt from top, or in the bottom half: displayed 14pt below the marker
    - Otherwise (upper half and sufficiently far from top): displayed 10pt above the marker
  - Horizontal position: anchor prevents clipping
    - Within 16pt from left edge: anchor = leading (text extends to the right of the marker)
    - Within 16pt from right edge: anchor = trailing (text extends to the left of the marker)
    - Otherwise: anchor = center

## Remaining Time Text

- Placed in the row below the graph (12pt height)
- Horizontal position: centered at the marker's x-coordinate (`GeometryReader` + `position`)
- Font: `.caption2`
- Color: `.secondary`

### Format

| Condition | Display Example |
|-----------|----------------|
| 24h or more | `4d 21h` |
| 1h to less than 24h | `2h 35m` |
| Less than 1h | `19m` ("0h" omitted) |
| Expired | `expired` |

## Footer Row (Diagnostic UI)

A horizontal row below the graph area, providing data freshness visibility and manual refresh.

### Layout

```
update 15:30  Next 2m  ↻
```

- Frame height: 18pt
- `HStack(spacing: 6)`, centered

### Elements

| Element | Implementation | Description |
|---------|---------------|-------------|
| Update time | `Text("update")` + `Text(snapshot.timestamp, style: .time)` | Shows when data was last fetched (absolute time, e.g., "15:30") |
| Next refresh | `Text("Next")` + `Text(nextRefresh, style: .relative)` | Auto-countdown to next expected refresh |
| Refresh button | `Button(intent: RefreshIntent())` with `Image(systemName: "arrow.clockwise")` | Manual refresh, bypasses OS budget |

### Styling

- All text: `.font(.system(size: 9))`, `.foregroundStyle(.secondary)`
- Refresh button icon: `.font(.system(size: 10))`, `.foregroundStyle(.secondary)`, `.buttonStyle(.plain)`

### Next Refresh Calculation

```swift
let intervalMinutes = AppGroupConfig.settingsInt(forKey: "refresh_interval_minutes") ?? 5
let nextRefresh = snapshot.timestamp.addingTimeInterval(Double(intervalMinutes) * 60)
```

- Uses `refresh_interval_minutes` from `settings.json` (see `spec/data/settings.md`)
- Falls back to 5 minutes if the setting is absent or the App Group container is unavailable

### Visibility

- Footer is only shown when `snapshot` is non-nil (data has been fetched)
- When `snapshot` is nil, the `notFetchedView` is displayed instead (no footer)

## RefreshIntent (AppIntent)

`code/app/ClaudeUsageTrackerWidget/RefreshIntent.swift`

```swift
struct RefreshIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Usage"

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
```

- Conforms to `AppIntent` (requires `import AppIntents`)
- Triggers `reloadAllTimelines()` which causes the timeline provider to re-read the snapshot file
- User-initiated actions bypass the WidgetKit OS budget (40-70 refreshes/day limit does not apply)
- `openAppWhenRun` is not set (defaults to false) — the main app is not opened
- Used by `Button(intent: RefreshIntent())` in the footer row
- Coexists with `widgetURL`: `Button` tap area takes priority over `widgetURL`; tapping outside the button opens the Analysis screen

## Files

| File | Description |
|------|-------------|
| `ClaudeUsageTrackerWidget/WidgetMiniGraph.swift` | Canvas graph drawing (shared component, split into 10 private drawing methods) |
| `ClaudeUsageTrackerWidget/WidgetMediumView.swift` | Medium widget layout (5h + 7d side by side + footer row) |
| `ClaudeUsageTrackerWidget/RefreshIntent.swift` | AppIntent for manual widget refresh |
| `ClaudeUsageTrackerWidget/WidgetColorThemeResolver.swift` | Chart color preset resolution from settings.json |

## Design Change History

- **2026-02-22**: Added marker (filled circle + outer ring + percent text)
- **2026-02-22**: Moved label (5h/7d) from the row below the graph to inside the graph (top left)
- **2026-02-22**: Moved percent display from the label row to above the marker
- **2026-02-22**: Moved remaining time from left-aligned in the label row to marker x-position
- **2026-02-22**: Omitted "0h" in remaining time format ("0h 19m" -> "19m")
- **2026-02-22**: Percent text horizontal clipping prevention (anchor switching, 16pt margin)
- **2026-02-22**: Percent text top clipping prevention (if within 14pt topMargin, display below)
- **2026-02-25**: Area extension -- horizontal extension from the last data point to min(current time, reset time). Restricted no-data gray to post-reset only. Moved marker position to the extension endpoint
- **2026-03-15**: Removed Small and Large sizes (Medium only). Added diagnostic footer row (update time + next refresh countdown + manual refresh button via AppIntent)

## WidgetKit Structure (UsageWidget.swift)

### UsageEntry

```swift
struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
}
```

- Conforms to `TimelineEntry`
- `snapshot` is nullable (represents the not-yet-fetched state)
- A preview constant using `snapshot: .placeholder` exists on `UsageSnapshot`

### UsageTimelineProvider

```swift
struct UsageTimelineProvider: TimelineProvider {
    typealias Entry = UsageEntry
}
```

| Method | Behavior |
|--------|----------|
| `placeholder(in:)` | Returns `UsageEntry(date: Date(), snapshot: .placeholder)` |
| `getSnapshot(in:)` | Returns placeholder if `context.isPreview` is true. Otherwise calls `UsageReader.load()` (reads snapshot file from App Group container) and returns the result |
| `getTimeline(in:)` | `UsageReader.load()` (reads snapshot file from App Group container) -> creates entries. If snapshot has `resetsAt` dates, adds a future entry at the earliest reset time. `policy: .never` — updates are driven exclusively by `reloadTimelines()` from the main app or `RefreshIntent` |

**Update policy**: `.never` — the widget does not self-refresh on a timer. The main app calls `WidgetCenter.shared.reloadAllTimelines()` after each fetch, which triggers `getTimeline()`. The user can also trigger this via the ↻ button (`RefreshIntent`). A future entry at the earliest `resetsAt` ensures the widget also refreshes at the reset moment.

### UsageWidgetEntryView

```swift
struct UsageWidgetEntryView: View {
    var entry: UsageEntry

    var body: some View {
        WidgetMediumView(snapshot: entry.snapshot)
    }
}
```

Only Medium size is supported. No size branching.

### UsageWidget (WidgetConfiguration)

| Property | Value |
|----------|-------|
| `kind` | `"ClaudeUsageTrackerWidget"` |
| Configuration | `StaticConfiguration` (no user settings) |
| `widgetURL` | `URL(string: "claudeusagetracker://analysis")` -- tapping opens the app's Analysis screen |
| `containerBackground` | `.clear` |
| `configurationDisplayName` | `"Claude Usage"` |
| `description` | `"Monitor Claude Code usage limits"` |
| `supportedFamilies` | `[.systemMedium]` |

## WidgetColorThemeResolver

`code/app/ClaudeUsageTrackerWidget/WidgetColorThemeResolver.swift`

Resolves chart color presets from `settings.json` via App Group for the Widget target. Since `SwiftUI.Color` cannot be shared via the Shared framework (it's a View type), the RGB mapping is duplicated in the Widget target.

```swift
enum WidgetColorThemeResolver {
    static func resolveChartColor(forKey key: String, default fallback: Color) -> Color
}
```

- Reads the preset string from `AppGroupConfig.settingsString(forKey:)` (e.g., `"blue"`, `"pink"`)
- Looks up the preset in an internal `colorMap` dictionary mapping preset names to RGB tuples
- Returns the matching `Color`, or `fallback` if the preset is unknown or the key is absent

Supported presets: `blue`, `pink`, `green`, `teal`, `purple`, `orange`, `white` (same as `ChartColorPreset`).

## WidgetMediumView

`code/app/ClaudeUsageTrackerWidget/WidgetMediumView.swift`

### notFetchedView (When snapshot is nil)

```
[chart.bar.fill icon] .font(.title2)  .foregroundStyle(.secondary)
[Not fetched text]    .font(.caption) .foregroundStyle(.secondary)
```

VStack(spacing: 4), `frame(maxWidth: .infinity, maxHeight: .infinity)` to fill the container.

### DisplayHelpers Usage

Uses `DisplayHelpers.remainingText(until: resetsAt)` to generate the remaining time text.
This text is positioned at the marker's x-coordinate using `GeometryReader` with `position(x:y:)`.

### nowXFraction (Internal Helper)

```swift
private func nowXFraction(resetsAt: Date, windowSeconds: TimeInterval) -> CGFloat {
    let windowStart = resetsAt.addingTimeInterval(-windowSeconds)
    let nowElapsed = Date().timeIntervalSince(windowStart)
    return CGFloat(min(max(nowElapsed / windowSeconds, 0.0), 1.0))
}
```

Uses `resetsAt - windowSeconds` as the window start time and clamps the current time's relative position to 0.0-1.0.
Used to calculate the x-coordinate for the remaining time text (multiplied by `GeometryReader.size.width`).

## WidgetMiniGraph Type Interface and Drawing Details

`code/app/ClaudeUsageTrackerWidget/WidgetMiniGraph.swift`

### Type Interface

```swift
struct WidgetMiniGraph: View {
    let label: String            // Label displayed at the graph's top left (e.g., "5h", "7d")
    let history: [HistoryPoint]  // Usage rate time-series data
    let windowSeconds: TimeInterval  // Display window width (seconds)
    let resetsAt: Date?          // Window reset time (nil = unknown)
    let areaColor: Color         // Area fill color
    let areaOpacity: Double      // Area base opacity
    let isLoggedIn: Bool         // When false, background uses a reddish color
}
```

All drawing is done within `Canvas { context, size in ... }` (no SwiftUI subviews inside).

### Constants (private static)

| Constant | Value | Purpose |
|----------|-------|---------|
| `bgColor` | `#121212` | Logged-in background |
| `bgColorSignedOut` | `#3A1010` | Not-logged-in background (dark red tint) |
| `tickColor` | `white.opacity(0.07)` | Time division lines |
| `usageLineColor` | `white.opacity(0.3)` | Usage rate dashed line |
| `noDataFill` | `white.opacity(0.06)` | Light gray for no-data regions |

### resolveWindowStart Logic

```swift
private func resolveWindowStart() -> Date? {
    if let resetsAt {
        return resetsAt.addingTimeInterval(-windowSeconds)
    } else if let first = history.first {
        return first.timestamp
    }
    return nil
}
```

Priority:
1. `resetsAt` is non-nil -> use `resetsAt - windowSeconds` as the start time
2. `resetsAt` is nil but `history` is non-empty -> use the first data point's `timestamp` as the start time
3. Neither is available -> return `nil`, aborting graph drawing early

### drawTicks Logic

```swift
let divisions = windowSeconds <= 5 * 3600 + 1 ? 5 : 7
for i in 1..<divisions {
    let x = CGFloat(i) / CGFloat(divisions) * w
    // Draw vertical line
}
```

- `windowSeconds <= 18001` (5h + 1 second) -> 5 divisions (for 5h window)
- Otherwise -> 7 divisions (for 7d window)
- Boundary lines (i=0 and i=divisions) are not drawn (`1..<divisions`)

### buildPoints Logic

```swift
for dp in history {
    let elapsed = dp.timestamp.timeIntervalSince(windowStart)
    guard elapsed >= 0 else { continue }   // Exclude data before window start
    let xFrac = min(elapsed / windowSeconds, 1.0)
    let yFrac = min(dp.percent / 100.0, 1.0)
    points.append((x: CGFloat(xFrac) * w, y: h - CGFloat(yFrac) * h))
    lastPercent = dp.percent
}
```

- Data points with `elapsed < 0` are skipped (outside window)
- x-coordinate: `elapsed / windowSeconds` clamped to 0-1, scaled to width w
- y-coordinate: `percent / 100` clamped to 0-1, inverted from height h (top is 0%)
- Returns `nil` if `points` is empty, aborting drawing

### drawFutureStripes Logic

Draws hatched diagonal lines for the future region (from `effectiveNowX` to `fillEndX`).

```
Condition: fillEndX > effectiveNowX + 1
```

Drawing procedure:
1. Fill the future region rectangle (y: lastY to h) with `areaColor.opacity(areaOpacity * 0.35)`
2. Within a `drawLayer`, clip to that rectangle and draw diagonal lines:
   - Spacing: `spacing = 4pt`
   - Direction: bottom-left to top-right diagonals (45 degrees)
   - Width: `0.5pt`
   - Color: `areaColor.opacity(areaOpacity * 0.5)`
   - Loop: `offset` increments from `-totalSpan` to `+totalSpan` by `spacing`
   - `totalSpan = (fillEndX - effectiveNowX) + (h - lastY)` (full diagonal length)
   - Each line start: `(effectiveNowX + offset, lastY + (h - lastY))`
   - Each line end: `(effectiveNowX + offset + (h - lastY), lastY)`

### Drawing Phase Order

Drawing order within the Canvas (later draws appear on top):

1. `drawBackground` -- Background rectangle (full fill)
2. `drawLabel` -- Label text (top left)
3. `resolveWindowStart` -- Returns early on failure
4. `drawTicks` -- Time division vertical lines
5. `buildPoints` -- Data point calculation; returns early on failure
6. `drawNoDataRegion` -- No-data region (gray)
7. `drawPastArea` -- Past area (step-style fill)
8. `drawFutureStripes` -- Future area (diagonal hatching)
9. `drawUsageLine` -- Usage rate dashed horizontal line
10. `drawMarker` -- Current position marker (inner circle + outer ring)
11. `drawPercentText` -- Percent text
