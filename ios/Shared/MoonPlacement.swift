import Foundation

/// Where the moon ring puts the moon: on the sun's hours, so moonrise and moonset read
/// against the clock; or where it is in the sky, so its angle from the sun shows the phase
/// (next to the sun at new moon, opposite at full).
nonisolated enum MoonPlacement: String, CaseIterable, Identifiable {
    case clock
    case sky

    var id: Self { self }

    var title: String {
        switch self {
        case .clock: "Moon on the Clock"
        case .sky: "Moon in the Sky"
        }
    }
}
