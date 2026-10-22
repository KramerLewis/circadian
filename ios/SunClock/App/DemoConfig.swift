import Foundation
import SunCore
import SwiftData

/// A frozen place and time, set from launch arguments, for deterministic screenshots:
///
///     -demoLatitude 47.61 -demoLongitude -122.33 -demoName Seattle
///     -demoDate 2026-06-21T15:00:00-07:00 [-demoTab alarms] [-demoSheet location|alarm|widgets]
///     [-demoTimeDisplay relative|twelveHour|twentyFourHour] [-demoScroll moon]
///
/// Debug builds only. In demo mode the app uses an in-memory store and never
/// touches CoreLocation, so no permission prompt covers the screen.
struct DemoConfig {
    var coordinate: Coordinate
    var name: String
    var date: Date
    var sheet: String?
    var tab: String?
    var timeDisplay: String?
    var scroll: String?

    static let current: DemoConfig? = {
        #if DEBUG
        // Parsed by hand rather than through UserDefaults' argument domain, which
        // would read a negative value like "-122.33" as the next flag.
        let arguments = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), arguments.indices.contains(i + 1) else { return nil }
            return arguments[i + 1]
        }
        guard
            let lat = value("-demoLatitude").flatMap(Double.init),
            let lon = value("-demoLongitude").flatMap(Double.init),
            let date = value("-demoDate").flatMap({ ISO8601DateFormatter().date(from: $0) })
        else { return nil }
        return DemoConfig(
            coordinate: Coordinate(latitude: lat, longitude: lon),
            name: value("-demoName") ?? "Demo",
            date: date,
            sheet: value("-demoSheet"),
            tab: value("-demoTab"),
            timeDisplay: value("-demoTimeDisplay"),
            scroll: value("-demoScroll")
        )
        #else
        return nil
        #endif
    }()
}

extension DemoConfig {
    /// Sample data for the in-memory demo store.
    func seed(_ context: ModelContext) {
        let settings = AppSettings()
        if let timeDisplay { settings.timeDisplayRaw = timeDisplay }
        context.insert(settings)
        let samples: [(String, SolarEvent, Int, [Int], Bool)] = [
            ("Wake up", .sunrise, -30, [2, 3, 4, 5, 6], true),
            ("", .solarNoon, 60, Array(1...7), true),
            ("Evening walk", .civilDusk, 0, [1, 7], false),
            ("", .nauticalDawn, 0, [], true),
        ]
        for (label, event, offset, weekdays, enabled) in samples {
            let alarm = SolarAlarm()
            alarm.label = label
            alarm.event = event
            alarm.offsetMinutes = offset
            alarm.weekdays = weekdays
            alarm.isEnabled = enabled
            alarm.armedAt = date
            context.insert(alarm)
        }
    }
}
