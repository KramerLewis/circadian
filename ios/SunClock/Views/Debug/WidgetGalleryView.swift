#if DEBUG
import SunCore
import SwiftUI

/// Debug-only: the widget content at widget sizes, for simulator screenshots (the
/// simulator can't capture real Home Screen widgets from CI). Open with
/// `-demoSheet widgets`.
struct WidgetGalleryView: View {
    let place: Place?
    let date: Date

    private var stored: SharedStore.StoredPlace? {
        place.map { SharedStore.StoredPlace(name: $0.name, latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                HStack(spacing: 24) {
                    tile("Small", width: 170, height: 170)
                    lockScreen
                }
                tile("Large", width: 364, height: 382)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func tile(_ title: String, width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 8) {
            SunRingWidgetContent(place: stored, date: date)
                .padding(16)
                .frame(width: width, height: height)
                .background(Color(.systemBackground), in: .rect(cornerRadius: 24))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var lockScreen: some View {
        VStack(spacing: 8) {
            SunRingWidgetContent(place: stored, date: date, monochrome: true, thickness: 0.38)
                .padding(4)
                .frame(width: 76, height: 76)
                .background(.white.opacity(0.15), in: .circle)
                .frame(width: 130, height: 170)
                .background(
                    LinearGradient(colors: [.indigo, .black], startPoint: .top, endPoint: .bottom),
                    in: .rect(cornerRadius: 24)
                )
            Text("Lock Screen").font(.caption).foregroundStyle(.secondary)
        }
    }
}
#endif
