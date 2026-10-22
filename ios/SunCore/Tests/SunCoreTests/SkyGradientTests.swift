import Foundation
import Testing
@testable import SunCore

struct SkyGradientTests {
    @Test func ringAltitudeMatchesTheDay() throws {
        let seattle = Coordinate(latitude: 47.61, longitude: -122.33)
        let now = try #require(ReferenceFixture.parseInstant("2026-06-21T15:00:00-07:00"))
        let model = DialModel(day: SolarCalculator.solarDay(containing: now, at: seattle), now: now)
        // Noon: 90 - (47.61 - 23.43) = 65.8 deg. Midnight: -(90 - 47.61 - 23.43) = -19.0 deg.
        #expect(abs(model.altitude(atAngle: 0) - 65.8) < 0.2)
        #expect(abs(model.altitude(atAngle: 180) + 19.0) < 0.2)
        // The ring's sunrise marker sits where the altitude crosses -0.833.
        let sunrise = try #require(model.markers.first { $0.event == .sunrise })
        #expect(abs(model.altitude(atAngle: sunrise.angle) + 0.833) < 0.1)
    }

    @Test func colorsInterpolateAndClamp() {
        let night = SkyGradient.color(altitude: -40, dark: false)
        #expect(night == SkyGradient.color(altitude: -18, dark: false))
        #expect(SkyGradient.color(altitude: 90, dark: false) == SkyGradient.color(altitude: 75, dark: false))
        // Halfway between the -18 and -12 stops.
        let mid = SkyGradient.color(altitude: -15, dark: false)
        #expect(abs(mid.blue - (0.26 + 0.42) / 2) < 1e-9)
    }

    @Test func brightnessRisesWithTheSun() {
        let samples = stride(from: -30.0, through: 90, by: 5).map(SkyGradient.brightness(altitude:))
        #expect(samples == samples.sorted())
        #expect(samples.first! > 0 && samples.last! <= 1)
    }

    @Test func sunReddensTowardTheHorizon() {
        let noon = SkyGradient.sunColor(altitude: 60).core
        let golden = SkyGradient.sunColor(altitude: 8).core
        let sunset = SkyGradient.sunColor(altitude: 0).core
        #expect(noon.blue > golden.blue && golden.blue > sunset.blue)
        #expect(noon.green > golden.green && golden.green > sunset.green)
        #expect(SkyGradient.sunColor(altitude: -30).core == SkyGradient.sunColor(altitude: -2).core)
    }
}
