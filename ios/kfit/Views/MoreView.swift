import SwiftUI

struct MoreView: View {
    @EnvironmentObject var authManager: AuthenticationManager

    var body: some View {
        NavigationView {
            List {
                // 履歴
                NavigationLink(destination: HistoryView().environmentObject(authManager)) {
                    MenuRow(icon: "calendar", iconColor: Color.duoBlue, label: "履歴")
                }

                // 健康データ
                NavigationLink(destination: HealthView()) {
                    MenuRow(icon: "heart.fill", iconColor: Color(red: 1.0, green: 0.294, blue: 0.294), label: "健康データ")
                }

                // ヘルプ
                NavigationLink(destination: HelpView()) {
                    MenuRow(icon: "questionmark.circle.fill", iconColor: Color.duoOrange, label: "ヘルプ")
                }
            }
            .navigationTitle("その他")
            .navigationBarTitleDisplayMode(.large)
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
