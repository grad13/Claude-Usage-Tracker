---
updated: 2026-08-11
checked: -
Deprecated: -
Format: spec-v2.1
Source: code/app/ClaudeUsageTracker/AnalysisExporter.swift
---

# Specification: AnalysisExporter

## 0. Meta

| Source | Runtime |
|--------|---------|
| `code/app/ClaudeUsageTracker/AnalysisExporter.swift` | Swift (container) + JavaScript/HTML/CSS (core) |

| Field | Value |
|-------|-------|
| Related | `documents/spec/analysis/overview.md`, `code/app/ClaudeUsageTracker/AnalysisSchemeHandler.swift` |
| Test Type | Unit (JS function logic) + Integration (end-to-end data flow) |

### Runtime Definition

| Value | Meaning |
|-------|---------|
| Swift (container) | Only `enum AnalysisExporter { static var htmlTemplate: String }`. No logic on the Swift side |
| JavaScript | All logic resides in `<script>` within the HTML template. Fetches JSON data via `cut://` endpoints, renders with Chart.js |

### Notes on the Source Table

- Although it is a Swift file, the substance is JS/HTML/CSS. The Swift side merely loads the HTML string from the bundle via `static var htmlTemplate`
- `AnalysisSchemeHandler` serves JSON data to the WKWebView via the `cut://` scheme (see Related)

## 1. Contract

### Swift Side

```swift
enum AnalysisExporter {
    static var htmlTemplate: String  // computed property: loads analysis.html from bundle
}

private final class BundleAnchor {}  // defined inside AnalysisExporter
```

#### `BundleAnchor` Class

```swift
private final class BundleAnchor {}
```

- A private class defined inside the `AnalysisExporter` enum
- Purpose: serves as an anchor for `Bundle(for: BundleAnchor.self)` to locate the bundle this file belongs to
- Swift enums cannot be passed directly to `Bundle(for:)` (which requires `AnyClass`), so this dummy class is a common workaround
- In unit test environments, the XCTest bundle becomes the execution bundle, so when `BundleAnchor` is in a test target, `Bundle(for: BundleAnchor.self)` points to the test bundle

#### `htmlTemplate` Computed Property Implementation

```swift
static var htmlTemplate: String {
    guard let url = Bundle(for: BundleAnchor.self).url(forResource: "analysis", withExtension: "html"),
          let html = try? String(contentsOf: url, encoding: .utf8) else {
        return "<html><body>Failed to load analysis template</body></html>"
    }
    return html
}
```

- Uses `var` (computed property), not `let`
- Reads `analysis.html` from the bundle on every invocation (no caching)
- Bundle resource name: `"analysis"`, extension: `"html"`
- Fallback HTML on load failure: `"<html><body>Failed to load analysis template</body></html>"`

### JavaScript Side (Function Signatures)

```typescript
// --- Data Loading ---
async function fetchJSON(url: string): Promise<any[] | null>
async function loadData(fromEpoch?: number, toEpoch?: number): Promise<{ usageData: UsageRecord[] }>

// --- Data Processing ---
function insertResetPoints(data: UsageRecord[], percentKey: string, resetsAtKey: string): Point[]
function buildWeeklySessions(data: UsageRecord[]): Session[]
function buildHourlySessions(data: UsageRecord[]): Session[]
function findNearest(sortedData: Point[], targetX: number): Point | null

// --- Chart Rendering ---
function renderUsageTab(): void
function renderMain(usageData: UsageRecord[]): void
function destroyAllCharts(): void

// --- Session Navigation ---
function buildSessionSlots(sessions: {id, resets_at}[], windowSec: number): Slot[]
function buildCalendarSlots(oldest: number, latest: number, stepSec: number, labelFn: (Date) => string): Slot[]
function switchMode(mode: NavMode): void
function updateNavUI(): void
async function navigateTo(index: number): Promise<void>
function initNavigation(): void

// --- Helpers ---
function timeXScale(): object
function createStripePattern(ctx, color, lineWidth, spacing): CanvasPattern
function formatDateShort(d: Date): string
function formatDateFull(d: Date): string

// --- Types (implicit) ---
interface UsageRecord {
  timestamp: number        // epoch seconds (Int)
  hourly_percent: number | null
  weekly_percent: number | null
  hourly_resets_at: number | null   // epoch seconds
  weekly_resets_at: number | null   // epoch seconds
}
interface Point {
  x: number   // epoch ms (Date value)
  y: number   // percent
}
type NavMode = 'sessionWeekly' | 'sessionHourly' | 'calWeek' | 'calDay'
interface MetaJSON {
  latestSevenDayResetsAt?: number  // epoch seconds
  latestTimestamp?: number         // epoch seconds
  oldestTimestamp?: number         // epoch seconds
  weeklySessions?: {id: number, resets_at: number}[]
  hourlySessions?: {id: number, resets_at: number}[]
}
interface Slot {
  from: number  // epoch seconds
  to: number    // epoch seconds
  label: string
}
```

