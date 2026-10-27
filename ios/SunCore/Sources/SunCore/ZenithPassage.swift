import Foundation

/// Zenith passage: the day the sun passes straight overhead at solar noon, so upright
/// things cast (almost) no shadow. It happens twice a year anywhere between the tropics,
/// when the sun's declination at noon equals the latitude; the Maya, among others, built
/// to mark it. Outside the tropics the sun is never overhead.
/// Mirrors web/src/core/zenith.ts.
public struct ZenithPassage: Hashable, Sendable {
    /// Solar noon on the passage day.
    public let date: Date
    /// The sun's altitude then, degrees (90 is straight overhead).
    public let altitude: Double

    /// The sun reaches at most this declination (the tropics' latitude).
    static let tropic = 23.44

    /// Zenith passages with their noon in `[start, end)`, chronological.
    public static func passages(from start: Date, to end: Date, at coordinate: Coordinate) -> [ZenithPassage] {
        let latitude = coordinate.latitude
        guard abs(latitude) <= tropic + 0.01 else { return [] }
        func offset(_ t: Date) -> Double { SolarCalculator.position(at: t).declination - latitude }
        var found: [ZenithPassage] = []
        // Solar noon moves by under a minute a day, so stepping a day at a time stays on
        // noon well enough to compare declinations; the passage's own noon is solved exactly.
        var a = SolarCalculator.solarDay(nearestNoonTo: start.addingTimeInterval(-86_400), at: coordinate).solarNoon
        var fa = offset(a)
        while a < end.addingTimeInterval(86_400) {
            let b = a.addingTimeInterval(86_400), fb = offset(b)
            if (fa < 0) != (fb < 0) {
                let noon = SolarCalculator.solarDay(nearestNoonTo: abs(fa) <= abs(fb) ? a : b, at: coordinate).solarNoon
                if noon >= start, noon < end {
                    found.append(ZenithPassage(date: noon, altitude: 90 - abs(offset(noon))))
                }
            }
            a = b
            fa = fb
        }
        return found
    }

    /// The first passage after `date` (within a year and a bit).
    public static func next(after date: Date, at coordinate: Coordinate) -> ZenithPassage? {
        passages(from: date.addingTimeInterval(43_200), to: date.addingTimeInterval(370 * 86_400), at: coordinate).first
    }
}
