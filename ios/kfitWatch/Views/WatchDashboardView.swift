import SwiftUI

private let duoGreen  = Color(red: 0.345, green: 0.800, blue: 0.008)
private let duoYellow = Color(red: 1.0,   green: 0.851, blue: 0.0)

struct WatchDashboardView: View {
    @StateObject private var connectivity = WatchConnectivityManager.shared
    @State private var showFlow = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {

                // ── ロゴ ──────────────────────────────
                HStack(spacing: 6) {
                    Image("mascot")
                        .resizable().scaledToFill()
                        .frame(width: 26, height: 26)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(duoGreen, lineWidth: 1.5))
                    Text("DuoFit")
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.black)
                        .foregroundColor(duoGreen)
                }

                // ── ステータス ────────────────────────
                HStack(spacing: 0) {
                    WatchStatItem(icon: "🔥", value: "\(connectivity.streak)", label: "連続")
                    Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 28)
                    WatchStatItem(icon: "⭐", value: "\(connectivity.todayXP)", label: "XP")
                    Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 28)
                    WatchStatItem(icon: "💪", value: "\(connectivity.todayReps)", label: "rep")
                }
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08))
                .cornerRadius(12)

                // ── スタートボタン ────────────────────
                Button { showFlow = true } label: {
                    VStack(spacing: 3) {
                        Text("🏋️").font(.title3)
                        Text("今日のメニュー").font(.caption).fontWeight(.bold)
                        Text("タップして開始").font(.system(size: 9)).foregroundColor(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(colors: [duoGreen, Color(red: 0.2, green: 0.65, blue: 0.0)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)

                // ── 今日の記録 ────────────────────────
                if !connectivity.recentWorkouts.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("今日の記録")
                            .font(.system(size: 9)).foregroundColor(.gray)
                        ForEach(connectivity.recentWorkouts, id: \.self) { w in
                            Text(w)
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.75))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.white.opacity(0.07))
                    .cornerRadius(10)
                }
            }
            .padding(10)
        }
        .fullScreenCover(isPresented: $showFlow) {
            WatchWorkoutFlowView(isPresented: $showFlow)
        }
    }
}

struct WatchStatItem: View {
    let icon: String; let value: String; let label: String
    var body: some View {
        VStack(spacing: 2) {
            Text(icon).font(.caption)
            Text(value).font(.caption).fontWeight(.black)
            Text(label).font(.system(size: 8)).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}
