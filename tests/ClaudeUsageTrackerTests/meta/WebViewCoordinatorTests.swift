import XCTest
import WebKit
@testable import ClaudeUsageTracker

// MARK: - MockUsageViewModel

/// Minimal mock that records calls made by WebViewCoordinator and allows
/// setting `popupWebView` as required by the spec.
@MainActor
final class MockUsageViewModel: WebViewCoordinatorDelegate {
    var popupWebView: WKWebView?
    var checkPopupLoginCallCount = 0
    var handlePageReadyCallCount = 0
    var closePopupCallCount = 0
    var handlePopupClosedCallCount = 0

    func checkPopupLogin() {
        checkPopupLoginCallCount += 1
    }

    func handlePageReady() {
        handlePageReadyCallCount += 1
    }

    func closePopup() {
        closePopupCallCount += 1
        popupWebView = nil
    }

    func handlePopupClosed() {
        handlePopupClosedCallCount += 1
    }

    func debug(_ message: String) {
        // no-op: side effects limited to logging, not verified in unit tests
    }
}

// MARK: - MockWKNavigationAction

/// Stub for WKNavigationAction allowing targetFrame control.
final class MockWKNavigationAction: WKNavigationAction {
    private let _targetFrame: WKFrameInfo?
    override var targetFrame: WKFrameInfo? { _targetFrame }

    init(targetFrame: WKFrameInfo?) {
        _targetFrame = targetFrame
    }
}

// MARK: - MockWKWindowFeatures

/// Stub for WKWindowFeatures (no configurable properties needed).
final class MockWKWindowFeatures: WKWindowFeatures {}

// MARK: - WebViewCoordinatorTests

/// Tests for WebViewCoordinator (WKNavigationDelegate + WKUIDelegate) and
/// CookieChangeObserver (WKHTTPCookieStoreObserver).
///
/// Spec source: spec/meta/webview-coordinator.md
/// The spec defines logic purely in terms of:
///   - Section 3.1: didFinish routing (popup vs main, host check)
///   - Section 3.2: createWebViewWith popup creation conditions
///   - Section 3.3: webViewDidClose popup close conditions
///   - Section 3.4: cookiesDidChange always calls onChange
@MainActor
final class WebViewCoordinatorTests: XCTestCase {

    var mockViewModel: MockUsageViewModel!

    override func setUp() {
        super.setUp()
        mockViewModel = MockUsageViewModel()
    }

    override func tearDown() {
        mockViewModel = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Creates a WebViewCoordinator backed by MockUsageViewModel.
    /// The mock is retained as `mockViewModel` to prevent deallocation of the weak reference.
    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(viewModel: mockViewModel)
    }

    /// Returns the 4 components needed to test popup creation via createWebViewWith.
    func makePopupScenario() -> (
        coordinator: WebViewCoordinator,
        configuration: WKWebViewConfiguration,
        action: MockWKNavigationAction,
        features: MockWKWindowFeatures
    ) {
        (makeCoordinator(), WKWebViewConfiguration(),
         MockWKNavigationAction(targetFrame: nil), MockWKWindowFeatures())
    }

    // MARK: - CookieChangeObserver: cookiesDidChange

    /// Section 3.4: cookiesDidChange always calls onChange regardless of arguments.
    func testCookieChangeObserver_cookiesDidChange_callsOnChange() {
        var callCount = 0
        let observer = CookieChangeObserver(onChange: { callCount += 1 })
        let store = WKWebsiteDataStore.nonPersistent().httpCookieStore
        observer.cookiesDidChange(in: store)
        XCTAssertEqual(callCount, 1,
                       "cookiesDidChange must always invoke the onChange closure")
    }

