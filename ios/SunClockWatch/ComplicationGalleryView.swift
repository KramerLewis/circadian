#if DEBUG
import SunCore
import SwiftUI
import WidgetKit

/// Debug-only: each complication at roughly its size on a 46 mm watch, for CI
/// screenshots (the simulator can't capture a configured watch face). Open with
/// `-demoSheet complications`.
struct ComplicationGalleryView: View {
    let place: SharedStore.StoredPlace
    let date: Date

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    tile("Circular") {
                        ComplicationView(family: .accessoryCircular, place: place, date: date).frame(width: 52, height: 52)
                    }
                    tile("Tinted") {
                        ComplicationView(family: .accessoryCircular, place: place, date: date, monochrome: true)
                            .frame(width: 52, height: 52)
                            .colorMultiply(.orange)
                    }
                    tile("Corner") {
                        ComplicationView(family: .accessoryCorner, place: place, date: date).frame(width: 40, height: 40)
                    }
                }
                tile("Rectangular · Smart Stack") {
                    ComplicationView(family: .accessoryRectangular, place: place, date: date)
                        .frame(width: 170, height: 52)
                }
                tile("Inline") {
                    ComplicationView(family: .accessoryInline, place: place, date: date)
                        .font(.caption)
                        .frame(width: 170)
                }
            }
        }
    }

    private func tile(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 2) {
            content()
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}
#endif
