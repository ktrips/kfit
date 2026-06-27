import SwiftUI

// MARK: - UIスケール（kfit の Color+Duo と同じ値）
enum UIScale {
    static let font: CGFloat = 1.2
}

// MARK: - Color 拡張（kfit の Color+Duo と同等）
extension Color {
    static let duoGreen     = Color(red: 0.345, green: 0.800, blue: 0.008)
    static let duoBg        = Color(.systemGroupedBackground)
    static let duoRed       = Color(red: 1.000, green: 0.294, blue: 0.294)
    static let duoYellow    = Color(red: 1.000, green: 0.851, blue: 0.000)
    static let duoGold      = Color(red: 0.700, green: 0.520, blue: 0.000)
    static let duoOrange    = Color(red: 1.000, green: 0.588, blue: 0.000)
    static let duoBlue      = Color(red: 0.110, green: 0.690, blue: 0.965)
    static let duoPurple    = Color(red: 0.573, green: 0.278, blue: 0.910)
    static let duoDark      = Color(.label)
    static let duoSubtitle  = Color(.secondaryLabel)
    static let duoCard      = Color(.systemBackground)

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        self.init(
            red:   Double((int >> 16) & 0xFF) / 255,
            green: Double((int >>  8) & 0xFF) / 255,
            blue:  Double( int        & 0xFF) / 255
        )
    }
}
