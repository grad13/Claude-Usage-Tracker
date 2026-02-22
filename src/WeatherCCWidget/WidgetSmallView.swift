// meta: created=2026-02-21 updated=2026-02-21 checked=never
import SwiftUI
import WidgetKit
import WeatherCCShared

struct WidgetSmallView: View {
    let snapshot: UsageSnapshot?

    var body: some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: 6) {
                Text("Claude Usage")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                usageRow(label: "5h", percent: snapshot.fiveHourPercent, resetsAt: snapshot.fiveHourResetsAt)
                usageRow(label: "7d", percent: snapshot.sevenDayPercent, resetsAt: snapshot.sevenDayResetsAt)

                Spacer(minLength: 0)

                if let resetsAt = snapshot.fiveHourResetsAt {
                    let remaining = remainingText(resetsAt)
                    Text("resets \(remaining)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        } else {
            notFetchedView
        }
    }

    @ViewBuilder
    private func usageRow(label: String, percent: Double?, resetsAt: Date?) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)
            if let percent {
                Text(String(format: "%.1f%%", percent))
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
            } else {
                Text("--%")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
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

    private func remainingText(_ date: Date) -> String {
        let remaining = date.timeIntervalSinceNow
        guard remaining > 0 else { return "expired" }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours >= 24 {
            return "in \(hours / 24)d \(hours % 24)h"
        }
        return "in \(hours)h \(minutes)m"
    }
}
