# refactor-spec Summary

Date: 2026-03-07
Total files analyzed: 17
Must: 0
Should: 1
Clean: 16

## Results

| File | Lines | Judgment | Issues |
|------|-------|----------|--------|
| spec/widget/design.md | 483 | **should** | S-AMBIGUOUS |
| spec/meta/viewmodel-lifecycle.md | 371 | clean | — |
| spec/data/settings.md | 355 | clean | — |
| spec/data/usage-store.md | 340 | clean | — |
| spec/analysis/analysis-scheme-handler.md | 332 | clean | — |
| spec/data/alert.md | 301 | clean | — |
| spec/ui/menu-content.md | 279 | clean | — |
| spec/meta/architecture.md | 270 | clean | — |
| spec/analysis/analysis-exporter.md | 239 | clean | — |
| spec/ui/app-windows.md | 234 | clean | — |
| spec/meta/viewmodel-session.md | 234 | clean | — |
| spec/tools/build-and-install.md | 207 | clean | — |
| spec/data/usage-fetcher.md | 190 | clean | — |
| spec/meta/protocols.md | 184 | clean | — |
| spec/ui/mini-usage-graph.md | 163 | clean | — |
| spec/meta/webview-coordinator.md | 124 | clean | — |
| spec/analysis/overview.md | 82 | clean | — |

## Should Issues

### spec/widget/design.md — S-AMBIGUOUS

Frontmatter `Source` field lists 6 files including `WidgetColorThemeResolver.swift`, but Meta Source table only has 5 rows, omitting that file. Inconsistency between two representations of the same information.

Details: `docs/.refactor-spec/should/spec/widget/design.md.md`
