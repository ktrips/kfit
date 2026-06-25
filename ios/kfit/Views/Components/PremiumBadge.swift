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
    /// Plus限定機能にインラインオーバーレイをかけるmodifier（コンポーネント内用）
    func plusOverlay(isPlus: Bool, onTapUpgrade: (() -> Void)? = nil) -> some View {
        modifier(PlusOverlay(isPlus: isPlus, onTapUpgrade: onTapUpgrade))
    }
}

// MARK: - PlusGateBlurModifier（Freeユーザーへのブラー・Plusバッジオーバーレイ）

/// Free ユーザーにはコンテンツをブラーしてPlusバッジを表示するViewModifier
struct PlusGateBlurModifier: ViewModifier {
    let isPlus: Bool
    var featureName: String = "分析レポート"

    func body(content: Content) -> some View {
        ZStack {
            content
                .blur(radius: isPlus ? 0 : 7)
                .saturation(isPlus ? 1 : 0.25)
                .allowsHitTesting(isPlus)

            if !isPlus {
                VStack(spacing: 8) {
                    PlusBadge(size: 34)
                    Text("Plus で解放")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "#333333"))
                    Text(featureName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "#888888"))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.ultraThinMaterial)
                        .shadow(color: Color.black.opacity(0.10), radius: 8, y: 3)
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

extension View {
    /// Free ユーザーにはブラーをかけて「Plus で解放」バッジを表示
    func plusGated(isPlus: Bool, featureName: String = "分析レポート") -> some View {
        modifier(PlusGateBlurModifier(isPlus: isPlus, featureName: featureName))
    }
}

// MARK: - PlusLockedSection（コンパクトなロックバナー）

/// 1ページに1つ置くコンパクトなロックバナー。
/// ロックされている機能名を箇条書きで示す。
struct PlusLockedSection: View {
    let features: [String]
    var onUpgrade: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                PlusBadge(size: 20)
                Text("Plus で解放")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "#FF8C00"))
                Spacer()
                if let onUpgrade {
                    Button(action: onUpgrade) {
                        Text("アップグレード →")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: "#FF8C00"))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(hex: "#FF8C00"), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(features, id: \.self) { feature in
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundColor(Color(hex: "#FF8C00").opacity(0.6))
                        Text(feature)
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#888888"))
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "#FF8C00").opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "#FF8C00").opacity(0.22), lineWidth: 1)
        )
        .cornerRadius(12)
    }
}

// MARK: - PlusFullLockView（タブ全体ロック画面）

/// MINDタブなど、タブ全体をPlusでロックする場合のフルスクリーン表示
struct PlusFullLockView: View {
    let tabIcon: String
    let tabName: String
    let features: [String]
    var onUpgrade: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 20) {
                // アイコン
                ZStack {
                    Circle()
                        .fill(Color(hex: "#CE82FF").opacity(0.12))
                        .frame(width: 80, height: 80)
                    Image(systemName: tabIcon)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(Color(hex: "#CE82FF").opacity(0.6))
                }

                VStack(spacing: 6) {
                    Text("\(tabName)タブは")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "#333333"))
                    HStack(spacing: 6) {
                        PlusBadge(size: 22)
                        Text("Plus 限定です")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: "#FF8C00"))
                    }
                }

                // 機能リスト
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(features, id: \.self) { feature in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "#FF8C00"))
                            Text(feature)
                                .font(.system(size: 13))
                                .foregroundColor(Color(hex: "#555555"))
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            .padding(28)
            .background(Color(.systemBackground))
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.08), radius: 12, y: 4)
            .padding(.horizontal, 32)

            // アップグレードボタン
            if let onUpgrade {
                Button(action: onUpgrade) {
                    HStack(spacing: 8) {
                        PlusBadge(size: 20)
                        Text("Plus にアップグレード")
                            .font(.system(size: 14, weight: .black))
                        Text("月額¥480〜")
                            .font(.system(size: 11)).opacity(0.85)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "#FF8C00"), Color(hex: "#FFD700")],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
                    .shadow(color: Color(hex: "#FF8C00").opacity(0.35), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
            }

            Spacer()
        }
    }
}

// MARK: - 後方互換エイリアス（削除予定）
typealias PremiumBadge = PlusBadge

#Preview {
    HStack(spacing: 20) {
        PlusBadge(size: 16)
        PlusBadge(size: 24)
        PlusBadge(size: 40)
        Text("Plus機能").plusOverlay(isPlus: false)
        Text("Plus機能").plusOverlay(isPlus: true)
    }
    .padding()
}
