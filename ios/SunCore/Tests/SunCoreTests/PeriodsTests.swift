import Foundation
import Testing
@testable import SunCore

/// Mirrors web/tests/periods.test.ts.
struct SunPeriodsTests {
    let seattle = Coordinate(latitude: 47.61, longitude: -122.33)
    let middles = ["R": "0", "N": "1", "S": "2", "M": "3"]
    let hour: TimeInterval = 3600

    /// A 12-hour day: sunrise 6:00, noon 12:00, sunset 18:00, midnight 24:00 (all equal quarters).
    var anchors: [SunPeriods.Anchor] {
        zip(["M", "R", "N", "S", "M", "R"], [0.0, 6, 12, 18, 24, 30]).map {
            SunPeriods.Anchor(letter: $0, date: Date(timeIntervalSince1970: $1 * hour))
        }
    }

    func code(_ hours: Double) -> String? {
        SunPeriods.period(at: Date(timeIntervalSince1970: hours * hour), anchors: anchors, middle: middles)?.code
    }

    @Test func theSixteenSectionsInOrder() {
        let hours = [5.9, 6, 6.3, 7, 9, 11, 11.9, 12.1, 13, 15, 17, 18, 19, 21, 23, 24.1, 25, 27, 29.9]
        #expect(hours.map(code) == ["R", "R", "R+", "R+", "0", "-N", "N", "N", "N+", "1", "-S", "S", "S+", "2", "-M", "M", "M+", "3", "R"])
    }

    @Test func milestoneWindowsAreFifteenMinutesEitherSide() throws {
        let p = try #require(SunPeriods.period(at: Date(timeIntervalSince1970: 12 * hour), anchors: anchors, middle: middles))
        #expect(p.code == "N")
        #expect(p.end.timeIntervalSince(p.start) == 2 * SunPeriods.milestoneGrace)
        #expect(code(12 - (SunPeriods.milestoneGrace + 1) / hour) == "-N")
    }

    @Test func seattleOnTheJuneSolstice() throws {
        let afternoon = try #require(ReferenceFixture.parseInstant("2026-06-21T15:00:00-07:00"))
        #expect(SunPeriods.sun(at: afternoon, coordinate: seattle)?.code == "N+")
        let sunset = try #require(ReferenceFixture.parseInstant("2026-06-21T21:10:00-07:00"))
        #expect(SunPeriods.sun(at: sunset, coordinate: seattle)?.code == "S")
        // Night is short in June (4 hours from solar midnight to sunrise), so its thirds
        // are 80 minutes: 60 minutes after midnight is still M+, 90 minutes is already 3.
        let noon = try #require(ReferenceFixture.parseInstant("2026-06-21T12:00:00-07:00"))
        let day = SolarCalculator.solarDay(containing: noon, at: seattle)
        #expect(SunPeriods.sun(at: day.solarMidnight.addingTimeInterval(60 * 60), coordinate: seattle)?.code == "M+")
        let deep = try #require(SunPeriods.sun(at: day.solarMidnight.addingTimeInterval(90 * 60), coordinate: seattle))
        #expect(deep.code == "3")
        #expect((deep.end.timeIntervalSince(deep.start) / 60).rounded() == 80)
        #expect(SunPeriods.phrase(deep) == "deep night")
    }

    @Test func polarDaysFallBackToNoonAndMidnight() throws {
        let tromso = Coordinate(latitude: 69.65, longitude: 18.96)
        let now = try #require(ReferenceFixture.parseInstant("2026-06-21T23:30:00+02:00"))
        let p = try #require(SunPeriods.sun(at: now, coordinate: tromso))
        #expect(["-M", "M", "M+", "2"].contains(p.code))
    }

    @Test func theMoonsScaleUsesLowercase() throws {
        let now = try #require(ReferenceFixture.parseInstant("2026-11-24T22:00:00-08:00"))
        let code = try #require(SunPeriods.moon(at: now, coordinate: seattle)?.code)
        #expect(code.range(of: "^-?[rnsm0-3]\\+?$", options: .regularExpression) != nil)
    }

    @Test func boundariesCoverTheDay() throws {
        let noon = try #require(ReferenceFixture.parseInstant("2026-06-21T12:00:00-07:00"))
        // Sixteen sections, so sixteen boundaries (the last can fall just past midnight).
        let count = SunPeriods.boundaries(inDayContaining: noon, at: seattle).count
        #expect((15...17).contains(count))
    }
}

