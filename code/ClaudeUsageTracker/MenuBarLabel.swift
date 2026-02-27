// meta: created=2026-02-26 updated=2026-02-26 checked=2026-02-26
import SwiftUI

// MARK: - Menu Bar Label (mini graphs)

struct MenuBarLabel: View {
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

struct MenuBarGraphsContent: View {
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
