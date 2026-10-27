import Foundation

/// How the wadokei kanji and animal are drawn (mirrors the web app's kanji styles).
nonisolated enum KanjiStyle: String, CaseIterable, Identifiable {
    /// Holes through the dial with molten rock inside.
    case molten
    /// Black or white, following the appearance.
    case plain
    case silver
    case gold

    var id: Self { self }

    var title: String {
        switch self {
        case .molten: "Molten"
        case .plain: "Plain"
        case .silver: "Silver"
        case .gold: "Gold"
        }
    }

    /// Whether the active kanji moves (molten flickers, metals shimmer).
    var animates: Bool { self != .plain }
}