## 2. State (Mermaid)

```mermaid
stateDiagram-v2
    [*] --> Loading: Page load begins
    Loading --> FetchMeta: fetch cut://meta.json
    FetchMeta --> BuildSlots: Build slots for 4 nav modes
    BuildSlots --> NavigateToLatest: navigateTo(last slot)
    NavigateToLatest --> LoadData: loadData(from, to)
    LoadData --> DrawingCharts: renderMain(usageData)
    DrawingCharts --> Loaded: Charts rendered
    Loading --> Error: Any fetch/render throws

    state Loaded {
        [*] --> ViewingSession: Current session displayed
        ViewingSession --> ViewingSession: Nav prev/next
        ViewingSession --> ViewingSession: Toggle weekly/daily
    }
```

### Session Navigation (4 Modes)

- `_allSlots` object holds slots for all 4 modes: `sessionWeekly`, `sessionHourly`, `calWeek`, `calDay`
- `_navMode` tracks the active mode (default: `sessionWeekly`)
- `_navSlots` is the active mode's slot array, `_navIndex` points to the current slot
- Prev/Next buttons load data for adjacent slots via `navigateTo()`
- `switchMode(mode)` changes `_navSlots` to the selected mode's slots and navigates to the latest
- Session modes use `buildSessionSlots()` (from resets_at timestamps), calendrical modes use `buildCalendarSlots()` (fixed-width time windows)

## 3. Logic (Decision Table)

### 3.1 insertResetPoints(data, percentKey, resetsAtKey)

When a resets_at timestamp falls between prev and curr, inserts a usage-rate-0 point to visualize the reset.

| Case ID | data | percentKey | Expected | Notes |
|---------|------|-----------|----------|-------|
| RP-01 | `[{t:10:00, hourly%:30, resets:10:30}, {t:11:00, hourly%:15}]` | `hourly_percent` | `[{x:10:00, y:30}, {x:10:30, y:0}, {x:11:00, y:15}]` | resets_at between prev.t and curr.t -> zero point inserted |
| RP-02 | `[{t:10:00, hourly%:30, resets:09:00}, {t:11:00, hourly%:15}]` | `hourly_percent` | `[{x:10:00, y:30}, {x:11:00, y:15}]` | resets_at < prev.t -> no insertion |
| RP-03 | `[{t:10:00, hourly%:30, resets:12:00}, {t:11:00, hourly%:15}]` | `hourly_percent` | `[{x:10:00, y:30}, {x:11:00, y:15}]` | resets_at > curr.t -> no insertion |
| RP-04 | `[{t:10:00, hourly%:30, resets:null}, {t:11:00, hourly%:15}]` | `hourly_percent` | `[{x:10:00, y:30}, {x:11:00, y:15}]` | resets_at is null -> no insertion |
| RP-05 | `[{t:10:00, hourly%:null}, {t:11:00, hourly%:15}]` | `hourly_percent` | `[{x:11:00, y:15}]` | percent is null -> row itself is skipped |
| RP-06 | `[{t:10:00, hourly%:30, resets:10:30}, {t:11:00, hourly%:null}, {t:12:00, hourly%:20, resets:null}]` | `hourly_percent` | `[{x:10:00, y:30}, {x:10:30, y:0}, {x:12:00, y:20}]` | null in between; lastValidIdx tracks prev |
| RP-07 | `[]` | `hourly_percent` | `[]` | Empty array |
| RP-08 | `[{t:10:00, hourly%:50}]` | `hourly_percent` | `[{x:10:00, y:50}]` | Single record -> no reset evaluation |

**Note**: The comparison target for resets_at is `prev` (the most recent valid record), not curr. The condition is `resetTime > prevTime && resetTime < currTime` (strict open interval).

