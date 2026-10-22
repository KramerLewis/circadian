import Foundation
import WatchConnectivity

/// Sends the Watch app what it needs (see `WatchContext`) whenever it changes. The
/// application context keeps only the latest value and is delivered when the Watch
/// app next runs, so there's no queue to manage.
final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()

    private var pending: WatchContext?
    private var sent: WatchContext?

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ context: WatchContext) {
        guard context != sent else { return }
        pending = context
        flush()
    }

    private func flush() {
        guard
            WCSession.isSupported(),
            WCSession.default.activationState == .activated,
            WCSession.default.isPaired, WCSession.default.isWatchAppInstalled,
            let context = pending
        else { return }
        do {
            try WCSession.default.updateApplicationContext(context.dictionary)
            sent = context
            pending = nil
        } catch {
            // Try again on the next change or activation.
        }
    }

    // MARK: WCSessionDelegate (called on a background queue)

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.flush() }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.flush() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Switching to another Watch: reactivate for the new one.
        session.activate()
    }
}