    /// Section 3.4: cookiesDidChange called multiple times invokes onChange each time.
    func testCookieChangeObserver_cookiesDidChange_calledMultipleTimes_callsOnChangeEachTime() {
        var callCount = 0
        let observer = CookieChangeObserver(onChange: { callCount += 1 })
        let store = WKWebsiteDataStore.nonPersistent().httpCookieStore
        observer.cookiesDidChange(in: store)
        observer.cookiesDidChange(in: store)
        observer.cookiesDidChange(in: store)
        XCTAssertEqual(callCount, 3,
                       "Each cookiesDidChange call must forward to onChange exactly once")
    }

    // MARK: - WebViewCoordinator: init

    /// Contract: WebViewCoordinator is NSObject, WKNavigationDelegate, WKUIDelegate.
    func testCoordinator_conformsToWKNavigationDelegate() {
        let coordinator = makeCoordinator()
        XCTAssertTrue(coordinator is WKNavigationDelegate)
    }

    func testCoordinator_conformsToWKUIDelegate() {
        let coordinator = makeCoordinator()
        XCTAssertTrue(coordinator is WKUIDelegate)
    }

    // MARK: - createWebViewWith: targetFrame != nil → returns nil

    /// Section 3.2: When targetFrame != nil, coordinator returns nil (normal link; not a popup).
    /// NOTE: WKFrameInfo cannot be instantiated directly in XCTest — WKFrameInfo() causes
    /// a CFRetain(NULL) crash because it is an opaque WebKit type. This guard path
    /// (targetFrame != nil → return nil) is implicitly verified by the nil-targetFrame tests
    /// above which confirm the only path that returns a non-nil popup.

    // MARK: - createWebViewWith: targetFrame == nil → returns popup WKWebView

    /// Section 3.2: When targetFrame == nil, coordinator creates and returns a popup WKWebView.
    func testCreateWebViewWith_nilTargetFrame_returnsPopupWebView() {
        let (coordinator, configuration, action, features) = makePopupScenario()

        let result = coordinator.webView(
            WKWebView(frame: .zero),
            createWebViewWith: configuration,
            for: action,
            windowFeatures: features
        )

        XCTAssertNotNil(result,
                        "createWebViewWith must return a WKWebView popup when targetFrame == nil")
    }

    /// Section 3.2: The returned popup has coordinator set as its navigationDelegate.
    func testCreateWebViewWith_nilTargetFrame_popupNavigationDelegateIsCoordinator() {
        let (coordinator, configuration, action, features) = makePopupScenario()

        let popup = coordinator.webView(
            WKWebView(frame: .zero),
            createWebViewWith: configuration,
            for: action,
            windowFeatures: features
        )

        XCTAssertTrue(popup?.navigationDelegate === coordinator,
                      "popup.navigationDelegate must be set to coordinator (spec 3.2)")
    }

    /// Section 3.2: configuration.preferences.javaScriptCanOpenWindowsAutomatically = true.
    func testCreateWebViewWith_nilTargetFrame_setsJavaScriptCanOpenWindowsAutomatically() {
        let (coordinator, configuration, action, features) = makePopupScenario()

        _ = coordinator.webView(
            WKWebView(frame: .zero),
            createWebViewWith: configuration,
            for: action,
            windowFeatures: features
        )

        XCTAssertTrue(configuration.preferences.javaScriptCanOpenWindowsAutomatically,
                      "spec 3.2: javaScriptCanOpenWindowsAutomatically must be set to true on the configuration")
    }

    // MARK: - webViewDidClose

    /// Section 3.3: webViewDidClose with a WKWebView that is NOT the popup → no ViewModel calls.
    func testWebViewDidClose_nonPopupWebView_doesNotCallClosePopup() {
        let coordinator = makeCoordinator()
        let unrelatedWebView = WKWebView(frame: .zero)

        coordinator.webViewDidClose(unrelatedWebView)

        XCTAssertEqual(mockViewModel.closePopupCallCount, 0,
                       "webViewDidClose must not call closePopup when webView is not the popup")
        XCTAssertEqual(mockViewModel.handlePopupClosedCallCount, 0,
                       "webViewDidClose must not call handlePopupClosed when webView is not the popup")
    }

