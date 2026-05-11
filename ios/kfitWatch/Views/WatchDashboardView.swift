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
                // メインコンテンツ（タブページング）
                TabView {
                    mainDashboard
                        .tag(0)

                    healthDataPage
                        .tag(1)
                }
                .tabViewStyle(.page)
            }
        }
        .fullScreenCover(isPresented: $showFlow) {
            WatchWorkoutFlowView(isPresented: $showFlow)
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

    // MARK: - メインダッシュボード（1ページ目）
    private var mainDashboard: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {

                // ── ロゴ ──────────────────────────────
                HStack(spacing: 6) {
                    Image("mascot")
                        .resizable().scaledToFill()
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(duoGreen, lineWidth: 2))
                    Text("DuoFit")
                        .font(.system(size: 18, design: .rounded))
                        .fontWeight(.black)
                        .foregroundColor(duoGreen)
                }
                .padding(.top, 4)

                // ── ステータス（統一指標）────────────────────────
                HStack(spacing: 0) {
                    WatchStatItem(icon: "🔥", value: "\(connectivity.streak)", label: "連続")
                    Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 28)
                    WatchStatItem(icon: "📊", value: "\(connectivity.todaySetCount)/\(connectivity.dailySetGoal)", label: "セット")
                    Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 28)
                    WatchStatItem(icon: "💪", value: "\(connectivity.todayReps)", label: "回数")
                }
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08))
                .cornerRadius(10)

                    // ── スタートボタン ────────────────────
                    Button { showFlow = true } label: {
                        VStack(spacing: 3) {
                            Text("🏋️").font(.system(size: 32))
                            Text("今日のメニュー").font(.system(size: 13)).fontWeight(.bold)
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

                    // ── 今日の記録（詳細版：個別セット表示）────────────────────────
                    if !connectivity.todayExercises.isEmpty {
                        VStack(spacing: 4) {
                            HStack {
                                Text("📝")
                                    .font(.system(size: 12))
                                Text("今日の記録")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white.opacity(0.9))
                                Spacer()
                                Text("\(connectivity.todaySetCount)セット")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white.opacity(0.7))
                            }

                            // 各セットを時刻と回数で表示
                            ForEach(Array(connectivity.todayExercises.enumerated()), id: \.element.id) { index, ex in
                                HStack(spacing: 5) {
                                    // 時刻
                                    Text(timeString(from: ex.timestamp))
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white.opacity(0.7))
                                        .frame(width: 38, alignment: .leading)

                                    // 絵文字
                                    Text(exerciseEmoji(ex.exerciseId))
                                        .font(.system(size: 13))

                                    // 種目名
                                    Text(ex.exerciseName)
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.8))
                                        .lineLimit(1)

                                    Spacer()

                                    // 回数
                                    Text("\(ex.reps)回")
                                        .font(.system(size: 11, weight: .black))
                                        .foregroundColor(.white)
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 7)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(7)
                            }
                        }
                        .padding(6)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(10)
                    } else if !connectivity.recentWorkouts.isEmpty {
                        // フォールバック：古い形式の表示
                        VStack(alignment: .leading, spacing: 3) {
                            Text("今日の記録")
                                .font(.system(size: 10)).foregroundColor(.gray)
                            ForEach(connectivity.recentWorkouts, id: \.self) { w in
                                Text(w)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.75))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(7)
                        .background(Color.white.opacity(0.07))
                        .cornerRadius(9)
                    }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    // MARK: - 健康データページ（2ページ目）
    private var healthDataPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {

                // ── ロゴ ──────────────────────────────
                HStack(spacing: 6) {
                    Image("mascot")
                        .resizable().scaledToFill()
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(duoGreen, lineWidth: 2))
                    Text("DuoFit")
                        .font(.system(size: 18, design: .rounded))
                        .fontWeight(.black)
                        .foregroundColor(duoGreen)
                }
                .padding(.top, 4)

                // ── 今日のApple Healthデータ ──────────────────────
                if healthKit.isAuthorized {
                    VStack(spacing: 6) {
                        HStack {
                            Text("💚")
                                .font(.system(size: 14))
                            Text("今日のApple Healthデータ")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white.opacity(0.9))
                            Spacer()
                        }
                        .padding(.bottom, 2)

                        // 睡眠時間（目標: 7時間）
                        compactHealthGoalRow(
                            icon: "😴",
                            value: healthKit.sleepHours,
                            goal: 7.0,
                            unit: "時間",
                            formatValue: { String(format: "%.1f", $0) }
                        )

                        // 体重・体脂肪
                        HStack(spacing: 4) {
                            compactMetricTile(
                                icon: "⚖️",
                                value: healthKit.latestBodyMass > 0 ? String(format: "%.1f", healthKit.latestBodyMass) : "—",
                                unit: "kg"
                            )
                            compactMetricTile(
                                icon: "📊",
                                value: healthKit.latestBodyFatPercentage > 0 ? String(format: "%.1f", healthKit.latestBodyFatPercentage) : "—",
                                unit: "%"
                            )
                        }

                        // 歩数（目標: 10,000歩）
                        compactHealthGoalRow(
                            icon: "👟",
                            value: Double(healthKit.todaySteps),
                            goal: 10000.0,
                            unit: "歩",
                            formatValue: { "\(Int($0))" }
                        )

                        // 消費カロリー（目標: カロリー目標）
                        compactHealthGoalRow(
                            icon: "🔥",
                            value: Double(healthKit.todayCalories),
                            goal: Double(connectivity.calorieTarget),
                            unit: "kcal",
                            formatValue: { "\(Int($0))" }
                        )

                        // 心拍数（目標なし）
                        if healthKit.averageHeartRate > 0 {
                            HStack(spacing: 5) {
                                Text("❤️").font(.system(size: 13))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("心拍数")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white.opacity(0.8))
                                    HStack(spacing: 2) {
                                        Text("\(healthKit.averageHeartRate)")
                                            .font(.system(size: 14, weight: .black))
                                            .foregroundColor(.white)
                                        Text("bpm")
                                            .font(.system(size: 9))
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(9)
                        }
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(10)
                } else {
                    // 未連携時のプレースホルダー
                    VStack(spacing: 14) {
                        Text("💚")
                            .font(.system(size: 36))

                        Text("Apple Healthと連動")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))

                        Text("健康データを自動取得")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)

                        Button {
                            Task {
                                await healthKit.requestAuthorization()
                            }
                        } label: {
                            Text("許可する")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(duoGreen)
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(14)
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }
}

