import SwiftUI

/// The card under the dial on a special sky day.
struct SpecialDayBanner: View {
    let special: SpecialDayText

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: special.symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(accent)
                .shadow(color: accent.opacity(0.7), radius: 8)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(special.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(accent)
                ForEach(special.lines, id: \.self) { line in
                    Text(line)
                        .font(.subheadline)
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [accent.opacity(0.28), accent.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18).strokeBorder(accent.opacity(0.45), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var accent: Color {
        switch special.style {
        case .solstice: Color(red: 1.0, green: 0.62, blue: 0.10)
        case .equinox: Color(red: 0.95, green: 0.60, blue: 0.25)
        case .fullMoon: Color(red: 0.55, green: 0.60, blue: 0.85)
        case .supermoon: Color(red: 0.50, green: 0.56, blue: 0.95)
        case .blueMoon: Color(red: 0.25, green: 0.48, blue: 1.0)
        case .newMoon: Color(red: 0.45, green: 0.45, blue: 0.85)
        }
    }
}
