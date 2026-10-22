import Foundation
import Testing
@testable import SunCore

struct ReadoutTests {
    let seattle = Coordinate(latitude: 47.61, longitude: -122.33)
    let tromso = Coordinate(latitude: 69.65, longitude: 18.96)

    @Test func afternoonReadsSinceSunriseAndUntilSunset() throws {
        // Sunrise 05:11:33, sunset 21:10:52 PDT (shared fixture).
        let now = try #require(ReferenceFixture.parseInstant("2026-06-21T15:00:00-07:00"))
        let readout = SolarReadout(at: now, coordinate: seattle)
        let previous = try #require(readout.previousHorizon)
        let next = try #require(readout.nextHorizon)
        #expect(previous.event == .sunrise)
        #expect(next.event == .sunset)
        #expect(SolarFormat.relative(previous, isPast: true) == "9h 48m after sunrise")
        #expect(SolarFormat.relative(next, isPast: false) == "6h 10m until sunset")
        #expect(readout.nextEvent?.event == .sunset)
        #expect(readout.polarCondition == nil)
    }

    @Test func lateEveningLooksAcrossMidnight() throws {
        let now = try #require(ReferenceFixture.parseInstant("2026-06-21T23:30:00-07:00"))
        let readout = SolarReadout(at: now, coordinate: seattle)
        #expect(readout.previousHorizon?.event == .sunset)
        #expect(readout.nextHorizon?.event == .sunrise)
        // Astronomical dusk is at 00:19 the next calendar day.
        #expect(readout.nextEvent?.event == .astronomicalDusk)
        let nextSunrise = try #require(readout.nextHorizon?.date)
        #expect(nextSunrise > now)
        #expect(nextSunrise.timeIntervalSince(now) < 7 * 3600)
    }

    @Test func midnightSunHasNoHorizonEvents() throws {
        let now = try #require(ReferenceFixture.parseInstant("2026-06-21T12:00:00+02:00"))
        let readout = SolarReadout(at: now, coordinate: tromso)
        #expect(readout.polarCondition == .midnightSun)
        #expect(readout.previousHorizon == nil)
        #expect(readout.nextHorizon == nil)
        #expect(readout.nextEvent?.event == .solarMidnight || readout.nextEvent?.event == .solarNoon)
    }

    @Test func polarNight() throws {
        let now = try #require(ReferenceFixture.parseInstant("2026-12-21T12:00:00+01:00"))
        #expect(SolarReadout(at: now, coordinate: tromso).polarCondition == .polarNight)
    }

    static let durations: [(Double, String)] = [
        (0, "<1m"), (59, "<1m"), (60, "1m"), (840, "14m"),
        (8099, "2h 14m"), (97_200, "27h 0m"),
    ]

    @Test(arguments: durations)
    func durationFormatting(seconds: Double, expected: String) {
        #expect(SolarFormat.duration(seconds) == expected)
    }

    @Test func solarClockFormatting() {
        #expect(SolarFormat.solarClock(minutes: 702.9) == "11:42")
        #expect(SolarFormat.solarClock(minutes: 5) == "00:05")
        #expect(SolarFormat.solarClock(minutes: 1439.99) == "23:59")
    }
}

struct DialModelTests {
    let seattle = Coordinate(latitude: 47.61, longitude: -122.33)
    let tromso = Coordinate(latitude: 69.65, longitude: 18.96)

    private func day(_ isoNoon: String, _ coordinate: Coordinate) throws -> (SolarDay, Date) {
        let now = try #require(ReferenceFixture.parseInstant(isoNoon))
        return (SolarCalculator.solarDay(containing: now, at: coordinate), now)
    }

    @Test func noonAtTopMidnightAtBottom() throws {
        let (day, now) = try day("2026-06-21T15:00:00-07:00", seattle)
        let model = DialModel(day: day, now: now)
        let noon = try #require(model.markers.first { $0.event == .solarNoon })
        let midnight = try #require(model.markers.first { $0.event == .solarMidnight })
        #expect(abs(noon.angle) < 0.1)
        #expect(abs(abs(midnight.angle) - 180) < 0.1)
        // 15:00 PDT is ~1h49m after solar noon: ~27 degrees clockwise.
        #expect(model.nowAngle > 25 && model.nowAngle < 30)
    }

    @Test func summerDayArcSpansTheTopSymmetrically() throws {
        let (day, now) = try day("2026-06-21T15:00:00-07:00", seattle)
        let model = DialModel(day: day, now: now)
        let dayArc = try #require(model.arcs.first { $0.band == .day })
        #expect(dayArc.start < 0 && dayArc.end > 0)
        #expect(abs(dayArc.start + dayArc.end) < 1)
        // ~16 hours of daylight = ~240 degrees.
        #expect(abs((dayArc.end - dayArc.start) - 240) < 2)
        #expect(model.arcs.map(\.band) == DialModel.Band.allCases)
    }

    @Test func midnightSunFillsTheDial() throws {
        let (day, now) = try day("2026-06-21T12:00:00+02:00", tromso)
        let model = DialModel(day: day, now: now)
        #expect(model.arcs.count == 4)
        #expect(model.arcs.allSatisfy { $0.isFullCircle })
    }

    @Test func polarNightHasTwilightButNoDay() throws {
        let (day, now) = try day("2026-12-21T12:00:00+01:00", tromso)
        let model = DialModel(day: day, now: now)
        #expect(model.arcs.map(\.band) == [.astronomicalTwilight, .nauticalTwilight, .civilTwilight])
    }

    @Test func solarHourAngles() {
        #expect(DialModel.angle(forSolarHour: 12) == 0)
        #expect(DialModel.angle(forSolarHour: 18) == 90)
        #expect(DialModel.angle(forSolarHour: 6) == -90)
    }
}
