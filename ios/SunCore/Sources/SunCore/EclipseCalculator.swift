import Foundation

/// Lunar and solar eclipses from the same sun and moon models as the rest of SunCore.
/// The reference implementation and fixture are shared/tools/generate_eclipse_fixtures.py;
/// against PyEphem, contact times agree within about a minute and magnitudes within 0.01.
public enum EclipseCalculator {
    // MARK: Lunar

    public struct LunarEclipse: Hashable, Sendable {
        public enum Kind: String, Sendable {
            /// Only Earth's faint outer shadow: a subtle dimming.
            case penumbral
            /// Part of the moon in Earth's dark inner shadow.
            case partial
            /// All of the moon in the inner shadow: a "blood moon".
            case total
        }

        public let kind: Kind
        public let greatest: Date
        /// Fraction of the moon's diameter inside the umbra at greatest eclipse.
        public let umbralMagnitude: Double
        public let penumbralMagnitude: Double
        /// Penumbral contacts (P1, P4): the whole eclipse.
        public let penumbralStart: Date
        public let penumbralEnd: Date
        /// Umbral contacts (U1, U4): the partial phases.
        public let partialStart: Date?
        public let partialEnd: Date?
        /// U2, U3: totality.
        public let totalStart: Date?
        public let totalEnd: Date?
    }

    /// The lunar eclipse at the full moon nearest `fullMoon`, if there is one.
    public static func lunarEclipse(near fullMoon: Date) -> LunarEclipse? {
        let greatest = minimize(near: fullMoon, span: 6 * 3600, step: 600) { lunarGeometry($0).separation }
        let g = lunarGeometry(greatest)
        let umbral = (g.umbra + g.moon - g.separation) / (2 * g.moon)
        let penumbral = (g.penumbra + g.moon - g.separation) / (2 * g.moon)
        guard penumbral > 0 else { return nil }

        func contacts(_ radius: @escaping (LunarGeometry) -> Double) -> (Date, Date)? {
            let f: (Date) -> Double = { let g = lunarGeometry($0); return g.separation - radius(g) }
            guard f(greatest) < 0 else { return nil }
            return (crossing(f, greatest.addingTimeInterval(-6 * 3600), greatest),
                    crossing(f, greatest, greatest.addingTimeInterval(6 * 3600)))
        }
        guard let whole = contacts({ $0.penumbra + $0.moon }) else { return nil }
        let partial = contacts { $0.umbra + $0.moon }
        let total = contacts { $0.umbra - $0.moon }
        return LunarEclipse(
            kind: total != nil ? .total : partial != nil ? .partial : .penumbral,
            greatest: greatest,
            umbralMagnitude: umbral,
            penumbralMagnitude: penumbral,
            penumbralStart: whole.0, penumbralEnd: whole.1,
            partialStart: partial?.0, partialEnd: partial?.1,
            totalStart: total?.0, totalEnd: total?.1
        )
    }

    /// How far into Earth's inner shadow the moon is at `instant`: 0 outside, 1 when
    /// the whole disc is inside. Drives the red tint on the dial.
    public static func umbralCoverage(at instant: Date) -> Double {
        let g = lunarGeometry(instant)
        return min(max((g.umbra + g.moon - g.separation) / (2 * g.moon), 0), 1)
    }

    struct LunarGeometry {
        /// Moon center to shadow center, and shadow and moon radii, degrees.
        let separation, umbra, penumbra, moon: Double
    }

    static func lunarGeometry(_ instant: Date) -> LunarGeometry {
        let sun = SolarCalculator.position(at: instant)
        let moon = LunarCalculator.position(at: instant)
        let moonParallax = moon.parallax
        let sunSemidiameter = sun.semidiameter
        // Meeus ch. 54, with the customary 2% enlargement for Earth's atmosphere.
        let umbra = 1.02 * (0.99834 * moonParallax - sunSemidiameter + sun.parallax)
        let penumbra = 1.02 * (0.99834 * moonParallax + sunSemidiameter + sun.parallax)
        let separation = angularSeparation(
            ra1: rev(sun.rightAscension + 180), dec1: -sun.declination,
            ra2: moon.rightAscension, dec2: moon.declination
        )
        return LunarGeometry(separation: separation, umbra: umbra, penumbra: penumbra, moon: 0.2725076 * moonParallax)
    }

    // MARK: Solar (local)

