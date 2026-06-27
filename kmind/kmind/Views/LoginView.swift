import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthenticationManager

    var body: some View {
        ZStack {
            // 背景グラデーション
            LinearGradient(
                colors: [Color(hex: "#1a1a2e"), Color(hex: "#16213e"), Color(hex: "#0f3460")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // ロゴ・タイトルエリア
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#6c63ff"), Color(hex: "#5a52e0")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)
                            .shadow(color: Color(hex: "#6c63ff").opacity(0.5), radius: 20)

                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 48))
                            .foregroundStyle(.white)
                    }

                    Text("kmind")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("マインドフルネス × 睡眠 × HRV")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                // 機能紹介カード
                VStack(spacing: 12) {
                    featureRow(icon: "moon.stars.fill", color: Color(hex: "#6c63ff"), title: "睡眠スコア", desc: "毎朝の睡眠質を可視化")
                    featureRow(icon: "waveform.path.ecg", color: Color(hex: "#ff6b9d"), title: "HRV モニタリング", desc: "自律神経の状態をトラッキング")
                    featureRow(icon: "figure.mind.and.body", color: Color(hex: "#43e97b"), title: "マインドフルネス", desc: "瞑想ログと習慣化サポート")
                }
                .padding(.horizontal, 24)

                Spacer()

                // Google ログインボタン
                VStack(spacing: 16) {
                    if auth.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                            .frame(height: 54)
                    } else {
                        Button {
                            Task { await auth.signIn() }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "g.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color(hex: "#4285F4"))

                                Text("Google でログイン")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                        }
                        .padding(.horizontal, 24)

                        // ゲストとして続ける
                        Button {
                            withAnimation {
                                // ゲストモード：サインインせずにアプリを使用
                                // AuthenticationManager に guestMode を設定
                            }
                        } label: {
                            Text("ゲストとして続ける")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.6))
                                .underline()
                        }
                    }

                    if let errorMessage = auth.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 48)
            }
        }
    }

    @ViewBuilder
    private func featureRow(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.2))
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthenticationManager.shared)
}
