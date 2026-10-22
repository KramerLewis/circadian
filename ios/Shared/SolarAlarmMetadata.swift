import AlarmKit
import Foundation

/// Extra data attached to each system alarm. Compiled into both the app and the
/// SunClockAlarmUI extension, which renders the alarm's Live Activity.
nonisolated struct SolarAlarmMetadata: AlarmMetadata {
    /// The `SolarAlarm` this occurrence belongs to.
    var alarmID: UUID
    /// e.g. "30 min before sunrise".
    var detail: String
}
