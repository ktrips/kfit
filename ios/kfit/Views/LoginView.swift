import SwiftUI
import GoogleSignIn

// MARK: - DuoFit カラー定義
extension Color {
    static let duoGreen    = Color(red: 0.345, green: 0.800, blue: 0.008)  // #58CC02
    static let duoOrange   = Color(red: 1.000, green: 0.588, blue: 0.000)  // #FF9600
    static let duoYellow   = Color(red: 1.000, green: 0.851, blue: 0.000)  // #FFD900
    static let duoRed      = Color(red: 1.000, green: 0.294, blue: 0.294)  // #FF4B4B
    static let duoBlue     = Color(red: 0.110, green: 0.690, blue: 0.965)  // #1CB0F6
    static let duoBg       = Color(red: 0.973, green: 0.973, blue: 0.973)  // #F8F8F8
}

struct LoginView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var isLoading = false
    @State private var mascotBounce = false

    private let features: [(icon: String, text: String)] = [
        ("🔥", "連続記録でストリーク継続"),
        ("⚡", "XPを獲得してレベルアップ"),
        ("🏆", "週間リーダーボードで競争"),
        ("📱", "モーションセンサーでrep自動計測"),
    ]

    var body: some View {
        ZStack {
            Color.duoBg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    Spacer(minLength: 40)

                    // マスコット + アプリ名
                    VStack(spacing: 16) {
                        Image("mascot")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.duoGreen, lineWidth: 4))
                            .shadow(color: Color.duoOrange.opacity(0.5), radius: 12)
                            .scaleEffect(mascotBounce ? 1.05 : 1.0)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: mascotBounce)
                            .onAppear { mascotBounce = true }

                        Text("DuoFit")
                            .font(.system(size: 44, weight: .black))
                            .foregroundColor(Color.duoGreen)

                        Text("毎日の運動をゲームにしよう！")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    // フィーチャーピル
                    VStack(spacing: 12) {
                        ForEach(features, id: \.text) { feature in
                            HStack(spacing: 12) {
                                Text(feature.icon)
                                    .font(.title3)
                                    .frame(width: 36, height: 36)
                                    .background(Color.duoGreen.opacity(0.15))
                                    .clipShape(Circle())

                                Text(feature.text)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.white)
                            .cornerRadius(12)
                            .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
                        }
                    }
                    .padding(.horizontal, 24)

                    // Google ログインボタン
                    VStack(spacing: 12) {
                        Button(action: signInWithGoogle) {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                            } else {
                                HStack(spacing: 12) {
                                    Image(systemName: "g.circle.fill")
                                        .font(.title3)
                                    Text("Googleでログイン")
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                            }
                        }
                        .foregroundColor(.white)
                        .background(Color.duoGreen)
                        .cornerRadius(14)
                        .shadow(color: Color.duoGreen.opacity(0.4), radius: 6, y: 4)
                        .disabled(isLoading)
                        .padding(.horizontal, 24)

                        if let error = authManager.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(Color.duoRed)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                    }

                    Spacer(minLength: 40)
                }
            }
        }
    }

    private func signInWithGoogle() {
        isLoading = true
        Task {
            let success = await authManager.signInWithGoogle()
            isLoading = false
            if !success && authManager.errorMessage == nil {
                authManager.errorMessage = "ログインに失敗しました"
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthenticationManager.shared)
}
