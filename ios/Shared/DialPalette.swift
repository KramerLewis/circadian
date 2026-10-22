import SunCore
import SwiftUI
import UIKit

/// Dial colors, each with a light- and dark-mode variant.
enum DialPalette {
    static let night = Color(light: rgb(0.10, 0.12, 0.26), dark: rgb(0.05, 0.06, 0.15))

    static func color(for band: DialModel.Band) -> Color {
        switch band {
        case .astronomicalTwilight: Color(light: rgb(0.19, 0.21, 0.42), dark: rgb(0.11, 0.13, 0.29))
        case .nauticalTwilight: Color(light: rgb(0.30, 0.35, 0.62), dark: rgb(0.20, 0.24, 0.47))
        case .civilTwilight: Color(light: rgb(0.56, 0.62, 0.88), dark: rgb(0.38, 0.44, 0.70))
        case .day: Color(light: rgb(1.00, 0.83, 0.42), dark: rgb(0.88, 0.67, 0.28))
        }
    }

    static let sun = Color(light: rgb(0.98, 0.55, 0.05), dark: rgb(1.00, 0.62, 0.15))

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: 1)
    }
}

extension Color {
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}
