// meta: created=2026-02-21 updated=2026-02-23 checked=never
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
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - Menu Content

private struct MenuContent: View {
    @ObservedObject var viewModel: UsageViewModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        if let fiveH = viewModel.fiveHourPercent {
            if let remaining = viewModel.fiveHourRemainingText {
                Text("5-hour: \(fiveH, specifier: "%.1f")%  (resets in \(remaining))")
            } else {
                Text("5-hour: \(fiveH, specifier: "%.1f")%")
            }
        }
        if let sevenD = viewModel.sevenDayPercent {
            if let remaining = viewModel.sevenDayRemainingText {
                Text("7-day: \(sevenD, specifier: "%.1f")%  (resets in \(remaining))")
            } else {
                Text("7-day: \(sevenD, specifier: "%.1f")%")
            }
        }
        if let error = viewModel.error {
            Text("Error: \(error)")
                .foregroundColor(.red)
        }

        Divider()

        if viewModel.isLoggedIn {
            Button("Sign Out") {
                viewModel.signOut()
            }
        } else {
            Button {
                openWindow(id: "login")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Text("Sign In...")
                    .foregroundColor(.red)
            }
        }

        Button("Refresh") {
            viewModel.fetch()
        }
        .disabled(viewModel.isFetching)

        Divider()

        Text("Open in Browser")
            .foregroundColor(.secondary)

        Button("Usage Page") {
            if let url = URL(string: "https://claude.ai/settings/billing") {
                NSWorkspace.shared.open(url)
            }
        }

        Button("Analysis") {
            AnalysisExporter.exportAndOpen()
        }

        Divider()

        Menu("Graph Settings") {
            Toggle("Show 5-hour", isOn: Binding(
                get: { viewModel.settings.showHourlyGraph },
                set: { viewModel.setShowHourlyGraph($0) }
            ))
            Toggle("Show 7-day", isOn: Binding(
                get: { viewModel.settings.showWeeklyGraph },
                set: { viewModel.setShowWeeklyGraph($0) }
            ))

            Divider()

            Menu("Chart Width") {
                let current = viewModel.settings.chartWidth
                ForEach(AppSettings.chartWidthPresets, id: \.self) { width in
                    Button("\(width)pt") {
                        viewModel.setChartWidth(width)
                    }
                    .badge(current == width ? "✓" : "")
                }
            }

            Divider()

            Menu("5-hour Color") {
                ForEach(ChartColorPreset.allCases, id: \.self) { preset in
                    Button(preset.displayName) {
                        viewModel.setHourlyColorPreset(preset)
                    }
                    .badge(viewModel.settings.hourlyColorPreset == preset ? "✓" : "")
                }
            }
            Menu("7-day Color") {
                ForEach(ChartColorPreset.allCases, id: \.self) { preset in
                    Button(preset.displayName) {
                        viewModel.setWeeklyColorPreset(preset)
                    }
                    .badge(viewModel.settings.weeklyColorPreset == preset ? "✓" : "")
                }
            }
        }

        Menu("Refresh Interval") {
            let current = viewModel.settings.refreshIntervalMinutes

            Button("Off") {
                viewModel.setRefreshInterval(minutes: 0)
            }
            .badge(current == 0 ? "✓" : "")

            Divider()

            ForEach(AppSettings.presets, id: \.self) { minutes in
                Button("\(minutes) min") {
                    viewModel.setRefreshInterval(minutes: minutes)
                }
                .badge(current == minutes ? "✓" : "")
            }

            Divider()

            Button("Custom...") {
                promptCustomInterval(current: current) { minutes in
                    viewModel.setRefreshInterval(minutes: minutes)
                }
            }
            if current > 0, !AppSettings.presets.contains(current) {
                Text("Current: \(current) min ✓")
            }
        }

        Toggle("Start at Login", isOn: Binding(
            get: { viewModel.settings.startAtLogin },
            set: { _ in viewModel.toggleStartAtLogin() }
        ))

        Divider()

        Button("Quit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

// MARK: - Custom Interval Prompt

private func promptCustomInterval(current: Int, onSet: @escaping (Int) -> Void) {
    let alert = NSAlert()
    alert.messageText = "Custom Refresh Interval"
    alert.informativeText = "Enter interval in minutes (1 or more, 0 to disable):"
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")

    let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
    input.stringValue = current > 0 ? "\(current)" : ""
    input.placeholderString = "minutes"
    alert.accessoryView = input

    NSApp.activate(ignoringOtherApps: true)
    let response = alert.runModal()
    if response == .alertFirstButtonReturn, let minutes = Int(input.stringValue), minutes >= 0 {
        onSet(minutes)
    }
}

// MARK: - Login Window

private struct LoginWindowView: View {
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

private struct PopupSheetView: View {
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

private struct PopupWebViewWrapper: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - Menu Bar Label (mini graphs)

private struct MenuBarLabel: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        let image = renderGraphs()
        Image(nsImage: image)
    }

    private func renderGraphs() -> NSImage {
        let s = viewModel.settings
        let graphCount = (s.showHourlyGraph ? 1 : 0) + (s.showWeeklyGraph ? 1 : 0)

        let content: AnyView
        if graphCount > 0 {
            content = AnyView(MenuBarGraphsContent(viewModel: viewModel))
        } else {
            content = AnyView(
                Text(viewModel.statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
            )
        }

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2.0
        guard let cgImage = renderer.cgImage else {
            return NSImage(size: NSSize(width: 80, height: 18))
        }
        let size = NSSize(
            width: CGFloat(cgImage.width) / 2.0,
            height: CGFloat(cgImage.height) / 2.0
        )
        return NSImage(cgImage: cgImage, size: size)
    }
}

private struct MenuBarGraphsContent: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        let s = viewModel.settings
        let loggedIn = viewModel.isLoggedIn
        HStack(spacing: 4) {
            if s.showHourlyGraph {
                MiniUsageGraph(
                    history: viewModel.fiveHourHistory,
                    windowSeconds: 5 * 3600,
                    resetsAt: viewModel.fiveHourResetsAt,
                    areaColor: s.hourlyColorPreset.color,
                    areaOpacity: 0.7,
                    divisions: 5,
                    chartWidth: CGFloat(s.chartWidth),
                    isLoggedIn: loggedIn
                )
            }
            if s.showWeeklyGraph {
                MiniUsageGraph(
                    history: viewModel.sevenDayHistory,
                    windowSeconds: 7 * 24 * 3600,
                    resetsAt: viewModel.sevenDayResetsAt,
                    areaColor: s.weeklyColorPreset.color,
                    areaOpacity: 0.65,
                    divisions: 7,
                    chartWidth: CGFloat(s.chartWidth),
                    isLoggedIn: loggedIn
                )
            }
        }
    }
}

private struct MiniUsageGraph: View {
    let history: [UsageStore.DataPoint]
    let windowSeconds: TimeInterval
    let resetsAt: Date?
    let areaColor: Color
    let areaOpacity: Double
    let divisions: Int
    let chartWidth: CGFloat
    let isLoggedIn: Bool