### 3.2 buildHourlyTimelineData(data, gapMs)

Builds the single Hourly fill and crosshair sequence from valid chronological samples. The default `gapMs` is 30 minutes (`1,800,000ms`). Exact reset/session identity is deliberately ignored for fill continuity; it remains authoritative elsewhere for metadata, navigation, reset display, and bands.

| Case ID | Input | Expected | Notes |
|---------|-------|----------|-------|
| HT-01 | Valid points every minute with alternating `hourly_resets_at` values | 1 segment, 0 separators | Reset identity changes are not visual gaps |
| HT-02 | Two contiguous runs separated by more than `gapMs` | 2 segments, exactly 1 `{x: midpoint, y: null}` separator | `spanGaps: false` leaves the true gap empty |
| HT-03 | Adjacent timestamps differ by exactly `gapMs` | 1 segment, 0 separators | Separation condition is strict `>` |
| HT-04 | Unordered input with invalid timestamp/percent rows | Valid points only, ordered by timestamp | Each Chart.js data item has a finite `x`; literal `null` items are forbidden |

### 3.3 renderMain(usageData) -- Usage Dataset Construction

| Case ID | usageData | Expected | Notes |
|---------|-----------|----------|-------|
| MN-01 | 100 records | Renders usage chart | Normal |
| MN-02 | 0 records | Empty chart | No data |
| MN-03 | Hourly samples containing reset-identity changes and a true time gap | Exactly one hourly dataset with `fill: true`, `spanGaps: false`, and `stepped: 'before'`; reset changes add no separator; the true `> gapMs` interval adds exactly one parser-safe `{x: finite midpoint, y: null}` skipped point; no dataset item is a literal `null` | Prevents independent origin-closing triangles and prevents a line/fill bridge only across actual missing time |

`renderUsageTab()` uses `buildHourlyTimelineData()` for both the one logical Hourly dataset and crosshair samples (with separator points excluded from lookup). Chart.js object-data parsing requires every array item to expose `x` and `y`; therefore a literal `null` must never be used as a dataset item. `buildHourlySessions()` remains available only for session bands/reset metadata behavior and cannot influence fill continuity. Weekly sessions remain separate datasets.

## 4. Side Effects (Integration)

| Type | Description |
|------|-------------|
| Network (CDN) | `https://cdn.jsdelivr.net/npm/chart.js@4` -- Chart.js library |
| Network (CDN) | `https://cdn.jsdelivr.net/npm/chartjs-adapter-date-fns@3` -- Date adapter |
| Store (fetch) | `cut://usage.json` -- SELECT from usage_log table (AnalysisSchemeHandler serves as JSON) |
| Store (fetch) | `cut://meta.json` -- Aggregate query results from usage_log + weekly_sessions served as JSON |
| DOM | `#loading` -- text update + display:none |
| DOM | `#app` -- display:'' to show |
| DOM | `<canvas>` -- Chart.js instances render usage chart (usageTimeline) |
| DOM | Session nav buttons -- prev/next + 4 mode buttons (Session Weekly/Hourly, Cal Week/Day) |
| Global State | `_usageData` -- set in renderMain() |
| Global State | `_meta` -- meta.json response |
| Global State | `_allSlots`, `_navMode`, `_navSlots`, `_navIndex` -- session navigation state |
| Global State | `_charts` -- Chart.js instance cache (for destroy) |

## 5. Notes

- **CDN dependency**: Chart.js does not work offline (dynamically loaded from CDN)
- **fetchJSON error handling**: Returns `null` on fetch failure; the corresponding data array becomes empty. Errors are only logged via console.warn
- **Hourly fill gaps**: Chronological Hourly samples use one filled dataset. Only elapsed time above the 30-minute default adds a parser-safe `{x, y: null}` skipped point; `spanGaps: false` keeps that true gap empty without creating per-session triangles. Reset/session identity changes alone remain continuous.
- **Data serving architecture**: `AnalysisExporter.htmlTemplate` loads `analysis.html` from the bundle, and `AnalysisSchemeHandler` serves JSON endpoints via the `cut://` scheme
- **Session navigation**: Entry point fetches `meta.json` to get timestamp range and session lists, builds slots for all 4 modes (sessionWeekly, sessionHourly, calWeek, calDay), then navigates to the latest slot in the default mode (sessionWeekly)
