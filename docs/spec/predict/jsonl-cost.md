---
Created: 2026-02-21
Updated: 2026-03-06
Checked: -
Deprecated: -
Format: spec-v2.1
Source: code/ClaudeUsageTracker/JSONLParser.swift, code/ClaudeUsageTracker/CostEstimator.swift
---

# Phase 2: JSONL Estimation (Predict) Specification

## 0. Meta

| Source | Runtime |
|--------|---------|
| code/ClaudeUsageTracker/JSONLParser.swift | macOS |
| code/ClaudeUsageTracker/CostEstimator.swift | macOS |

| Field | Value |
|-------|-------|
| Related | spec/meta/architecture.md |
| Test Type | Unit |

## Overview

Parses JSONL session logs from `~/.claude/projects/` and estimates token costs.
In Phase 3, this serves as the foundation for comparing with Phase 1 (Actual: server-side quota %) and analyzing dynamic rate limit patterns.

## Data Source

### File Structure

```
~/.claude/projects/{project-path}/{session-id}.jsonl
```

- Multiple JSONL files exist in each project directory
- Each file corresponds to one session
- Each line is a single JSON object

### Record Types

| type | Content | Phase 2 Usage |
|------|---------|---------------|
| `assistant` | AI response (contains usage field) | **Target** |
| `user` | User input | Not used |
| `system` | System event | Not used |
| `progress` | Progress event | Not used |
| `file-history-snapshot` | File change history | Not used |

### Target Record Criteria

Only records satisfying all of the following conditions are processed:

1. `type == "assistant"`
2. `message.usage` exists (not null)
3. `requestId` exists

### Extracted Fields

Verified against real data (Claude Code v2.1.42):

| Field | JSON Path | Type | Example |
|-------|----------|------|---------|
| Timestamp | `timestamp` | string (ISO 8601) | `"2026-02-16T19:48:50.408Z"` |
| Request ID | `requestId` | string | `"req_011CYCKvBKJfiwANdQWijE15"` |
| Model | `message.model` | string | `"claude-opus-4-6"` |
| Speed | `message.usage.speed` | string | `"standard"` |
| Input tokens | `message.usage.input_tokens` | int | `3` |
| Output tokens | `message.usage.output_tokens` | int | `238` |
| Cache read | `message.usage.cache_read_input_tokens` | int | `17890` |
| Cache write | `message.usage.cache_creation_input_tokens` | int | `2969` |
| Web search count | `message.usage.server_tool_use.web_search_requests` | int | `0` |

### Deduplication

JSONL includes intermediate streaming records (approximately 56% of all records are duplicates).

**Two-layer deduplication**:
1. **TokenStore (primary path)**: Uses `request_id` as SQLite PRIMARY KEY with `ON CONFLICT` to keep the record with the larger `output_tokens` (UPSERT). Handled by the caller after `parseFile`.
2. **parseDirectory (direct path)**: Applies `deduplicate()` after calling `parseFile`. Groups by `requestId` and keeps the record with the maximum `output_tokens`.

## Cost Calculation

### Per-Model Pricing (Public Prices as of February 2026)

| Model ID | input | output | cache_write | cache_read |
|----------|-------|--------|-------------|------------|
| `claude-opus-4-6` | $15.00/1M | $75.00/1M | $18.75/1M | $1.50/1M |
| `claude-sonnet-4-6` | $3.00/1M | $15.00/1M | $3.75/1M | $0.30/1M |
| `claude-haiku-4-5-*` | $0.80/1M | $4.00/1M | $1.00/1M | $0.08/1M |

### Formula

```
Record cost =
  (input_tokens x input price)
+ (output_tokens x output price)
+ (cache_creation_input_tokens x cache_write price)
+ (cache_read_input_tokens x cache_read price)
```

Unit: all values are token count / 1,000,000 x price (USD)

### Model ID Matching

Model IDs are matched using `String.contains()` for substring matching. Evaluation order (first match wins):
1. Contains `claude-opus-4` -> Opus pricing
2. Contains `claude-haiku` -> Haiku pricing
3. Everything else (`claude-sonnet-4`, etc.) -> Sonnet pricing (default)

