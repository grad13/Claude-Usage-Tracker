# AnalysisSQLQueryTests.swift - Refactor: S6 (Multiple Modules)

## Issue
This test file spans multiple domains/modules in a single file:
- **AnalysisSchemeHandler queries** (testUsageQuery_* methods)
- **Token record queries** (testTokenQuery_* methods)
- **CostEstimator integration** (testTokenQuery_costMatchesCostEstimator)

## Recommendation
Split into domain-specific test files:

1. **AnalysisSQLQueryTests_UsageLog.swift** - Usage query correctness
   - testUsageQuery_columnOrderMatchesJSMapping
   - testUsageQuery_orderByTimestampAsc
   - testUsageQuery_nullSessionIds_joinReturnsNull
   - Shared: tmpDir setup/teardown

2. **AnalysisSQLQueryTests_TokenRecords.swift** - Token record queries
   - testTokenQuery_columnOrderMatchesJSMapping
   - Shared: tmpDir setup/teardown

3. **CostEstimatorTests.swift** - Cost estimation (should be in main domain)
   - testTokenQuery_costMatchesCostEstimator (rename: testCost_fromTokenRecord)
   - Or merge with existing CostEstimator tests if they exist

## Rationale
- **Maintainability**: Each test file covers one domain → easier to locate/modify
- **Test organization**: Cost estimation belongs in CostEstimator tests, not SQL query tests
- **Clarity**: Test file name indicates what it tests (e.g., "TokenRecords" vs "SQL")
