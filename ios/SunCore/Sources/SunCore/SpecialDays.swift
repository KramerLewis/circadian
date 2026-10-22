import Foundation

/// Notable sky days: solstices, equinoxes, full moons (including supermoons and blue
/// moons) and new moons. Instants come from the same sun and moon models as the rest of
/// SunCore; they agree with a full ephemeris to within about 10 minutes, which is
/// plenty for deciding which day they fall on.
public enum SkyCalendar {
    public enum Season: String, CaseIterable, Sendable {
        case marchEquinox, juneSolstice, septemberEquinox, decemberSolstice

        /// The sun's apparent ecliptic longitude at this moment, degrees.
        var longitude: Double {
            switch self {
            case .marchEquinox: 0
            case .juneSolstice: 90
            case .septemberEquinox: 180
            case .decemberSolstice: 270
            }
        }

        public var isSolstice: Bool { self == .juneSolstice || self == .decemberSolstice }
    }

    public enum Kind: Hashable, Sendable {
        case season(Season)
        case fullMoon(supermoon: Bool, blueMoon: Bool)
        case newMoon
    }

    public struct Occurrence: Hashable, Sendable {
        public let kind: Kind
        public let date: Date
        /// Earth-moon distance at a full or new moon, km.
        public let moonDistance: Double?
    }

    /// A full moon closer than this is a supermoon (about 90% of the way to perigee).
    public static let supermoonDistance: Double = 362_000
    static let earthRadiusKm = 6378.14

    /// Every notable instant in `[start, end)`, chronological. Blue moons are judged in
    /// `timeZone` (the second full moon in one calendar month).
    public static func occurrences(from start: Date, to end: Date, in timeZone: TimeZone) -> [Occurrence] {
        var found: [Occurrence] = []
        for season in Season.allCases {
            for date in crossings(from: start, to: end, step: 86_400, target: season.longitude, angle: sunLongitude) {
                found.append(Occurrence(kind: .season(season), date: date, moonDistance: nil))
            }
        }
        // Look back a month for full moons so a blue moon early in the window knows
        // about the first full moon of its month.
        let fullMoons = crossings(from: start.addingTimeInterval(-32 * 86_400), to: end, step: 6 * 3600, target: 180, angle: elongation)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var previousMonth: DateComponents?
        for date in fullMoons {
            let month = calendar.dateComponents([.year, .month], from: date)
            let blue = month == previousMonth
            previousMonth = month
            guard date >= start else { continue }
            let distance = moonDistance(at: date)
            found.append(Occurrence(kind: .fullMoon(supermoon: distance < supermoonDistance, blueMoon: blue), date: date, moonDistance: distance))
        }
        for date in crossings(from: start, to: end, step: 6 * 3600, target: 0, angle: elongation) {
            found.append(Occurrence(kind: .newMoon, date: date, moonDistance: moonDistance(at: date)))
        }
        return found.sorted { $0.date < $1.date }
    }

    /// The notable event (if any) on the local calendar day containing `instant`.
    public static func event(onDayOf instant: Date, in timeZone: TimeZone) -> Occurrence? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: instant)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        // Seasons take precedence over moon phases if both fall on one day.
        return occurrences(from: start, to: end, in: timeZone).min { priority($0) < priority($1) }
    }

    /// The next notable event after today, if it's within `days` days.
    public static func upcoming(after instant: Date, within days: Int, in timeZone: TimeZone) -> Occurrence? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: instant)),
            let end = calendar.date(byAdding: .day, value: days, to: tomorrow)
        else { return nil }
        return occurrences(from: tomorrow, to: end, in: timeZone).first
    }

    // MARK: Helpers

    private static func priority(_ occurrence: Occurrence) -> Int {
        switch occurrence.kind {
        case .season: 0
        case .fullMoon: 1
        case .newMoon: 2
        }
    }

    private static func sunLongitude(_ date: Date) -> Double {
        SolarCalculator.position(at: date).apparentLongitude
    }

    /// Moon's ecliptic longitude minus the sun's, 0..<360 (0 new, 180 full).
    private static func elongation(_ date: Date) -> Double {
        let d = LunarCalculator.position(at: date).longitude - sunLongitude(date)
        let r = fmod(d, 360)
        return r < 0 ? r + 360 : r
    }

    private static func moonDistance(at date: Date) -> Double {
        LunarCalculator.position(at: date).distance * earthRadiusKm
    }

    /// Instants in `[start, end)` where an increasing angle passes `target`.
    private static func crossings(from start: Date, to end: Date, step: TimeInterval, target: Double, angle: (Date) -> Double) -> [Date] {
        func offset(_ t: Date) -> Double {
            var d = fmod(angle(t) - target, 360)
            if d < -180 { d += 360 } else if d >= 180 { d -= 360 }
            return d
        }
        var result: [Date] = []
        var t = start
        var previous = offset(t)
        while t < end {
            let next = t.addingTimeInterval(step)
            let current = offset(next)
            // A small negative-to-positive step is a crossing; a wrap from +180 to -180 isn't.
            if previous < 0, current >= 0, current - previous < 90 {
                var a = t, b = next
                for _ in 0..<40 {
                    let mid = Date(timeIntervalSince1970: (a.timeIntervalSince1970 + b.timeIntervalSince1970) / 2)
                    if offset(mid) < 0 { a = mid } else { b = mid }
                }
                let crossing = Date(timeIntervalSince1970: (a.timeIntervalSince1970 + b.timeIntervalSince1970) / 2)
                if crossing >= start, crossing < end { result.append(crossing) }
            }
            t = next
            previous = current
        }
        return result
    }
}

extension SkyCalendar.Occurrence {
    /// "Summer solstice", "Blue supermoon", "New moon". Solstice and equinox names
    /// follow the hemisphere.
    public func title(southern: Bool) -> String {
        switch kind {
        case .season(let season):
            switch (season, southern) {
            case (.juneSolstice, false), (.decemberSolstice, true): return "Summer solstice"
            case (.juneSolstice, true), (.decemberSolstice, false): return "Winter solstice"
            case (.marchEquinox, false), (.septemberEquinox, true): return "Spring equinox"
            case (.marchEquinox, true), (.septemberEquinox, false): return "Autumn equinox"
            }
        case .fullMoon(let supermoon, let blue):
            switch (supermoon, blue) {
            case (true, true): return "Blue supermoon"
            case (true, false): return "Supermoon"
            case (false, true): return "Blue moon"
            case (false, false): return "Full moon"
            }
        case .newMoon:
            return "New moon"
        }
    }
}
