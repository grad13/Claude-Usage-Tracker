// meta: ref=AnalysisSchemeHandler
import SwiftUI
import WebKit

// MARK: - Analysis Window (WKWebView + JSON)

struct AnalysisWindowView: View {
    /// Incremented each time the window appears, triggering a WKWebView reload.
    @State private var reloadToken = 0

    var body: some View {
        AnalysisWebView(reloadToken: reloadToken)
            .onAppear { reloadToken += 1 }
    }
}

/// WKWebView configured with AnalysisSchemeHandler.
/// JS fetches cut://usage.json (Swift-side SQLite → JSON).
struct AnalysisWebView: NSViewRepresentable {
    /// Changed by parent view on each onAppear, triggering updateNSView → reload.
    var reloadToken: Int

    func makeNSView(context: Context) -> WKWebView {
        let handler = AnalysisSchemeHandler(
            usageDbPath: UsageStore.shared.dbPath,
            htmlProvider: { AnalysisExporter.htmlTemplate }
        )
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(handler, forURLScheme: AnalysisSchemeHandler.scheme)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.load(URLRequest(url: URL(string: "\(AnalysisSchemeHandler.scheme)://analysis.html")!))
        context.coordinator.lastToken = reloadToken
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        guard reloadToken != context.coordinator.lastToken else { return }
        context.coordinator.lastToken = reloadToken
        nsView.reload()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastToken = 0
    }
}
