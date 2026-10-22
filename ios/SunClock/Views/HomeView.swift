import SunCore
import SwiftData
import SwiftUI

struct HomeView: View {
    @Bindable var settings: AppSettings
    @Environment(LocationService.self) private var locationService
    @State private var showingLocationSettings = DemoConfig.current?.sheet == "location"
    @State private var showingWidgetGallery = DemoConfig.current?.sheet == "widgets"

    var body: some View {
        let place = Place.resolve(settings: settings, live: locationService.location)
        NavigationStack {
            Group {
                if let place {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        content(place: place, now: DemoConfig.current?.date ?? context.date)
                    }
                } else {
                    LocationPromptView(showSettings: { showingLocationSettings = true })
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(place?.name ?? "SunClock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu("Time Display", systemImage: "clock") {
                        Picker("Time Display", selection: $settings.timeDisplay) {
                            ForEach(TimeDisplay.allCases) { Text($0.title).tag($0) }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Location", systemImage: place?.source == .manual ? "mappin.circle" : "location") {
                        showingLocationSettings = true
                    }
                }
            }
            .sheet(isPresented: $showingLocationSettings) {
                LocationSettingsView(settings: settings)
            }
            #if DEBUG
            .sheet(isPresented: $showingWidgetGallery) {
                WidgetGalleryView(place: place, date: DemoConfig.current?.date ?? .now)
            }
            #endif
        }
    }

    private func content(place: Place, now: Date) -> some View {
        let day = SolarCalculator.solarDay(containing: now, at: place.coordinate)
        let readout = SolarReadout(at: now, coordinate: place.coordinate)
        return ScrollView {
            VStack(spacing: 20) {
                SolarDialView(
                    model: DialModel(day: day, now: now),
                    now: now,
                    solarMinutes: SolarCalculator.apparentSolarMinutes(at: now, longitude: place.coordinate.longitude),
                    readout: readout,
                    timeDisplay: settings.timeDisplay,
                    onCycleDisplay: {
                        withAnimation { settings.timeDisplay = settings.timeDisplay.next }
                    }
                )
                .frame(maxWidth: 420)
                ReadoutView(readout: readout)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today")
                        .font(.headline)
                        .padding(.horizontal, 4)
                    EventListView(day: day, now: now)
                }
                Text(place.coordinate.formatted)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

/// Shown until there is any location to compute for.
struct LocationPromptView: View {
    let showSettings: () -> Void
    @Environment(LocationService.self) private var locationService

    var body: some View {
        ContentUnavailableView {
            Label("Where are you?", systemImage: "location.circle")
        } description: {
            Text("SunClock needs your approximate location to calculate the sun's position. Everything is computed on your device.")
        } actions: {
            if !locationService.isDenied {
                Button("Use My Location") { locationService.requestAccess() }
                    .buttonStyle(.borderedProminent)
            }
            Button("Enter a Location") { showSettings() }
        }
    }
}

#Preview {
    HomeView(settings: AppSettings())
        .environment(LocationService())
        .modelContainer(for: AppSettings.self, inMemory: true)
}
