import Foundation
import SunCore

/// The banner for a special sky day: a symbol, a title and a fact or two about today,
/// and how the dial should mark it.
struct SpecialDayText: Equatable {
    enum Style: Equatable {
        case solstice, equinox, zenith, fullMoon, supermoon, blueMoon, newMoon, lunarEclipse, solarEclipse
    }

    var symbol: String
    var title: String
    var lines: [String]
    var style: Style
    /// Short form for complications and widgets: "Supermoon tonight".
    var short: String

    init(_ occurrence: SkyCalendar.Occurrence, at coordinate: Coordinate, on date: Date) {
        let southern = coordinate.latitude < 0
        title = occurrence.title(southern: southern)
        switch occurrence.kind {
        case .season(let season):
            let day = SolarCalculator.solarDay(for: date, at: coordinate, in: .current)
            let daylight = day[.sunrise].date.flatMap { rise in day[.sunset].date.map { $0.timeIntervalSince(rise) } }
            let length = daylight.map(SolarFormat.duration)
            if season.isSolstice {
                let longest = title.hasPrefix("Summer")
                symbol = longest ? "sun.max.fill" : "sun.min.fill"
                style = .solstice
                lines = [
                    length.map { "\($0) of daylight, the \(longest ? "most" : "least") all year." } ?? (longest ? "The longest day of the year." : "The shortest day of the year."),
                    "Days start getting \(longest ? "shorter" : "longer") tomorrow.",
                ]
            } else {
                symbol = "circle.lefthalf.filled"
                style = .equinox
                lines = ["Day and night are nearly equal" + (length.map { ": \($0) of daylight." } ?? "."),
                         "The sun rises due east and sets due west."]
            }
            short = title
        case .fullMoon(let supermoon, let blue):
            symbol = "moon.fill"
            style = supermoon ? .supermoon : blue ? .blueMoon : .fullMoon
            var facts: [String] = []
            if supermoon, let km = occurrence.moonDistance {
                facts.append("Full moon closest to Earth: \(Int(km).formatted()) km.")
                facts.append("About 7% bigger and 15% brighter than usual.")
            }
            if blue { facts.append("The second full moon this month.") }
            let start = Calendar.current.startOfDay(for: date)
            if let rise = LunarCalculator.events(from: start, to: start.addingTimeInterval(86_400), at: coordinate)
                .first(where: { $0.event == .moonrise }) {
                facts.append("Moonrise at \(rise.date.formatted(date: .omitted, time: .shortened)).")
            }
            lines = Array(facts.prefix(2))
            short = "\(title) tonight"
        case .newMoon:
            symbol = "moon.stars.fill"
            style = .newMoon
            lines = ["The darkest skies of the month:", "good for stargazing tonight."]
            short = "New moon: dark skies"
        }
    }

    init(_ passage: ZenithPassage, at coordinate: Coordinate) {
        symbol = "sun.max.circle.fill"
        style = .zenith
        title = "Zenith passage"
        let next = ZenithPassage.next(after: passage.date, at: coordinate)
        lines = [
            "The sun passes straight overhead at \(passage.date.formatted(date: .omitted, time: .shortened)): upright things cast almost no shadow.",
            next.map { "The next one is \($0.date.formatted(.dateTime.month(.wide).day()))." } ?? "It happens twice a year between the tropics.",
        ]
        short = "Sun overhead at noon"
    }

    /// The zenith passage on the local day containing `date`, if any (only between the tropics).
    static func zenith(onDayOf date: Date, at coordinate: Coordinate) -> ZenithPassage? {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return ZenithPassage.passages(from: start, to: end, at: coordinate).first
    }

    /// Today's special day at a place, if any. An eclipse visible here outranks
    /// everything else, then a solstice or equinox, then a zenith passage, then the moon.
    static func today(at coordinate: Coordinate, on date: Date) -> SpecialDayText? {
        if let eclipse = VisibleEclipse.on(dayOf: date, at: coordinate) {
            return SpecialDayText(eclipse, at: coordinate)
        }
        let sky = SkyCalendar.event(onDayOf: date, in: .current)
        if let sky, case .season = sky.kind { return SpecialDayText(sky, at: coordinate, on: date) }
        if let passage = zenith(onDayOf: date, at: coordinate) { return SpecialDayText(passage, at: coordinate) }
        return sky.map { SpecialDayText($0, at: coordinate, on: date) }
    }

    init(_ eclipse: VisibleEclipse, at coordinate: Coordinate) {
        func time(_ date: Date?) -> String { date?.formatted(date: .omitted, time: .shortened) ?? "?" }
        switch eclipse {
        case .lunar(let e):
            style = .lunarEclipse
            symbol = "moon.fill"
            let moonUp = { (date: Date?) in date.map { LunarCalculator.altitude(at: $0, coordinate: coordinate) > 0 } ?? false }
            switch e.kind {
            case .total:
                title = "Total lunar eclipse"
                let whole = moonUp(e.totalStart) && moonUp(e.totalEnd)
                lines = ["A blood moon: totality \(time(e.totalStart))–\(time(e.totalEnd)).",
                         whole ? "The moon is up for all of totality." : "Part of totality happens with the moon below the horizon."]
                short = "Blood moon tonight"
            case .partial:
                title = "Partial lunar eclipse"
                lines = ["\(Int((e.umbralMagnitude * 100).rounded()))% of the moon in Earth's shadow at \(time(e.greatest)).",
                         "Partial phase \(time(e.partialStart))–\(time(e.partialEnd))."]
                short = "Lunar eclipse tonight"
            case .penumbral:
                title = "Penumbral lunar eclipse"
                lines = ["A subtle dimming of the moon, deepest at \(time(e.greatest)).",
                         "Easiest to see in photos."]
                short = "Lunar eclipse tonight"
            }
        case .solar(let e):
            style = .solarEclipse
            symbol = "circle.dashed.inset.filled"
            let window = "\(time(e.start))–\(time(e.end))"
            switch e.kind {
            case .total:
                title = "Total solar eclipse"
                lines = ["Totality here \(time(e.centralStart))–\(time(e.centralEnd)).",
                         "Eclipse \(window). Use eclipse glasses except during totality."]
            case .annular:
                title = "Annular solar eclipse"
                lines = ["A ring of fire \(time(e.centralStart))–\(time(e.centralEnd)).",
                         "Eclipse \(window). Always use eclipse glasses."]
            case .partial:
                title = "Partial solar eclipse"
                lines = ["\(Int((e.obscuration * 100).rounded()))% of the sun covered at \(time(e.maximum)).",
                         "Eclipse \(window). Always use eclipse glasses."]
            }
            short = "Solar eclipse today"
        }
    }

