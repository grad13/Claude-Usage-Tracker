# AnalysisSchemeHandlerMetaJSONTests.swift

- **Lines**: 262
- **Criteria**: S7
- **Finding**: 4 of 6 tests (UT-M02, UT-M04, UT-M05, UT-M04b) manually create SQLite databases with raw `sqlite3_open`/`sqlite3_exec` calls, while UT-M03 uses the shared `AnalysisTestDB.createUsageDb` helper. This inconsistency means DB schema changes require updating raw SQL in 4 places instead of 1 shared helper. Refactor candidates: extract schema creation variants into `AnalysisTestDB` methods (e.g., `createEmptySchemaDb`, `createUsageDbWithWeeklySessions`).