### Speed Adjustment

The `speed` field is recorded in `TokenRecord` but is not used in cost calculations (intentional omission).

Background: There is information suggesting fast mode costs approximately 5x more, but Claude Code's public pricing does not explicitly differentiate between fast/standard prices -- only per-model prices are published. Therefore, no speed-based adjustment is applied at this time. This will be reconsidered in Phase 3 if the accuracy gap versus Actual is significant.

## Window Aggregation

### 5-Hour Window

- Sum of costs for all records within the last 5 hours from the current time
- Filtered by `timestamp >= (now - 5 hours)`

### 7-Day Window

- Sum of costs for all records within the last 7 days from the current time
- Filtered by `timestamp >= (now - 7 days)`

### Cross-Project Aggregation

Window aggregation spans **all projects** under `~/.claude/projects/`.
This is because quotas are per-account, not per-project.

## Output Data

```swift
struct CostSummary {
    let totalCost: Double          // USD
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
```

## Known Limitations

1. **Quota formula is not public** -- The conversion formula between estimated cost (USD) and server-side quota (%) is unknown. An approximation model will be built in Phase 3 by comparing with Actual
2. **Cache read weighting is uncertain** -- The public price of 0.1x is used, but the weight in quota calculation may differ (up to 10x error possible)
3. **Multi-device usage is not included** -- Local JSONL only records usage from the current machine
4. **Dynamic rate limiting** -- Server load may cause the same cost to consume different amounts of quota (hypothesis stage)
5. **costUSD field is deprecated** -- Since Claude Code v1.0.9, JSONL no longer includes costUSD. Cost is calculated from token counts and public prices

## Phase 2 Scope

### Included

- JSONL parsing and deduplication
- Per-model cost calculation
- 5-hour / 7-day window aggregation
- Unit tests

### Excluded (Phase 3 and beyond)

- UI integration (menu bar display, UsageViewModel integration)
- Comparison with Actual (Phase 1) and recording
- Dynamic rate limit analysis
- Correction coefficient calculation

## fetchPredict Orchestration

`UsageViewModel.fetchPredict()` is the entry point that drives the entire JSONL cost estimation pipeline.

### Invocation Timing

| Timing | Location | Description |
|--------|----------|-------------|
| Initialization | `UsageViewModel.init` | Runs once after app launch, following `reloadHistory()` |
| After successful Actual fetch | Inside `UsageViewModel` fetch completion | Immediately after `snapshotWriter.saveAfterFetch()` + `widgetReloader.reloadAllTimelines()` |

### Execution Model

Runs via `Task.detached`. Detaches from the `@MainActor` context of `UsageViewModel` to perform JSONL sync, parsing, and cost calculation in the background. UI updates explicitly return to the main actor via `await MainActor.run {}`.

```
fetchPredict() {
    let ts = self.tokenSync        // Captured on MainActor
    Task.detached { [weak self] in
        // 1. Get directories (nonisolated static)
        // 2. TokenSync: JSONL -> SQLite sync
        // 3. Load records from SQLite (with cutoff)
        // 4. CostEstimator for 5h/7d estimation
        // 5. MainActor.run to apply results
    }
}
```

### Cutoff: 8 Days

The `loadRecords(since:)` cutoff is **8 days before the current time** (`-8 * 24 * 3600` seconds). This provides a 1-day margin beyond the 7-day window (168 hours), ensuring records near the 7-day window boundary are reliably included.

### Nil Conditions

`predictFiveHourCost` / `predictSevenDayCost` become `nil` under the following conditions:

| Condition | Reason |
|-----------|--------|
| `claudeProjectsDirectories()` returns an empty array | `~/.claude/projects` directory does not exist |
| `CostEstimator.estimate()` returns `totalCost` of 0 or less | No matching records in the window |
| Sign-out | Explicitly set to `nil` in `UsageViewModel+Session` |

## predictFiveHourCost / predictSevenDayCost Properties

```swift
@Published var predictFiveHourCost: Double?   // USD, estimated cost for 5-hour window
@Published var predictSevenDayCost: Double?   // USD, estimated cost for 7-day window
```