    /// "Full moon in 2 days", for the next special day within three days.
    static func headsUp(at coordinate: Coordinate, after date: Date) -> String? {
        let calendar = Calendar.current
        func when(_ day: Date) -> String {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: day)).day ?? 0
            return days <= 1 ? "tomorrow" : "in \(days) days"
        }
        for offset in 1...3 {
            if let day = calendar.date(byAdding: .day, value: offset, to: date),
               let eclipse = VisibleEclipse.on(dayOf: day, at: coordinate) {
                return "\(SpecialDayText(eclipse, at: coordinate).title) \(when(day))"
            }
        }
        let next = SkyCalendar.upcoming(after: date, within: 3, in: .current)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        if let zenith = ZenithPassage.passages(from: tomorrow, to: tomorrow.addingTimeInterval(3 * 86_400), at: coordinate).first,
           next.map({ zenith.date < $0.date }) ?? true {
            return "Zenith passage \(when(zenith.date))"
        }
        guard let next else { return nil }
        return "\(next.title(southern: coordinate.latitude < 0)) \(when(next.date))"
    }
}

/// An eclipse that can be seen from a place: a lunar eclipse while the moon is up, or a
/// solar eclipse while the sun is up.
enum VisibleEclipse: Hashable {
    case lunar(EclipseCalculator.LunarEclipse)
    case solar(EclipseCalculator.SolarEclipse)

    var date: Date {
        switch self {
        case .lunar(let e): e.greatest
        case .solar(let e): e.maximum
        }
    }

    /// The eclipse visible on the local day containing `date`, if any.
    static func on(dayOf date: Date, at coordinate: Coordinate) -> VisibleEclipse? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        // Called on every frame while scrubbing the Watch dial, so remember each day.
        let key = NextKey(day: start, latitude: (coordinate.latitude * 10).rounded(), longitude: (coordinate.longitude * 10).rounded())
        if let cached = dayCache[key] { return cached.value }
        let found = all(from: start, to: end, at: coordinate).first
        if dayCache.count > 16 { dayCache.removeAll() }
        dayCache[key] = Box(value: found)
        return found
    }

    /// The next visible eclipse after `date`, looking up to `days` ahead.
    static func next(after date: Date, at coordinate: Coordinate, days: Int = 400) -> VisibleEclipse? {
        let key = NextKey(day: Calendar.current.startOfDay(for: date), latitude: (coordinate.latitude * 10).rounded(), longitude: (coordinate.longitude * 10).rounded())
        if let cached = nextCache[key] { return cached.value }
        let found = all(from: date, to: date.addingTimeInterval(Double(days) * 86_400), at: coordinate).first { $0.date > date }
        if nextCache.count > 8 { nextCache.removeAll() }
        nextCache[key] = Box(value: found)
        return found
    }

    private struct NextKey: Hashable { let day: Date; let latitude, longitude: Double }
    private struct Box { let value: VisibleEclipse? }
    private static var nextCache: [NextKey: Box] = [:]
    private static var dayCache: [NextKey: Box] = [:]

    private static func all(from start: Date, to end: Date, at coordinate: Coordinate) -> [VisibleEclipse] {
        let lunar = EclipseCalculator.lunarEclipses(from: start.addingTimeInterval(-43_200), to: end.addingTimeInterval(43_200))
            .filter { $0.greatest >= start && $0.greatest < end }
            .filter { e in
                // Visible if the moon is up at any point of the eclipse.
                [e.penumbralStart, e.partialStart, e.totalStart, e.greatest, e.totalEnd, e.partialEnd, e.penumbralEnd]
                    .compactMap { $0 }
                    .contains { LunarCalculator.altitude(at: $0, coordinate: coordinate) > 0 }
            }
            .map(VisibleEclipse.lunar)
        let solar = EclipseCalculator.solarEclipses(from: start.addingTimeInterval(-43_200), to: end.addingTimeInterval(43_200), at: coordinate)
            .filter { $0.maximum >= start && $0.maximum < end }
            .filter { e in
                [e.start, e.maximum, e.end].contains { t in
                    SolarCalculator.altitude(
                        hourAngle: SolarCalculator.hourAngle(at: t, longitude: coordinate.longitude),
                        latitude: coordinate.latitude,
                        declination: SolarCalculator.position(at: t).declination
                    ) > -0.833
                }
            }
            .map(VisibleEclipse.solar)
        return (lunar + solar).sorted { $0.date < $1.date }
    }
}
