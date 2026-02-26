// meta: created=2026-02-21 updated=2026-02-21 checked=never ref=UsageViewModel
import SwiftUI
import WebKit

/// Displays the shared WKWebView for login / usage page.
/// All navigation logic is handled by UsageViewModel's coordinator.
struct LoginWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
