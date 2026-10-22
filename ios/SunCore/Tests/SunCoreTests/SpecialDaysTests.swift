import Foundation
import Testing
@testable import SunCore

/// Against PyEphem (`ephem.next_solstice`, `next_full_moon`, …) for 2026.
struct SpecialDaysTests {
    let utc = TimeZone(identifier: "UTC")!
    let pacific = TimeZone(identifier: "America/Los_Angeles")!
    let tolerance: TimeInterval = 15 * 60

    func instant(_ iso: String) -> Date { ReferenceFixture.parseInstant(iso)! }

    func year2026() -> [SkyCalendar.Occurrence] {
        SkyCalendar.occurrences(from: instant("2026-01-01T00:00:00Z"), to: instant("2027-01-01T00:00:00Z"), in: utc)
    }

    @Test func seasons() throws {
        let expected: [(SkyCalendar.Season, String)] = [
            (.marchEquinox, "2026-03-20T14:45:53Z"), (.juneSolstice, "2026-06-21T08:24:31Z"),
            (.septemberEquinox, "2026-09-23T00:05:09Z"), (.decemberSolstice, "2026-12-21T20:50:00Z"),
        ]
        let seasons = year2026().filter { if case .season = $0.kind { true } else { false } }
        #expect(seasons.count == 4)
        for (season, iso) in expected {
            let found = try #require(seasons.first { $0.kind == .season(season) })
            #expect(abs(found.date.timeIntervalSince(instant(iso))) < tolerance, "\(season)")
        }
    }

    @Test func fullMoonsSupermoonsAndTheBlueMoon() throws {
        let fulls = year2026().filter { if case .fullMoon = $0.kind { true } else { false } }
        #expect(fulls.count == 13)
        let dec24 = try #require(fulls.last)
        #expect(abs(dec24.date.timeIntervalSince(instant("2026-12-24T01:28:09Z"))) < tolerance)
        #expect(dec24.kind == .fullMoon(supermoon: true, blueMoon: false))
        #expect(abs(dec24.moonDistance! - 356_738) < 1_500)
        // May 2026 has two full moons; the second (May 31) is a blue moon.
        let blue = fulls.filter { if case .fullMoon(_, true) = $0.kind { true } else { false } }
        #expect(blue.count == 1)
        #expect(abs(blue[0].date.timeIntervalSince(instant("2026-05-31T08:45:08Z"))) < tolerance)
        #expect(blue[0].title(southern: false) == "Blue moon")
    }

    @Test func newMoon() throws {
        let news = SkyCalendar.occurrences(from: instant("2026-12-01T00:00:00Z"), to: instant("2026-12-31T00:00:00Z"), in: utc)
            .filter { $0.kind == .newMoon }
        #expect(news.count == 1)
        #expect(abs(news[0].date.timeIntervalSince(instant("2026-12-09T00:51:47Z"))) < tolerance)
    }

    @Test func dayLookupUsesLocalDates() throws {
        // The Dec 24 01:28 UTC full moon is on Dec 23 in Seattle.
        let seattleDay = try #require(SkyCalendar.event(onDayOf: instant("2026-12-23T12:00:00-08:00"), in: pacific))
        #expect(seattleDay.title(southern: false) == "Supermoon")
        #expect(SkyCalendar.event(onDayOf: instant("2026-12-24T12:00:00-08:00"), in: pacific) == nil)
        let june = try #require(SkyCalendar.event(onDayOf: instant("2026-06-21T12:00:00-07:00"), in: pacific))
        #expect(june.title(southern: false) == "Summer solstice")
        #expect(june.title(southern: true) == "Winter solstice")
    }

    @Test func headsUp() throws {
        let next = try #require(SkyCalendar.upcoming(after: instant("2026-12-20T12:00:00-08:00"), within: 3, in: pacific))
        #expect(next.kind == .season(.decemberSolstice))
        #expect(SkyCalendar.upcoming(after: instant("2026-12-12T12:00:00-08:00"), within: 3, in: pacific) == nil)
    }
}
