import Foundation
import SunCore
import SwiftData

/// A user's alarm: an event plus an offset, optionally repeating. Fire times are never
/// stored; `AlarmScheduler` computes them for wherever the device is.
///
/// Sync-ready like `AppSettings`: stable `id`, `updatedAt`, and soft deletes.
@Model
final class SolarAlarm {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// Set instead of deleting the row, so a future sync can propagate deletes.
    var deletedAt: Date?

    var label: String = ""
    var eventRaw: String = SolarEvent.sunrise.rawValue
    var offsetMinutes: Int = 0
    /// `Calendar` weekday numbers (1 = Sunday ... 7 = Saturday); empty means once.
    var weekdays: [Int] = []
    var isEnabled: Bool = true
    /// When the alarm was last turned on; a one-time alarm fires at the first
    /// occurrence after this.
    var armedAt: Date = Date()

    init() {}

    var event: SolarEvent {
        get { SolarEvent(rawValue: eventRaw) ?? .sunrise }
        set { eventRaw = newValue.rawValue }
    }

    var rule: AlarmRule {
        AlarmRule(
            id: id,
            revision: String(updatedAt.timeIntervalSince1970),
            event: event,
            offsetMinutes: offsetMinutes,
            weekdays: Set(weekdays),
            armedAt: armedAt
        )
    }

    var detail: String {
        SolarFormat.alarmDescription(event: event, offsetMinutes: offsetMinutes)
    }

    /// What the alarm says when it rings.
    var title: String {
        label.isEmpty ? detail : label
    }

    /// Turn on, re-arming a one-time alarm from now.
    func enable(at now: Date = .now) {
        isEnabled = true
        armedAt = now
        updatedAt = now
    }

    func touch(at now: Date = .now) {
        updatedAt = now
    }
}

extension SolarAlarm {
    /// "Once", "Every day", "Weekdays", "Weekends", or "Mon, Wed, Fri".
    var repeatDescription: String {
        let days = Set(weekdays)
        switch days {
        case []: return "Once"
        case Set(1...7): return "Every day"
        case [2, 3, 4, 5, 6]: return "Weekdays"
        case [1, 7]: return "Weekends"
        default:
            let symbols = Calendar.current.shortWeekdaySymbols
            return Self.weekdayOrder.filter(days.contains).map { symbols[$0 - 1] }.joined(separator: ", ")
        }
    }

    /// Weekday numbers in the user's locale order (e.g. Monday first in much of Europe).
    static var weekdayOrder: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }
}
