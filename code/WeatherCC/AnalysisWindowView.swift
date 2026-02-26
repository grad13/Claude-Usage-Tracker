// meta: created=2026-02-26 updated=2026-02-26 checked=2026-02-26
import SwiftUI
import WebKit

// MARK: - Analysis Window (WKWebView + JSON)

struct AnalysisWindowView: View {
    var body: some View {
        AnalysisWebView()
    }
}

/// WKWebView configured with AnalysisSchemeHandler.
/// JS fetches wcc://usage.json and wcc://tokens.json (Swift-side SQLite → JSON).
struct AnalysisWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let handler = AnalysisSchemeHandler(
            usageDbPath: UsageStore.shared.dbPath,
            tokensDbPath: TokenStore.shared.dbPath,
            htmlProvider: { AnalysisExporter.htmlTemplate }
        )
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(handler, forURLScheme: AnalysisSchemeHandler.scheme)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.load(URLRequest(url: URL(string: "\(AnalysisSchemeHandler.scheme)://analysis.html")!))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
