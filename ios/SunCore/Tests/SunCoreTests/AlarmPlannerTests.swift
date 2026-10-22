import Foundation
import Testing
@testable import SunCore

struct AlarmPlannerTests {
    let seattle = Coordinate(latitude: 47.61, longitude: -122.33)
    let tromso = Coordinate(latitude: 69.65, longitude: 18.96)
    let pacific = TimeZone(identifier: "America/Los_Angeles")!
    let weekdays: Set<Int> = [2, 3, 4, 5, 6]

    func rule(_ event: SolarEvent, _ offset: Int = 0, weekdays: Set<Int> = [], armedAt: Date = .distantPast, revision: String = "1") -> AlarmRule {
        AlarmRule(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, revision: revision,
                  event: event, offsetMinutes: offset, weekdays: weekdays, armedAt: armedAt)
    }

    func instant(_ iso: String) -> Date { ReferenceFixture.parseInstant(iso)! }

    @Test func weekdayAlarmsOverTwoWeeks() throws {
        // Saturday noon; Mon-Fri, 30 min before sunrise.
        let now = instant("2026-06-20T12:00:00-07:00")
        let r = rule(.sunrise, -30, weekdays: weekdays)
        let dates = AlarmPlanner.occurrences(of: r, at: seattle, in: pacific, after: now, days: 14)
        #expect(dates.count == 10)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacific
        for date in dates {
            #expect(weekdays.contains(calendar.component(.weekday, from: date)))
            // Late June sunrise in Seattle is ~5:11-5:16, so the alarm is ~4:41-4:46.
            #expect(calendar.component(.hour, from: date) == 4)
        }
        // First one is Monday June 22 (sunrise 5:11:48).
        let first = try #require(dates.first)
        #expect(calendar.component(.day, from: first) == 22)
        #expect(dates == dates.sorted())
    }

    @Test func oneTimeAlarmFiresAtTheNextOccurrenceAfterArming() throws {
        let afternoon = instant("2026-06-21T15:00:00-07:00")
        let sunsetToday = try #require(AlarmPlanner.oneTimeFireDate(of: rule(.sunset, armedAt: afternoon), at: seattle, in: pacific))
        #expect(abs(sunsetToday.timeIntervalSince(instant("2026-06-21T21:10:52-07:00"))) < 60)

        let late = instant("2026-06-21T22:00:00-07:00")
        let sunsetTomorrow = try #require(AlarmPlanner.oneTimeFireDate(of: rule(.sunset, armedAt: late), at: seattle, in: pacific))
        #expect(sunsetTomorrow > late)
        #expect(sunsetTomorrow.timeIntervalSince(sunsetToday) > 23 * 3600)
    }

    @Test func firedOneTimeAlarmIsNotPlannedAgain() {
        let armed = instant("2026-06-21T15:00:00-07:00")
        let afterSunset = instant("2026-06-21T22:00:00-07:00")
        let plan = AlarmPlanner.plan(rules: [rule(.sunset, armedAt: armed)], at: seattle, in: pacific, now: afterSunset)
        #expect(plan.isEmpty)
        #expect(AlarmPlanner.nextFireDate(of: rule(.sunset, armedAt: armed), at: seattle, in: pacific, after: afterSunset) == nil)
    }

    @Test func largeOffsetsCrossMidnight() throws {
        // Astronomical dusk on Sunday June 21 is 00:19 Monday; +60 min is 01:19 Monday,
        // but it belongs to Sunday's solar day, so a Sunday-only alarm includes it.
        let now = instant("2026-06-21T12:00:00-07:00")
        let dates = AlarmPlanner.occurrences(of: rule(.astronomicalDusk, 60, weekdays: [1]), at: seattle, in: pacific, after: now, days: 7)
        let first = try #require(dates.first)
        #expect(abs(first.timeIntervalSince(instant("2026-06-22T01:19:24-07:00"))) < 120)
    }

    @Test func polarDaysAreSkipped() {
        let oslo = TimeZone(identifier: "Europe/Oslo")!
        let now = instant("2026-06-21T12:00:00+02:00")
        #expect(AlarmPlanner.occurrences(of: rule(.sunrise, weekdays: Set(1...7)), at: tromso, in: oslo, after: now, days: 14).isEmpty)
        // Solar noon still happens every day.
        #expect(AlarmPlanner.occurrences(of: rule(.solarNoon, weekdays: Set(1...7)), at: tromso, in: oslo, after: now, days: 14).count == 14)
    }

    @Test func planIsSortedCappedAndStable() {
        let now = instant("2026-06-20T12:00:00-07:00")
        let rules = [rule(.sunrise, weekdays: Set(1...7)), {
            var r = rule(.sunset, weekdays: Set(1...7))
            r.id = UUID()
            return r
        }()]
        let plan = AlarmPlanner.plan(rules: rules, at: seattle, in: pacific, now: now, days: 14, limit: 20)
        #expect(plan.count == 20)
        #expect(plan.map(\.date) == plan.map(\.date).sorted())
        #expect(Set(plan.map(\.id)).count == plan.count)
        // Re-planning gives the same IDs.
        let again = AlarmPlanner.plan(rules: rules, at: seattle, in: pacific, now: now, days: 14, limit: 20)
        #expect(again == plan)
    }

    @Test func editingARuleChangesItsOccurrenceIDs() {
        let date = instant("2026-06-22T04:41:00-07:00")
        let a = AlarmPlanner.occurrenceID(rule: rule(.sunrise, revision: "1"), date: date)
        let b = AlarmPlanner.occurrenceID(rule: rule(.sunrise, revision: "2"), date: date)
        let c = AlarmPlanner.occurrenceID(rule: rule(.sunrise, revision: "1"), date: date.addingTimeInterval(120))
        #expect(a == AlarmPlanner.occurrenceID(rule: rule(.sunrise, revision: "1"), date: date))
        #expect(a != b)
        #expect(a != c)
    }

    @Test func reconcilerIsASetDifference() {
        let keep = PlannedAlarm(id: UUID(), ruleID: UUID(), date: .now)
        let add = PlannedAlarm(id: UUID(), ruleID: UUID(), date: .now)
        let stale = UUID()
        let ringing = UUID()
        let changes = AlarmReconciler.changes(desired: [keep, add], scheduled: [keep.id, stale, ringing], protected: [ringing])
        #expect(changes.cancel == [stale])
        #expect(changes.schedule == [add])
    }

    @Test func descriptions() {
        #expect(SolarFormat.alarmDescription(event: .sunrise, offsetMinutes: -30) == "30 min before sunrise")
        #expect(SolarFormat.alarmDescription(event: .solarNoon, offsetMinutes: 60) == "1 hr after solar noon")
        #expect(SolarFormat.alarmDescription(event: .civilDusk, offsetMinutes: 0) == "Civil dusk")
        #expect(SolarFormat.offset(90) == "1 hr 30 min")
    }
}
