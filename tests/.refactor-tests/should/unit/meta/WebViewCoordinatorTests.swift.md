# WebViewCoordinatorTests.swift — should refactor

- **File**: `tests/ClaudeUsageTrackerTests/meta/WebViewCoordinatorTests.swift` (303 lines)
- **Category**: S7 — hand-written partial mock

## Detected issue

Four hand-written mock/stub classes defined inline at the top of the test file:

| Mock class | Lines | Technique |
|---|---|---|
| `MockUsageViewModel` | 10-37 | Protocol conformance (`WebViewCoordinatorDelegate`) with call-count tracking |
| `MockWKNavigation` | 42 | Subclass of opaque WebKit type `WKNavigation` |
| `MockWKNavigationAction` | 47-54 | Subclass overriding `targetFrame` property |
| `MockWKWindowFeatures` | 59 | Subclass stub (no custom behavior) |

`MockUsageViewModel` is a reasonable protocol-based test double. The three WebKit subclass stubs (`MockWKNavigation`, `MockWKNavigationAction`, `MockWKWindowFeatures`) are minimal but tightly coupled to WebKit internals.

## Suggested action

- Extract `MockUsageViewModel` to a shared test helper if reused across files.
- `MockWKNavigation` is unused (never referenced in any test) — remove it.
- `MockWKNavigationAction` and `MockWKWindowFeatures` are small stubs; acceptable inline but could move to a shared `WebKitTestStubs.swift` if other test files need them.
