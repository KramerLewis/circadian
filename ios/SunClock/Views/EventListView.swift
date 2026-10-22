import SunCore
import SwiftUI

/// Today's events with clock times; the next upcoming event is highlighted.
struct EventListView: View {
    let day: SolarDay
    let now: Date

    var body: some View {
        let next = day.events.first { ($0.time.date ?? .distantPast) > now }?.event
        VStack(spacing: 0) {
            ForEach(day.events) { entry in
                HStack {
                    Label(entry.event.displayName, systemImage: entry.event.symbolName)
                    Spacer()
                    Text(timeText(entry.time))
                        .monospacedDigit()
                        .foregroundStyle(entry.time.date == nil ? .secondary : .primary)
                }
                .fontWeight(entry.event == next ? .semibold : .regular)
                .padding(.vertical, 10)
                if entry.event != SolarEvent.allCases.last {
                    Divider()
                }
            }
        }
        .padding(.horizontal)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private func timeText(_ time: EventTime) -> String {
        switch time {
        case .at(let date): date.formatted(date: .omitted, time: .shortened)
        case .sunAlwaysAbove: "Sun stays above"
        case .sunAlwaysBelow: "Sun stays below"
        }
    }
}
