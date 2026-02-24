// meta: created=2026-02-24 updated=2026-02-24 checked=never
import Foundation
import WebKit

/// Serves local files to the Analysis WKWebView via a custom URL scheme (wcc://).
/// This avoids file:// CORS restrictions, allowing sql.js to fetch SQLite databases directly.
final class AnalysisSchemeHandler: NSObject, WKURLSchemeHandler {

    static let scheme = "wcc"

    /// Maps URL paths to local file providers.
    /// "html" is special — returns the inline HTML template.
    /// "usage.db" and "tokens.db" map to the actual SQLite database files.
    private let fileMap: [String: () -> Data?]

    init(usageDbPath: String, tokensDbPath: String, htmlProvider: @escaping () -> String) {
        self.fileMap = [
            "analysis.html": { htmlProvider().data(using: .utf8) },
            "usage.db": { try? Data(contentsOf: URL(fileURLWithPath: usageDbPath)) },
            "tokens.db": { try? Data(contentsOf: URL(fileURLWithPath: tokensDbPath)) },
        ]
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            fail(urlSchemeTask, code: 400, message: "Missing URL")
            return
        }

        // wcc://analysis.html → host = "analysis.html"
        let path = url.host ?? url.path
        guard let provider = fileMap[path], let data = provider() else {
            fail(urlSchemeTask, code: 404, message: "Not found: \(path)")
            return
        }

        let mimeType = Self.mimeType(for: path)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mimeType,
                "Content-Length": "\(data.count)",
                "Access-Control-Allow-Origin": "*",
            ]
        )!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Nothing to cancel
    }

    // MARK: - Private

    private func fail(_ task: WKURLSchemeTask, code: Int, message: String) {
        let response = HTTPURLResponse(
            url: task.request.url ?? URL(string: "wcc://error")!,
            statusCode: code,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/plain"]
        )!
        task.didReceive(response)
        task.didReceive(message.data(using: .utf8)!)
        task.didFinish()
    }

    private static func mimeType(for path: String) -> String {
        if path.hasSuffix(".html") { return "text/html" }
        if path.hasSuffix(".js") { return "application/javascript" }
        if path.hasSuffix(".wasm") { return "application/wasm" }
        return "application/octet-stream"
    }
}
