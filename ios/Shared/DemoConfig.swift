import Foundation
import SunCore

/// A frozen place and time, set from launch arguments, for deterministic screenshots:
///
///     -demoLatitude 47.61 -demoLongitude -122.33 -demoName Seattle
///     -demoDate 2026-06-21T15:00:00-07:00 [-demoTab alarms] [-demoSheet location|alarm|widgets]
///     [-demoTimeDisplay relative|twelveHour|twentyFourHour|periods|wadokei] [-demoDialOrientation noonAtTop|nowAtTop]
///     [-demoMoonPlacement clock|sky] [-demoHandColor royalBlue|red|cyan|green|kryptonPurple|auto|gold]
///     [-demoKanjiStyle molten|plain|silver|gold] [-demoScroll moon] [-demoScrub minutes]
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
    var dialOrientation: String?
    var moonPlacement: String?
    var handColor: String?
    var kanjiStyle: String?
    var scroll: String?
    /// Watch: start scrubbed this many minutes from now (and don't snap back).
    var scrub: Double?

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
            dialOrientation: value("-demoDialOrientation"),
            moonPlacement: value("-demoMoonPlacement"),
            handColor: value("-demoHandColor"),
            kanjiStyle: value("-demoKanjiStyle"),
            scroll: value("-demoScroll"),
            scrub: value("-demoScrub").flatMap(Double.init)
        )
        #else
        return nil
        #endif
    }()
}
