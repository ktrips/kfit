import SwiftUI
import UIKit
import Combine
import WatchConnectivity
import HealthKit

struct GoalingoView: View {
    @Binding var selectedTab: Int
    @Binding var showRecordMenu: Bool
    // V1: 共有シングルトンは kfitApp から EnvironmentObject で受け取る
    @EnvironmentObject private var healthKit: HealthKitManager
    @EnvironmentObject private var dietManager: DietGoalManager
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject private var timeSlotManager: TimeSlotManager
    @EnvironmentObject private var plus: PlusManager
    @StateObject private var raceManager = RaceGoalManager.shared
    @State private var showDietGoalSettings = false
    @State private var showRaceGoalSettings = false
    @State private var showCharts = false
    @State private var showActivityHistory = false
    @State private var showRaceWorkoutHistory = false
    @State private var expandedActivitySetIds: Set<Int> = []
    @State private var todayExercises: [CompletedExercise] = []
    @State private var todayWorkoutSessions: [WorkoutSession] = []
    @State private var weeklySetCounts: [String: Int] = [:]
    @State private var weeklyIntakeData: [String: [String: Int]] = [:]
    @State private var isRefreshingWatchData = false
    @State private var todayWeekdayGoal: WeekdayGoal? = nil
    @State private var dailyFixedGoals: DailyFixedGoals = DailyFixedGoals()
    // 体重ログ（写真）フィード・記録用
    @ObservedObject private var eduLog = EduLogManager.shared
    @State private var showWeightPhotoLog = false
    @State private var swipeWeightItems: [EduLogHistoryItem] = []
    @State private var swipeWeightStart: Int = 0
    @State private var showOlderWeightFeed = false

