import Foundation
import Testing
@testable import SunCore

/// Mirrors web/tests/zenith.test.ts. Dates checked with PyEphem (the noon sun's peak
/// altitude each season).
struct ZenithPassageTests {
    func year(_ y: Int) -> (Date, Date) {
        (ReferenceFixture.parseInstant("\(y)-01-01T00:00:00Z")!, ReferenceFixture.parseInstant("\(y + 1)-01-01T00:00:00Z")!)
    }

    func day(_ date: Date, _ zone: String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    @Test func twiceAYearBetweenTheTropics() throws {
        // Mérida, Yucatán (20.97° N): the noon sun peaks at 89.92° on May 25 and 89.95° on July 18.
        let merida = Coordinate(latitude: 20.97, longitude: -89.62)
        let (start, end) = year(2026)
        let passages = ZenithPassage.passages(from: start, to: end, at: merida)
        #expect(passages.map { day($0.date, "America/Merida") } == ["2026-05-25", "2026-07-18"])
        for p in passages { #expect(p.altitude > 89.75) }
        let next = try #require(ZenithPassage.next(after: passages[0].date, at: merida))
        #expect(day(next.date, "America/Merida") == "2026-07-18")
    }

    @Test func theSouthernTropicsToo() {
        // Rio de Janeiro (22.91° S), either side of the December solstice.
        let rio = Coordinate(latitude: -22.91, longitude: -43.17)
        let (start, end) = year(2026)
        #expect(ZenithPassage.passages(from: start, to: end, at: rio).map { day($0.date, "America/Sao_Paulo") } == ["2026-01-02", "2026-12-10"])
    }

    @Test func onTheEquatorNearTheEquinoxes() {
        let quito = Coordinate(latitude: -0.18, longitude: -78.47)
        let (start, end) = year(2026)
        #expect(ZenithPassage.passages(from: start, to: end, at: quito).map { day($0.date, "America/Guayaquil").dropFirst(5).prefix(2) } == ["03", "09"])
    }

    @Test func neverOutsideTheTropics() {
        let (start, end) = year(2026)
        #expect(ZenithPassage.passages(from: start, to: end, at: Coordinate(latitude: 47.61, longitude: -122.33)).isEmpty)
        #expect(ZenithPassage.passages(from: start, to: end, at: Coordinate(latitude: 25.0, longitude: 55.3)).isEmpty)
    }
}
