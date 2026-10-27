import Foundation

// Two ways of naming where you are in the day, both stretching with the seasons:
//
// Sun periods (this app's own scale): the four milestones of the solar day, sunrise (R),
// solar noon (N), sunset (S) and solar midnight (M), split the day into quarters; each
// quarter splits into thirds. The third after a milestone is X+, the one before is -X,
// and the middle third is a number (0 mid-morning, 1 mid-afternoon, 2 mid-evening,
// 3 deep night). Each milestone itself gets a short window (X) of ±15 minutes, so the
// moment is something you can catch:
//
//   … -R  R  R+  0  -N  N  N+  1  -S  S  S+  2  -M  M  M+  3  -R …
//
// The same scale works for the moon, in lowercase, with moonrise (r), the moon highest
// (n), moonset (s) and the moon lowest (m).
//
// Wadokei (Edo-period Japanese temporal hours): daylight from dawn to dusk, and night
// from dusk to dawn, each split into six equal hours named for the zodiac animals.
// Dawn and dusk are when the sun is 7°21'40" below the horizon (the Kansei calendar's
// definition), roughly half an hour beyond sunrise and sunset.
//
// Mirrors web/src/core/periods.ts.

public enum SunPeriods {
    /// Half of a milestone's window.
    public static let milestoneGrace: TimeInterval = 15 * 60

    public struct Anchor: Hashable, Sendable {
        /// "R", "N", "S", "M" (or lowercase for the moon).
        public let letter: String
        public let date: Date

        public init(letter: String, date: Date) {
            self.letter = letter
            self.date = date
        }
    }

    public struct Period: Hashable, Sendable {
        /// "-R", "R", "R+", "0", …
        public let code: String
        public let start: Date
        public let end: Date
        /// The quarter of the day it's in: from one milestone to the next.
        public let from: Anchor
        public let to: Anchor
        /// How far through that quarter, 0…1.
        public let fraction: Double
    }

    /// The period containing `now`, given milestones in time order (they repeat R N S M
    /// or, in polar days, just N M). `middle` names the middle third after each letter.
    public static func period(at now: Date, anchors: [Anchor], middle: [String: String]) -> Period? {
        guard let i = anchors.indices.first(where: { $0 + 1 < anchors.count && anchors[$0].date <= now && anchors[$0 + 1].date > now })
        else { return nil }
        let from = anchors[i], to = anchors[i + 1]
        let quarter = to.date.timeIntervalSince(from.date)
        let third = quarter / 3
        // The window shrinks on very short quarters, so it never swallows a section.
        let grace = min(milestoneGrace, third / 3)
        let fraction = now.timeIntervalSince(from.date) / quarter
        let previousGrace = graceAround(anchors, i), nextGrace = graceAround(anchors, i + 1)
        func make(_ code: String, _ start: Date, _ end: Date) -> Period {
            Period(code: code, start: start, end: end, from: from, to: to, fraction: fraction)
        }
        if now < from.date.addingTimeInterval(previousGrace) {
            return make(from.letter, from.date.addingTimeInterval(-previousGrace), from.date.addingTimeInterval(previousGrace))
        }
        if now >= to.date.addingTimeInterval(-nextGrace) {
            return make(to.letter, to.date.addingTimeInterval(-nextGrace), to.date.addingTimeInterval(nextGrace))
        }
        if now < from.date.addingTimeInterval(third) {
            return make("\(from.letter)+", from.date.addingTimeInterval(grace), from.date.addingTimeInterval(third))
        }
        if now < from.date.addingTimeInterval(2 * third) {
            return make(middle[from.letter] ?? "·", from.date.addingTimeInterval(third), from.date.addingTimeInterval(2 * third))
        }
        return make("-\(to.letter)", from.date.addingTimeInterval(2 * third), to.date.addingTimeInterval(-nextGrace))
    }

    /// A milestone's half-window: 15 minutes, or less if a neighboring quarter is short.
    private static func graceAround(_ anchors: [Anchor], _ k: Int) -> TimeInterval {
        let before = k > 0 ? anchors[k].date.timeIntervalSince(anchors[k - 1].date) : .infinity
        let after = k + 1 < anchors.count ? anchors[k + 1].date.timeIntervalSince(anchors[k].date) : .infinity
        return min(milestoneGrace, before / 9, after / 9)
    }

