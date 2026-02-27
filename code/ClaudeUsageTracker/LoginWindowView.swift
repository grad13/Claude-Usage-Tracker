// meta: created=2026-02-26 updated=2026-02-26 checked=2026-02-26
import SwiftUI
import WebKit

// MARK: - Login Window

struct LoginWindowView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
            }

            LoginWebView(webView: viewModel.webView)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.popupWebView != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.closePopup()
                }
            }
        )) {
            if let popup = viewModel.popupWebView {
                PopupSheetView(webView: popup) {
                    viewModel.closePopup()
                }
            }
        }
    }
}

// MARK: - OAuth Popup Sheet

struct PopupSheetView: View {
    let webView: WKWebView
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                Button("Close") { onClose() }
            }
            PopupWebViewWrapper(webView: webView)
        }
        .padding()
        .frame(minWidth: 520, minHeight: 640)
    }
}

struct PopupWebViewWrapper: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
