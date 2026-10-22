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
    static func drawSun(in context: inout GraphicsContext, ring: Ring, angle: Double, monochrome: Bool) {
        let color = monochrome ? Color.white : DialPalette.sun
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
                with: .color(monochrome ? .white : Color(red: 1, green: 0.97, blue: 0.85))
            )
        }
    }
}
