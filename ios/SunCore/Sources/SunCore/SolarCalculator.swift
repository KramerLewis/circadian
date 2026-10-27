import Foundation

/// Solar position and event times, computed on-device with the NOAA solar
/// calculator formulas (Jean Meeus, *Astronomical Algorithms*).
///
/// Every event is solved as an instant rather than as minutes past a UTC date, which
/// makes time zones and DST irrelevant to the math: the only calendar-dependent step
/// is choosing local noon as the starting guess. Each solve is refined by recomputing
/// the sun's position at the candidate instant, as NOAA's own calculator does.
///
/// Reference: https://gml.noaa.gov/grad/solcalc/calcdetails.html
public enum SolarCalculator {
    /// Sun position at an instant.
    public struct Position: Sendable {
        /// Declination in degrees.
        public let declination: Double
        /// Equation of time in minutes (apparent minus mean solar time).
        public let equationOfTime: Double
        /// Apparent ecliptic longitude in degrees (used for the moon's phase).
        public let apparentLongitude: Double
        /// Apparent right ascension in degrees (used for eclipses).
        public let rightAscension: Double
        /// Distance from Earth in AU.
        public let distance: Double

        /// Apparent semidiameter in degrees (about 0.27).
        public var semidiameter: Double { 959.63 / 3600 / distance }
        /// Horizontal parallax in degrees (about 0.0024).
        public var parallax: Double { 8.794 / 3600 / distance }
    }

    // MARK: Solar days