    private static let solarLetters: [SolarEvent: String] = [.sunrise: "R", .solarNoon: "N", .sunset: "S", .solarMidnight: "M"]
    private static let solarMiddles = ["R": "0", "N": "1", "S": "2", "M": "3"]
    /// Polar days have only noon and midnight: the half after midnight is 0, after noon 2.
    private static let polarMiddles = ["M": "0", "N": "2"]

    public static func solarAnchors(around now: Date, at coordinate: Coordinate) -> [Anchor] {
        SolarTimeline(around: now, at: coordinate, days: 2).occurrences.compactMap { o in
            solarLetters[o.event].map { Anchor(letter: $0, date: o.date) }
        }
    }

    public static func sun(at now: Date, coordinate: Coordinate) -> Period? {
        let anchors = solarAnchors(around: now, at: coordinate)
        let polar = !anchors.contains { $0.letter == "R" }
        return period(at: now, anchors: anchors, middle: polar ? polarMiddles : solarMiddles)
    }

    private static let lunarLetters: [LunarEvent: String] = [.moonrise: "r", .moonTransit: "n", .moonset: "s", .moonLowerTransit: "m"]

    public static func moon(at now: Date, coordinate: Coordinate) -> Period? {
        let anchors = LunarCalculator.events(from: now.addingTimeInterval(-40 * 3600), to: now.addingTimeInterval(40 * 3600), at: coordinate)
            .compactMap { o in lunarLetters[o.event].map { Anchor(letter: $0, date: o.date) } }
        let polar = !anchors.contains { $0.letter == "r" }
        return period(at: now, anchors: anchors, middle: polar ? ["m": "0", "n": "2"] : ["r": "0", "n": "1", "s": "2", "m": "3"])
    }

    /// Every boundary between sun periods in the solar day containing `now`.
    public static func boundaries(inDayContaining now: Date, at coordinate: Coordinate) -> [Date] {
        let day = SolarCalculator.solarDay(containing: now, at: coordinate)
        var ends: [Date] = []
        var t = day.solarMidnight.addingTimeInterval(0.001)
        while t < day.nextSolarMidnight, ends.count < 40, let p = sun(at: t, coordinate: coordinate) {
            ends.append(p.end)
            t = p.end.addingTimeInterval(0.001)
        }
        return ends
    }

    // MARK: Words

    public static let milestoneNames = [
        "R": "sunrise", "N": "solar noon", "S": "sunset", "M": "solar midnight",
        "r": "moonrise", "n": "the moon's highest", "s": "moonset", "m": "the moon's lowest",
    ]
    private static let middleNames = ["0": "mid-morning", "1": "mid-afternoon", "2": "mid-evening", "3": "deep night"]
    private static let nextMilestone = ["R": "N", "N": "S", "S": "M", "M": "R"]

    /// "after solar noon", "around sunset", "mid-afternoon".
    public static func phrase(_ p: Period) -> String {
        let letter = p.code.filter { $0 != "-" && $0 != "+" }
        if let digit = p.code.first, digit.isNumber {
            // The usual solar quarters have names; the moon's and polar days' are described.
            return nextMilestone[p.from.letter] == p.to.letter
                ? middleNames[p.code] ?? p.code
                : "between \(milestoneNames[p.from.letter] ?? p.from.letter) and \(milestoneNames[p.to.letter] ?? p.to.letter)"
        }
        let name = milestoneNames[letter] ?? letter
        if p.code.hasPrefix("-") { return "before \(name)" }
        if p.code.hasSuffix("+") { return "after \(name)" }
        return "around \(name)"
    }
}

// MARK: - Wadokei

public enum Wadokei {
    public struct Hour: Hashable, Sendable {
        /// The zodiac animal's kanji, e.g. 午.
        public let kanji: String
        /// "Horse"
        public let animal: String
        /// The bell count the hour was called by (九つ at noon and midnight, then down to 四つ).
        public let count: Int
        public let start: Date
        public let end: Date

        public var isDaylight: Bool { Wadokei.day.contains { $0.kanji == kanji } }
        /// "九つ"
        public var countName: String { ["四つ", "五つ", "六つ", "七つ", "八つ", "九つ"][count - 4] }
    }

