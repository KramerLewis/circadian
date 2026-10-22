import SwiftUI
import WidgetKit

@main
struct SunClockWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SunRingWidget()
        AlarmLiveActivity()
    }
}
