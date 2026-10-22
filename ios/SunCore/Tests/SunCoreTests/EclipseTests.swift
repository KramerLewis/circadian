import Foundation
import Testing
@testable import SunCore

/// Checks EclipseCalculator against shared/fixtures/eclipse-reference.json
/// (see shared/tools/generate_eclipse_fixtures.py).
struct EclipseTests {
    static let fixture = EclipseFixture.shared

    func instant(_ iso: String) -> Date { ReferenceFixture.parseInstant(iso)! }

    @Test(arguments: fixture.lunar)
    func lunar(_ reference: EclipseFixture.Lunar) throws {
        let greatest = instant(reference.greatest)
        let eclipse = try #require(EclipseCalculator.lunarEclipse(near: greatest))
        #expect(eclipse.kind.rawValue == reference.kind)
        #expect(abs(eclipse.greatest.timeIntervalSince(greatest)) <= Self.fixture.toleranceSeconds)
        #expect(abs(eclipse.umbralMagnitude - reference.umbralMagnitude) <= Self.fixture.magnitudeTolerance)
        let contacts: [String: Date?] = [
            "Pstart": eclipse.penumbralStart, "Pend": eclipse.penumbralEnd,
            "Ustart": eclipse.partialStart, "Uend": eclipse.partialEnd,
            "Tstart": eclipse.totalStart, "Tend": eclipse.totalEnd,
        ]
        for (name, iso) in reference.contacts {
            let actual = try #require(contacts[name] ?? nil, "missing \(name)")
            #expect(abs(actual.timeIntervalSince(instant(iso))) <= Self.fixture.toleranceSeconds, "\(name)")
        }
    }

    @Test(arguments: fixture.solar)
    func solar(_ reference: EclipseFixture.Solar) throws {
        let coordinate = Coordinate(latitude: reference.latitude, longitude: reference.longitude)
        let day = instant(reference.date + "T12:00:00Z")
        let newMoon = try #require(SkyCalendar.occurrences(from: day.addingTimeInterval(-86_400), to: day.addingTimeInterval(86_400), in: .gmt)
            .first { $0.kind == .newMoon })
        let eclipse = EclipseCalculator.solarEclipse(near: newMoon.date, at: coordinate)
        guard let kind = reference.kind else {
            #expect(eclipse == nil)
            return
        }
        let found = try #require(eclipse)
        #expect(found.kind.rawValue == kind)
        let tolerance = Self.fixture.toleranceSeconds
        #expect(abs(found.maximum.timeIntervalSince(instant(reference.maximum!))) <= tolerance)
        #expect(abs(found.start.timeIntervalSince(instant(reference.start!))) <= tolerance)
        #expect(abs(found.end.timeIntervalSince(instant(reference.end!))) <= tolerance)
        #expect(abs(found.magnitude - reference.magnitude!) <= Self.fixture.magnitudeTolerance)
        #expect(abs(found.obscuration - reference.obscuration!) <= Self.fixture.magnitudeTolerance)
        if let central = reference.centralStart {
            #expect(abs(try #require(found.centralStart).timeIntervalSince(instant(central))) <= tolerance)
        }
    }

    @Test func searchFindsTheYearsEclipses() {
        let lunar = EclipseCalculator.lunarEclipses(from: instant("2026-01-01T00:00:00Z"), to: instant("2027-01-01T00:00:00Z"))
        #expect(lunar.map(\.kind) == [.total, .partial])
        let dallas = Coordinate(latitude: 32.78, longitude: -96.80)
        let solar = EclipseCalculator.solarEclipses(from: instant("2024-01-01T00:00:00Z"), to: instant("2025-01-01T00:00:00Z"), at: dallas)
        #expect(solar.map(\.kind) == [.total])
    }

    @Test func coverageDuringTotality() throws {
        let eclipse = try #require(EclipseCalculator.lunarEclipse(near: instant("2026-03-03T11:33:00Z")))
        let mid = try #require(eclipse.totalStart)
        #expect(EclipseCalculator.umbralCoverage(at: mid.addingTimeInterval(60)) > 0.99)
        #expect(EclipseCalculator.umbralCoverage(at: eclipse.penumbralStart) == 0)
    }
}

struct EclipseFixture: Decodable, Sendable {
    struct Lunar: Decodable, Sendable, CustomTestStringConvertible {
        let date: String
        let kind: String
        let greatest: String
        let umbralMagnitude: Double
        let contacts: [String: String]
        var testDescription: String { "\(kind) lunar \(date)" }
    }

    struct Solar: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let latitude: Double
        let longitude: Double
        let date: String
        let kind: String?
        let maximum: String?
        let start: String?
        let end: String?
        let magnitude: Double?
        let obscuration: Double?
        let centralStart: String?
        var testDescription: String { name }
    }

    let toleranceSeconds: Double
    let magnitudeTolerance: Double
    let lunar: [Lunar]
    let solar: [Solar]

    static let shared: EclipseFixture = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "shared/fixtures/eclipse-reference.json")
        do {
            return try JSONDecoder().decode(EclipseFixture.self, from: Data(contentsOf: url))
        } catch {
            fatalError("Could not load \(url.path): \(error)")
        }
    }()
}
