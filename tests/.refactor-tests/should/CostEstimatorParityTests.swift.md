# CostEstimatorParityTests.swift - Refactor Recommendations

## Issues Identified

### S6: Multiple Modules in Single Test File
- **Location**: Lines 7-124
- **Issue**: Tests both `CostEstimator` and `AnalysisExporter` in same test class
- **Models Tested**:
  - `CostEstimator` (pricing constants, cost calculation logic)
  - `AnalysisExporter` (HTML template and JS code generation)
- **Recommendation**: Split into separate test files:
  - `CostEstimatorTests.swift` - Pure cost calculation tests (testCostFormula_*, testJsPricing_matchesSwift)
  - `AnalysisExporterJsParityTests.swift` - JS template and field mapping verification (testJsModelRouting_matchesSwift, testJsCostFormula_fieldMapping)

### S7: Manual TokenRecord Construction Instead of Protocol Conformance
- **Location**: Lines 10-23 (helper method `swiftCost`)
- **Issue**: Helper method manually constructs `TokenRecord` with hardcoded values instead of using protocol-based mock or builder
- **Current Pattern**:
  ```swift
  let record = TokenRecord(
      timestamp: Date(),
      requestId: "test",
      model: model,
      speed: "standard",
      inputTokens: input,
      outputTokens: output,
      cacheReadTokens: cacheRead,
      cacheCreationTokens: cacheWrite,
      webSearchRequests: 0
  )
  ```
- **Recommendation**: Create a `TokenRecord` builder or factory method that defaults all fields except test parameters:
  ```swift
  static func makeTestRecord(model: String, input: Int, output: Int, cacheRead: Int, cacheWrite: Int) -> TokenRecord
  ```
  Or extract to a test helper protocol/extension for cleaner test data setup.

## Impact
- Refactoring reduces coupling between unrelated domain concepts
- Clearer test intent when modules are isolated
- Easier to maintain and extend when testing JS/HTML separately from cost logic
