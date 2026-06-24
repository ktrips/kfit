import SwiftUI

// MARK: - PlusBadge

/// Plusユーザー限定機能に表示するゴールドの「+」バッジ
struct PlusBadge: View {
    var size: CGFloat = 18

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#FFD700"), Color(hex: "#FF8C00")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
            Text("+")
                .font(.system(size: size * 0.62, weight: .black, design: .rounded))
                .foregroundColor(.white)
        }
        .shadow(color: Color(hex: "#FF8C00").opacity(0.4), radius: 3, y: 1)
    }
}

// MARK: - PlusOverlay ViewModifier

/// Plus限定コンテンツをラップするViewModifier
struct PlusOverlay: ViewModifier {
    let isPlus: Bool
    var onTapUpgrade: (() -> Void)?

    func body(content: Content) -> some View {
        ZStack(alignment: .topTrailing) {
            content
                .opacity(isPlus ? 1.0 : 0.45)
                .allowsHitTesting(isPlus)

            if !isPlus {
                PlusBadge(size: 18)
                    .offset(x: 4, y: -4)
                    .onTapGesture { onTapUpgrade?() }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isPlus { onTapUpgrade?() }
        }
    }
}

extension View {
    /// Plus限定機能にゲートをかけるmodifier
    func plusGated(isPlus: Bool, onTapUpgrade: (() -> Void)? = nil) -> some View {
        modifier(PlusOverlay(isPlus: isPlus, onTapUpgrade: onTapUpgrade))
    }
}

// MARK: - 後方互換エイリアス（削除予定）
typealias PremiumBadge = PlusBadge

#Preview {
    HStack(spacing: 20) {
        PlusBadge(size: 16)
        PlusBadge(size: 24)
        PlusBadge(size: 40)
        Text("Plus機能").plusGated(isPlus: false)
        Text("Plus機能").plusGated(isPlus: true)
    }
    .padding()
}
