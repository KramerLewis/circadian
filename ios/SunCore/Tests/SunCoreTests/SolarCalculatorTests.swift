import Foundation
import Testing
@testable import SunCore

/// Checks SolarCalculator against shared/fixtures/solar-reference.json, the reference
/// values every platform tests against (see shared/tools/generate_solar_fixtures.py).
struct SolarCalculatorTests {
    @Test(arguments: ReferenceFixture.shared.cases)
    func matchesReference(_ reference: ReferenceCase) throws {
        let timeZone = try #require(TimeZone(identifier: reference.timeZone))
        let date = try #require(ReferenceFixture.parseDay(reference.date, in: timeZone))
        let day = SolarCalculator.solarDay(for: date, at: reference.coordinate, in: timeZone)
        let tolerance = ReferenceFixture.shared.toleranceSeconds

        for event in SolarEvent.allCases {
            let expected = try #require(reference.events[event.rawValue], "fixture is missing \(event)")
            let actual = day[event]
            switch expected {
            case "sunAlwaysAbove":
                #expect(actual == .sunAlwaysAbove, "\(event): expected sun always above, got \(actual)")
            case "sunAlwaysBelow":
                #expect(actual == .sunAlwaysBelow, "\(event): expected sun always below, got \(actual)")
            default:
                let expectedDate = try #require(ReferenceFixture.parseInstant(expected), "bad date \(expected)")
                let actualDate = try #require(actual.date, "\(event): expected \(expected), got \(actual)")
                let delta = actualDate.timeIntervalSince(expectedDate)
                #expect(abs(delta) <= tolerance, "\(event): off by \(Int(delta))s (expected \(expected))")
            }
        }
    }

    @Test func eventsAreChronological() {
        let seattle = Coordinate(latitude: 47.61, longitude: -122.33)
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let day = SolarCalculator.solarDay(for: ReferenceFixture.parseDay("2026-06-21", in: timeZone)!, at: seattle, in: timeZone)
        let dates = day.events.compactMap(\.time.date)
        #expect(dates.count == SolarEvent.allCases.count)
        #expect(dates == dates.sorted())
        #expect(dates.last! < day.nextSolarMidnight)
    }

    @Test func solarDayContainingInstant() {
        let seattle = Coordinate(latitude: 47.61, longitude: -122.33)
        // 00:30 PDT on June 21 is before that morning's solar midnight (~01:11),
        // so it belongs to the solar day of June 20.
        let instant = ReferenceFixture.parseInstant("2026-06-21T00:30:00-07:00")!
        let day = SolarCalculator.solarDay(containing: instant, at: seattle)
        #expect(day.contains(instant))
        #expect(day.solarNoon < instant)

        let afternoon = ReferenceFixture.parseInstant("2026-06-21T15:00:00-07:00")!
        let today = SolarCalculator.solarDay(containing: afternoon, at: seattle)
        #expect(today.contains(afternoon))
        #expect(today.solarNoon < afternoon)
        #expect(today.solarNoon > instant)
    }

    @Test func apparentSolarTimeIsNoonAtSolarNoon() {
        let seattle = Coordinate(latitude: 47.61, longitude: -122.33)
        let noon = SolarCalculator.solarDay(containing: .now, at: seattle).solarNoon
        let minutes = SolarCalculator.apparentSolarMinutes(at: noon, longitude: seattle.longitude)
        #expect(abs(minutes - 720) < 0.1)
    }

    @Test func handlesThePoles() {
        let timeZone = TimeZone(identifier: "UTC")!
        let june = ReferenceFixture.parseDay("2026-06-21", in: timeZone)!
        let north = SolarCalculator.solarDay(for: june, at: Coordinate(latitude: 90, longitude: 0), in: timeZone)
        let south = SolarCalculator.solarDay(for: june, at: Coordinate(latitude: -90, longitude: 0), in: timeZone)
        #expect(north[.sunrise] == .sunAlwaysAbove)
        #expect(south[.sunrise] == .sunAlwaysBelow)
        #expect(south[.astronomicalDawn] == .sunAlwaysBelow)
    }
}

// MARK: - Fixture loading

struct ReferenceCase: Decodable, Sendable, CustomTestStringConvertible {
    let name: String
    let latitude: Double
    let longitude: Double
    let timeZone: String
    let date: String
    let events: [String: String]

    var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
    var testDescription: String { "\(name) (\(date))" }
}

struct ReferenceFixture: Decodable, Sendable {
    let toleranceSeconds: Double
    let cases: [ReferenceCase]

    static let shared: ReferenceFixture = {
        // Tests run from the source tree, so walk up from this file to the repo root.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SunCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // SunCore
            .deletingLastPathComponent() // ios
            .deletingLastPathComponent() // repo root
            .appending(path: "shared/fixtures/solar-reference.json")
        do {
            return try JSONDecoder().decode(ReferenceFixture.self, from: Data(contentsOf: url))
        } catch {
            fatalError("Could not load \(url.path): \(error)")
        }
    }()

    static func parseInstant(_ string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }

    /// Local midnight of a yyyy-MM-dd date in `timeZone`.
    static func parseDay(_ string: String, in timeZone: TimeZone) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