- Type: `Double?` (nil = no data or unable to calculate)
- Unit: USD
- Usage: UI display (menu bar / menu dropdown) and widget data sharing
- Only holds a value when `CostEstimator.estimate()` returns a `CostSummary.totalCost` greater than 0

## snapshotWriter / widgetReloader Integration

fetchPredict results are propagated to the widget via two paths:

1. **`snapshotWriter.updatePredict(fiveHourCost:sevenDayCost:)`**
   - Writes only the Predict values to `SnapshotStore` (does not modify Actual values)
   - The widget reads the latest data from `SnapshotStore`
   - Called even with empty directories (nil, nil) to clear previous values

2. **`widgetReloader.reloadAllTimelines()`**
   - Calls `WidgetCenter.shared.reloadAllTimelines()` to request timeline updates for all widgets
   - Called after snapshotWriter completes its write (ensures the widget can read the latest values)

Both are executed within the `MainActor.run {}` block.

## TokenSyncing Protocol and TokenStore

### TokenSyncing Protocol

```swift
protocol TokenSyncing: Sendable {
    func sync(directories: [URL])
    func loadRecords(since cutoff: Date) -> [TokenRecord]
}
```

- `Sendable` conformance: Required for safe use within `Task.detached`
- `UsageViewModel` holds `tokenSync: any TokenSyncing` (default: `TokenStore.shared`)
- Can be replaced with a mock for testing

### TokenStore

A store that persists JSONL parse results to SQLite and performs incremental sync.

| Field | Value |
|-------|-------|
| DB Path | `Library/Application Support/ClaudeUsageTracker/tokens.db` inside App Group container |
| Testing | `NSTemporaryDirectory()/ClaudeUsageTracker-test-shared/tokens.db` |
| Singleton | `TokenStore.shared` (`static let`) |
| Tables | `jsonl_files` (synced file tracking), `token_records` (token records) |
| Sync Strategy | Detects changes via file `contentModificationDate`; only re-parses modified files |
| Deduplication | `request_id` as PRIMARY KEY with `ON CONFLICT` keeping the larger `output_tokens` (UPSERT) |
| Transaction | All file processing wrapped in a single transaction |

**sync(directories:) flow:**

1. Fetch processed files `(path, mod_date)` from the `jsonl_files` table
2. Recursively scan specified directories for `.jsonl` files
3. Skip files whose `mod_date` has not changed (change detection; differences within 1 second are treated as identical)
4. Parse changed files with `JSONLParser.parseFile()` and UPSERT records
5. Record files as processed in `jsonl_files`

**loadRecords(since:) behavior:**

- Returns `token_records` filtered by `timestamp >= cutoff`, ordered by `timestamp ASC`
- Opens DB as read-only (`SQLITE_OPEN_READONLY`)

## claudeProjectsDirectories

```swift
nonisolated static func claudeProjectsDirectories() -> [URL]
```

- `nonisolated static`: Avoids actor isolation when called from `Task.detached` within the `@MainActor` `UsageViewModel`
- Return value: `[URL]` (0 or 1 elements)
- Path: `~/.claude/projects` (constructed from `FileManager.default.homeDirectoryForCurrentUser`)
- Returns an empty array `[]` if the directory does not exist

## Error and Empty Directory Behavior

| Situation | Behavior |
|-----------|----------|
| `~/.claude/projects` does not exist | Sets `predictFiveHourCost = nil`, `predictSevenDayCost = nil`, writes nil to snapshotWriter, reloads widget. Returns early |
| `~/.claude/projects` exists but contains no JSONL files | `TokenStore.sync()` processes 0 files and skips. `loadRecords()` returns an empty array, `CostEstimator` yields `totalCost = 0` -> nil |
| JSONL parse error (individual file) | `JSONLParser.parseFile()` skips erroneous lines. Only parseable lines are processed |
| SQLite open failure | `TokenStore.sync()` logs via NSLog and returns early. `loadRecords()` returns an empty array -> nil |
| `self` deallocated (`weak self` is nil) | All operations inside `MainActor.run` are skipped (optional chaining via `self?.`) |

## JSONLParser: Public API Details

