import SwiftUI

struct WatchDashboardView: View {
    @StateObject private var connectivity = WatchConnectivityManager.shared
    @State private var showWorkoutSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    // ロゴ
                    HStack(spacing: 6) {
                        Image("mascot")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.green, lineWidth: 1.5))

                        Text("DuoFit")
                            .font(.system(.headline, design: .rounded))
                            .fontWeight(.black)
                            .foregroundColor(.green)
                    }

                    // ステータス
                    HStack(spacing: 4) {
                        WatchStatView(icon: "🔥", value: "\(connectivity.streak)", label: "連続")
                        Divider().frame(height: 28)
                        WatchStatView(icon: "🏆", value: "\(connectivity.todayXP)", label: "XP")
                        Divider().frame(height: 28)
                        WatchStatView(icon: "💪", value: "\(connectivity.todayReps)", label: "rep")
                    }
                    .padding(8)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)

                    // スタートボタン
                    Button(action: { showWorkoutSheet = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.circle.fill")
                            Text("開始")
                                .fontWeight(.bold)
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }

                    // 今日の記録
                    if !connectivity.recentWorkouts.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("今日")
                                .font(.caption2)
                                .foregroundColor(.gray)

                            ForEach(connectivity.recentWorkouts, id: \.self) { workout in
                                Text(workout)
                                    .font(.caption2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(Color(.systemGray5))
                        .cornerRadius(6)
                    }
                }
                .padding(10)
            }
            .sheet(isPresented: $showWorkoutSheet) {
                WatchQuickWorkoutView(isPresented: $showWorkoutSheet)
            }
        }
    }
}

// MARK: - ステータスアイテム
struct WatchStatView: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(icon).font(.caption)
            Text(value).font(.caption2).fontWeight(.black)
            Text(label).font(.system(size: 8)).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    WatchDashboardView()
}
