import Foundation

/// Points in the moon's day, which runs about 24h 50m.
public enum LunarEvent: String, CaseIterable, Codable, Sendable, Identifiable {
    case moonrise
    /// Upper meridian transit: the moon at its highest.
    case moonTransit
    case moonset
    /// Lower meridian transit: the moon at its lowest.
    case moonLowerTransit

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .moonrise: "Moonrise"
        case .moonTransit: "Moon highest"
        case .moonset: "Moonset"
        case .moonLowerTransit: "Moon lowest"
        }
    }
}

/// The moon's position, phase and daily events, computed on device.
///
/// Position uses Paul Schlyter's low-precision method (orbital elements plus the main
/// perturbation terms, about 1-2 arcminutes; https://stjarnhimlen.se/comp/ppcomp.html).
/// That puts rise, set and transit times within about 30 seconds of a full ephemeris.
/// Rise/set use the standard altitude 0.7275 * parallax - 34' (topocentric upper limb
/// on the refracted horizon). The reference implementation and fixture are in
/// shared/tools/generate_lunar_fixtures.py.
public enum LunarCalculator {
    public struct Position: Sendable {
        /// Geocentric ecliptic longitude and latitude, degrees.
        public let longitude: Double
        public let latitude: Double
        /// Geocentric right ascension and declination, degrees.
        public let rightAscension: Double
        public let declination: Double
        /// Distance in Earth radii.
        public let distance: Double

        /// Horizontal parallax, degrees (about 0.9-1.0).
        public var parallax: Double { degrees(asin(1 / distance)) }
    }

    public struct Phase: Hashable, Sendable {
        /// Illuminated fraction of the disc, 0 (new) ... 1 (full).
        public let illumination: Double
        public let isWaxing: Bool

        public var name: String {
            switch (illumination, isWaxing) {
            case (..<0.02, _): "New moon"
            case (0.98..., _): "Full moon"
            case (0.45..<0.55, true): "First quarter"
            case (0.45..<0.55, false): "Last quarter"
            case (..<0.45, true): "Waxing crescent"
            case (..<0.45, false): "Waning crescent"
            case (_, true): "Waxing gibbous"
            case (_, false): "Waning gibbous"
            }
        }
    }

    public struct Occurrence: Hashable, Sendable {
        public let event: LunarEvent
        public let date: Date
    }

    // MARK: Position

    public static func position(at instant: Date) -> Position {
        let d = instant.timeIntervalSince1970 / 86_400 + 2_440_587.5 - 2_451_543.5 // days since 2000 Jan 0.0
        let n = rev(125.1228 - 0.0529538083 * d)
        let i = 5.1454
        let w = rev(318.0634 + 0.1643573223 * d)
        let a = 60.2666, e = 0.054900
        let m = rev(115.3654 + 13.0649929509 * d)
        let ms = rev(356.0470 + 0.9856002585 * d)
        let ls = rev(282.9404 + 4.70935e-5 * d + ms)

        var ecc = m + degrees(e * sin(radians(m)) * (1 + e * cos(radians(m))))
        for _ in 0..<5 {
            ecc -= (ecc - degrees(e * sin(radians(ecc))) - m) / (1 - e * cos(radians(ecc)))
        }
        let xv = a * (cos(radians(ecc)) - e)
        let yv = a * (1 - e * e).squareRoot() * sin(radians(ecc))
        let v = degrees(atan2(yv, xv))
        var r = (xv * xv + yv * yv).squareRoot()

        let xh = r * (cos(radians(n)) * cos(radians(v + w)) - sin(radians(n)) * sin(radians(v + w)) * cos(radians(i)))
        let yh = r * (sin(radians(n)) * cos(radians(v + w)) + cos(radians(n)) * sin(radians(v + w)) * cos(radians(i)))
        let zh = r * sin(radians(v + w)) * sin(radians(i))
        var lon = degrees(atan2(yh, xh))
        var lat = degrees(atan2(zh, (xh * xh + yh * yh).squareRoot()))

        // Main perturbations (mean elongation, argument of latitude).
        let lm = rev(n + w + m)
        let dd = rev(lm - ls)
        let f = rev(lm - n)
        func s(_ x: Double) -> Double { sin(radians(x)) }
        func c(_ x: Double) -> Double { cos(radians(x)) }
        lon += -1.274 * s(m - 2 * dd) + 0.658 * s(2 * dd) - 0.186 * s(ms) - 0.059 * s(2 * m - 2 * dd)
            - 0.057 * s(m - 2 * dd + ms) + 0.053 * s(m + 2 * dd) + 0.046 * s(2 * dd - ms)
            + 0.041 * s(m - ms) - 0.035 * s(dd) - 0.031 * s(m + ms) - 0.015 * s(2 * f - 2 * dd)
            + 0.011 * s(m - 4 * dd)
        lat += -0.173 * s(f - 2 * dd) - 0.055 * s(m - f - 2 * dd) - 0.046 * s(m + f - 2 * dd)
            + 0.033 * s(f + 2 * dd) + 0.017 * s(2 * m + f)
        r += -0.58 * c(m - 2 * dd) - 0.46 * c(2 * dd)

        let obliquity = 23.4393 - 3.563e-7 * d
        let xe = c(lon) * c(lat), ye = s(lon) * c(lat), ze = s(lat)
        let yq = ye * c(obliquity) - ze * s(obliquity)
        let zq = ye * s(obliquity) + ze * c(obliquity)
        return Position(
            longitude: rev(lon),
            latitude: lat,
            rightAscension: rev(degrees(atan2(yq, xe))),
            declination: degrees(atan2(zq, (xe * xe + yq * yq).squareRoot())),
            distance: r
        )
    }

