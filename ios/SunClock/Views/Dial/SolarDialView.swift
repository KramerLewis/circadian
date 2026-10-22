import SunCore
import SwiftUI

/// The 24-hour solar dial: solar noon at the top, solar midnight at the bottom,
/// twilight and daylight bands, event markers, and the "now" hand. Inside it, the moon
/// ring runs on the moon's own timeline (its highest point at the top).
struct SolarDialView: View {
    let model: DialModel
    let moon: MoonDialModel
    let now: Date
    let solarMinutes: Double
    let readout: SolarReadout
    let timeDisplay: TimeDisplay
    var special: SpecialDayText?
    /// Called when the center is tapped, to switch to the next display.
    var onCycleDisplay: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme

    /// Events that get a clock-time label outside the ring; the rest get a tick.
    private static let labeledEvents: Set<SolarEvent> = [.sunrise, .sunset, .solarNoon, .solarMidnight]

    var body: some View {
        Canvas { context, size in
            let geometry = Geometry(size: size)
            let dark = colorScheme == .dark
            if special?.style == .solstice {
                SkyRingRenderer.drawSpecialDay(.solstice, in: &context, ring: geometry.ring, innerRadius: geometry.moonInner, dark: dark)
            }
            drawRing(in: &context, geometry)
            SkyRingRenderer.drawMoonRing(in: &context, ring: geometry.moonRing, moon: moon, dark: dark, special: special?.style)
            if let style = special?.style, style == .equinox || style == .newMoon {
                SkyRingRenderer.drawSpecialDay(style, in: &context, ring: geometry.ring, innerRadius: geometry.moonInner, dark: dark)
            }
            drawHourTicks(in: &context, geometry)
            drawMarkers(in: &context, geometry)
            drawHand(in: &context, geometry)
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay {
            GeometryReader { proxy in
                // Keep the readout clear of the hour labels inside the ring.
                let width = Geometry(size: proxy.size).tickBase * 1.3
                VStack(spacing: 2) {
                    Text(centerText.primary)
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    Text(centerText.secondary)
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .contentTransition(.numericText())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: width)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
        .contentShape(.circle)
        .onTapGesture(perform: onCycleDisplay)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Solar dial")
        .accessibilityValue("\(centerText.primary) \(centerText.secondary). \(skySummary)")
        .accessibilityHint("Double-tap to change the time display.")
        .accessibilityAddTraits(.isButton)
    }

    /// What the rings show, for VoiceOver: "Sun 15 degrees up. Moon: waning gibbous, 84% lit, below the horizon."
    private var skySummary: String {
        let sun = Int(model.altitude(atAngle: model.nowAngle).rounded())
        let sunText = sun >= 0 ? "Sun \(sun) degrees up" : "Sun \(-sun) degrees below the horizon"
        let moonUp = moon.altitudeNow > moon.riseSetAltitude
        let lit = Int((moon.phase.illumination * 100).rounded())
        return "\(sunText). Moon: \(moon.phase.name.lowercased()), \(lit)% lit, \(moonUp ? "up" : "below the horizon")."
    }

    private var centerText: (primary: String, secondary: String) {
        DialCenterText.make(now: now, solarMinutes: solarMinutes, readout: readout, display: timeDisplay)
    }

    // MARK: Drawing

    private struct Geometry {
        let center: CGPoint
        let outer: CGFloat
        let inner: CGFloat

        init(size: CGSize) {
            let side = min(size.width, size.height)
            center = CGPoint(x: size.width / 2, y: size.height / 2)
            // Leave room outside the ring for event time labels.
            outer = side / 2 - 46
            inner = outer * 0.8
            moonOuter = inner - 5
            moonInner = moonOuter - outer * 0.1
        }

        let moonOuter: CGFloat
        let moonInner: CGFloat
        /// Hour ticks and labels sit just inside the moon ring.
        var tickBase: CGFloat { moonInner }

        var moonRing: SkyRingRenderer.Ring {
            SkyRingRenderer.Ring(center: center, inner: moonInner, outer: moonOuter)
        }

        /// Point at `radius` and dial angle `degrees` (clockwise from the top).
        func point(_ radius: CGFloat, _ degrees: Double) -> CGPoint {
            let t = degrees * .pi / 180
            return CGPoint(x: center.x + radius * sin(t), y: center.y - radius * cos(t))
        }

        var ring: SkyRingRenderer.Ring {
            SkyRingRenderer.Ring(center: center, inner: inner, outer: outer)
        }
    }

    private func drawRing(in context: inout GraphicsContext, _ g: Geometry) {
        SkyRingRenderer.drawSky(in: &context, ring: g.ring, model: model, dark: colorScheme == .dark, monochrome: false)
    }

    private func drawHourTicks(in context: inout GraphicsContext, _ g: Geometry) {
        for hour in 0..<24 {
            let angle = DialModel.angle(forSolarHour: Double(hour))
            let major = hour % 6 == 0
            var tick = Path()
            tick.move(to: g.point(g.tickBase - 2, angle))
            tick.addLine(to: g.point(g.tickBase - (major ? 9 : 5), angle))
            context.stroke(tick, with: .style(.secondary), lineWidth: major ? 2 : 1)
            if hour % 3 == 0 {
                let label = Text("\(hour)").font(.caption2.weight(major ? .semibold : .regular)).foregroundStyle(.secondary)
                context.draw(label, at: g.point(g.tickBase - 17, angle))
            }
        }
    }

    private func drawMarkers(in context: inout GraphicsContext, _ g: Geometry) {
        for marker in model.markers {
            if Self.labeledEvents.contains(marker.event) {
                let dot = g.point(g.outer + 6, marker.angle)
                context.fill(Path(ellipseIn: CGRect(x: dot.x - 3, y: dot.y - 3, width: 6, height: 6)), with: .style(.primary))
                let label = Text(marker.date, format: .dateTime.hour().minute())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                context.draw(label, at: g.point(g.outer + 24, marker.angle))
            } else {
                var tick = Path()
                tick.move(to: g.point(g.outer + 2, marker.angle))
                tick.addLine(to: g.point(g.outer + 8, marker.angle))
                context.stroke(tick, with: .style(.secondary), lineWidth: 1)
            }
        }
    }

    private func drawHand(in context: inout GraphicsContext, _ g: Geometry) {
        // A thin pointer across the ring for precision, under the glowing sun.
        var hand = Path()
        hand.move(to: g.point(g.inner - 4, model.nowAngle))
        hand.addLine(to: g.point(g.outer + 4, model.nowAngle))
        context.stroke(hand, with: .style(.primary.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        SkyRingRenderer.drawSun(in: &context, ring: g.ring, angle: model.nowAngle,
                                altitude: model.altitude(atAngle: model.nowAngle), monochrome: false)
    }
}
