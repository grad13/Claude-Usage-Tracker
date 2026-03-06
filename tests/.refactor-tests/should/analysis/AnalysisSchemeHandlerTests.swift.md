# AnalysisSchemeHandlerTests.swift — should refactor

- **Trigger**: S7 (hand-written protocol mock)
- **File**: `tests/ClaudeUsageTrackerTests/analysis/AnalysisSchemeHandlerTests.swift` (265 lines)
- **Mock location**: `MockSchemeTask` in `AnalysisTestHelpers.swift` — hand-written conformance to `WKURLSchemeTask`

## Details

`MockSchemeTask` manually implements `WKURLSchemeTask` (Apple protocol) with 4 methods: `didReceive(_: URLResponse)`, `didReceive(_: Data)`, `didFinish()`, `didFailWithError(_:)`. It captures `receivedResponse`, `receivedData`, and `didFinishCalled` for assertions.

## Assessment

This is a borderline S7 case. The mock is:
- Small (~30 lines), shared via `AnalysisTestHelpers.swift`
- Conforming to an Apple SDK protocol (`WKURLSchemeTask`) which cannot easily be replaced by a Swift protocol-based test double without wrapping
- Used by multiple test files (shared helper)

The mock is reasonable for its purpose. Refactoring priority is low — the mock is already extracted to a shared file and is minimal. No immediate action required unless a broader test infrastructure refactor is planned.
