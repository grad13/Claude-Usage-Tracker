// meta: created=2026-02-21 updated=2026-03-15 checked=2026-03-03
import AppIntents
import SwiftUI
import WidgetKit
import ClaudeUsageTrackerShared

struct WidgetMediumView: View {
    let snapshot: UsageSnapshot?
    @Environment(\.colorScheme) private var envColorScheme

    private var resolvedColorScheme: ColorScheme {
        WidgetColorThemeResolver.resolve(environment: envColorScheme)
    }

    private static let defaultFiveHourColor = Color(red: 100/255, green: 180/255, blue: 255/255)
    private static let defaultSevenDayColor = Color(red: 255/255, green: 130/255, blue: 180/255)

    private var fiveHourColor: Color {
        WidgetColorThemeResolver.resolveChartColor(forKey: "hourly_color_preset", default: Self.defaultFiveHourColor)
    }
    private var sevenDayColor: Color {
        WidgetColorThemeResolver.resolveChartColor(forKey: "weekly_color_preset", default: Self.defaultSevenDayColor)
    }

    private let footerHeight: CGFloat = 18

    var body: some View {
        if let snapshot {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        usageSection(
                            label: "5h",
                            percent: snapshot.fiveHourPercent,
                            resetsAt: snapshot.fiveHourResetsAt,
                            history: snapshot.fiveHourHistory,
                            windowSeconds: 5 * 3600,
                            color: fiveHourColor,
                            opacity: 0.7
                        )

                        usageSection(
                            label: "7d",
                            percent: snapshot.sevenDayPercent,
                            resetsAt: snapshot.sevenDayResetsAt,
                            history: snapshot.sevenDayHistory,
                            windowSeconds: 7 * 24 * 3600,
                            color: sevenDayColor,
                            opacity: 0.65
                        )
                    }
                    .frame(height: geo.size.height - footerHeight)

                    footerRow(timestamp: snapshot.timestamp)
                        .frame(height: footerHeight)
                        .background(Color.red)
                }
            }
        } else {
            notFetchedView
        }
    }

    @ViewBuilder
    private func usageSection(
        label: String,
        percent: Double?,
        resetsAt: Date?,
        history: [HistoryPoint],
        windowSeconds: TimeInterval,
        color: Color,
        opacity: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            WidgetMiniGraph(
                label: label,
                history: history,
                windowSeconds: windowSeconds,
                resetsAt: resetsAt,
                areaColor: color,
                areaOpacity: opacity,
                isLoggedIn: snapshot?.isLoggedIn ?? true,
                colorScheme: resolvedColorScheme
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            if let resetsAt {
                GeometryReader { geo in
                    let xFrac = GraphCalc.nowXFraction(resetsAt: resetsAt, windowSeconds: windowSeconds)
                    Text(DisplayHelpers.remainingText(until: resetsAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .position(x: xFrac * geo.size.width, y: geo.size.height / 2)
                }
                .frame(height: 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func footerRow(timestamp: Date) -> some View {
        let intervalMinutes = AppGroupConfig.settingsInt(forKey: "refresh_interval_minutes") ?? 5
        let nextRefresh = timestamp.addingTimeInterval(Double(intervalMinutes) * 60)

        HStack(spacing: 6) {
            Spacer(minLength: 0)

            HStack(spacing: 3) {
                Text("update")
                Text(timestamp, style: .time)
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)

            HStack(spacing: 3) {
                Text("Next")
                Text(nextRefresh, style: .relative)
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)

            Button(intent: RefreshIntent()) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .frame(height: 18)
    }

    private var notFetchedView: some View {
        VStack(spacing: 4) {
            Image(systemName: "chart.bar.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Not fetched")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func nowXFraction(resetsAt: Date, windowSeconds: TimeInterval) -> CGFloat {
        CGFloat(GraphCalc.nowXFraction(resetsAt: resetsAt, windowSeconds: windowSeconds))
    }
}