    // MARK: - Static formatters（毎呼び出しで DateFormatter を生成しないよう共有）
    private static let yyyyMMddFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let yyyyMdFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy/M/d"
        return f
    }()
    private static let HHmmFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let MdFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d"
        return f
    }()
    private static let dayOfWeekFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "E"
        return f
    }()

    @State private var showPlusViewFromFit = false
    @State private var watchActivitySent = false       // Watch 起動シグナル送信済み表示用

    // V25: トレーニング合計を @State にキャッシュ（body 評価ごとの再計算を防止）
    @State private var cachedTotalTrainingSets: Int = 0
    @State private var cachedTotalTrainingGoalSets: Int = 0

    private var totalTrainingSets: Int { cachedTotalTrainingSets }
    private var totalTrainingGoalSets: Int { cachedTotalTrainingGoalSets }

    private func rebuildTrainingTotals() {
        cachedTotalTrainingSets = TimeSlot.allCases.reduce(0) { $0 + countSetsInTimeSlot($1) }
        cachedTotalTrainingGoalSets = TimeSlot.allCases.reduce(0) { sum, slot in
            sum + (timeSlotManager.settings.goalFor(slot)?.trainingGoal ?? 0)
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.duoBg.ignoresSafeArea()
                if plus.isPlus {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 16) {
                            // 1. 大会までの１週間目標とその到達度
                            if raceManager.settings.isEnabled {
                                raceProgressCard
                                    .transition(.opacity)
                            }

                            // 2. Apple Watch アクティビティ起動ボタン
                            watchActivityButton

                            // 3. 今日のアクティビティ＋体重目標＋週間実績など
                            todayActivityWithHistoryCard

                            // 体重目標と到達度
                            goalHeroCard

                            // 体重グラフ（goalHeroCard 内のボタンで展開）
                            if showCharts {
                                weightChartCard
                                    .transition(.opacity)
                            }

                            if !raceManager.settings.isEnabled {
                                progressCard
                            }
                            weeklyBurnCard
                            weeklyActivityHistoryCard

                            weightFeedSection
                            Spacer(minLength: 40)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 20)
                    }
                    .refreshable {
                        loadTodayWeekdayGoal()
                        async let s0: Void = timeSlotManager.loadTodaySettings()
                        async let s1: Void = healthKit.fetchBodyMassHistory(days: 30)
                        async let s2: Void = healthKit.fetchGoalHealth()
                        async let s3: Void = healthKit.fetchWeeklyBurnData()
                        async let s4: Void = healthKit.fetchWeeklyDietarySamples()
                        async let s5: Void = healthKit.fetchWeeklyRaceWorkouts()
                        async let s6: Void = healthKit.fetchWeeklyWorkoutSessions()
                        async let ex   = authManager.getTodayExercises()
                        async let ws   = healthKit.fetchTodayWorkoutSessions()
                        async let wsc  = authManager.fetchWeeklySetCounts()
                        async let wid  = authManager.fetchWeeklyIntakeData()
                        let (exercises, sessions, setCounts, intakeData, _, _, _, _, _, _, _) =
                            await (ex, ws, wsc, wid, s0, s1, s2, s3, s4, s5, s6)
                        todayExercises       = exercises
                        todayWorkoutSessions = sessions
                        weeklySetCounts      = setCounts
                        weeklyIntakeData     = intakeData
                    }
                } else {
                    PlusFullLockView(
                        tabIcon: "flag.checkered",
                        tabName: "GOAL",
                        features: [
                            "大会までの週間目標と到達度",
                            "今日のアクティビティリング",
                            "体重目標と推移グラフ",
                            "週間実績（燃焼カロリー）",
                            "週間アクティビティ履歴",
                            "体重フォトログ"
                        ],
                        onUpgrade: { showPlusViewFromFit = true }
                    )
                }
            }
            .navigationBarHidden(true)
            .safeAreaInset(edge: .top, spacing: 0) { fitHeader }
            .sheet(isPresented: $showPlusViewFromFit) { PlusView() }
            .sheet(isPresented: $showRaceGoalSettings) {
                NavigationView { RaceGoalSettingsView() }
            }
            .sheet(isPresented: $showWeightPhotoLog) {
                EduPhotoLogSheet(
                    nodeEmoji: "⚖️",
                    nodeName: "体重ログ",
                    onComplete: { saveToFeed, isPublic, image, comment in
                        showWeightPhotoLog = false
                        // 完了判定は Health の体重計測のみ。ここでは FIT フィードへの投稿のみ。
                        if saveToFeed {
                            EduLogManager.shared.addItem(
                                activityName: "体重ログ",
                                activityEmoji: "⚖️",
                                comment: comment,
                                image: image,
                                isPublic: isPublic,
                                weightKg: healthKit.todayBodyMassRecord?.kg ?? (healthKit.latestBodyMass > 0 ? healthKit.latestBodyMass : nil),
                                bodyFatPercent: healthKit.latestBodyFatPercentage > 0 ? healthKit.latestBodyFatPercentage : nil
                            )
                        }
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: Binding(
                get: { !swipeWeightItems.isEmpty },
                set: { if !$0 { swipeWeightItems = [] } }
            )) {
                GoalingoSwipeableWeightFeedSheet(items: swipeWeightItems, startIndex: swipeWeightStart)
            }
            .task {
                // V25: 相互依存のない非同期タスクを async let で並列実行
                loadTodayWeekdayGoal()
                await timeSlotManager.loadTodaySettings()
                rebuildTrainingTotals()

                async let bodyMass:  Void = healthKit.fetchBodyMassHistory(days: 30)
                async let burnData:  Void = healthKit.fetchWeeklyBurnData()
                async let dietData:  Void = healthKit.fetchWeeklyDietarySamples()
                async let raceData:  Void = healthKit.fetchWeeklyRaceWorkouts()
                async let weekWo:    Void = healthKit.fetchWeeklyWorkoutSessions()
                async let exercises       = authManager.getTodayExercises()
                async let workouts        = healthKit.fetchTodayWorkoutSessions()
                async let setCountsData   = authManager.fetchWeeklySetCounts()
                async let intakeData      = authManager.fetchWeeklyIntakeData()

                if healthKit.weeklyCalorieData.isEmpty {
                    async let goalHealth: Void = healthKit.fetchGoalHealth()
                    _ = await (bodyMass, burnData, dietData, raceData, weekWo, goalHealth)
                } else {
                    _ = await (bodyMass, burnData, dietData, raceData, weekWo)
                }

                let (ex, wo, sc, id) = await (exercises, workouts, setCountsData, intakeData)
                todayExercises        = ex
                todayWorkoutSessions  = wo
                weeklySetCounts       = sc
                weeklyIntakeData      = id
                rebuildTrainingTotals()
            }
            .onChange(of: todayExercises.count) { _, _ in rebuildTrainingTotals() }
            // DailyTimeSlotSettings は Equatable 非準拠のため objectWillChange で監視
            .onReceive(timeSlotManager.objectWillChange) { _ in rebuildTrainingTotals() }
        }
    }

    // MARK: - Header

    private var fitHeader: some View {
        let raceDays = raceManager.settings.daysUntilRace
        let raceEnabled = raceManager.settings.isEnabled
        // 残り日数に応じてヘッダーの「あと◯日」の色を変える
        let raceDayColor: Color = raceDays <= 7
            ? Color(hex: "#FF4B4B")
            : raceDays <= 30 ? Color(hex: "#FFCC00") : .white

        return ZStack {
            LinearGradient(
                colors: [Color.duoGreen, Color(red: 0.18, green: 0.58, blue: 0.0)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea(edges: .top)
            HStack(spacing: 0) {
                Text("GOAL")
                    .font(.system(size: 8 * UIScale.font, weight: .black))
                    .foregroundColor(Color.duoGreen)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.white.opacity(0.9))
                    .cornerRadius(4)
                    .fixedSize()
                if todayWeekdayGoal?.exerciseEnabled == true {
                    Spacer(minLength: 6)
                    ZStack {
                        ActivityRingView(
                            progress: healthKit.activityMoveGoal > 0 ? healthKit.activityMoveCalories / healthKit.activityMoveGoal : 0,
                            color: Color(red: 0.98, green: 0.07, blue: 0.31), diameter: 26, lineWidth: 3.5)
                        ActivityRingView(
                            progress: healthKit.activityExerciseGoal > 0 ? Double(healthKit.activityExerciseMinutes) / Double(healthKit.activityExerciseGoal) : 0,
                            color: Color(red: 0.57, green: 0.91, blue: 0.16), diameter: 18, lineWidth: 3.5)
                        ActivityRingView(
                            progress: healthKit.activityStandGoal > 0 ? Double(healthKit.activityStandHours) / Double(healthKit.activityStandGoal) : 0,
                            color: Color(red: 0.12, green: 0.89, blue: 0.94), diameter: 10, lineWidth: 3.5)
                    }
                    .frame(width: 26, height: 26)
                    .fixedSize()
                }
                // 大会までの残り日数（レース目標が有効な場合のみ表示）
                if raceEnabled {
                    Spacer(minLength: 6)
                    HStack(spacing: 3) {
                        Text("🏁")
                            .font(.system(size: 13 * UIScale.font))
                        Text(raceDays > 0 ? "あと\(raceDays)日" : "本日！")
                            .font(.system(size: 12 * UIScale.font, weight: .black))
                            .foregroundColor(raceDayColor)
                            .lineLimit(1)
                    }
                    .fixedSize()
                }
                Spacer(minLength: 6)
                HStack(spacing: 2) {
                    Text("🔥").font(.system(size: 15 * UIScale.font))
                    Text(healthKit.activityMoveCalories > 0 ? "\(Int(healthKit.activityMoveCalories))" : "—")
                        .font(.system(size: 13 * UIScale.font, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if healthKit.activityMoveCalories > 0 {
                        Text("cal").font(.system(size: 10 * UIScale.font)).foregroundColor(.white.opacity(0.7))
                    }
                }
                .fixedSize()
                Spacer(minLength: 8)
                HeaderNavigationMenu(selectedTab: $selectedTab, showRecordMenu: $showRecordMenu)
                    .fixedSize()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(height: 50)
    }

    // MARK: - FITサマリー行

    private var fitSummaryRow: some View {
        let fitColor = Color(hex: "#FF9600")
        let todayWeightKg = healthKit.todayBodyMassRecord?.kg
        let stepsStr: String = {
            let s = healthKit.todaySteps
            guard s > 0 else { return "—" }
            return s >= 1000 ? String(format: "%.1fk", Double(s) / 1000.0) : "\(s)"
        }()
        return HStack(spacing: 6) {
            Text("GOAL")
                .font(.system(size: 8 * UIScale.font, weight: .black))
                .foregroundColor(.white)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(fitColor)
                .cornerRadius(4)
            if todayWeekdayGoal?.exerciseEnabled == true {
                ZStack {
                    ActivityRingView(
                        progress: healthKit.activityMoveGoal > 0 ? healthKit.activityMoveCalories / healthKit.activityMoveGoal : 0,
                        color: Color(red: 0.98, green: 0.07, blue: 0.31), diameter: 22, lineWidth: 3)
                    ActivityRingView(
                        progress: healthKit.activityExerciseGoal > 0 ? Double(healthKit.activityExerciseMinutes) / Double(healthKit.activityExerciseGoal) : 0,
                        color: Color(red: 0.57, green: 0.91, blue: 0.16), diameter: 15, lineWidth: 3)
                    ActivityRingView(
                        progress: healthKit.activityStandGoal > 0 ? Double(healthKit.activityStandHours) / Double(healthKit.activityStandGoal) : 0,
                        color: Color(red: 0.12, green: 0.89, blue: 0.94), diameter: 8, lineWidth: 3)
                }.frame(width: 22, height: 22)
            }
            if dailyFixedGoals.weightEnabled {
                HStack(spacing: 2) {
                    Text("⚖️").font(.system(size: 13 * UIScale.font))
                    Text(todayWeightKg != nil ? "\(Int(todayWeightKg!.rounded()))" : "—")
                        .font(.system(size: 9 * UIScale.font, weight: .bold))
                        .foregroundColor(todayWeightKg != nil ? fitColor : Color.duoDark)
                }
            }
            HStack(spacing: 2) {
                Text("👟").font(.system(size: 13 * UIScale.font))
                Text(stepsStr)
                    .font(.system(size: 9 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoDark)
            }
            HStack(spacing: 2) {
                Text("🔥").font(.system(size: 13 * UIScale.font))
                Text(healthKit.todayTotalCalories > 0 ? "\(Int(healthKit.todayTotalCalories))" : "—")
                    .font(.system(size: 9 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoDark)
                Text("cal").font(.system(size: 7 * UIScale.font)).foregroundColor(Color.duoSubtitle)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    // MARK: - FITヘッダー

    private var goalHeader: some View {
        let goal    = dietManager.settings
        let current = healthKit.latestBodyMass

        let weightChange = (goal.startWeight > 0 && current > 0) ? current - goal.startWeight : nil
        let remaining    = (goal.targetWeight > 0 && current > 0) ? current - goal.targetWeight : nil
        let cal = Calendar.current
        let daysLeft     = goal.hasStartStats
            ? max(0, cal.dateComponents([.day], from: Date(), to: goal.targetDate).day ?? 0)
            : nil
        let periodProgress: Int? = goal.hasStartStats ? {
            let total = cal.dateComponents([.day], from: goal.startDate, to: goal.targetDate).day ?? 0
            let elapsed = cal.dateComponents([.day], from: goal.startDate, to: Date()).day ?? 0
            guard total > 0 else { return nil }
            return min(100, max(0, Int(Double(elapsed) / Double(total) * 100)))
        }() : nil

        return ZStack {
            LinearGradient(
                colors: [Color.duoGreen, Color(red: 0.18, green: 0.58, blue: 0.0)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            HStack(spacing: 4) {
                // 左側: ロゴ
                HStack(spacing: 2) {
                    Image("mascot")
                        .resizable().scaledToFill()
                        .frame(width: 18, height: 18)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 0.4))
                    HStack(spacing: 0) {
                        Text("Goal")
                            .foregroundColor(Color(red: 1.0, green: 0.15, blue: 0.10))
                        Text("ingo")
                            .foregroundColor(.white)
                    }
                    .font(.system(size: 14 * UIScale.font, weight: .black, design: .rounded))
                }

                Spacer(minLength: 4)

                // 右側: 体重変化 / 残り削減分
                if goal.targetWeight > 0 && current > 0 {
                    HStack(spacing: 2) {
                        if let change = weightChange {
                            Text(String(format: "%+.1f", change))
                                .font(.system(size: 10 * UIScale.font, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        Text("/")
                            .font(.system(size: 9 * UIScale.font))
                            .foregroundColor(.white.opacity(0.6))
                        if let rem = remaining {
                            Text(String(format: "%.1fkg残", rem))
                                .font(.system(size: 10 * UIScale.font, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                    }
                }

                // 一番右: 残り日数 + 期間進捗
                if let days = daysLeft {
                    let daysColor: Color = days <= 7 ? Color(hex: "#FF4B4B") : days <= 30 ? Color(hex: "#FFCC00") : .white
                    HStack(spacing: 3) {
                        Text("あと\(days)日")
                            .font(.system(size: 10 * UIScale.font, weight: .black, design: .rounded))
                            .foregroundColor(daysColor)
                        if let pct = periodProgress {
                            Text("(\(pct)%)")
                                .font(.system(size: 9 * UIScale.font, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.75))
                        }
                    }
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .background(Color.white.opacity(0.18))
                    .cornerRadius(7)
                    .lineLimit(1)
                }

                HeaderNavigationMenu(selectedTab: $selectedTab, showRecordMenu: $showRecordMenu)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .cornerRadius(12)
    }

    // MARK: - 体重目標カード（シンプル）

    private var goalHeroCard: some View {
        let goal    = dietManager.settings
        let current = healthKit.latestBodyMass
        let cal     = Calendar.current

        // 体重進捗
        let weightProgress: Double = {
            guard goal.hasStartStats,
                  goal.startWeight > 0, goal.targetWeight > 0, current > 0 else { return 0 }
            let total = goal.startWeight - goal.targetWeight
            guard total != 0 else { return 1 }
            return min(1, max(0, (goal.startWeight - current) / total))
        }()

        // 期間進捗
        let totalDays  = goal.hasStartStats
            ? max(1, cal.dateComponents([.day], from: cal.startOfDay(for: goal.startDate),
                                        to: cal.startOfDay(for: goal.targetDate)).day ?? 1) : 0
        let elapsedDays = goal.hasStartStats
            ? max(0, cal.dateComponents([.day], from: cal.startOfDay(for: goal.startDate),
                                        to: cal.startOfDay(for: Date())).day ?? 0) : 0
        let timeProgress: Double  = totalDays > 0 ? min(1, Double(elapsedDays) / Double(totalDays)) : 0
        let daysRemaining = max(0, cal.dateComponents([.day], from: Date(), to: goal.targetDate).day ?? 0)

        let hasGoal = goal.targetWeight > 0

        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                if hasGoal {
                    // 体重ラベル行（スタート → 現在 → 目標）
                    HStack(spacing: 0) {
                        if goal.hasStartStats && goal.startWeight > 0 {
                            VStack(spacing: 1) {
                                Text(formatCompactKg(goal.startWeight))
                                    .font(.system(size: 12 * UIScale.font, weight: .bold))
                                    .foregroundColor(Color.duoSubtitle)
                                Text("スタート")
                                    .font(.system(size: 9 * UIScale.font))
                                    .foregroundColor(Color.duoSubtitle)
                            }
                            Spacer()
                        }
                        VStack(spacing: 1) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(current > 0 ? formatCompactKg(current) : "—")
                                    .font(.system(size: 15 * UIScale.font, weight: .black))
                                    .foregroundColor(Color.duoGreen)
                                if daysRemaining > 0 {
                                    Text("あと\(daysRemaining)日")
                                        .font(.system(size: 9 * UIScale.font, weight: .bold))
                                        .foregroundColor(daysRemaining <= 7 ? Color(hex: "#FF4B4B") : Color.duoSubtitle)
                                }
                            }
                            Text("現在")
                                .font(.system(size: 9 * UIScale.font))
                                .foregroundColor(Color.duoGreen.opacity(0.7))
                        }
                        Spacer()
                        VStack(spacing: 1) {
                            Text(formatCompactKg(goal.targetWeight))
                                .font(.system(size: 12 * UIScale.font, weight: .bold))
                                .foregroundColor(Color(hex: "#1CB0F6"))
                            Text("目標")
                                .font(.system(size: 9 * UIScale.font))
                                .foregroundColor(Color(hex: "#1CB0F6").opacity(0.7))
                        }
                    }

                    // 体重進捗バー
                    VStack(alignment: .leading, spacing: 3) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.duoSubtitle.opacity(0.15))
                                    .frame(height: 10)
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(LinearGradient(
                                        colors: [Color.duoGreen, Color(hex: "#1CB0F6")],
                                        startPoint: .leading, endPoint: .trailing))
                                    .frame(width: geo.size.width * CGFloat(weightProgress), height: 10)
                            }
                        }
                        .frame(height: 10)
                        HStack {
                            Text("体重 \(Int(weightProgress * 100))%")
                                .font(.system(size: 9 * UIScale.font))
                                .foregroundColor(Color.duoSubtitle)
                            Spacer()
                        }
                    }

                } else {
                    Text("目標体重を設定してください")
                        .font(.system(size: 12 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)
                }
            }
            .padding(14)

            // 体重グラフ展開ボタン
            Divider()
            Button {
                withAnimation(.easeInOut(duration: 0.3)) { showCharts.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 11 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color.duoGreen)
                    Text(showCharts ? "グラフを閉じる" : "体重グラフを表示")
                        .font(.system(size: 12 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoGreen)
                    Spacer()
                    Image(systemName: showCharts ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoGreen.opacity(0.7))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.07), radius: 6, y: 2)
    }

    private func refreshWatchData() {
        guard !isRefreshingWatchData else { return }
        isRefreshingWatchData = true
        Task {
            await healthKit.fetchGoalHealth(force: true)
            await healthKit.fetchBodyMassHistory(days: 30)
            await healthKit.fetchWeeklyBurnData()
            await healthKit.fetchWeeklyDietarySamples()
            await healthKit.fetchWeeklyRaceWorkouts()
            await healthKit.fetchWeeklyWorkoutSessions()
            let workouts = await healthKit.fetchTodayWorkoutSessions()
            await MainActor.run {
                todayWorkoutSessions = workouts
                isRefreshingWatchData = false
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        GoalingoView.yyyyMdFmt.string(from: date)
    }

    private func formatCompactKg(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))kg" : String(format: "%.1fkg", value)
    }

    private func formatCompactPercent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private func formatSignedDelta(_ value: Double) -> String {
        String(format: "%+.1f", value)
    }

    private func formatDistKm(_ km: Double) -> String {
        km == km.rounded() ? "\(Int(km))" : String(format: "%.4g", km)
    }

    private func loadTodayWeekdayGoal() {
        if let data = UserDefaults.standard.data(forKey: "dailyFixedGoals_v1"),
           let saved = try? JSONDecoder().decode(DailyFixedGoals.self, from: data) {
            dailyFixedGoals = saved
        }
        guard let data = UserDefaults.standard.data(forKey: "weekdayGoals_v1"),
              let goals = try? JSONDecoder().decode([WeekdayGoal].self, from: data) else {
            todayWeekdayGoal = nil
            return
        }
        let weekday = Calendar.current.component(.weekday, from: Date())
        let mapped = weekday == 1 ? 7 : weekday - 1
        todayWeekdayGoal = goals.first(where: { $0.weekday == mapped && $0.hasAnyGoal })
    }

    private func countSetsInTimeSlot(_ slot: TimeSlot) -> Int {
        let calendar = Calendar.current
        let slotExercises = todayExercises
            .filter { ex in
                let hour = calendar.component(.hour, from: ex.timestamp)
                return hour >= slot.startHour && hour < slot.endHour
            }
            .sorted { $0.timestamp < $1.timestamp }
        guard !slotExercises.isEmpty else { return 0 }
        var sessionCount = 0
        var lastTime: Date? = nil
        for ex in slotExercises {
            if let last = lastTime, ex.timestamp.timeIntervalSince(last) <= 30 * 60 {
                // same session
            } else {
                sessionCount += 1
            }
            lastTime = ex.timestamp
        }
        return sessionCount
    }

    private func metricColumn(label: String, weightVal: String, fatVal: String?, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundColor(Color.duoSubtitle)
            Text(weightVal)
                .font(.system(size: 36 * UIScale.font, weight: .black))
                .foregroundColor(color)
            Text("kg")
                .font(.caption)
                .foregroundColor(Color.duoSubtitle)
                .offset(y: -6)
            if let fat = fatVal {
                Text(fat + "%")
                    .font(.system(size: 14 * UIScale.font, weight: .bold))
                    .foregroundColor(color.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func daysRemainingBadge(goal: DietGoalSettings) -> some View {
        let days = max(0, Calendar.current.dateComponents([.day], from: Date(), to: goal.targetDate).day ?? 0)
        let color: Color = days > 30 ? Color(hex: "#1CB0F6") : days > 7 ? Color(hex: "#FF9600") : Color(hex: "#FF4B4B")
        return VStack(spacing: 1) {
            Text("\(days)")
                .font(.system(size: 17 * UIScale.font, weight: .black))
                .foregroundColor(color)
            Text("日後")
                .font(.system(size: 9 * UIScale.font, weight: .bold))
                .foregroundColor(color.opacity(0.8))
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(color.opacity(0.1))
        .cornerRadius(9)
    }

    private struct GoalActivityHistorySet: Identifiable {
        let id: Int
        let setNumber: Int
        let startTime: Date
        let exercises: [CompletedExercise]

        var totalReps: Int { exercises.reduce(0) { $0 + $1.reps } }
        var totalPoints: Int { exercises.reduce(0) { $0 + $1.points } }
    }

    private var activityHistoryExpandable: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    showActivityHistory.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 15 * UIScale.font, weight: .black))
                        .foregroundColor(Color.duoGreen)
                    Text(showActivityHistory ? "今日のアクティビティを閉じる" : "今日のアクティビティを表示")
                        .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor(Color.duoGreen)
                    Spacer()
                    Image(systemName: showActivityHistory ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14 * UIScale.font, weight: .black))
                        .foregroundColor(Color.duoGreen)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
            }
            .buttonStyle(.plain)

            if showActivityHistory {
                activityHistoryContent
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var activityHistoryContent: some View {
        let sets = buildActivityHistorySets(todayExercises)
        let workouts = standaloneWorkoutSessions(todayWorkoutSessions, excludingSets: sets)
        if sets.isEmpty && workouts.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundColor(Color.duoSubtitle)
                Text("今日のワークアウト記録はまだありません")
                    .font(.system(size: 12 * UIScale.font, weight: .semibold))
                    .foregroundColor(Color.duoSubtitle)
                Spacer()
            }
            .padding(12)
            .background(Color.duoBg)
            .cornerRadius(12)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if !sets.isEmpty {
                    historySubheader(
                        "Fitingoセット",
                        summary: "\(sets.count)セット  \(sets.reduce(0) { $0 + $1.totalReps }) rep"
                    )
                    ForEach(sets) { set in
                        activityHistorySetCard(set)
                    }
                }

                if !workouts.isEmpty {
                    historySubheader(
                        "通常ワークアウト",
                        summary: "\(Int(workouts.reduce(0) { $0 + $1.durationMinutes }.rounded()))分  \(Int(workouts.reduce(0) { $0 + $1.calories }.rounded())) kcal"
                    )
                    ForEach(workouts) { workout in
                        activityHistoryWorkoutRow(workout)
                    }
                }
            }
        }
    }

    private func historySubheader(_ title: String, summary: String? = nil) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10 * UIScale.font, weight: .black))
                .foregroundColor(Color.duoSubtitle)
            Spacer()
            if let summary {
                Text(summary)
                    .font(.system(size: 10 * UIScale.font, weight: .black, design: .rounded))
                    .foregroundColor(Color.duoGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.duoGreen.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
    }

    private func activityHistorySetCard(_ set: GoalActivityHistorySet) -> some View {
        let isExpanded = expandedActivitySetIds.contains(set.id)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isExpanded {
                        expandedActivitySetIds.remove(set.id)
                    } else {
                        expandedActivitySetIds.insert(set.id)
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Text(timeString(set.startTime))
                        .font(.system(size: 10 * UIScale.font, weight: .bold, design: .rounded))
                        .foregroundColor(Color.duoSubtitle)
                        .frame(width: 38, alignment: .leading)
                    Text("セット\(set.setNumber)")
                        .font(.system(size: 11 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor(Color.duoGreen)
                    Spacer()
                    Text("\(set.totalReps) rep")
                        .font(.system(size: 10 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor(Color.duoDark)
                    Text("+\(set.totalPoints) XP")
                        .font(.system(size: 10 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor(Color.duoGold)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoSubtitle)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 4) {
                    ForEach(Array(set.exercises.enumerated()), id: \.offset) { _, exercise in
                        activityHistoryExerciseRow(exercise)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.duoGreen.opacity(0.07))
        .cornerRadius(10)
    }

    private func activityHistoryWorkoutRow(_ workout: WorkoutSession) -> some View {
        HStack(spacing: 7) {
            Text(workout.emoji)
                .font(.system(size: 15 * UIScale.font))
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.activityName)
                    .font(.system(size: 11 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoDark)
                Text("\(timeString(workout.startDate))-\(timeString(workout.endDate)) ・ \(workout.sourceName)")
                    .font(.system(size: 8 * UIScale.font, weight: .semibold))
                    .foregroundColor(Color.duoSubtitle)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(workout.durationMinutes))分")
                    .font(.system(size: 11 * UIScale.font, weight: .black, design: .rounded))
                    .foregroundColor(Color.duoGreen)
                if workout.calories > 0 {
                    Text("\(Int(workout.calories)) kcal")
                        .font(.system(size: 8 * UIScale.font, weight: .bold, design: .rounded))
                        .foregroundColor(Color.duoOrange)
                }
            }
        }
        .padding(8)
        .background(Color.duoBlue.opacity(0.07))
        .cornerRadius(10)
    }

    private func activityHistoryExerciseRow(_ exercise: CompletedExercise) -> some View {
        HStack(spacing: 8) {
            Text(goalExerciseEmoji(id: exercise.exerciseId, name: exercise.exerciseName))
                .font(.system(size: 14 * UIScale.font))
            VStack(alignment: .leading, spacing: 1) {
                Text(exercise.exerciseName)
                    .font(.system(size: 11 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoDark)
                Text(timeString(exercise.timestamp))
                    .font(.system(size: 8 * UIScale.font, weight: .semibold))
                    .foregroundColor(Color.duoSubtitle)
            }
            Spacer()
            Text("\(exercise.reps)回")
                .font(.system(size: 11 * UIScale.font, weight: .black, design: .rounded))
                .foregroundColor(Color.duoGreen)
            if exercise.formScore > 0 {
                Text("\(Int(exercise.formScore))%")
                    .font(.system(size: 9 * UIScale.font, weight: .bold, design: .rounded))
                    .foregroundColor(Color.duoBlue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.duoBlue.opacity(0.12))
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.75))
        .cornerRadius(9)
    }

    private func buildActivityHistorySets(_ exercises: [CompletedExercise]) -> [GoalActivityHistorySet] {
        let sorted = exercises.sorted { $0.timestamp < $1.timestamp }
        var sessions: [[CompletedExercise]] = []
        var currentSession: [CompletedExercise] = []
        var lastTime: Date?

        for exercise in sorted {
            if let lastTime, exercise.timestamp.timeIntervalSince(lastTime) <= 30 * 60 {
                currentSession.append(exercise)
            } else {
                if !currentSession.isEmpty {
                    sessions.append(currentSession)
                }
                currentSession = [exercise]
            }
            lastTime = exercise.timestamp
        }

        if !currentSession.isEmpty {
            sessions.append(currentSession)
        }

        let nonZeroSessions = sessions.filter { session in
            session.contains { $0.reps > 0 || $0.points > 0 }
        }

        return nonZeroSessions.enumerated().map { index, session in
            GoalActivityHistorySet(
                id: index,
                setNumber: index + 1,
                startTime: session.first?.timestamp ?? Date(),
                exercises: session
            )
        }
    }

    private func timeString(_ date: Date) -> String {
        GoalingoView.HHmmFmt.string(from: date)
    }

    private func standaloneWorkoutSessions(
        _ workouts: [WorkoutSession],
        excludingSets sets: [GoalActivityHistorySet]
    ) -> [WorkoutSession] {
        workouts.filter { workout in
            let source = "\(workout.sourceName) \(workout.sourceBundleId)".lowercased()
            let isFromKfit = source.contains("kfit")
                || source.contains("fitingo")
                || source.contains("duofit")
                || source.contains("kfitappduo")
            let isEmptyKfitWorkout = isFromKfit && workout.durationMinutes < 1
            if isEmptyKfitWorkout {
                return false
            }
            let isOverlappingSet = sets.contains { set in
                guard let first = set.exercises.first?.timestamp,
                      let last = set.exercises.last?.timestamp else {
                    return false
                }
                let setStart = first.addingTimeInterval(-60)
                let setEnd = last.addingTimeInterval(60)
                return workout.startDate <= setEnd && workout.endDate >= setStart
                    && workout.activityName == "筋トレ"
            }
            return !isOverlappingSet
        }
    }

    private func goalExerciseEmoji(id: String, name: String) -> String {
        let key = "\(id) \(name)".lowercased()
        if key.contains("push") || key.contains("腕立") { return "💪" }
        if key.contains("squat") || key.contains("スクワット") { return "🏋️" }
        if key.contains("sit") || key.contains("腹筋") { return "🔥" }
        if key.contains("plank") || key.contains("プランク") { return "🧘" }
        if key.contains("lunge") || key.contains("ランジ") { return "🦵" }
        if key.contains("burpee") || key.contains("バーピー") { return "⚡" }
        return "🏃"
    }

    // MARK: - 今日のアクティビティカード

    // MARK: - Apple Watch アクティビティ起動ボタン

    private var watchActivityButton: some View {
        let session   = WCSession.isSupported() ? WCSession.default : nil
        let isPaired  = session?.isPaired     == true
        let isInstall = session?.isWatchAppInstalled == true
        let isReach   = session?.isReachable  == true
        let available = isPaired && isInstall

        return Button {
            guard available else { return }
            // WCSession 経由で kfitWatch のワークアウトフローを起動
            iOSWatchBridge.shared.sendStartWorkoutSignal()
            // HKHealthStore.startWatchApp でウォッチアプリをフォアグラウンドに
            let config = HKWorkoutConfiguration()
            config.activityType = .traditionalStrengthTraining
            config.locationType = .indoor
            HKHealthStore().startWatchApp(with: config) { _, _ in }
            // 送信完了フィードバックを 2 秒表示
            watchActivitySent = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                watchActivitySent = false
            }
        } label: {
            HStack(spacing: 12) {
                // Watch アイコン
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(available
                              ? Color(hex: "#1CB0F6").opacity(0.15)
                              : Color(.systemGray5))
                        .frame(width: 44, height: 44)
                    Image(systemName: "applewatch")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(available ? Color(hex: "#1CB0F6") : Color.gray)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Watch ワークアウト")
                        .font(.system(size: 14 * UIScale.font, weight: .bold))
                        .foregroundColor(available ? Color.duoDark : Color.gray)
                    Text(watchActivitySent
                         ? "✓ Watch に送信しました"
                         : isReach
                             ? "タップで Watch トレーニングを開始"
                             : available
                                 ? "Watch が非アクティブです"
                                 : "Apple Watch が連携されていません")
                        .font(.system(size: 11 * UIScale.font))
                        .foregroundColor(watchActivitySent
                                         ? Color(hex: "#58CC02")
                                         : Color.duoSubtitle)
                }

                Spacer()

                // 接続状態インジケーター
                Circle()
                    .fill(isReach
                          ? Color(hex: "#58CC02")
                          : available
                              ? Color.orange
                              : Color.gray)
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        available ? Color(hex: "#1CB0F6").opacity(0.35) : Color(.systemGray4),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .disabled(!available)
    }

    private var todayActivityWithHistoryCard: some View {
        VStack(spacing: 0) {
            todayActivityCard
            Divider()
                .padding(.horizontal, 18)
            activityHistoryExpandable
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    private var todayActivityCard: some View {
        let allRingsDone = healthKit.activityMoveCalories >= healthKit.activityMoveGoal
            && healthKit.activityExerciseMinutes >= healthKit.activityExerciseGoal
            && healthKit.activityStandHours >= healthKit.activityStandGoal
        let isGoal = todayWeekdayGoal?.exerciseEnabled == true

        let moveProgress = healthKit.activityMoveGoal > 0 ? min(healthKit.activityMoveCalories / healthKit.activityMoveGoal, 1.0) : 0
        let exerciseProgress = healthKit.activityExerciseGoal > 0 ? min(Double(healthKit.activityExerciseMinutes) / Double(healthKit.activityExerciseGoal), 1.0) : 0
        let standProgress = healthKit.activityStandGoal > 0 ? min(Double(healthKit.activityStandHours) / Double(healthKit.activityStandGoal), 1.0) : 0
        let activeCount = (healthKit.activityMoveGoal > 0 ? 1 : 0)
            + (healthKit.activityExerciseGoal > 0 ? 1 : 0)
            + (healthKit.activityStandGoal > 0 ? 1 : 0)
        let activityScore = activeCount > 0 ? Int((moveProgress + exerciseProgress + standProgress) / Double(activeCount) * 100) : 0

        let nowComponents = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let nowDecimal = Double(nowComponents.hour ?? 0) + Double(nowComponents.minute ?? 0) / 60.0
        let expectedPace = nowDecimal <= 6 ? 0 : nowDecimal >= 24 ? 1 : (nowDecimal - 6) / 18.0
        let paceDiff = activityScore - Int(expectedPace * 100)
        let (paceLabel, paceColor): (String, Color) = {
            if nowDecimal < 6 { return ("開始前", Color.duoSubtitle) }
            if activityScore >= 100 { return ("達成！", Color.duoGreen) }
            if paceDiff >= 0 { return ("順調", Color.duoGreen) }
            if paceDiff >= -15 { return ("やや遅れ", Color(hex: "#FF9600")) }
            return ("遅れ気味", Color(hex: "#FF4B4B"))
        }()

        return Button {
            let schemes = ["x-apple-fitness://", "x-apple-health://"]
            for scheme in schemes {
                if let url = URL(string: scheme), UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                    return
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "figure.walk.circle.fill")
                        .foregroundColor(Color(red: 0.98, green: 0.07, blue: 0.31))
                        .font(.system(size: 14 * UIScale.font))
                    Text("今日のアクティビティ")
                        .font(.system(size: 13 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoDark)
                    if isGoal && allRingsDone {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11 * UIScale.font))
                            .foregroundColor(Color.duoGreen)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        HStack(spacing: 2) {
                            Text("\(activityScore)")
                                .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                                .foregroundColor(paceColor)
                            Text("%")
                                .font(.system(size: 8 * UIScale.font, weight: .bold))
                                .foregroundColor(paceColor)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        Text(paceLabel)
                            .font(.system(size: 11 * UIScale.font, weight: .bold))
                            .foregroundColor(paceColor)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(paceColor.opacity(0.15))
                            .cornerRadius(10)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color.duoSubtitle)
                }

                HStack(spacing: 16) {
                    ZStack {
                        ActivityRingView(
                            progress: healthKit.activityMoveGoal > 0 ? healthKit.activityMoveCalories / healthKit.activityMoveGoal : 0,
                            color: Color(red: 0.98, green: 0.07, blue: 0.31),
                            diameter: 90,
                            lineWidth: 10
                        )
                        ActivityRingView(
                            progress: healthKit.activityExerciseGoal > 0 ? Double(healthKit.activityExerciseMinutes) / Double(healthKit.activityExerciseGoal) : 0,
                            color: Color(red: 0.57, green: 0.91, blue: 0.16),
                            diameter: 66,
                            lineWidth: 10
                        )
                        ActivityRingView(
                            progress: healthKit.activityStandGoal > 0 ? Double(healthKit.activityStandHours) / Double(healthKit.activityStandGoal) : 0,
                            color: Color(red: 0.12, green: 0.89, blue: 0.94),
                            diameter: 42,
                            lineWidth: 10
                        )
                    }
                    .frame(width: 90, height: 90)

                    VStack(alignment: .leading, spacing: 8) {
                        goalActivityRingLegend(color: Color(red: 0.98, green: 0.07, blue: 0.31), label: "ムーブ", value: "\(Int(healthKit.activityMoveCalories))", goal: "\(Int(healthKit.activityMoveGoal)) kcal")
                        goalActivityRingLegend(color: Color(red: 0.57, green: 0.91, blue: 0.16), label: "エクササイズ", value: "\(healthKit.activityExerciseMinutes)", goal: "\(healthKit.activityExerciseGoal) 分")
                        goalActivityRingLegend(color: Color(red: 0.12, green: 0.89, blue: 0.94), label: "スタンド", value: "\(healthKit.activityStandHours)", goal: "\(healthKit.activityStandGoal) 時間")
                    }

                    Spacer()

                    if healthKit.latestBodyMass > 0 || healthKit.latestBodyFatPercentage > 0 {
                        VStack(alignment: .trailing, spacing: 8) {
                            if healthKit.latestBodyMass > 0 {
                                VStack(alignment: .trailing, spacing: 2) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "scalemass.fill")
                                            .font(.system(size: 8 * UIScale.font))
                                            .foregroundColor(Color(hex: "#1CB0F6"))
                                        Text("体重")
                                            .font(.system(size: 8 * UIScale.font, weight: .semibold))
                                            .foregroundColor(Color.duoSubtitle)
                                    }
                                    Text(String(format: "%.1f kg", healthKit.latestBodyMass))
                                        .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                                        .foregroundColor(Color.duoDark)
                                    if let change = healthKit.weeklyBodyMassChange {
                                        let sign = change >= 0 ? "+" : ""
                                        Text(String(format: "%@%.1f kg/7日", sign, change))
                                            .font(.system(size: 8 * UIScale.font, weight: .semibold))
                                            .foregroundColor(change > 0.05 ? Color(hex: "#FF4B4B") : change < -0.05 ? Color.duoGreen : Color.duoSubtitle)
                                    }
                                }
                            }
                            if healthKit.latestBodyFatPercentage > 0 {
                                VStack(alignment: .trailing, spacing: 1) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "percent")
                                            .font(.system(size: 8 * UIScale.font))
                                            .foregroundColor(Color(hex: "#CE82FF"))
                                        Text("体脂肪")
                                            .font(.system(size: 8 * UIScale.font, weight: .semibold))
                                            .foregroundColor(Color.duoSubtitle)
                                    }
                                    Text(String(format: "%.1f%%", healthKit.latestBodyFatPercentage))
                                        .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                                        .foregroundColor(Color.duoDark)
                                    if let change = healthKit.weeklyBodyFatChange {
                                        let sign = change >= 0 ? "+" : ""
                                        Text(String(format: "%@%.1f%%/7日", sign, change))
                                            .font(.system(size: 8 * UIScale.font, weight: .semibold))
                                            .foregroundColor(change > 0.05 ? Color(hex: "#FF4B4B") : change < -0.05 ? Color.duoGreen : Color.duoSubtitle)
                                    }
                                }
                            }
                        }
                    }
                }

                goalStepsProgressBar
                goalBurnedCaloriesBar

                GoalCalorieBalanceBarCard(
                    totalConsumed: healthKit.todayTotalCalories,
                    intake: healthKit.todayIntakeCalories
                )
            }
            .padding(12)
        }
        .buttonStyle(.plain)
    }

    private func goalActivityRingLegend(color: Color, label: String, value: String, goal: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9 * UIScale.font, weight: .semibold))
                    .foregroundColor(Color.duoSubtitle)
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor(Color.duoDark)
                    Text("/ \(goal)")
                        .font(.system(size: 9 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)
                }
            }
        }
    }

    private func goalHealthMetricTile(icon: String, value: String, unit: String, bg: Color, healthCategory: String) -> some View {
        Button {
            if let url = URL(string: "x-apple-health://\(healthCategory)") {
                UIApplication.shared.open(url)
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(Color.duoDark)
                Text(value)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.black)
                    .foregroundColor(Color.duoDark)
                Text(unit)
                    .font(.system(size: 9 * UIScale.font))
                    .fontWeight(.bold)
                    .foregroundColor(Color.duoSubtitle)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(bg)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private var goalStepsProgressBar: some View {
        let goal = 10000.0
        let steps = Double(healthKit.todaySteps)
        let progress = min(1.0, steps / goal)
        return Button {
            if let url = URL(string: "x-apple-health://StepCount") {
                UIApplication.shared.open(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 11 * UIScale.font, weight: .bold))
                        .foregroundColor(Color(hex: "#1CB0F6"))
                    Text("今日の歩数")
                        .font(.system(size: 11 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoDark)
                    Spacer()
                    Text("\(healthKit.todaySteps.formatted()) / \(Int(goal).formatted())歩")
                        .font(.system(size: 10 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor(progress >= 1 ? Color(hex: "#1CB0F6") : Color.duoDark)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.systemGray5))
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color(hex: "#1CB0F6"), Color(hex: "#84D8FF")],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: max(8, geo.size.width * CGFloat(progress)))
                    }
                }
                .frame(height: 10)
            }
            .padding(10)
            .background(Color(hex: "#E5F6FF"))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private var goalBurnedCaloriesBar: some View {
        let resting = healthKit.todayRestingCalories
        let active = healthKit.todayActiveCalories
        let total = max(resting + active, 1)
        return Button {
            if let url = URL(string: "x-apple-health://ActiveEnergyBurned") {
                UIApplication.shared.open(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoGreen)
                    Text("今日の消費カロリー")
                        .font(.system(size: 11 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoDark)
                    Spacer()
                    Text("\(Int(resting + active)) kcal")
                        .font(.system(size: 10 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor(Color.duoDark)
                }

                GeometryReader { geo in
                    let restingWidth = geo.size.width * CGFloat(resting / total)
                    let activeWidth = geo.size.width * CGFloat(active / total)
                    HStack(spacing: 0) {
                        ZStack {
                            Rectangle().fill(Color.duoGreen.opacity(0.72))
                            Text("\(Int(resting)) 安静")
                                .font(.system(size: 10 * UIScale.font, weight: .black))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .frame(width: max(44, restingWidth), height: 28)

                        ZStack {
                            Rectangle().fill(Color(red: 0.18, green: 0.72, blue: 0.18))
                            Text("\(Int(active)) 活動")
                                .font(.system(size: 10 * UIScale.font, weight: .black))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .frame(width: max(44, activeWidth), height: 28)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(height: 28)
            }
            .padding(10)
            .background(Color(red: 0.90, green: 1.0, blue: 0.86))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 進捗カード

    private var progressCard: some View {
        let goal    = dietManager.settings
        let deficit = goal.dailyDeficitGoal
        let days    = max(1, Calendar.current.dateComponents([.day], from: Date(), to: goal.targetDate).day ?? 1)
        let deficitColor: Color = deficit < 0 ? Color.duoGreen : Color(hex: "#FF4B4B")
        let weeklyChange     = Double(deficit * 7)  / 7700.0
        let monthlyChange    = Double(deficit * 30) / 7700.0
        let threeMonthChange = Double(deficit * 90) / 7700.0
        let goalDateChange   = Double(deficit * days) / 7700.0

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("📋").font(.system(size: 12 * UIScale.font))
                Text("目標プラン")
                    .font(.system(size: 12 * UIScale.font, weight: .black))
                    .foregroundColor(Color.duoDark)
            }

            HStack(spacing: 0) {
                planItem(icon: "🔥", label: "1日収支",
                         value: (deficit >= 0 ? "+" : "") + "\(deficit)",
                         unit: "kcal", color: deficitColor)
                Divider().frame(height: 36)
                planItem(icon: "📅", label: "残り日数",
                         value: "\(days)", unit: "日",
                         color: Color(hex: "#1CB0F6"))
                Divider().frame(height: 36)
                planItem(icon: "⚖️", label: "週変化",
                         value: String(format: "%.2f", weeklyChange),
                         unit: "kg/週", color: deficitColor)
                Divider().frame(height: 36)
                planItem(icon: "📆", label: "月変化",
                         value: String(format: "%.1f", monthlyChange),
                         unit: "kg/月", color: deficitColor)
                Divider().frame(height: 36)
                planItem(icon: "🎯", label: "目標日",
                         value: String(format: "%.1f", goalDateChange),
                         unit: "kg", color: deficitColor)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    private func planItem(icon: String, label: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(icon).font(.system(size: 11 * UIScale.font))
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 13 * UIScale.font, weight: .black))
                    .foregroundColor(color)
                Text(unit)
                    .font(.system(size: 7 * UIScale.font))
                    .foregroundColor(Color.duoSubtitle)
            }
            Text(label)
                .font(.system(size: 8 * UIScale.font))
                .foregroundColor(Color.duoSubtitle)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 大会プランカード

    private var racePlanCard: some View {
        let settings = raceManager.settings
        let days = settings.daysUntilRace
        let weeks = settings.weeksUntilRace
        let weeklyGoal = settings.weeklyTrainingGoal()
        let daysColor: Color = days <= 7 ? Color(hex: "#FF4B4B") : days <= 30 ? Color(hex: "#FFCC00") : Color(hex: "#1CB0F6")

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("📋").font(.system(size: 12 * UIScale.font))
                Text("大会プラン")
                    .font(.system(size: 12 * UIScale.font, weight: .black))
                    .foregroundColor(Color.duoDark)
            }

            HStack(spacing: 0) {
                planItem(icon: "📅", label: "大会まで",
                         value: "\(days)日（\(weeks)週）", unit: "", color: daysColor)
                if weeklyGoal.swimKm > 0 {
                    Divider().frame(height: 36)
                    planItem(icon: "🏊", label: "週スイム",
                             value: String(format: "%.1f", weeklyGoal.swimKm),
                             unit: "km", color: Color(hex: "#1CB0F6"))
                }
                if weeklyGoal.bikeKm > 0 {
                    Divider().frame(height: 36)
                    planItem(icon: "🚴", label: "週バイク",
                             value: String(format: "%.0f", weeklyGoal.bikeKm),
                             unit: "km", color: Color(hex: "#FF9600"))
                }
                if weeklyGoal.runKm > 0 {
                    Divider().frame(height: 36)
                    planItem(icon: "🏃", label: "週ラン/ウォーク",
                             value: String(format: "%.1f", weeklyGoal.runKm),
                             unit: "km", color: Color.duoGreen)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - 週間消費カロリーカード

    private var weeklyBurnCard: some View {
        var data = healthKit.weeklyBurnData
        for i in data.indices {
            let key = GoalingoView.yyyyMMddFmt.string(from: data[i].date)
            data[i].setCount = weeklySetCounts[key] ?? 0
        }
        // 日別摂取カロリー
        var samplesByKey: [String: [DietarySample]] = [:]
        for sample in healthKit.weeklyDietarySamples {
            let key = GoalingoView.yyyyMMddFmt.string(from: sample.startDate)
            samplesByKey[key, default: []].append(sample)
        }
        let intakePerDay: [Double] = data.map { day in
            let key = GoalingoView.yyyyMMddFmt.string(from: day.date)
            return (samplesByKey[key] ?? []).reduce(0.0) { $0 + $1.value }
        }
        // 日別体重（月曜起算 7日分）
        let cal = Calendar(identifier: .gregorian)
        let weekStart = cal.mondayStart(for: Date())
        let weightPerDay: [Double?] = (0..<7).map { i in
            guard let dayStart = cal.date(byAdding: .day, value: i, to: cal.startOfDay(for: weekStart)),
                  let dayEnd   = cal.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
            return healthKit.bodyMassHistory
                .filter { $0.measuredAt >= dayStart && $0.measuredAt < dayEnd }
                .last?.kg
        }
        return GoalWeeklyBurnCard(data: data, intakePerDay: intakePerDay, weightPerDay: weightPerDay)
    }

    // MARK: - 週間アクティビティ履歴カード（週間カロリーの下）

    private var weeklyActivityHistoryCard: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    showActivityHistory.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 13 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color.duoGreen)
                    Text(showActivityHistory ? "アクティビティ履歴を閉じる" : "アクティビティ履歴を表示")
                        .font(.system(size: 12 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoGreen)
                    Spacer()
                    Image(systemName: showActivityHistory ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoGreen.opacity(0.7))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showActivityHistory {
                weeklyActivityRows
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.07), radius: 6, y: 2)
    }

    // MARK: - 摂取カロリートレンドカード

    private var intakeTrendCard: some View {
        let weekStart = Calendar.current.mondayStart(for: Date())

        // HealthKit サンプルを日付キーでグルーピング
        var samplesByKey: [String: [DietarySample]] = [:]
        for sample in healthKit.weeklyDietarySamples {
            let key = GoalingoView.yyyyMMddFmt.string(from: sample.startDate)
            samplesByKey[key, default: []].append(sample)
        }

        // 水分は Firestore から
        let days: [GoalIntakeDayData] = (0..<7).compactMap { i in
            guard let dayStart = cal.date(byAdding: .day, value: i, to: weekStart) else { return nil }
            let key = GoalingoView.yyyyMMddFmt.string(from: dayStart)
            let intake = weeklyIntakeData[key] ?? [:]
            return GoalIntakeDayData(
                date: dayStart,
                dayLabel: GoalingoView.dayOfWeekFmt.string(from: dayStart),
                samples: samplesByKey[key] ?? [],
                waterMl: intake["waterMl"] ?? 0
            )
        }
        return GoalIntakeTrendCard(days: days)
    }

    // MARK: - 週間カロリー収支カード

    private var weeklyCalorieCard: some View {
        GoalWeeklyCalorieCard(
            data: healthKit.weeklyCalorieData,
            dailyGoal: dietManager.settings.dailyDeficitGoal
        )
    }

    // MARK: - FITフィード（体重計測の写真）

    private var weightFeedSection: some View {
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let allLogs   = eduLog.history.filter { $0.activityName == "体重ログ" && ($0.thumbnailPath != nil || $0.thumbnailData != nil) }
        let recent    = allLogs.filter { $0.timestamp >= twoWeeksAgo }
        let older     = allLogs.filter { $0.timestamp < twoWeeksAgo }
        let displayed = showOlderWeightFeed ? allLogs : recent
        let fitBlue   = Color(hex: "#1CB0F6")

        return VStack(alignment: .leading, spacing: 10) {
            // ── ヘッダー（FOODフィードと同スタイル） ──
            HStack(spacing: 6) {
                Image(systemName: "scalemass.fill")
                    .font(.system(size: 12 * UIScale.font))
                    .foregroundColor(fitBlue)
                Text("FITフィード")
                    .font(.system(size: 13 * UIScale.font, weight: .black))
                    .foregroundColor(Color.duoDark)
                Spacer()
                if plus.isPlus {
                    Text("\(displayed.count)件")
                        .font(.system(size: 10 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoSubtitle)
                } else {
                    HStack(spacing: 3) {
                        Text("+")
                            .font(.system(size: 9 * UIScale.font, weight: .black))
                            .foregroundColor(.white)
                            .frame(width: 14, height: 14)
                            .background(Color.duoGold)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        Text("Plus限定")
                            .font(.system(size: 10 * UIScale.font, weight: .bold))
                            .foregroundColor(Color.duoGold)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.duoGold.opacity(0.1))
                    .clipShape(Capsule())
                }
            }

            // ── コンテンツ ──
            if !plus.isPlus {
                // Free ユーザー向けプロモ（FOODフィードプロモと同スタイル）
                Button { showPlusViewFromFit = true } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 14) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 22 * UIScale.font))
                                .foregroundColor(.white)
                                .frame(width: 48, height: 48)
                                .background(fitBlue)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("FIT に関する写真を記録できます")
                                    .font(.system(size: 13 * UIScale.font, weight: .black))
                                    .foregroundColor(Color.duoDark)
                                Text("体重変化・体型の推移を写真で管理")
                                    .font(.system(size: 11 * UIScale.font))
                                    .foregroundColor(Color.duoSubtitle)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12 * UIScale.font, weight: .semibold))
                                .foregroundColor(Color.duoSubtitle)
                        }
                    }
                    .padding(14)
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.06), radius: 5, y: 2)
                }
                .buttonStyle(.plain)
            } else if displayed.isEmpty {
                // Plus ユーザーだが写真なし
                Text("直近2週間の体重ログ写真はありません")
                    .font(.system(size: 12 * UIScale.font))
                    .foregroundColor(Color.duoSubtitle)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(Array(displayed.enumerated()), id: \.element.id) { idx, item in
                        WeightFeedCard(item: item)
                            .onTapGesture {
                                swipeWeightItems = displayed
                                swipeWeightStart = idx
                            }
                    }
                }

                if !showOlderWeightFeed && !older.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showOlderWeightFeed = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 13 * UIScale.font, weight: .semibold))
                            Text("過去のフィードを表示（\(older.count)件）")
                                .font(.system(size: 12 * UIScale.font, weight: .bold))
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10 * UIScale.font, weight: .semibold))
                        }
                        .foregroundColor(fitBlue)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(fitBlue.opacity(0.08))
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                } else if showOlderWeightFeed && !older.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showOlderWeightFeed = false
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 10 * UIScale.font, weight: .semibold))
                            Text("2週間以内のみ表示")
                                .font(.system(size: 11 * UIScale.font, weight: .bold))
                        }
                        .foregroundColor(Color.duoSubtitle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 体重グラフ

    private var weightChartCard: some View {
        let records = healthKit.bodyMassHistory
            .sorted { $0.measuredAt < $1.measuredAt }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("⚖️").font(.title3)
                Text("体重 推移（直近30日）")
                    .font(.headline.weight(.black)).foregroundColor(Color.duoDark)
                Spacer()
                if let latest = records.last {
                    Text(String(format: "%.1f kg", latest.kg))
                        .font(.system(size: 13 * UIScale.font, weight: .black))
                        .foregroundColor(Color(hex: "#1CB0F6"))
                }
            }

            if records.count >= 2 {
                LineChartView(
                    points: records.map { CGFloat($0.kg) },
                    lineColor: Color(hex: "#1CB0F6"),
                    goalLine: dietManager.settings.targetWeight > 0
                        ? CGFloat(dietManager.settings.targetWeight) : nil,
                    goalColor: Color.duoGreen,
                    labels: chartDateLabels(records.map { $0.measuredAt }),
                    unit: "kg"
                )
                .frame(height: 140)
            } else {
                emptyChartPlaceholder(message: "体重データが2件以上記録されると表示されます")
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - レース進捗カード

    private var raceProgressCard: some View {
        let settings = raceManager.settings
        let goal = settings.weeklyTrainingGoal()
        let actual = healthKit.weeklyRaceDistances
        let weeks = settings.weeksUntilRace
        let days  = settings.daysUntilRace
        let raceType = settings.raceType

        return VStack(alignment: .leading, spacing: 0) {
            // ── メイン目標セクション ──
            VStack(alignment: .leading, spacing: 12) {
                // ヘッダー
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(raceType == .custom && !settings.customName.isEmpty
                                 ? settings.customName : raceType.displayName)
                                .font(.system(size: 14 * UIScale.font, weight: .black))
                                .foregroundColor(Color.duoDark)
                            // 残り日数に応じて日付テキストの色を変える
                            let raceDateColor: Color = days == 0
                                ? Color(hex: "#FF4B4B")
                                : days <= 7  ? Color(hex: "#FF4B4B")
                                : days <= 30 ? Color(hex: "#FF9600")
                                : Color.duoSubtitle
                            Text("(\(GoalingoView.MdFmt.string(from: settings.raceDate)))")
                                .font(.system(size: 13 * UIScale.font, weight: days <= 30 ? .bold : .regular))
                                .foregroundColor(raceDateColor)
                        }
                        let distDesc = raceType == .custom
                            ? {
                                var parts: [String] = []
                                let d = settings.effectiveDistances
                                if d.swimKm > 0 { parts.append("スイム \(formatDistKm(d.swimKm))km") }
                                if d.bikeKm > 0 { parts.append("バイク \(formatDistKm(d.bikeKm))km") }
                                if d.runKm  > 0 { parts.append("ラン \(formatDistKm(d.runKm))km") }
                                return parts.joined(separator: " / ")
                            }()
                            : raceType.distanceDescription.joined(separator: " / ")
                        if !distDesc.isEmpty {
                            Text(distDesc)
                                .font(.system(size: 11 * UIScale.font))
                                .foregroundColor(Color.duoSubtitle)
                        }
                    }
                    Spacer()
                    Button {
                        showRaceGoalSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color.duoSubtitle)
                    }
                }

                Divider()

                // 大会プラン（planItems 横並び）
                let daysColor: Color = days <= 7 ? Color(hex: "#FF4B4B") : days <= 30 ? Color(hex: "#FFCC00") : Color(hex: "#1CB0F6")
                HStack(spacing: 0) {
                    // 大会まで（日数大・週数小）
                    VStack(spacing: 2) {
                        Text("📅").font(.system(size: 11 * UIScale.font))
                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                            Text("\(days)日")
                                .font(.system(size: 13 * UIScale.font, weight: .black))
                                .foregroundColor(daysColor)
                            Text("（\(weeks)週）")
                                .font(.system(size: 9 * UIScale.font))
                                .foregroundColor(Color.duoSubtitle)
                        }
                        Text("大会まで")
                            .font(.system(size: 8 * UIScale.font))
                            .foregroundColor(Color.duoSubtitle)
                    }
                    .frame(maxWidth: .infinity)
                    if goal.swimKm > 0 {
                        Divider().frame(height: 36)
                        planItem(icon: "🏊", label: "週スイム",
                                 value: String(format: "%.1f", goal.swimKm),
                                 unit: "km", color: Color(hex: "#1CB0F6"))
                    }
                    if goal.bikeKm > 0 {
                        Divider().frame(height: 36)
                        planItem(icon: "🚴", label: "週バイク",
                                 value: String(format: "%.0f", goal.bikeKm),
                                 unit: "km", color: Color(hex: "#FF9600"))
                    }
                    if goal.runKm > 0 {
                        Divider().frame(height: 36)
                        planItem(icon: "🏃", label: "週ラン/ウォーク",
                                 value: String(format: "%.1f", goal.runKm),
                                 unit: "km", color: Color.duoGreen)
                    }
                }
                .frame(maxWidth: .infinity)

                Divider()

                // 今週の目標 vs 実績
                VStack(spacing: 10) {
                    HStack {
                        Text("1週間の目標")
                            .font(.system(size: 12 * UIScale.font, weight: .bold))
                            .foregroundColor(Color.duoSubtitle)
                        Spacer()
                    }
                    if goal.swimKm > 0 {
                        raceProgressRow(
                            emoji: "🏊", label: "スイム",
                            actual: actual.swimKm, goal: goal.swimKm,
                            color: Color(hex: "#1CB0F6")
                        )
                    }
                    if goal.bikeKm > 0 {
                        raceProgressRow(
                            emoji: "🚴", label: "バイク",
                            actual: actual.bikeKm, goal: goal.bikeKm,
                            color: Color(hex: "#FF9600")
                        )
                    }
                    if goal.runKm > 0 {
                        raceProgressRow(
                            emoji: "🏃", label: "ラン/ウォーク",
                            actual: actual.runKm, goal: goal.runKm,
                            color: Color.duoGreen
                        )
                    }
                    // 週間活動カロリー進捗
                    // 週間活動カロリー目標 = トレーニング消費 + 最低限の歩行など（250kcal/日×7）
                    let bodyKg = healthKit.latestBodyMass > 0 ? healthKit.latestBodyMass : 65.0
                    let trainingCalGoal: Double = {
                        var cal = 0.0
                        cal += goal.swimKm * 70.0 * (bodyKg / 65.0)  // スイム ~70kcal/km
                        cal += goal.bikeKm * 28.0 * (bodyKg / 65.0)  // バイク ~28kcal/km
                        cal += goal.runKm  * 65.0 * (bodyKg / 65.0)  // ラン   ~65kcal/km
                        return cal
                    }()
                    let weeklyActiveGoal = trainingCalGoal + 400.0 * 7  // 歩行等ベースライン
                    let weeklyActiveDone = healthKit.weeklyBurnData.reduce(0.0) { $0 + $1.activeCalories }
                    if weeklyActiveGoal > 0 {
                        let calProgress = min(1.0, weeklyActiveDone / weeklyActiveGoal)
                        let calDone = weeklyActiveDone >= weeklyActiveGoal
                        let calColor = Color(red: 0.98, green: 0.07, blue: 0.31)
                        VStack(spacing: 4) {
                            HStack(spacing: 6) {
                                Text("🔥").font(.system(size: 14))
                                Text("週間カロリー目標")
                                    .font(.system(size: 12 * UIScale.font, weight: .medium))
                                    .foregroundColor(Color.duoDark)
                                Spacer()
                                if calDone {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(calColor)
                                }
                                Text("\(Int(weeklyActiveDone)) / \(Int(weeklyActiveGoal)) kcal")
                                    .font(.system(size: 12 * UIScale.font, weight: .bold))
                                    .foregroundColor(calDone ? calColor : Color.duoDark)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(calColor.opacity(0.15))
                                        .frame(height: 8)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(calColor)
                                        .frame(width: geo.size.width * CGFloat(calProgress), height: 8)
                                }
                            }
                            .frame(height: 8)
                        }
                    }
                    // 体重進捗バー
                    let weightGoal = dietManager.settings.targetWeight
                    let weightStart = dietManager.settings.hasStartStats && dietManager.settings.startWeight > 0
                        ? dietManager.settings.startWeight : max(healthKit.latestBodyMass, weightGoal)
                    let weightCurrent = healthKit.latestBodyMass
                    if weightGoal > 0 && weightCurrent > 0 {
                        let weightProgress: Double = {
                            let total = weightStart - weightGoal
                            guard total > 0 else { return weightCurrent <= weightGoal ? 1 : 0 }
                            return min(1, max(0, (weightStart - weightCurrent) / total))
                        }()
                        let weightDone = weightCurrent <= weightGoal
                        let weightColor = Color(hex: "#1CB0F6")
                        VStack(spacing: 4) {
                            HStack(spacing: 6) {
                                Text("⚖️").font(.system(size: 14))
                                Text("体重")
                                    .font(.system(size: 12 * UIScale.font, weight: .medium))
                                    .foregroundColor(Color.duoDark)
                                Spacer()
                                if weightDone {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(weightColor)
                                }
                                Text(String(format: "%.1f / %.1f kg", weightCurrent, weightGoal))
                                    .font(.system(size: 12 * UIScale.font, weight: .bold))
                                    .foregroundColor(weightDone ? weightColor : Color.duoDark)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(weightColor.opacity(0.15))
                                        .frame(height: 8)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(weightColor)
                                        .frame(width: geo.size.width * CGFloat(weightProgress), height: 8)
                                }
                            }
                            .frame(height: 8)
                        }
                    }
                }
            }
            .padding(14)

            // ── 今日の通常ワークアウト履歴（距離表示）──
            Divider()
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    showRaceWorkoutHistory.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 13 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color.duoGreen)
                    Text(showRaceWorkoutHistory ? "週間アクティビティを閉じる" : "週間アクティビティを表示")
                        .font(.system(size: 12 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoGreen)
                    Spacer()
                    // 週間カロリー合計
                    let weeklyTotalCal = healthKit.weeklyWorkoutSessions.filter { w in
                        let src = "\(w.sourceName) \(w.sourceBundleId)".lowercased()
                        let isKfit = src.contains("kfit") || src.contains("fitingo") || src.contains("duofit")
                        return !(isKfit && w.durationMinutes < 1)
                    }.reduce(0.0) { $0 + $1.calories }
                    if weeklyTotalCal > 0 {
                        Text("\(Int(weeklyTotalCal)) kcal")
                            .font(.system(size: 11 * UIScale.font, weight: .bold, design: .rounded))
                            .foregroundColor(Color.duoOrange)
                    }
                    Image(systemName: showRaceWorkoutHistory ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoGreen.opacity(0.7))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showRaceWorkoutHistory {
                raceWorkoutHistoryRows
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.07), radius: 6, y: 2)
    }

    /// 大会カード用：今週の通常ワークアウト（Fitingoセット除く）を日付付き・距離で表示
    private var raceWorkoutHistoryRows: some View {
        // kfit/fitingo アプリからの短いワークアウトを除外
        let workouts = healthKit.weeklyWorkoutSessions.filter { w in
            let src = "\(w.sourceName) \(w.sourceBundleId)".lowercased()
            let isKfit = src.contains("kfit") || src.contains("fitingo") || src.contains("duofit")
            return !(isKfit && w.durationMinutes < 1)
        }
        // 日付ごとにグループ化（新しい順）
        let cal = Calendar.current
        var grouped: [(date: Date, items: [WorkoutSession])] = []
        var seen: [Date: [WorkoutSession]] = [:]
        for w in workouts {
            let d = cal.startOfDay(for: w.startDate)
            seen[d, default: []].append(w)
        }
        let sortedDates = seen.keys.sorted(by: >)
        for d in sortedDates { grouped.append((date: d, items: seen[d]!)) }

        return Group {
            if workouts.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "figure.run")
                        .foregroundColor(Color.duoSubtitle)
                    Text("今週のワークアウト記録はまだありません")
                        .font(.system(size: 12 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color.duoSubtitle)
                    Spacer()
                }
                .padding(12)
                .background(Color.duoBg)
                .cornerRadius(12)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    // 日別グループ
                    ForEach(grouped, id: \.date) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 4) {
                                Text(GoalingoView.MdFmt.string(from: group.date))
                                    .font(.system(size: 10 * UIScale.font, weight: .black))
                                    .foregroundColor(Color.duoSubtitle)
                                Spacer()
                                // 1日の活動カロリー合計
                                let dayCal = group.items.reduce(0.0) { $0 + $1.calories }
                                if dayCal > 0 {
                                    Text("🔥 \(Int(dayCal)) kcal")
                                        .font(.system(size: 10 * UIScale.font, weight: .bold, design: .rounded))
                                        .foregroundColor(Color.duoOrange)
                                }
                            }
                            .padding(.top, 2)
                            ForEach(group.items) { w in
                                raceWorkoutDistanceRow(w)
                            }
                        }
                    }
                }
            }
        }
    }

    private func raceWorkoutDistanceRow(_ workout: WorkoutSession) -> some View {
        HStack(spacing: 7) {
            Text(workout.emoji)
                .font(.system(size: 15 * UIScale.font))
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.activityName)
                    .font(.system(size: 11 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoDark)
                Text("\(timeString(workout.startDate))-\(timeString(workout.endDate)) ・ \(workout.sourceName)")
                    .font(.system(size: 8 * UIScale.font, weight: .semibold))
                    .foregroundColor(Color.duoSubtitle)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if workout.distanceKm > 0 {
                    Text(workout.distanceKm >= 1
                         ? String(format: "%.2f km", workout.distanceKm)
                         : String(format: "%.0f m", workout.distanceKm * 1000))
                        .font(.system(size: 11 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor(Color.duoGreen)
                } else {
                    Text("\(Int(workout.durationMinutes))分")
                        .font(.system(size: 11 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor(Color.duoGreen)
                }
                if workout.calories > 0 {
                    Text("\(Int(workout.calories)) kcal")
                        .font(.system(size: 8 * UIScale.font, weight: .bold, design: .rounded))
                        .foregroundColor(Color.duoOrange)
                }
            }
        }
        .padding(8)
        .background(Color.duoBlue.opacity(0.07))
        .cornerRadius(10)
    }

    private var weeklyActivityRows: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let data: [DailyBurnSummary] = {
            var d = healthKit.weeklyBurnData
            for i in d.indices {
                let key = GoalingoView.yyyyMMddFmt.string(from: d[i].date)
                d[i].setCount = weeklySetCounts[key] ?? 0
            }
            return d
        }()

        return VStack(spacing: 4) {
            ForEach(data) { day in
                let isToday = cal.startOfDay(for: day.date) == today
                let hasData = day.activeCalories > 0 || day.setCount > 0 || day.steps > 0
                HStack(spacing: 6) {
                    Text(day.dayLabel)
                        .font(.system(size: 11 * UIScale.font, weight: isToday ? .black : .medium))
                        .foregroundColor(isToday ? Color.duoGreen : Color.duoSubtitle)
                        .frame(width: 20, alignment: .leading)
                    if hasData {
                        if day.setCount > 0 {
                            Label("\(day.setCount)set", systemImage: "dumbbell.fill")
                                .font(.system(size: 10 * UIScale.font, weight: .bold))
                                .foregroundColor(Color.duoGreen)
                        }
                        if day.exerciseMinutes > 0 {
                            Label("\(Int(day.exerciseMinutes))分", systemImage: "clock.fill")
                                .font(.system(size: 10 * UIScale.font))
                                .foregroundColor(Color(hex: "#1CB0F6"))
                        }
                        if day.activeCalories > 0 {
                            Label("\(Int(day.activeCalories))kcal", systemImage: "flame.fill")
                                .font(.system(size: 10 * UIScale.font))
                                .foregroundColor(Color(hex: "#FF9600"))
                        }
                        if day.steps > 0 {
                            Label(day.steps >= 1000
                                  ? String(format: "%.1fk", Double(day.steps) / 1000.0)
                                  : "\(day.steps)",
                                  systemImage: "figure.walk")
                                .font(.system(size: 10 * UIScale.font))
                                .foregroundColor(Color.duoSubtitle)
                        }
                    } else {
                        Text("—")
                            .font(.system(size: 10 * UIScale.font))
                            .foregroundColor(Color.duoSubtitle.opacity(0.5))
                    }
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(isToday ? Color.duoGreen.opacity(0.07) : Color.clear)
                .cornerRadius(8)
            }
        }
    }

    private func raceProgressRow(emoji: String, label: String,
                                  actual: Double, goal: Double,
                                  color: Color) -> some View {
        let progress = goal > 0 ? min(1.0, actual / goal) : 0
        let done = actual >= goal && goal > 0
        return VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text(emoji).font(.system(size: 14))
                Text(label)
                    .font(.system(size: 12 * UIScale.font, weight: .medium))
                    .foregroundColor(Color.duoDark)
                Spacer()
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(color)
                }
                Text(actual >= 10
                     ? "\(Int(actual.rounded())) / \(Int(goal.rounded())) km"
                     : String(format: "%.1f / %.1f km", actual, goal))
                    .font(.system(size: 12 * UIScale.font, weight: .bold))
                    .foregroundColor(done ? color : Color.duoDark)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.duoSubtitle.opacity(0.15))
                        .frame(height: 7)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(progress), height: 7)
                }
            }
            .frame(height: 7)
        }
    }

    // MARK: - 体脂肪グラフ

    private var bodyFatChartCard: some View {
        let records = healthKit.bodyFatHistory

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("📉").font(.title3)
                Text("体脂肪率 推移（直近30日）")
                    .font(.headline.weight(.black)).foregroundColor(Color.duoDark)
                Spacer()
                if let latest = records.last {
                    Text(String(format: "%.1f%%", latest.percent))
                        .font(.system(size: 13 * UIScale.font, weight: .black))
                        .foregroundColor(Color(hex: "#CE82FF"))
                }
            }

            if records.count >= 2 {
                let goal = dietManager.settings
                LineChartView(
                    points: records.map { CGFloat($0.percent) },
                    lineColor: Color(hex: "#CE82FF"),
                    goalLine: goal.hasBodyFatTarget && goal.targetBodyFatPercent > 0
                        ? CGFloat(goal.targetBodyFatPercent) : nil,
                    goalColor: Color.duoGreen,
                    labels: chartDateLabels(records.map { $0.measuredAt }),
                    unit: "%"
                )
                .frame(height: 140)
            } else {
                emptyChartPlaceholder(message: "体脂肪率データが2件以上記録されると表示されます")
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - Helpers

    private func emptyChartPlaceholder(message: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 28 * UIScale.font))
                    .foregroundColor(Color(.systemGray4))
                Text(message)
                    .font(.caption)
                    .foregroundColor(Color.duoSubtitle)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(height: 100)
    }

    private func chartDateLabels(_ dates: [Date]) -> [String] {
        guard !dates.isEmpty else { return [] }
        let step = max(1, dates.count / 4)
        return dates.enumerated().map { i, d in
            (i % step == 0 || i == dates.count - 1) ? GoalingoView.MdFmt.string(from: d) : ""
        }
    }
}

