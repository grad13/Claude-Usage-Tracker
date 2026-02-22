// meta: created=2026-02-21 updated=2026-02-22 checked=never
import SwiftUI
import WidgetKit
import WeatherCCShared

struct WidgetSmallView: View {
    let snapshot: UsageSnapshot?

    private static let fiveHourColor = Color(red: 100/255, green: 180/255, blue: 255/255)
    private static let sevenDayColor = Color(red: 255/255, green: 130/255, blue: 180/255)

    var body: some View {
        if let snapshot {
            VStack(spacing: 4) {
                usageSection(
                    label: "5h",
                    percent: snapshot.fiveHourPercent,
                    resetsAt: snapshot.fiveHourResetsAt,
                    history: snapshot.fiveHourHistory,
                    windowSeconds: 5 * 3600,
                    color: Self.fiveHourColor,
                    opacity: 0.7
                )

                usageSection(
                    label: "7d",
                    percent: snapshot.sevenDayPercent,
                    resetsAt: snapshot.sevenDayResetsAt,
                    history: snapshot.sevenDayHistory,
                    windowSeconds: 7 * 24 * 3600,
                    color: Self.sevenDayColor,
                    opacity: 0.65
                )
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
        WidgetMiniGraph(
            label: label,
            history: history,
            windowSeconds: windowSeconds,
            resetsAt: resetsAt,
            areaColor: color,
            areaOpacity: opacity,
            isLoggedIn: snapshot?.isLoggedIn ?? true
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 4))
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
    }
}
