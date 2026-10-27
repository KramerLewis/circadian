import Foundation
import SunCore

/// The dial's center readout.
enum TimeDisplay: String, CaseIterable, Identifiable {
    /// Time from the nearest of sunrise, solar noon, sunset, solar midnight.
    case relative
    case twelveHour
    case twentyFourHour
    /// This app's own scale: -R R R+ 0 -N N N+ 1 … (see `SunPeriods`).
    case periods
    /// Edo-period temporal hours, with the zodiac kanji around the dial and the hour's
    /// animal in the middle (see `Wadokei`).
    case wadokei
    /// Twelve hours from sunrise to sunset and four watches of the night (see `RomanHours`).
    case roman

    var id: Self { self }

    var title: String {
        switch self {
        case .relative: "Relative to the Sun"
        case .twelveHour: "12-Hour Clock"
        case .twentyFourHour: "24-Hour Clock"
        case .periods: "Sun Periods"
        case .wadokei: "Wadokei (Edo Hours)"
        case .roman: "Roman Hours"
        }
    }

    /// The historical clocks, kept in a group of their own.
    var isHistorical: Bool { self == .wadokei || self == .roman }
    static let everyday = allCases.filter { !$0.isHistorical }
    static let historical = allCases.filter(\.isHistorical)

    /// Whether the dial's 24 hour ticks give way to the display's own sections.
    var hasSections: Bool { self == .periods || isHistorical }

    /// The next display in this one's group (tapping the dial cycles within it).
    var next: TimeDisplay {
        let group = isHistorical ? Self.historical : Self.everyday
        return group[((group.firstIndex(of: self) ?? -1) + 1) % group.count]
    }
}

/// The two lines in the middle of the dial, for a time display setting.
enum DialCenterText {
    static func make(now: Date, solarMinutes: Double, readout: SolarReadout, display: TimeDisplay,
                     coordinate: Coordinate?) -> (primary: String, secondary: String) {
        let solar = "\(SolarFormat.solarClock(minutes: solarMinutes)) solar"
        switch display {
        case .relative:
            guard let anchor = readout.nearestAnchor else { return (solar, "") }
            let direction = readout.nearestAnchorIsPast ? "after" : "until"
            return (SolarFormat.duration(anchor.interval), "\(direction) \(anchor.event.displayName.lowercased())")
        case .twelveHour:
            return (clock(now, format: "h:mm a"), solar)
        case .twentyFourHour:
            return (clock(now, format: "HH:mm"), solar)
        case .periods:
            guard let coordinate, let period = SunPeriods.sun(at: now, coordinate: coordinate) else { return (solar, "") }
            return (period.code, SunPeriods.phrase(period))
        case .wadokei:
            // The animal and kanji are drawn in the middle instead; this is for VoiceOver.
            guard let coordinate, let hour = Wadokei.hour(at: now, coordinate: coordinate) else { return (solar, "") }
            return ("", "\(hour.animal) hour")
        case .roman:
            guard let coordinate, let hour = RomanHours.hour(at: now, coordinate: coordinate) else { return (solar, "") }
            return (hour.title, hour.phrase)
        }
    }

    /// An explicit 12- or 24-hour clock, regardless of the device's setting.
    private static func clock(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