    /// The solar day centered on the solar noon of `date`'s local calendar day.
    public static func solarDay(
        for date: Date,
        at coordinate: Coordinate,
        in timeZone: TimeZone
    ) -> SolarDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: date)
        let localNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: start) ?? start
        return solarDay(nearestNoonTo: localNoon, at: coordinate)
    }

    /// The solar day (solar midnight to solar midnight) containing `instant`.
    public static func solarDay(containing instant: Date, at coordinate: Coordinate) -> SolarDay {
        let day = solarDay(nearestNoonTo: instant, at: coordinate)
        // The nearest noon is within 12 solar hours, so the instant is in this day
        // except for rounding right at a midnight boundary.
        if instant < day.solarMidnight {
            return solarDay(nearestNoonTo: day.solarNoon.addingTimeInterval(-86_400), at: coordinate)
        }
        if instant >= day.nextSolarMidnight {
            return solarDay(nearestNoonTo: day.solarNoon.addingTimeInterval(86_400), at: coordinate)
        }
        return day
    }

    static func solarDay(nearestNoonTo guess: Date, at coordinate: Coordinate) -> SolarDay {
        let noon = solve(hourAngle: 0, near: guess, longitude: coordinate.longitude)
        let midnight = solve(hourAngle: 180, near: noon.addingTimeInterval(-43_200), longitude: coordinate.longitude)
        let nextMidnight = solve(hourAngle: 180, near: noon.addingTimeInterval(43_200), longitude: coordinate.longitude)
        var events: [SolarEvent: EventTime] = [:]
        for event in SolarEvent.allCases {
            guard let altitude = event.altitude else { continue }
            events[event] = eventTime(altitude: altitude, direction: event.direction, noon: noon, coordinate: coordinate)
        }
        return SolarDay(
            coordinate: coordinate,
            solarNoon: noon,
            solarMidnight: midnight,
            nextSolarMidnight: nextMidnight,
            horizonEvents: events
        )
    }

    /// When the sun's center crosses `altitude` on the solar day of `noon`: rising
    /// (`direction` -1, before noon) or setting (+1, after). For definitions other than the
    /// standard events, such as the wadokei's dawn and dusk.
    public static func crossing(altitude: Double, direction: Double, noon: Date, coordinate: Coordinate) -> EventTime {
        eventTime(altitude: altitude, direction: direction, noon: noon, coordinate: coordinate)
    }

    private static func eventTime(altitude: Double, direction: Double, noon: Date, coordinate: Coordinate) -> EventTime {
        var hourAngle: Double
        switch altitudeHourAngle(altitude, latitude: coordinate.latitude, declination: position(at: noon).declination) {
        case .success(let h): hourAngle = h
        case .failure(let polar): return polar.eventTime
        }
        var t = noon.addingTimeInterval(direction * hourAngle * secondsPerDegree)
        for _ in 0..<iterations {
            switch altitudeHourAngle(altitude, latitude: coordinate.latitude, declination: position(at: t).declination) {
            case .success(let h): hourAngle = h
            case .failure(let polar): return polar.eventTime
            }
            let error = normalize(direction * hourAngle - self.hourAngle(at: t, longitude: coordinate.longitude))
            t = t.addingTimeInterval(error * secondsPerDegree)
        }
        return .at(t)
    }

    // MARK: Solar time

    /// Apparent (sundial) solar time at `instant`, in minutes past solar midnight, in `0..<1440`.
    public static func apparentSolarMinutes(at instant: Date, longitude: Double) -> Double {
        let utcMinutes = mod(instant.timeIntervalSince1970 / 60, 1440)
        return mod(utcMinutes + 4 * longitude + position(at: instant).equationOfTime, 1440)
    }

    /// Solar hour angle in degrees, in `(-180, 180]`; 0 at solar noon, increasing with time.
    public static func hourAngle(at instant: Date, longitude: Double) -> Double {
        normalize((apparentSolarMinutes(at: instant, longitude: longitude) - 720) / 4)
    }

    // MARK: Sun position (NOAA)

    public static func position(at instant: Date) -> Position {
        let julianDay = instant.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let t = (julianDay - 2_451_545) / 36_525

        let meanLongitude = mod(280.46646 + t * (36000.76983 + 0.0003032 * t), 360)
        let meanAnomaly = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let m = radians(meanAnomaly)
        let equationOfCenter = sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * m) * (0.019993 - 0.000101 * t)
            + sin(3 * m) * 0.000289
        let trueLongitude = meanLongitude + equationOfCenter
        let omega = 125.04 - 1934.136 * t
        let apparentLongitude = trueLongitude - 0.00569 - 0.00478 * sin(radians(omega))
        let obliquitySeconds = 21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))
        let meanObliquity = 23 + (26 + obliquitySeconds / 60) / 60
        let obliquity = radians(meanObliquity + 0.00256 * cos(radians(omega)))

        let declination = degrees(asin(sin(obliquity) * sin(radians(apparentLongitude))))

        let y = pow(tan(obliquity / 2), 2)
        let l0 = radians(meanLongitude)
        let e = eccentricity
        let eot = y * sin(2 * l0)
            - 2 * e * sin(m)
            + 4 * e * y * sin(m) * cos(2 * l0)
            - 0.5 * y * y * sin(4 * l0)
            - 1.25 * e * e * sin(2 * m)

        let lambda = radians(apparentLongitude)
        let rightAscension = mod(degrees(atan2(cos(obliquity) * sin(lambda), cos(lambda))), 360)
        let trueAnomaly = radians(meanAnomaly + equationOfCenter)
        let distance = 1.000001018 * (1 - eccentricity * eccentricity) / (1 + eccentricity * cos(trueAnomaly))
        return Position(
            declination: declination,
            equationOfTime: 4 * degrees(eot),
            apparentLongitude: mod(apparentLongitude, 360),
            rightAscension: rightAscension,
            distance: distance
        )
    }

    // MARK: Helpers

    /// The earth turns one degree of hour angle every four minutes.
    private static let secondsPerDegree = 240.0
    private static let iterations = 5

    private enum Polar: Error {
        case alwaysAbove, alwaysBelow
        var eventTime: EventTime { self == .alwaysAbove ? .sunAlwaysAbove : .sunAlwaysBelow }
    }

    /// Hour angle (degrees, positive) at which the sun's center reaches `altitude`.
    private static func altitudeHourAngle(_ altitude: Double, latitude: Double, declination: Double) -> Result<Double, Polar> {
        // Avoid dividing by cos(90 deg) exactly at the poles.
        let lat = radians(min(max(latitude, -89.9999), 89.9999))
        let dec = radians(declination)
        let cosH = (sin(radians(altitude)) - sin(lat) * sin(dec)) / (cos(lat) * cos(dec))
        if cosH > 1 { return .failure(.alwaysBelow) }
        if cosH < -1 { return .failure(.alwaysAbove) }
        return .success(degrees(acos(cosH)))
    }

    /// The instant nearest `guess` at which the hour angle equals `target`.
    private static func solve(hourAngle target: Double, near guess: Date, longitude: Double) -> Date {
        var t = guess
        for _ in 0..<iterations {
            t = t.addingTimeInterval(normalize(target - hourAngle(at: t, longitude: longitude)) * secondsPerDegree)
        }
        return t
    }

    /// Wraps degrees to `(-180, 180]`.
    private static func normalize(_ degrees: Double) -> Double {
        var d = fmod(degrees, 360)
        if d <= -180 { d += 360 } else if d > 180 { d -= 360 }
        return d
    }

    private static func mod(_ x: Double, _ m: Double) -> Double {
        let r = fmod(x, m)
        return r < 0 ? r + m : r
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}
