import SwiftUI

// ─── モード定義 ───────────────────────────────────────────────────────────────

private struct LoginMode {
    let index: Int
    let emoji: String
    let label: String
    let sublabel: String
    let accent: Color
    let accentDark: Color
}

private let loginModes: [LoginMode] = [
    LoginMode(index: 0, emoji: "💪", label: "筋トレ",    sublabel: "90秒で体を動かそう",        accent: Color(hex: "#58CC02"), accentDark: Color(hex: "#46A302")),
    LoginMode(index: 1, emoji: "⚖️", label: "ダイエット", sublabel: "毎日1回の体重記録から",       accent: Color(hex: "#CE82FF"), accentDark: Color(hex: "#9C5CC9")),
    LoginMode(index: 2, emoji: "🍱", label: "食事ログ",  sublabel: "写真1枚でカロリー管理",       accent: Color(hex: "#FF9600"), accentDark: Color(hex: "#CC7700")),
    LoginMode(index: 3, emoji: "📚", label: "語学",      sublabel: "スクショ1枚でAI例文作成",     accent: Color(hex: "#1CB0F6"), accentDark: Color(hex: "#1090CC")),
]

// ─── LoginView ────────────────────────────────────────────────────────────────

struct LoginView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @AppStorage("simpleMode.selectedModeIndex") private var selectedModeIndex = 0

    @State private var loadingIndex: Int? = nil

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // ── ヘッダー ─────────────────────────────────────────────────
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image("mascot")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.duoGreen, lineWidth: 2))
                        Text("Fitingo")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.duoGreen)
                    }
                    .padding(.bottom, 12)

                    Text("今度こそ、続く。")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundColor(.duoDark)
                    Text("何を続けますか？ 5日間だけ試してみよう。")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.duoSubtitle)
                }
                .padding(.top, 64)
                .padding(.bottom, 36)

                // ── 4 モードボタン ──────────────────────────────────────────
                VStack(spacing: 14) {
                    ForEach(loginModes, id: \.index) { mode in
                        modeButton(mode)
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                // ── フッター ─────────────────────────────────────────────────
                VStack(spacing: 4) {
                    if let error = authManager.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    Text("選んだカテゴリの90秒モードがスタート")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(.tertiaryLabel))
                }
                .padding(.bottom, 44)
            }
        }
    }

    @ViewBuilder
    private func modeButton(_ mode: LoginMode) -> some View {
        let isLoading = loadingIndex == mode.index
        let isDisabled = loadingIndex != nil

        Button {
            guard loadingIndex == nil else { return }
            selectMode(mode)
        } label: {
            HStack(spacing: 16) {
                Text(mode.emoji)
                    .font(.system(size: 36))
                    .frame(width: 52, height: 52)
                    .background(isLoading ? Color.white.opacity(0.2) : mode.accent.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.label)
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(isLoading ? .white : .duoDark)
                    Text(isLoading ? "Googleでログイン中…" : mode.sublabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isLoading ? .white.opacity(0.8) : .duoSubtitle)
                }

                Spacer()

                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(mode.accent)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(isLoading ? mode.accent : mode.accent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(mode.accent, lineWidth: 2)
            )
            .shadow(color: mode.accent.opacity(isLoading ? 0.3 : 0.15), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled && !isLoading ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.15), value: loadingIndex)
    }

    private func selectMode(_ mode: LoginMode) {
        selectedModeIndex = mode.index
        loadingIndex = mode.index
        Task {
            let success = await authManager.signInWithGoogle()
            await MainActor.run {
                loadingIndex = nil
                if !success && authManager.errorMessage == nil {
                    authManager.errorMessage = "ログインに失敗しました"
                }
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthenticationManager.shared)
}
