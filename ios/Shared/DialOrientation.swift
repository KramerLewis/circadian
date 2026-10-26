import Foundation

/// How the dial is turned: fixed with solar noon at the top (the sun travels round), or
/// turning so that now is always at the top (the day passes under the sun).
nonisolated enum DialOrientation: String, CaseIterable, Identifiable {
    case noonAtTop
    case nowAtTop

    var id: Self { self }

    var title: String {
        switch self {
        case .noonAtTop: "Noon at Top"
        case .nowAtTop: "Now at Top"
        }
    }

    /// Degrees to turn the dial (clockwise) when the hand is at `nowAngle`.
    func rotation(nowAngle: Double) -> Double {
        self == .nowAtTop ? -nowAngle : 0
    }
}
