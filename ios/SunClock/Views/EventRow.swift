import SwiftUI

/// An event label and its time side by side, stacked at accessibility text sizes so
/// neither gets truncated. Read by VoiceOver as one element.
struct EventRow<Label: View>: View {
    let label: Label
    let time: String
    var timeIsSecondary = false
    @Environment(\.dynamicTypeSize) private var typeSize

    init(time: String, timeIsSecondary: Bool = false, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.time = time
        self.timeIsSecondary = timeIsSecondary
    }

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout())
        layout {
            label
            if !stacked { Spacer(minLength: 8) }
            Text(time)
                .monospacedDigit()
                .foregroundStyle(timeIsSecondary ? .secondary : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