    private struct Name { let kanji: String, animal: String, count: Int }

    /// In order from dusk: 酉 (暮れ六つ) through to 寅.
    private static let night = [
        Name(kanji: "酉", animal: "Rooster", count: 6), Name(kanji: "戌", animal: "Dog", count: 5),
        Name(kanji: "亥", animal: "Boar", count: 4), Name(kanji: "子", animal: "Rat", count: 9),
        Name(kanji: "丑", animal: "Ox", count: 8), Name(kanji: "寅", animal: "Tiger", count: 7),
    ]
    private static let day = [
        Name(kanji: "卯", animal: "Rabbit", count: 6), Name(kanji: "辰", animal: "Dragon", count: 5),
        Name(kanji: "巳", animal: "Snake", count: 4), Name(kanji: "午", animal: "Horse", count: 9),
        Name(kanji: "未", animal: "Goat", count: 8), Name(kanji: "申", animal: "Monkey", count: 7),
    ]

    /// The Kansei calendar's dawn and dusk: the sun 7°21'40" below the horizon.
    public static let twilightAltitude = -(7 + 21.0 / 60 + 40.0 / 3600)

    /// The animal's English name for a kanji, e.g. "Horse" for 午.
    public static func animal(for kanji: String) -> String? {
        (night + day).first { $0.kanji == kanji }?.animal
    }

    /// The twelve temporal hours of the solar day containing `now`, plus the hours either
    /// side of it. Without a dawn or dusk (polar days and nights), the hours fall back to
    /// equal two-hour steps with 子 starting at solar midnight, as fixed-hour clocks did.
    public static func hours(around now: Date, at coordinate: Coordinate) -> [Hour] {
        let today = SolarCalculator.solarDay(containing: now, at: coordinate)
        let days = [-1, 0, 1].map { k in
            k == 0 ? today : SolarCalculator.solarDay(nearestNoonTo: today.solarNoon.addingTimeInterval(Double(k) * 86_400), at: coordinate)
        }
        let twilights = days.map { d in
            (dawn: SolarCalculator.crossing(altitude: twilightAltitude, direction: -1, noon: d.solarNoon, coordinate: coordinate).date,
             dusk: SolarCalculator.crossing(altitude: twilightAltitude, direction: 1, noon: d.solarNoon, coordinate: coordinate).date)
        }
        var hours: [Hour] = []
        func split(_ start: Date, _ end: Date, _ names: [Name]) {
            let step = end.timeIntervalSince(start) / 6
            for (k, n) in names.enumerated() {
                hours.append(Hour(kanji: n.kanji, animal: n.animal, count: n.count,
                                  start: start.addingTimeInterval(step * Double(k)), end: start.addingTimeInterval(step * Double(k + 1))))
            }
        }
        let instants = twilights.compactMap { t in t.dawn.flatMap { dawn in t.dusk.map { (dawn, $0) } } }
        if instants.count == 3 {
            for k in 0..<3 {
                if k > 0 { split(instants[k - 1].1, instants[k].0, night) }
                split(instants[k].0, instants[k].1, day)
            }
        } else {
            // Equal hours: 子 from solar midnight, 午 from solar noon.
            let order = Array(night[3...]) + day + Array(night[..<3]) // 子 … 亥
            for d in days {
                let step = d.nextSolarMidnight.timeIntervalSince(d.solarMidnight) / 12
                for (k, n) in order.enumerated() {
                    hours.append(Hour(kanji: n.kanji, animal: n.animal, count: n.count,
                                      start: d.solarMidnight.addingTimeInterval(step * Double(k)),
                                      end: d.solarMidnight.addingTimeInterval(step * Double(k + 1))))
                }
            }
        }
        return hours
    }

    public static func hour(at now: Date, coordinate: Coordinate) -> Hour? {
        hours(around: now, at: coordinate).first { $0.start <= now && now < $0.end }
    }

    /// One of each animal for the dial: the hours overlapping the solar day containing
    /// `now`, each the one nearest to now, at the dial angle of its middle.
    public struct RingHour: Hashable, Sendable {
        public let kanji: String
        public let angle: Double
        public let isActive: Bool
    }

