import CoreLocation
import SunCore

/// The location the app is currently computing for, and where it came from.
struct Place: Equatable {
    enum Source: Equatable {
        case current, lastKnown, manual, demo
    }

    var name: String
    var coordinate: Coordinate
    var source: Source

    /// Picks the location to use, in priority order:
    /// manual (if preferred) → live fix → last known fix → manual (as fallback).
    static func resolve(settings: AppSettings, live: CLLocation?) -> Place? {
        if let demo = DemoConfig.current {
            return Place(name: demo.name, coordinate: demo.coordinate, source: .demo)
        }
        let manual = settings.manualCoordinate.map {
            Place(name: settings.manualName.isEmpty ? "Manual location" : settings.manualName, coordinate: $0, source: .manual)
        }
        if settings.useManualLocation, let manual {
            return manual
        }
        if let live {
            let c = live.coordinate
            return Place(name: "Current location", coordinate: Coordinate(latitude: c.latitude, longitude: c.longitude), source: .current)
        }
        if let lat = settings.lastLatitude, let lon = settings.lastLongitude {
            return Place(name: "Last known location", coordinate: Coordinate(latitude: lat, longitude: lon), source: .lastKnown)
        }
        return manual
    }
}

extension AppSettings {
    var manualCoordinate: Coordinate? {
        guard let manualLatitude, let manualLongitude else { return nil }
        return Coordinate(latitude: manualLatitude, longitude: manualLongitude)
    }
}

extension Coordinate {
    /// "47.61° N, 122.33° W"
    var formatted: String {
        let lat = String(format: "%.2f° %@", abs(latitude), latitude >= 0 ? "N" : "S")
        let lon = String(format: "%.2f° %@", abs(longitude), longitude >= 0 ? "E" : "W")
        return "\(lat), \(lon)"
    }
}
