---
Created: 2026-02-22
Updated: 2026-03-06
Checked: -
Deprecated: -
Format: spec-v2.1
Source: code/ClaudeUsageTrackerWidget/UsageWidget.swift, code/ClaudeUsageTrackerWidget/WidgetSmallView.swift, code/ClaudeUsageTrackerWidget/WidgetMediumView.swift, code/ClaudeUsageTrackerWidget/WidgetLargeView.swift, code/ClaudeUsageTrackerWidget/WidgetMiniGraph.swift
---

# Widget Design Specification

## 0. Meta

| Source | Runtime |
|--------|---------|
| code/ClaudeUsageTrackerWidget/UsageWidget.swift | macOS |
| code/ClaudeUsageTrackerWidget/WidgetSmallView.swift | macOS |
| code/ClaudeUsageTrackerWidget/WidgetMediumView.swift | macOS |
| code/ClaudeUsageTrackerWidget/WidgetLargeView.swift | macOS |
| code/ClaudeUsageTrackerWidget/WidgetMiniGraph.swift | macOS |

| Field | Value |
|-------|-------|
| Related | spec/meta/architecture.md |
| Test Type | - |

## Overview

A macOS WidgetKit Medium-size widget. Displays two usage rate graphs (5h and 7d) side by side.

## Layout Structure

```
+---------------------------------------+
| [5h Graph]  [gap 8pt]  [7d Graph]     |
| [remaining]            [remaining]    |
+---------------------------------------+
```

Each section is a VStack (spacing: 3pt):
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
- 5h: `rgba(100, 180, 255)` opacity 0.7
- 7d: `rgba(255, 130, 180)` opacity 0.65

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

## Files

| File | Description |
|------|-------------|
| `ClaudeUsageTrackerWidget/WidgetMiniGraph.swift` | Canvas graph drawing (shared component, split into 10 private drawing methods) |
| `ClaudeUsageTrackerWidget/WidgetMediumView.swift` | Medium widget layout (5h + 7d side by side) |
| `ClaudeUsageTrackerWidget/WidgetLargeView.swift` | Large widget (uses the same WidgetMiniGraph) |
| `tmp/marker_prototype.html` | Design prototype (Canvas/JS) |

## Design Change History

- **2026-02-22**: Added marker (filled circle + outer ring + percent text)
- **2026-02-22**: Moved label (5h/7d) from the row below the graph to inside the graph (top left)
- **2026-02-22**: Moved percent display from the label row to above the marker
- **2026-02-22**: Moved remaining time from left-aligned in the label row to marker x-position
- **2026-02-22**: Omitted "0h" in remaining time format ("0h 19m" -> "19m")
- **2026-02-22**: Percent text horizontal clipping prevention (anchor switching, 16pt margin)
- **2026-02-22**: Percent text top clipping prevention (if within 14pt topMargin, display below)
- **2026-02-25**: Area extension -- horizontal extension from the last data point to min(current time, reset time). Restricted no-data gray to post-reset only. Moved marker position to the extension endpoint

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
| `getSnapshot(in:)` | Returns placeholder if `context.isPreview` is true. Otherwise calls `SnapshotStore.load()` and returns the result |
| `getTimeline(in:)` | `SnapshotStore.load()` -> creates a single-entry Timeline. `policy: .after(Date() + 5 min)` requests refresh after 5 minutes |

**Update policy**: Every 5 minutes (`5 * 60` seconds). Expressed as `Timeline(entries: [entry], policy: .after(nextUpdate))`.

### UsageWidgetEntryView (Size Branching)

```swift
@Environment(\.widgetFamily) private var family

switch family {
case .systemSmall:  WidgetSmallView(snapshot: entry.snapshot)
case .systemMedium: WidgetMediumView(snapshot: entry.snapshot)
case .systemLarge:  WidgetLargeView(snapshot: entry.snapshot)
default:            WidgetSmallView(snapshot: entry.snapshot)
}
```

Fallback for unsupported sizes (`.systemExtraLarge`, etc.) is Small.

### UsageWidget (WidgetConfiguration)

| Property | Value |
|----------|-------|
| `kind` | `"ClaudeUsageTrackerWidget"` |
| Configuration | `StaticConfiguration` (no user settings) |
| `widgetURL` | `URL(string: "claudeusagetracker://analysis")` -- tapping opens the app's Analysis screen |
| `containerBackground` | `.clear` |
| `configurationDisplayName` | `"Claude Usage"` |
| `description` | `"Monitor Claude Code usage limits"` |
| `supportedFamilies` | `[.systemSmall, .systemMedium, .systemLarge]` |

## WidgetSmallView

`code/ClaudeUsageTrackerWidget/WidgetSmallView.swift`

### Layout

```
+-----------+
| [5h Graph]|
| [7d Graph]|
+-----------+
```

- Outer frame: `VStack(spacing: 4)`
- Each graph is a `WidgetMiniGraph` with `frame(maxWidth: .infinity, maxHeight: .infinity)`
- `clipShape(RoundedRectangle(cornerRadius: 4))`
- No `resetsAt` text row (unlike Medium)

### usageSection Argument Mapping

| Argument | 5h Value | 7d Value |
|----------|----------|----------|
| `label` | `"5h"` | `"7d"` |
| `percent` | `snapshot.fiveHourPercent` | `snapshot.sevenDayPercent` |
| `resetsAt` | `snapshot.fiveHourResetsAt` | `snapshot.sevenDayResetsAt` |
| `history` | `snapshot.fiveHourHistory` | `snapshot.sevenDayHistory` |
| `windowSeconds` | `5 * 3600` | `7 * 24 * 3600` |
| `color` | `Color(100/255, 180/255, 255/255)` | `Color(255/255, 130/255, 180/255)` |
| `opacity` | `0.7` | `0.65` |