    public static func ring(at now: Date, coordinate: Coordinate) -> [RingHour] {
        let day = SolarCalculator.solarDay(containing: now, at: coordinate)
        var nearest: [String: (hour: RingHour, distance: TimeInterval)] = [:]
        var order: [String] = []
        for h in hours(around: now, at: coordinate) where h.end >= day.solarMidnight && h.start <= day.nextSolarMidnight {
            let middle = h.start.addingTimeInterval(h.end.timeIntervalSince(h.start) / 2)
            let distance = abs(middle.timeIntervalSince(now))
            if let prior = nearest[h.kanji], prior.distance <= distance { continue }
            if nearest[h.kanji] == nil { order.append(h.kanji) }
            nearest[h.kanji] = (RingHour(kanji: h.kanji, angle: DialModel.angle(for: middle, longitude: coordinate.longitude),
                                         isActive: h.start <= now && now < h.end), distance)
        }
        return order.compactMap { nearest[$0]?.hour }
    }
}

// MARK: - Roman hours

/// The Roman day (like the Babylonian, Greek and medieval European ones) ran from sunrise
/// to sunset in twelve equal hours, so an hour stretched to about 80 minutes in summer and
/// shrank to 40 in winter; hora sexta ended at midday. The night was kept in four watches
/// (vigiliae) from sunset to sunrise, each three night hours long.
public enum RomanHours {
    public struct Hour: Hashable, Sendable {
        public enum Kind: Hashable, Sendable { case hora, vigilia }

        public let kind: Kind
        /// 1…12 for hours of the day, 1…4 for watches of the night.
        public let number: Int
        public let start: Date
        public let end: Date

        /// "Hora VII", "Vigilia II"
        public var title: String { "\(kind == .hora ? "Hora" : "Vigilia") \(RomanHours.numeral(number))" }

        /// "seventh hour of the day", "second watch of the night"
        public var phrase: String {
            "\(RomanHours.ordinals[number]) \(kind == .hora ? "hour of the day" : "watch of the night")"
        }

        /// Which of the twelve night hours `now` falls in, during a watch.
        public func nightHour(at now: Date) -> Int {
            let fraction = now.timeIntervalSince(start) / end.timeIntervalSince(start)
            return min(12, (number - 1) * 3 + Int(fraction * 3) + 1)
        }
    }

    static let ordinals = ["", "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth", "eleventh", "twelfth"]

    public static func numeral(_ n: Int) -> String {
        let numerals = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"]
        return numerals.indices.contains(n) ? numerals[n] : String(n)
    }

    /// The Roman hours and watches around `now` (the solar days either side of it too).
    /// Without a sunrise or sunset (polar days and nights), the day falls back to the
    /// equinox's: six equal hours either side of solar noon.
    public static func hours(around now: Date, at coordinate: Coordinate) -> [Hour] {
        let today = SolarCalculator.solarDay(containing: now, at: coordinate)
        let days = [-1, 0, 1].map { k in
            k == 0 ? today : SolarCalculator.solarDay(nearestNoonTo: today.solarNoon.addingTimeInterval(Double(k) * 86_400), at: coordinate)
        }
        let horizons = days.compactMap { d in d[.sunrise].date.flatMap { rise in d[.sunset].date.map { (rise, $0) } } }
        let bounds = horizons.count == days.count
            ? horizons
            : days.map { ($0.solarNoon.addingTimeInterval(-6 * 3600), $0.solarNoon.addingTimeInterval(6 * 3600)) }
        var hours: [Hour] = []
        func split(_ kind: Hour.Kind, _ start: Date, _ end: Date, _ count: Int) {
            let step = end.timeIntervalSince(start) / Double(count)
            for k in 0..<count {
                hours.append(Hour(kind: kind, number: k + 1, start: start.addingTimeInterval(step * Double(k)),
                                  end: start.addingTimeInterval(step * Double(k + 1))))
            }
        }
        for (k, b) in bounds.enumerated() {
            if k > 0 { split(.vigilia, bounds[k - 1].1, b.0, 4) }
            split(.hora, b.0, b.1, 12)
        }
        return hours
    }

    public static func hour(at now: Date, coordinate: Coordinate) -> Hour? {
        hours(around: now, at: coordinate).first { $0.start <= now && now < $0.end }
    }
}
