import ActivityKit
import AlarmKit
import AppIntents
import Foundation
import SunCore
import SwiftUI

/// Keeps the system's AlarmKit alarms in step with the user's solar alarms.
///
/// AlarmKit only schedules fixed times, but solar times drift daily, so each refresh
/// plans the next `horizonDays` of occurrences (`AlarmPlanner`) and reconciles them
/// with what AlarmKit has (`AlarmReconciler`): stale occurrences are cancelled and
/// missing ones scheduled. Occurrence IDs are deterministic, so refreshing is cheap and
/// idempotent. See ios/README.md for the limits of this approach.
final class AlarmScheduler {
    static let horizonDays = 14
    /// Apple doesn't document a per-app alarm limit; stay well clear of any.
    static let maxScheduled = 64
    static let snoozeDuration: TimeInterval = 9 * 60

    struct Status: Equatable {
        enum Outcome: Equatable {
            case scheduled(count: Int, through: Date?)
            case notAuthorized
            case noLocation
            case failed(String)
        }

        var date: Date
        var reason: String
        var outcome: Outcome
    }

    private let manager = AlarmManager.shared

    var authorization: AlarmManager.AuthorizationState {
        manager.authorizationState
    }

    /// Shows the system prompt the first time; returns whether alarms are allowed.
    func requestAuthorization() async -> Bool {
        switch manager.authorizationState {
        case .authorized: return true
        case .denied: return false
        default: return (try? await manager.requestAuthorization()) == .authorized
        }
    }

    func refresh(alarms: [SolarAlarm], place: Place?, reason: String, now: Date = .now) async -> Status {
        func status(_ outcome: Status.Outcome) -> Status {
            Status(date: now, reason: reason, outcome: outcome)
        }
        let active = alarms.filter { $0.isEnabled && $0.deletedAt == nil }
        if active.isEmpty && manager.authorizationState != .authorized {
            // Nothing to schedule, and no point prompting for permission yet.
            return status(.scheduled(count: 0, through: nil))
        }
        guard manager.authorizationState == .authorized else { return status(.notAuthorized) }
        // Without a location, keep whatever is scheduled rather than cancelling it.
        guard let place else { return status(.noLocation) }

        let byID = Dictionary(active.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let desired = AlarmPlanner.plan(
            rules: active.map(\.rule),
            at: place.coordinate,
            in: .current,
            now: now,
            days: Self.horizonDays,
            limit: Self.maxScheduled
        )
        do {
            let existing = try manager.alarms
            // Never cancel an alarm that is ringing or snoozed right now.
            let protected = Set(existing.filter { $0.state != .scheduled }.map(\.id))
            let changes = AlarmReconciler.changes(desired: desired, scheduled: Set(existing.map(\.id)), protected: protected)
            for id in changes.cancel {
                try? manager.cancel(id: id)
            }
            for occurrence in changes.schedule {
                guard let alarm = byID[occurrence.ruleID] else { continue }
                _ = try await manager.schedule(id: occurrence.id, configuration: configuration(for: alarm, at: occurrence.date))
            }
            return status(.scheduled(count: desired.count, through: desired.last?.date))
        } catch {
            return status(.failed(error.localizedDescription))
        }
    }

    private func configuration(for alarm: SolarAlarm, at date: Date) -> AlarmManager.AlarmConfiguration<SolarAlarmMetadata> {
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource("\(alarm.title)"),
            stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle"),
            secondaryButton: AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz"),
            // "Snooze" starts a countdown of `postAlert` seconds, then rings again.
            secondaryButtonBehavior: .countdown
        )
        let presentation = AlarmPresentation(
            alert: alert,
            countdown: AlarmPresentation.Countdown(title: "Snoozing"),
            paused: nil
        )
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: SolarAlarmMetadata(alarmID: alarm.id, detail: alarm.detail),
            tintColor: .orange
        )
        return AlarmManager.AlarmConfiguration(
            countdownDuration: Alarm.CountdownDuration(preAlert: nil, postAlert: Self.snoozeDuration),
            schedule: .fixed(date),
            attributes: attributes,
            stopIntent: nil,
            secondaryIntent: nil,
            sound: .default
        )
    }
}
