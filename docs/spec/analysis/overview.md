---
Created: 2026-02-26
Updated: 2026-03-06
Checked: -
Deprecated: -
Format: spec-v2.1
Source: code/ClaudeUsageTracker/AnalysisExporter.swift
---

# Analysis Page

## 0. Meta

| Source | Runtime |
|--------|---------|
| code/ClaudeUsageTracker/AnalysisExporter.swift | macOS |
| code/ClaudeUsageTracker/AnalysisSchemeHandler.swift | macOS |
| code/ClaudeUsageTracker/Resources/analysis.html | macOS |

| Field | Value |
|-------|-------|
| Related | spec/analysis/analysis-scheme-handler.md, spec/analysis/analysis-exporter.md |
| Test Type | - |

## Overview

An analysis window that visualizes Claude Code usage and cost data.
Opened from the menu bar via "Analysis" (SwiftUI Window, 1200x800pt).
Built with WKWebView + sql.js + Chart.js. Dark theme (GitHub Dark: #0d1117).

## Data Sources

| DB | Table | Purpose | Key Columns |
|----|-------|---------|-------------|
| `usage.db` | `usage_log` | Time-series usage rate records | `timestamp`, `five_hour_percent`, `seven_day_percent`, `five_hour_resets_at`, `seven_day_resets_at` |
| `tokens.db` | `token_records` | Token records extracted from JSONL | `timestamp`, `model`, `input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_creation_tokens` |

## Data Flow

```
Analysis window opens
  -> AnalysisSchemeHandler (cut:// scheme) serves DB files
  -> sql.js fetches cut://usage.db, cut://tokens.db
  -> SELECT FROM usage_log / token_records
  -> JS-side cost calculation (MODEL_PRICING x token count)
  -> main(usageData, tokenData) -> summary + tab rendering
```

### Data Ingestion into tokens.db

```
~/.claude/projects/**/*.jsonl
  -> UsageViewModel.fetchPredict()
    -> claudeProjectsDirectories() returns ~/.claude/projects/
    -> TokenStore.sync(directories:) performs incremental parse -> INSERT into tokens.db
```

- **Sync trigger**: Runs automatically on every fetch cycle (auto-refresh timer + manual Refresh)

## Summary Statistics (Common Header Across All Tabs)

| Field | Data Source |
|-------|------------|
| Usage Records | `usageData.length` |
| Token Records | `tokenData.length` |
| Total Est. Cost | Sum of each `tokenData` record calculated as MODEL_PRICING x token count |
| Usage Span | Time difference between the first and last usage records |
| Latest 5h | Latest `five_hour_percent` |
| Latest 7d | Latest `seven_day_percent` |

## Tab Specifications

### 1. Usage Tab

- **Data**: `usage_log` only (no token data needed)
- **Chart**: Line chart (Chart.js `line`)
  - Blue line: 5h%, Red line: 7d%
  - X: time series, Y: 0-100%
- **Reset points**: Inserts a usage-rate-0 point at the `resets_at` timestamp (visualizes drops)
- **Gap handling**: Segments exceeding the gap threshold (5-360 min, default 30 min) have their lines made transparent
  - User can adjust the threshold via a slider

### 2. Cost Tab

- **Data**: `token_records` only
- **Chart**: Bar chart -- estimated cost per request (USD, JS-computed) over time
- **Cost calculation**: JS-side MODEL_PRICING x token count
  - Opus: input $15, output $75, cacheWrite $18.75, cacheRead $1.50 / 1M tokens
  - Sonnet: input $3, output $15, cacheWrite $3.75, cacheRead $0.30 / 1M tokens
  - Haiku: input $0.80, output $4, cacheWrite $1, cacheRead $0.08 / 1M tokens

### 3. Efficiency Tab

- **Data**: `usage_log` + `token_records` joined via `computeDeltas()`
  - Aggregates token costs occurring between two consecutive usage records
  - Produces pairs of delta-5h% and delta-cost
- **Chart 1**: Scatter plot -- delta-cost (x) vs delta-5h% (y), colored by time-of-day
- **Chart 2**: KDE density curve -- probability distribution of the delta-% / delta-$ ratio
- **Chart 3**: Heatmap -- day-of-week (7) x hour-of-day (24) average delta-% / delta-$
  - Cell color: gradient based on ratio (red -> yellow -> green)
- **Filter**: Filterable by date range (From / To)

### 4. Cumulative Tab

- **Data**: `token_records` only
- **Chart**: Line chart -- cumulative sum of estimated cost (USD, JS-computed) over time

## Empty State Specification

Tabs with no data display a message instead of an empty canvas.

| Condition | Affected Tab | Message |
|-----------|-------------|---------|
| `usageData` is empty | Usage | "No usage data available.\nUsage will be recorded automatically when monitoring is active." |
| `tokenData` is empty | Cost, Cumulative | "No token data available.\nJSONL logs from ~/.claude/projects/ will be synced automatically." |
| `deltas` is empty | Efficiency | "No efficiency data.\nRequires both usage records and token data." |

Display style: centered, `color: #484f58`, `font-size: 14px`

## Technical Architecture

| Component | File | Responsibility |
|-----------|------|----------------|
| `AnalysisExporter` | `code/ClaudeUsageTracker/AnalysisExporter.swift` | HTML template (CSS + JS + HTML in one) |
| `AnalysisSchemeHandler` | `code/ClaudeUsageTracker/AnalysisSchemeHandler.swift` | Serves DB files to WKWebView via cut:// scheme |
| `AnalysisWebView` | `code/ClaudeUsageTracker/ClaudeUsageTrackerApp.swift` L265-288 | NSViewRepresentable wrapper |
| `AnalysisWindowView` | `code/ClaudeUsageTracker/ClaudeUsageTrackerApp.swift` L22-25 | SwiftUI Window definition |

## Known Limitations

- MODEL_PRICING is hardcoded in JS (duplicated with CostEstimator.swift)
- All records are SELECTed and passed to JS (performance with large datasets is unverified)
