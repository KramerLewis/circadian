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

    /// Last fix from CoreLocation, so the app (and later the alarm scheduler) has a
    /// location before the first fix after launch.
    var lastLatitude: Double?
    var lastLongitude: Double?
    var lastLocationDate: Date?

    init() {}
}
