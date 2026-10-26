import Foundation
import Testing
@testable import SunCore

/// Checks LunarCalculator against shared/fixtures/lunar-reference.json
/// (see shared/tools/generate_lunar_fixtures.py).
struct LunarCalculatorTests {
    @Test(arguments: LunarFixture.shared.cases)
    func matchesReference(_ reference: LunarCase) throws {
        let timeZone = try #require(TimeZone(identifier: reference.timeZone))
        let start = try #require(ReferenceFixture.parseDay(reference.date, in: timeZone))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let end = try #require(calendar.date(byAdding: .day, value: 1, to: start))
        let coordinate = Coordinate(latitude: reference.latitude, longitude: reference.longitude)

        let events = LunarCalculator.events(from: start, to: end, at: coordinate)
        #expect(events.map(\.event.rawValue) == reference.events.map(\.event))
        for (actual, expected) in zip(events, reference.events) {
            let expectedDate = try #require(ReferenceFixture.parseInstant(expected.time))
            let delta = actual.date.timeIntervalSince(expectedDate)
            #expect(abs(delta) <= LunarFixture.shared.toleranceSeconds, "\(expected.event): off by \(Int(delta))s")
        }

        let noon = try #require(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: start))
        let phase = LunarCalculator.phase(at: noon)
        #expect(abs(phase.illumination - reference.illuminationAtNoon) <= LunarFixture.shared.illuminationTolerance)
        #expect(phase.isWaxing == reference.waxingAtNoon)
    }

    @Test func phaseNames() {
        #expect(LunarCalculator.Phase(illumination: 0.01, isWaxing: true).name == "New moon")
        #expect(LunarCalculator.Phase(illumination: 0.5, isWaxing: true).name == "First quarter")
        #expect(LunarCalculator.Phase(illumination: 0.8, isWaxing: false).name == "Waning gibbous")
        #expect(LunarCalculator.Phase(illumination: 0.99, isWaxing: false).name == "Full moon")
    }

    @Test func moonRingSharesTheSunsTimeline() throws {
        let seattle = Coordinate(latitude: 47.61, longitude: -122.33)
        let now = try #require(ReferenceFixture.parseInstant("2026-11-24T12:00:00-08:00"))
        let model = MoonDialModel(now: now, coordinate: seattle)
        // The moon sits under the sun's hand.
        #expect(abs(model.nowAngle - DialModel.angle(for: now, longitude: seattle.longitude)) < 1e-9)
        #expect(abs(model.altitude(atAngle: model.nowAngle) - model.altitudeNow) < 0.5)
        #expect(abs(model.altitudeNow - LunarCalculator.altitude(at: now, coordinate: seattle)) < 0.01)
        // Rise and set ticks land where the full event search puts them.
        let day = SolarCalculator.solarDay(containing: now, at: seattle)
        let events = LunarCalculator.events(from: day.solarMidnight, to: day.nextSolarMidnight, at: seattle)
            .filter { $0.event == .moonrise || $0.event == .moonset }
        #expect(model.horizonMarkers.map(\.event) == events.map(\.event))
        for (marker, event) in zip(model.horizonMarkers, events) {
            #expect(abs(marker.date.timeIntervalSince(event.date)) < 120, "\(marker.event)")
            #expect(abs(marker.angle - DialModel.angle(for: event.date, longitude: seattle.longitude)) < 0.5)
        }
    }

    @Test func moonColorsBrightenWithHeightAndFullness() {
        let low = MoonGradient.color(altitude: 5, riseSetAltitude: 0.1, illumination: 1, dark: false)
        let high = MoonGradient.color(altitude: 50, riseSetAltitude: 0.1, illumination: 1, dark: false)
        let newMoonHigh = MoonGradient.color(altitude: 50, riseSetAltitude: 0.1, illumination: 0, dark: false)
        #expect(high.blue > low.blue)
        #expect(high.blue > newMoonHigh.blue)
    }
}

struct LunarCase: Decodable, Sendable, CustomTestStringConvertible {
    struct Event: Decodable, Sendable {
        let event: String
        let time: String
    }

    let name: String
    let latitude: Double
    let longitude: Double
    let timeZone: String
    let date: String
    let events: [Event]
    let illuminationAtNoon: Double
    let waxingAtNoon: Bool

    var testDescription: String { "\(name) (\(date))" }
}

struct LunarFixture: Decodable, Sendable {
    let toleranceSeconds: Double
    let illuminationTolerance: Double
    let cases: [LunarCase]

    static let shared: LunarFixture = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "shared/fixtures/lunar-reference.json")
        do {
            return try JSONDecoder().decode(LunarFixture.self, from: Data(contentsOf: url))
        } catch {
            fatalError("Could not load \(url.path): \(error)")
        }
    }()
}
