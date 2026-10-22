import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

@main
struct SunClockAlarmUIBundle: WidgetBundle {
    var body: some Widget {
        AlarmLiveActivity()
    }
}

/// Lock Screen and Dynamic Island UI for a SunClock alarm while it counts down (i.e.
/// while snoozed). The ringing alert itself is drawn by the system from the alarm's
/// `AlarmPresentation`; AlarmKit requires this extension for the countdown state.
struct AlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<SolarAlarmMetadata>.self) { context in
            HStack(spacing: 16) {
                Image(systemName: "sun.horizon.fill")
                    .font(.largeTitle)
                    .foregroundStyle(context.attributes.tintColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.metadata?.detail ?? "SunClock")
                        .font(.headline)
                    StateText(state: context.state)
                        .font(.title2.monospacedDigit())
                }
                Spacer()
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "sun.horizon.fill")
                        .foregroundStyle(context.attributes.tintColor)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.metadata?.detail ?? "SunClock")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StateText(state: context.state)
                        .monospacedDigit()
                }
            } compactLeading: {
                Image(systemName: "sun.horizon.fill")
                    .foregroundStyle(context.attributes.tintColor)
            } compactTrailing: {
                StateText(state: context.state)
                    .monospacedDigit()
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "sun.horizon.fill")
                    .foregroundStyle(context.attributes.tintColor)
            }
        }
    }
}

private struct StateText: View {
    let state: AlarmPresentationState

    var body: some View {
        switch state.mode {
        case .countdown(let countdown):
            Text(timerInterval: Date.now...countdown.fireDate, countsDown: true)
        case .paused:
            Text("Paused")
        default:
            Text("Alarm")
        }
    }
}
