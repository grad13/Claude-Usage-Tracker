# WebViewCoordinatorTests.swift refactor analysis

- **File**: `tests/ClaudeUsageTrackerTests/meta/WebViewCoordinatorTests.swift`
- **Lines**: 307
- **Test cases**: 14

## Issues

### S7: Duplicated setup code

The following 4-line setup pattern is repeated 5 times across tests (`testCreateWebViewWith_nilTargetFrame_returnsPopupWebView`, `testCreateWebViewWith_nilTargetFrame_popupNavigationDelegateIsCoordinator`, `testCreateWebViewWith_nilTargetFrame_setsJavaScriptCanOpenWindowsAutomatically`, `testCreateWebViewWith_nilTargetFrame_setsPopupWebViewOnViewModel`, `testStateDiagram_idleToPopupOpen_viaCreateWebViewWith`):

```swift
let coordinator = makeCoordinator()
let configuration = WKWebViewConfiguration()
let action = MockWKNavigationAction(targetFrame: nil)
let features = MockWKWindowFeatures()
```

**Recommendation**: Extract a helper such as `makePopupScenario() -> (WebViewCoordinator, WKWebViewConfiguration, MockWKNavigationAction, MockWKWindowFeatures)` or a tuple/struct to eliminate the repetition.
