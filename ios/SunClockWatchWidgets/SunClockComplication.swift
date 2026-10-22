import SunCore
import SwiftUI
import WidgetKit

@main
struct SunClockWatchWidgets: WidgetBundle {
    var body: some Widget {
        SunClockComplication()
    }
}

/// Complications for every watch face slot, plus the Smart Stack card (rectangular).
struct SunClockComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SunClockComplication", provider: ComplicationProvider()) { entry in
            ComplicationEntryView(entry: entry)
                .containerBackground(for: .widget) { Color.black }
        }
        .configurationDisplayName("SunClock")
        .description("The sun ring, the moon, and the next sunrise or sunset.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

nonisolated struct ComplicationEntry: TimelineEntry {
    let date: Date
    let place: SharedStore.StoredPlace?
}

/// One entry every 10 minutes for 6 hours, like the iPhone widgets; countdowns are
/// drawn live by the system between entries.
nonisolated struct ComplicationProvider: TimelineProvider {
    static let step: TimeInterval = 10 * 60
    static let span: TimeInterval = 6 * 3600

    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: .now, place: SharedStore.StoredPlace(name: "Seattle", latitude: 47.61, longitude: -122.33))
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(ComplicationEntry(date: .now, place: SharedStore.loadPlace() ?? placeholder(in: context).place))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let place = SharedStore.loadPlace()
        let start = Date(timeIntervalSince1970: (Date.now.timeIntervalSince1970 / Self.step).rounded(.down) * Self.step)
        let entries = stride(from: 0, through: Self.span, by: Self.step).map {
            ComplicationEntry(date: start.addingTimeInterval($0), place: place)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct ComplicationEntryView: View {
    let entry: ComplicationEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        ComplicationView(family: family, place: entry.place, date: entry.date, monochrome: renderingMode != .fullColor)
    }
}
