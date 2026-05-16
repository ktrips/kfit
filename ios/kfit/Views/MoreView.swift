import SwiftUI

struct MoreView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var showLogoutConfirm = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.duoBg.ignoresSafeArea()

                List {
                    // 履歴
                    NavigationLink(destination: HistoryView().environmentObject(authManager)) {
                        MenuRow(icon: "calendar", iconColor: Color.duoBlue, label: "履歴")
                    }
                    .listRowBackground(Color.white)

                    // 健康データ
                    NavigationLink(destination: HealthView()) {
                        MenuRow(icon: "heart.fill", iconColor: Color(red: 1.0, green: 0.294, blue: 0.294), label: "健康データ")
                    }
                    .listRowBackground(Color.white)

                    // ヘルプ
                    NavigationLink(destination: HelpView()) {
                        MenuRow(icon: "questionmark.circle.fill", iconColor: Color.duoOrange, label: "ヘルプ")
                    }
                    .listRowBackground(Color.white)

                    // ログアウト
                    Button(action: {
                        showLogoutConfirm = true
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.right.square.fill")
                                .font(.title3)
                                .foregroundColor(Color.red)
                                .frame(width: 32)

                            Text("ログアウト")
                                .font(.body)
                                .foregroundColor(Color.red)

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.white)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("その他")
            .navigationBarTitleDisplayMode(.large)
            .alert("ログアウト", isPresented: $showLogoutConfirm) {
                Button("キャンセル", role: .cancel) { }
                Button("ログアウト", role: .destructive) {
                    authManager.signOut()
                }
            } message: {
                Text("ログアウトしますか？\n別のアカウントでログインできます。")
            }
        }
    }
}

struct MenuRow: View {
    let icon: String
    let iconColor: Color
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 32)

            Text(label)
                .font(.body)
                .foregroundColor(Color.duoDark)

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    MoreView()
        .environmentObject(AuthenticationManager.shared)
}
