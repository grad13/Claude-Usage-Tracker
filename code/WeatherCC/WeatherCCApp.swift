// meta: created=2026-02-21 updated=2026-02-26 checked=2026-02-26
import SwiftUI
import WebKit

@main
struct WeatherCCApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(viewModel: viewModel)
        } label: {
            MenuBarLabel(viewModel: viewModel)
        }

        Window("WeatherCC — Sign In", id: "login") {
            LoginWindowView(viewModel: viewModel)
        }
        .defaultSize(width: 900, height: 700)

        Window("WeatherCC — Analysis", id: "analysis") {
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
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString),
              url.scheme == "weathercc", url.host == "analysis" else { return }
        NSApp.activate(ignoringOtherApps: true)
    }
}
