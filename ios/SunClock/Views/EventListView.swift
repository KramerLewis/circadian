import SunCore
import SwiftUI

/// Stage 1: today's solar events for a fixed location. Location services and the
/// dial arrive in stage 2.
struct EventListView: View {
    var coordinate = Coordinate(latitude: 47.61, longitude: -122.33)
    var placeName = "Seattle"

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                let day = SolarCalculator.solarDay(containing: context.date, at: coordinate)
                List {
                    Section {
                        LabeledContent("Solar time", value: solarTimeText(at: context.date))
                    }
                    Section("Today") {
                        ForEach(day.events) { item in
                            LabeledContent(item.event.displayName, value: timeText(item.time))
                        }
                    }
                }
                .navigationTitle(placeName)
            }
        }
    }

    private func solarTimeText(at date: Date) -> String {
        let minutes = Int(SolarCalculator.apparentSolarMinutes(at: date, longitude: coordinate.longitude))
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private func timeText(_ time: EventTime) -> String {
        switch time {
        case .at(let date): date.formatted(date: .omitted, time: .shortened)
        case .sunAlwaysAbove: "Sun stays above"
        case .sunAlwaysBelow: "Sun stays below"
        }
    }
}

#Preview {
    EventListView()
}
