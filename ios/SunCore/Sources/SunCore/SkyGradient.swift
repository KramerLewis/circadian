import Foundation

/// Sky color as a continuous function of the sun's altitude, for painting the dial
/// ring: deep night below astronomical twilight, blues through nautical and civil
/// twilight, warm sunrise/sunset colors near the horizon, and pale light at the
/// sun's highest. The event thresholds (-18, -12, -6, -0.833 deg) are color stops.
public enum SkyGradient {
    public struct RGB: Hashable, Sendable {
        public var red: Double
        public var green: Double
        public var blue: Double

        public init(_ red: Double, _ green: Double, _ blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    /// (altitude in degrees, color), ascending.
    static let lightStops: [(Double, RGB)] = [
        (-18, RGB(0.10, 0.12, 0.26)),
        (-12, RGB(0.18, 0.21, 0.42)),
        (-6, RGB(0.33, 0.37, 0.66)),
        (-2.5, RGB(0.74, 0.52, 0.66)),
        (-0.833, RGB(0.96, 0.52, 0.36)),
        (4, RGB(1.00, 0.64, 0.30)),
        (12, RGB(1.00, 0.78, 0.40)),
        (30, RGB(1.00, 0.87, 0.50)),
        (55, RGB(1.00, 0.94, 0.66)),
        (75, RGB(1.00, 0.98, 0.84)),
    ]

    static let darkStops: [(Double, RGB)] = [
        (-18, RGB(0.05, 0.06, 0.15)),
        (-12, RGB(0.10, 0.12, 0.28)),
        (-6, RGB(0.21, 0.25, 0.48)),
        (-2.5, RGB(0.52, 0.36, 0.50)),
        (-0.833, RGB(0.80, 0.40, 0.26)),
        (4, RGB(0.88, 0.50, 0.22)),
        (12, RGB(0.90, 0.63, 0.28)),
        (30, RGB(0.92, 0.72, 0.36)),
        (55, RGB(0.95, 0.80, 0.48)),
        (75, RGB(0.97, 0.86, 0.62)),
    ]

    /// Brightness in 0...1, for single-color rendering (Lock Screen, tinted widgets).
    static let brightnessStops: [(Double, Double)] = [
        (-18, 0.10), (-12, 0.18), (-6, 0.30), (-0.833, 0.48), (10, 0.66), (35, 0.84), (70, 0.96),
    ]

    public static func color(altitude: Double, dark: Bool) -> RGB {
        let stops = dark ? darkStops : lightStops
        let (lower, upper, t) = bracket(altitude, stops.map(\.0))
        let a = stops[lower].1, b = stops[upper].1
        return RGB(a.red + (b.red - a.red) * t, a.green + (b.green - a.green) * t, a.blue + (b.blue - a.blue) * t)
    }

    public static func brightness(altitude: Double) -> Double {
        let (lower, upper, t) = bracket(altitude, brightnessStops.map(\.0))
        let a = brightnessStops[lower].1, b = brightnessStops[upper].1
        return a + (b - a) * t
    }

    /// Indices of the stops around `x` and the fraction between them; clamps at the ends.
    private static func bracket(_ x: Double, _ positions: [Double]) -> (Int, Int, Double) {
        guard x > positions[0] else { return (0, 0, 0) }
        guard let upper = positions.firstIndex(where: { $0 >= x }) else {
            return (positions.count - 1, positions.count - 1, 0)
        }
        let lower = upper - 1
        return (lower, upper, (x - positions[lower]) / (positions[upper] - positions[lower]))
    }
}

extension SolarCalculator {
    /// Altitude (degrees) of the sun's center at a given hour angle, for a declination.
    public static func altitude(hourAngle: Double, latitude: Double, declination: Double) -> Double {
        let lat = latitude * .pi / 180, dec = declination * .pi / 180, h = hourAngle * .pi / 180
        let s = sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(h)
        return asin(min(max(s, -1), 1)) * 180 / .pi
    }
}