### notFetchedView (When snapshot is nil)

```
[chart.bar.fill icon] .font(.title2)  .foregroundStyle(.secondary)
[Not fetched text]    .font(.caption) .foregroundStyle(.secondary)
```

VStack(spacing: 4)

## WidgetMediumView

`code/ClaudeUsageTrackerWidget/WidgetMediumView.swift`

### notFetchedView (When snapshot is nil)

```
[chart.bar.fill icon] .font(.title2)  .foregroundStyle(.secondary)
[Not fetched text]    .font(.caption) .foregroundStyle(.secondary)
```

VStack(spacing: 4), `frame(maxWidth: .infinity, maxHeight: .infinity)` to fill the container.

Same design as Small's `notFetchedView` (differs from Large in text and font).

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

## WidgetLargeView

`code/ClaudeUsageTrackerWidget/WidgetLargeView.swift`

### Layout

```
+------------------------------------------+
| Claude Usage            .font(.headline)  |
|                                           |
| 5-hour Usage            .font(.subheadline)|
| [5h MiniGraph  height:48]                 |
| [xx.x%]  [resets in Xh Ym]  [Est. $x.xx] |
|                                           |
| 7-day Usage             .font(.subheadline)|
| [7d MiniGraph  height:48]                 |
| [xx.x%]  [resets in Xd Yh]  [Est. $x.xx] |
|                                           |
| Spacer                                    |
+------------------------------------------+
```

- Outer frame: `VStack(alignment: .leading, spacing: 10)` + `.padding(.vertical, 4)`
- Header: `Text("Claude Usage")` `.font(.headline)`
- Each block: `usageBlock` method

### usageBlock Structure

`VStack(alignment: .leading, spacing: 4)`:

1. Title row: `Text(title)` `.font(.subheadline)` `.foregroundStyle(.secondary)`
2. Graph: `WidgetMiniGraph` `.frame(height: 48)` `.frame(maxWidth: .infinity)` `clipShape(RoundedRectangle(cornerRadius: 4))`
3. Metrics row: `HStack(spacing: 8)`:
   - Percent (when `percent != nil`): `"%.1f%%"` format, `.system(.body, design: .rounded, weight: .semibold)` `.monospacedDigit()`
   - Reset time (when `resetsAt != nil`): `"resets \(remainingText)"` `.font(.caption)` `.foregroundStyle(.secondary)`
   - `Spacer()`
   - Estimated cost (when `predictCost != nil`): `"Est. $%.2f"` `.font(.caption)` `.foregroundStyle(.secondary)`

### usageBlock Argument Mapping

| Argument | 5h Value | 7d Value |
|----------|----------|----------|
| `title` | `"5-hour Usage"` | `"7-day Usage"` |
| `percent` | `snapshot.fiveHourPercent` | `snapshot.sevenDayPercent` |
| `resetsAt` | `snapshot.fiveHourResetsAt` | `snapshot.sevenDayResetsAt` |
| `history` | `snapshot.fiveHourHistory` | `snapshot.sevenDayHistory` |
| `windowSeconds` | `5 * 3600` | `7 * 24 * 3600` |
| `color` | `Color(100/255, 180/255, 255/255)` | `Color(255/255, 130/255, 180/255)` |
| `opacity` | `0.7` | `0.65` |
| `predictCost` | `snapshot.predictFiveHourCost` | `snapshot.predictSevenDayCost` |

The MiniGraph `label` argument receives `title` (the full title string) directly (unlike the abbreviated labels in Small/Medium). However, since it is displayed at 9pt in the graph's top left, there is no visual issue.

### remainingText (Internal Helper)

```swift
private func remainingText(_ date: Date) -> String {
    let text = DisplayHelpers.remainingText(until: date)
    return text == "expired" ? text : "in " + text
}
```

If the result of `DisplayHelpers.remainingText(until:)` is `"expired"`, returns it as-is.
Otherwise, prepends `"in "` to produce strings like `"resets in 2h 35m"`.

### notFetchedView (When snapshot is nil)

Large-specific design (different text and font from Small/Medium):

```
[chart.bar.fill]          .font(.largeTitle)
[Not fetched yet]         .font(.body)
[Open ClaudeUsageTracker  .font(.caption)
 to sign in]              .foregroundStyle(.tertiary)
```

VStack(spacing: 8), `frame(maxWidth: .infinity, maxHeight: .infinity)` to fill the container.

## WidgetMiniGraph Type Interface and Drawing Details

`code/ClaudeUsageTrackerWidget/WidgetMiniGraph.swift`

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

## Size Comparison Table

| Aspect | Small | Medium | Large |
|--------|-------|--------|-------|
| Outer frame | VStack spacing:4 | HStack spacing:8 | VStack spacing:10 |
| Graph arrangement | 2 stacked vertically | 2 side by side | 2 stacked vertically (with titles) |
| Graph height | maxHeight (.infinity) | maxHeight (.infinity) | Fixed 48pt |
| Label text | `"5h"` / `"7d"` | `"5h"` / `"7d"` | `"5-hour Usage"` / `"7-day Usage"` |
| resetsAt text | None | Present (at marker x-position) | Present ("resets in Xh") |
| Percent display | None (graph marker only) | None (graph marker only) | Present ("%.1f%%", rounded semibold) |
| Estimated cost | None | None | Present (`predictFiveHourCost` / `predictSevenDayCost`) |
| notFetchedView icon | `.title2` | `.title2` | `.largeTitle` |
| notFetchedView text | "Not fetched" caption | "Not fetched" caption | "Not fetched yet" body + description caption |
