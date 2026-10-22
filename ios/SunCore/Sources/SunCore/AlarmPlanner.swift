import Foundation

/// A solar alarm's definition: an event plus an offset, optionally repeating on weekdays.
///
/// This is all that gets stored or synced; actual fire times are computed for wherever
/// the device is.
public struct AlarmRule: Hashable, Sendable {
    public var id: UUID
    /// Changes whenever the alarm is edited, so edits produce new occurrence IDs.
    public var revision: String
    public var event: SolarEvent
    /// Minutes relative to the event; negative is before.
    public var offsetMinutes: Int
    /// `Calendar` weekday numbers (1 = Sunday ... 7 = Saturday). Empty means "once".
    public var weekdays: Set<Int>
    /// When a one-time alarm was turned on; it fires at the first occurrence after this.
    public var armedAt: Date

    public init(id: UUID, revision: String, event: SolarEvent, offsetMinutes: Int, weekdays: Set<Int>, armedAt: Date) {
        self.id = id
        self.revision = revision
        self.event = event
        self.offsetMinutes = offsetMinutes
        self.weekdays = weekdays
        self.armedAt = armedAt
    }

    public var repeats: Bool { !weekdays.isEmpty }
}

/// One concrete alarm to hand to the system.
public struct PlannedAlarm: Hashable, Sendable {
    /// Deterministic: the same rule, revision and fire minute always give the same ID,
    /// so re-planning is idempotent.
    public let id: UUID
    public let ruleID: UUID
    public let date: Date
}

/// Turns alarm rules into fixed fire times over a rolling window.
///
/// The system's alarm API only takes fixed times, but solar times drift every day, so
/// the app keeps the next `days` days of occurrences scheduled and re-plans whenever
/// something that affects them changes (see `AlarmReconciler`).
public enum AlarmPlanner {
    /// How far ahead a one-time alarm looks for its event (polar regions can go months
    /// without a given event).
    public static let oneTimeSearchDays = 30

    /// Fire times for a repeating rule after `start`, up to `days` days ahead.
    public static func occurrences(
        of rule: AlarmRule,
        at coordinate: Coordinate,
        in timeZone: TimeZone,
        after start: Date,
        days: Int
    ) -> [Date] {
        let end = start.addingTimeInterval(Double(days) * 86_400)
        return candidates(rule, coordinate, timeZone, from: start, days: days)
            .filter { $0.date > start && $0.date <= end && (rule.weekdays.isEmpty || rule.weekdays.contains($0.weekday)) }
            .map(\.date)
    }

    /// The fire time of a one-time rule: the first occurrence after it was armed. It may
    /// be in the past, meaning the alarm has already gone off.
    public static func oneTimeFireDate(of rule: AlarmRule, at coordinate: Coordinate, in timeZone: TimeZone) -> Date? {
        candidates(rule, coordinate, timeZone, from: rule.armedAt, days: oneTimeSearchDays)
            .first { $0.date > rule.armedAt }?
            .date
    }

    /// The next time a rule will fire after `now`, if any within its search window.
    public static func nextFireDate(of rule: AlarmRule, at coordinate: Coordinate, in timeZone: TimeZone, after now: Date) -> Date? {
        if rule.repeats {
            return occurrences(of: rule, at: coordinate, in: timeZone, after: now, days: oneTimeSearchDays).first
        }
        return oneTimeFireDate(of: rule, at: coordinate, in: timeZone).flatMap { $0 > now ? $0 : nil }
    }

    /// Every alarm that should be scheduled right now, soonest first, capped at `limit`.
    public static func plan(
        rules: [AlarmRule],
        at coordinate: Coordinate,
        in timeZone: TimeZone,
        now: Date,
        days: Int = 14,
        limit: Int = 64
    ) -> [PlannedAlarm] {
        var planned: [PlannedAlarm] = []
        for rule in rules {
            let dates = rule.repeats
                ? occurrences(of: rule, at: coordinate, in: timeZone, after: now, days: days)
                : oneTimeFireDate(of: rule, at: coordinate, in: timeZone).map { $0 > now ? [$0] : [] } ?? []
            planned += dates.map { PlannedAlarm(id: occurrenceID(rule: rule, date: $0), ruleID: rule.id, date: $0) }
        }
        return Array(planned.sorted { $0.date < $1.date }.prefix(limit))
    }

    /// A stable UUID for one occurrence of a rule, rounded to the minute.
    public static func occurrenceID(rule: AlarmRule, date: Date) -> UUID {
        let minute = Int((date.timeIntervalSince1970 / 60).rounded())
        return StableUUID.make("\(rule.id.uuidString)|\(rule.revision)|\(minute)")
    }

    // MARK: Private

    private struct Candidate {
        let date: Date
        /// Weekday of the local date whose solar day the event belongs to.
        let weekday: Int
    }

    /// Event + offset for each local date from the day before `start` through `days` after.
    /// The day before is included because a large positive offset can push yesterday's
    /// event past `start`.
    private static func candidates(_ rule: AlarmRule, _ coordinate: Coordinate, _ timeZone: TimeZone, from start: Date, days: Int) -> [Candidate] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: start)
        return (-1...days).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let day = SolarCalculator.solarDay(for: date, at: coordinate, in: timeZone)
            guard let eventDate = day[rule.event].date else { return nil }
            return Candidate(
                date: eventDate.addingTimeInterval(Double(rule.offsetMinutes) * 60),
                weekday: calendar.component(.weekday, from: date)
            )
        }
    }
}

/// The difference between what should be scheduled and what is.
public enum AlarmReconciler {
    public struct Changes: Equatable, Sendable {
        public var cancel: [UUID]
        public var schedule: [PlannedAlarm]
    }

    /// Because occurrence IDs encode the rule revision and fire minute, any change to an
    /// occurrence yields a new ID, so reconciling is a set difference.
    ///
    /// - Parameter protected: alarms that must not be cancelled even if no longer wanted
    ///   (one that is ringing or snoozed right now).
    public static func changes(desired: [PlannedAlarm], scheduled: Set<UUID>, protected: Set<UUID> = []) -> Changes {
        let desiredIDs = Set(desired.map(\.id))
        return Changes(
            cancel: scheduled.subtracting(desiredIDs).subtracting(protected).sorted { $0.uuidString < $1.uuidString },
            schedule: desired.filter { !scheduled.contains($0.id) }
        )
    }
}

/// Name-based UUIDs without CryptoKit (so SunCore stays portable): two FNV-1a 64-bit
/// hashes of the name, marked as a version 8 (custom) UUID.
enum StableUUID {
    static func make(_ name: String) -> UUID {
        let bytes = Array(name.utf8)
        var a = fnv1a(bytes, seed: 0xcbf2_9ce4_8422_2325)
        var b = fnv1a(bytes, seed: 0x8422_2325_cbf2_9ce4)
        var out = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            out[i] = UInt8(truncatingIfNeeded: a)
            out[i + 8] = UInt8(truncatingIfNeeded: b)
            a >>= 8
            b >>= 8
        }
        out[6] = (out[6] & 0x0F) | 0x80 // version 8
        out[8] = (out[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (out[0], out[1], out[2], out[3], out[4], out[5], out[6], out[7],
                           out[8], out[9], out[10], out[11], out[12], out[13], out[14], out[15]))
    }

    private static func fnv1a(_ bytes: [UInt8], seed: UInt64) -> UInt64 {
        var hash = seed
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
