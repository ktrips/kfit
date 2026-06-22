import SwiftUI
import GoogleSignIn


struct LoginView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var isLoading = false
    @State private var mascotBounce = false

    private let features: [(icon: String, text: String)] = [
        ("🔥", "連続記録でストリーク継続"),
        ("⚡", "XPを獲得してレベルアップ"),
        ("🏆", "週間リーダーボードで競争"),
        ("📱", "モーションセンサーで筋トレを自動カウント"),
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.duoGreen.opacity(0.3), Color.duoBg],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    Spacer(minLength: 60)

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

                        Text("Fitingo")
                            .font(.system(size: 44 * UIScale.font, weight: .black))
                            .foregroundColor(Color.duoGreen)

                        Text("毎日の運動をゲームのように！Fitingoで習慣に！")
                            .font(.subheadline)
                            .foregroundColor(Color.duoDark)
                            .multilineTextAlignment(.center)
                    }

                    // フィーチャーピル（コンパクト版：2列グリッド）
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(features, id: \.text) { feature in
                            HStack(spacing: 8) {
                                Text(feature.icon)
                                    .font(.body)
                                    .frame(width: 28, height: 28)
                                    .background(Color.duoGreen.opacity(0.13))
                                    .clipShape(Circle())
                                Text(feature.text)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Color.duoDark)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color(.systemBackground))
                            .cornerRadius(10)
                            .shadow(color: Color.black.opacity(0.05), radius: 3, y: 1)
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

                    // 関連書籍バナー
                    VStack(spacing: 10) {
                        Text("📚 関連書籍")
                            .font(.caption)
                            .fontWeight(.black)
                            .foregroundColor(Color.duoSubtitle)
                            .textCase(.uppercase)
                            .tracking(1.2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)

                        // AppleWatch Diet Ultra2
                        Link(destination: URL(string: "https://amzn.to/4ek5fHi")!) {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(red: 0.9, green: 0.97, blue: 0.93))
                                        .frame(width: 44, height: 44)
                                    Text("⌚").font(.title3)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("AppleWatch Diet Ultra2")
                                        .font(.subheadline).fontWeight(.black)
                                        .foregroundColor(Color.duoDark)
                                    Text("Apple Watchで痩せる100のメソッド")
                                        .font(.caption).foregroundColor(Color.duoSubtitle)
                                        .lineLimit(1)
                                    Text("📖 Kindle で読む")
                                        .font(.caption2).fontWeight(.bold)
                                        .foregroundColor(Color(red: 0.85, green: 0.55, blue: 0.0))
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(Color.duoSubtitle)
                            }
                            .padding(12)
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                            .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
                        }
                        .padding(.horizontal, 24)

                        // iOSアプリの作り方
                        Link(destination: URL(string: "https://amzn.to/4ek5fHi")!) {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(red: 0.93, green: 0.95, blue: 1.0))
                                        .frame(width: 44, height: 44)
                                    Text("📱").font(.title3)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Cursor + Claude で iOS アプリを作る")
                                        .font(.subheadline).fontWeight(.black)
                                        .foregroundColor(Color.duoDark)
                                    Text("週末だけで iPhone・Apple Watch アプリを個人開発")
                                        .font(.caption).foregroundColor(Color.duoSubtitle)
                                        .lineLimit(1)
                                    Text("📖 Kindle で読む")
                                        .font(.caption2).fontWeight(.bold)
                                        .foregroundColor(Color(red: 0.85, green: 0.55, blue: 0.0))
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(Color.duoSubtitle)
                            }
                            .padding(12)
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                            .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
                        }
                        .padding(.horizontal, 24)
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
