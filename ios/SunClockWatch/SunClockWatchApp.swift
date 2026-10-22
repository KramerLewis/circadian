import SunCore
import SwiftUI

@main
struct SunClockWatchApp: App {
    @State private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(model)
                .task { model.start() }
        }
    }
}

struct WatchRootView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if let place = model.context.place {
                    #if DEBUG
                    if DemoConfig.current?.sheet == "complications" {
                        ComplicationGalleryView(place: place, date: DemoConfig.current?.date ?? .now)
                    } else if DemoConfig.current?.sheet == "events" {
                        WatchEventsView(place: place, date: DemoConfig.current?.date ?? .now)
                    } else {
                        WatchDialView(place: place)
                    }
                    #else
                    WatchDialView(place: place)
                    #endif
                } else {
                    NoPlaceView()
                }
            }
        }
    }
}

/// Shown until the iPhone shares a place or the Watch finds its own.
struct NoPlaceView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "sun.horizon")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("Open SunClock on your iPhone to share your location.")
                    .multilineTextAlignment(.center)
                Button(model.locating ? "Locating…" : "Use Watch Location") {
                    Task { await model.useWatchLocation() }
                }
                .disabled(model.locating)
            }
            .padding(.horizontal)
        }
    }
}
