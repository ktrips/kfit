import SwiftUI
import UIKit

extension UIImage {
    /// 指定サイズにリサイズした UIImage を返す
    func resized(to size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

/// アプリ全体のUIスケール設定。
/// フォントやアイコン（SFシンボル・絵文字）の固定サイズ指定に掛けることで、
/// 一括で「少しだけ大きく」表示する。1.0 に戻せば元のサイズに復帰できる。
enum UIScale {
    /// フォント／アイコンの拡大率
    static let font: CGFloat = 1.2
}

extension Color {
    static let duoGreen     = Color(red: 0.345, green: 0.800, blue: 0.008) // #58CC02
    static let duoBg        = Color(.systemGroupedBackground)   // adaptive: light gray / dark
    static let duoRed       = Color(red: 1.000, green: 0.294, blue: 0.294) // #FF4B4B
    static let duoYellow    = Color(red: 1.000, green: 0.851, blue: 0.000) // #FFD900
    static let duoGold      = Color(red: 0.700, green: 0.520, blue: 0.000) // #B38500
    static let duoOrange    = Color(red: 1.000, green: 0.588, blue: 0.000) // #FF9600
    static let duoBlue      = Color(red: 0.110, green: 0.690, blue: 0.965) // #1CB0F6
    static let duoPurple    = Color(red: 0.573, green: 0.278, blue: 0.910) // #9247E8
    static let duoBrown     = Color(red: 0.588, green: 0.353, blue: 0.157) // #966028
    static let duoDark      = Color(.label)                  // adaptive: dark text / light text
    static let duoSubtitle  = Color(.secondaryLabel)         // adaptive
    static let duoText      = Color(.label)                  // adaptive
    static let duoCard      = Color(.systemBackground)       // adaptive: white / dark gray
    static let duoBackground = Color(.secondarySystemBackground) // adaptive

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
