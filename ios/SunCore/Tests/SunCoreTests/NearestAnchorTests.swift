import Foundation
import Testing
@testable import SunCore

struct NearestAnchorTests {
    let seattle = Coordinate(latitude: 47.61, longitude: -122.33)

    func readout(_ iso: String) -> SolarReadout {
        SolarReadout(at: ReferenceFixture.parseInstant(iso)!, coordinate: seattle)
    }

    @Test func afternoonCountsFromSolarNoon() throws {
        // Solar noon 13:11:13, sunset 21:10:52 PDT: 15:00 is closer to noon.
        let r = readout("2026-06-21T15:00:00-07:00")
        let anchor = try #require(r.nearestAnchor)
        #expect(anchor.event == .solarNoon)
        #expect(r.nearestAnchorIsPast)
        #expect(SolarFormat.relative(anchor, isPast: r.nearestAnchorIsPast) == "1h 48m after solar noon")
    }

    @Test func eveningCountsDownToSunset() throws {
        let r = readout("2026-06-21T19:00:00-07:00")
        let anchor = try #require(r.nearestAnchor)
        #expect(anchor.event == .sunset)
        #expect(!r.nearestAnchorIsPast)
        #expect(SolarFormat.relative(anchor, isPast: false) == "2h 10m until sunset")
    }

    @Test func polarDaysStillHaveNoonAndMidnight() throws {
        let tromso = Coordinate(latitude: 69.65, longitude: 18.96)
        let r = SolarReadout(at: ReferenceFixture.parseInstant("2026-06-21T20:00:00+02:00")!, coordinate: tromso)
        let anchor = try #require(r.nearestAnchor)
        #expect(anchor.event == .solarNoon || anchor.event == .solarMidnight)
    }
}
