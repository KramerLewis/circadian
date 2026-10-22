import Foundation

/// Text formatting shared by the app and (later) widgets.
public enum SolarFormat {
    /// "2h 14m", "14m", or "<1m". Rounds down to the minute.
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((max(seconds, 0) / 60).rounded(.down))
        if minutes < 1 { return "<1m" }
        let hours = minutes / 60
        return hours == 0 ? "\(minutes)m" : "\(hours)h \(minutes % 60)m"
    }

    /// "2h 14m after sunrise" or "4h 51m until sunset".
    public static func relative(_ relative: SolarReadout.Relative, isPast: Bool) -> String {
        "\(duration(relative.interval)) \(isPast ? "after" : "until") \(relative.event.displayName.lowercased())"
    }

    /// 24-hour apparent solar time, e.g. "11:42".
    public static func solarClock(minutes: Double) -> String {
        let total = Int(minutes.rounded(.down)) % 1440
        let h = total / 60, m = total % 60
        return (h < 10 ? "0" : "") + "\(h):" + (m < 10 ? "0" : "") + "\(m)"
    }

    /// "30 min before sunrise", "1 hr after solar noon", "Civil dusk".
    public static func alarmDescription(event: SolarEvent, offsetMinutes: Int) -> String {
        if offsetMinutes == 0 { return event.displayName }
        let direction = offsetMinutes < 0 ? "before" : "after"
        return "\(offset(abs(offsetMinutes))) \(direction) \(event.displayName.lowercased())"
    }

    /// "30 min", "1 hr", "1 hr 30 min".
    public static func offset(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        switch (h, m) {
        case (0, _): return "\(m) min"
        case (_, 0): return "\(h) hr"
        default: return "\(h) hr \(m) min"
        }
    }
}
