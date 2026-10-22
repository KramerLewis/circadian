import SunCore
import SwiftUI

/// Draws the dial's ring: a sky gradient that follows the sun's altitude all the way
/// round, and the sun as a soft glowing disc that stays inside the ring.
/// Shared by the app's dial and the widgets.
enum SkyRingRenderer {
    struct Ring {
        var center: CGPoint
        var inner: CGFloat
        var outer: CGFloat

        var thickness: CGFloat { outer - inner }

        /// Point at `radius` and dial angle `degrees` (clockwise from the top).
        func point(_ radius: CGFloat, _ degrees: Double) -> CGPoint {
            let t = degrees * .pi / 180
            return CGPoint(x: center.x + radius * sin(t), y: center.y - radius * cos(t))
        }

        var path: Path {
            var path = Path()
            path.addEllipse(in: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2))
            path.addEllipse(in: CGRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2))
            return path
        }
    }

    private static let evenOdd = FillStyle(eoFill: true, antialiased: true)

    /// The ring filled with a conic gradient sampled every degree from the sun's
    /// altitude at that point of the day.
    static func drawSky(in context: inout GraphicsContext, ring: Ring, model: DialModel, dark: Bool, monochrome: Bool) {
        let stops = (0...360).map { degree -> Gradient.Stop in
            let altitude = model.altitude(atAngle: Double(degree))
            let color: Color
            if monochrome {
                color = .white.opacity(SkyGradient.brightness(altitude: altitude))
            } else {
                let rgb = SkyGradient.color(altitude: altitude, dark: dark)
                color = Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
            }
            return Gradient.Stop(color: color, location: Double(degree) / 360)
        }
        // Conic gradients start at 3 o'clock and run clockwise; -90 deg starts them at
        // the top, matching dial angles.
        context.fill(
            ring.path,
            with: .conicGradient(Gradient(stops: stops), center: ring.center, angle: .degrees(-90)),
            style: evenOdd
        )
    }

    /// The sun at `angle`, sized to fit within the ring, with its glow clipped to it.
    /// It dims as it sinks below the horizon (`altitude` in degrees).
    static func drawSun(in context: inout GraphicsContext, ring: Ring, angle: Double, altitude: Double, monochrome: Bool) {
        let strength = altitude >= -0.833 ? 1 : max(0.3, 1 + (altitude + 0.833) / 25)
        let color = (monochrome ? Color.white : DialPalette.sun).opacity(strength)
        let center = ring.point((ring.inner + ring.outer) / 2, angle)
        let radius = ring.thickness * 0.3
        context.drawLayer { layer in
            layer.clip(to: ring.path, style: evenOdd)
            let glow = ring.thickness * 0.9
            layer.fill(
                Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2)),
                with: .radialGradient(
                    Gradient(colors: [color.opacity(0.7), color.opacity(0)]),
                    center: center, startRadius: radius * 0.6, endRadius: glow
                )
            )
            layer.fill(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                with: .color((monochrome ? Color.white : Color(red: 1, green: 0.97, blue: 0.85)).opacity(strength))
            )
        }
    }

    // MARK: Moon

    /// The moon's ring: its own timeline (angle = the moon's hour angle), colored by
    /// the moon's altitude and fullness, with ticks at moonrise and moonset.
    static func drawMoonRing(in context: inout GraphicsContext, ring: Ring, moon: MoonDialModel, dark: Bool) {
        let stops = (0...360).map { degree -> Gradient.Stop in
            let rgb = MoonGradient.color(
                altitude: moon.altitude(atAngle: Double(degree)),
                riseSetAltitude: moon.riseSetAltitude,
                illumination: moon.phase.illumination,
                dark: dark
            )
            return Gradient.Stop(color: Color(red: rgb.red, green: rgb.green, blue: rgb.blue), location: Double(degree) / 360)
        }
        context.fill(
            ring.path,
            with: .conicGradient(Gradient(stops: stops), center: ring.center, angle: .degrees(-90)),
            style: evenOdd
        )
        if let rise = moon.riseSetAngle {
            for angle in [-rise, rise] {
                var tick = Path()
                tick.move(to: ring.point(ring.inner, angle))
                tick.addLine(to: ring.point(ring.outer, angle))
                context.stroke(tick, with: .style(.secondary), lineWidth: 1)
            }
        }
        let radius = ring.thickness * 0.75
        drawMoon(in: &context, center: ring.point((ring.inner + ring.outer) / 2, moon.nowAngle),
                 radius: radius, phase: moon.phase, southern: moon.latitude < 0, monochrome: false)
    }

    /// The moon as it looks now (NASA texture lit for the phase, see `MoonRenderer`),
    /// with a soft glow that grows as the moon fills.
    static func drawMoon(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat,
                         phase: LunarCalculator.Phase, southern: Bool, monochrome: Bool) {
        let k = phase.illumination
        let glow = radius * 1.9
        let glowColor = monochrome ? Color.white : Color(red: 0.80, green: 0.84, blue: 0.97)
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2)),
            with: .radialGradient(
                Gradient(colors: [glowColor.opacity(0.10 + 0.35 * k), glowColor.opacity(0)]),
                center: center, startRadius: radius * 0.95, endRadius: glow
            )
        )
        let scale = context.environment.displayScale
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        if let image = MoonRenderer.image(phase: phase, southern: southern, pixels: Int((radius * 2 * scale).rounded(.up)), monochrome: monochrome) {
            context.draw(Image(decorative: image, scale: scale), in: rect)
        }
    }
}

/// A moon glyph in its current phase.
struct MoonPhaseView: View {
    let phase: LunarCalculator.Phase
    var southern = false

    var body: some View {
        Canvas { context, size in
            // Leave room inside the frame for the glow.
            let radius = min(size.width, size.height) / 2 / 1.5
            SkyRingRenderer.drawMoon(in: &context, center: CGPoint(x: size.width / 2, y: size.height / 2),
                                     radius: radius, phase: phase, southern: southern, monochrome: false)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("\(phase.name), \(Int((phase.illumination * 100).rounded()))% lit")
    }
}
