import SunCore
import SwiftUI

/// The 24-hour solar dial: solar noon at the top, solar midnight at the bottom,
/// twilight and daylight bands, event markers, and the "now" hand.
struct SolarDialView: View {
    let model: DialModel
    let now: Date
    let solarMinutes: Double

    /// Events that get a clock-time label outside the ring; the rest get a tick.
    private static let labeledEvents: Set<SolarEvent> = [.sunrise, .sunset, .solarNoon, .solarMidnight]

    var body: some View {
        Canvas { context, size in
            let geometry = Geometry(size: size)
            drawRing(in: &context, geometry)
            drawHourTicks(in: &context, geometry)
            drawMarkers(in: &context, geometry)
            drawHand(in: &context, geometry)
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay {
            GeometryReader { proxy in
                // Keep the readout clear of the hour labels inside the ring.
                let width = Geometry(size: proxy.size).inner * 1.25
                VStack(spacing: 2) {
                    Text(now, format: .dateTime.hour().minute())
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    Text("\(SolarFormat.solarClock(minutes: solarMinutes)) solar")
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: width)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Solar dial")
        .accessibilityValue("\(now.formatted(date: .omitted, time: .shortened)), \(SolarFormat.solarClock(minutes: solarMinutes)) solar time")
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
            inner = outer * 0.72
        }

        /// Point at `radius` and dial angle `degrees` (clockwise from the top).
        func point(_ radius: CGFloat, _ degrees: Double) -> CGPoint {
            let t = degrees * .pi / 180
            return CGPoint(x: center.x + radius * sin(t), y: center.y - radius * cos(t))
        }

        func ring(from start: Double, to end: Double) -> Path {
            var path = Path()
            let steps = max(2, Int((end - start).rounded(.up)))
            let angles = (0...steps).map { start + (end - start) * Double($0) / Double(steps) }
            path.move(to: point(outer, angles[0]))
            for a in angles.dropFirst() { path.addLine(to: point(outer, a)) }
            for a in angles.reversed() { path.addLine(to: point(inner, a)) }
            path.closeSubpath()
            return path
        }
    }

    private func drawRing(in context: inout GraphicsContext, _ g: Geometry) {
        context.fill(g.ring(from: -180, to: 180), with: .color(DialPalette.night))
        for arc in model.arcs {
            context.fill(g.ring(from: arc.start, to: arc.end), with: .color(DialPalette.color(for: arc.band)))
        }
    }

    private func drawHourTicks(in context: inout GraphicsContext, _ g: Geometry) {
        for hour in 0..<24 {
            let angle = DialModel.angle(forSolarHour: Double(hour))
            let major = hour % 6 == 0
            var tick = Path()
            tick.move(to: g.point(g.inner - 2, angle))
            tick.addLine(to: g.point(g.inner - (major ? 10 : 5), angle))
            context.stroke(tick, with: .style(.secondary), lineWidth: major ? 2 : 1)
            if hour % 3 == 0 {
                let label = Text("\(hour)").font(.caption2.weight(major ? .semibold : .regular)).foregroundStyle(.secondary)
                context.draw(label, at: g.point(g.inner - 20, angle))
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
        var hand = Path()
        hand.move(to: g.point(g.inner - 4, model.nowAngle))
        hand.addLine(to: g.point(g.outer + 4, model.nowAngle))
        context.stroke(hand, with: .style(.primary), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        let sun = g.point((g.inner + g.outer) / 2, model.nowAngle)
        let radius = (g.outer - g.inner) * 0.28
        let disc = Path(ellipseIn: CGRect(x: sun.x - radius, y: sun.y - radius, width: radius * 2, height: radius * 2))
        context.fill(disc, with: .color(DialPalette.sun))
        context.stroke(disc, with: .style(.primary), lineWidth: 2)
    }
}
