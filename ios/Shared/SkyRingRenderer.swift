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
        /// Degrees the whole dial is turned clockwise (see `DialOrientation`).
        var rotation: Double = 0

        var thickness: CGFloat { outer - inner }

        /// Point at `radius` and dial angle `degrees` (clockwise from the top).
        func point(_ radius: CGFloat, _ degrees: Double) -> CGPoint {
            let t = (degrees + rotation) * .pi / 180
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
            with: .conicGradient(Gradient(stops: stops), center: ring.center, angle: .degrees(-90 + ring.rotation)),
            style: evenOdd
        )
    }

    /// The sun at `angle`, sized to fit within the ring: a rendered disc (see
    /// `SunRenderer`) inside a two-layer corona tinted for its altitude, clipped to the
    /// ring. It dims and reddens as it sinks below the horizon.
    /// `eclipse`: the moon's offset and size relative to the sun's radius while it's
    /// crossing the sun, for a solar eclipse.
    static func drawSun(in context: inout GraphicsContext, ring: Ring, angle: Double, altitude: Double, monochrome: Bool,
                        eclipse: (offset: Double, moonScale: Double)? = nil) {
        let strength = altitude >= -0.833 ? 1 : max(0.3, 1 + (altitude + 0.833) / 25)
        let rgb = SkyGradient.sunColor(altitude: altitude).glow
        let glowColor = monochrome ? Color.white : Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
        let center = ring.point((ring.inner + ring.outer) / 2, angle)
        let radius = ring.thickness * 0.4
        let scale = context.environment.displayScale
        context.drawLayer { layer in
            layer.clip(to: ring.path, style: evenOdd)
            for (reach, opacity) in [(radius * 3.6, 0.35), (radius * 1.8, 0.6)] {
                layer.fill(
                    Path(ellipseIn: CGRect(x: center.x - reach, y: center.y - reach, width: reach * 2, height: reach * 2)),
                    with: .radialGradient(
                        Gradient(colors: [glowColor.opacity(opacity * strength), glowColor.opacity(0)]),
                        center: center, startRadius: radius * 0.9, endRadius: reach
                    )
                )
            }
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            if let image = SunRenderer.image(altitude: altitude, pixels: Int((radius * 2 * scale).rounded(.up)), monochrome: monochrome) {
                layer.draw(Image(decorative: image, scale: scale), in: rect)
            }
            if let eclipse, abs(eclipse.offset) < 1 + eclipse.moonScale {
                // The moon's silhouette crossing the sun.
                let mr = radius * eclipse.moonScale
                let mc = CGPoint(x: center.x + radius * eclipse.offset, y: center.y)
                let moonDisc = Path(ellipseIn: CGRect(x: mc.x - mr, y: mc.y - mr, width: mr * 2, height: mr * 2))
                if abs(eclipse.offset) < eclipse.moonScale - 1 {
                    // Totality: the corona flares around the black disc.
                    layer.fill(Path(ellipseIn: rect.insetBy(dx: -radius * 0.9, dy: -radius * 0.9)),
                               with: .radialGradient(Gradient(colors: [.white.opacity(0.85), .white.opacity(0)]),
                                                     center: center, startRadius: radius, endRadius: radius * 1.9))
                }
                layer.fill(moonDisc, with: .color(Color(red: 0.06, green: 0.06, blue: 0.09)))
            }
        }
    }

    // MARK: Special days

    /// Marks for solstices, equinoxes and new moons, drawn around and inside the dial.
    /// (Full moons are marked by `drawMoonRing`.)
    static func drawSpecialDay(_ style: SpecialDayText.Style, in context: inout GraphicsContext,
                               ring: Ring, innerRadius: CGFloat, dark: Bool) {
        switch style {
        case .solstice:
            // A golden halo around the sun ring, strongest at the top (solar noon).
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: ring.thickness * 0.35))
                let r = ring.outer + 3
                let halo = Path(ellipseIn: CGRect(x: ring.center.x - r, y: ring.center.y - r, width: r * 2, height: r * 2))
                layer.stroke(halo, with: .conicGradient(
                    Gradient(colors: [.orange.opacity(0.9), .yellow.opacity(0.35), .orange.opacity(0.15), .yellow.opacity(0.35), .orange.opacity(0.9)]),
                    center: ring.center, angle: .degrees(-90 + ring.rotation)
                ), lineWidth: ring.thickness * 0.45)
            }
        case .equinox:
            // The horizon: sunrise and sunset sit on the 6 and 18 marks today.
            let left = ring.point(ring.outer + 14, -90), right = ring.point(ring.outer + 14, 90)
            var line = Path()
            line.move(to: left)
            line.addLine(to: right)
            let gold = Color(red: 1, green: 0.84, blue: 0.55)
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 3))
                layer.stroke(line, with: .linearGradient(
                    Gradient(colors: [gold, gold.opacity(0.15), gold]), startPoint: left, endPoint: right
                ), lineWidth: 3)
                for point in [left, right] {
                    layer.fill(Path(ellipseIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)), with: .color(gold))
                }
            }
            context.stroke(line, with: .color(gold.opacity(0.7)), lineWidth: 1)
        case .newMoon:
            // A sprinkle of stars: the darkest skies of the month.
            let color = dark ? Color(red: 0.88, green: 0.9, blue: 1) : Color(red: 0.32, green: 0.36, blue: 0.62)
            var seed: UInt64 = 0x5EED_5EED
            func random() -> CGFloat {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return CGFloat(seed >> 33) / CGFloat(1 << 31)
            }
            for _ in 0..<70 {
                let angle = Double(random()) * 360
                let distance = sqrt(random()) * innerRadius * 0.92
                let point = ring.point(distance, angle)
                // Keep the center readout clear.
                if abs(point.y - ring.center.y) < innerRadius * 0.28, abs(point.x - ring.center.x) < innerRadius * 0.75 { continue }
                let size = 0.6 + random() * 1.4
                context.fill(Path(ellipseIn: CGRect(x: point.x - size, y: point.y - size, width: size * 2, height: size * 2)),
                             with: .color(color.opacity(0.35 + 0.6 * Double(random()))))
            }
        case .zenith, .fullMoon, .supermoon, .blueMoon, .lunarEclipse, .solarEclipse:
            break
        }
    }

    // MARK: Moon

    /// The moon's ring: on the sun ring's timeline, colored by the moon's altitude and
    /// fullness through the day, with ticks at moonrise and moonset.
    static func drawMoonRing(in context: inout GraphicsContext, ring: Ring, moon: MoonDialModel, dark: Bool,
                             special: SpecialDayText.Style? = nil, eclipseShadow: Double = 0,
                             placement: MoonPlacement = .clock) {
        let sky = placement == .sky
        // Full moons light up the ring; a supermoon most of all.
        let boost: Double = switch special {
        case .supermoon: 1.3
        case .fullMoon, .blueMoon: 1.15
        default: 1
        }
        let stops = (0...360).map { degree -> Gradient.Stop in
            // In the sky view the ring is directions round the sky (the moon's hour angle),
            // so the part above the horizon is centered on the top, like the sun's.
            let rgb = MoonGradient.color(
                altitude: sky ? moon.sky.altitude(atAngle: Double(degree), latitude: moon.latitude) : moon.altitude(atAngle: Double(degree)),
                riseSetAltitude: moon.riseSetAltitude,
                illumination: min(moon.phase.illumination * boost, 1.3),
                dark: dark
            )
            return Gradient.Stop(color: Color(red: min(rgb.red, 1), green: min(rgb.green, 1), blue: min(rgb.blue, 1)), location: Double(degree) / 360)
        }
        context.fill(
            ring.path,
            with: .conicGradient(Gradient(stops: stops), center: ring.center, angle: .degrees(-90 + ring.rotation)),
            style: evenOdd
        )
        let ticks = sky ? moon.sky.riseSetAngle.map { [-$0, $0] } ?? [] : moon.horizonMarkers.map(\.angle)
        for angle in ticks {
            var tick = Path()
            tick.move(to: ring.point(ring.inner, angle))
            tick.addLine(to: ring.point(ring.outer, angle))
            context.stroke(tick, with: .style(.secondary), lineWidth: 1)
        }
        let radius = ring.thickness * (special == .supermoon ? 0.95 : 0.75)
        let glow: Double = switch special {
        case .supermoon: 2.4
        case .fullMoon, .blueMoon: 1.8
        default: 1
        }
        drawMoon(in: &context, center: ring.point((ring.inner + ring.outer) / 2, sky ? moon.sky.nowAngle : moon.nowAngle),
                 radius: radius, phase: moon.phase, southern: moon.latitude < 0, monochrome: false,
                 glowScale: glow, blueGlow: special == .blueMoon, shadow: eclipseShadow)
    }

    /// The moon as it looks now (NASA texture lit for the phase, see `MoonRenderer`),
    /// with a soft glow that grows as the moon fills.
    static func drawMoon(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat,
                         phase: LunarCalculator.Phase, southern: Bool, monochrome: Bool,
                         glowScale: Double = 1, blueGlow: Bool = false, shadow: Double = 0) {
        let k = min(phase.illumination * glowScale, 2)
        let glow = radius * (1.9 + 0.5 * (glowScale - 1))
        let glowColor = monochrome ? Color.white
            : shadow > 0.3 ? Color(red: 0.85, green: 0.30, blue: 0.20)
            : blueGlow ? Color(red: 0.45, green: 0.62, blue: 1.0) : Color(red: 0.80, green: 0.84, blue: 0.97)
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2)),
            with: .radialGradient(
                Gradient(colors: [glowColor.opacity(0.10 + 0.35 * k), glowColor.opacity(0)]),
                center: center, startRadius: radius * 0.95, endRadius: glow
            )
        )
        let scale = context.environment.displayScale
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        if let image = MoonRenderer.image(phase: phase, southern: southern, pixels: Int((radius * 2 * scale).rounded(.up)),
                                          monochrome: monochrome, shadow: shadow) {
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
            // Leave room inside the frame for the glow (1.9 x the radius).
            let radius = min(size.width, size.height) / 2 / 2
            SkyRingRenderer.drawMoon(in: &context, center: CGPoint(x: size.width / 2, y: size.height / 2),
                                     radius: radius, phase: phase, southern: southern, monochrome: false)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("\(phase.name), \(Int((phase.illumination * 100).rounded()))% lit")
    }
}
