import SunCore
import SwiftUI
import WidgetKit

/// The complication for each watch face slot. Shared by the Watch widget extension
/// and the Watch app's debug gallery (used for CI screenshots).
struct ComplicationView: View {
    let family: WidgetFamily
    let place: SharedStore.StoredPlace?
    let date: Date
    var monochrome = false
    /// Countdowns drawn live by the system. Off for previews frozen at a fake date.
    var liveRelativeTimes = true

    var body: some View {
        if let place {
            switch family {
            case .accessoryCircular: circular(place)
            case .accessoryCorner: corner(place)
            case .accessoryRectangular: rectangular(place)
            case .accessoryInline: inline(place)
            default: circular(place)
            }
        } else {
            Image(systemName: "sun.horizon")
                .widgetLabel("Open SunClock")
                .accessibilityLabel("Open SunClock on iPhone to set a location")
        }
    }

    private func readout(_ place: SharedStore.StoredPlace) -> SolarReadout {
        SolarReadout(at: date, coordinate: place.coordinate)
    }

    /// Sun ring with the glowing sun, and the moon in its current phase in the middle.
    private func circular(_ place: SharedStore.StoredPlace) -> some View {
        let day = SolarCalculator.solarDay(containing: date, at: place.coordinate)
        return ZStack {
            AccessoryWidgetBackground()
            SunRingView(model: DialModel(day: day, now: date), monochrome: monochrome, thickness: 0.26)
                .padding(2)
            MoonPhaseView(phase: LunarCalculator.phase(at: date), southern: place.latitude < 0)
                .padding(15)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(nextLabel(readout(place)))
    }

    /// Daylight progress as a gauge, labelled with the next sunrise or sunset along the
    /// face's curve.
    private func corner(_ place: SharedStore.StoredPlace) -> some View {
        let r = readout(place)
        let next = r.nextHorizon
        return Gauge(value: daylightProgress(place)) {
            Image(systemName: next?.event.symbolName ?? "sun.max.fill")
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(.orange)
        .widgetLabel {
            if let next {
                Text("\(next.event.displayName.uppercased()) \(next.date.formatted(date: .omitted, time: .shortened))")
            } else {
                Text(r.polarCondition == .midnightSun ? "MIDNIGHT SUN" : "POLAR NIGHT")
            }
        }
    }

    /// Ring beside the next sunrise/sunset with a live countdown, and the moon. Also the
    /// Smart Stack card.
    private func rectangular(_ place: SharedStore.StoredPlace) -> some View {
        let r = readout(place)
        let day = SolarCalculator.solarDay(containing: date, at: place.coordinate)
        let phase = LunarCalculator.phase(at: date)
        return HStack(spacing: 8) {
            SunRingView(model: DialModel(day: day, now: date), monochrome: monochrome, thickness: 0.3)
            VStack(alignment: .leading, spacing: 0) {
                if let next = r.nextHorizon {
                    Text("\(next.event.displayName) \(next.date.formatted(date: .omitted, time: .shortened))")
                        .font(.headline)
                        .widgetAccentable()
                    countdown(next)
                        .monospacedDigit()
                } else {
                    Text(r.polarCondition == .midnightSun ? "Midnight sun" : "Polar night")
                        .font(.headline)
                }
                if let special = SpecialDayText.today(at: place.coordinate, on: date) {
                    Text(special.short)
                        .foregroundStyle(.orange)
                        .widgetAccentable()
                } else {
                    Text("Moon \(Int((phase.illumination * 100).rounded()))% · \(phase.isWaxing ? "waxing" : "waning")")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "1h 51m until sunset" (counts down live).
    private func inline(_ place: SharedStore.StoredPlace) -> some View {
        let r = readout(place)
        return Group {
            if let special = SpecialDayText.today(at: place.coordinate, on: date) {
                Label(special.short, systemImage: special.symbol)
            } else if let next = r.nextHorizon {
                Label {
                    Text("\(countdown(next)) to \(next.event.displayName.lowercased())")
                } icon: {
                    Image(systemName: next.event.symbolName)
                }
            } else {
                Label(r.polarCondition == .midnightSun ? "Midnight sun" : "Polar night", systemImage: "sun.max")
            }
        }
    }

    private func countdown(_ event: SolarReadout.Relative) -> Text {
        liveRelativeTimes ? Text(event.date, style: .relative) : Text(SolarFormat.duration(event.interval))
    }

    /// Fraction of today's daylight that has passed (0 before sunrise, 1 after sunset).
    private func daylightProgress(_ place: SharedStore.StoredPlace) -> Double {
        let day = SolarCalculator.solarDay(containing: date, at: place.coordinate)
        guard let rise = day[.sunrise].date, let set = day[.sunset].date, set > rise else {
            return day[.sunrise] == .sunAlwaysAbove ? 1 : 0
        }
        return min(max(date.timeIntervalSince(rise) / set.timeIntervalSince(rise), 0), 1)
    }

    private func nextLabel(_ r: SolarReadout) -> String {
        guard let next = r.nextHorizon else { return "Sun ring" }
        return "\(next.event.displayName) in \(SolarFormat.duration(next.interval))"
    }
}
