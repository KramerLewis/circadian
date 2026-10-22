import Foundation
import SwiftData

/// App-wide settings. There is one row; `RootView` creates it on first launch.
///
/// Every property has a default and the row carries `id`/`updatedAt` so it can be
/// synced (last write wins) once there's a backend.
@Model
final class AppSettings {
    var id: UUID = UUID()
    var updatedAt: Date = Date()

    /// Prefer the manual location even when location access is available.
    var useManualLocation: Bool = false
    var manualName: String = ""
    var manualLatitude: Double?
    var manualLongitude: Double?

    /// What the dial's center shows; see `TimeDisplay`.
    var timeDisplayRaw: String = TimeDisplay.relative.rawValue

    /// Last fix from CoreLocation, so the app (and later the alarm scheduler) has a
    /// location before the first fix after launch.
    var lastLatitude: Double?
    var lastLongitude: Double?
    var lastLocationDate: Date?

    init() {}
}

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

extension AppSettings {
    var timeDisplay: TimeDisplay {
        get { TimeDisplay(rawValue: timeDisplayRaw) ?? .relative }
        set {
            timeDisplayRaw = newValue.rawValue
            updatedAt = .now
        }
    }
}
