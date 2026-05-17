import SwiftUI
import WatchKit

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
    @State private var selectedTab = 1  // 初期表示は真ん中（今日のメニュー）
    @State private var showIntakeConfirm = false  // 摂取記録確認ダイアログ
    @State private var pendingIntakeType: String = ""  // 保留中の摂取タイプ
    @State private var pendingIntakeSubtype: String? = nil  // 保留中の摂取サブタイプ
    @State private var intakeConfirmMessage = ""  // 確認メッセージ
    @State private var doubleTapCount = 0  // ダブルタップカウント（デバッグ用）
    @Environment(\.openURL) private var openURL

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
                TabView(selection: $selectedTab) {
                    intakeInputPage
                        .tag(0)

                    mainDashboard
                        .tag(1)

                    wellnessPage
                        .tag(2)

                    healthDataPage
                        .tag(3)
                }
                .tabViewStyle(.page)
            }
        }
        .fullScreenCover(isPresented: $showFlow) {
            WatchWorkoutFlowView(isPresented: $showFlow)
        }
        .alert(intakeConfirmMessage, isPresented: $showIntakeConfirm) {
            Button("キャンセル", role: .cancel) { }
            Button("記録する") {
                connectivity.sendIntakeRecord(type: pendingIntakeType, subtype: pendingIntakeSubtype)
                // 記録後、少し待ってから最新データを取得
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    connectivity.requestStatsFromiOS()
                }
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
            // 最新のApplicationContextを確認（iOSアプリが起動していない場合用）
            connectivity.checkLatestApplicationContext()
            // iOSアプリが起動している場合はリアルタイムでリクエスト
            connectivity.requestStatsFromiOS()
            Task {
                await healthKit.requestAuthorization()
            }
        }
    }

    // MARK: - ダブルタップハンドラー
    private func handleDoubleTap() {
        // 触覚フィードバック
        WKInterfaceDevice.current().play(.success)

        doubleTapCount += 1
        print("[Watch] 👆 Double tap detected (count: \(doubleTapCount))")

        // メインダッシュボード表示中の場合、ワークアウトを開始
        if selectedTab == 1 && !showFlow {
            showFlow = true
        }
        // 摂取記録ページの場合は、水を記録
        else if selectedTab == 0 {
            confirmIntake(type: "water", subtype: nil,
                        message: "水\(connectivity.waterPerCup)mlを追加しますか？")
        }
        // ウェルネスページの場合は、データを更新
        else if selectedTab == 2 {
            Task { await healthKit.fetchAllTodayData() }
        }
        // ヘルスデータページの場合は、データを更新
        else if selectedTab == 3 {
            Task { await healthKit.fetchAllTodayData() }
        }
    }

    // MARK: - 摂取記録入力ページ（左スワイプで表示）
    private var intakeInputPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {
                // ── ヘッダー：食事／ドリンク入力状況 ──────────────────────
                HStack(spacing: 0) {
                    WatchStatItem(
                        icon: "🍽️",
                        value: "\(connectivity.totalMealLogged)/\(connectivity.totalMealGoal)",
                        label: "食事",
                        isCompleted: connectivity.totalMealLogged >= connectivity.totalMealGoal && connectivity.totalMealGoal > 0
                    )
                    Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 32)
                    WatchStatItem(
                        icon: "💧",
                        value: "\(connectivity.totalDrinkLogged)/\(connectivity.totalDrinkGoal)",
                        label: "ドリンク",
                        isCompleted: connectivity.totalDrinkLogged >= connectivity.totalDrinkGoal && connectivity.totalDrinkGoal > 0
                    )
                }
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08))
                .cornerRadius(10)
                .padding(.top, 4)

                // ── 食事 ──────────────────────
                VStack(spacing: 6) {
                    watchIntakeButton(emoji: "🌅", label: "朝食") {
                        confirmIntake(type: "meal", subtype: "breakfast",
                                    message: "朝食\(connectivity.breakfastCalories)kcalを追加しますか？")
                    }
                    watchIntakeButton(emoji: "🍱", label: "昼食") {
                        confirmIntake(type: "meal", subtype: "lunch",
                                    message: "昼食\(connectivity.lunchCalories)kcalを追加しますか？")
                    }
                    watchIntakeButton(emoji: "🍽️", label: "夕食") {
                        confirmIntake(type: "meal", subtype: "dinner",
                                    message: "夕食\(connectivity.dinnerCalories)kcalを追加しますか？")
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.08))
                .cornerRadius(10)

                // ── 水分・コーヒー ──────────────────────
                VStack(spacing: 6) {
                    watchIntakeButton(emoji: "💧", label: "水") {
                        confirmIntake(type: "water", subtype: nil,
                                    message: "水\(connectivity.waterPerCup)mlを追加しますか？")
                    }
                    watchIntakeButton(emoji: "☕", label: "コーヒー") {
                        confirmIntake(type: "coffee", subtype: nil,
                                    message: "コーヒー\(connectivity.coffeePerCup)ml（カフェイン\(connectivity.caffeinePerCup)mg）を追加しますか？")
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.08))
                .cornerRadius(10)

                // ── アルコール ──────────────────────
                VStack(spacing: 6) {
                    watchIntakeButton(emoji: "🍺", label: "ビール") {
                        confirmIntake(type: "alcohol", subtype: "beer",
                                    message: "ビール（アルコール\(String(format: "%.1f", connectivity.beerAlcoholG))g）を追加しますか？")
                    }
                    watchIntakeButton(emoji: "🍷", label: "ワイン") {
                        confirmIntake(type: "alcohol", subtype: "wine",
                                    message: "ワイン（アルコール\(String(format: "%.1f", connectivity.wineAlcoholG))g）を追加しますか？")
                    }
                    watchIntakeButton(emoji: "🥃", label: "酎ハイ") {
                        confirmIntake(type: "alcohol", subtype: "chuhai",
                                    message: "酎ハイ（アルコール\(String(format: "%.1f", connectivity.chuhaiAlcoholG))g）を追加しますか？")
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.08))
                .cornerRadius(10)

                Text("← スワイプでメイン画面へ")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    private func watchIntakeButton(emoji: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(emoji)
                    .font(.system(size: 26))
                Text(label)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(duoGreen)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.08))
            .cornerRadius(9)
        }
        .buttonStyle(.plain)
    }

    // MARK: - メインダッシュボード（2ページ目）
    private var mainDashboard: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {

                // ── ヘッダー：トレーニング／マインドフルネス ────────────────
                HStack(spacing: 0) {
                    WatchStatItem(
                        icon: "💪",
                        value: "\(connectivity.totalTraining)/\(connectivity.totalTrainingGoal)",
                        label: "トレーニング",
                        isCompleted: connectivity.totalTraining >= connectivity.totalTrainingGoal && connectivity.totalTrainingGoal > 0
                    )
                    Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 32)
                    WatchStatItem(
                        icon: "🧘",
                        value: "\(connectivity.totalMindfulness)/\(connectivity.totalMindfulnessGoal)",
                        label: "マインドフル",
                        isCompleted: connectivity.totalMindfulness >= connectivity.totalMindfulnessGoal && connectivity.totalMindfulnessGoal > 0
                    )
                }
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08))
                .cornerRadius(10)

                    // ── スタートボタン ────────────────────
                    Button { showFlow = true } label: {
                        VStack(spacing: 4) {
                            // マスコット
                            Image("mascot")
                                .resizable().scaledToFill()
                                .frame(width: 42, height: 42)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 2))

                            // メッセージ（回数に応じて変化）
                            if connectivity.todaySetCount == 0 {
                                Text("今日のDuofitトレーニング")
                                    .font(.system(size: 15)).fontWeight(.bold)
                                Text("タップして開始")
                                    .font(.system(size: 11)).foregroundColor(.white.opacity(0.7))
                            } else {
                                Text("今日\(connectivity.todaySetCount + 1)回目")
                                    .font(.system(size: 15)).fontWeight(.bold)
                                Text("トレーニングしよう！")
                                    .font(.system(size: 13)).fontWeight(.semibold)
                                    .foregroundColor(.white.opacity(0.85))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(colors: [duoGreen, Color(red: 0.2, green: 0.65, blue: 0.0)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .handGestureShortcut(.primaryAction)

                    // ── マインドフルネスボタン ────────────────────
                    Button {
                        openMindfulnessApp()
                    } label: {
                        VStack(spacing: 3) {
                            Text("🧘").font(.system(size: 32))
                            Text("マインドフルネス").font(.system(size: 13)).fontWeight(.bold)
                            Text("Breatheアプリを開く").font(.system(size: 9)).foregroundColor(.white.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(colors: [Color(red: 0.808, green: 0.51, blue: 1.0), Color(red: 0.58, green: 0.32, blue: 0.76)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)

                    // ── スワイプヒント ────────────────────
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.4))
                        Text("摂取記録")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.4))
                        Spacer()
                        Text("ウェルネス")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.4))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.vertical, 4)

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

    // MARK: - 摂取記録確認
    private func confirmIntake(type: String, subtype: String?, message: String) {
        pendingIntakeType = type
        pendingIntakeSubtype = subtype
        intakeConfirmMessage = message
        showIntakeConfirm = true
    }

    // MARK: - ウェルネスページ（3ページ目）

    private func stressInfo(hrv: Double) -> (label: String, color: Color, emoji: String) {
        if hrv <= 0 { return ("不明", .gray, "❓") }
        if hrv >= 60 { return ("低い", duoGreen, "😌") }
        if hrv >= 40 { return ("やや低い", Color(red: 0.6, green: 0.85, blue: 0.3), "🙂") }
        if hrv >= 20 { return ("普通", duoYellow, "😐") }
        return ("高め", Color(red: 1.0, green: 0.4, blue: 0.3), "😰")
    }

    private var wellnessPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {

                // ── ヘッダー：心拍数 / HRV ────────────────────
                let stress = stressInfo(hrv: healthKit.latestHRV)
                VStack(spacing: 8) {
                    HStack {
                        Text("🫀").font(.system(size: 18))
                        Text("ウェルネス")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                        Spacer()
                        Button {
                            Task { await healthKit.fetchAllTodayData() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14))
                                .foregroundColor(duoGreen)
                        }
                        .buttonStyle(.plain)
                    }

                    // 心拍数 + HRV
                    HStack(spacing: 0) {
                        VStack(spacing: 3) {
                            Text("❤️").font(.system(size: 20))
                            Text(healthKit.averageHeartRate > 0
                                 ? "\(healthKit.averageHeartRate)"
                                 : "—")
                                .font(.system(size: 20, weight: .black))
                                .foregroundColor(.white)
                            Text("bpm").font(.system(size: 9)).foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity)

                        Rectangle()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 1, height: 44)

                        VStack(spacing: 3) {
                            Text("💓").font(.system(size: 20))
                            Text(healthKit.latestHRV > 0
                                 ? String(format: "%.0f", healthKit.latestHRV)
                                 : "—")
                                .font(.system(size: 20, weight: .black))
                                .foregroundColor(.white)
                            Text("ms HRV").font(.system(size: 9)).foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(10)
                }
                .padding(12)
                .background(Color.white.opacity(0.08))
                .cornerRadius(14)
                .onAppear {
                    Task { await healthKit.fetchAllTodayData() }
                }

                // ── ストレス度合い ────────────────────
                HStack(spacing: 12) {
                    Text(stress.emoji).font(.system(size: 28))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ストレス度合い")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                        Text(stress.label)
                            .font(.system(size: 18, weight: .black))
                            .foregroundColor(stress.color)
                        if healthKit.latestHRV > 0 {
                            Text("HRV \(String(format: "%.0f", healthKit.latestHRV))ms から推定")
                                .font(.system(size: 9))
                                .foregroundColor(.gray)
                        } else {
                            Text("HRVデータ取得中...")
                                .font(.system(size: 9))
                                .foregroundColor(.gray)
                        }
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.white.opacity(0.08))
                .cornerRadius(14)

                // ── マインドフルネスボタン ────────────────────
                Button {
                    openMindfulnessApp()
                } label: {
                    VStack(spacing: 6) {
                        Text("🧘").font(.system(size: 34))
                        Text("マインドフルネス")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        Text("Breatheアプリを開く")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.65))
                        if healthKit.todayMindfulnessSessions > 0 {
                            Text("今日 \(healthKit.todayMindfulnessSessions)回実施済み")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(duoGreen)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.808, green: 0.51, blue: 1.0),
                                     Color(red: 0.58, green: 0.32, blue: 0.76)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    // MARK: - マインドフルネスアプリを開く
    private func openMindfulnessApp() {
        // マインドフルネス（旧Breathe）アプリのURL
        if let url = URL(string: "com.apple.mindfulness://") {
            openURL(url)
            print("[Watch] 🧘 Opening Mindfulness app")
        } else {
            // フォールバック: HealthKitに直接記録
            Task {
                await healthKit.saveMindfulnessSession(durationMinutes: 1)
                await healthKit.fetchTodayMindfulness()
                print("[Watch] 🧘 Mindfulness session recorded (fallback)")
            }
        }
    }

    // MARK: - マインドフルネス記録（未使用 - 念のため残す）
    private func recordMindfulness() async {
        // HealthKitに1分間のマインドフルネスセッションを記録
        await healthKit.saveMindfulnessSession(durationMinutes: 1)

        // HealthKitデータを再取得して最新のセッション数を反映
        await healthKit.fetchTodayMindfulness()

        print("[Watch] 🧘 Mindfulness session recorded")
    }

    // MARK: - 健康データページ（2ページ目）
    private var healthDataPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {

                // ── ヘッダー：アクティビティ／スタンド ──────────────────────
                HStack(spacing: 0) {
                    WatchStatItem(
                        icon: "🏃",
                        value: "\(healthKit.todayWorkoutMinutes)分",
                        label: "アクティビティ",
                        isCompleted: healthKit.todayWorkoutMinutes >= 15
                    )
                    Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 32)
                    WatchStatItem(
                        icon: "🕐",
                        value: "\(healthKit.todayStandHours)h",
                        label: "スタンド",
                        isCompleted: healthKit.todayStandHours >= 8
                    )
                }
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08))
                .cornerRadius(10)
                .padding(.top, 0)
                .padding(.bottom, 4)
                .onAppear {
                    connectivity.requestStatsFromiOS()
                    Task { await healthKit.fetchAllTodayData() }
                }

                // ── 今日のApple Health ──────────────────────
                if healthKit.isAuthorized {
                    VStack(spacing: 6) {
                        HStack {
                            Text("💚").font(.system(size: 18))
                            Text("今日のHealth")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white.opacity(0.9))
                            Spacer()
                            Button {
                                Task {
                                    await healthKit.fetchAllTodayData()
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14))
                                    .foregroundColor(duoGreen)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.bottom, 4)

                        VStack(spacing: 7) {
                            watchLargeHealthItem(
                                icon: "😴", label: "睡眠",
                                value: healthKit.sleepHours, goal: 7.0, unit: "h",
                                formatValue: { String(format: "%.1f", $0) }
                            )
                            watchLargeHealthItem(
                                icon: "⚖️", label: "体重",
                                value: healthKit.latestBodyMass, goal: nil, unit: "kg",
                                formatValue: { String(format: "%.1f", $0) }
                            )
                            watchLargeHealthItem(
                                icon: "📊", label: "体脂肪",
                                value: healthKit.latestBodyFatPercentage, goal: nil, unit: "%",
                                formatValue: { String(format: "%.1f", $0) }
                            )
                            watchLargeHealthItem(
                                icon: "👟", label: "歩数",
                                value: Double(healthKit.todaySteps), goal: 10000.0, unit: "歩",
                                formatValue: { "\(Int($0))" }
                            )
                            watchLargeHealthItem(
                                icon: "🏃", label: "アクティビティ",
                                value: Double(healthKit.todayWorkoutMinutes), goal: 30.0, unit: "分",
                                formatValue: { "\(Int($0))" }
                            )
                            watchLargeHealthItem(
                                icon: "🕐", label: "スタンド",
                                value: Double(healthKit.todayStandHours), goal: 12.0, unit: "h",
                                formatValue: { "\(Int($0))" }
                            )
                            watchLargeHealthItem(
                                icon: "❤️", label: "心拍数",
                                value: Double(healthKit.averageHeartRate), goal: nil, unit: "bpm",
                                formatValue: { "\(Int($0))" }
                            )
                            watchLargeHealthItem(
                                icon: "🔥", label: "消費Cal",
                                value: Double(healthKit.todayCalories),
                                goal: Double(connectivity.calorieTarget), unit: "kcal",
                                formatValue: { "\(Int($0))" }
                            )
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(14)

                    // ── 今日の摂取（Apple Healthから取得）──────────────────────
                    VStack(spacing: 6) {
                        HStack {
                            Text("🍽️").font(.system(size: 18))
                            Text("今日の摂取")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white.opacity(0.9))
                            Spacer()
                            Button {
                                Task { await healthKit.fetchAllTodayData() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14))
                                    .foregroundColor(duoGreen)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.bottom, 4)

                        VStack(spacing: 7) {
                            watchLargeHealthItem(
                                icon: "🍽️", label: "摂取Cal",
                                value: healthKit.todayDietaryCalories,
                                goal: Double(connectivity.intakeCaloriesGoal), unit: "kcal",
                                formatValue: { "\(Int($0))" }
                            )
                            watchLargeHealthItem(
                                icon: "💧", label: "水分",
                                value: healthKit.todayDietaryWater,
                                goal: Double(connectivity.intakeWaterGoal), unit: "ml",
                                formatValue: { "\(Int($0))" }
                            )
                            watchLargeHealthItem(
                                icon: "☕", label: "カフェイン",
                                value: healthKit.todayDietaryCaffeine,
                                goal: Double(connectivity.intakeCaffeineLimit), unit: "mg",
                                formatValue: { "\(Int($0))" }, isReverse: true
                            )
                            watchLargeHealthItem(
                                icon: "🍺", label: "アルコール",
                                value: healthKit.todayDietaryAlcohol,
                                goal: connectivity.intakeAlcoholLimit, unit: "g",
                                formatValue: { String(format: "%.1f", $0) }, isReverse: true
                            )
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(14)
                } else {
                    VStack(spacing: 14) {
                        Text("💚").font(.system(size: 36))
                        Text("Apple Healthと連動")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                        Text("健康データと摂取データを自動取得")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                        Button {
                            Task { await healthKit.requestAuthorization() }
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
    let icon: String
    let value: String
    let label: String
    var isCompleted: Bool = false

    var body: some View {
        VStack(spacing: 2) {
            Text(icon).font(.system(size: 20))
            Text(value)
                .font(.system(size: 16))
                .fontWeight(.black)
                .foregroundColor(isCompleted ? duoGreen : .white)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.gray)
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

// ── Watch用コンパクトヘルスアイテム（2列レイアウト）────────────────────────────────
private func watchCompactHealthItem(
    icon: String,
    label: String,
    value: Double,
    goal: Double?,
    unit: String,
    formatValue: (Double) -> String,
    isReverse: Bool = false
) -> some View {
    let percent = goal != nil && goal! > 0 ? min(Int((value / goal!) * 100), 100) : 0
    let isGood = goal == nil ? (value > 0) : (isReverse ? (value <= goal!) : (value >= goal!))

    return VStack(alignment: .leading, spacing: 3) {
        // アイコン + ラベル
        HStack(spacing: 3) {
            Text(icon).font(.system(size: 11))
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white.opacity(0.8))
        }

        // 値表示
        HStack(alignment: .bottom, spacing: 2) {
            Text(value > 0 ? formatValue(value) : "—")
                .font(.system(size: 13, weight: .black))
                .foregroundColor(isGood ? duoGreen : .white)
            Text(unit)
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(0.6))
                .padding(.bottom, 1)
        }

        // プログレスバー（目標がある場合のみ）
        if let _ = goal {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2)).frame(height: 2)
                    Capsule().fill(isGood ? duoGreen : Color.orange)
                        .frame(width: max(2, geo.size.width * CGFloat(percent) / 100), height: 2)
                }
            }
            .frame(height: 2)
        }
    }
    .padding(6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white.opacity(0.05))
    .cornerRadius(7)
}

