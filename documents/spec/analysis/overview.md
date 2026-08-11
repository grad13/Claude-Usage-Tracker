---
updated: 2026-08-11
checked: -
Deprecated: -
Format: spec-v2.1
Source: code/app/ClaudeUsageTracker/AnalysisExporter.swift
---

# Analysis Page

## 0. Meta

| Source | Runtime |
|--------|---------|
| code/app/ClaudeUsageTracker/AnalysisExporter.swift | macOS |
| code/app/ClaudeUsageTracker/AnalysisSchemeHandler.swift | macOS |
| code/app/ClaudeUsageTracker/Resources/analysis.html | macOS |

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
| `usage.db` | `usage_log` | Time-series usage rate and exact reset observations | `timestamp`, `hourly_percent`, `weekly_percent`, `five_hour_resets_at`, `seven_day_resets_at`, `resets_at_observed_at` |
| `usage.db` | `weekly_sessions` | Weekly session metadata | `id`, `resets_at` |
| `usage.db` | `hourly_sessions` | Hourly session metadata | `id`, `resets_at` |

## Data Flow

```
Analysis window opens
  -> AnalysisSchemeHandler (cut:// scheme)
  -> fetch cut://meta.json -> build exact session slots and calendar slots
  -> fetch cut://usage.json?from=X&to=Y -> usage data for current session
  -> renderMain(usageData) -> usage chart rendering
```

`AnalysisSchemeHandler` serves exact API reset observations first and falls back to normalized session-table values for legacy rows. Per-row JSON exposes independent 5-hour/7-day observation provenance. Meta JSON exposes exact-first aggregate/session `resets_at`, the normalized identity separately as `normalized_resets_at`, session `started_at`, and exact `resets_at_observed_at`. See `analysis-scheme-handler.md` for the authoritative key contract.

## Usage Chart

- **Data**: `usage_log` with LEFT JOIN on `hourly_sessions` and `weekly_sessions`
- **Chart**: Line chart (Chart.js `line`)
  - Blue line: hourly%, Red line: weekly%
  - X: time series, Y: 0-100%
- **Reset points**: Weekly session rendering can append usage-rate 0 at a completed `resets_at`. Hourly exact reset values remain metadata/display authority and do not inject points into the chronological Hourly fill.
- **Hourly continuity authority**: Exact `hourly_resets_at` / session identity remains authoritative for metadata, navigation, reset display, and bands, but it does not split the Hourly fill. Historical reset identities can interleave between adjacent chronological samples and are not evidence of missing usage data.
- **Hourly gap handling**: Valid Hourly samples are ordered by timestamp into one filled stepped dataset. Only elapsed time greater than the 30-minute default gap threshold inserts one parser-safe `{x: midpoint, y: null}` skipped point; `spanGaps: false` leaves that real interval empty. Literal `null` dataset items are forbidden because Chart.js object-data parsing dereferences each item's `x`. Reset/session identity changes alone never insert separators.
- **Weekly rendering**: Weekly sessions remain separate datasets and retain their session-based reset behavior.

## Session Navigation

- Entry point fetches `cut://meta.json` for overall range plus exact weekly/hourly session bounds
- Builds session-based weekly/hourly slots and calendar week/day slots
- User navigates between slots via Prev/Next buttons
- Each navigation triggers `loadData(from, to)` with epoch range

## Empty State

When no usage data is available, an empty chart is displayed.

## Technical Architecture

| Component | File | Responsibility |
|-----------|------|----------------|
| `AnalysisExporter` | `code/app/ClaudeUsageTracker/AnalysisExporter.swift` | Loads analysis.html from bundle resource |
| `AnalysisSchemeHandler` | `code/app/ClaudeUsageTracker/AnalysisSchemeHandler.swift` | Serves JSON data to WKWebView via cut:// scheme |
| `analysis.html` | `code/app/ClaudeUsageTracker/Resources/analysis.html` | HTML/CSS/JS (Chart.js) for usage visualization |
| `AnalysisWebView` | `code/app/ClaudeUsageTracker/ClaudeUsageTrackerApp.swift` L265-288 | NSViewRepresentable wrapper |
| `AnalysisWindowView` | `code/app/ClaudeUsageTracker/AnalysisWindowView.swift` | SwiftUI Window definition |

## Known Limitations

- All records within the selected session are SELECTed and passed to JS (performance with large datasets is unverified)
