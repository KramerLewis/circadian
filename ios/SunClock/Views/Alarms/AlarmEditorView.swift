import SunCore
import SwiftData
import SwiftUI

/// Create or edit an alarm: event, offset, repeat days, label.
struct AlarmEditorView: View {
    /// nil when creating.
    let alarm: SolarAlarm?
    let place: Place?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(RefreshCoordinator.self) private var refresh

    enum Timing: String, CaseIterable, Identifiable {
        case before = "Before", at = "At", after = "After"
        var id: Self { self }
    }

    @State private var event: SolarEvent = .sunrise
    @State private var timing: Timing = .at
    @State private var minutes = 30
    @State private var weekdays: Set<Int> = []
    @State private var label = ""

    private var offsetMinutes: Int {
        switch timing {
        case .before: -minutes
        case .at: 0
        case .after: minutes
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Event", selection: $event) {
                        ForEach(SolarEvent.allCases) { event in
                            Label(event.displayName, systemImage: event.symbolName).tag(event)
                        }
                    }
                    Picker("Timing", selection: $timing) {
                        ForEach(Timing.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if timing != .at {
                        Stepper(value: $minutes, in: 5...720, step: 5) {
                            LabeledContent("Offset", value: SolarFormat.offset(minutes))
                        }
                    }
                } footer: {
                    Text(preview)
                }

                Section("Repeat") {
                    WeekdayPicker(selection: $weekdays)
                }

                Section("Label") {
                    TextField(SolarFormat.alarmDescription(event: event, offsetMinutes: offsetMinutes), text: $label)
                }

                if let alarm {
                    Section {
                        Button("Delete Alarm", role: .destructive) {
                            alarm.deletedAt = .now
                            alarm.touch()
                            refresh.request("alarm deleted")
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(alarm == nil ? "New Alarm" : "Edit Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .onAppear(perform: load)
        }
    }

    /// "30 min before sunrise · Next: Tue, Jun 23, 4:42 AM"
    private var preview: String {
        let description = SolarFormat.alarmDescription(event: event, offsetMinutes: offsetMinutes)
        guard let place else { return description }
        let now = DemoConfig.current?.date ?? .now
        let rule = AlarmRule(id: UUID(), revision: "", event: event, offsetMinutes: offsetMinutes, weekdays: weekdays, armedAt: now)
        guard let next = AlarmPlanner.nextFireDate(of: rule, at: place.coordinate, in: .current, after: now) else {
            return "\(description) · Doesn't occur in the next \(AlarmPlanner.oneTimeSearchDays) days at \(place.name.lowercased())"
        }
        return "\(description) · Next: \(next.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))"
    }

    private func load() {
        guard let alarm else { return }
        event = alarm.event
        timing = alarm.offsetMinutes < 0 ? .before : alarm.offsetMinutes > 0 ? .after : .at
        minutes = alarm.offsetMinutes == 0 ? 30 : abs(alarm.offsetMinutes)
        weekdays = Set(alarm.weekdays)
        label = alarm.label
    }

    private func save() {
        let target = alarm ?? SolarAlarm()
        if alarm == nil { context.insert(target) }
        target.event = event
        target.offsetMinutes = offsetMinutes
        target.weekdays = weekdays.sorted()
        target.label = label.trimmingCharacters(in: .whitespaces)
        // Saving re-arms the alarm, so a one-time alarm fires at its next occurrence.
        target.enable()
        Task {
            _ = await refresh.scheduler.requestAuthorization()
            refresh.request("alarm saved")
        }
        dismiss()
    }
}

/// Seven round toggles, in the locale's week order.
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let names = Calendar.current.weekdaySymbols
        HStack {
            ForEach(SolarAlarm.weekdayOrder, id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(symbols[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(isOn ? Color.accentColor : Color(.tertiarySystemFill), in: .circle)
                        .foregroundStyle(isOn ? .white : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(names[day - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
