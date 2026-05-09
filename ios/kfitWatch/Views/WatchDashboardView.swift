import SwiftUI

private let duoGreen  = Color(red: 0.345, green: 0.800, blue: 0.008)
private let duoYellow = Color(red: 1.0,   green: 0.851, blue: 0.0)

private func exerciseEmoji(_ id: String) -> String {
    let map: [String: String] = [
        "pushup": "💪", "push-up": "💪",
        "squat": "🏋️", "situp": "🔥", "sit-up": "🔥",
        "lunge": "🦵", "burpee": "⚡", "plank": "🧘"
    ]
    for (key, emoji) in map {
        if id.lowercased().contains(key) { return emoji }
    }
    return "🏃"
}

struct WatchDashboardView: View {
    @StateObject private var connectivity = WatchConnectivityManager.shared
    @State private var showFlow = false

    var body: some View {
        ZStack {
            if connectivity.isLoading && !connectivity.hasLoadedData {
                // 初回ロード中
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: duoGreen))
                        .scaleEffect(1.2)
                    Text("データ読み込み中...")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            } else {
                // メインコンテンツ
                mainContent
            }
        }
        // iOS アプリ起動シグナルを受信したら自動でワークアウトを開始する
        .onChange(of: connectivity.shouldAutoStartWorkout) { triggered in
            if triggered && !showFlow {
                showFlow = true
                connectivity.shouldAutoStartWorkout = false
            }
        }
        // 起動時に最新 stats を iOS に問い合わせる
        .onAppear {
            connectivity.requestStatsFromiOS()
        }
    }

    private var mainContent: some View {
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
                    Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 28)
                    WatchStatItem(icon: "✅", value: "\(connectivity.todaySets)", label: "セット")
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
                if !connectivity.todayExercises.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("今日の記録")
                            .font(.system(size: 9)).foregroundColor(.gray)
                        ForEach(connectivity.todayExercises) { ex in
                            HStack(spacing: 4) {
                                Text(exerciseEmoji(ex.exerciseId))
                                    .font(.system(size: 14))
                                Text(ex.exerciseName)
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.75))
                                Spacer()
                                Text("\(ex.reps)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white.opacity(0.9))
                                Text("+\(ex.points)")
                                    .font(.system(size: 9))
                                    .foregroundColor(duoYellow.opacity(0.9))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.white.opacity(0.07))
                    .cornerRadius(10)
                } else if !connectivity.recentWorkouts.isEmpty {
                    // フォールバック：古い形式の表示
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
