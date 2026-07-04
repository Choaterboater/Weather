import SwiftUI
import WidgetKit

/// One timeline entry: the bite reading to show at a given moment.
struct BiteEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// Feeds the widget from the shared snapshot the app publishes. The app nudges
/// reloads whenever the score changes; the timeline also refreshes periodically
/// as a backstop.
struct BiteTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> BiteEntry {
        BiteEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (BiteEntry) -> Void) {
        completion(BiteEntry(date: Date(), snapshot: WidgetSnapshotStore.read() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BiteEntry>) -> Void) {
        let entry = BiteEntry(date: Date(), snapshot: WidgetSnapshotStore.read() ?? .placeholder)
        let refresh = Calendar.current.date(byAdding: .hour, value: 3, to: Date())
            ?? Date().addingTimeInterval(3 * 3600)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

struct BiteWidget: Widget {
    let kind = "BiteWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BiteTimelineProvider()) { entry in
            BiteWidgetView(snapshot: entry.snapshot)
                .containerBackground(Ink.abyss, for: .widget)
        }
        .configurationDisplayName("Bite Score")
        .description("Today's bite score for your active spot.")
        .supportedFamilies([.systemSmall])
    }
}
