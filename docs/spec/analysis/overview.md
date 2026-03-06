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

An analysis window that visualizes Claude Code usage data.
Opened from the menu bar via "Analysis" (SwiftUI Window, 1200x800pt).
Built with WKWebView + Chart.js. Dark theme (GitHub Dark: #0d1117).

## Data Sources

| DB | Table | Purpose | Key Columns |
|----|-------|---------|-------------|
| `usage.db` | `usage_log` | Time-series usage rate records | `timestamp`, `hourly_percent`, `weekly_percent`, `hourly_resets_at`, `weekly_resets_at` |
| `usage.db` | `weekly_sessions` | Weekly session metadata | `id`, `resets_at` |
| `usage.db` | `hourly_sessions` | Hourly session metadata | `id`, `resets_at` |

## Data Flow

```
Analysis window opens
  -> AnalysisSchemeHandler (cut:// scheme)
  -> fetch cut://meta.json -> build session slots (weekly/daily)
  -> fetch cut://usage.json?from=X&to=Y -> usage data for current session
  -> renderMain(usageData) -> usage chart rendering
```

## Usage Chart

- **Data**: `usage_log` with LEFT JOIN on `hourly_sessions` and `weekly_sessions`
- **Chart**: Line chart (Chart.js `line`)
  - Blue line: hourly%, Red line: weekly%
  - X: time series, Y: 0-100%
- **Reset points**: Inserts a usage-rate-0 point at the `resets_at` timestamp (visualizes drops)
- **Gap handling**: Segments exceeding the gap threshold (5-360 min, default 30 min) have their lines made transparent
  - User can adjust the threshold via a slider

## Session Navigation

- Entry point fetches `cut://meta.json` to get overall timestamp range
- Builds weekly or daily slots from the timestamp range
- User navigates between slots via Prev/Next buttons
- Each navigation triggers `loadData(from, to)` with epoch range

## Empty State

When no usage data is available, an empty chart is displayed.

## Technical Architecture

| Component | File | Responsibility |
|-----------|------|----------------|
| `AnalysisExporter` | `code/ClaudeUsageTracker/AnalysisExporter.swift` | Loads analysis.html from bundle resource |
| `AnalysisSchemeHandler` | `code/ClaudeUsageTracker/AnalysisSchemeHandler.swift` | Serves JSON data to WKWebView via cut:// scheme |
| `analysis.html` | `code/ClaudeUsageTracker/Resources/analysis.html` | HTML/CSS/JS (Chart.js) for usage visualization |
| `AnalysisWebView` | `code/ClaudeUsageTracker/ClaudeUsageTrackerApp.swift` L265-288 | NSViewRepresentable wrapper |
| `AnalysisWindowView` | `code/ClaudeUsageTracker/AnalysisWindowView.swift` | SwiftUI Window definition |

## Known Limitations

- All records within the selected session are SELECTed and passed to JS (performance with large datasets is unverified)
