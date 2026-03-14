// meta: created=2026-02-21 updated=2026-03-15 checked=2026-03-03
import SwiftUI
import WidgetKit
import ClaudeUsageTrackerShared

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
}

struct UsageTimelineProvider: TimelineProvider {
    typealias Entry = UsageEntry

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview {
            completion(UsageEntry(date: Date(), snapshot: .placeholder))
            return
        }
        let snapshot = UsageReader.load()
        completion(UsageEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let snapshot = UsageReader.load()
        let now = Date()
        var entries = [UsageEntry(date: now, snapshot: snapshot)]

        // Add a future entry at the earliest reset time so the widget
        // refreshes automatically when a usage window resets.
        if let s = snapshot {
            let resetDates = [s.fiveHourResetsAt, s.sevenDayResetsAt].compactMap { $0 }.filter { $0 > now }
            if let earliest = resetDates.min() {
                entries.append(UsageEntry(date: earliest, snapshot: snapshot))
            }
        }

        completion(Timeline(entries: entries, policy: .never))
    }
}

struct UsageWidgetEntryView: View {
    var entry: UsageEntry

    var body: some View {
        WidgetMediumView(snapshot: entry.snapshot)
    }
}

struct UsageWidget: Widget {
    let kind = "ClaudeUsageTrackerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageTimelineProvider()) { entry in
            UsageWidgetEntryView(entry: entry)
                .widgetURL(URL(string: "claudeusagetracker://analysis"))
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Claude Usage")
        .description("Monitor Claude Code usage limits")
        .supportedFamilies([.systemMedium])
    }
}
