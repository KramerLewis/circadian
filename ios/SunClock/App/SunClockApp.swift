import SwiftData
import SwiftUI

@main
struct SunClockApp: App {
    @State private var locationService = LocationService()
    private let container: ModelContainer

    init() {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: DemoConfig.current != nil)
        do {
            container = try ModelContainer(for: AppSettings.self, configurations: configuration)
        } catch {
            fatalError("Could not open the SwiftData store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(locationService)
        }
        .modelContainer(container)
    }
}

/// Ensures the settings row exists and keeps location updates tied to the app's lifecycle.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(LocationService.self) private var locationService
    @Query private var allSettings: [AppSettings]

    var body: some View {
        Group {
            if let settings = allSettings.first {
                HomeView(settings: settings)
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
            case .active: locationService.startIfAuthorized()
            case .background: locationService.stop()
            default: break
            }
        }
        .onChange(of: locationService.location) { _, location in
            guard let location, let settings = allSettings.first else { return }
            settings.lastLatitude = location.coordinate.latitude
            settings.lastLongitude = location.coordinate.longitude
            settings.lastLocationDate = location.timestamp
            settings.updatedAt = .now
        }
    }
}
