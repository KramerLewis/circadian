import Foundation

/// What the iPhone app sends the Watch app (WatchConnectivity application context):
/// the place it's computing for and the display settings. Plain property-list
/// values, so it can cross the connection as a dictionary.
nonisolated struct WatchContext: Equatable, Sendable {
    var place: SharedStore.StoredPlace?
    var timeDisplay: String
    var dialOrientation: String
    var moonPlacement: String
    var kanjiStyle: String

    var dictionary: [String: Any] {
        var d: [String: Any] = ["timeDisplay": timeDisplay, "dialOrientation": dialOrientation, "moonPlacement": moonPlacement, "kanjiStyle": kanjiStyle]
        if let place {
            d["name"] = place.name
            d["latitude"] = place.latitude
            d["longitude"] = place.longitude
        }
        return d
    }

    init(place: SharedStore.StoredPlace?, timeDisplay: String, dialOrientation: String, moonPlacement: String, kanjiStyle: String) {
        self.place = place
        self.timeDisplay = timeDisplay
        self.dialOrientation = dialOrientation
        self.moonPlacement = moonPlacement
        self.kanjiStyle = kanjiStyle
    }

    init(dictionary d: [String: Any]) {
        timeDisplay = d["timeDisplay"] as? String ?? "relative"
        dialOrientation = d["dialOrientation"] as? String ?? "noonAtTop"
        moonPlacement = d["moonPlacement"] as? String ?? "clock"
        kanjiStyle = d["kanjiStyle"] as? String ?? "molten"
        if let lat = d["latitude"] as? Double, let lon = d["longitude"] as? Double {
            place = SharedStore.StoredPlace(name: d["name"] as? String ?? "", latitude: lat, longitude: lon)
        }
    }
}
