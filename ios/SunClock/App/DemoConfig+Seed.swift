import Foundation
import SunCore
import SwiftData

extension DemoConfig {
    /// Sample data for the in-memory demo store.
    func seed(_ context: ModelContext) {
        let settings = AppSettings()
        if let timeDisplay { settings.timeDisplayRaw = timeDisplay }
        if let dialOrientation { settings.dialOrientationRaw = dialOrientation }
        if let moonPlacement { settings.moonPlacementRaw = moonPlacement }
        if let handColor { settings.handColorRaw = handColor }
        context.insert(settings)
        let samples: [(String, SolarEvent, Int, [Int], Bool)] = [
            ("Wake up", .sunrise, -30, [2, 3, 4, 5, 6], true),
            ("", .solarNoon, 60, Array(1...7), true),
            ("Evening walk", .civilDusk, 0, [1, 7], false),
            ("", .nauticalDawn, 0, [], true),
        ]
        for (label, event, offset, weekdays, enabled) in samples {
            let alarm = SolarAlarm()
            alarm.label = label
            alarm.event = event
            alarm.offsetMinutes = offset
            alarm.weekdays = weekdays
            alarm.isEnabled = enabled
            alarm.armedAt = date
            context.insert(alarm)
        }
    }
}