struct WatchStatItem: View {
    let icon: String; let value: String; let label: String
    var body: some View {
        VStack(spacing: 1) {
            Text(icon).font(.system(size: 15))
            Text(value).font(.system(size: 13)).fontWeight(.black)
            Text(label).font(.system(size: 8)).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}

// ── コンパクトな健康メトリック（目標付き）────────────────────────────────
private func compactHealthGoalRow(
    icon: String,
    value: Double,
    goal: Double,
    unit: String,
    formatValue: (Double) -> String
) -> some View {
    let percent = goal > 0 ? min(Int((value / goal) * 100), 100) : 0
    let isAchieved = value >= goal

    return HStack(spacing: 5) {
        Text(icon).font(.system(size: 13))

        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 2) {
                Text(value > 0 ? formatValue(value) : "—")
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(.white)
                Text("/ \(formatValue(goal)) \(unit)")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.6))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2)).frame(height: 5)
                    Capsule().fill(isAchieved ? duoGreen : Color.orange)
                        .frame(width: max(5, geo.size.width * CGFloat(percent) / 100), height: 5)
                }
            }
            .frame(height: 5)
        }

        Spacer()

        Text("\(percent)%")
            .font(.system(size: 11, weight: .black))
            .foregroundColor(isAchieved ? duoGreen : Color.orange)
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 7)
    .background(Color.white.opacity(0.05))
    .cornerRadius(9)
}

// ── コンパクトなメトリックタイル（目標なし）────────────────────────────────
private func compactMetricTile(icon: String, value: String, unit: String) -> some View {
    HStack(spacing: 4) {
        Text(icon).font(.system(size: 13))
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 14, weight: .black))
                .foregroundColor(.white)
            Text(unit)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.6))
        }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 7)
    .background(Color.white.opacity(0.05))
    .cornerRadius(9)
}
