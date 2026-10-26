import CoreLocation
import Foundation
import Observation
import SunCore
import WatchConnectivity
import WidgetKit

/// The Watch app's data: the place and display settings sent by the iPhone, or
/// the Watch's own location when the phone hasn't sent one. Persisted in the App
/// Group so the complications draw from the same values.
@Observable
final class WatchModel: NSObject, WCSessionDelegate {
    private(set) var context: WatchContext
    private(set) var locating = false

    @ObservationIgnored private var session: CLServiceSession?

    override init() {
        if let demo = DemoConfig.current {
            context = WatchContext(
                place: SharedStore.StoredPlace(name: demo.name, latitude: demo.coordinate.latitude, longitude: demo.coordinate.longitude),
                timeDisplay: demo.timeDisplay ?? TimeDisplay.relative.rawValue,
                dialOrientation: demo.dialOrientation ?? DialOrientation.noonAtTop.rawValue,
                moonPlacement: demo.moonPlacement ?? MoonPlacement.clock.rawValue
            )
        } else {
            context = WatchContext(
                place: SharedStore.loadPlace(),
                timeDisplay: SharedStore.loadTimeDisplay() ?? TimeDisplay.relative.rawValue,
                dialOrientation: SharedStore.loadDialOrientation() ?? DialOrientation.noonAtTop.rawValue,
                moonPlacement: SharedStore.loadMoonPlacement() ?? MoonPlacement.clock.rawValue
            )
        }
        super.init()
    }

    var timeDisplay: TimeDisplay { TimeDisplay(rawValue: context.timeDisplay) ?? .relative }
    var dialOrientation: DialOrientation { DialOrientation(rawValue: context.dialOrientation) ?? .noonAtTop }
    var moonPlacement: MoonPlacement { MoonPlacement(rawValue: context.moonPlacement) ?? .clock }

    func start() {
        guard DemoConfig.current == nil, WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Cycle the time display on the Watch (the phone's next update wins).
    func cycleTimeDisplay() {
        var updated = context
        updated.timeDisplay = timeDisplay.next.rawValue
        apply(updated)
    }

    /// Use the Watch's own location, for when the iPhone hasn't shared one.
    func useWatchLocation() async {
        guard !locating else { return }
        locating = true
        defer { locating = false; session?.invalidate(); session = nil }
        session = CLServiceSession(authorization: .whenInUse)
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                guard let location = update.location else {
                    if update.authorizationDenied { return }
                    continue
                }
                var updated = context
                updated.place = SharedStore.StoredPlace(
                    name: "Watch location",
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
                apply(updated)
                return
            }
        } catch {}
    }

    private func apply(_ new: WatchContext) {
        guard new != context else { return }
        context = new
        guard DemoConfig.current == nil else { return }
        SharedStore.savePlace(new.place)
        SharedStore.saveTimeDisplay(new.timeDisplay)
        SharedStore.saveDialOrientation(new.dialOrientation)
        SharedStore.saveMoonPlacement(new.moonPlacement)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Keep a known place when the phone sends a context without one.
    private func merge(_ incoming: WatchContext) {
        var merged = incoming
        if merged.place == nil { merged.place = context.place }
        apply(merged)
    }

    // MARK: WCSessionDelegate (called on a background queue)

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let received = session.receivedApplicationContext
        guard !received.isEmpty else { return }
        let incoming = WatchContext(dictionary: received)
        Task { @MainActor in self.merge(incoming) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let incoming = WatchContext(dictionary: applicationContext)
        Task { @MainActor in self.merge(incoming) }
    }
}
