import CoreLocation
import Observation

/// Foreground location with "when in use" permission.
///
/// Publishes a new `location` only when it moves more than `significantDistance`, so
/// the dial and (later) the alarm scheduler recompute on meaningful moves, not GPS
/// jitter. Approximate (reduced accuracy) location is enough: a 5 km error shifts
/// solar events by well under a minute.
@Observable
final class LocationService {
    static let significantDistance: CLLocationDistance = 5_000

    private(set) var location: CLLocation?
    private(set) var authorization: CLAuthorizationStatus

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var session: CLServiceSession?
    @ObservationIgnored private var updates: Task<Void, Never>?

    init() {
        authorization = manager.authorizationStatus
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    /// Start updates if the user already granted access. Call when the app becomes active.
    func startIfAuthorized() {
        refreshAuthorization()
        if isAuthorized { start() }
    }

    /// Ask for access (shows the system prompt the first time) and start updates.
    func requestAccess() {
        start()
    }

    func start() {
        guard updates == nil else { return }
        // Holding a service session is what requests and keeps "when in use" access.
        session = CLServiceSession(authorization: .whenInUse)
        updates = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    guard let self else { return }
                    self.refreshAuthorization()
                    if let location = update.location {
                        self.accept(location)
                    }
                }
            } catch {
                // The stream ended (e.g. cancelled); `start()` makes a new one.
            }
        }
    }

    func stop() {
        updates?.cancel()
        updates = nil
        session?.invalidate()
        session = nil
    }

    private func refreshAuthorization() {
        let status = manager.authorizationStatus
        if status != authorization { authorization = status }
    }

    private func accept(_ new: CLLocation) {
        if let location, location.distance(from: new) < Self.significantDistance { return }
        location = new
    }
}
