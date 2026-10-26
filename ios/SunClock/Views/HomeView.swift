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
                    Menu("Display", systemImage: "clock") {
                        Picker("Time Display", selection: $settings.timeDisplay) {
                            ForEach(TimeDisplay.allCases) { Text($0.title).tag($0) }
                        }
                        Picker("Dial", selection: $settings.dialOrientation) {
                            ForEach(DialOrientation.allCases) { Text($0.title).tag($0) }
                        }
                        Picker("Moon", selection: $settings.moonPlacement) {
                            ForEach(MoonPlacement.allCases) { Text($0.title).tag($0) }
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

    /// "Next: Moonset 1:01 AM · Moonrise 2:24 PM"
    private func nextMoonTimes(_ sky: MoonDialModel.Sky) -> String? {
        let times = [(sky.nextRise, "Moonrise"), (sky.nextSet, "Moonset")]
            .compactMap { date, name in date.map { ($0, name) } }
            .sorted { $0.0 < $1.0 }
            .map { "\($0.1) \($0.0.formatted(date: .omitted, time: .shortened))" }
        return times.isEmpty ? nil : "Next: " + times.joined(separator: " · ")
    }

    private func content(place: Place, now: Date) -> some View {
        let day = SolarCalculator.solarDay(containing: now, at: place.coordinate)
        let readout = SolarReadout(at: now, coordinate: place.coordinate)
        let special = SpecialDayText.today(at: place.coordinate, on: now)
        let headsUp = special == nil ? SpecialDayText.headsUp(at: place.coordinate, after: now) : nil
        let moon = MoonDialModel(now: now, coordinate: place.coordinate)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    SolarDialView(
                        model: DialModel(day: day, now: now),
                        moon: moon,
                        now: now,
                        solarMinutes: SolarCalculator.apparentSolarMinutes(at: now, longitude: place.coordinate.longitude),
                        readout: readout,
                        timeDisplay: settings.timeDisplay,
                        special: special,
                        orientation: settings.dialOrientation,
                        moonPlacement: settings.moonPlacement,
                        coordinate: place.coordinate,
                        onCycleDisplay: {
                            withAnimation { settings.timeDisplay = settings.timeDisplay.next }
                        }
                    )
                    .frame(maxWidth: 420)
                    if settings.moonPlacement == .sky, let times = nextMoonTimes(moon.sky) {
                        // The sky view's moon ticks don't line up with the hours.
                        Text(times)
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .padding(.top, -12)
                    }
                    if let special {
                        SpecialDayBanner(special: special)
                    } else if let headsUp {
                        Label(headsUp, systemImage: "calendar.badge.clock")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(.secondarySystemGroupedBackground), in: .capsule)
                    }
                    ReadoutView(readout: readout)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Today")
                            .font(.headline)
                            .padding(.horizontal, 4)
                        EventListView(day: day, now: now)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Moon")
                            .font(.headline)
                            .padding(.horizontal, 4)
                        MoonListView(day: day, coordinate: place.coordinate, now: now)
                    }
                    .id("moon")
                    Text(place.coordinate.formatted)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .onAppear {
                if let target = DemoConfig.current?.scroll { proxy.scrollTo(target, anchor: .bottom) }
            }
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