// MARK: - 週間カロリー収支バー（日別）

// MARK: - 週間カロリー収支カード

private struct GoalWeeklyCalorieCard: View {
    let data: [DailyCalorieBalance]
    var dailyGoal: Int = -150

    private let halfBarH: CGFloat = 42
    private var weeklyGoal: Int { dailyGoal * 7 }

    private func statusBadge(weekTotal: Int) -> (label: String, color: Color) {
        let today = Calendar.current.startOfDay(for: Date())
        let daysElapsed = max(1, data.filter { Calendar.current.startOfDay(for: $0.date) <= today }.count)
        let expected = daysElapsed * dailyGoal
        if weekTotal <= weeklyGoal       { return ("🎉 達成！", Color.duoGreen) }
        if weekTotal <= expected         { return ("👍 順調", Color(hex: "#1CB0F6")) }
        if weekTotal < expected / 2      { return ("⚠️ 注意", Color(hex: "#FF9600")) }
        return ("🚨 要注意", Color(hex: "#FF4B4B"))
    }

    var body: some View {
        let weekTotal = data.reduce(0) { $0 + $1.balance }
        let maxAbs = max(data.map { abs($0.balance) }.max() ?? 0, 300)
        let badge = statusBadge(weekTotal: weekTotal)

        let todayStart = Calendar.current.startOfDay(for: Date())
        let daysElapsed = max(1, data.filter { Calendar.current.startOfDay(for: $0.date) <= todayStart }.count)
        let dailyAvg = weekTotal / daysElapsed

        let balanceColor: Color = weekTotal > 0 ? Color(hex: "#FF4B4B") : Color.duoGreen
        let mondayMass: Double? = data.first?.bodyMass
        let latestMass: Double? = data.reversed().first(where: { $0.bodyMass != nil })?.bodyMass
        let actualChange: Double? = mondayMass.flatMap { mon in latestMass.map { lat in lat - mon } }
        let targetWeeklyKg = Double(dailyGoal) * 7.0 / 7700.0

        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color(hex: "#FF9600"), Color(hex: "#FFCC00")],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 4)

            VStack(alignment: .leading, spacing: 12) {
                // タイトル行
                HStack(spacing: 6) {
                    Text("⚖️")
                        .font(.system(size: 17 * UIScale.font))
                    HStack(spacing: 5) {
                        Text("カロリー収支")
                            .font(.system(size: 14 * UIScale.font, weight: .black))
                            .foregroundColor(Color.duoDark)
                        Text(badge.label)
                            .font(.system(size: 10 * UIScale.font, weight: .black))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(badge.color)
                            .cornerRadius(6)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        HStack(alignment: .lastTextBaseline, spacing: 3) {
                            Text("平均 " + (dailyAvg >= 0 ? "+" : "") + "\(dailyAvg)")
                                .font(.system(size: 10 * UIScale.font, weight: .semibold))
                                .foregroundColor(Color.duoSubtitle)
                            Text("/")
                                .font(.system(size: 10 * UIScale.font))
                                .foregroundColor(Color.duoSubtitle)
                            Text("計 " + (weekTotal >= 0 ? "+" : "") + "\(weekTotal)")
                                .font(.system(size: 15 * UIScale.font, weight: .black))
                                .foregroundColor(balanceColor)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .fixedSize(horizontal: true, vertical: false)

                        Text("kcal")
                            .font(.system(size: 10 * UIScale.font, weight: .semibold))
                            .foregroundColor(Color.duoSubtitle)
                    }
                }

                if data.isEmpty {
                    Text("今週のカロリーデータを読み込み中...")
                        .font(.caption)
                        .foregroundColor(Color.duoSubtitle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    // ─── 凡例 ───
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 1).fill(Color.duoGreen.opacity(0.85)).frame(width: 10, height: 4)
                            Text("消費超過").font(.system(size: 10 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                        }
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 1).fill(Color(hex: "#FF4B4B").opacity(0.75)).frame(width: 10, height: 4)
                            Text("摂取超過").font(.system(size: 10 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                        }
                        HStack(spacing: 4) {
                            ZStack {
                                Rectangle().fill(Color.duoOrange).frame(width: 12, height: 1.5)
                                Circle().fill(Color.duoOrange).frame(width: 5, height: 5)
                            }
                            .frame(width: 12, height: 8)
                            Text("体重変化").font(.system(size: 10 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                        }
                        Spacer()
                    }

                    // ─── balance値ラベル行 ───
                    HStack(spacing: 4) {
                        ForEach(data) { day in
                            Text(day.balance != 0 ? (day.balance >= 0 ? "+" : "") + "\(day.balance)" : "")
                                .font(.system(size: 8 * UIScale.font, weight: .bold))
                                .foregroundColor(day.balance <= 0 ? Color.duoGreen : Color(hex: "#FF4B4B"))
                                .lineLimit(1).minimumScaleFactor(0.5)
                                .frame(maxWidth: .infinity).frame(height: 11)
                        }
                    }

                    // ─── 棒グラフ ＋ 体重折れ線オーバーレイ ───
                    ZStack {
                        // 積み上げ棒
                        HStack(spacing: 4) {
                            ForEach(data) { day in
                                balanceBarColumn(day: day, maxAbs: maxAbs)
                            }
                        }
                        // 体重折れ線
                        GeometryReader { geo in
                            weightLineOverlay(data: data, size: geo.size)
                        }
                    }
                    .frame(height: halfBarH * 2 + 1)

                    // ─── 曜日・体重ラベル行 ───
                    HStack(spacing: 4) {
                        ForEach(data) { day in
                            VStack(spacing: 1) {
                                Text(day.dayLabel)
                                    .font(.system(size: 10 * UIScale.font, weight: .semibold))
                                    .foregroundColor(Color.duoSubtitle)
                                if let mass = day.bodyMass {
                                    Text(String(format: "%.1f", mass))
                                        .font(.system(size: 10 * UIScale.font, weight: .black, design: .rounded))
                                        .foregroundColor(Color.duoDark)
                                        .lineLimit(1)
                                } else {
                                    Text("—")
                                        .font(.system(size: 10 * UIScale.font, weight: .bold))
                                        .foregroundColor(Color(.systemGray4))
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    // ─── グラフ下3指標 ───
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("目標差異")
                                .font(.system(size: 10 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                            HStack(alignment: .lastTextBaseline, spacing: 2) {
                                Text((dailyGoal >= 0 ? "+" : "") + "\(dailyGoal)")
                                    .font(.system(size: 14 * UIScale.font, weight: .black, design: .rounded))
                                    .foregroundColor(dailyGoal <= 0 ? Color.duoGreen : Color(hex: "#FF4B4B"))
                                Text("kcal/日")
                                    .font(.system(size: 10 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                            }
                        }
                        Spacer()
                        VStack(alignment: .center, spacing: 2) {
                            Text("目標減少")
                                .font(.system(size: 10 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                            HStack(alignment: .lastTextBaseline, spacing: 2) {
                                Text(String(format: "%.2f", targetWeeklyKg))
                                    .font(.system(size: 14 * UIScale.font, weight: .black, design: .rounded))
                                    .foregroundColor(targetWeeklyKg <= 0 ? Color.duoGreen : Color(hex: "#FF4B4B"))
                                Text("kg/週")
                                    .font(.system(size: 10 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("実")
                                .font(.system(size: 10 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                            if let ch = actualChange {
                                HStack(alignment: .lastTextBaseline, spacing: 2) {
                                    Text(String(format: "%+.1f", ch))
                                        .font(.system(size: 14 * UIScale.font, weight: .black, design: .rounded))
                                        .foregroundColor(ch <= 0 ? Color.duoGreen : Color(hex: "#FF4B4B"))
                                    Text("kg")
                                        .font(.system(size: 10 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                                }
                            } else {
                                Text("—")
                                    .font(.system(size: 14 * UIScale.font, weight: .black)).foregroundColor(Color.duoSubtitle)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
    }

    // ── 収支棒（1日分）─────────────────────────────────────────────────
    private func balanceBarColumn(day: DailyCalorieBalance, maxAbs: Int) -> some View {
        let bal  = day.balance
        let barH = maxAbs > 0
            ? max(CGFloat(bal != 0 ? 2 : 0), halfBarH * CGFloat(abs(bal)) / CGFloat(maxAbs))
            : 0
        return VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                Color.clear.frame(height: halfBarH)
                if bal < 0 {
                    RoundedRectangle(cornerRadius: 2).fill(Color.duoGreen.opacity(0.85))
                        .frame(height: min(barH, halfBarH))
                }
            }
            Rectangle().fill(Color(.systemGray3)).frame(height: 1)
            ZStack(alignment: .top) {
                Color.clear.frame(height: halfBarH)
                if bal > 0 {
                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: "#FF4B4B").opacity(0.75))
                        .frame(height: min(barH, halfBarH))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // ── 体重折れ線オーバーレイ ─────────────────────────────────────────
    // 中心線（y = size.height/2）= 収支ゼロ基準。
    // 体重増加 → 中心より上（y 減少）、体重減少 → 中心より下（y 増加）
    private func weightLineOverlay(data: [DailyCalorieBalance], size: CGSize) -> some View {
        let massPoints: [(idx: Int, mass: Double)] = data.enumerated().compactMap { i, day in
            guard let m = day.bodyMass else { return nil }
            return (i, m)
        }
        guard let baseline = massPoints.first?.mass else { return AnyView(EmptyView()) }

        let deltas = massPoints.map { (idx: $0.idx, delta: $0.mass - baseline) }
        let maxDelta = max(deltas.map { abs($0.delta) }.max() ?? 0.01, 0.01)
        let scale    = CGFloat(halfBarH) / CGFloat(maxDelta)

        let count  = max(data.count, 1)
        let colW   = size.width / CGFloat(count)
        let centerY = size.height / 2

        let pts: [(idx: Int, pt: CGPoint)] = deltas.map { item in
            let x = colW * CGFloat(item.idx) + colW / 2
            // 増加 → 上 (y 小)、減少 → 下 (y 大)
            let y = centerY - CGFloat(item.delta) * scale
            return (item.idx, CGPoint(x: x, y: max(4, min(size.height - 4, y))))
        }

        return AnyView(ZStack {
            if pts.count >= 2 {
                Path { path in
                    path.move(to: pts[0].pt)
                    for p in pts.dropFirst() { path.addLine(to: p.pt) }
                }
                .stroke(Color.duoOrange,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            ForEach(pts, id: \.idx) { vp in
                // ドット
                Circle().fill(Color.duoOrange).frame(width: 5, height: 5).position(vp.pt)
                // 体重値ラベル（ドットの上下に交互配置して重なりを軽減）
                let labelY = vp.idx % 2 == 0
                    ? max(vp.pt.y - 9, 5)
                    : min(vp.pt.y + 9, size.height - 5)
                Text(String(format: "%.1f", massPoints.first(where: { $0.idx == vp.idx })?.mass ?? 0))
                    .font(.system(size: 7 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoOrange)
                    .position(x: vp.pt.x, y: labelY)
            }
        })
    }
}

// MARK: - Line Chart View

private struct LineChartView: View {
    let points: [CGFloat]
    let lineColor: Color
    var goalLine: CGFloat? = nil
    var goalColor: Color = Color.duoGreen
    var labels: [String] = []
    var unit: String = ""

    var body: some View {
        let minVal = (points.min() ?? 0)
        let maxVal = (points.max() ?? 1)
        let dataRange = max(maxVal - minVal, 0.5)

        let effectiveMin: CGFloat = {
            if let g = goalLine { return min(minVal, g) - dataRange * 0.1 }
            return minVal - dataRange * 0.15
        }()
        let effectiveMax: CGFloat = {
            if let g = goalLine { return max(maxVal, g) + dataRange * 0.1 }
            return maxVal + dataRange * 0.15
        }()
        let totalRange = max(effectiveMax - effectiveMin, 0.1)

        return VStack(spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                ZStack {
                    // Grid lines
                    ForEach(0..<4) { i in
                        let y = h * CGFloat(i) / 3
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: w, y: y))
                        }
                        .stroke(Color(.systemGray5), lineWidth: 0.5)
                    }

                    // Goal line (dashed green)
                    if let goal = goalLine {
                        let gy = h * (1 - (goal - effectiveMin) / totalRange)
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: gy))
                            p.addLine(to: CGPoint(x: w, y: gy))
                        }
                        .stroke(goalColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))

                        Text(unit == "%" ? String(format: "%.1f%%", Float(goal)) : String(format: "%.1f", Float(goal)))
                            .font(.system(size: 8 * UIScale.font, weight: .bold))
                            .foregroundColor(goalColor)
                            .position(x: w - 22, y: max(10, min(h - 10, gy - 8)))
                    }

                    // Fill area
                    Path { p in
                        guard points.count > 1 else { return }
                        let step = w / CGFloat(points.count - 1)
                        let startY = h * (1 - (points[0] - effectiveMin) / totalRange)
                        p.move(to: CGPoint(x: 0, y: h))
                        p.addLine(to: CGPoint(x: 0, y: startY))
                        for i in 1..<points.count {
                            let x = step * CGFloat(i)
                            let y = h * (1 - (points[i] - effectiveMin) / totalRange)
                            p.addLine(to: CGPoint(x: x, y: y))
                        }
                        p.addLine(to: CGPoint(x: w, y: h))
                        p.closeSubpath()
                    }
                    .fill(lineColor.opacity(0.12))

                    // Line
                    Path { p in
                        guard points.count > 1 else { return }
                        let step = w / CGFloat(points.count - 1)
                        p.move(to: CGPoint(
                            x: 0,
                            y: h * (1 - (points[0] - effectiveMin) / totalRange)
                        ))
                        for i in 1..<points.count {
                            let x = step * CGFloat(i)
                            let y = h * (1 - (points[i] - effectiveMin) / totalRange)
                            p.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    .stroke(lineColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    // Dots
                    ForEach(0..<points.count, id: \.self) { i in
                        let step = w / CGFloat(max(points.count - 1, 1))
                        let x = step * CGFloat(i)
                        let y = h * (1 - (points[i] - effectiveMin) / totalRange)
                        Circle()
                            .fill(lineColor)
                            .frame(width: 4, height: 4)
                            .position(x: x, y: y)
                    }

                    // Min/Max labels
                    VStack {
                        Text(String(format: "%.1f", Float(effectiveMax)))
                            .font(.system(size: 8 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                        Spacer()
                        Text(String(format: "%.1f", Float(effectiveMin)))
                            .font(.system(size: 8 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                    }
                    .frame(width: w, height: h, alignment: .trailing)
                    .padding(.trailing, 2)
                }
            }

            // X-axis labels
            if !labels.isEmpty {
                HStack(spacing: 0) {
                    ForEach(0..<labels.count, id: \.self) { i in
                        Text(labels[i])
                            .font(.system(size: 8 * UIScale.font))
                            .foregroundColor(Color.duoSubtitle)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

// MARK: - 週間消費カロリーカード（安静時・活動積み上げ棒グラフ）

private struct GoalWeeklyBurnCard: View {
    let data: [DailyBurnSummary]
    let intakePerDay: [Double]
    let weightPerDay: [Double?]

    private let restingColor = Color(hex: "#16A34A")
    private let activeColor  = Color(hex: "#4ADE80")
    private let intakeColor  = Color(hex: "#FF9600")
    private let weightColor  = Color(hex: "#1CB0F6")
    private let maxBurnH: CGFloat = 92
    private let maxIntakeH: CGFloat = 70

    var body: some View {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let pastData   = data.filter { Calendar.current.startOfDay(for: $0.date) < todayStart }
        let maxBurn    = max(data.map { $0.totalCalories }.max() ?? 1, 1)
        let maxIntake  = max(intakePerDay.max() ?? 1, 1)
        let weekBurn   = Int(data.reduce(0) { $0 + $1.totalCalories })
        let weekIntake = Int(intakePerDay.reduce(0, +))
        let avgBurn: Int? = pastData.isEmpty ? nil
            : Int(pastData.reduce(0) { $0 + $1.totalCalories } / Double(pastData.count))

        Button {
            let schemes = ["x-apple-fitness://", "x-apple-health://"]
            for scheme in schemes {
                if let url = URL(string: scheme), UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url); return
                }
            }
        } label: {
            VStack(spacing: 0) {
                LinearGradient(colors: [Color(hex: "#16A34A"), Color(hex: "#4ADE80")],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(height: 4)

                VStack(alignment: .leading, spacing: 12) {
                    // ── ヘッダー ──────────────────────────────────────────────
                    HStack(spacing: 6) {
                        Text("🔥").font(.system(size: 17 * UIScale.font))
                        Text("週間カロリー")
                            .font(.system(size: 14 * UIScale.font, weight: .black))
                            .foregroundColor(Color.duoDark)
                        Spacer()
                        if weekBurn > 0 {
                            VStack(alignment: .trailing, spacing: 2) {
                                HStack(alignment: .lastTextBaseline, spacing: 3) {
                                    if let avg = avgBurn {
                                        Text("平均消費 \(avg)")
                                            .font(.system(size: 10 * UIScale.font, weight: .semibold))
                                            .foregroundColor(Color.duoSubtitle)
                                        Text("/").font(.system(size: 10 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                                    }
                                    Text("\(weekBurn)")
                                        .font(.system(size: 13 * UIScale.font, weight: .black))
                                        .foregroundColor(Color(hex: "#16A34A"))
                                }
                                Text("kcal").font(.system(size: 10 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                            }
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11 * UIScale.font, weight: .semibold))
                            .foregroundColor(Color.duoSubtitle)
                    }

                    // ── 凡例 ─────────────────────────────────────────────────
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2).fill(restingColor).frame(width: 10, height: 8)
                            Text("安静時").font(.system(size: 10 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                        }
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2).fill(activeColor).frame(width: 10, height: 8)
                            Text("活動").font(.system(size: 10 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                        }
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2).fill(intakeColor).frame(width: 10, height: 8)
                            Text("食事").font(.system(size: 10 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                        }
                        HStack(spacing: 4) {
                            ZStack {
                                Rectangle().fill(weightColor).frame(width: 12, height: 1.5)
                                Circle().fill(weightColor).frame(width: 5, height: 5)
                            }.frame(width: 12, height: 8)
                            Text("体重").font(.system(size: 10 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                        }
                        Spacer()
                        if weekIntake > 0 {
                            Text("食事 \(weekIntake) kcal")
                                .font(.system(size: 10 * UIScale.font, weight: .semibold))
                                .foregroundColor(intakeColor)
                        }
                    }

                    if data.isEmpty {
                        Text("データを読み込み中...")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                            .frame(maxWidth: .infinity).padding(.vertical, 20)
                    } else {
                        // 体重折れ線の計算
                        let monBase: Double? = weightPerDay.first(where: { $0 != nil }) ?? nil
                        let wDeltas: [Double?] = weightPerDay.map { $0.map { $0 - (monBase ?? $0) } }
                        let wMaxD = max(wDeltas.compactMap { $0 }.map { abs($0) }.max() ?? 0.5, 0.5)
                        // 高さ定数
                        let burnLabelH: CGFloat = 11
                        let burnH: CGFloat = maxBurnH      // 64
                        let dayH: CGFloat = 28             // 曜日ラベル行（コンテンツ+padding）
                        let intakeH: CGFloat = maxIntakeH  // 48
                        let intakeLabelH: CGFloat = 11
                        let totalH = burnLabelH + burnH + dayH + intakeH + intakeLabelH
                        // 体重の基準Y（曜日ラベル行の中央）
                        let wBaseY = burnLabelH + burnH + dayH / 2
                        // 上下の振れ幅は ±burnH*0.65 と ±intakeH*0.55 の小さい方
                        let amplitude = min(burnH * 0.65, intakeH * 0.55)

                        ZStack(alignment: .top) {
                            // カロリーバー＋曜日ラベル
                            VStack(spacing: 0) {
                                // 燃焼カロリー値ラベル（上）
                                HStack(spacing: 0) {
                                    ForEach(Array(data.enumerated()), id: \.offset) { _, day in
                                        Text(day.totalCalories > 0 ? "\(Int(day.totalCalories))" : "")
                                            .font(.system(size: 8 * UIScale.font, weight: .bold))
                                            .foregroundColor(Color.duoDark)
                                            .lineLimit(1).minimumScaleFactor(0.5)
                                            .frame(maxWidth: .infinity).frame(height: burnLabelH)
                                    }
                                }
                                // 燃焼バー（上方向）
                                HStack(alignment: .bottom, spacing: 0) {
                                    ForEach(Array(data.enumerated()), id: \.offset) { _, day in
                                        burnBar(day: day, maxBurn: maxBurn)
                                    }
                                }
                                .frame(height: burnH)
                                // 中央：曜日ラベル
                                HStack(spacing: 0) {
                                    ForEach(Array(data.enumerated()), id: \.offset) { _, day in
                                        Text(day.dayLabel)
                                            .font(.system(size: 10 * UIScale.font, weight: .semibold))
                                            .foregroundColor(Color.duoSubtitle)
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .frame(height: dayH)
                                // 食事バー（下方向）
                                HStack(alignment: .top, spacing: 0) {
                                    ForEach(Array(intakePerDay.enumerated()), id: \.offset) { i, intake in
                                        intakeBar(calories: intake, maxIntake: maxIntake)
                                    }
                                }
                                .frame(height: intakeH)
                                // 食事カロリー値ラベル（下）
                                HStack(spacing: 0) {
                                    ForEach(Array(intakePerDay.enumerated()), id: \.offset) { _, intake in
                                        Text(intake > 0 ? "\(Int(intake))" : "")
                                            .font(.system(size: 8 * UIScale.font, weight: .bold))
                                            .foregroundColor(intakeColor)
                                            .lineLimit(1).minimumScaleFactor(0.5)
                                            .frame(maxWidth: .infinity).frame(height: intakeLabelH)
                                    }
                                }
                            }

                            // 体重折れ線オーバーレイ
                            if monBase != nil {
                                GeometryReader { geo in
                                    let count = max(weightPerDay.count, 1)
                                    let colW  = geo.size.width / CGFloat(count)
                                    let pts: [(Int, CGPoint)] = wDeltas.enumerated().compactMap { i, d in
                                        guard let delta = d else { return nil }
                                        let x = colW * CGFloat(i) + colW / 2
                                        let y = wBaseY - CGFloat(delta / wMaxD) * amplitude
                                        return (i, CGPoint(x: x, y: y))
                                    }
                                    ZStack {
                                        // 基準線（曜日ラベル中央）
                                        Rectangle()
                                            .fill(weightColor.opacity(0.3))
                                            .frame(height: 1)
                                            .position(x: geo.size.width / 2, y: wBaseY)
                                        // 折れ線
                                        if pts.count >= 2 {
                                            Path { p in
                                                p.move(to: pts[0].1)
                                                for vp in pts.dropFirst() { p.addLine(to: vp.1) }
                                            }
                                            .stroke(weightColor,
                                                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                                        }
                                        // ドット＋kg値
                                        ForEach(pts, id: \.0) { i, pt in
                                            Circle().fill(weightColor).frame(width: 5, height: 5).position(pt)
                                            if let kg = weightPerDay[safe: i] ?? nil {
                                                Text(String(format: "%.1f", kg))
                                                    .font(.system(size: 7.5 * UIScale.font, weight: .bold))
                                                    .foregroundColor(weightColor)
                                                    .position(x: pt.x, y: pt.y < wBaseY ? pt.y - 9 : pt.y + 9)
                                            }
                                        }
                                    }
                                }
                                .frame(height: totalH)
                                .allowsHitTesting(false)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
            }
            .background(Color(.systemBackground))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
    }

    // ── 燃焼バー（積み上げ・上方向）─────────────────────────────────────
    private func burnBar(day: DailyBurnSummary, maxBurn: Double) -> some View {
        let totalH = maxBurn > 0 ? maxBurnH * CGFloat(day.totalCalories) / CGFloat(maxBurn) : 0
        let restH  = day.totalCalories > 0 ? totalH * CGFloat(day.restingCalories) / CGFloat(day.totalCalories) : 0
        let actH   = totalH - restH
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2).fill(activeColor)
                    .frame(height: max(actH, day.activeCalories > 0 ? 2 : 0))
                RoundedRectangle(cornerRadius: 2).fill(restingColor)
                    .frame(height: max(restH, day.restingCalories > 0 ? 2 : 0))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // ── 食事バー（下方向）────────────────────────────────────────────────
    private func intakeBar(calories: Double, maxIntake: Double) -> some View {
        let h = maxIntake > 0 ? maxIntakeH * CGFloat(calories) / CGFloat(maxIntake) : 0
        return VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2).fill(intakeColor)
                .frame(height: max(h, calories > 0 ? 2 : 0))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - 摂取カロリートレンド データ

private struct GoalIntakeDayData: Identifiable {
    let id = UUID()
    let date: Date
    let dayLabel: String
    var samples: [DietarySample] = []   // HealthKit 摂取サンプル（時刻順）
    var waterMl: Int = 0
    var totalCal: Int { samples.reduce(0) { $0 + Int($1.value) } }
}

// MARK: - 摂取カロリートレンドカード

private struct GoalIntakeTrendCard: View {
    let days: [GoalIntakeDayData]

    // 時間帯別カラー（ポップカラー）
    static func timeColor(hour: Int) -> Color {
        switch hour {
        case 0..<6:   return Color(hex: "#A78BFA")  // ラベンダー（深夜）
        case 6..<10:  return Color(hex: "#FF9600")  // オレンジ（朝）
        case 10..<13: return Color(hex: "#FFCC00")  // イエロー（昼前）
        case 13..<17: return Color(hex: "#58CC02")  // グリーン（昼後）
        case 17..<21: return Color(hex: "#1CB0F6")  // ブルー（夕）
        default:      return Color(hex: "#CE82FF")  // パープル（夜）
        }
    }

    var body: some View {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let pastDays = days.filter { Calendar.current.startOfDay(for: $0.date) < todayStart }
        let maxCal = max(days.map { Double($0.totalCal) }.max() ?? 1, 1)
        let hasData = days.contains { $0.totalCal > 0 }
        let weekTotal = days.reduce(0) { $0 + $1.totalCal }
        let pastWithData = pastDays.filter { $0.totalCal > 0 }
        let avgIntake: Int? = pastWithData.isEmpty ? nil : Int(pastWithData.reduce(0) { $0 + $1.totalCal } / pastWithData.count)

        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color(hex: "#FF4B4B"), Color(hex: "#FF9600")],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 4)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text("🍽️")
                        .font(.system(size: 17 * UIScale.font))
                    Text("食事カロリー")
                        .font(.system(size: 14 * UIScale.font, weight: .black))
                        .foregroundColor(Color.duoDark)
                    Spacer()
                    if let avg = avgIntake, weekTotal > 0 {
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(alignment: .lastTextBaseline, spacing: 3) {
                                Text("平均 \(avg)")
                                    .font(.system(size: 10 * UIScale.font, weight: .semibold))
                                    .foregroundColor(Color.duoSubtitle)
                                Text("/")
                                    .font(.system(size: 10 * UIScale.font))
                                    .foregroundColor(Color.duoSubtitle)
                                Text("計 \(weekTotal)")
                                    .font(.system(size: 16 * UIScale.font, weight: .black))
                                    .foregroundColor(Color(hex: "#FF4B4B"))
                            }
                            Text("kcal")
                                .font(.system(size: 10 * UIScale.font))
                                .foregroundColor(Color.duoSubtitle)
                        }
                    }
                }

                // 時間帯カラー凡例
                HStack(spacing: 8) {
                    ForEach([
                        (6, "朝"), (10, "昼前"), (13, "昼後"), (17, "夕"), (21, "夜")
                    ], id: \.0) { hour, label in
                        HStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(GoalIntakeTrendCard.timeColor(hour: hour))
                                .frame(width: 10, height: 8)
                            Text(label)
                                .font(.system(size: 10 * UIScale.font))
                                .foregroundColor(Color.duoSubtitle)
                        }
                    }
                    Spacer()
                }

                if days.isEmpty {
                    Text("データを読み込み中...")
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                        .frame(maxWidth: .infinity).padding(.vertical, 20)
                } else {
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(days) { day in
                            GoalIntakeDayColumn(day: day, maxCal: maxCal)
                        }
                    }
                    if !hasData {
                        Text("今週の食事記録がありません（Apple Health に記録すると表示されます）")
                            .font(.system(size: 10 * UIScale.font))
                            .foregroundColor(Color.duoSubtitle)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
    }
}

private struct GoalIntakeDayColumn: View {
    let day: GoalIntakeDayData
    let maxCal: Double

    private let maxBarH: CGFloat = 78
    private let cal = Calendar.current

    var body: some View {
        let totalCal = day.totalCal
        let totalH = maxCal > 0 ? maxBarH * CGFloat(totalCal) / CGFloat(maxCal) : 0

        VStack(spacing: 3) {
            Text(totalCal > 0 ? "\(totalCal)" : "")
                .font(.system(size: 8 * UIScale.font, weight: .bold))
                .foregroundColor(Color.duoDark)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(height: 11)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if day.samples.isEmpty {
                    Color.clear
                } else {
                    // 各サンプルを時間帯色で積み上げ（下＝早朝、上＝深夜）
                    let sorted = day.samples.sorted { $0.startDate < $1.startDate }
                    let totalKcal = Double(max(totalCal, 1))
                    VStack(spacing: 1) {
                        ForEach(sorted.reversed()) { sample in
                            let h = totalH * CGFloat(sample.value) / CGFloat(totalKcal)
                            let hour = cal.component(.hour, from: sample.startDate)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(GoalIntakeTrendCard.timeColor(hour: hour))
                                .frame(height: max(h, h > 0 ? 2 : 0))
                        }
                    }
                }
            }
            .frame(height: maxBarH)

            Text(day.dayLabel)
                .font(.system(size: 10 * UIScale.font, weight: .semibold))
                .foregroundColor(Color.duoSubtitle)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - モチベーションバナー

private struct GoalMotivatingBanner: View {
    let weightProgress: Double
    let timeProgress: Double
    let daysRemaining: Int
    var weeklySetTotal: Int = 0
    var todayBalance: Int = 0
    var hasIntakeThisWeek: Bool = false
    var todaySteps: Int = 0
    var todayActiveCalories: Double = 0
    var todayRestingCalories: Double = 0
    var todaySetCount: Int = 0
    var onAction: ((String) -> Void)? = nil

    private var contents: [(message: String, color: Color, action: String?)] {
        // 目標達成・期間終了 → 1件だけ
        if daysRemaining <= 0 {
            return [weightProgress >= 1
                ? ("🏆 目標達成！おめでとうございます！", Color.duoGreen, nil)
                : ("📅 挑戦期間終了。次の目標を設定しよう！", Color.duoSubtitle, nil)]
        }
        if weightProgress >= 1 {
            return [("🏆 目標体重クリア！この調子で維持を続けよう！", Color.duoGreen, nil)]
        }

        var candidates: [(message: String, color: Color, action: String?, priority: Int)] = []

        // ラストスパート
        if daysRemaining <= 3 {
            candidates.append(("🔥 あと\(daysRemaining)日！できることを全力でやろう！ →", Color(hex: "#FF4B4B"), "training", 100))
        } else if daysRemaining <= 7 {
            candidates.append(("🔥 ラストスパート！今週の運動と食事が勝負！ →", Color(hex: "#FF4B4B"), "training", 90))
        }

        // 今日のカロリーオーバー
        if todayBalance > 300 {
            let priority = todayBalance > 700 ? 95 : 82
            candidates.append(("🍽️ 今日\(todayBalance)kcalオーバー。夕食を軽めにしてみよう →", Color(hex: "#FF9600"), "intake", priority))
        }

        // 安静時カロリー（基礎代謝）が低め
        if todayRestingCalories > 0 {
            let hour = Calendar.current.component(.hour, from: Date())
            let dayProgress = min(1.0, max(0.0, Double(hour) / 24.0))
            let expectedResting = 1400.0 * dayProgress
            let isRestingLow = (hour >= 10 && todayRestingCalories < max(450, expectedResting * 0.75))
                || (hour >= 18 && todayRestingCalories < 900)
            if isRestingLow {
                candidates.append(("🔥 安静時カロリー・基礎代謝が低め。筋トレをしよう！ →", Color(hex: "#FF9600"), "training", 88))
            }
        }

        // 今日の運動なし
        if weeklySetTotal == 0 {
            candidates.append(("💪 今週まだ運動なし！今日1セット始めよう →", Color(hex: "#FF9600"), "training", 86))
        } else if todaySetCount == 0 {
            candidates.append(("💪 今日まだ筋トレなし！1セットやってみよう →", Color(hex: "#FF9600"), "training", 78))
        }

        // 歩数少ない
        if todaySteps > 0 && todaySteps < 5000 {
            let stepsStr = todaySteps >= 1000
                ? String(format: "%.1fk", Double(todaySteps) / 1000.0)
                : "\(todaySteps)"
            let priority = todaySteps < 2500 ? 72 : 58
            candidates.append(("🚶 今日の歩数が\(stepsStr)歩。少し散歩してみよう！", Color(hex: "#1CB0F6"), nil, priority))
        }

        // 活動カロリー少ない
        if todayActiveCalories > 0 && todayActiveCalories < 200 {
            let priority = todayActiveCalories < 100 ? 74 : 62
            candidates.append(("🏃 今日の活動カロリーが少なめ。散歩や軽い運動はどうですか？ →", Color(hex: "#FF9600"), "training", priority))
        }

        // 食事記録なし
        if !hasIntakeThisWeek {
            candidates.append(("📝 食事記録を続けよう！記録がダイエットの近道です →", Color(hex: "#1CB0F6"), "intake", 70))
        }

        // 進捗 vs 時間
        let lead = weightProgress - timeProgress
        if lead > 0.1 {
            candidates.append(("🚀 目標ペース超え！週\(weeklySetTotal)セット達成中。絶好調！", Color.duoGreen, nil, 40))
        } else if lead > 0 {
            candidates.append(("💪 順調！週\(weeklySetTotal)セット継続中。この調子で！", Color.duoGreen, nil, 35))
        } else if lead > -0.15 {
            candidates.append(("⚡ もう少しペースアップを。週に1回は有酸素運動を加えよう →", Color(hex: "#FF9600"), "training", 76))
        } else {
            candidates.append(("🏃 ペースが遅れ気味。毎日の食事記録と運動習慣を見直そう →", Color(hex: "#FF4B4B"), "intake", 96))
        }

        return candidates
            .sorted { $0.priority > $1.priority }
            .prefix(1)
            .map { (message: $0.message, color: $0.color, action: $0.action) }
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(contents.enumerated()), id: \.offset) { _, item in
                bannerRow(item)
            }
        }
    }

    private func bannerRow(_ item: (message: String, color: Color, action: String?)) -> some View {
        let (message, color, action) = item
        let label = Text(message)
            .font(.system(size: 12 * UIScale.font, weight: .bold))
            .foregroundColor(color)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(color.opacity(action != nil ? 0.13 : 0.09))
            .cornerRadius(10)
        if let action {
            return AnyView(Button { onAction?(action) } label: { label }.buttonStyle(.plain))
        } else {
            return AnyView(label)
        }
    }
}

// MARK: - GOALページ用カロリー収支バー

private struct GoalCalorieBalanceBarCard: View {
    let totalConsumed: Double
    let intake: Double

    var body: some View {
        let balance = intake - totalConsumed
        let isPositive = balance > 0
        let absBalance = abs(balance)
        let circleSize: CGFloat = 35 + 20 * min(absBalance / 1000.0, 1.0)

        let calLabel: String = {
            if balance < -500 { return "大幅減" }
            if balance < 0 { return "良好" }
            if balance < 300 { return "普通" }
            return "過剰"
        }()
        let calColor: Color = {
            if balance < 0 { return Color.duoGreen }
            if balance < 300 { return Color(hex: "#FFD900") }
            return Color(hex: "#FF4B4B")
        }()

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 10 * UIScale.font))
                    .foregroundColor(Color.duoDark)
                Text("カロリー収支")
                    .font(.system(size: 11 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoDark)
                Spacer()
                if totalConsumed > 0 || intake > 0 {
                    let sign = balance >= 0 ? "+" : ""
                    Text("\(sign)\(Int(balance)) kcal")
                        .font(.system(size: 10 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor(calColor)
                    Text(calLabel)
                        .font(.system(size: 11 * UIScale.font, weight: .bold))
                        .foregroundColor(calColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(calColor.opacity(0.15))
                        .cornerRadius(10)
                }
            }

            GeometryReader { geo in
                barInner(
                    consumed: totalConsumed,
                    intake: intake,
                    isPositive: isPositive,
                    absBalance: absBalance,
                    circleSize: circleSize,
                    geo: geo
                )
            }
            .frame(height: 68)

        }
        .padding(8)
        .background(Color.white.opacity(0.5))
        .cornerRadius(10)
    }

    private func barInner(
        consumed: Double,
        intake: Double,
        isPositive: Bool,
        absBalance: Double,
        circleSize: CGFloat,
        geo: GeometryProxy
    ) -> some View {
        let barWidth = geo.size.width - circleSize - 12
        let maxValue = max(consumed, intake)
        let consumedWidth = max(maxValue > 0 ? (consumed / maxValue) * barWidth * 0.5 : 0, 60)
        let intakeWidth = max(maxValue > 0 ? (intake / maxValue) * barWidth * 0.5 : 0, 60)

        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 0) {
                Text("消費Cal")
                    .font(.system(size: 8 * UIScale.font, weight: .semibold))
                    .foregroundColor(Color.duoGreen)
                    .frame(width: consumedWidth, alignment: .center)
                Text("摂取Cal")
                    .font(.system(size: 8 * UIScale.font, weight: .semibold))
                    .foregroundColor(Color.duoRed)
                    .frame(width: intakeWidth, alignment: .center)
                Spacer()
            }
            HStack(alignment: .center, spacing: 0) {
                consumedBar(consumed: consumed, width: consumedWidth)
                intakeBar(intake: intake, width: intakeWidth)
                Spacer()
                balanceCircle(isPositive: isPositive, absBalance: absBalance, circleSize: circleSize)
                    .padding(.trailing, 8)
            }
        }
    }

    private func consumedBar(consumed: Double, width: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(Color.duoGreen)
            HStack(spacing: 2) {
                Spacer()
                Text("\(Int(consumed))")
                    .font(.system(size: 13 * UIScale.font, weight: .black))
                    .foregroundColor(.white)
                Text("cal")
                    .font(.system(size: 8 * UIScale.font, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.bottom, 1)
            }
        }
        .frame(width: width, height: 36)
        .cornerRadius(6, corners: [.topLeft, .bottomLeft])

    }

    private func intakeBar(intake: Double, width: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(Color.duoRed)
            HStack(spacing: 2) {
                Text("\(Int(intake))")
                    .font(.system(size: 13 * UIScale.font, weight: .black))
                    .foregroundColor(.white)
                Text("cal")
                    .font(.system(size: 8 * UIScale.font, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.bottom, 1)
                Spacer()
            }
        }
        .frame(width: width, height: 36)
        .cornerRadius(6, corners: [.topRight, .bottomRight])
    }

    private func balanceCircle(isPositive: Bool, absBalance: Double, circleSize: CGFloat) -> some View {
        let weightChangeG = Int(absBalance / 7200.0 * 1000)
        return VStack(alignment: .trailing, spacing: 2) {
            ZStack {
                Circle().fill(isPositive ? Color.red : Color.duoGreen)
                    .frame(width: circleSize, height: circleSize)
                    .shadow(color: (isPositive ? Color.red : Color.duoGreen).opacity(0.3), radius: 2, y: 1)
                VStack(spacing: -1) {
                    Text(isPositive ? "+" : "-")
                        .font(.system(size: circleSize * 0.20, weight: .bold))
                        .foregroundColor(.white)
                    Text("\(Int(absBalance))")
                        .font(.system(size: circleSize * 0.30, weight: .black))
                        .foregroundColor(.white)
                    Text("cal")
                        .font(.system(size: circleSize * 0.13))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            weightPrediction(isPositive: isPositive, absBalance: absBalance, grams: weightChangeG)
        }
    }

    @ViewBuilder
    private func weightPrediction(isPositive: Bool, absBalance: Double, grams: Int) -> some View {
        if isPositive {
            HStack(spacing: 1) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 6 * UIScale.font))
                    .foregroundColor(.red)
                Text("+\(grams)g")
                    .font(.system(size: 7 * UIScale.font, weight: .bold))
                    .foregroundColor(.red)
            }
        } else if absBalance > 0 {
            HStack(spacing: 1) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 6 * UIScale.font))
                    .foregroundColor(Color.duoGreen)
                Text("-\(grams)g")
                    .font(.system(size: 7 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoGreen)
            }
        }
    }
}

// MARK: - FITフィード カード（体重計測の写真）

// WeightFeedCard は Views/Components/SharedEduViews.swift で共有定義（GoalView と共通）

// MARK: - FITフィード 詳細シート

struct GoalingoWeightFeedDetailSheet: View {
    let item: EduLogHistoryItem
    var embedded: Bool = false
    @StateObject private var eduLogManager = EduLogManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isPublicInTomo: Bool = false

    private static let fullFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月d日 (E) HH:mm"; return f
    }()

    var body: some View {
        if embedded {
            scrollContent
        } else {
            NavigationView {
                scrollContent
                    .navigationTitle("体重ログ")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") { dismiss() }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var scrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if let thumb = item.thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .cornerRadius(16)
                        .overlay(alignment: .bottom) {
                            HStack {
                                Text(GoalingoWeightFeedDetailSheet.fullFmt.string(from: item.timestamp))
                                    .font(.system(size: 12 * UIScale.font, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Color.black.opacity(0.50))
                                    .clipShape(Capsule())
                                Spacer()
                                Text(dayLabel(for: item.timestamp))
                                    .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Color.black.opacity(0.50))
                                    .clipShape(Capsule())
                            }
                            .padding(10)
                        }
                }

                HStack(spacing: 12) {
                    metric(emoji: "⚖️", label: "体重",
                           value: item.weightKg != nil ? String(format: "%.1f", item.weightKg!) : "—",
                           unit: "kg", color: Color(hex: "#1CB0F6"))
                    metric(emoji: "📉", label: "体脂肪率",
                           value: item.bodyFatPercent != nil ? String(format: "%.1f", item.bodyFatPercent!) : "—",
                           unit: "%", color: Color(hex: "#CE82FF"))
                }

                if !item.comment.isEmpty {
                    Text(item.comment)
                        .font(.system(size: 15 * UIScale.font))
                        .foregroundColor(Color.duoDark)
                }

                weightTomoPublicToggle
            }
            .padding(16)
        }
        .onAppear { isPublicInTomo = item.isPublic }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var weightTomoPublicToggle: some View {
        HStack(spacing: 8) {
            Image(systemName: isPublicInTomo ? "person.2.fill" : "person.2")
                .font(.system(size: 13 * UIScale.font, weight: .semibold))
                .foregroundColor(isPublicInTomo ? Color.duoBlue : Color(.systemGray3))
            Text("TOMOフィードに公開")
                .font(.system(size: 12 * UIScale.font, weight: .semibold))
                .foregroundColor(Color.duoDark)
            Spacer()
            Toggle("", isOn: Binding(
                get: { isPublicInTomo },
                set: { v in
                    isPublicInTomo = v
                    eduLogManager.setPublic(id: item.id, isPublic: v)
                }
            ))
            .labelsHidden()
            .tint(Color.duoBlue)
            .scaleEffect(0.85)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private func metric(emoji: String, label: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(emoji).font(.system(size: 22 * UIScale.font))
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24 * UIScale.font, weight: .black, design: .rounded))
                    .foregroundColor(color)
                Text(unit)
                    .font(.system(size: 11 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoSubtitle)
            }
            Text(label)
                .font(.system(size: 11 * UIScale.font, weight: .semibold))
                .foregroundColor(Color.duoSubtitle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(color.opacity(0.08))
        .cornerRadius(14)
    }
}

// MARK: - Swipeable FIT feed sheet

struct GoalingoSwipeableWeightFeedSheet: View {
    let items: [EduLogHistoryItem]
    let startIndex: Int
    @State private var page: Int
    @Environment(\.dismiss) private var dismiss

    init(items: [EduLogHistoryItem], startIndex: Int) {
        self.items = items
        self.startIndex = startIndex
        _page = State(initialValue: startIndex)
    }

    var body: some View {
        NavigationView {
            TabView(selection: $page) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    GoalingoWeightFeedDetailSheet(item: item, embedded: true)
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .always : .never))
            .navigationTitle(items.count > 1 ? "\(page + 1) / \(items.count)" : "体重ログ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .onAppear {
                let target = startIndex
                DispatchQueue.main.async { page = target }
            }
        }
    }
}

#Preview {
    GoalingoView(selectedTab: .constant(7), showRecordMenu: .constant(false))
        .environmentObject(AuthenticationManager.shared)
}
