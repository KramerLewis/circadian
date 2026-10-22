import SunCore
import SwiftData
import SwiftUI

struct AlarmListView: View {
    let settings: AppSettings
    @Environment(\.modelContext) private var context
    @Environment(LocationService.self) private var locationService
    @Environment(RefreshCoordinator.self) private var refresh
    @Query(filter: #Predicate<SolarAlarm> { $0.deletedAt == nil }, sort: \SolarAlarm.createdAt)
    private var alarms: [SolarAlarm]
    @State private var editing: SolarAlarm?
    @State private var creating = DemoConfig.current?.sheet == "alarm"

    var body: some View {
        let place = Place.resolve(settings: settings, live: locationService.location)
        let now = DemoConfig.current?.date ?? .now
        NavigationStack {
            List {
                if refresh.status?.outcome == .notAuthorized {
                    Section {
                        Label("Alarms are turned off for SunClock. Turn them on in Settings › SunClock › Alarms.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    ForEach(alarms) { alarm in
                        Button { editing = alarm } label: {
                            AlarmRow(alarm: alarm, place: place, now: now)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Edit alarm")
                    }
                    .onDelete(perform: delete)
                } footer: {
                    if let status = refresh.status {
                        Text(statusText(status))
                    }
                }
            }
            .overlay {
                if alarms.isEmpty {
                    ContentUnavailableView(
                        "No Alarms",
                        systemImage: "alarm",
                        description: Text("Add an alarm tied to sunrise, sunset, or any other point in the solar day.")
                    )
                }
            }
            .navigationTitle("Alarms")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add Alarm", systemImage: "plus") { creating = true }
                }
            }
            .sheet(isPresented: $creating) {
                AlarmEditorView(alarm: nil, place: place)
            }
            .sheet(item: $editing) { alarm in
                AlarmEditorView(alarm: alarm, place: place)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            alarms[index].deletedAt = .now
            alarms[index].touch()
        }
        refresh.request("alarm deleted")
    }

    private func statusText(_ status: AlarmScheduler.Status) -> String {
        let when = status.date.formatted(date: .omitted, time: .shortened)
        switch status.outcome {
        case .scheduled(let count, let through):
            let until = through.map { ", through \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? ""
            return "\(count) upcoming alarm\(count == 1 ? "" : "s") scheduled\(until). Updated \(when) (\(status.reason))."
        case .notAuthorized:
            return "Not scheduled: SunClock isn't allowed to set alarms."
        case .noLocation:
            return "Not updated: no location yet. Set one on the Sun tab."
        case .failed(let message):
            return "Couldn't schedule alarms: \(message)"
        }
    }
}

private struct AlarmRow: View {
    @Bindable var alarm: SolarAlarm
    let place: Place?
    let now: Date
    @Environment(RefreshCoordinator.self) private var refresh

    var body: some View {
        let next = place.flatMap {
            AlarmPlanner.nextFireDate(of: alarm.rule, at: $0.coordinate, in: .current, after: now)
        }
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(next.map { $0.formatted(date: .omitted, time: .shortened) } ?? "--:--")
                    .font(.system(.largeTitle, design: .rounded, weight: .light))
                    .monospacedDigit()
                Text(alarm.label.isEmpty ? alarm.detail : "\(alarm.label) · \(alarm.detail)")
                    .font(.subheadline)
                Text(subtitle(next: next))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(alarm.isEnabled ? .primary : .secondary)
            Spacer()
            Toggle(alarm.title, isOn: Binding(
                get: { alarm.isEnabled },
                set: { on in
                    if on {
                        alarm.enable()
                        Task {
                            _ = await refresh.scheduler.requestAuthorization()
                            refresh.request("alarm turned on")
                        }
                    } else {
                        alarm.isEnabled = false
                        alarm.touch()
                        refresh.request("alarm turned off")
                    }
                }
            ))
            .labelsHidden()
        }
        .contentShape(.rect)
    }

    private func subtitle(next: Date?) -> String {
        guard let next else {
            return place == nil ? alarm.repeatDescription : "\(alarm.repeatDescription) · Doesn't occur soon at this location"
        }
        let day = Calendar.current.isDate(next, inSameDayAs: now)
            ? "Today"
            : Calendar.current.isDate(next, inSameDayAs: now.addingTimeInterval(86_400))
                ? "Tomorrow"
                : next.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(alarm.repeatDescription) · \(alarm.isEnabled ? "Next" : "Would be") \(day)"
    }
}