struct WadokeiTests {
    let seattle = Coordinate(latitude: 47.61, longitude: -122.33)

    @Test func sixHoursFromDawnToDusk() throws {
        let noon = try #require(ReferenceFixture.parseInstant("2026-06-21T12:00:00-07:00"))
        let hours = Wadokei.hours(around: noon, at: seattle)
        #expect(hours.filter(\.isDaylight).count % 6 == 0)
        let afternoon = try #require(ReferenceFixture.parseInstant("2026-06-21T13:20:00-07:00"))
        #expect(Wadokei.hour(at: afternoon, coordinate: seattle)?.kanji == "午")
        let night = try #require(ReferenceFixture.parseInstant("2026-06-21T01:20:00-07:00"))
        #expect(Wadokei.hour(at: night, coordinate: seattle)?.kanji == "子")
        // Summer day hours are long, night hours short.
        let horse = try #require(hours.first { $0.kanji == "午" })
        let rat = try #require(hours.first { $0.kanji == "子" })
        #expect(horse.end.timeIntervalSince(horse.start) / 60 > 150)
        #expect(rat.end.timeIntervalSince(rat.start) / 60 < 80)
        #expect(horse.countName == "九つ")
    }

    @Test func theRingHasEachAnimalOnceWithOneActive() throws {
        let now = try #require(ReferenceFixture.parseInstant("2026-06-21T15:00:00-07:00"))
        let ring = Wadokei.ring(at: now, coordinate: seattle)
        #expect(Set(ring.map(\.kanji)).count == 12)
        #expect(ring.filter(\.isActive).map(\.kanji) == ["午"])
    }

    @Test func polarDaysUseEqualHours() throws {
        let tromso = Coordinate(latitude: 69.65, longitude: 18.96)
        let now = try #require(ReferenceFixture.parseInstant("2026-06-21T12:00:00+02:00"))
        let hours = Wadokei.hours(around: now, at: tromso)
        #expect(hours.count == 36)
        #expect(Wadokei.hour(at: now, coordinate: tromso) != nil)
    }
}

struct RomanHoursTests {
    let seattle = Coordinate(latitude: 47.61, longitude: -122.33)

    @Test func twelveHoursFromSunriseToSunset() throws {
        let noon = try #require(ReferenceFixture.parseInstant("2026-06-21T12:00:00-07:00"))
        let day = SolarCalculator.solarDay(containing: noon, at: seattle)
        let hours = RomanHours.hours(around: noon, at: seattle)
            .filter { $0.kind == .hora && $0.start >= day.solarMidnight && $0.end <= day.nextSolarMidnight }
        #expect(hours.map(\.number) == Array(1...12))
        #expect(hours.first?.start == day[.sunrise].date)
        #expect(hours.last?.end == day[.sunset].date)
        // Sixteen hours of daylight in June: each hour is 80 minutes.
        #expect((hours[0].end.timeIntervalSince(hours[0].start) / 60).rounded() == 80)
        #expect(abs(hours[5].end.timeIntervalSince(day.solarNoon)) / 60 < 3)
        let afternoon = try #require(ReferenceFixture.parseInstant("2026-06-21T15:00:00-07:00"))
        let hour = try #require(RomanHours.hour(at: afternoon, coordinate: seattle))
        #expect(hour.title == "Hora VIII")
        #expect(hour.phrase == "eighth hour of the day")
    }

    @Test func fourWatchesFromSunsetToSunrise() throws {
        let night = try #require(ReferenceFixture.parseInstant("2026-12-21T23:30:00-08:00"))
        let watch = try #require(RomanHours.hour(at: night, coordinate: seattle))
        #expect(watch.kind == .vigilia)
        #expect(watch.title == "Vigilia II")
        // A 16-hour December night: watches of 4 hours.
        #expect((watch.end.timeIntervalSince(watch.start) / 3600).rounded() == 4)
        #expect((4...6).contains(watch.nightHour(at: night)))
    }

    @Test func polarDaysFallBackToEqualHours() throws {
        let tromso = Coordinate(latitude: 69.65, longitude: 18.96)
        let now = try #require(ReferenceFixture.parseInstant("2026-06-21T12:00:00+02:00"))
        let hour = try #require(RomanHours.hour(at: now, coordinate: tromso))
        #expect(hour.kind == .hora)
        #expect((hour.end.timeIntervalSince(hour.start) / 60).rounded() == 60)
    }
}