    /// The moon's local hour angle in `(-180, 180]`: 0 at its highest.
    public static func hourAngle(at instant: Date, longitude: Double) -> Double {
        hourAngle(at: instant, longitude: longitude, rightAscension: position(at: instant).rightAscension)
    }

    public static func altitude(at instant: Date, coordinate: Coordinate) -> Double {
        let p = position(at: instant)
        let h = hourAngle(at: instant, longitude: coordinate.longitude, rightAscension: p.rightAscension)
        return SolarCalculator.altitude(hourAngle: h, latitude: coordinate.latitude, declination: p.declination)
    }

    /// Altitude of the moon's center at moonrise/moonset.
    public static func riseSetAltitude(distance: Double) -> Double {
        0.7275 * degrees(asin(1 / distance)) - 34.0 / 60
    }

    public static func phase(at instant: Date) -> Phase {
        let moon = position(at: instant)
        let sunLongitude = SolarCalculator.position(at: instant).apparentLongitude
        let elongation = degrees(acos(cos(radians(moon.latitude)) * cos(radians(moon.longitude - sunLongitude))))
        return Phase(
            illumination: (1 - cos(radians(elongation))) / 2,
            isWaxing: rev(moon.longitude - sunLongitude) < 180
        )
    }

    // MARK: Events

    /// Moonrise, moonset and both transits in `[start, end)`, chronological. Any of
    /// them can be missing on a given day.
    public static func events(from start: Date, to end: Date, at coordinate: Coordinate) -> [Occurrence] {
        let lon = coordinate.longitude
        func aboveHorizon(_ t: Date) -> Double {
            let p = position(at: t)
            let h = hourAngle(at: t, longitude: lon, rightAscension: p.rightAscension)
            return SolarCalculator.altitude(hourAngle: h, latitude: coordinate.latitude, declination: p.declination)
                - riseSetAltitude(distance: p.distance)
        }
        func upper(_ t: Date) -> Double { hourAngle(at: t, longitude: lon) }
        func lower(_ t: Date) -> Double { normalize(upper(t) - 180) }

        var found: [Occurrence] = []
        var t = start
        var previous = (aboveHorizon(t), upper(t), lower(t))
        while t < end {
            let next = min(t.addingTimeInterval(step), end)
            let current = (aboveHorizon(next), upper(next), lower(next))
            if previous.0 < 0, current.0 >= 0 {
                found.append(Occurrence(event: .moonrise, date: bisect(aboveHorizon, t, next)))
            }
            if previous.0 >= 0, current.0 < 0 {
                found.append(Occurrence(event: .moonset, date: bisect(aboveHorizon, t, next)))
            }
            // A hour-angle crossing of 0 (not the wrap at 180) is a transit.
            if previous.1 < 0, current.1 >= 0, current.1 - previous.1 < 90 {
                found.append(Occurrence(event: .moonTransit, date: bisect(upper, t, next)))
            }
            if previous.2 < 0, current.2 >= 0, current.2 - previous.2 < 90 {
                found.append(Occurrence(event: .moonLowerTransit, date: bisect(lower, t, next)))
            }
            t = next
            previous = current
        }
        return found.sorted { $0.date < $1.date }
    }

