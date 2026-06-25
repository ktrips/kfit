import SwiftUI

struct GoalView: View {
    @Binding var selectedTab: Int
    @Binding var showRecordMenu: Bool
    // V1: 共有シングルトンは kfitApp から EnvironmentObject で受け取る
    @EnvironmentObject private var healthKit: HealthKitManager
    @EnvironmentObject private var dietManager: DietGoalManager
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject private var timeSlotManager: TimeSlotManager
    @EnvironmentObject private var plus: PlusManager
    @State private var showDietGoalSettings = false
    @State private var showCharts = false
    @State private var showActivityHistory = false
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
    @State private var selectedWeightFeedItem: EduLogHistoryItem? = nil
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
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        goalHeroCard
                        if showCharts {
                            weightChartCard
                                .transition(.opacity)
                            bodyFatChartCard
                                .transition(.opacity)
                        }
                        fitingoTrainingButton
                        todayActivityWithHistoryCard
                        if plus.isPlus {
                            progressCard
                            HStack(spacing: 6) {
                                Image(systemName: "chart.bar.doc.horizontal.fill")
                                    .font(.system(size: 14 * UIScale.font, weight: .bold))
                                    .foregroundColor(Color.duoGreen)
                                Text("週間実績")
                                    .font(.system(size: 15 * UIScale.font, weight: .black))
                                    .foregroundColor(Color.duoDark)
                                Spacer()
                            }
                            .padding(.horizontal, 4)
                            .padding(.bottom, -4)
                            weeklyBurnCard
                            intakeTrendCard
                            weeklyCalorieCard
                        } else {
                            PlusLockedSection(
                                features: [
                                    "目標プランレポート",
                                    "週間実績（燃焼カロリー）",
                                    "摂取カロリー推移",
                                    "週間カロリー分析"
                                ],
                                onUpgrade: { showPlusViewFromFit = true }
                            )
                        }
                        weightFeedSection
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }
                .refreshable {
                    loadTodayWeekdayGoal()
                    await timeSlotManager.loadTodaySettings()
                    await healthKit.fetchBodyMassHistory(days: 30)
                    await healthKit.fetchBodyFatHistory(days: 30)
                    await healthKit.fetchGoalHealth()
                    await healthKit.fetchWeeklyBurnData()
                    await healthKit.fetchWeeklyDietarySamples()
                    todayExercises = await authManager.getTodayExercises()
                    todayWorkoutSessions = await healthKit.fetchTodayWorkoutSessions()
                    weeklySetCounts = await authManager.fetchWeeklySetCounts()
                    weeklyIntakeData = await authManager.fetchWeeklyIntakeData()
                }
            }
            .navigationBarHidden(true)
            .safeAreaInset(edge: .top, spacing: 0) { fitHeader }
            .sheet(isPresented: $showPlusViewFromFit) { PlusView() }
            .sheet(isPresented: $showDietGoalSettings) {
                NavigationView { DietGoalSettingsView() }
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
            .sheet(item: $selectedWeightFeedItem) { item in
                WeightFeedDetailSheet(item: item)
            }
            .task {
                // V25: 相互依存のない非同期タスクを async let で並列実行
                loadTodayWeekdayGoal()
                await timeSlotManager.loadTodaySettings()
                rebuildTrainingTotals()

                async let bodyMass: Void = healthKit.fetchBodyMassHistory(days: 30)
                async let bodyFat: Void  = healthKit.fetchBodyFatHistory(days: 30)
                async let burnData: Void = healthKit.fetchWeeklyBurnData()
                async let dietData: Void = healthKit.fetchWeeklyDietarySamples()
                async let exercises      = authManager.getTodayExercises()
                async let workouts       = healthKit.fetchTodayWorkoutSessions()
                async let setCountsData  = authManager.fetchWeeklySetCounts()
                async let intakeData     = authManager.fetchWeeklyIntakeData()

                if healthKit.weeklyCalorieData.isEmpty {
                    async let goalHealth: Void = healthKit.fetchGoalHealth()
                    _ = await (bodyMass, bodyFat, burnData, dietData, goalHealth)
                } else {
                    _ = await (bodyMass, bodyFat, burnData, dietData)
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
        let totalTraining = totalTrainingSets
        let totalTrainingGoal = totalTrainingGoalSets
        let todayWeightKg = healthKit.todayBodyMassRecord?.kg
        let stepsStr: String = {
            let s = healthKit.todaySteps
            guard s > 0 else { return "—" }
            return s >= 1000 ? String(format: "%.1fk", Double(s) / 1000.0) : "\(s)"
        }()
        let trainingGoalDone = totalTrainingGoal > 0 && totalTraining >= totalTrainingGoal
        return ZStack {
            LinearGradient(
                colors: [Color.duoGreen, Color(red: 0.18, green: 0.58, blue: 0.0)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea(edges: .top)
            HStack(spacing: 0) {
                Text("FIT")
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
                if dailyFixedGoals.weightEnabled {
                    Spacer(minLength: 6)
                    Button {
                        showWeightPhotoLog = true
                    } label: {
                        HStack(spacing: 2) {
                            Text("⚖️").font(.system(size: 15 * UIScale.font))
                            Text(todayWeightKg != nil ? "\(Int(todayWeightKg!.rounded()))" : "—")
                                .font(.system(size: 13 * UIScale.font, weight: .bold))
                                .foregroundColor(todayWeightKg != nil ? Color(red: 1.0, green: 0.95, blue: 0.5) : .white)
                                .lineLimit(1)
                            Image(systemName: "camera.fill")
                                .font(.system(size: 9 * UIScale.font))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 6)
                HStack(spacing: 2) {
                    Text("💪").font(.system(size: 15 * UIScale.font))
                    Text(totalTrainingGoal > 0 ? "\(totalTraining)/\(totalTrainingGoal)" : "\(totalTraining)")
                        .font(.system(size: 13 * UIScale.font, weight: .bold))
                        .foregroundColor(trainingGoalDone ? Color(red: 1.0, green: 0.95, blue: 0.5) : .white)
                        .lineLimit(1)
                }
                .fixedSize()
                Spacer(minLength: 6)
                HStack(spacing: 2) {
                    Text("👟").font(.system(size: 15 * UIScale.font))
                    Text(stepsStr)
                        .font(.system(size: 13 * UIScale.font, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .fixedSize()
                Spacer(minLength: 6)
                HStack(spacing: 2) {
                    Text("🔥").font(.system(size: 15 * UIScale.font))
                    Text(healthKit.todayTotalCalories > 0 ? "\(Int(healthKit.todayTotalCalories))" : "—")
                        .font(.system(size: 13 * UIScale.font, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if healthKit.todayTotalCalories > 0 {
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
        let totalTraining = totalTrainingSets
        let totalTrainingGoal = totalTrainingGoalSets
        let todayWeightKg = healthKit.todayBodyMassRecord?.kg
        let stepsStr: String = {
            let s = healthKit.todaySteps
            guard s > 0 else { return "—" }
            return s >= 1000 ? String(format: "%.1fk", Double(s) / 1000.0) : "\(s)"
        }()
        return HStack(spacing: 6) {
            Text("FIT")
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
                Text("💪").font(.system(size: 13 * UIScale.font))
                Text(totalTrainingGoal > 0 ? "\(totalTraining)/\(totalTrainingGoal)" : "\(totalTraining)")
                    .font(.system(size: 9 * UIScale.font, weight: .bold))
                    .foregroundColor(totalTrainingGoal > 0 && totalTraining >= totalTrainingGoal ? fitColor : Color.duoDark)
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
                        Text("Fit")
                            .foregroundColor(Color(red: 1.0, green: 0.29, blue: 0.10))
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

    // MARK: - ヒーローカード（現状 vs 目標）

    private var goalHeroCard: some View {
        let goal       = dietManager.settings
        let current    = healthKit.latestBodyMass
        let currentFat = healthKit.latestBodyFatPercentage
        let weightDiff = (current > 0 && goal.targetWeight > 0) ? current - goal.targetWeight : nil
        let cal        = Calendar.current

        // 体重達成度（スタート体重設定時はそこからの進捗、未設定時は現在と目標の差から推定）
        let weightProgress: Double = {
            if goal.hasStartStats && goal.startWeight > 0 && goal.targetWeight > 0 && current > 0 {
                let total = goal.startWeight - goal.targetWeight
                guard total != 0 else { return 1 }
                return min(1, max(0, (goal.startWeight - current) / total))
            }
            guard let diff = weightDiff, current > 0, goal.targetWeight > 0 else { return 0 }
            let sw = max(current, goal.targetWeight + diff)
            let tc = sw - goal.targetWeight
            guard tc > 0 else { return 1 }
            return min(1, max(0, (sw - current) / tc))
        }()

        // 期間進捗（スタート日〜目標日）
        let totalDays: Int = goal.hasStartStats
            ? max(0, cal.dateComponents([.day],
                from: cal.startOfDay(for: goal.startDate),
                to:   cal.startOfDay(for: goal.targetDate)).day ?? 0) : 0
        let elapsedDays: Int = goal.hasStartStats
            ? max(0, cal.dateComponents([.day],
                from: cal.startOfDay(for: goal.startDate),
                to:   cal.startOfDay(for: Date())).day ?? 0) : 0
        let timeProgress: Double = totalDays > 0 ? min(1, Double(elapsedDays) / Double(totalDays)) : 0
        let daysRemaining = max(0, cal.dateComponents([.day], from: Date(), to: goal.targetDate).day ?? 0)

        // バナー用データ
        let todayKeyB = GoalView.yyyyMMddFmt.string(from: Date())
        let weeklySetTotal = weeklySetCounts.values.reduce(0, +)
        let todayHKDay = healthKit.weeklyCalorieData.first { GoalView.yyyyMMddFmt.string(from: $0.date) == todayKeyB }
        let todayBalance = todayHKDay.map { Int($0.consumed) - Int($0.burned) } ?? 0
        let hasIntakeThisWeek = weeklyIntakeData.values.contains { $0.values.contains { $0 > 0 } }
        let todayBurnDay = healthKit.weeklyBurnData.first { GoalView.yyyyMMddFmt.string(from: $0.date) == todayKeyB }
        let todaySteps = todayBurnDay?.steps ?? 0
        let todayActiveCalories = todayBurnDay?.activeCalories ?? 0.0
        let todayRestingCalories = healthKit.todayRestingCalories > 0
            ? healthKit.todayRestingCalories
            : (todayBurnDay?.restingCalories ?? 0.0)
        let todaySetCount = weeklySetCounts[todayKeyB] ?? 0

        return VStack(spacing: 0) {
            LinearGradient(
                colors: [Color(hex: "#58CC02"), Color(hex: "#1CB0F6")],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 4)

            if goal.hasStartStats {
                GoalTimelineStrip(
                    startWeight: goal.startWeight > 0 ? formatCompactKg(goal.startWeight) : "—",
                    startBodyFat: goal.startBodyFatPercent > 0 ? formatCompactPercent(goal.startBodyFatPercent) : nil,
                    currentWeight: current > 0 ? formatCompactKg(current) : "—",
                    currentBodyFat: currentFat > 0 ? formatCompactPercent(currentFat) : nil,
                    goalWeight: goal.targetWeight > 0 ? formatCompactKg(goal.targetWeight) : "—",
                    goalBodyFat: goal.hasBodyFatTarget && goal.targetBodyFatPercent > 0
                        ? formatCompactPercent(goal.targetBodyFatPercent) : nil,
                    startToCurrentDelta: goal.startWeight > 0 && current > 0
                        ? formatSignedDelta(current - goal.startWeight) : nil,
                    currentToGoalDelta: current > 0 && goal.targetWeight > 0
                        ? formatSignedDelta(goal.targetWeight - current) : nil,
                    timeProgress: timeProgress,
                    daysRemaining: daysRemaining,
                    startDate: goal.startDate,
                    targetDate: goal.targetDate,
                    onGearTap: { showDietGoalSettings = true }
                )
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
            }

            if goal.targetWeight > 0 && current > 0 {
                GoalMotivatingBanner(
                    weightProgress: weightProgress,
                    timeProgress: timeProgress,
                    daysRemaining: daysRemaining,
                    weeklySetTotal: weeklySetTotal,
                    todayBalance: todayBalance,
                    hasIntakeThisWeek: hasIntakeThisWeek,
                    todaySteps: todaySteps,
                    todayActiveCalories: todayActiveCalories,
                    todayRestingCalories: todayRestingCalories,
                    todaySetCount: todaySetCount,
                    onAction: { action in
                        switch action {
                        case "training":
                            NotificationCenter.default.post(name: .requestStartTraining, object: nil)
                        case "intake":
                            selectedTab = 3
                        default: break
                        }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            // グラフ展開ボタン
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
                .padding(.horizontal, 16).padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.07), radius: 8, y: 3)
    }

    private func refreshWatchData() {
        guard !isRefreshingWatchData else { return }
        isRefreshingWatchData = true
        Task {
            await healthKit.fetchGoalHealth(force: true)
            await healthKit.fetchBodyMassHistory(days: 30)
            await healthKit.fetchBodyFatHistory(days: 30)
            await healthKit.fetchWeeklyBurnData()
            await healthKit.fetchWeeklyDietarySamples()
            let workouts = await healthKit.fetchTodayWorkoutSessions()
            await MainActor.run {
                todayWorkoutSessions = workouts
                isRefreshingWatchData = false
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        GoalView.yyyyMdFmt.string(from: date)
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
                    Text(showActivityHistory ? "アクティビティ履歴を閉じる" : "アクティビティ履歴を表示")
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
        GoalView.HHmmFmt.string(from: date)
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

    private var fitingoTrainingButton: some View {
        let totalTraining = totalTrainingSets
        let totalTrainingGoal = totalTrainingGoalSets
        let done = totalTrainingGoal > 0 && totalTraining >= totalTrainingGoal
        let bgColors: [Color] = done
            ? [Color(hex: "#E8FFB8"), Color(hex: "#6FE8D8")]
            : [Color(hex: "#F5FFF3"), Color(hex: "#DDFBFF")]
        let imageName = done ? "fitingo_button_mascot" : "fitingo_jdi"
        let message: String = done
            ? "今日の目標達成！おめでとう 🎉"
            : totalTrainingGoal > 0
                ? "あと\(totalTrainingGoal - totalTraining)セット完了しよう！"
                : "Fitingoトレーニングを始めよう！"

        return Button {
            NotificationCenter.default.post(name: .requestStartTraining, object: nil)
        } label: {
            ZStack {
                LinearGradient(colors: bgColors, startPoint: .topLeading, endPoint: .bottomTrailing)

                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                LinearGradient(
                    colors: [.clear, Color.black.opacity(done ? 0.16 : 0.36)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack {
                    Spacer()
                    Text(message)
                        .font(.system(size: 16 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color.black.opacity(0.42))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
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

    // MARK: - 週間消費カロリーカード

    private var weeklyBurnCard: some View {
        var data = healthKit.weeklyBurnData
        for i in data.indices {
            let key = GoalView.yyyyMMddFmt.string(from: data[i].date)
            data[i].setCount = weeklySetCounts[key] ?? 0
        }
        return GoalWeeklyBurnCard(data: data)
    }

    // MARK: - 摂取カロリートレンドカード

    private var intakeTrendCard: some View {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let today = Date()
        let weekStart = cal.date(
            from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        ) ?? today

        // HealthKit サンプルを日付キーでグルーピング
        var samplesByKey: [String: [DietarySample]] = [:]
        for sample in healthKit.weeklyDietarySamples {
            let key = GoalView.yyyyMMddFmt.string(from: sample.startDate)
            samplesByKey[key, default: []].append(sample)
        }

        // 水分は Firestore から
        let days: [GoalIntakeDayData] = (0..<7).compactMap { i in
            guard let dayStart = cal.date(byAdding: .day, value: i, to: weekStart) else { return nil }
            let key = GoalView.yyyyMMddFmt.string(from: dayStart)
            let intake = weeklyIntakeData[key] ?? [:]
            return GoalIntakeDayData(
                date: dayStart,
                dayLabel: GoalView.dayOfWeekFmt.string(from: dayStart),
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
        let allLogs   = eduLog.history.filter { $0.activityName == "体重ログ" && $0.thumbnailData != nil }
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
                    ForEach(displayed) { item in
                        WeightFeedCard(item: item)
                            .onTapGesture { selectedWeightFeedItem = item }
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
            (i % step == 0 || i == dates.count - 1) ? GoalView.MdFmt.string(from: d) : ""
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

    private let restingColor = Color(hex: "#16A34A")
    private let activeColor  = Color(hex: "#4ADE80")
    private let lineColor    = Color(hex: "#1CB0F6")
    private let maxBarH: CGFloat = 74

    var body: some View {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let pastData   = data.filter { Calendar.current.startOfDay(for: $0.date) < todayStart }
        let maxTotal   = max(data.map { $0.totalCalories }.max() ?? 1, 1)
        let maxMinutes = max(data.map { $0.exerciseMinutes }.max() ?? 1, 1)
        let weekTotal  = Int(data.reduce(0) { $0 + $1.totalCalories })
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
                        Text("総燃焼カロリー")
                            .font(.system(size: 14 * UIScale.font, weight: .black))
                            .foregroundColor(Color.duoDark)
                        Spacer()
                        if let avg = avgBurn, weekTotal > 0 {
                            VStack(alignment: .trailing, spacing: 2) {
                                HStack(alignment: .lastTextBaseline, spacing: 3) {
                                    Text("平均 \(avg)")
                                        .font(.system(size: 10 * UIScale.font, weight: .semibold))
                                        .foregroundColor(Color.duoSubtitle)
                                    Text("/").font(.system(size: 10 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                                    Text("計 \(weekTotal)")
                                        .font(.system(size: 16 * UIScale.font, weight: .black))
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
                            // 折れ線の凡例シンボル
                            ZStack {
                                Rectangle().fill(lineColor).frame(width: 12, height: 1.5)
                                Circle().fill(lineColor).frame(width: 5, height: 5)
                            }
                            .frame(width: 12, height: 8)
                            Text("運動時間").font(.system(size: 10 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                        }
                        Spacer()
                    }

                    if data.isEmpty {
                        Text("データを読み込み中...")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                            .frame(maxWidth: .infinity).padding(.vertical, 20)
                    } else {
                        VStack(spacing: 3) {
                            // カロリー値ラベル行
                            HStack(spacing: 0) {
                                ForEach(data) { day in
                                    Text(day.totalCalories > 0 ? "\(Int(day.totalCalories))" : "")
                                        .font(.system(size: 8 * UIScale.font, weight: .bold))
                                        .foregroundColor(Color.duoDark)
                                        .lineLimit(1).minimumScaleFactor(0.6)
                                        .frame(maxWidth: .infinity).frame(height: 11)
                                }
                            }

                            // ── 棒グラフ ＋ 折れ線グラフオーバーレイ ──────────
                            ZStack(alignment: .bottom) {
                                // 積み上げ棒
                                HStack(alignment: .bottom, spacing: 0) {
                                    ForEach(data) { day in
                                        stackedBar(day: day, maxTotal: maxTotal)
                                    }
                                }

                                // 運動時間 折れ線オーバーレイ
                                GeometryReader { geo in
                                    exerciseLineOverlay(
                                        data: data, size: geo.size, maxMinutes: maxMinutes)
                                }
                            }
                            .frame(height: maxBarH)

                            // 曜日・メタ情報ラベル行
                            HStack(spacing: 0) {
                                ForEach(data) { day in columnMeta(day) }
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

    // ── 積み上げ棒（1日分）────────────────────────────────────────────────
    private func stackedBar(day: DailyBurnSummary, maxTotal: Double) -> some View {
        let totalH = maxTotal > 0 ? maxBarH * CGFloat(day.totalCalories) / CGFloat(maxTotal) : 0
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

    // ── 折れ線グラフオーバーレイ（GeometryReader の中で使用）────────────
    private func exerciseLineOverlay(data: [DailyBurnSummary],
                                     size: CGSize,
                                     maxMinutes: Double) -> some View {
        let count  = max(data.count, 1)
        let colW   = size.width / CGFloat(count)
        let pts: [(idx: Int, pt: CGPoint)] = data.enumerated().compactMap { i, day in
            guard day.exerciseMinutes > 0 else { return nil }
            let x = colW * CGFloat(i) + colW / 2
            let y = size.height * (1.0 - CGFloat(day.exerciseMinutes) / CGFloat(maxMinutes))
            return (i, CGPoint(x: x, y: y))
        }
        return ZStack {
            if pts.count >= 2 {
                Path { path in
                    path.move(to: pts[0].pt)
                    for vp in pts.dropFirst() { path.addLine(to: vp.pt) }
                }
                .stroke(lineColor,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            ForEach(pts, id: \.idx) { vp in
                // ドット
                Circle().fill(lineColor).frame(width: 5, height: 5).position(vp.pt)
                // 分数ラベル（ドットの上）
                Text("\(Int(data[vp.idx].exerciseMinutes))m")
                    .font(.system(size: 8 * UIScale.font, weight: .bold))
                    .foregroundColor(lineColor)
                    .position(x: vp.pt.x, y: max(vp.pt.y - 9, 5))
            }
        }
    }

    // ── 曜日・メタ情報（1日分）──────────────────────────────────────────
    private func columnMeta(_ day: DailyBurnSummary) -> some View {
        VStack(spacing: 2) {
            Text(day.dayLabel)
                .font(.system(size: 10 * UIScale.font, weight: .semibold))
                .foregroundColor(Color.duoSubtitle)
            HStack(spacing: 2) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 8 * UIScale.font))
                    .foregroundColor(day.setCount > 0 ? Color.duoGreen : Color(.systemGray4))
                Text(day.setCount > 0 ? "\(day.setCount)" : "-")
                    .font(.system(size: 8 * UIScale.font, weight: .bold))
                    .foregroundColor(day.setCount > 0 ? Color.duoGreen : Color(.systemGray4))
            }
            HStack(spacing: 2) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 8 * UIScale.font))
                    .foregroundColor(day.steps > 0 ? Color(hex: "#FF9600") : Color(.systemGray4))
                Text(day.steps > 0
                    ? (day.steps >= 1000 ? String(format: "%.1fk", Double(day.steps) / 1000.0) : "\(day.steps)")
                    : "-")
                    .font(.system(size: 8 * UIScale.font, weight: .bold))
                    .foregroundColor(day.steps > 0 ? Color(hex: "#FF9600") : Color(.systemGray4))
            }
        }
        .frame(maxWidth: .infinity)
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

// MARK: - タイムラインストリップ

private struct GoalTimelineStrip: View {
    let startWeight: String
    let startBodyFat: String?
    let currentWeight: String
    let currentBodyFat: String?
    let goalWeight: String
    let goalBodyFat: String?
    let startToCurrentDelta: String?
    let currentToGoalDelta: String?
    let timeProgress: Double
    let daysRemaining: Int
    var startDate: Date? = nil
    var targetDate: Date? = nil
    var onGearTap: (() -> Void)? = nil

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    private var daysColor: Color {
        if daysRemaining <= 7 { return Color(hex: "#FF4B4B") }
        if daysRemaining <= 30 { return Color(hex: "#FF9600") }
        return Color(hex: "#1CB0F6")
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 2) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 8 * UIScale.font))
                            .foregroundColor(Color.duoSubtitle)
                        Text("スタート")
                            .font(.system(size: 9 * UIScale.font, weight: .semibold))
                            .foregroundColor(Color.duoSubtitle)
                    }
                    if let d = startDate {
                        Text("(\(GoalTimelineStrip.dateFormatter.string(from: d)))")
                            .font(.system(size: 9 * UIScale.font, weight: .bold, design: .rounded))
                            .foregroundColor(Color.duoSubtitle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 2) {
                    Text("今日")
                        .font(.system(size: 9 * UIScale.font, weight: .bold))
                        .foregroundColor(Color(hex: "#1CB0F6"))
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        HStack(alignment: .lastTextBaseline, spacing: 0) {
                            Text("あと")
                                .font(.system(size: 9 * UIScale.font, weight: .black, design: .rounded))
                                .foregroundColor(daysColor)
                            Text("\(daysRemaining)")
                                .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                                .foregroundColor(daysColor)
                            Text("日")
                                .font(.system(size: 9 * UIScale.font, weight: .black, design: .rounded))
                                .foregroundColor(daysColor)
                        }
                        Text("(\(Int(timeProgress * 100))%)")
                            .font(.system(size: 8 * UIScale.font, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "#1CB0F6").opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 2) {
                        if let gearTap = onGearTap {
                            Button(action: gearTap) {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 10 * UIScale.font))
                                    .foregroundColor(Color.duoGreen)
                            }
                            .buttonStyle(.plain)
                        }
                        Text("ゴール")
                            .font(.system(size: 9 * UIScale.font, weight: .semibold))
                            .foregroundColor(Color.duoGreen)
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 8 * UIScale.font))
                            .foregroundColor(Color.duoGreen)
                    }
                    if let d = targetDate {
                        Text("(\(GoalTimelineStrip.dateFormatter.string(from: d)))")
                            .font(.system(size: 9 * UIScale.font, weight: .bold, design: .rounded))
                            .foregroundColor(Color.duoGreen)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let rawX = w * CGFloat(max(0, min(1, timeProgress)))
                let dotX = max(6, min(w - 6, rawX))

                ZStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(.systemGray5))
                        .frame(width: w, height: 5)
                        .position(x: w / 2, y: h / 2)

                    if rawX > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#1A7A3F"), Color(hex: "#58CC02")],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: dotX, height: 5)
                            .position(x: dotX / 2, y: h / 2)
                    }

                    Circle()
                        .fill(Color(hex: "#1CB0F6"))
                        .frame(width: 13, height: 13)
                        .shadow(color: Color(hex: "#1CB0F6").opacity(0.35), radius: 4)
                        .position(x: dotX, y: h / 2)
                }
            }
            .frame(height: 13)

            HStack(alignment: .center, spacing: 4) {
                VStack(alignment: .center, spacing: 2) {
                    outlinedWeightText(startWeight)
                        .frame(height: 54, alignment: .center)
                    if let startBodyFat {
                        Text(startBodyFat)
                            .font(.system(size: 11 * UIScale.font, weight: .bold, design: .rounded))
                            .foregroundColor(Color.duoSubtitle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                deltaArrowColumn(delta: startToCurrentDelta, color: Color.duoGreen)
                    .padding(.trailing, 6)

                VStack(alignment: .center, spacing: 2) {
                    weightText(currentWeight, size: 38, color: Color(hex: "#1CB0F6"), kgSize: 9)
                        .frame(height: 54, alignment: .center)
                    if let currentBodyFat {
                        Text(currentBodyFat)
                            .font(.system(size: 12 * UIScale.font, weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: "#1CB0F6").opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                deltaArrowColumn(delta: currentToGoalDelta, color: Color.duoGreen)
                    .padding(.leading, 6)

                VStack(alignment: .center, spacing: 2) {
                    weightText(goalWeight, size: 31, color: Color.duoGreen, kgSize: 9)
                        .frame(height: 54, alignment: .center)
                    if let goalBodyFat {
                        Text(goalBodyFat)
                            .font(.system(size: 11 * UIScale.font, weight: .bold, design: .rounded))
                            .foregroundColor(Color.duoGreen.opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func deltaArrowColumn(delta: String?, color: Color) -> some View {
        VStack(spacing: 1) {
            Image(systemName: "arrow.right")
                .font(.system(size: 12 * UIScale.font, weight: .black))
                .foregroundColor(color)
            if let delta {
                Text(delta)
                    .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                    .foregroundColor(color)
                Text("kg")
                    .font(.system(size: 7 * UIScale.font, weight: .bold, design: .rounded))
                    .foregroundColor(color.opacity(0.75))
            }
        }
        .frame(minWidth: 28)
        .padding(.top, 18)
    }

    private func outlinedWeightText(_ value: String) -> some View {
        VStack(spacing: -2) {
            ZStack {
                ForEach([-1, 0, 1], id: \.self) { x in
                    ForEach([-1, 0, 1], id: \.self) { y in
                        if x != 0 || y != 0 {
                            weightNumberText(value, size: 31, decimalSize: 17, color: Color.duoDark)
                                .offset(x: CGFloat(x) * 0.5, y: CGFloat(y) * 0.5)
                        }
                    }
                }
                weightNumberText(value, size: 31, decimalSize: 17, color: .white)
            }
            Text("kg")
                .font(.system(size: 9 * UIScale.font, weight: .bold, design: .rounded))
                .foregroundColor(Color.duoSubtitle)
        }
    }

    private func weightText(_ value: String, size: CGFloat, color: Color, kgSize: CGFloat) -> some View {
        VStack(spacing: -2) {
            weightNumberText(value, size: size, decimalSize: size * 0.58, color: color)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: true, vertical: false)
            Text("kg")
                .font(.system(size: kgSize, weight: .bold, design: .rounded))
                .foregroundColor(color.opacity(0.75))
        }
    }

    private func weightNumber(_ value: String) -> String {
        value.replacingOccurrences(of: "kg", with: "")
    }

    private func weightNumberText(_ value: String, size: CGFloat, decimalSize: CGFloat, color: Color) -> Text {
        let number = weightNumber(value)
        let parts = number.split(separator: ".", maxSplits: 1).map(String.init)
        let integer = parts.first ?? number
        let decimal = parts.count > 1 ? "." + parts[1] : ""
        return Text(integer)
            .font(.system(size: size, weight: .black, design: .rounded))
            .foregroundColor(color)
        + Text(decimal)
            .font(.system(size: decimalSize, weight: .black, design: .rounded))
            .foregroundColor(color)
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

private struct WeightFeedCard: View {
    let item: EduLogHistoryItem

    private static let mdFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d (E)"; return f
    }()

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let thumb = item.thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(colors: [Color(hex: "#1CB0F6"), Color(hex: "#58CC02")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(Text("⚖️").font(.system(size: 44 * UIScale.font)))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150)
            .clipped()

            VStack(alignment: .leading, spacing: 3) {
                Text(WeightFeedCard.mdFmt.string(from: item.timestamp))
                    .font(.system(size: 10 * UIScale.font, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.5), radius: 2)
                HStack(spacing: 6) {
                    HStack(spacing: 2) {
                        Text("⚖️").font(.system(size: 10 * UIScale.font))
                        Text(item.weightKg != nil ? String(format: "%.1f", item.weightKg!) : "—")
                            .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("kg")
                            .font(.system(size: 8 * UIScale.font, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    if let fat = item.bodyFatPercent {
                        HStack(spacing: 2) {
                            Text("📉").font(.system(size: 10 * UIScale.font))
                            Text(String(format: "%.1f", fat))
                                .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                            Text("%")
                                .font(.system(size: 8 * UIScale.font, weight: .bold))
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                    Spacer()
                }
                .shadow(color: .black.opacity(0.5), radius: 2)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [.clear, Color.black.opacity(0.65)],
                               startPoint: .top, endPoint: .bottom)
            )
        }
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.14), radius: 6, x: 0, y: 3)
    }
}

// MARK: - FITフィード 詳細シート

struct WeightFeedDetailSheet: View {
    let item: EduLogHistoryItem
    @StateObject private var eduLogManager = EduLogManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isPublicInTomo: Bool = false

    private static let fullFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月d日 (E) HH:mm"; return f
    }()

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if let thumb = item.thumbnail {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .cornerRadius(16)
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

                    Text(WeightFeedDetailSheet.fullFmt.string(from: item.timestamp))
                        .font(.system(size: 12 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)

                    weightTomoPublicToggle
                }
                .padding(16)
            }
            .navigationTitle("体重ログ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .onAppear { isPublicInTomo = item.isPublic }
        }
    }

    private var weightTomoPublicToggle: some View {
        HStack(spacing: 12) {
            Image(systemName: isPublicInTomo ? "person.2.fill" : "person.2")
                .font(.system(size: 16 * UIScale.font, weight: .bold))
                .foregroundColor(isPublicInTomo ? Color.duoBlue : Color(.systemGray3))
                .frame(width: 32, height: 32)
                .background((isPublicInTomo ? Color.duoBlue : Color(.systemGray5)).opacity(0.15))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("TOMOフィードに公開")
                    .font(.system(size: 13 * UIScale.font, weight: .black))
                    .foregroundColor(Color.duoDark)
                Text(isPublicInTomo ? "TOMOの友達に表示されます" : "自分のFITページにのみ表示")
                    .font(.system(size: 11 * UIScale.font))
                    .foregroundColor(Color.duoSubtitle)
            }
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
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(14)
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

#Preview {
    GoalView(selectedTab: .constant(1), showRecordMenu: .constant(false))
        .environmentObject(AuthenticationManager.shared)
}
