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
    /// How the dial is turned; see `DialOrientation`.
    var dialOrientationRaw: String = DialOrientation.noonAtTop.rawValue
    /// The dial hand's color; see `HandColor`.
    var handColorRaw: String = HandColor.royalBlue.rawValue
    /// Where the moon ring puts the moon; see `MoonPlacement`.
    var moonPlacementRaw: String = MoonPlacement.clock.rawValue
    /// How the wadokei's kanji and animal are drawn; see `KanjiStyle`.
    var kanjiStyleRaw: String = KanjiStyle.molten.rawValue

    /// Last fix from CoreLocation, so the app (and later the alarm scheduler) has a
    /// location before the first fix after launch.
    var lastLatitude: Double?
    var lastLongitude: Double?
    var lastLocationDate: Date?

    init() {}
}

extension AppSettings {
    var timeDisplay: TimeDisplay {
        get { TimeDisplay(rawValue: timeDisplayRaw) ?? .relative }
        set {
            timeDisplayRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    var handColor: HandColor {
        get { HandColor(rawValue: handColorRaw) ?? .royalBlue }
        set {
            handColorRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    var moonPlacement: MoonPlacement {
        get { MoonPlacement(rawValue: moonPlacementRaw) ?? .clock }
        set {
            moonPlacementRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    var kanjiStyle: KanjiStyle {
        get { KanjiStyle(rawValue: kanjiStyleRaw) ?? .molten }
        set {
            kanjiStyleRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    var dialOrientation: DialOrientation {
        get { DialOrientation(rawValue: dialOrientationRaw) ?? .noonAtTop }
        set {
            dialOrientationRaw = newValue.rawValue
            updatedAt = .now
        }
    }
}
