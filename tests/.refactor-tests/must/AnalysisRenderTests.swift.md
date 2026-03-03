---
File: tests/ClaudeUsageTrackerTests/AnalysisRenderTests.swift
Lines: 1142
Judgment: must
Issues: [M2]
---

# AnalysisRenderTests.swift

## 問題点

### 1. [M2] File exceeds 500 lines — split into focused test modules

**現状**: Single test file with 1142 lines contains two test classes:
- `AnalysisTemplateRenderTests` (lines 11-367): Tests DOM-interacting functions (buildHeatmap, main/renderMain, destroyAllCharts, renderUsageTab, renderCumulativeTab)
- `AnalysisBugHuntingTests` (lines 373-1142): Bug-hunting tests targeting specific output values and edge cases

Both classes inherit from `AnalysisJSTestCase` and use JavaScript evaluation via `evalJS()`.

**本質**: 1142 lines in a single file makes maintenance, navigation, and testing difficult. The two logical test classes (template rendering vs. bug-hunting) can be split into separate files for clarity and modularity.

**あるべき姿**: Split into two focused test files:
1. `AnalysisTemplateRenderTests.swift` (lines 11-367) — ~360 lines
2. `AnalysisBugHuntingTests.swift` (lines 373-1142) — ~770 lines

Consider further splitting bug-hunting tests if the second file still exceeds 500 lines, organizing by feature (stats display, chart configuration, date calculations, etc.).