### parseLines(_:) Method

```swift
static func parseLines(_ lines: [String]) -> [TokenRecord]
```

- **Visibility**: `static` (no `public` modifier; module-internal)
- **Purpose**: For testing and in-memory processing. Parses an array of strings directly without going through files
- **Deduplication**: Applies `deduplicate()` to the result, same as `parseDirectory`
- **Argument**: `[String]` -- each element corresponds to one JSONL line. Empty lines are naturally skipped as `parseLine()` returns nil for them

### parseFile(_:) Visibility

```swift
static func parseFile(_ url: URL) -> [TokenRecord]
```

- **Visibility**: `static` (not `private`)
- **Deduplication**: `parseFile` alone does not perform deduplication. `parseDirectory` applies `deduplicate()` after calling `parseFile`. When using `parseFile` return values directly (e.g., the TokenStore use case), the caller is responsible for deduplication as needed

### Two-Stage Timestamp Parsing Fallback

The "Extracted Fields" section above states ISO 8601 format. The parsing implementation details are as follows.

**Two-stage parsing strategy:**

```swift
private static func parseTimestamp(_ string: String?) -> Date? {
    guard let string else { return nil }
    return dateFormatter.date(from: string) ?? dateFormatterNoFraction.date(from: string)
}
```

| Step | Formatter | formatOptions | Example |
|------|-----------|---------------|---------|
| 1st try | `dateFormatter` | `.withInternetDateTime` + `.withFractionalSeconds` | `"2026-02-16T19:48:50.408Z"` |
| 2nd try (fallback) | `dateFormatterNoFraction` | `.withInternetDateTime` | `"2026-02-16T19:48:50Z"` |

- The fallback handles older formats or certain client timestamps that lack fractional seconds
- On parse failure (nil), the entire record line is discarded (`parseLine` returns nil)

## CostEstimator: Public API Details

### estimateAll(records:) Method

```swift
static func estimateAll(records: [TokenRecord]) -> CostSummary
```

- **Visibility**: `static` (module-internal)
- **Purpose**: Aggregates all provided records without time-window filtering
- Difference from `estimate(records:windowHours:now:)`: Skips cutoff calculation and filtering, calling `summarize()` directly
- Primary use: Testing and total cost display

### cost(for:) Public API

```swift
static func cost(for record: TokenRecord) -> Double
```

- **Visibility**: `static` (not `private`)
- **Return value**: Double in USD. Returns the cost for a single record only (no aggregation)
- **Purpose**: Called internally from `summarize()` and also usable directly for inspecting individual record costs
- **Formula**: As described in the "Cost Calculation" section (sum of 4 token types x respective prices / 1,000,000)

### pricingForModel(_:) Visibility

```swift
static func pricingForModel(_ model: String) -> ModelPricing
```

- **Visibility**: `static` (not `private`)
- Used internally via `summarize()` -> `cost(for:)`, but also callable externally to retrieve pricing for a given model ID
- Matching uses `String.contains()` for substring matching. Priority: opus -> haiku -> sonnet (default)

### ModelPricing Struct Contract

```swift
struct ModelPricing {
    let input: Double       // USD / 1M tokens
    let output: Double      // USD / 1M tokens
    let cacheWrite: Double  // USD / 1M tokens (corresponds to cache_creation_input_tokens)
    let cacheRead: Double   // USD / 1M tokens (corresponds to cache_read_input_tokens)
}
```

- All fields are immutable (`let`)
- Unit is USD / 1,000,000 tokens (divided by `1_000_000.0` during calculation)
- Predefined constants: `CostEstimator.opus`, `CostEstimator.sonnet`, `CostEstimator.haiku`

| Constant | input | output | cacheWrite | cacheRead |
|----------|-------|--------|------------|-----------|
| `opus` | 15.0 | 75.0 | 18.75 | 1.50 |
| `sonnet` | 3.0 | 15.0 | 3.75 | 0.30 |
| `haiku` | 0.80 | 4.0 | 1.00 | 0.08 |

### Current Implementation Note

`cost(for:)` does not reference the `record.speed` field. This is an intentional omission per the "Speed Adjustment" policy above.
