// meta: created=2026-02-26 updated=2026-02-26 checked=2026-02-26
import Foundation
import WebKit

// MARK: - WebView Coordinator (navigation + OAuth popup handling)

final class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    private weak var viewModel: UsageViewModel?

    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let viewModel else { return }
        let url = webView.url?.absoluteString ?? "nil"

        // Popup: check login status, close if logged in
        if webView === viewModel.popupWebView {
            viewModel.debug("didFinish[popup]: url=\(url)")
            viewModel.checkPopupLogin()
            return
        }

        viewModel.debug("didFinish[main]: url=\(url)")

        // Main WebView: notify ViewModel if on target host
        if let host = webView.url?.host, host == "claude.ai" {
            viewModel.handlePageReady()
        } else {
            viewModel.debug("didFinish[main]: host is not claude.ai, skipping")
        }
    }

    // MARK: OAuth Popup (sheet modal)

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let viewModel else { return nil }
        guard navigationAction.targetFrame == nil else { return nil }
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.navigationDelegate = self
        viewModel.popupWebView = popup
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard let viewModel else { return }
        if webView === viewModel.popupWebView {
            viewModel.closePopup()
            viewModel.handlePopupClosed()
        }
    }
}

// MARK: - Cookie Observer

final class CookieChangeObserver: NSObject, WKHTTPCookieStoreObserver {
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        onChange()
    }
}
