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
/// Position uses the main terms of the ELP-2000/82 theory as given by Meeus,
/// *Astronomical Algorithms* ch. 47 (about 10″; coefficients in LunarTerms.swift). That
/// puts rise, set and transit times within seconds of a full ephemeris, and is accurate
/// enough for solar eclipse magnitudes near totality.
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

    /// Clocks run on UT; the lunar theory runs on Terrestrial Time. TT − UT (ΔT) has
    /// been within a second of 69 s since 2015 and drifts well under a second a year.
    static let deltaT: TimeInterval = 69

    public static func position(at instant: Date) -> Position {
        let jd = (instant.timeIntervalSince1970 + deltaT) / 86_400 + 2_440_587.5
        let t = (jd - 2_451_545) / 36_525
        let t2 = t * t, t3 = t2 * t, t4 = t3 * t

        // Fundamental arguments (degrees).
        let lp = 218.3164477 + 481267.88123421 * t - 0.0015786 * t2 + t3 / 538_841 - t4 / 65_194_000
        let d = 297.8501921 + 445267.1114034 * t - 0.0018819 * t2 + t3 / 545_868 - t4 / 113_065_000
        let m = 357.5291092 + 35999.0502909 * t - 0.0001536 * t2 + t3 / 24_490_000
        let mp = 134.9633964 + 477198.8675055 * t + 0.0087414 * t2 + t3 / 69_699 - t4 / 14_712_000
        let f = 93.2720950 + 483202.0175233 * t - 0.0036539 * t2 - t3 / 3_526_000 + t4 / 863_310_000
        let a1 = 119.75 + 131.849 * t
        let a2 = 53.09 + 479264.290 * t
        let a3 = 313.45 + 481266.484 * t
        let e = 1 - 0.002516 * t - 0.0000074 * t2

        func argument(_ cd: Int8, _ cm: Int8, _ cmp: Int8, _ cf: Int8) -> Double {
            radians(Double(cd) * d + Double(cm) * m + Double(cmp) * mp + Double(cf) * f)
        }
        func eccentricity(_ cm: Int8) -> Double { cm == 0 ? 1 : abs(cm) == 1 ? e : e * e }

        var sl = 0.0, sr = 0.0, sb = 0.0
        for (cd, cm, cmp, cf, l, r) in longitudeDistanceTerms {
            let arg = argument(cd, cm, cmp, cf)
            let ecc = eccentricity(cm)
            sl += Double(l) * ecc * sin(arg)
            sr += Double(r) * ecc * cos(arg)
        }
        for (cd, cm, cmp, cf, b) in latitudeTerms {
            sb += Double(b) * eccentricity(cm) * sin(argument(cd, cm, cmp, cf))
        }
        sl += 3958 * sin(radians(a1)) + 1962 * sin(radians(lp - f)) + 318 * sin(radians(a2))
        sb += -2235 * sin(radians(lp)) + 382 * sin(radians(a3)) + 175 * sin(radians(a1 - f))
            + 175 * sin(radians(a1 + f)) + 127 * sin(radians(lp - mp)) - 115 * sin(radians(lp + mp))

        // Nutation (main terms) and the true obliquity of the ecliptic.
        let omega = radians(125.04452 - 1934.136261 * t)
        let ls = radians(280.4665 + 36000.7698 * t), lm = radians(218.3165 + 481267.8813 * t)
        let dpsi = (-17.20 * sin(omega) - 1.32 * sin(2 * ls) - 0.23 * sin(2 * lm) + 0.21 * sin(2 * omega)) / 3600
        let deps = (9.20 * cos(omega) + 0.57 * cos(2 * ls) + 0.10 * cos(2 * lm) - 0.09 * cos(2 * omega)) / 3600
        let eps0 = 23 + 26.0 / 60 + 21.448 / 3600 - (46.8150 * t + 0.00059 * t2 - 0.001813 * t3) / 3600
        let eps = radians(eps0 + deps)

        let lon = rev(lp + sl / 1e6 + dpsi)
        let lat = sb / 1e6
        let distanceKm = 385_000.56 + sr / 1000
        let l = radians(lon), b = radians(lat)
        let ra = rev(degrees(atan2(sin(l) * cos(eps) - tan(b) * sin(eps), cos(l))))
        let dec = degrees(asin(sin(b) * cos(eps) + cos(b) * sin(eps) * sin(l)))
        return Position(longitude: lon, latitude: lat, rightAscension: ra, declination: dec, distance: distanceKm / earthRadiusKm)
    }

    static let earthRadiusKm = 6378.14

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
