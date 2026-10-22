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

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let sunRadius = radius * thickness * 0.42
            // Inset so the sun's glow stays inside the frame.
            let outer = radius - sunRadius * 0.6
            let inner = outer * (1 - thickness)

            func point(_ r: CGFloat, _ degrees: Double) -> CGPoint {
                let t = degrees * .pi / 180
                return CGPoint(x: center.x + r * sin(t), y: center.y - r * cos(t))
            }
            func ring(_ start: Double, _ end: Double) -> Path {
                var path = Path()
                let steps = max(2, Int((end - start).rounded(.up)))
                let angles = (0...steps).map { start + (end - start) * Double($0) / Double(steps) }
                path.move(to: point(outer, angles[0]))
                for a in angles.dropFirst() { path.addLine(to: point(outer, a)) }
                for a in angles.reversed() { path.addLine(to: point(inner, a)) }
                path.closeSubpath()
                return path
            }

            context.fill(ring(-180, 180), with: .color(nightColor))
            for arc in model.arcs {
                context.fill(ring(arc.start, arc.end), with: .color(color(for: arc.band)))
            }

            // The sun: a soft glow around a bright disc, no outline.
            let sun = point((inner + outer) / 2, model.nowAngle)
            let glow = sunRadius * 2.2
            context.fill(
                Path(ellipseIn: CGRect(x: sun.x - glow, y: sun.y - glow, width: glow * 2, height: glow * 2)),
                with: .radialGradient(
                    Gradient(colors: [sunColor.opacity(0.55), sunColor.opacity(0)]),
                    center: sun, startRadius: sunRadius * 0.8, endRadius: glow
                )
            )
            context.fill(
                Path(ellipseIn: CGRect(x: sun.x - sunRadius, y: sun.y - sunRadius, width: sunRadius * 2, height: sunRadius * 2)),
                with: .color(sunColor)
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Sun ring")
    }

    private var nightColor: Color {
        monochrome ? .white.opacity(0.12) : DialPalette.night
    }

    private func color(for band: DialModel.Band) -> Color {
        guard monochrome else { return DialPalette.color(for: band) }
        return switch band {
        case .astronomicalTwilight: .white.opacity(0.22)
        case .nauticalTwilight: .white.opacity(0.32)
        case .civilTwilight: .white.opacity(0.45)
        case .day: .white.opacity(0.62)
        }
    }

    private var sunColor: Color {
        monochrome ? .white : DialPalette.sun
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