    private static let bgColor = Color(red: 0x12/255, green: 0x12/255, blue: 0x12/255)
    private static let bgColorSignedOut = Color(red: 0x3A/255, green: 0x10/255, blue: 0x10/255)
    private static let tickColor = Color.white.opacity(0.07)
    private static let usageLineColor = Color.white.opacity(0.3)
    private static let noDataFill = Color.white.opacity(0.06)

    private func xPosition(for timestamp: Date, windowStart: Date) -> Double {
        let elapsed = timestamp.timeIntervalSince(windowStart)
        return min(max(elapsed / windowSeconds, 0.0), 1.0)
    }

    private func usageValue(from point: UsageStore.DataPoint) -> Double? {
        if windowSeconds <= 5 * 3600 + 1 {
            return point.fiveHourPercent
        } else {
            return point.sevenDayPercent
        }
    }

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            // Background
            let bg = isLoggedIn ? Self.bgColor : Self.bgColorSignedOut
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(bg))

            // Determine window start
            let windowStart: Date
            if let resetsAt {
                windowStart = resetsAt.addingTimeInterval(-windowSeconds)
            } else if let first = history.first {
                windowStart = first.timestamp
            } else {
                return
            }

            // Time division ticks
            for i in 1..<divisions {
                let x = CGFloat(i) / CGFloat(divisions) * w
                var tickPath = Path()
                tickPath.move(to: CGPoint(x: x, y: 0))
                tickPath.addLine(to: CGPoint(x: x, y: h))
                context.stroke(tickPath, with: .color(Self.tickColor), lineWidth: 0.5)
            }

            // Build points (skip data before window start)
            var points: [(x: CGFloat, y: CGFloat)] = []
            for dp in history {
                guard dp.timestamp >= windowStart else { continue }
                guard let usage = usageValue(from: dp) else { continue }
                let xFrac = xPosition(for: dp.timestamp, windowStart: windowStart)
                let yFrac = min(usage / 100.0, 1.0)
                points.append((x: CGFloat(xFrac) * w, y: h - CGFloat(yFrac) * h))
            }

            guard !points.isEmpty else { return }

            // No-data gray fill: window start → first data point
            if points[0].x > 1 {
                context.fill(
                    Path(CGRect(x: 0, y: 0, width: points[0].x, height: h)),
                    with: .color(Self.noDataFill)
                )
            }

            // No-data gray fill: last data point → current time
            let now = Date()
            let nowElapsed = now.timeIntervalSince(windowStart)
            let nowXFrac = min(max(nowElapsed / windowSeconds, 0.0), 1.0)
            let nowX = CGFloat(nowXFrac) * w
            let lastX = points.last!.x
            if nowX > lastX + 1 {
                context.fill(
                    Path(CGRect(x: lastX, y: 0, width: nowX - lastX, height: h)),
                    with: .color(Self.noDataFill)
                )
            }

            // Area fill (step interpolation — usage is constant between measurements)
            var areaPath = Path()
            areaPath.move(to: CGPoint(x: points[0].x, y: h))
            for (i, p) in points.enumerated() {
                if i > 0 {
                    areaPath.addLine(to: CGPoint(x: p.x, y: points[i-1].y))
                }
                areaPath.addLine(to: CGPoint(x: p.x, y: p.y))
            }
            areaPath.addLine(to: CGPoint(x: points.last!.x, y: h))
            areaPath.closeSubpath()
            context.fill(areaPath, with: .color(areaColor.opacity(areaOpacity)))

            // Usage level: white dashed horizontal line
            let usageY = points.last!.y
            var usageLine = Path()
            usageLine.move(to: CGPoint(x: 0, y: usageY))
            usageLine.addLine(to: CGPoint(x: w, y: usageY))
            context.stroke(
                usageLine,
                with: .color(Self.usageLineColor),
                style: StrokeStyle(lineWidth: 0.5, dash: [2, 2])
            )
        }
        .frame(width: chartWidth, height: 18)
    }
}
