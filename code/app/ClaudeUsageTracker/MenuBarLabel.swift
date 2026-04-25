// meta: updated=2026-04-25 05:00 checked=-
import SwiftUI

// MARK: - Menu Bar Label (mini graphs)

struct MenuBarLabel: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        let image = renderGraphs()
        Image(nsImage: image)
    }

    static func graphCount(settings: AppSettings) -> Int {
        (settings.showHourlyGraph ? 1 : 0) + (settings.showWeeklyGraph ? 1 : 0)
    }

    private func renderGraphs() -> NSImage {
        let s = viewModel.settings
        let graphCount = Self.graphCount(settings: s)
        let resolved = s.graphColorTheme.resolvedColorScheme()

        let content: AnyView
        if graphCount > 0 {
            content = AnyView(MenuBarGraphsContent(viewModel: viewModel, colorScheme: resolved))
        } else {
            content = AnyView(
                Text(viewModel.statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(resolved == .dark ? .white : .black)
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

struct MenuBarGraphsContent: View {
    @ObservedObject var viewModel: UsageViewModel
    let colorScheme: ColorScheme

    var body: some View {
        let s = viewModel.settings
        let loggedIn = viewModel.isLoggedIn
        // 7d window is session-scoped: bounds = [startedAt, resetsAt].
        // Fallback to 7-day fixed when no session data is available yet.
        let sevenDayWindowSeconds: TimeInterval = {
            if let started = viewModel.sevenDayStartedAt,
               let reset = viewModel.sevenDayResetsAt {
                return reset.timeIntervalSince(started)
            }
            return 7 * 24 * 3600
        }()
        HStack(spacing: 4) {
            if s.showHourlyGraph {
                MiniUsageGraph(
                    history: viewModel.fiveHourHistory,
                    windowSeconds: 5 * 3600,
                    resetsAt: viewModel.fiveHourResetsAt,
                    startedAt: nil,
                    areaColor: s.hourlyColorPreset.color,
                    areaOpacity: 0.7,
                    divisions: 5,
                    chartWidth: CGFloat(s.chartWidth),
                    isLoggedIn: loggedIn,
                    colorScheme: colorScheme
                )
            }
            if s.showWeeklyGraph {
                MiniUsageGraph(
                    history: viewModel.sevenDayHistory,
                    windowSeconds: sevenDayWindowSeconds,
                    resetsAt: viewModel.sevenDayResetsAt,
                    startedAt: viewModel.sevenDayStartedAt,
                    areaColor: s.weeklyColorPreset.color,
                    areaOpacity: 0.65,
                    divisions: 7,
                    chartWidth: CGFloat(s.chartWidth),
                    isLoggedIn: loggedIn,
                    colorScheme: colorScheme
                )
            }
        }
    }
}
