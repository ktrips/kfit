import SwiftUI

extension Color {
    static let duoGreen  = Color(red: 0.345, green: 0.800, blue: 0.008) // #58CC02
    static let duoBg     = Color(red: 0.969, green: 0.969, blue: 0.969) // #F7F7F7
    static let duoRed    = Color(red: 1.000, green: 0.294, blue: 0.294) // #FF4B4B
    static let duoYellow = Color(red: 1.000, green: 0.851, blue: 0.000) // #FFD900 (badge bg only)
    static let duoGold   = Color(red: 0.700, green: 0.520, blue: 0.000) // #B38500 (XP text on light bg)
    static let duoOrange = Color(red: 1.000, green: 0.588, blue: 0.000) // #FF9600
    static let duoBlue   = Color(red: 0.110, green: 0.690, blue: 0.965) // #1CB0F6
    static let duoPurple = Color(red: 0.573, green: 0.278, blue: 0.910) // #9247E8
    static let duoBrown  = Color(red: 0.588, green: 0.353, blue: 0.157) // #966028 (coffee color)
    static let duoDark   = Color(red: 0.15, green: 0.15, blue: 0.15) // #262626 (より濃く、コントラスト改善)
    static let duoSubtitle = Color(red: 0.35, green: 0.35, blue: 0.40) // より濃く
    static let duoText   = Color(red: 0.15, green: 0.15, blue: 0.15) // #262626
    static let duoCard   = Color.white
    static let duoBackground = Color(red: 0.95, green: 0.95, blue: 0.95) // #F2F2F2

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
