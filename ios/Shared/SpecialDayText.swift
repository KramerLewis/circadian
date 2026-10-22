import Foundation
import SunCore

/// The banner for a special sky day: a symbol, a title and a fact or two about today,
/// and how the dial should mark it.
struct SpecialDayText: Equatable {
    enum Style: Equatable {
        case solstice, equinox, fullMoon, supermoon, blueMoon, newMoon
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

    /// Today's special day at a place, if any.
    static func today(at coordinate: Coordinate, on date: Date) -> SpecialDayText? {
        SkyCalendar.event(onDayOf: date, in: .current).map { SpecialDayText($0, at: coordinate, on: date) }
    }

    /// "Full moon in 2 days", for the next special day within three days.
    static func headsUp(at coordinate: Coordinate, after date: Date) -> String? {
        guard let next = SkyCalendar.upcoming(after: date, within: 3, in: .current) else { return nil }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: next.date)).day ?? 0
        let when = days <= 1 ? "tomorrow" : "in \(days) days"
        return "\(next.title(southern: coordinate.latitude < 0)) \(when)"
    }
}