// ── Watch用大きめのヘルスアイテム（1列レイアウト）────────────────────────────────
private func watchLargeHealthItem(
    icon: String,
    label: String,
    value: Double,
    goal: Double?,
    unit: String,
    formatValue: (Double) -> String,
    isReverse: Bool = false
) -> some View {
    let percent = goal != nil && goal! > 0 ? min(Int((value / goal!) * 100), 100) : 0
    let isGood = goal == nil ? (value > 0) : (isReverse ? (value <= goal!) : (value >= goal!))
    let isOver = goal != nil && isReverse && value > goal!

    return VStack(alignment: .leading, spacing: 4) {
        // アイコン + ラベル
        HStack(spacing: 4) {
            Text(icon).font(.system(size: 16))
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
            Spacer()
            // パーセンテージ表示（目標がある場合のみ）
            if let _ = goal {
                Text("\(percent)%")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isOver ? Color.red : (isGood ? duoGreen : Color.orange))
            }
        }

        // 値表示
        HStack(alignment: .bottom, spacing: 3) {
            Text(value > 0 ? formatValue(value) : "—")
                .font(.system(size: 18, weight: .black))
                .foregroundColor(isOver ? Color.red : (isGood ? duoGreen : .white))
            Text(unit)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
                .padding(.bottom, 1)
            if isOver {
                Text("過剰")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color.red)
                    .padding(.bottom, 1)
            }
        }

        // プログレスバー（目標がある場合のみ）
        if let _ = goal {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2)).frame(height: 3)
                    Capsule().fill(isOver ? Color.red : (isGood ? duoGreen : Color.orange))
                        .frame(width: max(3, geo.size.width * CGFloat(percent) / 100), height: 3)
                }
            }
            .frame(height: 3)
        }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white.opacity(0.08))
    .cornerRadius(10)
}
