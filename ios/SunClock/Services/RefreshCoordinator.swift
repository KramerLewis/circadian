import BackgroundTasks
import CoreLocation
import Foundation
import Observation
import SunCore
import SwiftData

/// The single entry point for re-planning alarms. Every trigger (launch, foreground,
/// location change, significant time change, time zone change, alarm edits, and the
/// background refresh task) calls `request(_:)`; requests arriving close together are
/// coalesced into one refresh.
@Observable
final class RefreshCoordinator {
    static let backgroundTaskIdentifier = "com.kray.circadian.refresh"
    /// How long until iOS may run the next background refresh. It's a floor, not a
    /// promise: iOS decides when (and whether) to run it.
    static let backgroundInterval: TimeInterval = 6 * 3600

    private(set) var status: AlarmScheduler.Status?

    @ObservationIgnored let scheduler = AlarmScheduler()
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let locationService: LocationService
    @ObservationIgnored private var pending: Task<Void, Never>?

    init(container: ModelContainer, locationService: LocationService) {
        self.container = container
        self.locationService = locationService
    }

    /// Refresh soon, merging with any other request in the next half second.
    func request(_ reason: String) {
        guard DemoConfig.current == nil else { return }
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await refresh(reason)
        }
    }

    /// Refresh now. Used directly by the background task, which must finish before
    /// returning.
    func refresh(_ reason: String) async {
        let context = container.mainContext
        let now = Date.now
        let settings = (try? context.fetch(FetchDescriptor<AppSettings>()))?.first
        let alarms = (try? context.fetch(FetchDescriptor<SolarAlarm>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        let place = settings.flatMap { Place.resolve(settings: $0, live: locationService.location) }

        // A one-time alarm whose moment has passed has rung; turn it off.
        if let place {
            for alarm in alarms where alarm.isEnabled && alarm.weekdays.isEmpty {
                if let fire = AlarmPlanner.oneTimeFireDate(of: alarm.rule, at: place.coordinate, in: .current), fire <= now {
                    alarm.isEnabled = false
                    alarm.touch(at: now)
                }
            }
        }
        status = await scheduler.refresh(alarms: alarms, place: place, reason: reason, now: now)
        try? context.save()
    }

    /// Ask iOS to wake the app for a refresh later. Safe to call repeatedly; a newer
    /// request replaces the pending one.
    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: backgroundInterval)
        try? BGTaskScheduler.shared.submit(request)
    }
}