    public struct SolarEclipse: Hashable, Sendable {
        public enum Kind: String, Sendable {
            case partial
            /// The moon too small to cover the sun: a ring of fire.
            case annular
            case total
        }

        public let kind: Kind
        public let start: Date
        public let maximum: Date
        public let end: Date
        /// Fraction of the sun's diameter covered at maximum.
        public let magnitude: Double
        /// Fraction of the sun's area covered at maximum.
        public let obscuration: Double
        /// Totality or the annular ring (C2 to C3), when the location gets one.
        public let centralStart: Date?
        public let centralEnd: Date?
        /// The sun's altitude at maximum; negative means it's below the horizon then.
        public let sunAltitudeAtMaximum: Double
    }

    /// The solar eclipse seen from `coordinate` at the new moon nearest `newMoon`, if any.
    public static func solarEclipse(near newMoon: Date, at coordinate: Coordinate) -> SolarEclipse? {
        let geometry = { (t: Date) in solarGeometry(t, at: coordinate) }
        let maximum = minimize(near: newMoon, span: 5 * 3600, step: 120) { geometry($0).separation }
        let g = geometry(maximum)
        guard g.separation < g.sun + g.moon else { return nil }
        let kind: SolarEclipse.Kind = g.moon > g.sun && g.separation <= g.moon - g.sun ? .total
            : g.moon < g.sun && g.separation <= g.sun - g.moon ? .annular : .partial
        let outer: (Date) -> Double = { let g = geometry($0); return g.separation - (g.sun + g.moon) }
        let inner: (Date) -> Double = { let g = geometry($0); return g.separation - abs(g.moon - g.sun) }
        let central = kind == .partial ? nil
            : (crossing(inner, maximum.addingTimeInterval(-3600), maximum), crossing(inner, maximum, maximum.addingTimeInterval(3600)))
        return SolarEclipse(
            kind: kind,
            start: crossing(outer, maximum.addingTimeInterval(-4 * 3600), maximum),
            maximum: maximum,
            end: crossing(outer, maximum, maximum.addingTimeInterval(4 * 3600)),
            magnitude: (g.sun + g.moon - g.separation) / (2 * g.sun),
            obscuration: obscuration(g),
            centralStart: central?.0,
            centralEnd: central?.1,
            sunAltitudeAtMaximum: SolarCalculator.altitude(
                hourAngle: SolarCalculator.hourAngle(at: maximum, longitude: coordinate.longitude),
                latitude: coordinate.latitude,
                declination: SolarCalculator.position(at: maximum).declination
            )
        )
    }

    /// How much of the sun the moon covers from `coordinate` at `instant` (0...1 of the
    /// area), and which way the moon is offset, for drawing on the dial.
    public static func solarCoverage(at instant: Date, coordinate: Coordinate) -> (obscuration: Double, offset: Double, moonScale: Double) {
        let g = solarGeometry(instant, at: coordinate)
        return (obscuration(g), g.separation / g.sun * g.side, g.moon / g.sun)
    }

    struct SolarGeometry {
        /// Topocentric sun-moon separation and the two semidiameters, degrees; `side` is
        /// +1 when the moon is east of the sun (it moves west to east across it).
        let separation, sun, moon, side: Double
    }

    static func solarGeometry(_ instant: Date, at coordinate: Coordinate) -> SolarGeometry {
        let sun = SolarCalculator.position(at: instant)
        let moon = LunarCalculator.position(at: instant)
        // Topocentric moon: its geocentric vector (Earth radii) minus the observer's
        // (a spherical Earth is plenty here).
        let r = moon.distance
        let (mra, mdec) = (radians(moon.rightAscension), radians(moon.declination))
        let mx = r * cos(mdec) * cos(mra), my = r * cos(mdec) * sin(mra), mz = r * sin(mdec)
        let lst = radians(moon.rightAscension + LunarCalculator.hourAngle(
            at: instant, longitude: coordinate.longitude, rightAscension: moon.rightAscension))
        let lat = radians(coordinate.latitude)
        let tx = mx - cos(lat) * cos(lst), ty = my - cos(lat) * sin(lst), tz = mz - sin(lat)
        let tr = (tx * tx + ty * ty + tz * tz).squareRoot()
        let ra = rev(degrees(atan2(ty, tx)))
        let dec = degrees(asin(tz / tr))
        let deltaRA = normalize(ra - sun.rightAscension)
        return SolarGeometry(
            separation: angularSeparation(ra1: sun.rightAscension, dec1: sun.declination, ra2: ra, dec2: dec),
            sun: sun.semidiameter,
            moon: degrees(asin(0.2725076 / tr)),
            side: deltaRA >= 0 ? 1 : -1
        )
    }

