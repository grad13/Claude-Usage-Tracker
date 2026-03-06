# AnalysisSchemeHandlerHelperTests.swift - Refactor Analysis

## Basic Info
- **Lines:** 324
- **Test cases:** 10 (2 classes: AnalysisSchemeHandlerHelperTests x6, AnalysisSchemeHandlerErrorHeaderTests x4)
- **Imports:** XCTest, WebKit, SQLite3, @testable ClaudeUsageTracker

## Issues Found

### S6: Duplicated Setup / Boilerplate

The full DB schema (`CREATE TABLE hourly_sessions`, `weekly_sessions`, `usage_log` + `INSERT`) is manually written inline in 3 tests:

- `testColumnInt_nullColumn_isJsonNull` (lines 99-109)
- `testColumnInt_integerColumn_returnsCorrectInt` (lines 138-148)
- `testMetaJson_success_hasCORSHeader` (lines 301-310)

Meanwhile, `AnalysisTestDB.createUsageDb` helper already exists and is used by the other tests in this file. The 3 tests above bypass it to insert rows with specific NULL/non-NULL session IDs, but the schema creation portion (3 CREATE TABLE statements) is identical each time.

**Suggested fix:** Extend `AnalysisTestDB` with a helper that creates the schema and optionally inserts rows with configurable session IDs (including NULL). This would eliminate ~30 lines of duplicated schema DDL.
