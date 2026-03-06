// Supplement for: tests/ClaudeUsageTrackerTests/meta/WebViewCoordinatorTests.swift
//
// Covers Section 3.1 didFinish (WKNavigationDelegate) — 4 scenarios:
//   1. viewModel == nil → return (no delegate calls)
//   2. popup webView → checkPopupLogin()
//   3. main webView + host "claude.ai" → handlePageReady()
//   4. main webView + host != "claude.ai" → skip (no delegate calls)
//
// Note: WKNavigation cannot be safely instantiated outside WebKit.
// Its dealloc accesses internal state (CFRetain(NULL) → SIGTRAP).
// Pass nil for the navigation parameter since the coordinator ignores it.

import XCTest
import WebKit
@testable import ClaudeUsageTracker

// MARK: - TestPageSchemeHandler

/// Serves an empty HTML page for any URL requested via the "testpage" scheme.
/// Used to load a real WKWebView with a controlled URL host (e.g. testpage://claude.ai/usage)
/// without subclassing WKWebView (which is fragile with WebKit internals).
private final class TestPageSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let url = task.request.url!
        let response = URLResponse(url: url, mimeType: "text/html",
                                   expectedContentLength: -1, textEncodingName: "utf-8")
        task.didReceive(response)
        task.didReceive("<html></html>".data(using: .utf8)!)
        task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

// MARK: - WebViewCoordinatorDidFinishTests

/// Tests for Section 3.1 didFinish routing logic.
///
/// Reuses MockUsageViewModel from WebViewCoordinatorTests.
/// URL-dependent tests use TestPageSchemeHandler to load a real URL into WKWebView.
/// WKNavigation is NOT instantiated — pass nil since the coordinator ignores it.
@MainActor
final class WebViewCoordinatorDidFinishTests: XCTestCase {

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

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(viewModel: mockViewModel)
    }

    /// Creates a WKWebView loaded with a URL that has the given host.
    /// Uses a custom URL scheme handler so no network access is needed.
    /// After this returns, `webView.url?.host` equals the provided host.
    func makeWebView(host: String, path: String = "/test") -> WKWebView {
        let config = WKWebViewConfiguration()
        let handler = TestPageSchemeHandler()
        config.setURLSchemeHandler(handler, forURLScheme: "testpage")

        let webView = WKWebView(frame: .zero, configuration: config)
        let exp = expectation(description: "Page loaded: \(host)")
        let navDelegate = TestNavDelegate(onFinish: { exp.fulfill() })
        webView.navigationDelegate = navDelegate
        objc_setAssociatedObject(webView, "navDelegate", navDelegate, .OBJC_ASSOCIATION_RETAIN)

        webView.load(URLRequest(url: URL(string: "testpage://\(host)\(path)")!))
        wait(for: [exp], timeout: 5.0)
        return webView
    }

    // MARK: - Section 3.1: didFinish — viewModel == nil → return

    func testDidFinish_viewModelNil_doesNotCallAnyDelegateMethod() {
        var temporaryViewModel: MockUsageViewModel? = MockUsageViewModel()
        let coordinator = WebViewCoordinator(viewModel: temporaryViewModel!)
        let trackingViewModel = temporaryViewModel!

        temporaryViewModel = nil

        let webView = WKWebView(frame: .zero)
        coordinator.webView(webView, didFinish: nil)

        XCTAssertEqual(trackingViewModel.checkPopupLoginCallCount, 0)
        XCTAssertEqual(trackingViewModel.handlePageReadyCallCount, 0)
    }

    // MARK: - Section 3.1: didFinish — popup webView → checkPopupLogin()

    func testDidFinish_popupWebView_callsCheckPopupLogin() {
        let coordinator = makeCoordinator()
        let popupWebView = WKWebView(frame: .zero)
        mockViewModel.popupWebView = popupWebView

        coordinator.webView(popupWebView, didFinish: nil)

        XCTAssertEqual(mockViewModel.checkPopupLoginCallCount, 1)
    }

    func testDidFinish_popupWebView_doesNotCallHandlePageReady() {
        let coordinator = makeCoordinator()
        let popupWebView = WKWebView(frame: .zero)
        mockViewModel.popupWebView = popupWebView

        coordinator.webView(popupWebView, didFinish: nil)

        XCTAssertEqual(mockViewModel.handlePageReadyCallCount, 0)
    }

    // MARK: - Section 3.1: didFinish — main webView + host "claude.ai" → handlePageReady()

    func testDidFinish_mainWebView_hostClaudeAI_callsHandlePageReady() {
        let coordinator = makeCoordinator()
        let mainWebView = makeWebView(host: "claude.ai", path: "/usage")

        XCTAssertEqual(mainWebView.url?.host, "claude.ai", "Precondition")

        mainWebView.navigationDelegate = nil
        coordinator.webView(mainWebView, didFinish: nil)

        XCTAssertEqual(mockViewModel.handlePageReadyCallCount, 1)
    }

    func testDidFinish_mainWebView_hostClaudeAI_doesNotCallCheckPopupLogin() {
        let coordinator = makeCoordinator()
        let mainWebView = makeWebView(host: "claude.ai", path: "/usage")

        mainWebView.navigationDelegate = nil
        coordinator.webView(mainWebView, didFinish: nil)

        XCTAssertEqual(mockViewModel.checkPopupLoginCallCount, 0)
    }

    // MARK: - Section 3.1: didFinish — main webView + host != "claude.ai" → skip

    func testDidFinish_mainWebView_hostNotClaudeAI_doesNotCallHandlePageReady() {
        let coordinator = makeCoordinator()
        let mainWebView = makeWebView(host: "accounts.google.com", path: "/login")

        XCTAssertEqual(mainWebView.url?.host, "accounts.google.com", "Precondition")

        mainWebView.navigationDelegate = nil
        coordinator.webView(mainWebView, didFinish: nil)

        XCTAssertEqual(mockViewModel.handlePageReadyCallCount, 0)
        XCTAssertEqual(mockViewModel.checkPopupLoginCallCount, 0)
    }

    func testDidFinish_mainWebView_urlNil_doesNotCallHandlePageReady() {
        let coordinator = makeCoordinator()
        let mainWebView = WKWebView(frame: .zero)

        coordinator.webView(mainWebView, didFinish: nil)

        XCTAssertEqual(mockViewModel.handlePageReadyCallCount, 0)
        XCTAssertEqual(mockViewModel.checkPopupLoginCallCount, 0)
    }
}
