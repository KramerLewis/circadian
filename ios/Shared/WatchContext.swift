import Foundation

/// What the iPhone app sends the Watch app (WatchConnectivity application context):
/// the place it's computing for and the time display setting. Plain property-list
/// values, so it can cross the connection as a dictionary.
nonisolated struct WatchContext: Equatable, Sendable {
    var place: SharedStore.StoredPlace?
    var timeDisplay: String

    var dictionary: [String: Any] {
        var d: [String: Any] = ["timeDisplay": timeDisplay]
        if let place {
            d["name"] = place.name
            d["latitude"] = place.latitude
            d["longitude"] = place.longitude
        }
        return d
    }

    init(place: SharedStore.StoredPlace?, timeDisplay: String) {
        self.place = place
        self.timeDisplay = timeDisplay
    }

    init(dictionary d: [String: Any]) {
        timeDisplay = d["timeDisplay"] as? String ?? "relative"
        if let lat = d["latitude"] as? Double, let lon = d["longitude"] as? Double {
            place = SharedStore.StoredPlace(name: d["name"] as? String ?? "", latitude: lat, longitude: lon)
        }
    }
}
