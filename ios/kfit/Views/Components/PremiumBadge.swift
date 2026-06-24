import SwiftUI

// MARK: - ゴールドPバッジ（Premium機能マーカー）

struct PremiumBadge: View {
    var size: CGFloat = 16

    var body: some View {
        Text("P")
            .font(.system(size: size * 0.65, weight: .black, design: .rounded))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [Color(hex: "#FFD700"), Color(hex: "#FF8C00")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(Circle())
            .shadow(color: Color(hex: "#FFD700").opacity(0.5), radius: 2, x: 0, y: 1)
    }
}

// MARK: - ViewModifier: Premium機能オーバーレイ

struct PremiumOverlay: ViewModifier {
    let isPremium: Bool
    let onTapUpgrade: (() -> Void)?

    func body(content: Content) -> some View {
        ZStack(alignment: .topTrailing) {
            content
                .opacity(isPremium ? 1.0 : 0.45)
                .allowsHitTesting(isPremium)
            if !isPremium {
                Button {
                    onTapUpgrade?()
                } label: {
                    PremiumBadge(size: 20)
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

extension View {
    /// Premium機能のガード — isPremium=false の時は半透明＋バッジ表示
    func premiumGated(isPremium: Bool, onTapUpgrade: (() -> Void)? = nil) -> some View {
        modifier(PremiumOverlay(isPremium: isPremium, onTapUpgrade: onTapUpgrade))
    }
}

#Preview {
    HStack(spacing: 12) {
        PremiumBadge(size: 14)
        PremiumBadge(size: 20)
        PremiumBadge(size: 28)
    }
    .padding()
}
