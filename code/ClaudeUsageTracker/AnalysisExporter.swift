// meta: created=2026-02-22 updated=2026-02-26 checked=2026-02-26
import Foundation

/// Provides the HTML template for the Analysis window.
/// Data is loaded via AnalysisSchemeHandler (cut:// scheme) JSON endpoints.
/// The HTML is served via AnalysisSchemeHandler (cut:// scheme) in a WKWebView.
enum AnalysisExporter {

    private final class BundleAnchor {}

    static var htmlTemplate: String {
        guard let url = Bundle(for: BundleAnchor.self).url(forResource: "analysis", withExtension: "html"),
              let html = try? String(contentsOf: url, encoding: .utf8) else {
            return "<html><body>Failed to load analysis template</body></html>"
        }
        return html
    }
}
