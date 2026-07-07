import SwiftUI
import WatchKit

// WatchRuntimeSessionDelegate と startExtendedSession は WatchFlowViews.swift に定義

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

private let _timeStringFmt: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f
}()

private func timeString(from date: Date) -> String {
    _timeStringFmt.string(from: date)
}

/// フィード行用フォーマッタ（行ごとの DateFormatter 生成を避ける）
private let _feedTimeFmt: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "M/d HH:mm"
    f.locale = Locale(identifier: "ja_JP")
    return f
}()

private struct WatchFaceTaskNode {
    let id: String
    let emoji: String
    let accentColor: Color
    let isDone: Bool
    let actionType: String  // "training" | "mindfulness" | "meal" | "water" | "stretch"
    var mealSubtype: String? = nil
    var intakeMessage: String = ""
}

struct WatchDashboardView: View {
    // watchFacePage 用静的 DateFormatter（body 評価のたびに生成しない）
    private static let watchFaceDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d (EEE)"
        f.locale = Locale(identifier: "ja_JP")
        return f
    }()

    @StateObject private var connectivity = WatchConnectivityManager.shared
    @StateObject private var healthKit = WatchHealthKitManager.shared
    @State private var showFlow = false
    @State private var showBreatheFlow = false
    @State private var showStretchFlow = false
    @State private var showStandFlow = false
    @State private var selectedTab = 1  // 初期表示は真ん中（今日のメニュー）
    @State private var showIntakeConfirm = false  // 摂取記録確認ダイアログ
    @State private var pendingIntakeType: String = ""  // 保留中の摂取タイプ
    @State private var pendingIntakeSubtype: String? = nil  // 保留中の摂取サブタイプ
    @State private var intakeConfirmMessage = ""  // 確認メッセージ
    @State private var doubleTapCount = 0  // ダブルタップカウント（デバッグ用）
    @State private var isManualRefreshing = false
    @State private var lastHealthRefreshByScope: [String: Date] = [:]
    // ノード位置キャッシュ（毎 body 評価で再構築しない）
    @State private var cachedNodePositions: [(WatchFaceTaskNode, Double, Double)] = []
    @State private var cachedSpiralMetrics: (startAngle: Double, totalAngle: Double, startRadius: Double, endRadius: Double) = (-140, 402, 32, 80)
    // タブスワイプのデバウンス用タスク
    @State private var tabRefreshTask: Task<Void, Never>?
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

                    watchFacePage
                        .tag(2)

                    wellnessPage
                        .tag(3)

                    healthDataPage
                        .tag(4)

                    feedPage
                        .tag(5)
                }
                .tabViewStyle(.page)
            }
        }
        .fullScreenCover(isPresented: $showFlow) {
            WatchWorkoutFlowView(isPresented: $showFlow)
        }
        .fullScreenCover(isPresented: $showBreatheFlow) {
            WatchBreatheFlowView(isPresented: $showBreatheFlow)
        }
        .fullScreenCover(isPresented: $showStretchFlow) {
            WatchStretchFlowView(isPresented: $showStretchFlow)
        }
        .fullScreenCover(isPresented: $showStandFlow) {
            WatchStandFlowView(isPresented: $showStandFlow)
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
        // W5: タブスワイプ時にキャンセル可能デバウンス(300ms)でリフレッシュ
        .onChange(of: selectedTab) { tab in
            tabRefreshTask?.cancel()
            tabRefreshTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                refreshForSelectedTab(tab)
            }
        }
        // W1: 依存値変化時にノード位置を再計算（毎 body 評価を防ぐ）
        .onChange(of: nodePositionKey) { _ in
            rebuildNodePositions()
        }
        // 起動時に最新 stats を iOS に問い合わせる & HealthKit データ取得
        .onAppear {
            rebuildNodePositions()
            // 最新のApplicationContextを確認（iOSアプリが起動していない場合用）
            connectivity.checkLatestApplicationContext()
            // iOSアプリが起動している場合はリアルタイムでリクエスト
            connectivity.requestStatsFromiOS()
            Task {
                if !healthKit.isAuthorized {
                    await healthKit.requestAuthorization()
                } else {
                    await healthKit.fetchDashboardData()
                }
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
        // ウォッチフェイスページの場合は、ワークアウトを開始
        else if selectedTab == 2 {
            showFlow = true
        }
        // ヘルスデータページの場合は、データを更新
        else if selectedTab == 3 {
            refreshNow(scope: "wellness")
        }
        // ヘルスデータページの場合は、データを更新
        else if selectedTab == 4 {
            refreshNow(scope: "health")
        }
        // フィードページの場合は同期
        else if selectedTab == 5 {
            WKInterfaceDevice.current().play(.success)
            connectivity.requestFeedFromiOS()
        }
    }

    private func refreshNow(scope: String = "dashboard") {
        guard !isManualRefreshing else { return }
        isManualRefreshing = true
        WKInterfaceDevice.current().play(.click)
        Task {
            await refreshHealthData(scope: scope, force: true)
            connectivity.requestStatsFromiOS(scope: scope, force: true)
            isManualRefreshing = false
            WKInterfaceDevice.current().play(.success)
        }
    }

    private func refreshForSelectedTab(_ tab: Int) {
        switch tab {
        case 0:
            Task { await refreshHealthData(scope: "intake") }
            connectivity.requestStatsFromiOS(scope: "intake")
        case 2:
            Task { await refreshHealthData(scope: "watchFace") }
            connectivity.requestStatsFromiOS(scope: "watchFace")
        case 3:
            Task { await refreshHealthData(scope: "wellness") }
            connectivity.requestStatsFromiOS(scope: "wellness")
        case 4:
            Task { await refreshHealthData(scope: "health") }
            connectivity.requestStatsFromiOS(scope: "health")
        case 5:
            connectivity.requestFeedFromiOS()
        default:
            Task { await refreshHealthData(scope: "dashboard") }
            connectivity.requestStatsFromiOS(scope: "dashboard")
        }
    }

    private func refreshHealthData(scope: String, force: Bool = false) async {
        if !force,
           let lastRefresh = lastHealthRefreshByScope[scope],
           Date().timeIntervalSince(lastRefresh) < healthRefreshTTL(for: scope) {
            return
        }
        if !healthKit.isAuthorized {
            await healthKit.requestAuthorization()
        } else {
            await healthKit.fetchData(scope: scope, force: force)
        }
        await MainActor.run {
            lastHealthRefreshByScope[scope] = Date()
        }
    }

    private func healthRefreshTTL(for scope: String) -> TimeInterval {
        switch scope {
        case "intake":
            return 15
        case "watchFace":
            return 15
        case "wellness", "health":
            return 25
        default:
            return 20
        }
    }

    // MARK: - 摂取記録入力ページ（左スワイプで表示）
    private var intakeInputPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {
                // ── ヘッダー：食事／ドリンク入力状況（Apple Health実績）──────────────────────
                ZStack {
                    HStack(spacing: 0) {
                        Button {
                            confirmIntake(type: "meal", subtype: "breakfast",
                                          message: "朝食\(connectivity.breakfastCalories)kcalを追加しますか？")
                        } label: {
                            WatchStatItem(
                                icon: "🍽️",
                                value: "\(Int(healthKit.todayDietaryCalories))k",
                                label: "食事kcal ＋",
                                isCompleted: connectivity.totalMealGoal > 0 && Int(healthKit.todayDietaryCalories) >= connectivity.totalMealGoal
                            )
                        }
                        .buttonStyle(.plain)
                        Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 32)
                        Button {
                            confirmIntake(type: "water", subtype: nil,
                                          message: "水\(connectivity.waterPerCup)mlを追加しますか？")
                        } label: {
                            WatchStatItem(
                                icon: "💧",
                                value: "\(Int(healthKit.todayDietaryWater))ml",
                                label: "水分ml ＋",
                                isCompleted: connectivity.totalDrinkGoal > 0 && Int(healthKit.todayDietaryWater) >= connectivity.totalDrinkGoal
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Button { refreshNow(scope: "intake") } label: {
                        Image(systemName: isManualRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.55))
                            .frame(width: 22, height: 18)
                            .background(Color.black.opacity(0.16))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
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
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {

                // ── トレーニング／カスタム目標（マインドフルネス）────────────────
                ZStack {
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

                    Button { refreshNow(scope: "dashboard") } label: {
                        Image(systemName: isManualRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.55))
                            .frame(width: 22, height: 18)
                            .background(Color.black.opacity(0.16))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
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
                                Text("今日のFitingoトレーニング")
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
                    .modifier(HandGesturePrimaryActionModifier())

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

                    stretchButton

                    standButton

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

                    // ── 今日のトレーニング履歴（先に表示）────────────────────────
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

                    // ── 今日のマインドフルネス履歴（トレーニング履歴の下）────────────────────────
                    mindfulnessHistorySection
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

                // ── 心拍数 / HRV / ストレス ────────────────────
                let stress = stressInfo(hrv: healthKit.latestHRV)
                ZStack(alignment: .topTrailing) {
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

                        Rectangle()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 1, height: 44)

                        VStack(spacing: 3) {
                            Text(stress.emoji).font(.system(size: 20))
                            Text(stress.label)
                                .font(.system(size: 16, weight: .black))
                                .foregroundColor(stress.color)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text("ストレス").font(.system(size: 9)).foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 6)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(12)

                    Button {
                        Task { await refreshHealthData(scope: "wellness", force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.72))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                    .padding(.trailing, 4)
                }

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

                stretchButton
                standButton
                mindfulnessHistorySection

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    private var stretchButton: some View {
        Button {
            showStretchFlow = true
        } label: {
            VStack(spacing: 5) {
                Text("🤸").font(.system(size: 30))
                Text("3分ストレッチ")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Text("Reflectとして保存")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.65))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.35, green: 0.80, blue: 0.55), Color(red: 0.10, green: 0.62, blue: 0.75)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private var standButton: some View {
        Button {
            showStandFlow = true
        } label: {
            VStack(spacing: 5) {
                Text("🍅").font(.system(size: 30))
                Text("20分スタンド")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Text("立って作業に集中")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.99, green: 0.55, blue: 0.12), Color(red: 0.94, green: 0.27, blue: 0.15)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private var mindfulnessHistorySection: some View {
        let samples = healthKit.todayMindfulnessSamples.sorted { $0.startDate > $1.startDate }
        let impacts = healthKit.mindfulnessImpactHistory
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text("🧘").font(.system(size: 11))
                Text("今日のマインドフル")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Text("\(samples.count)件")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
            }

            if samples.isEmpty {
                Text("まだ記録はありません")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(samples.prefix(4)) { session in
                    // セッション開始時刻に近いImpactデータを検索（±5分）
                    let matchedImpact = impacts.first { impact in
                        abs(impact.startDate.timeIntervalSince(session.startDate)) < 300
                    }
                    mindfulnessHistoryRow(session, impact: matchedImpact)
                }
            }
        }
        .padding(7)
        .background(Color.white.opacity(0.07))
        .cornerRadius(10)
    }

    private func mindfulnessHistoryRow(_ session: WatchMindfulnessSession, impact: WatchMindfulnessImpact? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(session.emoji).font(.system(size: 12))
                VStack(alignment: .leading, spacing: 0) {
                    Text(session.typeLabel)
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.white)
                    Text(session.sourceLabel)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.white.opacity(0.52))
                        .lineLimit(1)
                }
                Spacer()
                Text(formatMindfulMinutes(session.durationMinutes))
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(session.typeLabel == "3分ストレッチ" ? Color(red: 0.82, green: 0.51, blue: 1.0) : duoGreen)
            }

            // HealthKitセッションのHR/HRV（直接取得）
            let hkHR = session.averageHeartRate
            let hkHRV = session.averageHRV
            // Impactデータ（before/after）のafter値を使用
            let impactAfterHR = impact?.after.heartRate ?? 0
            let impactAfterHRV = impact?.after.hrv ?? 0

            let displayHR = hkHR > 0 ? hkHR : impactAfterHR
            let displayHRV = hkHRV > 0 ? hkHRV : impactAfterHRV

            if displayHR > 0 || displayHRV > 0 || impact != nil {
                HStack(spacing: 6) {
                    if displayHR > 0 {
                        HStack(spacing: 2) {
                            Text("❤️").font(.system(size: 8))
                            Text("\(Int(displayHR))")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.85))
                            Text("bpm")
                                .font(.system(size: 7))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    if displayHRV > 0 {
                        HStack(spacing: 2) {
                            Text("💙").font(.system(size: 8))
                            Text("\(Int(displayHRV))")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.85))
                            Text("ms")
                                .font(.system(size: 7))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    // Impactデータがあり両端のHRVが有効ならストレス変化をコンパクト表示
                    if let imp = impact, imp.before.hrv > 0 && imp.after.hrv > 0 {
                        let delta = imp.stressDelta
                        let deltaStr = delta == 0 ? "±0" : (delta > 0 ? "+\(delta)" : "\(delta)")
                        let deltaColor: Color = delta < 0 ? duoGreen : delta > 0 ? Color(red: 1.0, green: 0.4, blue: 0.3) : .gray
                        HStack(spacing: 1) {
                            Text("ストレス")
                                .font(.system(size: 7))
                                .foregroundColor(.white.opacity(0.5))
                            Text(deltaStr)
                                .font(.system(size: 9, weight: .black))
                                .foregroundColor(deltaColor)
                        }
                    }
                }
                .padding(.leading, 17)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.06))
        .cornerRadius(7)
    }

    private var wellnessImpactHistorySection: some View {
        let history = healthKit.mindfulnessImpactHistory
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text("📊").font(.system(size: 11))
                Text("心拍・HRV 前後変化")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Text("\(history.count)件")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
            }

            if history.isEmpty {
                Text("セッション完了後に記録されます")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(history.prefix(5)) { impact in
                    wellnessImpactRow(impact)
                }
            }
        }
        .padding(7)
        .background(Color.white.opacity(0.07))
        .cornerRadius(10)
    }

    private static let impactDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        return f
    }()

    private func wellnessImpactRow(_ impact: WatchMindfulnessImpact) -> some View {
        let dateStr = Self.impactDateFmt.string(from: impact.startDate)
        let emoji = impact.sessionType == "Reflect" ? "🤸" : "🧘"
        let label = impact.sessionType == "Reflect" ? "ストレッチ" : "瞑想"
        let hrDelta = Int(impact.heartRateDelta)
        let hrvDelta = impact.hrvDelta
        let hrColor: Color = hrDelta < 0 ? duoGreen : hrDelta > 0 ? Color(red: 1.0, green: 0.4, blue: 0.3) : .gray
        let hrvColor: Color = hrvDelta > 0 ? duoGreen : hrvDelta < 0 ? Color(red: 1.0, green: 0.4, blue: 0.3) : .gray
        let hrDeltaStr = hrDelta == 0 ? "±0" : (hrDelta > 0 ? "+\(hrDelta)" : "\(hrDelta)")
        let hrvDeltaStr: String = {
            if abs(hrvDelta) < 0.5 { return "±0" }
            return String(format: hrvDelta > 0 ? "+%.0f" : "%.0f", hrvDelta)
        }()
        let stressDelta = impact.stressDelta
        let stressDeltaStr = stressDelta == 0 ? "±0" : (stressDelta > 0 ? "+\(stressDelta)" : "\(stressDelta)")
        let stressColor: Color = stressDelta < 0 ? duoGreen : stressDelta > 0 ? Color(red: 1.0, green: 0.4, blue: 0.3) : .gray
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(emoji).font(.system(size: 11))
                Text(label)
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.white)
                Spacer()
                Text(dateStr)
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.5))
            }
            HStack(spacing: 10) {
                HStack(spacing: 2) {
                    Text("❤️").font(.system(size: 9))
                    Text("\(Int(impact.before.heartRate))→\(Int(impact.after.heartRate))")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                    Text(hrDeltaStr)
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(hrColor)
                }
                HStack(spacing: 2) {
                    Text("💓").font(.system(size: 9))
                    Text(String(format: "%.0f→%.0f", impact.before.hrv, impact.after.hrv))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                    Text(hrvDeltaStr)
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(hrvColor)
                }
            }
            HStack(spacing: 2) {
                Text("ストレス")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.white.opacity(0.58))
                Text("\(impact.stressBefore)→\(impact.stressAfter)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.88))
                Text(stressDeltaStr)
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(stressColor)
                Text(stressDelta < 0 ? "改善" : stressDelta > 0 ? "上昇" : "維持")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(stressColor)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.06))
        .cornerRadius(7)
    }

    private func formatMindfulMinutes(_ minutes: Double) -> String {
        if minutes < 1 {
            return "\(Int(minutes * 60))秒"
        }
        if abs(minutes.rounded() - minutes) < 0.05 {
            return "\(Int(minutes.rounded()))分"
        }
        return String(format: "%.1f分", minutes)
    }

    // MARK: - 1分Breatheセッションを開始
    private func openMindfulnessApp() {
        showBreatheFlow = true
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

                // ── ヘッダー：アクティビティリング ──────────────────────
                HStack(spacing: 12) {
                    ZStack {
                        WatchRingView(
                            progress: healthKit.activityMoveGoal > 0 ? healthKit.activityMoveCalories / healthKit.activityMoveGoal : 0,
                            color: Color(red: 0.98, green: 0.07, blue: 0.31),
                            diameter: 56, lineWidth: 6
                        )
                        WatchRingView(
                            progress: healthKit.activityExerciseGoal > 0 ? Double(healthKit.activityExerciseMinutes) / Double(healthKit.activityExerciseGoal) : 0,
                            color: Color(red: 0.57, green: 0.91, blue: 0.16),
                            diameter: 40, lineWidth: 6
                        )
                        WatchRingView(
                            progress: healthKit.activityStandGoal > 0 ? Double(healthKit.activityStandHours) / Double(healthKit.activityStandGoal) : 0,
                            color: Color(red: 0.12, green: 0.89, blue: 0.94),
                            diameter: 24, lineWidth: 6
                        )
                    }
                    .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 4) {
                        ringLegendRow(color: Color(red: 0.98, green: 0.07, blue: 0.31),
                                      value: "\(Int(healthKit.activityMoveCalories))/\(Int(healthKit.activityMoveGoal))", unit: "kcal")
                        ringLegendRow(color: Color(red: 0.57, green: 0.91, blue: 0.16),
                                      value: "\(healthKit.activityExerciseMinutes)/\(healthKit.activityExerciseGoal)", unit: "分")
                        ringLegendRow(color: Color(red: 0.12, green: 0.89, blue: 0.94),
                                      value: "\(healthKit.activityStandHours)/\(healthKit.activityStandGoal)", unit: "h")
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(Color.white.opacity(0.08))
                .cornerRadius(10)
                .padding(.bottom, 4)

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
                                    await refreshHealthData(scope: "health", force: true)
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
                                Task { await refreshHealthData(scope: "intake", force: true) }
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

    // MARK: - フィードページ（6ページ目）
    private var feedPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {
                // ── ヘッダー：タイトル + 同期ボタン ──────────────────────
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("📋 フィード")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        Text(connectivity.feedItems.isEmpty ? "同期ボタンで取得" : "\(connectivity.feedItems.count)件")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Button {
                        WKInterfaceDevice.current().play(.click)
                        connectivity.requestFeedFromiOS()
                    } label: {
                        HStack(spacing: 4) {
                            if connectivity.isSyncingFeed {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: duoGreen))
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(duoGreen)
                            }
                            Text("同期")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(duoGreen)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(duoGreen.opacity(0.15))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(connectivity.isSyncingFeed)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08))
                .cornerRadius(10)

                // ── フィード一覧 ──────────────────────
                if connectivity.isSyncingFeed && connectivity.feedItems.isEmpty {
                    VStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: duoGreen))
                            .scaleEffect(1.1)
                        Text("同期中...")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 20)
                } else if connectivity.feedItems.isEmpty {
                    VStack(spacing: 8) {
                        Text("📭")
                            .font(.system(size: 28))
                        Text("投稿がありません")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Text("iPhoneアプリで投稿してから\n「同期」してください")
                            .font(.system(size: 10))
                            .foregroundColor(.gray.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 20)
                } else {
                    ForEach(connectivity.feedItems) { item in
                        watchFeedItemRow(item)
                    }
                }

                Spacer(minLength: 16)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
    }

    // MARK: - ウォッチフェイスページ（5ページ目）
    private var watchFacePage: some View {
        // W1: キャッシュ済みノード位置・スパイラルメトリクスを参照（body 評価ごとに再構築しない）
        let dateStr = Self.watchFaceDateFmt.string(from: Date())
        let positions = cachedNodePositions
        let doneCount = positions.filter { $0.0.isDone }.count
        let totalCount = positions.count
        let trainingGoal = max(connectivity.totalTrainingGoal, 0)
        let mindfulnessGoal = max(connectivity.totalMindfulnessGoal, 0)
        let standGoal = connectivity.totalStandGoal
        let standDone = connectivity.totalStand
        let standColor = Color(red: 0.0, green: 0.60, blue: 0.85)
        let spiralScale = cachedSpiralMetrics

        return ZStack {
            // 渦巻きタスクレイアウト（中心=朝→外側=夜）
            ZStack {
                // 渦巻きガイドライン（Canvas でZStack中心を基準に描画）
                Canvas { ctx, size in
                    let cx = size.width / 2, cy = size.height / 2

                    // 背景スパイラルレール（淡い溝）
                    var rail = Path()
                    let steps = 120
                    let rStart: Double = 12
                    let rEnd = spiralScale.endRadius + 3
                    let θ0 = spiralScale.startAngle * .pi / 180.0
                    let totalAngle = spiralScale.totalAngle * .pi / 180.0
                    for i in 0...steps {
                        let t = Double(i) / Double(steps)
                        let r = rStart + (rEnd - rStart) * t
                        let θ = θ0 + totalAngle * t
                        let pt = CGPoint(x: cx + r * cos(θ), y: cy + r * sin(θ))
                        if i == 0 { rail.move(to: pt) } else { rail.addLine(to: pt) }
                    }
                    ctx.stroke(rail, with: .color(.white.opacity(0.10)),
                               style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 4]))

                    // ノード間カラーアーク（iOS Mandalaスタイルに統一）
                    for i in 0..<(positions.count - 1) {
                        let (node, deg0, r0) = positions[i]
                        let (_, deg1, r1) = positions[i + 1]
                        let a0 = deg0 * .pi / 180.0
                        let a1 = deg1 * .pi / 180.0
                        var arcPath = Path()
                        let arcSteps = 16
                        for step in 0...arcSteps {
                            let t = Double(step) / Double(arcSteps)
                            let a = a0 + (a1 - a0) * t
                            let r = r0 + (r1 - r0) * t
                            let pt = CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
                            if step == 0 { arcPath.move(to: pt) } else { arcPath.addLine(to: pt) }
                        }
                        // iOSと同じ不透明度設定: 完了 0.52、未完了 0.16
                        let opacity = node.isDone ? 0.52 : 0.16
                        ctx.stroke(arcPath, with: .color(node.accentColor.opacity(opacity)),
                                   style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    }
                }

                // タスクノード（内側=朝、外側=夜の渦巻き配置）
                ForEach(positions.indices, id: \.self) { i in
                    let (node, deg, r) = positions[i]
                    let rad = deg * .pi / 180.0
                    watchFaceNodeView(node)
                        .offset(x: r * CGFloat(cos(rad)), y: r * CGFloat(sin(rad)))
                }

                // 中央: 進捗リング + マスコット（タップでトレーニング開始）
                ZStack {
                    // 進捗トラック（背景リング）
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 4)
                        .frame(width: 54, height: 54)
                    // 進捗リング（緑）
                    Circle()
                        .trim(from: 0, to: CGFloat(doneCount) / CGFloat(max(totalCount, 1)))
                        .stroke(duoGreen, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 54, height: 54)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.6), value: doneCount)
                    // マスコットボタン
                    Button { showFlow = true } label: {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [duoGreen, Color(red: 0.2, green: 0.65, blue: 0.0)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 40, height: 40)
                            Image("mascot")
                                .resizable().scaledToFill()
                                .frame(width: 28, height: 28)
                                .clipShape(Circle())
                        }
                    }
                    .buttonStyle(.plain)
                    .modifier(HandGesturePrimaryActionModifier())
                }
                .overlay(alignment: .bottom) {
                    Text(totalCount > 0 ? "\(Int(Double(doneCount) / Double(totalCount) * 100))%" : "--")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.black.opacity(0.48))
                        .cornerRadius(4)
                        .offset(y: 11)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 四隅セクション
            VStack {
                HStack(alignment: .top) {
                    watchFaceCornerSection(
                        icon: "💪",
                        title: "TRAIN",
                        value: "\(connectivity.totalTraining)/\(trainingGoal)",
                        color: Color(red: 1.0, green: 0.588, blue: 0.0),
                        horizontalAlignment: .leading,
                        frameAlignment: .leading,
                        action: { showFlow = true }
                    )
                    Spacer()
                    watchFaceDateStreakSection(dateStr: dateStr) {
                        confirmIntake(type: "water", subtype: nil,
                                      message: "水\(connectivity.waterPerCup)mlを追加しますか？")
                    }
                }
                Spacer()
                HStack(alignment: .bottom) {
                    watchFaceCornerSection(
                        icon: "🧘",
                        title: "MIND",
                        value: "\(connectivity.totalMindfulness)/\(mindfulnessGoal)",
                        color: Color(red: 0.808, green: 0.51, blue: 1.0),
                        horizontalAlignment: .leading,
                        frameAlignment: .leading,
                        action: { openMindfulnessApp() }
                    )
                    Spacer()
                    watchFaceCornerSection(
                        icon: doneCount == totalCount && totalCount > 0 ? "🎉" : "✓",
                        title: "TODAY",
                        value: "\(doneCount)/\(totalCount)",
                        color: doneCount == totalCount && totalCount > 0 ? duoGreen : .white.opacity(0.72),
                        horizontalAlignment: .trailing,
                        frameAlignment: .trailing,
                        action: {
                            confirmIntake(type: "meal", subtype: "dinner",
                                          message: "夕食\(connectivity.dinnerCalories)kcalを追加しますか？")
                        }
                    )
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)

            VStack {
                Spacer()
                Button { refreshNow(scope: "watchFace") } label: {
                    Image(systemName: isManualRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(width: 22, height: 16)
                        .background(Color.black.opacity(0.18))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func watchFaceCornerSection(
        icon: String,
        title: String,
        value: String,
        color: Color,
        horizontalAlignment: HorizontalAlignment,
        frameAlignment: Alignment,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: horizontalAlignment, spacing: 1) {
                HStack(spacing: 2) {
                    Text(icon)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                    Text(title)
                        .font(.system(size: 7, weight: .black, design: .rounded))
                        .foregroundColor(.white.opacity(0.62))
                }
                Text(value)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(width: 62, alignment: frameAlignment)
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.28))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .cornerRadius(9)
        }
        .buttonStyle(.plain)
    }

    private func watchFaceDateStreakSection(dateStr: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(dateStr)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                HStack(spacing: 2) {
                    Text("🔥")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                    Text("\(connectivity.streak)")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .frame(width: 68, alignment: .trailing)
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.28))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .cornerRadius(9)
        }
        .buttonStyle(.plain)
    }

    // 渦巻き配置ノード（内側=朝r≈30 → 外側=夜r≈66）
    // 朝: 💪🍳💧  昼: 💪🍱💧  午後: 💪🍃🤸💧  夜: 💪🍽️💧🧘
    // W1: ノード位置の依存値を整数ハッシュにまとめ、変化時のみ再計算をトリガー
    // W3: 水分/食事は connectivity (iOS Firestore が正源) を参照
    private var nodePositionKey: Int {
        var h = connectivity.totalTraining
        h = h &* 31 &+ connectivity.totalMindfulness
        h = h &* 31 &+ connectivity.totalStand
        h = h &* 31 &+ connectivity.intakeWater
        h = h &* 31 &+ connectivity.intakeCalories
        h = h &* 31 &+ connectivity.totalDrinkGoal
        h = h &* 31 &+ connectivity.totalMealGoal
        h = h &* 31 &+ healthKit.todayMindfulnessSessions
        h = h &* 31 &+ healthKit.todayHKWorkoutCount
        h = h &* 31 &+ connectivity.watchFaceTasks.count
        return h
    }

    // W1: ノード位置をキャッシュ変数に再構築するメソッド（body 外で実行）
    private func rebuildNodePositions() {
        let trainColor   = Color(red: 1.0,  green: 0.588, blue: 0.0)
        let mindColor    = Color(red: 0.808, green: 0.51,  blue: 1.0)
        let waterColor   = Color(red: 0.27,  green: 0.67,  blue: 1.0)
        let mealColor    = Color(red: 0.345, green: 0.80,  blue: 0.008)
        let stretchColor = Color(red: 0.3,   green: 0.85,  blue: 0.75)
        let standColor   = Color(red: 0.0,   green: 0.60,  blue: 0.85)

        func color(for key: String) -> Color {
            switch key {
            case "training": return trainColor
            case "mind":     return mindColor
            case "water":    return waterColor
            case "meal":     return mealColor
            case "stretch":  return stretchColor
            case "stand":    return standColor
            default:         return .white.opacity(0.72)
            }
        }

        // Apple Health を正源とし、Firestoreの同期ラグを補完する
        let tDone = max(connectivity.totalTraining, healthKit.todayHKWorkoutCount)
        let hkMindfulSessions = healthKit.todayMindfulnessSessions
        let mDone = max(connectivity.totalMindfulness, hkMindfulSessions > 0 ? 1 : 0)
        // W3: 水分/食事は iOS Firestore 経由 (connectivity) を正源に
        let water = connectivity.intakeWater
        let cals  = connectivity.intakeCalories
        let dGoal = max(connectivity.totalDrinkGoal, 1)
        let mealG = max(connectivity.totalMealGoal, 1)

        let nodes: [(WatchFaceTaskNode, Double, Double)] = [
            // 朝（内側 r=32、上から時計回りへ）
            (WatchFaceTaskNode(id:"t0", emoji:"💪", accentColor:trainColor,
                isDone: tDone >= 1, actionType:"training"), -140, 32),
            (WatchFaceTaskNode(id:"bf", emoji:"🍳", accentColor:mealColor,
                isDone: cals >= mealG / 3, actionType:"meal", mealSubtype:"breakfast",
                intakeMessage:"朝食\(connectivity.breakfastCalories)kcalを追加しますか？"), -90, 32),
            (WatchFaceTaskNode(id:"w0", emoji:"💧", accentColor:waterColor,
                isDone: water >= dGoal / 4, actionType:"water",
                intakeMessage:"水\(connectivity.waterPerCup)mlを追加しますか？"), -40, 32),
            // 昼（中 r=50）
            (WatchFaceTaskNode(id:"t1", emoji:"💪", accentColor:trainColor,
                isDone: tDone >= 2, actionType:"training"), -15, 50),
            (WatchFaceTaskNode(id:"ln", emoji:"🍱", accentColor:mealColor,
                isDone: cals >= mealG * 2 / 3, actionType:"meal", mealSubtype:"lunch",
                intakeMessage:"昼食\(connectivity.lunchCalories)kcalを追加しますか？"), 20, 50),
            (WatchFaceTaskNode(id:"w1", emoji:"💧", accentColor:waterColor,
                isDone: water >= dGoal / 2, actionType:"water",
                intakeMessage:"水\(connectivity.waterPerCup)mlを追加しますか？"), 55, 50),
            // 午後（中外 r=64）
            (WatchFaceTaskNode(id:"t2", emoji:"💪", accentColor:trainColor,
                isDone: tDone >= 3, actionType:"training"), 82, 64),
            (WatchFaceTaskNode(id:"sn", emoji:"🍃", accentColor:mealColor,
                isDone: false, actionType:"meal", mealSubtype:"snack",
                intakeMessage:"間食を追加しますか？"), 110, 64),
            (WatchFaceTaskNode(id:"st", emoji:"🤸", accentColor:stretchColor,
                isDone: false, actionType:"stretch"), 138, 64),
            (WatchFaceTaskNode(id:"w2", emoji:"💧", accentColor:waterColor,
                isDone: water >= dGoal * 3 / 4, actionType:"water",
                intakeMessage:"水\(connectivity.waterPerCup)mlを追加しますか？"), 165, 64),
            // 夜（外側 r=80）
            (WatchFaceTaskNode(id:"t3", emoji:"💪", accentColor:trainColor,
                isDone: tDone >= 4, actionType:"training"), 192, 80),
            (WatchFaceTaskNode(id:"dn", emoji:"🍽️", accentColor:mealColor,
                isDone: cals >= mealG, actionType:"meal", mealSubtype:"dinner",
                intakeMessage:"夕食\(connectivity.dinnerCalories)kcalを追加しますか？"), 215, 80),
            (WatchFaceTaskNode(id:"w3", emoji:"💧", accentColor:waterColor,
                isDone: water >= dGoal, actionType:"water",
                intakeMessage:"水\(connectivity.waterPerCup)mlを追加しますか？"), 238, 80),
            (WatchFaceTaskNode(id:"md", emoji:"🧘", accentColor:mindColor,
                isDone: mDone >= 1, actionType:"mindfulness"), 262, 80),
            (WatchFaceTaskNode(id:"sd", emoji:"🧍", accentColor:standColor,
                isDone: connectivity.totalStand >= 1 && connectivity.totalStandGoal > 0,
                actionType:"stand"), 286, 80),
        ]
        cachedNodePositions = nodes
        cachedSpiralMetrics = watchFaceSpiralMetrics(for: nodes.count)
    }

    private func watchFaceSpiralMetrics(for count: Int) -> (startAngle: Double, totalAngle: Double, startRadius: Double, endRadius: Double) {
        // ノードサイズ38ptに合わせ、間隔を広げた渦巻き
        switch count {
        case 0...12:
            return (-140, 402, 32, 80)
        case 13...18:
            return (-150, 500, 28, 86)
        case 19...24:
            return (-160, 610, 24, 90)
        default:
            return (-170, 730, 22, 96)
        }
    }

    // タスクノードビュー（完了=塗りつぶし、未完了=輪郭+タップでアクション）
    private func watchFaceNodeView(_ node: WatchFaceTaskNode) -> some View {
        Button {
            switch node.actionType {
            case "training":  showFlow = true
            case "mindfulness": openMindfulnessApp()
            case "stretch": showStretchFlow = true
            case "stand": showStandFlow = true
            case "meal", "water":
                if !node.intakeMessage.isEmpty {
                    confirmIntake(type: node.actionType == "water" ? "water" : "meal",
                                  subtype: node.mealSubtype,
                                  message: node.intakeMessage)
                }
            default: break
            }
        } label: {
            Group {
                if node.isDone {
                    ZStack {
                        Circle().fill(node.accentColor)
                            .frame(width: 38, height: 38)
                        Text(node.emoji).font(.system(size: 22))
                    }
                } else {
                    ZStack {
                        Circle().fill(Color.black.opacity(0.40))
                            .frame(width: 38, height: 38)
                        Circle().stroke(node.accentColor.opacity(0.72), lineWidth: 1.5)
                            .frame(width: 38, height: 38)
                        Text(node.emoji).font(.system(size: 22))
                            .opacity(0.55)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func ringLegendRow(color: Color, value: String, unit: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(unit)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    @ViewBuilder
    private func watchFeedItemRow(_ item: WatchFeedItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(item.activityEmoji.isEmpty ? "📝" : item.activityEmoji)
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.activityName.isEmpty ? "活動記録" : item.activityName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(item.isOwn ? "自分" : item.authorName)
                            .font(.system(size: 10))
                            .foregroundColor(item.isOwn ? duoGreen : .orange)
                        Text("·")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                        Text(_feedTimeFmt.string(from: item.timestamp))
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
                if item.likeCount > 0 {
                    HStack(spacing: 2) {
                        Text("❤️")
                            .font(.system(size: 10))
                        Text("\(item.likeCount)")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                }
            }
            if !item.comment.isEmpty {
                Text(item.comment)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(2)
            }
            if let cal = item.calories, cal > 0 {
                Text("🔥 \(cal) kcal")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.06))
        .cornerRadius(10)
    }
}

// MARK: - フロービュー（WatchFlowViews.swift に定義済み）
// WatchBreatheFlowView, WatchStretchFlowView, WatchStandFlowView, BreathingBackground は
// ios/kfitWatch/Views/WatchFlowViews.swift に移動（kmind Watch との共有のため）

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

struct WatchRingView: View {
    let progress: Double
    let color: Color
    let diameter: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(CGFloat(progress), 1.0))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
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

// MARK: - Availability helpers

private struct HandGesturePrimaryActionModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(watchOS 11.0, *) {
            content.handGestureShortcut(.primaryAction)
        } else {
            content
        }
    }
}
