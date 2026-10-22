import SunCore
import SwiftUI
import WidgetKit

/// Home Screen and Lock Screen widget: the sun ring (no numbers), plus the next
/// events in the medium size.
struct SunRingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SunRing", provider: SunRingProvider()) { entry in
            SunRingWidgetView(entry: entry)
        }
        .configurationDisplayName("Sun Ring")
        .description("Where the sun is in its day.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular])
    }
}

nonisolated struct SunRingEntry: TimelineEntry {
    let date: Date
    let place: SharedStore.StoredPlace?
}

/// One entry every 10 minutes for the next 6 hours; then WidgetKit asks again. The
/// sun moves 2.5 degrees of the ring in 10 minutes, so steps are barely visible.
nonisolated struct SunRingProvider: TimelineProvider {
    static let step: TimeInterval = 10 * 60
    static let span: TimeInterval = 6 * 3600

    func placeholder(in context: Context) -> SunRingEntry {
        SunRingEntry(date: .now, place: SharedStore.StoredPlace(name: "Seattle", latitude: 47.61, longitude: -122.33))
    }

    func getSnapshot(in context: Context, completion: @escaping (SunRingEntry) -> Void) {
        completion(SunRingEntry(date: .now, place: SharedStore.loadPlace() ?? placeholder(in: context).place))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SunRingEntry>) -> Void) {
        let place = SharedStore.loadPlace()
        // Start on a step boundary so every widget on the device moves together.
        let start = Date(timeIntervalSince1970: (Date.now.timeIntervalSince1970 / Self.step).rounded(.down) * Self.step)
        let entries = stride(from: 0, through: Self.span, by: Self.step).map {
            SunRingEntry(date: start.addingTimeInterval($0), place: place)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct SunRingWidgetView: View {
    let entry: SunRingEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Group {
            if family == .systemMedium {
                SunRingMediumContent(place: entry.place, date: entry.date, monochrome: renderingMode != .fullColor)
            } else {
                SunRingWidgetContent(
                    place: entry.place,
                    date: entry.date,
                    monochrome: renderingMode != .fullColor,
                    thickness: family == .accessoryCircular ? 0.38 : 0.3
                )
            }
        }
        .padding(family == .accessoryCircular ? 2 : 0)
        .containerBackground(for: .widget) {
            if family == .accessoryCircular {
                AccessoryWidgetBackground()
            } else {
                Color(.systemBackground)
            }
        }
    }
}
