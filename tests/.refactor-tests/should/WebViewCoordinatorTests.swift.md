# WebViewCoordinatorTests.swift - Refactoring Recommendations

## Summary
This test file tests **multiple modules** (WebViewCoordinator + CookieChangeObserver) in a single file and uses **hand-written mock subclasses** instead of protocol-based mocking. Both S6 and S7 criteria apply.

**File**: `tests/ClaudeUsageTrackerTests/WebViewCoordinatorTests.swift`
**Line count**: 266 lines (under 500 - M2 not triggered)
**Criteria**: S6, S7

---

## S6: Multiple Modules in One Test File

**Finding**: The test file covers two distinct components:
- **WebViewCoordinator** (WKNavigationDelegate + WKUIDelegate delegate methods)
- **CookieChangeObserver** (WKHTTPCookieStoreObserver)

**Recommendation**: Split into two files:
- `WebViewCoordinatorTests.swift` - coordinator initialization, createWebViewWith, webViewDidClose behavior
- `CookieChangeObserverTests.swift` - cookie change callback forwarding

**Rationale**: Each component has distinct responsibilities. Separation improves maintainability and allows independent test evolution.

---

## S7: Hand-Written Mock Subclasses Without Protocol Conformance

**Findings**:

1. **MockUsageViewModel** (lines 10-37)
   - Custom mock class with manual call-count tracking
   - No protocol boundary; tightly coupled to real ViewModel interface
   - Methods: `checkPopupLogin()`, `handlePageReady()`, `closePopup()`, `handlePopupClosed()`, `debug()`

2. **MockWKNavigation** (line 42)
   - Subclass of `WKNavigation` (opaque WebKit type)
   - Empty implementation; used only as a stub

3. **MockWKNavigationAction** (lines 47-54)
   - Subclass of `WKNavigationAction` with override of `targetFrame` property
   - Allows test to control the `targetFrame` value (nil vs. non-nil) for routing tests

4. **MockWKWindowFeatures** (line 59)
   - Subclass of `WKWindowFeatures` (no customization needed)
   - Empty implementation; used as a stub

**Recommendation**:
- **MockUsageViewModel** and WebKit stubs serve different purposes:
  - WebKit stubs exist because these are **opaque types that cannot be instantiated directly** (comment on line 139-140 confirms CFRetain(NULL) crash)
  - MockUsageViewModel exists because there is **no protocol boundary** between WebViewCoordinator and UsageViewModel

**Action**:
- Introduce a **UsageViewModelDelegate protocol** that WebViewCoordinator depends on
- MockUsageViewModel becomes a direct implementation of UsageViewModelDelegate (protocol conformance)
- This breaks coupling and allows testing of WebViewCoordinator without relying on real ViewModel internals

**WebKit stubs**: Leave as-is (these are necessary workarounds for opaque types; protocol conformance is not applicable)

---

## Testing Notes

### Line 139-141: Comment on CFRetain(NULL) crash
```swift
// NOTE: WKFrameInfo cannot be instantiated directly in XCTest — WKFrameInfo() causes
// a CFRetain(NULL) crash because it is an opaque WebKit type.
```

This explains why `MockWKNavigationAction` subclasses `WKNavigationAction`: the real type cannot be created, so a subclass with controllable properties is necessary. This is a valid pattern for opaque types.

### State: Mixing real VM with mocks
The test creates a real `UsageViewModel` (line 95) but does not use it for verification. Instead, the test relies on WebViewCoordinator's behavior (e.g., returning a non-nil popup) rather than inspecting ViewModel calls. Consider whether ViewModel calls should be verified if they are critical to the spec.

---

## Summary of Changes

| Item | Action |
|------|--------|
| **S6: Multiple modules** | Split into `WebViewCoordinatorTests.swift` + `CookieChangeObserverTests.swift` |
| **S7: MockUsageViewModel** | Extract UsageViewModelDelegate protocol; make mock conform to protocol |
| **S7: WebKit stubs** | Keep as-is (opaque types require this pattern) |

