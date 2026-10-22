import SunCore

/// SF Symbols for each event, used by the app and widgets.
extension SolarEvent {
    var symbolName: String {
        switch self {
        case .solarMidnight: "moon.fill"
        case .astronomicalDawn, .nauticalDawn, .civilDawn: "sun.haze"
        case .sunrise: "sunrise.fill"
        case .solarNoon: "sun.max.fill"
        case .sunset: "sunset.fill"
        case .civilDusk, .nauticalDusk, .astronomicalDusk: "moon.haze"
        }
    }
}
