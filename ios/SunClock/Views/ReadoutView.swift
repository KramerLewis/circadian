import SunCore
import SwiftUI

/// "2h 14m after sunrise" / "4h 51m until sunset", plus the next event of any kind.
struct ReadoutView: View {
    let readout: SolarReadout

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch readout.polarCondition {
            case .midnightSun:
                row("sun.max.fill", "Midnight sun: the sun doesn't set today")
            case .polarNight:
                row("moon.stars.fill", "Polar night: the sun doesn't rise today")
            case nil:
                EmptyView()
            }
            if let previous = readout.previousHorizon {
                row(previous.event.symbolName, SolarFormat.relative(previous, isPast: true))
            }
            if let next = readout.nextHorizon {
                row(next.event.symbolName, SolarFormat.relative(next, isPast: false))
            }
            if let next = readout.nextEvent, next.event != readout.nextHorizon?.event {
                row("clock", "Next: \(next.event.displayName) in \(SolarFormat.duration(next.interval))")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.body.monospacedDigit())
    }
}

extension SolarEvent {
    var symbolName: String {
        switch self {
        case .solarMidnight: "moon.fill"
        case .astronomicalDawn, .nauticalDawn, .civilDawn: "sun.haze"
        case .sunrise: "sunrise.fill"
        case .solarNoon: "sun.max.fill"
        case .sunset: "sunset.fill"
        case .civilDusk, .nauticalDusk, .astronomicalDusk: "moon.haze"
        }
    }
}
