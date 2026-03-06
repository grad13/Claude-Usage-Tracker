# WebViewCoordinatorTests.swift -- should refactor

## Triggered Criteria

- **S7 (hand-written partial mock)**: `MockWKNavigationAction` subclasses `WKNavigationAction` and overrides `targetFrame` property. This is a partial mock of a WebKit framework class. `MockWKNavigation` and `MockWKWindowFeatures` also subclass WebKit types as stubs.

## Current State (307 lines)

- 4 hand-written mock/stub classes (lines 10-59)
- 15 test methods covering CookieChangeObserver and WebViewCoordinator
- Tests cover: delegate protocol conformance, createWebViewWith popup creation, webViewDidClose routing, cookie observer forwarding

## Refactor Consideration

The partial mocks of WebKit opaque types (`WKNavigationAction`, `WKNavigation`, `WKWindowFeatures`) are a pragmatic workaround for untestable WebKit internals. The comment on line 135-138 acknowledges that `WKFrameInfo` cannot be instantiated at all. These mocks may be fragile if WebKit internals change across macOS versions. Consider whether a protocol-based abstraction layer over the WebKit delegate methods would reduce coupling to framework internals.

`MockUsageViewModel` conforms to `WebViewCoordinatorDelegate` protocol, which is a clean test double pattern -- no issue there.
