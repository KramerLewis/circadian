import Foundation

/// A latitude/longitude in degrees. Longitude is positive east.
///
/// SunCore deliberately avoids CoreLocation so it stays portable and testable anywhere.
public struct Coordinate: Hashable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// When an event happens on a given day, or why it doesn't.
public enum EventTime: Hashable, Sendable {
    case at(Date)
    /// The sun stays above the event's altitude all day (e.g. no sunset under the midnight sun).
    case sunAlwaysAbove
    /// The sun stays below the event's altitude all day (e.g. no sunrise in polar night).
    case sunAlwaysBelow

    public var date: Date? {
        if case .at(let date) = self { date } else { nil }
    }
}

/// All solar events for one solar day: from the solar midnight before a local
/// date's solar noon to the solar midnight after it.
public struct SolarDay: Hashable, Sendable {
    public let coordinate: Coordinate
    public let solarNoon: Date
    /// Start of this solar day.
    public let solarMidnight: Date
    /// End of this solar day (start of the next).
    public let nextSolarMidnight: Date
    private let horizonEvents: [SolarEvent: EventTime]

    init(
        coordinate: Coordinate,
        solarNoon: Date,
        solarMidnight: Date,
        nextSolarMidnight: Date,
        horizonEvents: [SolarEvent: EventTime]
    ) {
        self.coordinate = coordinate
        self.solarNoon = solarNoon
        self.solarMidnight = solarMidnight
        self.nextSolarMidnight = nextSolarMidnight
        self.horizonEvents = horizonEvents
    }

    public subscript(event: SolarEvent) -> EventTime {
        switch event {
        case .solarNoon: .at(solarNoon)
        case .solarMidnight: .at(solarMidnight)
        default: horizonEvents[event] ?? .sunAlwaysBelow
        }
    }

    public struct Entry: Hashable, Sendable, Identifiable {
        public let event: SolarEvent
        public let time: EventTime
        public var id: SolarEvent { event }
    }

    /// Events in chronological order, paired with their times.
    public var events: [Entry] {
        SolarEvent.allCases.map { Entry(event: $0, time: self[$0]) }
    }

    public func contains(_ instant: Date) -> Bool {
        instant >= solarMidnight && instant < nextSolarMidnight
    }
}