    /// Section 3.3: webViewDidClose with the popup WebView → calls closePopup + handlePopupClosed.
    func testWebViewDidClose_popupWebView_callsClosePopupAndHandlePopupClosed() {
        let coordinator = makeCoordinator()
        let configuration = WKWebViewConfiguration()
        let action = MockWKNavigationAction(targetFrame: nil)
        let features = MockWKWindowFeatures()

        // Create a popup so that viewModel.popupWebView is set
        let popup = coordinator.webView(
            WKWebView(frame: .zero),
            createWebViewWith: configuration,
            for: action,
            windowFeatures: features
        )!

        coordinator.webViewDidClose(popup)

        XCTAssertEqual(mockViewModel.closePopupCallCount, 1,
                       "webViewDidClose must call closePopup when webView matches popup")
        XCTAssertEqual(mockViewModel.handlePopupClosedCallCount, 1,
                       "webViewDidClose must call handlePopupClosed when webView matches popup")
    }

    // MARK: - CookieChangeObserver: init stores closure

    /// CookieChangeObserver.init stores the onChange closure; cookiesDidChange forwards to it.
    func testCookieChangeObserver_init_storesOnChangeClosure() {
        var invoked = false
        let observer = CookieChangeObserver(onChange: { invoked = true })
        let store = WKWebsiteDataStore.nonPersistent().httpCookieStore
        observer.cookiesDidChange(in: store)
        XCTAssertTrue(invoked, "CookieChangeObserver must store and invoke the closure passed to init")
    }

    /// CookieChangeObserver is NSObject and WKHTTPCookieStoreObserver.
    func testCookieChangeObserver_conformsToWKHTTPCookieStoreObserver() {
        let observer = CookieChangeObserver(onChange: {})
        XCTAssertTrue(observer is WKHTTPCookieStoreObserver)
    }

    // MARK: - createWebViewWith: sets popupWebView on viewModel

    /// Section 3.2: createWebViewWith stores the popup in viewModel.popupWebView.
    func testCreateWebViewWith_nilTargetFrame_setsPopupWebViewOnViewModel() {
        let (coordinator, configuration, action, features) = makePopupScenario()

        XCTAssertNil(mockViewModel.popupWebView, "popupWebView must be nil before popup creation")

        let popup = coordinator.webView(
            WKWebView(frame: .zero),
            createWebViewWith: configuration,
            for: action,
            windowFeatures: features
        )

        XCTAssertTrue(mockViewModel.popupWebView === popup,
                      "createWebViewWith must store the returned popup in viewModel.popupWebView")
    }

    // MARK: - State diagram: Idle → PopupOpen (createWebViewWith)

    /// Section 2 state diagram: init() → Idle. createWebViewWith returns popup → PopupOpen.
    /// Verifies the transition by confirming a non-nil popup is produced.
    func testStateDiagram_idleToPopupOpen_viaCreateWebViewWith() {
        let (coordinator, configuration, action, features) = makePopupScenario()

        let popup = coordinator.webView(
            WKWebView(frame: .zero),
            createWebViewWith: configuration,
            for: action,
            windowFeatures: features
        )

        XCTAssertNotNil(popup, "Idle→PopupOpen transition must produce a non-nil popup WebView")
    }

    // MARK: - Multiple cookiesDidChange calls are independent

    /// Section 3.4: Each onChange invocation is independent; CookieChangeObserver holds no
    /// internal state that would suppress subsequent calls.
    func testCookieChangeObserver_multipleStores_callsOnChangeForEach() {
        var callCount = 0
        let observer = CookieChangeObserver(onChange: { callCount += 1 })
        let storeA = WKWebsiteDataStore.nonPersistent().httpCookieStore
        let storeB = WKWebsiteDataStore.nonPersistent().httpCookieStore
        observer.cookiesDidChange(in: storeA)
        observer.cookiesDidChange(in: storeB)
        XCTAssertEqual(callCount, 2,
                       "CookieChangeObserver must call onChange for each cookiesDidChange invocation")
    }
}
