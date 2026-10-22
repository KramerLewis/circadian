import Foundation
import SunCore

/// The dial's center readout.
enum TimeDisplay: String, CaseIterable, Identifiable {
    /// Time from the nearest of sunrise, solar noon, sunset, solar midnight.
    case relative
    case twelveHour
    case twentyFourHour

    var id: Self { self }

    var title: String {
        switch self {
        case .relative: "Relative to the Sun"
        case .twelveHour: "12-Hour Clock"
        case .twentyFourHour: "24-Hour Clock"
        }
    }

    var next: TimeDisplay {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// The two lines in the middle of the dial, for a time display setting.
enum DialCenterText {
    static func make(now: Date, solarMinutes: Double, readout: SolarReadout, display: TimeDisplay) -> (primary: String, secondary: String) {
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
