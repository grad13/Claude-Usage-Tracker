// meta: created=2026-02-21 updated=2026-02-23 checked=never
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
        let snapshot = SnapshotStore.load()
        completion(UsageEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let snapshot = SnapshotStore.load()
        let entry = UsageEntry(date: Date(), snapshot: snapshot)
        let nextUpdate = Date().addingTimeInterval(5 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct UsageWidgetEntryView: View {
    var entry: UsageEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            WidgetSmallView(snapshot: entry.snapshot)
        case .systemMedium:
            WidgetMediumView(snapshot: entry.snapshot)
        case .systemLarge:
            WidgetLargeView(snapshot: entry.snapshot)
        default:
            WidgetSmallView(snapshot: entry.snapshot)
        }
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
