// meta: created=2026-02-21 updated=2026-02-27 checked=2026-02-26
import SwiftUI
import WebKit

@main
struct ClaudeUsageTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(viewModel: viewModel)
        } label: {
            MenuBarLabel(viewModel: viewModel)
        }

        Window("ClaudeUsageTracker — Sign In", id: "login") {
            LoginWindowView(viewModel: viewModel)
        }
        .defaultSize(width: 900, height: 700)

        Window("ClaudeUsageTracker — Analysis", id: "analysis") {
            AnalysisWindowView()
        }
        .defaultSize(width: 1200, height: 800)
        .handlesExternalEvents(matching: ["analysis"])
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
