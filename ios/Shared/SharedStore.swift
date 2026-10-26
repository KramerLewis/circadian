import Foundation
import SunCore

/// Data the app shares with its widgets through the App Group container. Widgets
/// can't use the app's location service, so the app publishes the place it's
/// currently computing for, and the widgets draw from that.
nonisolated enum SharedStore {
    static let appGroup = "group.com.kray.circadian"
    private static let placeKey = "place"

    struct StoredPlace: Codable, Equatable, Sendable {
        var name: String
        var latitude: Double
        var longitude: Double

        var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
    }

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func loadPlace() -> StoredPlace? {
        guard let data = defaults?.data(forKey: placeKey) else { return nil }
        return try? JSONDecoder().decode(StoredPlace.self, from: data)
    }

    private static let timeDisplayKey = "timeDisplay"
    private static let dialOrientationKey = "dialOrientation"
    private static let moonPlacementKey = "moonPlacement"

    static func loadMoonPlacement() -> String? {
        defaults?.string(forKey: moonPlacementKey)
    }

    static func saveMoonPlacement(_ raw: String) {
        defaults?.set(raw, forKey: moonPlacementKey)
    }

    static func loadDialOrientation() -> String? {
        defaults?.string(forKey: dialOrientationKey)
    }

    static func saveDialOrientation(_ raw: String) {
        defaults?.set(raw, forKey: dialOrientationKey)
    }

    static func loadTimeDisplay() -> String? {
        defaults?.string(forKey: timeDisplayKey)
    }

    static func saveTimeDisplay(_ raw: String) {
        defaults?.set(raw, forKey: timeDisplayKey)
    }

    /// Returns whether the stored place changed.
    @discardableResult
    static func savePlace(_ place: StoredPlace?) -> Bool {
        guard place != loadPlace() else { return false }
        if let place, let data = try? JSONEncoder().encode(place) {
            defaults?.set(data, forKey: placeKey)
        } else {
            defaults?.removeObject(forKey: placeKey)
        }
        return true
    }
}
