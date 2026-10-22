import Foundation

/// Geometry for the 24-hour solar dial, independent of any drawing framework.
///
/// Angles are degrees clockwise from the top of the dial, in `(-180, 180]`. The dial
/// angle of an instant is the sun's hour angle, so solar noon is at the top (0),
/// solar midnight at the bottom (180), mornings on the left and evenings on the right.
public struct DialModel: Hashable, Sendable {
    /// Bands painted over the night background, darkest first.
    public enum Band: Int, CaseIterable, Hashable, Sendable {
        case astronomicalTwilight, nauticalTwilight, civilTwilight, day

        /// The events that bound this band: the sun is above `dawn`'s altitude between them.
        public var bounds: (dawn: SolarEvent, dusk: SolarEvent) {
            switch self {
            case .astronomicalTwilight: (.astronomicalDawn, .astronomicalDusk)
            case .nauticalTwilight: (.nauticalDawn, .nauticalDusk)
            case .civilTwilight: (.civilDawn, .civilDusk)
            case .day: (.sunrise, .sunset)
            }
        }
    }

    public struct Arc: Hashable, Sendable {
        public let band: Band
        /// Start angle; the arc runs clockwise to `end` (`end > start`).
        public let start: Double
        public let end: Double
        public var isFullCircle: Bool { end - start >= 360 }
    }

    public struct Marker: Hashable, Sendable {
        public let event: SolarEvent
        public let date: Date
        public let angle: Double
    }

    public let arcs: [Arc]
    public let markers: [Marker]
    public let nowAngle: Double
    public let latitude: Double
    /// The sun's declination at this day's solar noon. It changes by under half a
    /// degree a day, so one value is accurate enough to color the whole ring.
    public let declination: Double

    public init(day: SolarDay, now: Date) {
        let longitude = day.coordinate.longitude
        var arcs: [Arc] = []
        for band in Band.allCases {
            switch (day[band.bounds.dawn], day[band.bounds.dusk]) {
            case (.at(let dawn), .at(let dusk)):
                let start = Self.angle(for: dawn, longitude: longitude)
                var end = Self.angle(for: dusk, longitude: longitude)
                if end < start { end += 360 }
                arcs.append(Arc(band: band, start: start, end: end))
            case (.sunAlwaysAbove, _), (_, .sunAlwaysAbove):
                arcs.append(Arc(band: band, start: -180, end: 180))
            default:
                break // The sun never gets this high today.
            }
        }
        self.arcs = arcs
        markers = day.events.compactMap { entry in
            entry.time.date.map { Marker(event: entry.event, date: $0, angle: Self.angle(for: $0, longitude: longitude)) }
        }
        nowAngle = Self.angle(for: now, longitude: longitude)
        latitude = day.coordinate.latitude
        declination = SolarCalculator.position(at: day.solarNoon).declination
    }

    /// The sun's altitude (degrees) at a dial angle: highest at the top, lowest at the
    /// bottom. Drives the ring's sky gradient.
    public func altitude(atAngle angle: Double) -> Double {
        SolarCalculator.altitude(hourAngle: angle, latitude: latitude, declination: declination)
    }

    public static func angle(for date: Date, longitude: Double) -> Double {
        SolarCalculator.hourAngle(at: date, longitude: longitude)
    }

    /// Dial angle of a solar clock hour (0–24): 12 is the top, 0 the bottom.
    public static func angle(forSolarHour hour: Double) -> Double {
        hour * 15 - 180
    }
}
