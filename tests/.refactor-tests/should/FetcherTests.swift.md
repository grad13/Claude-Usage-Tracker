# FetcherTests.swift — Refactoring Recommendations

## Overview
- **File**: `tests/ClaudeUsageTrackerTests/FetcherTests.swift`
- **Line count**: 456 lines
- **Status**: should refactor

---

## Issues

### S6: Multiple Modules in Single Test File

**Finding**: This test file covers **two distinct types**:
1. `UsageFetcher` — parser and utility functions (parseStatus, parseResetDate, trimFractionalSeconds, calcPercent, parseUnixTimestamp, parse(jsonString:), parsePercent, parseResetsAt)
2. `UsageFetchError` — error type with isAuthError property and errorDescription

**Impact**: Reduces clarity on what each test file is responsible for. Error tests (lines 10–35, 150–156) could be isolated.

**Recommendation**:
- Split into `UsageFetcherTests.swift` (parsing and calculation logic)
- Create `UsageFetchErrorTests.swift` (error handling and descriptions)

---

### S7: Hand-Written Dictionary Mocks Instead of Protocol Conformance

**Finding**: Multiple tests construct `[String: Any]` dictionaries manually to represent window objects:
- Line 289: `let window: [String: Any] = ["utilization": 42]`
- Line 294: `let window: [String: Any] = ["limit": 100.0, "remaining": 25.0]`
- Lines 424–428: Complex window with multiple keys including precedence test

**Impact**:
- No type safety — typos in key names won't be caught at compile time
- Repetition of magic strings ("utilization", "limit", "remaining") across 6+ test methods
- If the actual window structure is a defined type/struct, hand-rolling dictionaries is less maintainable

**Recommendation**:
- Extract dictionary construction into helper factory methods (e.g., `makeWindow(utilization:)`, `makeWindow(limit:remaining:)`)
- Or, if UsageFetcher accepts a protocol (e.g., `WindowProtocol`), create lightweight conforming test doubles instead of raw dictionaries
- Centralize magic keys in a single test helper to ensure consistency and catch future refactorings

---

## Complexity Breakdown

| Category | Count | Lines |
|----------|-------|-------|
| `UsageFetcher` parsing tests | ~35 tests | ~330 |
| `UsageFetchError` tests | ~6 tests | ~40 |
| Utility and error description tests | ~3 tests | ~30 |
| **Total** | **44 tests** | **456** |

---

## Suggested Action Plan

1. **Extract `UsageFetchErrorTests.swift`** (lines 10–35, 150–156, 433–455)
   - testIsAuthError_* (6 tests)
   - testUsageFetchError_errorDescription
   - testParse_error* variants (5 tests)

2. **Create test helpers** in `FetcherTests.swift`
   ```swift
   private func makeWindow(utilization: Int) -> [String: Any] {
       ["utilization": utilization]
   }

   private func makeWindow(limit: Double, remaining: Double) -> [String: Any] {
       ["limit": limit, "remaining": remaining]
   }
   ```

3. **Replace all hand-rolled dictionaries** with helper calls
   - Line 289: `UsageFetcher.parsePercent(makeWindow(utilization: 42))`
   - Line 294: `UsageFetcher.parsePercent(makeWindow(limit: 100.0, remaining: 25.0))`

4. **Re-check for additional module cohesion** after split

---

## Notes for Implementation

- Preserve all assertions and test behavior — this is purely a structural refactor
- Ensure both extracted files remain in `tests/ClaudeUsageTrackerTests/`
- Run full test suite after split to confirm no regressions
