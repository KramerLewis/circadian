import SunCore
import SwiftUI

/// Today's solar events and the moon, as a list.
struct WatchEventsView: View {
    let place: SharedStore.StoredPlace
    let date: Date

    var body: some View {
        let day = SolarCalculator.solarDay(containing: date, at: place.coordinate)
        let phase = LunarCalculator.phase(at: date)
        let moonEvents = LunarCalculator.events(from: day.solarMidnight, to: day.nextSolarMidnight, at: place.coordinate)
        List {
            Section("Sun") {
                ForEach(day.events) { entry in
                    HStack {
                        Image(systemName: entry.event.symbolName)
                            .foregroundStyle(.orange)
                            .frame(width: 22)
                        Text(entry.event.displayName)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer()
                        Text(timeText(entry.time))
                            .monospacedDigit()
                            .foregroundStyle(entry.time.date == nil ? .secondary : .primary)
                    }
                    .font(.footnote)
                }
            }
            Section("Moon") {
                HStack {
                    MoonPhaseView(phase: phase, southern: place.latitude < 0)
                        .frame(width: 34, height: 34)
                        .padding(-6)
                    Text(phase.name)
                    Spacer()
                    Text("\(Int((phase.illumination * 100).rounded()))%")
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
                ForEach(moonEvents, id: \.self) { occurrence in
                    HStack {
                        Image(systemName: occurrence.event.symbolName)
                            .frame(width: 22)
                        Text(occurrence.event.displayName)
                        Spacer()
                        Text(occurrence.date.formatted(date: .omitted, time: .shortened))
                            .monospacedDigit()
                    }
                    .font(.footnote)
                }
            }
        }
        .navigationTitle("Today")
    }

    private func timeText(_ time: EventTime) -> String {
        switch time {
        case .at(let date): date.formatted(date: .omitted, time: .shortened)
        case .sunAlwaysAbove: "Up"
        case .sunAlwaysBelow: "Down"
        }
    }
}
