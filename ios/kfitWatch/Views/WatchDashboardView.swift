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

private func timeString(from date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}

struct WatchDashboardView: View {
    @StateObject private var connectivity = WatchConnectivityManager.shared
    @StateObject private var healthKit = WatchHealthKitManager.shared
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
        // 起動時に最新 stats を iOS に問い合わせる & HealthKit データ取得
        .onAppear {
            connectivity.requestStatsFromiOS()
            Task {
                await healthKit.requestAuthorization()
            }
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

                // ── ステータス（統一指標）────────────────────────
                HStack(spacing: 0) {
                    WatchStatItem(icon: "🔥", value: "\(connectivity.streak)", label: "連続")
                    Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 28)
                    WatchStatItem(icon: "📊", value: "\(connectivity.todaySetCount)/\(connectivity.dailySetGoal)", label: "セット")
                    Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 28)
                    WatchStatItem(icon: "🔥", value: "\(connectivity.caloriePercentage)%", label: "Cal")
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

                // ── 目標カロリー ──────────────────────
                VStack(spacing: 4) {
                    HStack {
                        Text("🔥")
                            .font(.system(size: 11))
                        Text("今日の目標カロリー")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                        Spacer()
                        Text("\(connectivity.caloriePercent)%")
                            .font(.system(size: 11, weight: .black))
                            .foregroundColor(connectivity.caloriePercent >= 100 ? duoGreen : Color.orange)
                    }

                    HStack(alignment: .bottom, spacing: 4) {
                        Text("\(connectivity.calorieConsumed)")
                            .font(.system(size: 18, weight: .black))
                            .foregroundColor(.white)
                        Text("/ \(connectivity.calorieTarget) kcal")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.6))
                        Spacer()
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.2)).frame(height: 6)
                            Capsule().fill(
                                connectivity.caloriePercent >= 100 ? duoGreen : Color.orange
                            )
                            .frame(width: max(6, geo.size.width * CGFloat(connectivity.caloriePercent) / 100), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
                .padding(8)
                .background(Color.white.opacity(0.08))
                .cornerRadius(12)

                // ── 今日の健康データ ──────────────────
                if healthKit.isAuthorized {
                    VStack(spacing: 6) {
                        HStack {
                            Text("💚")
                                .font(.system(size: 11))
                            Text("今日の健康データ")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.9))
                            Spacer()
                        }

                        HStack(spacing: 4) {
                            healthDataItem(icon: "👟", value: "\(healthKit.todaySteps)", unit: "歩")
                            healthDataItem(icon: "❤️", value: "\(healthKit.averageHeartRate)", unit: "bpm")
                        }

                        HStack(spacing: 4) {
                            healthDataItem(icon: "🔥", value: "\(healthKit.todayCalories)", unit: "kcal")
                            healthDataItem(icon: "😴", value: String(format: "%.1f", healthKit.sleepHours), unit: "時間")
                        }
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(12)
                }

                // ── 今日の記録（詳細版：個別セット表示）────────────────────────
                if !connectivity.todayExercises.isEmpty {
                    VStack(spacing: 6) {
                        HStack {
                            Text("📝")
                                .font(.system(size: 11))
                            Text("今日の記録")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.9))
                            Spacer()
                            Text("\(connectivity.todaySetCount)セット")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.7))
                        }

                        // 各セットを時刻と回数で表示
                        ForEach(Array(connectivity.todayExercises.enumerated()), id: \.element.id) { index, ex in
                            HStack(spacing: 6) {
                                // 時刻
                                Text(timeString(from: ex.timestamp))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white.opacity(0.7))
                                    .frame(width: 40, alignment: .leading)

                                // 絵文字
                                Text(exerciseEmoji(ex.exerciseId))
                                    .font(.system(size: 12))

                                // 種目名
                                Text(ex.exerciseName)
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.8))
                                    .lineLimit(1)

                                Spacer()

                                // 回数
                                Text("\(ex.reps)回")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundColor(.white)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(8)
                        }
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(12)
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

// ── 健康データアイテム ────────────────────────────────
private func healthDataItem(icon: String, value: String, unit: String) -> some View {
    VStack(spacing: 2) {
        Text(icon).font(.system(size: 12))
        HStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .black))
                .foregroundColor(.white)
            Text(unit)
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(0.6))
        }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 6)
    .background(Color.white.opacity(0.05))
    .cornerRadius(8)
}
