import SunCore
import SwiftUI

/// The dial's ring with no text: night, twilight and daylight bands, and the sun at
/// its current position. Used by the widgets (and shown in the app's debug gallery).
struct SunRingView: View {
    let model: DialModel
    /// Draw in shades of one color, for the Lock Screen and tinted Home Screen modes.
    var monochrome = false
    /// Ring thickness as a fraction of its outer radius.
    var thickness: CGFloat = 0.3
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let outer = min(size.width, size.height) / 2
            let ring = SkyRingRenderer.Ring(
                center: CGPoint(x: size.width / 2, y: size.height / 2),
                inner: outer * (1 - thickness),
                outer: outer
            )
            SkyRingRenderer.drawSky(in: &context, ring: ring, model: model, dark: colorScheme == .dark, monochrome: monochrome)
            SkyRingRenderer.drawSun(in: &context, ring: ring, angle: model.nowAngle,
                                    altitude: model.altitude(atAngle: model.nowAngle), monochrome: monochrome)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Sun ring")
    }
}

/// Widget content: the ring for a place and moment, or a prompt when the app hasn't
/// shared a location yet.
struct SunRingWidgetContent: View {
    let place: SharedStore.StoredPlace?
    let date: Date
    var monochrome = false
    var thickness: CGFloat = 0.3

    var body: some View {
        if let place {
            let day = SolarCalculator.solarDay(containing: date, at: place.coordinate)
            SunRingView(model: DialModel(day: day, now: date), monochrome: monochrome, thickness: thickness)
        } else {
            Image(systemName: "location.slash")
                .font(.title)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Open SunClock to set a location")
        }
    }
}

/// Medium widget content: the ring beside the next sunrise or sunset and the next
/// event of any kind. Relative times are rendered by the system, so they stay
/// current between timeline entries.
struct SunRingMediumContent: View {
    let place: SharedStore.StoredPlace?
    let date: Date
    var monochrome = false
    /// Let the system keep relative times live. Off for previews frozen at a fake date,
    /// where "live" would count from the real clock.
    var liveRelativeTimes = true

    var body: some View {
        if let place {
            let readout = SolarReadout(at: date, coordinate: place.coordinate)
            HStack(spacing: 16) {
                SunRingWidgetContent(place: place, date: date, monochrome: monochrome)
                VStack(alignment: .leading, spacing: 6) {
                    Text(place.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let next = readout.nextHorizon {
                        eventBlock(next, prominent: true)
                    } else if let polar = readout.polarCondition {
                        Label(polar == .midnightSun ? "Midnight sun" : "Polar night",
                              systemImage: polar == .midnightSun ? "sun.max.fill" : "moon.stars.fill")
                            .font(.headline)
                    }
                    if let other = readout.nextEvent, other.event != readout.nextHorizon?.event {
                        eventBlock(other, prominent: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            SunRingWidgetContent(place: nil, date: date)
        }
    }

    @ViewBuilder
    private func eventBlock(_ event: SolarReadout.Relative, prominent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(event.event.displayName, systemImage: event.event.symbolName)
                .font(prominent ? .headline : .subheadline)
            HStack(spacing: 4) {
                Text(event.date, style: .time)
                Text("·")
                if liveRelativeTimes {
                    Text(event.date, style: .relative)
                } else {
                    Text("in \(SolarFormat.duration(event.interval))")
                }
            }
            .font(prominent ? .subheadline : .caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }
}
