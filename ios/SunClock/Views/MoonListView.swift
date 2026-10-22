import SunCore
import SwiftUI

/// The moon's phase and its events during the current solar day.
struct MoonListView: View {
    let day: SolarDay
    let coordinate: Coordinate
    let now: Date

    var body: some View {
        let phase = LunarCalculator.phase(at: now)
        let events = LunarCalculator.events(from: day.solarMidnight, to: day.nextSolarMidnight, at: coordinate)
        let next = events.first { $0.date > now }
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                MoonPhaseView(phase: phase, southern: coordinate.latitude < 0)
                    .frame(width: 56, height: 56)
                    .padding(-14)
                Text(phase.name)
                Spacer()
                Text("\(Int((phase.illumination * 100).rounded()))% lit")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            ForEach(events, id: \.self) { occurrence in
                Divider()
                HStack {
                    Label(occurrence.event.displayName, systemImage: occurrence.event.symbolName)
                    Spacer()
                    Text(occurrence.date.formatted(date: .omitted, time: .shortened))
                        .monospacedDigit()
                }
                .fontWeight(occurrence == next ? .semibold : .regular)
                .padding(.vertical, 10)
            }
            if !events.contains(where: { $0.event == .moonrise }) || !events.contains(where: { $0.event == .moonset }) {
                Divider()
                Text(missingNote(events))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            }
        }
        .padding(.horizontal)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    /// The moon's day is ~50 minutes longer than ours, so some days have no moonrise
    /// or no moonset.
    private func missingNote(_ events: [LunarCalculator.Occurrence]) -> String {
        let rises = events.contains { $0.event == .moonrise }
        let sets = events.contains { $0.event == .moonset }
        switch (rises, sets) {
        case (false, false): return "No moonrise or moonset today."
        case (false, true): return "No moonrise today."
        default: return "No moonset today."
        }
    }
}
