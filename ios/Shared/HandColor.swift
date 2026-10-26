import SwiftUI

/// The color of the dial's "now" hand. Gold shimmers: a highlight runs along the hand
/// (held still with Reduce Motion).
nonisolated enum HandColor: String, CaseIterable, Identifiable {
    case royalBlue, red, cyan, green, kryptonPurple, auto, gold

    var id: Self { self }

    var title: String {
        switch self {
        case .royalBlue: "Royal Blue"
        case .red: "Red"
        case .cyan: "Cyan"
        case .green: "Green"
        case .kryptonPurple: "Krypton Purple"
        case .auto: "White or Black (Auto)"
        case .gold: "Gold (Shimmering)"
        }
    }

    var shimmers: Bool { self == .gold }

    /// The hand's color: white on dark backgrounds and black on light ones for `.auto`.
    func color(dark: Bool) -> Color {
        switch self {
        case .royalBlue: Color(red: 0.11, green: 0.42, blue: 1.0)
        case .red: Color(red: 1.0, green: 0.16, blue: 0.2)
        case .cyan: Color(red: 0.0, green: 0.86, blue: 1.0)
        case .green: Color(red: 0.12, green: 0.9, blue: 0.35)
        case .kryptonPurple: Color(red: 0.68, green: 0.36, blue: 1.0)
        case .auto: dark ? .white : .black
        case .gold: Color(red: 1.0, green: 0.78, blue: 0.24)
        }
    }

    /// Gold's highlight and shadow tones, for the shimmer.
    static let goldLight = Color(red: 1.0, green: 0.96, blue: 0.75)
    static let goldDeep = Color(red: 0.78, green: 0.52, blue: 0.08)
}
