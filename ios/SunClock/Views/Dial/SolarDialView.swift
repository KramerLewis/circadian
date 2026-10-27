import SunCore
import SwiftUI

/// The 24-hour solar dial: solar noon at the top, solar midnight at the bottom,
/// twilight and daylight bands, event markers, and the "now" hand. Inside it, the moon
/// ring shows when the moon is up on the same 24 hours, with ticks at moonrise and moonset.
struct SolarDialView: View {
    let model: DialModel
    let moon: MoonDialModel
    let now: Date
    let solarMinutes: Double
    let readout: SolarReadout
    let timeDisplay: TimeDisplay
    var special: SpecialDayText?
    var orientation: DialOrientation = .noonAtTop
    var moonPlacement: MoonPlacement = .clock
    var handColor: HandColor = .royalBlue
    var kanjiStyle: KanjiStyle = .molten
    /// Where the dial is drawn for; only needed to place the moon over the sun in a solar eclipse.
    var coordinate: Coordinate?
    /// Called when the center is tapped, to switch to the next display.
    var onCycleDisplay: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme

    /// Events that get a clock-time label outside the ring; the rest get a tick.
    private static let labeledEvents: Set<SolarEvent> = [.sunrise, .sunset, .solarNoon, .solarMidnight]

    var body: some View {
        Canvas { context, size in
            let geometry = Geometry(size: size, rotation: orientation.rotation(nowAngle: model.nowAngle))
            let dark = colorScheme == .dark
            if special?.style == .solstice {
                SkyRingRenderer.drawSpecialDay(.solstice, in: &context, ring: geometry.ring, innerRadius: geometry.moonInner, dark: dark)
            }
            drawRing(in: &context, geometry)
            SkyRingRenderer.drawMoonRing(in: &context, ring: geometry.moonRing, moon: moon, dark: dark, special: special?.style,
                                         eclipseShadow: special?.style == .lunarEclipse ? EclipseCalculator.umbralCoverage(at: now) : 0,
                                         placement: moonPlacement)
            if let style = special?.style, style == .equinox || style == .newMoon {
                SkyRingRenderer.drawSpecialDay(style, in: &context, ring: geometry.ring, innerRadius: geometry.moonInner, dark: dark)
            }
            if timeDisplay.hasSections {
                drawSectionTicks(in: &context, geometry)
            } else {
                drawHourTicks(in: &context, geometry)
            }
            drawMarkers(in: &context, geometry)
            SkyRingRenderer.drawSun(in: &context, ring: geometry.ring, angle: model.nowAngle,
                                    altitude: model.altitude(atAngle: model.nowAngle), monochrome: false,
                                    eclipse: special?.style == .solarEclipse ? solarEclipseOverlay : nil)
        }
        .aspectRatio(1, contentMode: .fit)
        // The hand runs beneath both rings, from inside the moon ring to past the sun ring.
        // It's its own layer so a shimmering hand animates without redrawing the dial.
        .background {
            HandLayer(nowAngle: model.nowAngle, rotation: orientation.rotation(nowAngle: model.nowAngle), color: handColor)
        }
        .overlay {
            if timeDisplay == .wadokei, let coordinate {
                let rotation = orientation.rotation(nowAngle: model.nowAngle)
                WadokeiLayer(hours: Wadokei.ring(at: now, coordinate: coordinate),
                             active: Wadokei.hour(at: now, coordinate: coordinate)?.kanji,
                             rotation: rotation, style: kanjiStyle) { size in
                    let g = Geometry(size: size, rotation: rotation)
                    return WadokeiLayer.Layout(center: g.center, ringRadius: g.outer + 18,
                                               kanjiSize: max(13, min(20, min(size.width, size.height) * 0.045)),
                                               centerRadius: g.moonInner)
                }
            }
        }
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
                // The wadokei's animal and kanji take the middle instead.
                .opacity(timeDisplay == .wadokei ? 0 : 1)
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

    /// The moon's position over the sun right now, during a solar eclipse.
    private var solarEclipseOverlay: (offset: Double, moonScale: Double)? {
        guard let coordinate else { return nil }
        let c = EclipseCalculator.solarCoverage(at: now, coordinate: coordinate)
        return (c.offset, c.moonScale)
    }

    private var centerText: (primary: String, secondary: String) {
        DialCenterText.make(now: now, solarMinutes: solarMinutes, readout: readout, display: timeDisplay, coordinate: coordinate)
    }

    // MARK: Drawing

    private struct Geometry {
        let center: CGPoint
        let outer: CGFloat
        let inner: CGFloat
        /// Degrees the dial is turned clockwise.
        let rotation: Double

        init(size: CGSize, rotation: Double = 0) {
            self.rotation = rotation
            let side = min(size.width, size.height)
            center = CGPoint(x: size.width / 2, y: size.height / 2)
            // Leave room outside the ring for event time labels, which sit beside the ring
            // at 3 and 9 o'clock when the dial turns.
            outer = side / 2 - 58
            inner = outer * 0.8
            moonOuter = inner - 5
            moonInner = moonOuter - outer * 0.1
        }

        let moonOuter: CGFloat
        let moonInner: CGFloat
        /// Hour ticks and labels sit just inside the moon ring.
        var tickBase: CGFloat { moonInner }

        var moonRing: SkyRingRenderer.Ring {
            SkyRingRenderer.Ring(center: center, inner: moonInner, outer: moonOuter, rotation: rotation)
        }

        /// Point at `radius` and dial angle `degrees` (clockwise from the top).
        func point(_ radius: CGFloat, _ degrees: Double) -> CGPoint {
            let t = (degrees + rotation) * .pi / 180
            return CGPoint(x: center.x + radius * sin(t), y: center.y - radius * cos(t))
        }

        var ring: SkyRingRenderer.Ring {
            SkyRingRenderer.Ring(center: center, inner: inner, outer: outer, rotation: rotation)
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
            // Skip a number that the turning dial would put under the center readout.
            let at = g.point(g.tickBase - 17, angle)
            let underReadout = abs(at.x - g.center.x) < g.tickBase * 0.65 + 12 && abs(at.y - g.center.y) < g.tickBase * 0.32
            if hour % 3 == 0, !underReadout {
                let label = Text("\(hour)").font(.caption2.weight(major ? .semibold : .regular)).foregroundStyle(.secondary)
                context.draw(label, at: at)
            }
        }
    }

    /// Ticks at the boundaries of the display's own sections (sun periods or wadokei hours),
    /// in place of the hour ticks.
    private func drawSectionTicks(in context: inout GraphicsContext, _ g: Geometry) {
        guard let coordinate else { return }
        let dates = switch timeDisplay {
        case .wadokei: Wadokei.hours(around: now, at: coordinate).map(\.start)
        case .roman: RomanHours.hours(around: now, at: coordinate).map(\.start)
        default: SunPeriods.boundaries(inDayContaining: now, at: coordinate)
        }
        for date in dates {
            let angle = DialModel.angle(for: date, longitude: coordinate.longitude)
            var tick = Path()
            tick.move(to: g.point(g.outer - 5, angle))
            tick.addLine(to: g.point(g.outer + 1, angle))
            context.stroke(tick, with: .style(HierarchicalShapeStyle.secondary.opacity(0.8)), lineWidth: 1)
        }
    }

    private func drawMarkers(in context: inout GraphicsContext, _ g: Geometry) {
        // The wadokei's kanji sit where the event labels go: keep just the four dots.
        let labels = timeDisplay != .wadokei
        for marker in model.markers {
            if !labels, !Self.labeledEvents.contains(marker.event) { continue }
            if Self.labeledEvents.contains(marker.event) {
                let dot = g.point(g.outer + 6, marker.angle)
                context.fill(Path(ellipseIn: CGRect(x: dot.x - 3, y: dot.y - 3, width: 6, height: 6)), with: .style(.primary))
                guard labels else { continue }
                let label = Text(marker.date, format: .dateTime.hour().minute())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                // Anchor the label on its inner edge, so it grows away from the ring at any
                // angle (and as the dial turns).
                let side = sin((marker.angle + g.rotation) * .pi / 180)
                let anchor: UnitPoint = side > 0.35 ? .leading : side < -0.35 ? .trailing : .center
                context.draw(label, at: g.point(g.outer + (abs(side) > 0.35 ? 12 : 20), marker.angle), anchor: anchor)
            } else {
                var tick = Path()
                tick.move(to: g.point(g.outer + 2, marker.angle))
                tick.addLine(to: g.point(g.outer + 8, marker.angle))
                context.stroke(tick, with: .style(.secondary), lineWidth: 1)
            }
        }
    }

    /// The "now" hand: a vivid glowing line in the chosen color.
    private struct HandLayer: View {
        let nowAngle: Double
        let rotation: Double
        let color: HandColor
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            if color.shimmers && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    canvas(phase: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                canvas(phase: nil)
            }
        }

        private func canvas(phase: Double?) -> some View {
            Canvas { context, size in
                let g = Geometry(size: size, rotation: rotation)
                let start = g.point(g.moonInner - 14, nowAngle), end = g.point(g.outer + 8, nowAngle)
                var hand = Path()
                hand.move(to: start)
                hand.addLine(to: end)
                let base = color.color(dark: colorScheme == .dark)
                let fill: GraphicsContext.Shading
                if color.shimmers {
                    // A bright band sweeps outward along the hand every two seconds.
                    let t = phase.map { ($0 / 2).truncatingRemainder(dividingBy: 1) } ?? 0.5
                    let stops = [
                        Gradient.Stop(color: HandColor.goldDeep, location: 0),
                        Gradient.Stop(color: base, location: max(0, t - 0.2)),
                        Gradient.Stop(color: HandColor.goldLight, location: t),
                        Gradient.Stop(color: base, location: min(1, t + 0.2)),
                        Gradient.Stop(color: HandColor.goldDeep, location: 1),
                    ]
                    fill = .linearGradient(Gradient(stops: stops), startPoint: start, endPoint: end)
                } else {
                    fill = .color(base)
                }
                context.drawLayer { glow in
                    glow.addFilter(.blur(radius: 5))
                    glow.stroke(hand, with: .color(base.opacity(color == .auto ? 0.5 : 0.9)),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round))
                }
                context.stroke(hand, with: fill, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
