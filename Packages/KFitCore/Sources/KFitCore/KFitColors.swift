import SwiftUI
import UIKit

// MARK: - Duolingo カラーパレット（kfit / kedu / kmind 共通）
// ⚠️ このファイルが単一の真実のソース。
//    kfit/Extensions/Color+Duo.swift、kedu/KeduStubViews.swift は
//    KFitCore を追加後に削除し、こちらへの参照に切り替える。

public extension Color {
    static let duoGreen     = Color(red: 0.345, green: 0.800, blue: 0.008) // #58CC02
    static let duoBg        = Color(.systemGroupedBackground)
    static let duoRed       = Color(red: 1.000, green: 0.294, blue: 0.294) // #FF4B4B
    static let duoYellow    = Color(red: 1.000, green: 0.851, blue: 0.000) // #FFD900
    static let duoGold      = Color(red: 0.700, green: 0.520, blue: 0.000) // #B38500
    static let duoOrange    = Color(red: 1.000, green: 0.588, blue: 0.000) // #FF9600
    static let duoBlue      = Color(red: 0.110, green: 0.690, blue: 0.965) // #1CB0F6
    static let duoPurple    = Color(red: 0.573, green: 0.278, blue: 0.910) // #9247E8
    static let duoBrown     = Color(red: 0.588, green: 0.353, blue: 0.157) // #966028
    static let duoDark      = Color(.label)
    static let duoSubtitle  = Color(.secondaryLabel)
    static let duoText      = Color(.label)
    static let duoCard      = Color(.systemBackground)
    static let duoBackground = Color(.secondarySystemBackground)

    /// Instagram 風ブランドグラデーション
    static let instagramGradient = LinearGradient(
        colors: [
            Color(red: 0.996, green: 0.855, blue: 0.459),
            Color(red: 0.980, green: 0.494, blue: 0.118),
            Color(red: 0.839, green: 0.161, blue: 0.463),
            Color(red: 0.588, green: 0.184, blue: 0.749),
            Color(red: 0.310, green: 0.357, blue: 0.835)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// "#RRGGBB" 形式の hex 文字列から Color を生成
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

// MARK: - UIScale（フォント・アイコン拡大率）

/// アプリ全体の UI スケール係数。1.0 で元のサイズ。
public enum UIScale {
    public static let font: CGFloat = 1.2
}

// MARK: - UIImage ユーティリティ

public extension UIImage {
    /// 指定サイズにリサイズした UIImage を返す
    func resized(to size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
