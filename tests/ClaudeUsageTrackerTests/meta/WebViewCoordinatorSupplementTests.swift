// Supplement for: tests/ClaudeUsageTrackerTests/meta/WebViewCoordinatorTests.swift
//
// Covers Section 3.1 didFinish (WKNavigationDelegate) — 4 scenarios:
//   1. viewModel == nil → return (no delegate calls)
//   2. popup webView → checkPopupLogin()
//   3. main webView + host "claude.ai" → handlePageReady()
//   4. main webView + host != "claude.ai" → skip (no delegate calls)

import XCTest
import WebKit
@testable import ClaudeUsageTracker

// MARK: - StubWKWebView

/// WKWebView subclass that allows controlling the `url` property for testing.
/// WKWebView.url is read-only and set internally by navigation;
/// overriding it lets us simulate page loads without async navigation.
private class StubWKWebView: WKWebView {
    private let _url: URL?
    override var url: URL? { _url }

    init(url: URL?) {
        _url = url
        super.init(frame: .zero, configuration: WKWebViewConfiguration())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - WebViewCoordinatorDidFinishTests

/// Tests for Section 3.1 didFinish routing logic.
///
/// Reuses MockUsageViewModel and MockWKNavigation from WebViewCoordinatorTests.
/// The mock is defined in the main test file and shared via the same test target.
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

    // MARK: - Section 3.1: didFinish — viewModel == nil → return

    /// When the weak viewModel reference has been deallocated, didFinish
    /// must return without calling any delegate methods.
    func testDidFinish_viewModelNil_doesNotCallAnyDelegateMethod() {
        // Create coordinator with a temporary MockUsageViewModel that will be
        // released when we nil out the strong reference below.
        var temporaryViewModel: MockUsageViewModel? = MockUsageViewModel()
        let coordinator = WebViewCoordinator(viewModel: temporaryViewModel!)
        let trackingViewModel = temporaryViewModel!

        // Release the strong reference so the weak reference inside coordinator becomes nil
        temporaryViewModel = nil

        let webView = WKWebView(frame: .zero)
        let navigation = MockWKNavigation()

        coordinator.webView(webView, didFinish: navigation)

        XCTAssertEqual(trackingViewModel.checkPopupLoginCallCount, 0,
                       "didFinish must not call checkPopupLogin when viewModel is nil")
        XCTAssertEqual(trackingViewModel.handlePageReadyCallCount, 0,
                       "didFinish must not call handlePageReady when viewModel is nil")
    }

    // MARK: - Section 3.1: didFinish — popup webView → checkPopupLogin()

    /// When didFinish is called with a webView that matches viewModel.popupWebView
    /// (identity check via ===), coordinator must call checkPopupLogin().
    func testDidFinish_popupWebView_callsCheckPopupLogin() {
        let coordinator = makeCoordinator()
        let popupWebView = WKWebView(frame: .zero)
        mockViewModel.popupWebView = popupWebView

        let navigation = MockWKNavigation()
        coordinator.webView(popupWebView, didFinish: navigation)

        XCTAssertEqual(mockViewModel.checkPopupLoginCallCount, 1,
                       "didFinish must call checkPopupLogin when webView === popupWebView")
    }

    /// When didFinish is called with the popup webView, handlePageReady must NOT
    /// be called — the popup path returns after checkPopupLogin.
    func testDidFinish_popupWebView_doesNotCallHandlePageReady() {
        let coordinator = makeCoordinator()
        let popupWebView = WKWebView(frame: .zero)
        mockViewModel.popupWebView = popupWebView

        let navigation = MockWKNavigation()
        coordinator.webView(popupWebView, didFinish: navigation)

        XCTAssertEqual(mockViewModel.handlePageReadyCallCount, 0,
                       "didFinish must not call handlePageReady for popup webView")
    }

    // MARK: - Section 3.1: didFinish — main webView + host "claude.ai" → handlePageReady()

    /// When didFinish is called with a non-popup webView whose URL host is "claude.ai",
    /// coordinator must call handlePageReady().
    func testDidFinish_mainWebView_hostClaudeAI_callsHandlePageReady() {
        let coordinator = makeCoordinator()
        let mainWebView = StubWKWebView(url: URL(string: "https://claude.ai/usage")!)

        let navigation = MockWKNavigation()
        coordinator.webView(mainWebView, didFinish: navigation)

        XCTAssertEqual(mockViewModel.handlePageReadyCallCount, 1,
                       "didFinish must call handlePageReady when main webView host is claude.ai")
    }

    /// When didFinish is called with a main webView on claude.ai,
    /// checkPopupLogin must NOT be called.
    func testDidFinish_mainWebView_hostClaudeAI_doesNotCallCheckPopupLogin() {
        let coordinator = makeCoordinator()
        let mainWebView = StubWKWebView(url: URL(string: "https://claude.ai/usage")!)

        let navigation = MockWKNavigation()
        coordinator.webView(mainWebView, didFinish: navigation)

        XCTAssertEqual(mockViewModel.checkPopupLoginCallCount, 0,
                       "didFinish must not call checkPopupLogin for main webView")
    }

    // MARK: - Section 3.1: didFinish — main webView + host != "claude.ai" → skip

    /// When didFinish is called with a non-popup webView whose URL host is NOT "claude.ai",
    /// coordinator must not call handlePageReady or checkPopupLogin.
    func testDidFinish_mainWebView_hostNotClaudeAI_doesNotCallHandlePageReady() {
        let coordinator = makeCoordinator()
        let mainWebView = StubWKWebView(url: URL(string: "https://accounts.google.com/login")!)

        let navigation = MockWKNavigation()
        coordinator.webView(mainWebView, didFinish: navigation)

        XCTAssertEqual(mockViewModel.handlePageReadyCallCount, 0,
                       "didFinish must not call handlePageReady when host is not claude.ai")
        XCTAssertEqual(mockViewModel.checkPopupLoginCallCount, 0,
                       "didFinish must not call checkPopupLogin for main webView")
    }

    /// When the webView URL is nil (no page loaded), didFinish must skip
    /// (host is nil, which does not match "claude.ai").
    func testDidFinish_mainWebView_urlNil_doesNotCallHandlePageReady() {
        let coordinator = makeCoordinator()
        let mainWebView = WKWebView(frame: .zero) // url is nil by default

        let navigation = MockWKNavigation()
        coordinator.webView(mainWebView, didFinish: navigation)

        XCTAssertEqual(mockViewModel.handlePageReadyCallCount, 0,
                       "didFinish must not call handlePageReady when webView.url is nil")
        XCTAssertEqual(mockViewModel.checkPopupLoginCallCount, 0,
                       "didFinish must not call checkPopupLogin for main webView with nil url")
    }
}
