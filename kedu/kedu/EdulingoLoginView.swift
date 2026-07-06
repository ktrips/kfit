import SwiftUI
import Combine

// MARK: - EdulingoLoginView
// kedu 専用ログイン画面。AuthenticationManager（kfit 共有）で Google ログインを行う。

struct EdulingoLoginView: View {
    @EnvironmentObject private var auth: AuthenticationManager
    @State private var isSigningIn = false

    private let tips: [String] = [
        "🦉 毎日 Duolingo を続けよう！",
        "📖 1日10ページが読書習慣の第一歩",
        "✏️ 勉強記録をシェアしてモチベーションアップ",
        "🌍 語学はコツコツ続けることが一番の近道",
        "🏆 友達と一緒に学ぶと3倍長続きする",
    ]
    @State private var tipIndex = 0
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // 背景グラデーション
            LinearGradient(
                colors: [Color(hex: "#58CC02"), Color(hex: "#1CB0F6")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 60)

                // ロゴ
                VStack(spacing: 12) {
                    Image("kedu_icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 110, height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)

                    HStack(spacing: 0) {
                        Text("Edu")
                            .foregroundColor(Color(hex: "#FFD900"))
                            .font(.system(size: 44, weight: .black, design: .rounded))
                        Text("lingo")
                            .foregroundColor(.white)
                            .font(.system(size: 44, weight: .black, design: .rounded))
                    }
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                }

                Spacer(minLength: 32)

                // キャッチコピー
                VStack(spacing: 8) {
                    Text("語学・勉強・読書を続けよう！")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("学習記録を友達とシェアして\nモチベーションを高めよう")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                Spacer(minLength: 32)

                // ローリングヒント
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.2))
                    Text(tips[tipIndex])
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .id(tipIndex)
                        .animation(.easeInOut(duration: 0.5), value: tipIndex)
                }
                .frame(height: 56)
                .padding(.horizontal, 40)

                Spacer(minLength: 48)

                // Google ログインボタン
                VStack(spacing: 16) {
                    Button {
                        guard !isSigningIn else { return }
                        isSigningIn = true
                        Task {
                            await auth.signInWithGoogle()
                            isSigningIn = false
                        }
                    } label: {
                        HStack(spacing: 12) {
                            if isSigningIn {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "#58CC02")))
                            } else {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(Color(hex: "#58CC02"))
                            }
                            Text(isSigningIn ? "ログイン中..." : "Google でログイン")
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .foregroundColor(Color(hex: "#58CC02"))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    }
                    .disabled(isSigningIn)
                    .padding(.horizontal, 32)

                    Text("kfit アカウントでそのままログインできます")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }

                Spacer(minLength: 60)
            }
        }
        .onReceive(timer) { _ in
            withAnimation {
                tipIndex = (tipIndex + 1) % tips.count
            }
        }
    }
}