    /// Fraction of the sun's disc area covered (two overlapping circles).
    static func obscuration(_ g: SolarGeometry) -> Double {
        let (d, ss, sm) = (g.separation, g.sun, g.moon)
        if d >= ss + sm { return 0 }
        if d <= abs(sm - ss) { return min(1, (sm / ss) * (sm / ss)) }
        let a = ss * ss * acos((d * d + ss * ss - sm * sm) / (2 * d * ss))
        let b = sm * sm * acos((d * d + sm * sm - ss * ss) / (2 * d * sm))
        let c = 0.5 * ((-d + ss + sm) * (d + ss - sm) * (d - ss + sm) * (d + ss + sm)).squareRoot()
        return (a + b - c) / (.pi * ss * ss)
    }

    // MARK: Searching

    /// Lunar eclipses in `[start, end)`.
    public static func lunarEclipses(from start: Date, to end: Date) -> [LunarEclipse] {
        SkyCalendar.occurrences(from: start, to: end, in: .gmt)
            .filter { if case .fullMoon = $0.kind { true } else { false } }
            .compactMap { lunarEclipse(near: $0.date) }
    }

    /// Solar eclipses seen from `coordinate` in `[start, end)` (including ones that are
    /// partly or wholly below the horizon; check `sunAltitudeAtMaximum`).
    public static func solarEclipses(from start: Date, to end: Date, at coordinate: Coordinate) -> [SolarEclipse] {
        SkyCalendar.occurrences(from: start, to: end, in: .gmt)
            .filter { $0.kind == .newMoon }
            .compactMap { newMoon in
                // Only new moons near a node can eclipse the sun; skip the rest cheaply.
                abs(LunarCalculator.position(at: newMoon.date).latitude) < 1.6
                    ? solarEclipse(near: newMoon.date, at: coordinate) : nil
            }
    }

    // MARK: Helpers

    static func angularSeparation(ra1: Double, dec1: Double, ra2: Double, dec2: Double) -> Double {
        let a = pow(sin(radians(dec2 - dec1) / 2), 2) + cos(radians(dec1)) * cos(radians(dec2)) * pow(sin(radians(ra2 - ra1) / 2), 2)
        return degrees(2 * asin(min(1, a.squareRoot())))
    }

    /// The time near `center` (within `span` either side) that minimizes `f`: a coarse scan,
    /// then golden-section search.
    static func minimize(near center: Date, span: TimeInterval, step: TimeInterval, _ f: (Date) -> Double) -> Date {
        var best = center.addingTimeInterval(-span), bestValue = Double.infinity
        var t = center.addingTimeInterval(-span)
        while t <= center.addingTimeInterval(span) {
            let v = f(t)
            if v < bestValue { (best, bestValue) = (t, v) }
            t = t.addingTimeInterval(step)
        }
        var a = best.timeIntervalSince1970 - step, b = best.timeIntervalSince1970 + step
        for _ in 0..<60 {
            let m1 = a + (b - a) * 0.382, m2 = a + (b - a) * 0.618
            if f(Date(timeIntervalSince1970: m1)) < f(Date(timeIntervalSince1970: m2)) { b = m2 } else { a = m1 }
        }
        return Date(timeIntervalSince1970: (a + b) / 2)
    }

    /// Where `f` changes sign between `a` and `b`.
    static func crossing(_ f: (Date) -> Double, _ a: Date, _ b: Date) -> Date {
        var lo = a.timeIntervalSince1970, hi = b.timeIntervalSince1970
        let negativeAtLo = f(a) < 0
        for _ in 0..<50 {
            let mid = (lo + hi) / 2
            if (f(Date(timeIntervalSince1970: mid)) < 0) == negativeAtLo { lo = mid } else { hi = mid }
        }
        return Date(timeIntervalSince1970: (lo + hi) / 2)
    }

    private static func rev(_ x: Double) -> Double {
        let r = fmod(x, 360)
        return r < 0 ? r + 360 : r
    }

    private static func normalize(_ x: Double) -> Double {
        var d = fmod(x, 360)
        if d <= -180 { d += 360 } else if d > 180 { d -= 360 }
        return d
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}
