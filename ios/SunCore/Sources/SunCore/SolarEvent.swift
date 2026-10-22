import Foundation

/// A point in the solar day, in chronological order from solar midnight.
public enum SolarEvent: String, CaseIterable, Codable, Sendable, Identifiable {
    case solarMidnight
    case astronomicalDawn
    case nauticalDawn
    case civilDawn
    case sunrise
    case solarNoon
    case sunset
    case civilDusk
    case nauticalDusk
    case astronomicalDusk

    public var id: String { rawValue }

    /// Sun altitude (degrees, sun's center) that defines the event, or nil for the
    /// meridian transits (solar noon and midnight).
    public var altitude: Double? {
        switch self {
        case .solarMidnight, .solarNoon: nil
        case .astronomicalDawn, .astronomicalDusk: -18
        case .nauticalDawn, .nauticalDusk: -12
        case .civilDawn, .civilDusk: -6
        // Standard refraction (34') plus solar semidiameter (16').
        case .sunrise, .sunset: -0.833
        }
    }

    /// -1 for events before solar noon, +1 after, 0 for the transits.
    var direction: Double {
        switch self {
        case .astronomicalDawn, .nauticalDawn, .civilDawn, .sunrise: -1
        case .sunset, .civilDusk, .nauticalDusk, .astronomicalDusk: 1
        case .solarMidnight, .solarNoon: 0
        }
    }

    public var displayName: String {
        switch self {
        case .solarMidnight: "Solar midnight"
        case .astronomicalDawn: "Astronomical dawn"
        case .nauticalDawn: "Nautical dawn"
        case .civilDawn: "Civil dawn"
        case .sunrise: "Sunrise"
        case .solarNoon: "Solar noon"
        case .sunset: "Sunset"
        case .civilDusk: "Civil dusk"
        case .nauticalDusk: "Nautical dusk"
        case .astronomicalDusk: "Astronomical dusk"
        }
    }
}
