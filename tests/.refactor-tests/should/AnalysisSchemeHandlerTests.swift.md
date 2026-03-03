# AnalysisSchemeHandlerTests.swift - Refactor Recommendation

## Issue: S6 - Multiple modules tested in single file

### Current Structure
- **File**: AnalysisSchemeHandlerTests.swift (469 lines)
- **Test Classes**: 2 classes testing the same module
  - `AnalysisSchemeHandlerTests` (lines 8-314) - Tests HTML/JSON serving, headers, MIME types, error handling
  - `AnalysisSchemeHandlerSQLiteTests` (lines 320-468) - Tests with real SQLite databases

### Problem
Both test classes focus on testing `AnalysisSchemeHandler`, differing only in setup approach:
- First class: Manually creates minimal SQLite DBs
- Second class: Uses `AnalysisTestDB` helper for database creation

This violates S6: "複数モジュールを1テストファイルでテスト → should"

### Recommendation
**Split into two focused files:**
1. `AnalysisSchemeHandlerTests.swift` - Core scheme handler functionality (HTML/JSON serving, headers, error cases)
2. `AnalysisSchemeHandlerSQLiteTests.swift` - SQLite integration tests (data correctness, large datasets)

### Benefits
- Single responsibility: each file tests one aspect
- Easier to locate tests for specific functionality
- Clearer test organization following module boundaries
- Reduced cognitive load when reading tests

### Test Groups to Migrate
- **Keep in AnalysisSchemeHandlerTests**: testSchemeIsCut, HTML serving, JSON serving, headers, CORS, MIME types, 404 handling, missing DB graceful handling
- **Move to AnalysisSchemeHandlerSQLiteTests**: Data correctness tests, HTML template integration, large dataset handling