    // MARK: Helpers

    private static let step: TimeInterval = 600

    static func hourAngle(at instant: Date, longitude: Double, rightAscension: Double) -> Double {
        let jd = instant.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let t = (jd - 2_451_545) / 36_525
        let gmst = 280.46061837 + 360.98564736629 * (jd - 2_451_545) + 0.000387933 * t * t
        return normalize(gmst + longitude - rightAscension)
    }

    private static func bisect(_ f: (Date) -> Double, _ a: Date, _ b: Date) -> Date {
        var a = a, b = b
        var fa = f(a)
        for _ in 0..<30 {
            let mid = Date(timeIntervalSince1970: (a.timeIntervalSince1970 + b.timeIntervalSince1970) / 2)
            let fm = f(mid)
            if (fm > 0) == (fa > 0) {
                a = mid
                fa = fm
            } else {
                b = mid
            }
        }
        return Date(timeIntervalSince1970: (a.timeIntervalSince1970 + b.timeIntervalSince1970) / 2)
    }

    private static func rev(_ x: Double) -> Double {
        let r = fmod(x, 360)
        return r < 0 ? r + 360 : r
    }

    /// Wraps degrees to `(-180, 180]`.
    private static func normalize(_ x: Double) -> Double {
        var d = fmod(x, 360)
        if d <= -180 { d += 360 } else if d > 180 { d -= 360 }
        return d
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
}

private func degrees(_ radians: Double) -> Double { radians * 180 / .pi }

/// The moon ring on the dial: its own timeline, where the angle is the moon's hour
/// angle, so the moon's highest point is at the top and moonrise/moonset sit
/// symmetrically either side, just like the sun ring.
public struct MoonDialModel: Hashable, Sendable {
    public let latitude: Double
    public let declination: Double
    /// The moon's current hour angle (degrees, clockwise from the top).
    public let nowAngle: Double
    public let altitudeNow: Double
    public let riseSetAltitude: Double
    public let phase: LunarCalculator.Phase

    public init(now: Date, coordinate: Coordinate) {
        let position = LunarCalculator.position(at: now)
        latitude = coordinate.latitude
        declination = position.declination
        nowAngle = LunarCalculator.hourAngle(at: now, longitude: coordinate.longitude, rightAscension: position.rightAscension)
        riseSetAltitude = LunarCalculator.riseSetAltitude(distance: position.distance)
        altitudeNow = SolarCalculator.altitude(hourAngle: nowAngle, latitude: latitude, declination: declination)
        phase = LunarCalculator.phase(at: now)
    }

    public func altitude(atAngle angle: Double) -> Double {
        SolarCalculator.altitude(hourAngle: angle, latitude: latitude, declination: declination)
    }

    /// Hour angle of moonrise/moonset on the ring (moonrise at minus this), or nil if
    /// the moon stays up or stays down all day.
    public var riseSetAngle: Double? {
        let lat = latitude * .pi / 180, dec = declination * .pi / 180
        let cosH = (sin(riseSetAltitude * .pi / 180) - sin(lat) * sin(dec)) / (cos(lat) * cos(dec))
        guard (-1...1).contains(cosH) else { return nil }
        return acos(cosH) * 180 / .pi
    }
}

/// Moon ring colors: dark while the moon is down, silver while it's up, brighter when
/// higher and fuller.
public enum MoonGradient {
    public static func color(altitude: Double, riseSetAltitude: Double, illumination: Double, dark: Bool) -> SkyGradient.RGB {
        let down = dark ? SkyGradient.RGB(0.10, 0.11, 0.17) : SkyGradient.RGB(0.20, 0.22, 0.32)
        let up = dark ? SkyGradient.RGB(0.80, 0.84, 0.94) : SkyGradient.RGB(0.86, 0.89, 0.97)
        // Fade in over the first few degrees above the horizon, then brighten with
        // height; a new moon barely lifts the ring at all.
        let height = min(max((altitude - riseSetAltitude) / 30, 0), 1)
        let horizonFade = min(max((altitude - riseSetAltitude + 1) / 3, 0), 1)
        let t = horizonFade * (0.35 + 0.65 * height) * (0.25 + 0.75 * illumination)
        return SkyGradient.RGB(
            down.red + (up.red - down.red) * t,
            down.green + (up.green - down.green) * t,
            down.blue + (up.blue - down.blue) * t
        )
    }
}
