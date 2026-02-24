// meta: created=2026-02-21 updated=2026-02-21 checked=never
import SwiftUI
import WidgetKit
import WeatherCCShared

struct WidgetLargeView: View {
    let snapshot: UsageSnapshot?

    private static let fiveHourColor = Color(red: 100/255, green: 180/255, blue: 255/255)
    private static let sevenDayColor = Color(red: 255/255, green: 130/255, blue: 180/255)

    var body: some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: 10) {
                Text("Claude Usage")
                    .font(.headline)

                usageBlock(
                    title: "5-hour Usage",
                    percent: snapshot.fiveHourPercent,
                    resetsAt: snapshot.fiveHourResetsAt,
                    history: snapshot.fiveHourHistory,
                    windowSeconds: 5 * 3600,
                    color: Self.fiveHourColor,
                    opacity: 0.7,
                    predictCost: snapshot.predictFiveHourCost
                )

                usageBlock(
                    title: "7-day Usage",
                    percent: snapshot.sevenDayPercent,
                    resetsAt: snapshot.sevenDayResetsAt,
                    history: snapshot.sevenDayHistory,
                    windowSeconds: 7 * 24 * 3600,
                    color: Self.sevenDayColor,
                    opacity: 0.65,
                    predictCost: snapshot.predictSevenDayCost
                )

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        } else {
            notFetchedView
        }
    }

    @ViewBuilder
    private func usageBlock(
        title: String,
        percent: Double?,
        resetsAt: Date?,
        history: [HistoryPoint],
        windowSeconds: TimeInterval,
        color: Color,
        opacity: Double,
        predictCost: Double?
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            WidgetMiniGraph(
                label: title,
                history: history,
                windowSeconds: windowSeconds,
                resetsAt: resetsAt,
                areaColor: color,
                areaOpacity: opacity,
                isLoggedIn: snapshot?.isLoggedIn ?? true
            )
            .frame(height: 48)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack(spacing: 8) {
                if let percent {
                    Text(String(format: "%.1f%%", percent))
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                }
                if let resetsAt {
                    Text("resets \(remainingText(resetsAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let cost = predictCost {
                    Text(String(format: "Est. $%.2f", cost))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var notFetchedView: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Not fetched yet")
                .font(.body)
                .foregroundStyle(.secondary)
            Text("Open WeatherCC to sign in")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func remainingText(_ date: Date) -> String {
        let text = DisplayHelpers.remainingText(until: date)
        return text == "expired" ? text : "in " + text
    }
}
