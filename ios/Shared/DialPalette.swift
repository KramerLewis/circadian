import SunCore
import SwiftUI
import UIKit

/// Dial colors that aren't part of the sky gradient (`SkyGradient`), each with a
/// light- and dark-mode variant.
enum DialPalette {
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
