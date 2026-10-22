import Combine
import CoreLocation
import SwiftData
import SwiftUI
import UIKit

@main
struct SunClockApp: App {
    @State private var locationService: LocationService
    @State private var refresh: RefreshCoordinator
    private let container: ModelContainer

    init() {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: DemoConfig.current != nil)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: AppSettings.self, SolarAlarm.self, configurations: configuration)
        } catch {
            fatalError("Could not open the SwiftData store: \(error)")
        }
        let locationService = LocationService()
        self.container = container
        _locationService = State(initialValue: locationService)
        _refresh = State(initialValue: RefreshCoordinator(container: container, locationService: locationService))
        DemoConfig.current?.seed(container.mainContext)
    }

    var body: some Scene {
        let refresh = refresh
        WindowGroup {
            RootView()
                .environment(locationService)
                .environment(refresh)
        }
        .modelContainer(container)
        // iOS wakes the app in the background for this (when it chooses to): re-plan
        // the alarm window and ask for the next wake-up.
        .backgroundTask(.appRefresh(RefreshCoordinator.backgroundTaskIdentifier)) {
            await MainActor.run { RefreshCoordinator.scheduleBackgroundRefresh() }
            await refresh.refresh("background refresh")
        }
    }
}

/// Ensures the settings row exists, ties location updates to the app's lifecycle, and
/// forwards every event that can move alarm times to the refresh coordinator.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(LocationService.self) private var locationService
    @Environment(RefreshCoordinator.self) private var refresh
    @Query private var allSettings: [AppSettings]
    @State private var tab = DemoConfig.current?.tab ?? "sun"

    var body: some View {
        Group {
            if let settings = allSettings.first {
                TabView(selection: $tab) {
                    Tab("Sun", systemImage: "sun.max", value: "sun") {
                        HomeView(settings: settings)
                    }
                    Tab("Alarms", systemImage: "alarm", value: "alarms") {
                        AlarmListView(settings: settings)
                    }
                }
                .onChange(of: Place.resolve(settings: settings, live: locationService.location)) {
                    refresh.request("location changed")
                }
            } else {
                Color.clear
            }
        }
        .task {
            if allSettings.isEmpty { context.insert(AppSettings()) }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard DemoConfig.current == nil else { return }
            switch phase {
            case .active:
                locationService.startIfAuthorized()
                refresh.request("app opened")
            case .background:
                locationService.stop()
                RefreshCoordinator.scheduleBackgroundRefresh()
            default:
                break
            }
        }
        .onChange(of: locationService.location) { _, location in
            guard let location, let settings = allSettings.first else { return }
            settings.lastLatitude = location.coordinate.latitude
            settings.lastLongitude = location.coordinate.longitude
            settings.lastLocationDate = location.timestamp
            settings.updatedAt = .now
        }
        // Midnight, a clock change, or a carrier time update.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            refresh.request("significant time change")
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            refresh.request("time zone changed")
        }
    }
}
