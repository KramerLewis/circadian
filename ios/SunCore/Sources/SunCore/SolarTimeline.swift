import Foundation

/// Solar events spanning several consecutive solar days, in chronological order,
/// for answering "what happened last / what's next" across day boundaries.
public struct SolarTimeline: Sendable {
    public struct Occurrence: Hashable, Sendable {
        public let event: SolarEvent
        public let date: Date
    }

    public let coordinate: Coordinate
    public let occurrences: [Occurrence]

    /// Events from `days` solar days before to `days` after the one containing `instant`.
    public init(around instant: Date, at coordinate: Coordinate, days: Int = 3) {
        let today = SolarCalculator.solarDay(containing: instant, at: coordinate)
        var occurrences: [Occurrence] = []
        for offset in -days...days {
            let day = offset == 0
                ? today
                : SolarCalculator.solarDay(nearestNoonTo: today.solarNoon.addingTimeInterval(Double(offset) * 86_400), at: coordinate)
            for entry in day.events {
                if let date = entry.time.date {
                    occurrences.append(Occurrence(event: entry.event, date: date))
                }
            }
        }
        self.coordinate = coordinate
        self.occurrences = occurrences.sorted { $0.date < $1.date }
    }

    /// The latest occurrence of any of `events` at or before `instant`.
    public func last(of events: Set<SolarEvent> = Set(SolarEvent.allCases), atOrBefore instant: Date) -> Occurrence? {
        occurrences.last { events.contains($0.event) && $0.date <= instant }
    }

    /// The earliest occurrence of any of `events` after `instant`.
    public func next(of events: Set<SolarEvent> = Set(SolarEvent.allCases), after instant: Date) -> Occurrence? {
        occurrences.first { events.contains($0.event) && $0.date > instant }
    }
}

/// The relative readouts under the dial: "2h 14m after sunrise", "4h 51m until sunset".
public struct SolarReadout: Hashable, Sendable {
    public enum PolarCondition: Hashable, Sendable {
        /// The sun doesn't set today.
        case midnightSun
        /// The sun doesn't rise today.
        case polarNight
    }

    public struct Relative: Hashable, Sendable {
        public let event: SolarEvent
        public let date: Date
        /// Always non-negative.
        public let interval: TimeInterval
    }

    /// Most recent sunrise or sunset.
    public let previousHorizon: Relative?
    /// Next sunrise or sunset.
    public let nextHorizon: Relative?
    /// Next event of any kind (twilights, noon, midnight included).
    public let nextEvent: Relative?
    public let polarCondition: PolarCondition?

    public init(at instant: Date, coordinate: Coordinate) {
        let timeline = SolarTimeline(around: instant, at: coordinate)
        let horizon: Set<SolarEvent> = [.sunrise, .sunset]
        func relative(_ occurrence: SolarTimeline.Occurrence?) -> Relative? {
            occurrence.map { Relative(event: $0.event, date: $0.date, interval: abs($0.date.timeIntervalSince(instant))) }
        }
        previousHorizon = relative(timeline.last(of: horizon, atOrBefore: instant))
        nextHorizon = relative(timeline.next(of: horizon, after: instant))
        nextEvent = relative(timeline.next(after: instant))
        polarCondition = switch SolarCalculator.solarDay(containing: instant, at: coordinate)[.sunrise] {
        case .sunAlwaysAbove: .midnightSun
        case .sunAlwaysBelow: .polarNight
        case .at: nil
        }
    }
}
