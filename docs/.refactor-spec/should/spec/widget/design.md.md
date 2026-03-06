# Spec Analysis: spec/widget/design.md

## Verdict: should

## Issues Found

### S-AMBIGUOUS: Frontmatter Source list and Meta Source table are inconsistent

**Contradicting locations:**

- Line 7 (frontmatter `Source` field): lists 6 files, including `code/ClaudeUsageTrackerWidget/WidgetColorThemeResolver.swift`
- Lines 14-20 (Meta Source table): lists only 5 files, missing `WidgetColorThemeResolver.swift`

**What contradicts:**
The frontmatter declares 6 source files but the Meta Source table only contains 5 rows. `WidgetColorThemeResolver.swift` is present in the frontmatter but absent from the table. The file is clearly relevant -- it has its own dedicated section (line 228-243) in the spec body.

**Fix recommendation:**
Add the missing row to the Meta Source table:

```
| code/ClaudeUsageTrackerWidget/WidgetColorThemeResolver.swift | macOS |
```

This aligns the table with the frontmatter and the spec body content.
