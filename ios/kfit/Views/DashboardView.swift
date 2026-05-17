import SwiftUI
import UIKit
import HealthKit
import WidgetKit

// MARK: - PFC円グラフ
struct PFCPieChart: View {
    let proteinPercent: Double
    let fatPercent: Double
    let carbsPercent: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // たんぱく質（オレンジ）
                PieSlice(
                    startAngle: .degrees(0),
                    endAngle: .degrees(proteinPercent * 3.6)
                )
                .fill(Color.duoOrange)

                // 脂質（紫）
                PieSlice(
                    startAngle: .degrees(proteinPercent * 3.6),
                    endAngle: .degrees((proteinPercent + fatPercent) * 3.6)
                )
                .fill(Color.duoPurple)

                // 炭水化物（青）
                PieSlice(
                    startAngle: .degrees((proteinPercent + fatPercent) * 3.6),
                    endAngle: .degrees(360)
                )
                .fill(Color.duoBlue)

                // 中央の白い円（ドーナツ型にする）
                Circle()
                    .fill(Color.white)
                    .frame(width: geometry.size.width * 0.6, height: geometry.size.height * 0.6)
            }
        }
    }
}

struct PieSlice: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle - .degrees(90), // 12時の位置から開始
            endAngle: endAngle - .degrees(90),
            clockwise: false
        )
        path.closeSubpath()

        return path
    }
}

struct DashboardView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var habitManager = HabitStackManager.shared
    @StateObject private var healthKit    = HealthKitManager.shared
    @StateObject private var timeSlotManager = TimeSlotManager.shared
    @State private var todayExercises: [CompletedExercise] = []
    @State private var totalReps     = 0
    @State private var totalCalories = 0
    @State private var totalXP      = 0
    @State private var todaySetCount = 0  // 今日完了したセット数
    @State private var dailySetGoal  = 2  // 1日の目標セット数
    @State private var dailySets    = DailySets(amSets: 0, pmSets: 0)  // 元の型を保持
    @State private var weeklySetProgress = WeeklySetProgress(completedSets: 0, dailyGoal: 2)
    @State private var calorieGoal = DailyCalorieGoal()
    @State private var isLoading    = false  // 初期値をfalseに変更
    @State private var mascotBounce = false
    @State private var showTracker  = false
    @State private var showHabits   = false
    @State private var hasLoadedOnce = false  // 1度だけロード実行するフラグ
    @State private var expandedSetId: String? = nil  // 展開中のセットID
    @State private var showCalorieGoalEdit = false  // カロリー目標編集モーダル
    @State private var tempCalorieTarget = 500  // 一時的なカロリー目標
    @State private var showTodayRecords = false  // 今日の記録を表示するか
    @State private var showMenu = false  // ハンバーガーメニューの表示状態
    @State private var showHealthGoalEdit = false  // 健康目標編集モーダル
    @State private var tempSleepGoal = 7.0  // 一時的な睡眠目標
    @State private var tempStepsGoal = 10000  // 一時的な歩数目標
    @State private var tempCaloriesGoal = 500  // 一時的な消費カロリー目標
    @State private var todayIntake = TodayIntakeSummary()  // 今日の摂取記録
    @State private var intakeGoals = IntakeSettings.defaultSettings  // 摂取目標
    @State private var showIntakeGoalEdit = false  // 摂取目標編集モーダル
    @State private var showIntakeConfirm = false  // 摂取記録確認ダイアログ
    @State private var pendingIntakeAction: (() -> Void)?  // 保留中の記録アクション
    @State private var confirmMessage = ""  // 確認メッセージ
    @State private var showPhotoLog = false  // フォトログモーダル
    @State private var pfcAnalysis: PFCBalanceAnalysis?  // PFCバランス分析結果
    @State private var sleepScore: SleepScoreAnalysis?  // 睡眠スコア分析結果
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        coreView
            .onChange(of: healthKit.todayMindfulnessSessions) { oldValue, newValue in
                handleMindfulnessChange(old: oldValue, new: newValue)
            }
            .onChange(of: healthKit.todayActiveCalories) { _, _ in updateWidgetData() }
            .onChange(of: healthKit.todayRestingCalories) { _, _ in updateWidgetData() }
            .onChange(of: healthKit.todayWorkoutMinutes) { _, _ in updateWidgetData() }
            .onChange(of: healthKit.todayStandHours) { _, _ in updateWidgetData() }
            .onChange(of: todayIntake.totalCalories) { _, _ in updateWidgetData() }
            .onChange(of: todaySetCount) { _, _ in updateWidgetData() }
            .onReceive(NotificationCenter.default.publisher(for: .timeSlotProgressDidSave)) { _ in
                updateWidgetData()
            }
            .onAppear {
                withAnimation { mascotBounce = true }
                if !hasLoadedOnce {
                    hasLoadedOnce = true
                    isLoading = true
                    Task {
                        print("🟢 DashboardView.onAppear - loadDataを開始")
                        if healthKit.isAvailable && !healthKit.isAuthorized {
                            await healthKit.requestAuthorization()
                        }
                        await timeSlotManager.loadTodaySettings()
                        await timeSlotManager.loadTodayProgress()
                        await loadData()
                    }
                } else {
                    print("⚠️ DashboardView.onAppear - 既にロード済み、スキップ")
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
    }

    // MARK: - コアビュー（シート・アラート群）
    private var coreView: some View {
        ZStack {
            Color.duoBg.ignoresSafeArea(.all)

            VStack(spacing: 0) {
                if isLoading {
                    Spacer()
                    ProgressView().tint(Color.duoGreen).scaleEffect(1.4)
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            headerInfoCard
                            dailySetsCard
                            quickMenu
                            calorieAndWeightCard
                            pointsCard
                            challengeCard
                            habitStackCard
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                        .padding(.bottom, 60)
                    }
                }
            }

            if showMenu {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showMenu = false
                        }
                    }
                VStack {
                    Spacer()
                    floatingMenuPanel
                }
                .transition(.move(edge: .bottom))
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showTracker) {
            ExerciseTrackerView(isPresented: $showTracker)
                .environmentObject(authManager)
        }
        .onChange(of: showTracker) { _, newValue in
            if !newValue {
                Task {
                    print("🔄 ExerciseTrackerView閉じた - データ再読み込み")
                    await loadData()
                }
            }
        }
        .sheet(isPresented: $showHabits) { NavigationView { HabitStackView() } }
        .sheet(isPresented: $showCalorieGoalEdit) { calorieGoalEditSheet }
        .sheet(isPresented: $showHealthGoalEdit) { healthGoalEditSheet }
        .sheet(isPresented: $showIntakeGoalEdit) {
            IntakeSettingsView().environmentObject(authManager)
        }
        .fullScreenCover(isPresented: $showPhotoLog) { PhotoLogView() }
        .alert(confirmMessage, isPresented: $showIntakeConfirm) {
            Button("キャンセル", role: .cancel) { }
            Button("記録する") {
                pendingIntakeAction?()
                pendingIntakeAction = nil
            }
        }
    }

    private func handleMindfulnessChange(old: Int, new: Int) {
        Task {
            print("🧘 Mindfulness sessions: \(old) → \(new)")
            // TimeSlotManagerの合計とHealthKitの差分だけ記録（二重カウント防止）
            let totalInSlots = TimeSlot.allCases.compactMap {
                timeSlotManager.progress.progressFor($0)?.mindfulnessCompleted
            }.reduce(0, +)
            let needed = new - totalInSlots
            if needed > 0 {
                let currentSlot = TimeSlot.current()
                for _ in 0..<needed {
                    await timeSlotManager.recordMindfulnessCompleted(at: currentSlot)
                }
                print("✅ Recorded \(needed) mindfulness session(s) to \(currentSlot.displayName)")
            }
            updateWidgetData()
        }
    }

    // MARK: - 常時表示CTAボタン（画面最下部に固定）
    private var startTrainingButton: some View {
        GeometryReader { geometry in
            Button { showTracker = true } label: {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.22))
                            .frame(width: 30, height: 30)
                            .scaleEffect(mascotBounce && todayExercises.isEmpty ? 1.1 : 1.0)
                            .animation(
                                todayExercises.isEmpty
                                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                                    : .default,
                                value: mascotBounce
                            )
                        Text(todayExercises.isEmpty ? "💪" : "➕")
                            .font(.callout)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Text(todayExercises.isEmpty
                             ? "今日のトレーニングを始めよう！"
                             : "さらに記録する")
                            .font(.caption).fontWeight(.black)
                            .foregroundColor(.white)
                        Text(todayExercises.isEmpty
                             ? "タップして開始"
                             : "\(todayExercises.count) 種目 · \(totalXP) XP")
                            .font(.caption2)
                            .foregroundColor(Color.white.opacity(0.85))
                    }

                    Spacer()

                    Image(systemName: "chevron.right.circle.fill")
                        .font(.callout)
                        .foregroundColor(Color.white.opacity(0.8))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    LinearGradient(
                        colors: [Color.duoGreen, Color(red: 0.18, green: 0.62, blue: 0.0)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: Color.duoGreen.opacity(0.3), radius: 6, y: 2)
                )
            }
            .buttonStyle(.plain)

            // マインドフルネスボタン
            Button {
                openMindfulness()
            } label: {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.22))
                            .frame(width: 30, height: 30)
                        Text("🧘")
                            .font(.callout)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Text("マインドフルネス")
                            .font(.caption).fontWeight(.black)
                            .foregroundColor(.white)
                        Text("呼吸セッション")
                            .font(.caption2)
                            .foregroundColor(Color.white.opacity(0.85))
                    }

                    Spacer()

                    Image(systemName: "chevron.right.circle.fill")
                        .font(.callout)
                        .foregroundColor(Color.white.opacity(0.8))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    LinearGradient(
                        colors: [Color.duoPurple, Color(red: 0.58, green: 0.32, blue: 0.76)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: Color.duoPurple.opacity(0.3), radius: 6, y: 2)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 0 : 8)
            .padding(.top, 2)
            .background(
                Color.duoBg
                    .shadow(color: Color.black.opacity(0.05), radius: 3, y: -1)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .frame(height: 110)
    }

    // MARK: - ヒーロー（極小1行バー + 記録ボタン）
    private var heroSection: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [Color.duoGreen, Color(red: 0.18, green: 0.58, blue: 0.0)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .ignoresSafeArea(.all, edges: .top)

                VStack(spacing: 0) {
                    // ステータスバー領域（実際のセーフエリア高さを使用）
                    Color.clear
                        .frame(height: geometry.safeAreaInsets.top)

                    // ロゴ + 統計（1行のみ）
                    HStack(spacing: 0) {
                        // ── ロゴ ──────────────────
                        HStack(spacing: 2) {
                            Image("mascot")
                                .resizable().scaledToFill()
                                .frame(width: 11, height: 11)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 0.4))
                            Text("DuoFit")
                                .font(.system(size: 10, design: .rounded))
                                .fontWeight(.black)
                                .foregroundColor(.white)
                        }

                        Spacer()

                        // ── 統計 2項目（横1列）- 連続記録と直近の時間帯セット状況 ───
                        currentTimeSlotStats
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                }
            }
            .frame(height: geometry.safeAreaInsets.top + 22)
        }
        .frame(height: 66)
    }

    // MARK: - ヘッダー情報カード（メインコンテンツ最上部）
    private var headerInfoCard: some View {
        ZStack {
            LinearGradient(
                colors: [Color.duoGreen, Color(red: 0.18, green: 0.58, blue: 0.0)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            HStack {
                // 左側: ロゴ
                HStack(spacing: 2) {
                    Image("mascot")
                        .resizable().scaledToFill()
                        .frame(width: 16, height: 16)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 0.4))
                    Text("DuoFit")
                        .font(.system(size: 16, design: .rounded))
                        .fontWeight(.black)
                        .foregroundColor(.white)
                }

                Spacer()

                // 右側: 数値情報
                HStack(spacing: 8) {
                    // 連続記録
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        Text("\(authManager.userProfile?.streak ?? 0)日")
                            .font(.system(size: 10, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }

                    // 到達度
                    HStack(spacing: 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                        Text("\(completionPercentage)%")
                            .font(.system(size: 10, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }

                    // カロリー収支（プラスは赤字、マイナスは黄色字）
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundColor(calorieBalance > 0 ? .red : (calorieBalance < 0 ? .yellow : .white))
                        Text(calorieBalance > 0 ? "+\(calorieBalance)cal" : (calorieBalance < 0 ? "\(calorieBalance)cal" : "0cal"))
                            .font(.system(size: 10, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(calorieBalance > 0 ? .red : (calorieBalance < 0 ? .yellow : .white))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .cornerRadius(12)
    }

    // MARK: - ヘッダー計算プロパティ

    private var completionPercentage: Int {
        let totalGoals = timeSlotManager.settings.goals.reduce(0) { $0 + $1.trainingGoal + $1.mindfulnessGoal }
        guard totalGoals > 0 else { return 0 }

        let totalCompleted = timeSlotManager.progress.progress.reduce(0) { $0 + $1.trainingCompleted + $1.mindfulnessCompleted }
        return min(100, Int((Double(totalCompleted) / Double(totalGoals)) * 100))
    }

    private var calorieBalance: Int {
        let consumed = todayIntake.totalCalories
        let burned = Int(healthKit.todayActiveCalories + healthKit.todayRestingCalories)
        // Apple Health方式: 摂取 − 消費（プラス = 摂取過多, マイナス = 消費超過）
        return consumed - burned
    }

    // MARK: - ヘッダー（コンパクト・最上段固定）
    private var headerCard: some View {
        let currentHour = Calendar.current.component(.hour, from: Date())
        var completedSlots: [TimeSlot] = []
        if currentHour >= 6 { completedSlots.append(.morning) }
        if currentHour >= 10 { completedSlots.append(.noon) }
        if currentHour >= 14 { completedSlots.append(.afternoon) }
        if currentHour >= 18 { completedSlots.append(.evening) }

        let totalTrainingCompleted = completedSlots.reduce(0) { sum, slot in
            sum + countSetsInTimeSlot(slot)
        }
        let totalTrainingGoal = completedSlots.reduce(0) { sum, slot in
            sum + (timeSlotManager.settings.goalFor(slot)?.trainingGoal ?? 0)
        }
        let totalMindfulnessCompleted = completedSlots.reduce(0) { sum, slot in
            sum + (timeSlotManager.progress.progressFor(slot)?.mindfulnessCompleted ?? 0)
        }
        let totalMindfulnessGoal = completedSlots.reduce(0) { sum, slot in
            sum + (timeSlotManager.settings.goalFor(slot)?.mindfulnessGoal ?? 0)
        }
        let totalMealLogged = completedSlots.reduce(0) { sum, slot in
            sum + (timeSlotManager.progress.progressFor(slot)?.logProgress.mealLogged ?? 0)
        }
        let totalMealGoal = completedSlots.reduce(0) { sum, slot in
            sum + (timeSlotManager.settings.goalFor(slot)?.logGoal.mealGoal ?? 0)
        }
        let totalDrinkLogged = completedSlots.reduce(0) { sum, slot in
            sum + (timeSlotManager.progress.progressFor(slot)?.logProgress.drinkLogged ?? 0)
        }
        let totalDrinkGoal = completedSlots.reduce(0) { sum, slot in
            sum + (timeSlotManager.settings.goalFor(slot)?.logGoal.drinkGoal ?? 0)
        }

        var totalGoals = 0
        var completedGoals = 0
        if totalTrainingGoal > 0 {
            totalGoals += 1
            if totalTrainingCompleted >= totalTrainingGoal { completedGoals += 1 }
        }
        if totalMindfulnessGoal > 0 {
            totalGoals += 1
            if totalMindfulnessCompleted >= totalMindfulnessGoal { completedGoals += 1 }
        }
        if totalMealGoal > 0 {
            totalGoals += 1
            if totalMealLogged >= totalMealGoal { completedGoals += 1 }
        }
        if totalDrinkGoal > 0 {
            totalGoals += 1
            if totalDrinkLogged >= totalDrinkGoal { completedGoals += 1 }
        }
        if timeSlotManager.settings.globalGoals.workoutEnabled {
            totalGoals += 1
            if timeSlotManager.progress.globalProgress.workoutMinutes >= timeSlotManager.settings.globalGoals.workoutMinutes {
                completedGoals += 1
            }
        }
        if timeSlotManager.settings.globalGoals.standEnabled {
            totalGoals += 1
            if timeSlotManager.progress.globalProgress.standHours >= timeSlotManager.settings.globalGoals.standHours {
                completedGoals += 1
            }
        }

        let progressPercent = totalGoals > 0 ? Int((Double(completedGoals) / Double(totalGoals)) * 100) : 0
        let totalConsumed = healthKit.todayTotalCalories
        let intake = Double(todayIntake.totalCalories)
        let balance = intake - totalConsumed

        return GeometryReader { geometry in
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [Color.duoGreen, Color(red: 0.18, green: 0.58, blue: 0.0)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .ignoresSafeArea(.all, edges: .top)

                VStack(spacing: 0) {
                    Color.clear.frame(height: geometry.safeAreaInsets.top)

                    VStack(spacing: 4) {
                        // ロゴ
                        HStack(spacing: 3) {
                            Image("mascot")
                                .resizable().scaledToFill()
                                .frame(width: 14, height: 14)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 0.5))
                            Text("DuoFit")
                                .font(.system(size: 12, design: .rounded))
                                .fontWeight(.black)
                                .foregroundColor(.white)
                        }

                        // 統計情報
                        HStack(spacing: 8) {
                            compactStat(icon: "🔥", value: "\(authManager.userProfile?.streak ?? 0)")
                            compactStat(icon: "📊", value: "\(progressPercent)%")
                            compactStat(icon: balance >= 0 ? "📈" : "📉", value: balance >= 0 ? "+\(Int(balance))" : "\(Int(balance))")
                            compactStat(icon: "⭐", value: "\((authManager.userProfile?.totalPoints ?? 0).formatted())")
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
            }
            .frame(height: geometry.safeAreaInsets.top + 50)
        }
        .frame(height: 94)
    }

    private func compactStat(icon: String, value: String) -> some View {
        HStack(spacing: 1) {
            Text(icon).font(.system(size: 10))
            Text(value)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundColor(.white)
        }
    }

    // ── 現在の時間帯セット状況 ───
    private var currentTimeSlotStats: some View {
        // 現時点までのトータル進捗を計算
        let currentHour = Calendar.current.component(.hour, from: Date())

        // 現時点までの時間帯を取得
        var completedSlots: [TimeSlot] = []
        if currentHour >= 6 { completedSlots.append(.morning) }
        if currentHour >= 10 { completedSlots.append(.noon) }
        if currentHour >= 14 { completedSlots.append(.afternoon) }
        if currentHour >= 18 { completedSlots.append(.evening) }

        // トータルのトレーニング実績と目標（実際のセット数）
        let totalTrainingCompleted = completedSlots.reduce(0) { sum, slot in
            sum + countSetsInTimeSlot(slot)
        }
        let totalTrainingGoal = completedSlots.reduce(0) { sum, slot in
            sum + (timeSlotManager.settings.goalFor(slot)?.trainingGoal ?? 0)
        }

        // トータルのマインドフルネス実績と目標
        let totalMindfulnessCompleted = completedSlots.reduce(0) { sum, slot in
            sum + (timeSlotManager.progress.progressFor(slot)?.mindfulnessCompleted ?? 0)
        }
        let totalMindfulnessGoal = completedSlots.reduce(0) { sum, slot in
            sum + (timeSlotManager.settings.goalFor(slot)?.mindfulnessGoal ?? 0)
        }

        // トータルのログ完了状況（回数の合計）
        let totalMealLogged = completedSlots.reduce(0) { sum, slot in
            sum + (timeSlotManager.progress.progressFor(slot)?.logProgress.mealLogged ?? 0)
        }
        let totalMealGoal = completedSlots.reduce(0) { sum, slot in
            sum + (timeSlotManager.settings.goalFor(slot)?.logGoal.mealGoal ?? 0)
        }

        let totalDrinkLogged = completedSlots.reduce(0) { sum, slot in
            sum + (timeSlotManager.progress.progressFor(slot)?.logProgress.drinkLogged ?? 0)
        }
        let totalDrinkGoal = completedSlots.reduce(0) { sum, slot in
            sum + (timeSlotManager.settings.goalFor(slot)?.logGoal.drinkGoal ?? 0)
        }

        // トータル進捗％を計算（1日全体の目標も含む）
        var totalGoals = 0
        var completedGoals = 0

        if totalTrainingGoal > 0 {
            totalGoals += 1
            if totalTrainingCompleted >= totalTrainingGoal { completedGoals += 1 }
        }
        if totalMindfulnessGoal > 0 {
            totalGoals += 1
            if totalMindfulnessCompleted >= totalMindfulnessGoal { completedGoals += 1 }
        }
        if totalMealGoal > 0 {
            totalGoals += 1
            if totalMealLogged >= totalMealGoal { completedGoals += 1 }
        }
        if totalDrinkGoal > 0 {
            totalGoals += 1
            if totalDrinkLogged >= totalDrinkGoal { completedGoals += 1 }
        }

        // 1日全体の目標（ワークアウトとスタンド時間）
        if timeSlotManager.settings.globalGoals.workoutEnabled {
            totalGoals += 1
            if timeSlotManager.progress.globalProgress.workoutMinutes >= timeSlotManager.settings.globalGoals.workoutMinutes {
                completedGoals += 1
            }
        }
        if timeSlotManager.settings.globalGoals.standEnabled {
            totalGoals += 1
            if timeSlotManager.progress.globalProgress.standHours >= timeSlotManager.settings.globalGoals.standHours {
                completedGoals += 1
            }
        }

        let progressPercent = totalGoals > 0 ? Int((Double(completedGoals) / Double(totalGoals)) * 100) : 0

        // カロリー収支を計算
        let totalConsumed = healthKit.todayTotalCalories
        let intake = Double(todayIntake.totalCalories)
        let balance = intake - totalConsumed
        let isPositive = balance > 0

        return HStack(spacing: 3) {
            // 1. 連続記録
            miniStat("🔥", "\(authManager.userProfile?.streak ?? 0)", "")

            // 2. トータル進捗％
            HStack(spacing: 1) {
                Text("📊").font(.system(size: 9))
                Text("\(progressPercent)%")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundColor(progressPercent == 100 ? Color.white : Color.white.opacity(0.8))
                if progressPercent == 100 {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 7))
                        .foregroundColor(.white)
                }
            }

            // 3. カロリー収支
            HStack(spacing: 1) {
                Text(isPositive ? "📈" : "📉").font(.system(size: 9))
                Text(isPositive ? "+" : "")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                Text("\(Int(abs(balance)))")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }

            // 4. 総ポイント数
            HStack(spacing: 1) {
                Text("⭐").font(.system(size: 9))
                Text("\((authManager.userProfile?.totalPoints ?? 0).formatted())")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundColor(Color.duoYellow)
            }
        }
    }

    private func miniStat(_ icon: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 1) {
            Text(icon).font(.system(size: 9))
            Text(value)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 7))
                .foregroundColor(Color.white.opacity(0.7))
        }
    }

    /// 回数＋カロリーを2行で表示するヘッダー統計アイテム
    @ViewBuilder
    private func repCalStat(reps: Int, kcal: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("⚡").font(.system(size: 9))
                Text("\(reps)回")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }
            Text("\(kcal)kcal")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Color.white.opacity(0.8))
        }
    }

    // MARK: - 今日のセット状況カード
    private var dailySetsCard: some View {
        // 現在時刻から表示すべき時間帯を決定
        let currentHour = Calendar.current.component(.hour, from: Date())
        let visibleSlots: [TimeSlot]
        let totalSlotsToShow: Int

        if currentHour < 6 {
            // 6時前は全時間帯表示（前日扱い）
            visibleSlots = TimeSlot.allCases
            totalSlotsToShow = 4
        } else if currentHour < 10 {
            // 朝（6-10時）：朝のみ
            visibleSlots = [.morning]
            totalSlotsToShow = 1
        } else if currentHour < 14 {
            // 昼（10-14時）：朝、昼
            visibleSlots = [.morning, .noon]
            totalSlotsToShow = 2
        } else if currentHour < 18 {
            // 午後（14-18時）：朝、昼、午後
            visibleSlots = [.morning, .noon, .afternoon]
            totalSlotsToShow = 3
        } else {
            // 夜（18時以降）：全時間帯
            visibleSlots = TimeSlot.allCases
            totalSlotsToShow = 4
        }

        // 表示する時間帯の達成状況を計算
        let totalCompletedSlots = visibleSlots.filter { slot in
            if let goal = timeSlotManager.settings.goalFor(slot),
               let progress = timeSlotManager.progress.progressFor(slot) {
                // トレーニングは実際のセット数でチェック
                let setsCompleted = countSetsInTimeSlot(slot)
                let trainingGoalMet = goal.trainingGoal == 0 || setsCompleted >= goal.trainingGoal
                let mindfulnessGoalMet = goal.mindfulnessGoal == 0 || progress.mindfulnessCompleted >= goal.mindfulnessGoal
                let mealGoalMet = goal.logGoal.mealGoal == 0 || progress.logProgress.mealLogged >= goal.logGoal.mealGoal
                let drinkGoalMet = goal.logGoal.drinkGoal == 0 || progress.logProgress.drinkLogged >= goal.logGoal.drinkGoal
                let mindInputGoalMet = !goal.logGoal.mindInputRequired || progress.logProgress.mindInputLogged > 0
                return trainingGoalMet && mindfulnessGoalMet && mealGoalMet && drinkGoalMet && mindInputGoalMet
            }
            return false
        }.count

        // トータル進捗を計算（今日1日分の全時間帯）
        var totalTraining = 0
        var totalTrainingGoal = 0
        var totalMindfulness = 0
        var totalMindfulnessGoal = 0
        var totalMealLogged = 0
        var totalMealGoal = 0
        var totalDrinkLogged = 0
        var totalDrinkGoal = 0
        var totalCustomCompleted = 0
        var totalCustomGoal = 0

        // 今日1日分の全時間帯をカウント（表示用）
        for slot in TimeSlot.allCases {
            if let goal = timeSlotManager.settings.goalFor(slot),
               let progress = timeSlotManager.progress.progressFor(slot) {
                // 実際のセット数をカウント（その時間帯に実行された運動記録の数）
                let setsInSlot = countSetsInTimeSlot(slot)
                totalTraining += setsInSlot
                totalTrainingGoal += goal.trainingGoal

                totalMindfulnessGoal += goal.mindfulnessGoal

                if goal.logGoal.mealGoal > 0 {
                    totalMealGoal += goal.logGoal.mealGoal
                    totalMealLogged += progress.logProgress.mealLogged
                }
                if goal.logGoal.drinkGoal > 0 {
                    totalDrinkGoal += goal.logGoal.drinkGoal
                    totalDrinkLogged += progress.logProgress.drinkLogged
                }

                let enabled = goal.customActivities.filter { $0.isEnabled }
                totalCustomGoal += enabled.count
                totalCustomCompleted += enabled.filter { progress.completedActivityIds.contains($0.id) }.count
            }
        }

        // マインドフルネスはHealthKitを正として使用（TimeSlotManagerの合計より正確）
        totalMindfulness = healthKit.todayMindfulnessSessions

        // 全ての目標達成チェック
        let allGoalsCompleted = (totalTrainingGoal > 0 && totalTraining >= totalTrainingGoal) &&
                                (totalMindfulnessGoal > 0 && totalMindfulness >= totalMindfulnessGoal) &&
                                (totalMealGoal > 0 && totalMealLogged >= totalMealGoal) &&
                                (totalDrinkGoal > 0 && totalDrinkLogged >= totalDrinkGoal)
        // @ViewBuilder内に書くとスタックオーバーフローの原因になるため事前計算
        let gp = timeSlotManager.progress.globalProgress
        let gg = timeSlotManager.settings.globalGoals
        let hasGlobalRow = totalMealGoal > 0 || totalDrinkGoal > 0
            || gp.sleepScore > 0 || gp.pfcScore > 0 || gp.weightMeasured
        let sleepAchieved = gp.sleepScore >= gg.sleepScoreThreshold
        let pfcAchieved = gp.pfcScore >= gg.pfcScoreThreshold

        return VStack(alignment: .leading, spacing: 0) {
            // ヘッダー（タップで展開）
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showTodayRecords.toggle()
                }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    // タイトル行: 日付 + ステータス
                    HStack(spacing: 6) {
                        HStack(spacing: 3) {
                            Text(formatDate(Date()))
                                .font(.headline)
                                .fontWeight(.black)
                                .foregroundColor(Color.duoGreen)
                            Text("のDuoFit")
                                .font(.headline)
                                .fontWeight(.black)
                                .foregroundColor(Color.duoDark)
                        }

                        Spacer()

                        if allGoalsCompleted {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("完了!")
                                    .font(.caption).fontWeight(.black)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.duoGreen)
                            .cornerRadius(20)
                        }

                        Image(systemName: showTodayRecords ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(Color.duoGreen)
                    }

                    // トレーニング・マインドフルネス・ワークアウト・スタンド表示行
                    HStack(spacing: 12) {
                        // トレーニング（セット数）
                        HStack(spacing: 4) {
                            Text("💪").font(.title3)
                            Text("\(totalTraining)/\(totalTrainingGoal)")
                                .font(.subheadline).fontWeight(.bold)
                                .foregroundColor(totalTraining >= totalTrainingGoal ? Color.duoGreen : Color.duoDark)
                        }

                        // マインドフルネス
                        HStack(spacing: 4) {
                            Text("🧘").font(.title3)
                            Text("\(totalMindfulness)/\(totalMindfulnessGoal)")
                                .font(.subheadline).fontWeight(.bold)
                                .foregroundColor(totalMindfulness >= totalMindfulnessGoal ? Color.duoGreen : Color.duoDark)
                        }

                        // ワークアウト（実績のみ表示）
                        if gg.workoutEnabled {
                            HStack(spacing: 4) {
                                Text("🏃").font(.title3)
                                Text("\(gp.workoutMinutes)分")
                                    .font(.subheadline).fontWeight(.bold)
                                    .foregroundColor(gp.workoutMinutes >= gg.workoutMinutes ? Color.duoGreen : Color.duoDark)
                            }
                        }

                        // スタンド時間（実績のみ表示）
                        if gg.standEnabled {
                            HStack(spacing: 4) {
                                Text("🕐").font(.title3)
                                Text("\(gp.standHours)h")
                                    .font(.subheadline).fontWeight(.bold)
                                    .foregroundColor(gp.standHours >= gg.standHours ? Color.duoGreen : Color.duoDark)
                            }
                        }

                        // カスタム項目合計
                        if totalCustomGoal > 0 {
                            HStack(spacing: 4) {
                                Text("🎯").font(.title3)
                                Text("\(totalCustomCompleted)/\(totalCustomGoal)")
                                    .font(.subheadline).fontWeight(.bold)
                                    .foregroundColor(totalCustomCompleted >= totalCustomGoal ? Color.duoGreen : Color.duoDark)
                            }
                        }

                        Spacer()
                    }

                    // 食事・水分 + 睡眠・PFC・体重計測
                    if hasGlobalRow {
                        HStack(spacing: 8) {
                            // 睡眠スコア
                            if gp.sleepScore > 0 {
                                HStack(spacing: 3) {
                                    Text("😴").font(.caption)
                                    Text("\(gp.sleepScore)")
                                        .font(.caption).fontWeight(.bold)
                                        .foregroundColor(sleepAchieved ? Color.duoGreen : Color.duoDark)
                                }
                            }
                            // PFCバランス
                            if gp.pfcScore > 0 {
                                HStack(spacing: 3) {
                                    Text("🥗").font(.caption)
                                    Text("\(gp.pfcScore)")
                                        .font(.caption).fontWeight(.bold)
                                        .foregroundColor(pfcAchieved ? Color.duoGreen : Color.duoDark)
                                }
                            }
                            // 体重計測
                            if gp.weightMeasured {
                                HStack(spacing: 3) {
                                    Text("⚖️").font(.caption)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(Color.duoGreen)
                                }
                            }

                            Spacer()

                            // 食事ログ
                            if totalMealGoal > 0 && totalMealLogged > 0 {
                                HStack(spacing: 2) {
                                    Text("🍽️").font(.caption)
                                    Text("\(totalMealLogged)")
                                        .font(.caption2).fontWeight(.bold)
                                        .foregroundColor(totalMealLogged >= totalMealGoal ? Color.duoGreen : Color.duoSubtitle)
                                }
                            }
                            // 水分ログ
                            if totalDrinkGoal > 0 && totalDrinkLogged > 0 {
                                HStack(spacing: 2) {
                                    Text("💧").font(.caption)
                                    Text("\(totalDrinkLogged)")
                                        .font(.caption2).fontWeight(.bold)
                                        .foregroundColor(totalDrinkLogged >= totalDrinkGoal ? Color.duoBlue : Color.duoSubtitle)
                                }
                            }
                        }
                    }

                    // カスタム目標の達成アイコン行
                    goalAchievementIconsRow

                    // 達成メッセージ
                    if totalCompletedSlots == totalSlotsToShow {
                        Text(totalSlotsToShow == 4 ? "全時間帯の目標達成！素晴らしい一日🎉" : "ここまでの目標達成！順調です💪")
                            .font(.caption).fontWeight(.bold).foregroundColor(Color.duoGreen)
                            .padding(.top, 2)
                    } else if totalCompletedSlots == 0 {
                        Text("今日はまだ目標を達成していません。始めましょう！")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                            .padding(.top, 2)
                    } else {
                        Text("あと \(totalSlotsToShow - totalCompletedSlots) つの時間帯で目標達成！")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                            .padding(.top, 2)
                    }
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            // 時間帯別の進捗（アコーディオン）- メッセージの下
            if showTodayRecords {
                VStack(spacing: 0) {
                    Divider()
                        .padding(.horizontal, 16)

                    VStack(spacing: 10) {
                        ForEach(visibleSlots, id: \.rawValue) { slot in
                            VStack(alignment: .leading, spacing: 4) {
                                timeSlotRow(for: slot)
                                // カスタム活動チップ（横並び）
                                if let goal = timeSlotManager.settings.goalFor(slot),
                                   !goal.customActivities.filter({ $0.isEnabled }).isEmpty {
                                    let slotProgress = timeSlotManager.progress.progressFor(slot)
                                    HStack(spacing: 6) {
                                        ForEach(goal.customActivities.filter { $0.isEnabled }) { activity in
                                            let done = slotProgress?.completedActivityIds.contains(activity.id) ?? false
                                            Button {
                                                Task { await timeSlotManager.toggleCustomActivity(id: activity.id, at: slot) }
                                            } label: {
                                                HStack(spacing: 3) {
                                                    Text(activity.emoji).font(.caption)
                                                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                                        .font(.caption2)
                                                        .foregroundColor(done ? Color.duoGreen : Color(.systemGray4))
                                                }
                                                .padding(.horizontal, 8).padding(.vertical, 4)
                                                .background(done ? Color.duoGreen.opacity(0.1) : Color(.systemGray6))
                                                .cornerRadius(20)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        Spacer()
                                    }
                                    .padding(.leading, 40)
                                    .padding(.top, 2)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }

            dailySetsCardButtons

            // 今日の記録（展開時のみ表示）- 緑ボタンの下
            if showTodayRecords && !todayExercises.isEmpty {
                VStack(spacing: 0) {
                    Divider()
                        .padding(.horizontal, 16)

                    todayRecordsSection
                }
            }
        }
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 5, y: 2)
    }

    private var dailySetsCardButtons: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 16)

            Button { showTracker = true } label: {
                HStack(spacing: 10) {
                    Image("mascot")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
                        .scaleEffect(mascotBounce && todayExercises.isEmpty ? 1.1 : 1.0)
                        .animation(
                            todayExercises.isEmpty
                                ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                                : .default,
                            value: mascotBounce
                        )

                    VStack(alignment: .leading, spacing: 0) {
                        Text(todayExercises.isEmpty
                             ? "今日のDuoFit!"
                             : "\(todaySetCount + 1)回目のDuoFit!")
                            .font(.system(size: 15, weight: .black))
                            .foregroundColor(.white)
                        Text(todayExercises.isEmpty
                             ? "タップして開始"
                             : "\(todayExercises.count) 種目 · \(totalXP) XP")
                            .font(.caption)
                            .foregroundColor(Color.white.opacity(0.85))
                    }

                    Spacer()

                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color.white.opacity(0.8))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [Color.duoGreen, Color(red: 0.18, green: 0.62, blue: 0.0)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: Color.duoGreen.opacity(0.3), radius: 6, y: 2)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Button { openWatchMindfulness() } label: {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.duoPurple.opacity(0.2))
                            .frame(width: 30, height: 30)
                        Text("🧘").font(.callout)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Text("マインドフルネス")
                            .font(.subheadline).fontWeight(.black)
                            .foregroundColor(Color.duoPurple)
                        Text("Watchアプリを起動")
                            .font(.caption)
                            .foregroundColor(Color.duoPurple.opacity(0.7))
                    }

                    Spacer()

                    Image(systemName: "chevron.right.circle.fill")
                        .font(.callout)
                        .foregroundColor(Color.duoPurple.opacity(0.6))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [Color.duoPurple.opacity(0.15), Color.duoPurple.opacity(0.08)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 4)

            Button { showPhotoLog = true } label: {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 30, height: 30)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Text("フォトログ")
                            .font(.subheadline).fontWeight(.black)
                            .foregroundColor(Color.duoDark)
                        Text("AI食事分析")
                            .font(.caption)
                            .foregroundColor(Color.duoSubtitle)
                    }

                    Spacer()

                    Image(systemName: "chevron.right.circle.fill")
                        .font(.callout)
                        .foregroundColor(Color.duoSubtitle.opacity(0.6))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.08), Color.purple.opacity(0.08)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    // MARK: - 週間目標カード（独立）
    private var weeklyGoalCard: some View {
        let activeDays = 5
        let weeklyTarget = weeklySetProgress.dailyGoal * activeDays
        let today = Calendar.current.dateComponents([.weekday], from: Date()).weekday ?? 1
        // 月曜日=2, 火曜日=3, ..., 金曜日=6, 土日=1として、月〜金の経過日数を計算
        let activeDaysElapsed = today == 1 ? 0 : max(0, min(today - 2, activeDays))
        let expectedNow = weeklySetProgress.dailyGoal * activeDaysElapsed
        let weekPct = weeklyTarget > 0 ? min(Double(weeklySetProgress.completedSets) / Double(weeklyTarget) * 100, 100) : 0
        let isOnTrack = expectedNow > 0 ? weeklySetProgress.completedSets >= expectedNow : true

        return VStack(alignment: .leading, spacing: 10) {
            // ヘッダー
            HStack(spacing: 5) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.subheadline)
                    .foregroundColor(Color.duoGreen)
                Text("週間目標").fontWeight(.black)
                    .font(.subheadline)
                    .foregroundColor(Color.duoDark)
                Spacer()
                Text("1日\(weeklySetProgress.dailyGoal)セット × \(activeDays)日")
                    .font(.caption2).fontWeight(.bold)
                    .foregroundColor(Color.duoGreen)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.duoGreen.opacity(0.12))
                    .cornerRadius(6)
            }

            // 進捗表示
            HStack(alignment: .bottom, spacing: 6) {
                Text("\(weeklySetProgress.completedSets)")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(isOnTrack ? Color.duoGreen : Color.duoOrange)
                Text("/ \(weeklyTarget) セット")
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(Color.duoSubtitle)
                    .padding(.bottom, 3)
                Spacer()
                Text("\(Int(weekPct))%")
                    .font(.title3).fontWeight(.black)
                    .foregroundColor(isOnTrack ? Color.duoGreen : Color.duoOrange)
            }

            // プログレスバー
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5)).frame(height: 10)
                    Capsule().fill(
                        LinearGradient(
                            colors: isOnTrack ? [Color.duoGreen, Color(red: 0.57, green: 0.9, blue: 0.16)] : [Color.duoYellow, Color.duoOrange],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(10, geo.size.width * CGFloat(weekPct / 100)), height: 10)
                }
            }
            .frame(height: 10)

            Text(isOnTrack ? "🎉 ペース通り！素晴らしい" : "今日まで目標 \(expectedNow) セット（\(activeDaysElapsed)日経過）")
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(isOnTrack ? Color.duoGreen : Color.duoSubtitle)
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
    }

    // MARK: - 今日の記録セクション（セット一覧）
    private var todayRecordsSection: some View {
        let sets = buildTodaySets(todayExercises)

        return VStack(alignment: .leading, spacing: 8) {
            // ヘッダー
            HStack(spacing: 5) {
                Image(systemName: "list.bullet.circle.fill")
                    .foregroundColor(Color.duoGold)
                Text("今日の記録").fontWeight(.bold)
                Spacer()
                Text("\(sets.count)セット · \(totalReps)回 · \(totalXP) XP")
                    .font(.caption2).fontWeight(.bold)
                    .foregroundColor(Color.duoGold)
            }
            .font(.subheadline)
            .foregroundColor(Color.duoDark)
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // セット一覧
            VStack(spacing: 6) {
                ForEach(sets) { set in
                    todaySetButton(set)
                }
            }
            .padding(.horizontal, 16)

            // マインドフルネス記録
            if healthKit.todayMindfulnessSessions > 0 {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.duoPurple.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Text("🧘").font(.callout)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("マインドフルネス")
                            .font(.caption).fontWeight(.bold)
                            .foregroundColor(Color.duoDark)
                        Text("\(healthKit.todayMindfulnessSessions)セッション · 計\(Int(healthKit.todayMindfulnessMinutes))分")
                            .font(.caption2)
                            .foregroundColor(Color.duoSubtitle)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color.duoPurple)
                        .font(.subheadline)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.duoPurple.opacity(0.06))
                .cornerRadius(10)
                .padding(.horizontal, 16)
            }

            Spacer(minLength: 12)
        }
    }

    // MARK: - セットボタン（展開式）
    private func todaySetButton(_ set: TodaySet) -> some View {
        let isExpanded = expandedSetId == set.id

        return VStack(spacing: 0) {
            // セットサマリー
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    expandedSetId = isExpanded ? nil : set.id
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(set.period) セット\(set.setNumber)")
                            .font(.caption).fontWeight(.bold)
                            .foregroundColor(Color.duoDark)
                        Text(timeString(set.startTime))
                            .font(.caption2)
                            .foregroundColor(Color.duoSubtitle)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Text("\(set.exercises.count)種目")
                            .font(.caption2)
                            .foregroundColor(Color.duoSubtitle)
                        Text("\(set.totalReps)回")
                            .font(.caption2).fontWeight(.bold)
                            .foregroundColor(Color.duoGreen)
                        Text("+\(set.totalPoints)")
                            .font(.caption2).fontWeight(.bold)
                            .foregroundColor(Color.duoGold)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(Color.duoGreen)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(isExpanded ? Color.duoGreen.opacity(0.08) : Color.duoBg)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)

            // 詳細（展開時のみ表示）
            if isExpanded {
                VStack(spacing: 4) {
                    ForEach(set.exercises) { ex in
                        HStack(spacing: 8) {
                            Text(emojiFor(ex.exerciseName))
                                .font(.callout)
                                .frame(width: 28, height: 28)
                                .background(Color.duoGreen.opacity(0.12))
                                .cornerRadius(8)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(ex.exerciseName)
                                    .font(.caption).fontWeight(.bold)
                                    .foregroundColor(Color.duoDark)
                                if ex.exerciseId.lowercased().contains("plank") {
                                    Text("\(ex.reps) 秒")
                                        .font(.caption2).fontWeight(.semibold)
                                        .foregroundColor(Color.duoSubtitle)
                                } else {
                                    Text("\(ex.reps) 回")
                                        .font(.caption2).fontWeight(.semibold)
                                        .foregroundColor(Color.duoSubtitle)
                                }
                            }

                            Spacer()

                            Text("+\(ex.points) XP")
                                .font(.caption2).fontWeight(.bold)
                                .foregroundColor(Color.duoGold)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.duoYellow.opacity(0.22))
                                .cornerRadius(5)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .background(Color.white)
                        .cornerRadius(8)
                    }
                }
                .padding(.top, 4)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .background(Color.duoGreen.opacity(0.05))
                .cornerRadius(10)
            }
        }
    }

    private func setRow(icon: String, label: String, count: Int, needed: Int, isFlexible: Bool) -> some View {
        HStack(spacing: 10) {
            Text(icon).font(.subheadline)
                .frame(width: 24)

            Text(label)
                .font(.caption).fontWeight(.semibold).foregroundColor(Color.duoDark)

            Spacer()

            // セットアイコン
            HStack(spacing: 4) {
                ForEach(0..<needed, id: \.self) { idx in
                    Image(systemName: idx < count ? "circle.fill" : "circle")
                        .font(.system(size: 12))
                        .foregroundColor(idx < count ? Color.duoGreen : Color(.systemGray3))
                }
            }

            // 状態テキスト
            if count >= needed {
                Text("完了")
                    .font(.caption2).fontWeight(.black).foregroundColor(Color.duoGreen)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.duoGreen.opacity(0.12)).cornerRadius(6)
            } else if count > 0 {
                Text("\(count)/\(needed)")
                    .font(.caption2).fontWeight(.bold).foregroundColor(Color.duoOrange)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.duoOrange.opacity(0.12)).cornerRadius(6)
            } else {
                Text("未実施")
                    .font(.caption2).fontWeight(.medium).foregroundColor(Color.duoSubtitle)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color(.systemGray5)).cornerRadius(6)
            }
        }
    }

    // MARK: - 時間帯別の行表示
    private func timeSlotRow(for slot: TimeSlot) -> some View {
        let goal = timeSlotManager.settings.goalFor(slot)
        let progress = timeSlotManager.progress.progressFor(slot)
        let gp = timeSlotManager.progress.globalProgress
        let gg = timeSlotManager.settings.globalGoals

        return HStack(spacing: 8) {
            // 時間帯アイコンと名前 + 時刻
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(slot.emoji).font(.subheadline)
                    Text(slot.displayName)
                        .font(.caption).fontWeight(.semibold).foregroundColor(Color.duoDark)
                }
                Text("~\(slot.endHour):00")
                    .font(.system(size: 9))
                    .foregroundColor(Color.duoSubtitle)
            }
            .frame(width: 50, alignment: .leading)

            if slot == .midnight {
                // 夜中スロット: 睡眠スコア表示
                if gg.sleepEnabled {
                    if gp.sleepScore > 0 {
                        let achieved = gp.sleepScore >= gg.sleepScoreThreshold
                        HStack(spacing: 3) {
                            Text("😴").font(.caption)
                            Text("\(gp.sleepScore)点")
                                .font(.caption2).fontWeight(.bold)
                                .foregroundColor(achieved ? Color.duoGreen : Color.duoSubtitle)
                            if gp.sleepHours > 0 {
                                Text(String(format: "%.1fh", gp.sleepHours))
                                    .font(.system(size: 9))
                                    .foregroundColor(Color.duoSubtitle)
                            }
                            if achieved {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundColor(Color.duoGreen)
                            }
                        }
                    } else {
                        HStack(spacing: 3) {
                            Text("😴").font(.caption)
                            Text("データなし")
                                .font(.caption2)
                                .foregroundColor(Color.duoSubtitle)
                        }
                    }
                }
            } else {
                // トレーニング進捗（実際のセット数）
                if let goal = goal, goal.trainingGoal > 0 {
                    HStack(spacing: 2) {
                        Text("💪").font(.caption)
                        let setsCompleted = countSetsInTimeSlot(slot)
                        Text("\(setsCompleted)")
                            .font(.caption2).fontWeight(.medium)
                            .foregroundColor(setsCompleted >= goal.trainingGoal ? Color.duoGreen : Color.duoSubtitle)
                    }
                }

                // マインドフルネス進捗
                if let goal = goal, goal.mindfulnessGoal > 0 {
                    HStack(spacing: 2) {
                        let completed = progress?.mindfulnessCompleted ?? 0
                        Text("🧘").font(.caption)
                        Text("\(completed)")
                            .font(.caption2).fontWeight(.medium)
                            .foregroundColor(completed >= goal.mindfulnessGoal ? Color.duoGreen : Color.duoSubtitle)
                    }
                }

                // カスタム活動の達成表示
                if let goal = goal, let progress = progress {
                    ForEach(goal.customActivities.filter { act in
                        progress.completedActivityIds.contains(act.id)
                    }) { act in
                        HStack(spacing: 2) {
                            Text(act.emoji).font(.caption)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(Color.duoGreen)
                        }
                    }
                }
            }

            Spacer()

            // ログ進捗バッジ（夜中以外）
            if slot != .midnight, let goal = goal, let progress = progress {
                HStack(spacing: 4) {
                    if goal.logGoal.mealRequired {
                        Image(systemName: progress.logProgress.mealLogged > 0 ? "fork.knife.circle.fill" : "fork.knife.circle")
                            .font(.title3)
                            .foregroundColor(progress.logProgress.mealLogged > 0 ? Color.duoGreen : Color(.systemGray4))
                    }
                    if goal.logGoal.drinkRequired {
                        Image(systemName: progress.logProgress.drinkLogged > 0 ? "drop.circle.fill" : "drop.circle")
                            .font(.title3)
                            .foregroundColor(progress.logProgress.drinkLogged > 0 ? Color.duoBlue : Color(.systemGray4))
                    }
                    if goal.logGoal.mindInputRequired {
                        Image(systemName: progress.logProgress.mindInputLogged > 0 ? "brain.head.profile.fill" : "brain.head.profile")
                            .font(.subheadline)
                            .foregroundColor(progress.logProgress.mindInputLogged > 0 ? Color.duoPurple : Color(.systemGray4))
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - ハビットスタックカード
    private var habitStackCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ヘッダー
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "link")
                    Text("ハビットスタック").fontWeight(.black)
                }
                .font(.subheadline)
                .foregroundColor(Color.duoGreen)
                Spacer()
                Button {
                    showHabits = true
                } label: {
                    Text(habitManager.habits.isEmpty ? "設定する" : "管理")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(Color.duoGreen)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.duoGreen.opacity(0.12))
                        .cornerRadius(8)
                }
            }

            if habitManager.habits.isEmpty {
                // 未設定状態
                Button { showHabits = true } label: {
                    HStack(spacing: 10) {
                        Text("🔗").font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("日課とトレーニングをリンク")
                                .font(.subheadline).fontWeight(.bold)
                                .foregroundColor(Color.duoDark)
                            Text("歯磨き後・コーヒー後などに通知")
                                .font(.caption)
                                .foregroundColor(Color.duoSubtitle)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                    .padding(12)
                    .background(Color.duoGreen.opacity(0.06))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            } else {
                // 習慣一覧（有効なものだけ表示、最大3件）
                let active = habitManager.habits.filter { $0.isEnabled }.prefix(3)
                ForEach(Array(active)) { habit in
                    HStack(spacing: 10) {
                        Text(habit.emoji).font(.title3)
                        Text(habit.name)
                            .font(.subheadline).fontWeight(.medium)
                            .foregroundColor(Color.duoDark)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(habit.timeString)
                                .font(.caption).fontWeight(.bold)
                        }
                        .foregroundColor(Color.duoGreen)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundColor(Color.duoSubtitle)
                        Image(systemName: "figure.run")
                            .font(.caption2)
                            .foregroundColor(Color.duoGreen)
                    }
                    .padding(.vertical, 4)
                    if habit.id != active.last?.id {
                        Divider()
                    }
                }
                if habitManager.habits.filter({ $0.isEnabled }).count > 3 {
                    Text("他 \(habitManager.habits.filter { $0.isEnabled }.count - 3) 件")
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                }
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
    }


    // MARK: - Apple Healthデータカード（2列レイアウト）
    private var calorieAndWeightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ヘッダー
            HStack(spacing: 5) {
                Image(systemName: "heart.text.square.fill")
                    .foregroundColor(Color(red: 1.0, green: 0.294, blue: 0.294))
                Text("今日のApple Health").fontWeight(.black)
                Spacer()
                if healthKit.isAvailable && healthKit.isAuthorized {
                    // 更新ボタン
                    Button {
                        Task {
                            await healthKit.fetchAll()
                            await loadData()
                        }
                    } label: {
                        Image(systemName: healthKit.isLoading ? "arrow.circlepath" : "arrow.clockwise")
                            .font(.caption)
                            .foregroundColor(Color.duoSubtitle)
                            .rotationEffect(healthKit.isLoading ? .degrees(360) : .degrees(0))
                            .animation(healthKit.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: healthKit.isLoading)
                    }
                    .disabled(healthKit.isLoading)

                    // 設定ボタン
                    Button {
                        showIntakeGoalEdit = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.caption)
                            .foregroundColor(Color.duoGreen)
                    }
                }
            }
            .font(.subheadline)
            .foregroundColor(Color.duoDark)

            if !healthKit.isAvailable || !healthKit.isAuthorized {
                // 未連携時のプレースホルダー
                Button {
                    Task {
                        await healthKit.requestAuthorization()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "heart.text.square")
                            .font(.title3)
                            .foregroundColor(Color.duoSubtitle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apple Healthと連動する")
                                .font(.subheadline).fontWeight(.bold)
                                .foregroundColor(Color.duoDark)
                            Text("睡眠・体重・歩数・心拍数・カロリー・摂取記録")
                                .font(.caption)
                                .foregroundColor(Color.duoSubtitle)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(Color.duoSubtitle)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            } else {
                healthMetricsGrid
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
    }

    // MARK: - ヘルスメトリクスグリッド（型境界を分離してスタックオーバーフロー防止）
    private var healthMetricsGrid: some View {
        VStack(spacing: 8) {
            integratedSleepCard
            HStack(spacing: 8) {
                bodyWeightFatCard
                exerciseTimeCalCard
            }
            healthMetricsGridTop
            calorieBalanceBarCard
            healthMetricsGridBottom
        }
    }

    @ViewBuilder
    private var healthMetricsGridTop: some View {
        HStack(spacing: 8) {
            compactHealthItem(
                icon: "figure.walk",
                iconColor: Color.duoGreen,
                label: "歩数",
                value: Double(healthKit.todaySteps),
                goal: 10000.0,
                unit: "歩",
                formatValue: { "\(Int($0))" }
            )
            Color.clear.frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var healthMetricsGridBottom: some View {
        heartRateWithHRVItem
        HStack(spacing: 8) {
            compactHealthItem(
                icon: "brain.head.profile",
                iconColor: Color.duoPurple,
                label: "マインドフル",
                value: healthKit.todayMindfulnessMinutes,
                goal: nil,
                unit: "分",
                formatValue: { String(format: "%.0f", $0) + " (\(healthKit.todayMindfulnessSessions)回)" },
                healthKitURL: "x-apple-health://mindfulness"
            )
            compactHealthItem(
                icon: "sun.max.fill",
                iconColor: Color.duoYellow,
                label: "日光下時間",
                value: healthKit.todayDaylightMinutes,
                goal: 30.0,
                unit: "分",
                formatValue: { "\(Int($0))" }
            )
        }
        HStack(spacing: 8) {
            compactHealthItemThird(
                icon: "drop.fill",
                iconColor: Color.duoBlue,
                label: "水分",
                value: Double(todayIntake.totalWaterMl),
                goal: Double(intakeGoals.dailyWaterGoal),
                unit: "ml",
                formatValue: { "\(Int($0))" },
                healthKitURL: "x-apple-health://dietarywater"
            )
            compactHealthItemThird(
                icon: "cup.and.saucer.fill",
                iconColor: Color.duoBrown,
                label: "カフェイン",
                value: Double(todayIntake.totalCaffeineMg),
                goal: Double(intakeGoals.dailyCaffeineLimit),
                unit: "mg",
                formatValue: { "\(Int($0))" },
                isReverse: true,
                healthKitURL: "x-apple-health://dietarycaffeine"
            )
            compactHealthItemThird(
                icon: "wineglass.fill",
                iconColor: Color.duoPurple,
                label: "アルコール",
                value: todayIntake.totalAlcoholG,
                goal: intakeGoals.dailyAlcoholLimit,
                unit: "g",
                formatValue: { String(format: "%.1f", $0) },
                isReverse: true,
                healthKitURL: "x-apple-health://nutrition"
            )
        }
        if let analysis = pfcAnalysis, analysis.score > 0 {
            pfcBalanceChart(analysis)
        }
    }

    // MARK: - ポイントカード
    private var pointsCard: some View {
        Button {
            // TODO: 日別のトレーニング詳細画面を表示
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                // ヘッダー
                HStack(spacing: 5) {
                    Image(systemName: "star.fill")
                        .foregroundColor(Color.duoGold)
                    Text("ポイント")
                        .fontWeight(.black)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(Color.duoSubtitle)
                }
                .font(.subheadline)
                .foregroundColor(Color.duoDark)

                // ポイント表示
                HStack(spacing: 20) {
                    // 今日のポイント
                    VStack(alignment: .leading, spacing: 4) {
                        Text("今日")
                            .font(.caption)
                            .foregroundColor(Color.duoSubtitle)
                        HStack(alignment: .bottom, spacing: 4) {
                            Text("\(totalXP)")
                                .font(.system(size: 34, weight: .black, design: .rounded))
                                .foregroundColor(Color.duoGreen)
                            Text("XP")
                                .font(.caption)
                                .foregroundColor(Color.duoSubtitle)
                                .padding(.bottom, 4)
                        }
                    }

                    Divider()
                        .frame(height: 40)

                    // 総ポイント
                    VStack(alignment: .leading, spacing: 4) {
                        Text("総ポイント")
                            .font(.caption)
                            .foregroundColor(Color.duoSubtitle)
                        HStack(alignment: .bottom, spacing: 4) {
                            Text("\(authManager.userProfile?.totalPoints ?? 0)")
                                .font(.system(size: 34, weight: .black, design: .rounded))
                                .foregroundColor(Color.duoOrange)
                            Text("XP")
                                .font(.caption)
                                .foregroundColor(Color.duoSubtitle)
                                .padding(.bottom, 4)
                        }
                    }

                    Spacer()
                }
            }
            .padding(12)
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - コンパクトヘルスアイテム（半分幅）
    private func compactHealthItem(
        icon: String,
        iconColor: Color,
        label: String,
        value: Double,
        goal: Double?,
        unit: String,
        formatValue: (Double) -> String,
        isReverse: Bool = false,
        healthKitURL: String? = nil
    ) -> some View {
        let percent = goal != nil && goal! > 0 ? Int((value / goal!) * 100) : 0
        let isOver = goal != nil && value > goal!
        let isGood = goal == nil ? (value > 0) : (isReverse ? (value <= goal!) : (value >= goal!))
        let displayColor = (isOver && isReverse) ? Color.red : (isGood ? Color.duoGreen : Color.duoOrange)

        let content = VStack(alignment: .leading, spacing: 4) {
            // アイコン + ラベル + ％
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(iconColor)
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.duoDark)
                Spacer()
                // 目標がある場合は％を表示
                if let _ = goal {
                    VStack(spacing: 0) {
                        Text("\(percent)%")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(displayColor)
                        if isOver && isReverse {
                            Text("過剰")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(Color.red)
                        }
                    }
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(displayColor.opacity(0.15))
                    .cornerRadius(3)
                }
            }

            // 値表示
            HStack(alignment: .bottom, spacing: 2) {
                Text(value > 0 ? formatValue(value) : "—")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor((isOver && isReverse) ? Color.red : (isGood ? Color.duoGreen : Color.duoDark))
                Text(unit)
                    .font(.system(size: 9))
                    .foregroundColor(Color.duoSubtitle)
                    .padding(.bottom, 1)
            }

            // プログレスバー（目標がある場合のみ）
            if let _ = goal {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.systemGray5)).frame(height: 3)
                        Capsule().fill(isGood ? Color.duoGreen : iconColor.opacity(0.7))
                            .frame(width: max(3, geo.size.width * CGFloat(percent) / 100), height: 3)
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(iconColor.opacity(0.08))
        .cornerRadius(8)

        if let url = healthKitURL {
            return AnyView(
                Button {
                    if let healthURL = URL(string: url) {
                        UIApplication.shared.open(healthURL)
                    }
                } label: {
                    content
                }
                .buttonStyle(.plain)
            )
        } else {
            return AnyView(content)
        }
    }

    // MARK: - コンパクトヘルスアイテム（1/3幅）
    private func compactHealthItemThird(
        icon: String,
        iconColor: Color,
        label: String,
        value: Double,
        goal: Double?,
        unit: String,
        formatValue: (Double) -> String,
        isReverse: Bool = false,
        healthKitURL: String? = nil
    ) -> some View {
        let percent = goal != nil && goal! > 0 ? Int((value / goal!) * 100) : 0
        let isOver = goal != nil && value > goal!
        let isGood = goal == nil ? (value > 0) : (isReverse ? (value <= goal!) : (value >= goal!))

        // 達成度に応じた色を計算
        let displayColor: Color
        if label == "水分" {
            // 水分: 多いほど緑（0-100%でグラデーション）
            if percent >= 100 {
                displayColor = Color.duoGreen
            } else if percent >= 70 {
                displayColor = Color.duoGreen.opacity(0.7)
            } else if percent >= 40 {
                displayColor = Color.duoOrange
            } else {
                displayColor = Color.duoDark
            }
        } else if label == "カフェイン" || label == "アルコール" {
            // カフェインとアルコール: 多いほど赤
            if isOver || percent >= 100 {
                displayColor = Color.red
            } else if percent >= 70 {
                displayColor = Color.duoOrange
            } else if percent >= 40 {
                displayColor = Color.duoGreen.opacity(0.7)
            } else {
                displayColor = Color.duoGreen
            }
        } else {
            // その他: 既存のロジック
            displayColor = (isOver && isReverse) ? Color.red : (isGood ? Color.duoGreen : Color.duoOrange)
        }

        let content = VStack(alignment: .center, spacing: 3) {
            // アイコン
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(iconColor)

            // ラベル
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Color.duoDark)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            // 値表示
            VStack(spacing: 1) {
                Text(value > 0 ? formatValue(value) : "—")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor((isOver && isReverse) ? Color.red : (isGood ? Color.duoGreen : Color.duoDark))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(unit)
                    .font(.system(size: 7))
                    .foregroundColor(Color.duoSubtitle)
            }

            // プログレスバー（目標がある場合のみ）
            if let _ = goal {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.systemGray5)).frame(height: 2)
                        Capsule().fill(displayColor)
                            .frame(width: max(2, geo.size.width * CGFloat(percent) / 100), height: 2)
                    }
                }
                .frame(height: 2)

                // パーセント表示
                Text("\(percent)%")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(displayColor)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(iconColor.opacity(0.08))
        .cornerRadius(8)

        if let url = healthKitURL {
            return AnyView(
                Button {
                    if let healthURL = URL(string: url) {
                        UIApplication.shared.open(healthURL)
                    }
                } label: {
                    content
                }
                .buttonStyle(.plain)
            )
        } else {
            return AnyView(content)
        }
    }

    // MARK: - 達成アイコン行（今日の状況カード内）

    @ViewBuilder
    private var goalAchievementIconsRow: some View {
        let goals = timeSlotManager.settings.globalGoals
        let prog = timeSlotManager.progress.globalProgress

        // カスタム目標のみ表示（睡眠・PFC・体重は上の行で表示済み）
        let customGoals = goals.customGoals.filter { $0.isEnabled }

        if !customGoals.isEmpty {
            HStack(spacing: 10) {
                ForEach(customGoals) { goal in
                    let achieved = prog.completedCustomGoalIds.contains(goal.id)
                    Button {
                        Task { await timeSlotManager.toggleCustomGoal(id: goal.id) }
                    } label: {
                        goalIconDot(emoji: goal.emoji, achieved: achieved, hasData: true)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(.vertical, 2)
        }
    }

    private func goalIconDot(emoji: String, achieved: Bool, hasData: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Text(emoji)
                .font(.system(size: 22))
                .opacity(hasData ? 1.0 : 0.35)

            Circle()
                .fill(achieved ? Color.duoGreen : (hasData ? Color.duoRed : Color(.systemGray4)))
                .frame(width: 8, height: 8)
                .offset(x: 2, y: 2)
        }
        .frame(width: 32, height: 32)
    }

    // MARK: - 体重・体脂肪カード
    private var bodyWeightFatCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "scalemass.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Color.duoBlue)
                Text("体重・体脂肪")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.duoDark)
            }

            HStack(spacing: 8) {
                // 体重
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .bottom, spacing: 2) {
                        Text(healthKit.latestBodyMass > 0 ? String(format: "%.1f", healthKit.latestBodyMass) : "—")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(healthKit.latestBodyMass > 0 ? Color.duoGreen : Color.duoDark)
                        Text("kg")
                            .font(.system(size: 9))
                            .foregroundColor(Color.duoSubtitle)
                            .padding(.bottom, 1)
                    }
                    if let delta = healthKit.weeklyBodyMassChange {
                        weeklyDeltaLabel(delta: delta, unit: "kg", decimalPlaces: 1)
                    }
                }

                Divider()
                    .frame(height: 28)

                // 体脂肪
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .bottom, spacing: 2) {
                        Text(healthKit.latestBodyFatPercentage > 0 ? String(format: "%.0f", healthKit.latestBodyFatPercentage) : "—")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(healthKit.latestBodyFatPercentage > 0 ? Color.duoGreen : Color.duoDark)
                        Text("%")
                            .font(.system(size: 9))
                            .foregroundColor(Color.duoSubtitle)
                            .padding(.bottom, 1)
                    }
                    if let delta = healthKit.weeklyBodyFatChange {
                        weeklyDeltaLabel(delta: delta, unit: "%", decimalPlaces: 0)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.duoBlue.opacity(0.08))
        .cornerRadius(8)
    }

    // MARK: - アクティブ運動時間カード
    private var exerciseTimeCalCard: some View {
        let pct = min(100, Int(Double(healthKit.todayWorkoutMinutes) / 30.0 * 100))
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "figure.run")
                    .font(.system(size: 10))
                    .foregroundColor(Color.duoGreen)
                Text("運動時間・Cal")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.duoDark)
            }
            HStack(alignment: .center, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .bottom, spacing: 2) {
                        Text(healthKit.todayWorkoutMinutes > 0 ? "\(healthKit.todayWorkoutMinutes)" : "—")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundColor(healthKit.todayWorkoutMinutes >= 30 ? Color.duoGreen : Color.duoDark)
                        Text("分")
                            .font(.system(size: 8))
                            .foregroundColor(Color.duoSubtitle)
                            .padding(.bottom, 1)
                    }
                    Text("目標\(pct)%")
                        .font(.system(size: 7))
                        .foregroundColor(pct >= 100 ? Color.duoGreen : Color.duoOrange)
                }
                Divider().frame(height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .bottom, spacing: 2) {
                        Text(healthKit.todayActiveCalories > 0 ? "\(Int(healthKit.todayActiveCalories))" : "—")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundColor(Color.duoOrange)
                        Text("kcal")
                            .font(.system(size: 8))
                            .foregroundColor(Color.duoSubtitle)
                            .padding(.bottom, 1)
                    }
                    Text("活動Cal")
                        .font(.system(size: 7))
                        .foregroundColor(Color.duoSubtitle)
                }
                Spacer()
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.duoGreen.opacity(0.08))
        .cornerRadius(8)
    }

    /// 1週間変動ラベル（▲▼矢印付き）
    @ViewBuilder
    private func weeklyDeltaLabel(delta: Double, unit: String, decimalPlaces: Int) -> some View {
        let absVal = abs(delta)
        let fmt = String(format: "%.\(decimalPlaces)f", absVal)
        let (arrow, color): (String, Color) = {
            if delta > 0.009 { return ("▲", Color(red: 1.0, green: 0.29, blue: 0.29)) }
            if delta < -0.009 { return ("▼", Color.duoGreen) }
            return ("→", Color.duoSubtitle)
        }()
        HStack(spacing: 1) {
            Text(arrow).font(.system(size: 8, weight: .bold)).foregroundColor(color)
            Text(delta == 0 ? "0\(unit)" : "\(fmt)\(unit)")
                .font(.system(size: 8, weight: .bold)).foregroundColor(color)
            Text("7日").font(.system(size: 7)).foregroundColor(Color.duoSubtitle)
        }
    }

    // MARK: - カロリー収支バーカード
    private var calorieBalanceBarCard: some View {
        CalorieBalanceBarCard(
            totalConsumed: healthKit.todayTotalCalories,
            intake: Double(todayIntake.totalCalories)
        )
    }

    // MARK: - 旧カロリー収支カード（削除予定）
    private var calorieBalanceCard: some View {
        let totalConsumed = healthKit.todayTotalCalories  // 安静時＋アクティブ
        let intake = Double(todayIntake.totalCalories)
        let balance = intake - totalConsumed
        let isPositive = balance > 0
        let absBalance = abs(balance)

        return VStack(alignment: .leading, spacing: 6) {
            // ヘッダー
            HStack(spacing: 4) {
                Image(systemName: "equal.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(isPositive ? Color.red : Color.duoBlue)
                Text("カロリー収支")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.duoDark)
                Spacer()
            }

            // 収支表示
            HStack(alignment: .bottom, spacing: 4) {
                Text(isPositive ? "+" : "-")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(isPositive ? Color.red : Color.duoBlue)
                Text("\(Int(absBalance))")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(isPositive ? Color.red : Color.duoBlue)
                Text("kcal")
                    .font(.system(size: 9))
                    .foregroundColor(Color.duoSubtitle)
                    .padding(.bottom, 2)
            }

            // 傾向表示
            HStack(spacing: 4) {
                if isPositive {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color.red)
                    Text("太り傾向")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.red)
                } else if balance < 0 {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color.duoBlue)
                    Text("痩せ傾向")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.duoBlue)
                } else {
                    Image(systemName: "equal.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color.duoGreen)
                    Text("バランス")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.duoGreen)
                }

                Spacer()

                // 7,200kcalで約1kg換算
                if absBalance > 0 {
                    let kgPerDay = absBalance / 7200.0
                    Text("約\(String(format: "%.2f", kgPerDay))kg/日")
                        .font(.system(size: 8))
                        .foregroundColor(Color.duoSubtitle)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background((isPositive ? Color.red : Color.duoBlue).opacity(0.08))
            .cornerRadius(5)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: isPositive ? [Color.red.opacity(0.05), Color.red.opacity(0.12)] : [Color.duoBlue.opacity(0.05), Color.duoBlue.opacity(0.12)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isPositive ? Color.red.opacity(0.3) : Color.duoBlue.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - 健康メトリック行（目標付き）
    private func healthGoalRow(
        icon: String,
        iconColor: Color,
        label: String,
        value: Double,
        goal: Double,
        unit: String,
        formatValue: (Double) -> String
    ) -> some View {
        let percent = goal > 0 ? min(Int((value / goal) * 100), 100) : 0
        let isAchieved = value >= goal

        return VStack(alignment: .leading, spacing: 6) {
            // ヘッダー行
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(iconColor)
                Text(label)
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(Color.duoDark)
                Spacer()
                Text("\(percent)%")
                    .font(.caption2).fontWeight(.bold)
                    .foregroundColor(isAchieved ? Color.duoGreen : Color.duoOrange)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background((isAchieved ? Color.duoGreen : Color.duoOrange).opacity(0.12))
                    .cornerRadius(5)
            }

            // 値表示 & プログレスバー
            HStack(alignment: .bottom, spacing: 6) {
                Text(value > 0 ? formatValue(value) : "—")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(isAchieved ? Color.duoGreen : Color.duoDark)
                Text("/ \(formatValue(goal)) \(unit)")
                    .font(.caption2).fontWeight(.semibold)
                    .foregroundColor(Color.duoSubtitle)
                    .padding(.bottom, 2)
            }

            // プログレスバー
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5)).frame(height: 6)
                    Capsule().fill(
                        LinearGradient(
                            colors: isAchieved ? [Color.duoGreen, Color(red: 0.57, green: 0.9, blue: 0.16)] : [iconColor.opacity(0.7), iconColor],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(6, geo.size.width * CGFloat(percent) / 100), height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - 体重・体脂肪行（測定回数目標付き）
    private func healthWeightRow() -> some View {
        let measurementGoal = 1  // 1日1回の測定で目標達成
        let measurements = healthKit.todayBodyMassMeasurements
        let isComplete = measurements >= measurementGoal

        return VStack(alignment: .leading, spacing: 6) {
            // ヘッダー行
            HStack(spacing: 6) {
                Image(systemName: "scalemass.fill")
                    .font(.caption)
                    .foregroundColor(Color.duoBlue)
                Text("体重・体脂肪")
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(Color.duoDark)
                Spacer()
                // 測定完了ステータスのみ表示（回数は非表示）
                if isComplete {
                    Text("✓")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(Color.duoGreen)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.duoGreen.opacity(0.12))
                        .cornerRadius(5)
                }
            }

            // 値表示
            HStack(spacing: 10) {
                // 体重
                HStack(spacing: 4) {
                    Image(systemName: "scalemass")
                        .font(.system(size: 10))
                        .foregroundColor(Color.duoBlue)
                    if healthKit.latestBodyMass > 0 {
                        Text(String(format: "%.1f kg", healthKit.latestBodyMass))
                            .font(.caption).fontWeight(.bold)
                            .foregroundColor(Color.duoDark)
                    } else {
                        Text("未測定")
                            .font(.caption2).foregroundColor(Color.duoSubtitle)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color(red: 0.878, green: 0.941, blue: 1.0))
                .cornerRadius(6)

                // 体脂肪
                HStack(spacing: 4) {
                    Image(systemName: "percent")
                        .font(.system(size: 10))
                        .foregroundColor(Color.duoOrange)
                    if healthKit.latestBodyFatPercentage > 0 {
                        Text(String(format: "%.1f%%", healthKit.latestBodyFatPercentage))
                            .font(.caption).fontWeight(.bold)
                            .foregroundColor(Color.duoDark)
                    } else {
                        Text("未測定")
                            .font(.caption2).foregroundColor(Color.duoSubtitle)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color(red: 1.0, green: 0.925, blue: 0.878))
                .cornerRadius(6)
            }

            // メッセージ
            if !isComplete {
                Text("⚖️ 今日の測定をしましょう")
                    .font(.system(size: 10)).fontWeight(.semibold)
                    .foregroundColor(Color.duoSubtitle)
            } else {
                Text("✅ 今日の測定完了！")
                    .font(.system(size: 10)).fontWeight(.semibold)
                    .foregroundColor(Color.duoGreen)
            }
        }
    }

    // MARK: - 摂取記録カード
    private var intakeGoalsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ヘッダー
            HStack(spacing: 5) {
                Image(systemName: "fork.knife")
                    .foregroundColor(Color.duoOrange)
                Text("今日の摂取記録").fontWeight(.black)
                Spacer()
                Button {
                    showIntakeGoalEdit = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.caption)
                        .foregroundColor(Color.duoGreen)
                }
            }
            .font(.subheadline)
            .foregroundColor(Color.duoDark)

            VStack(spacing: 10) {
                // 摂取カロリー
                intakeGoalRow(
                    icon: "flame.fill",
                    iconColor: Color.duoOrange,
                    label: "摂取カロリー",
                    value: Double(todayIntake.totalCalories),
                    goal: Double(intakeGoals.dailyCalorieGoal),
                    unit: "kcal",
                    formatValue: { "\(Int($0))" },
                    isReverse: false
                )

                Divider()

                // 水分
                intakeGoalRow(
                    icon: "drop.fill",
                    iconColor: Color.duoBlue,
                    label: "水分摂取",
                    value: Double(todayIntake.totalWaterMl),
                    goal: Double(intakeGoals.dailyWaterGoal),
                    unit: "ml",
                    formatValue: { "\(Int($0))" },
                    isReverse: false
                )

                Divider()

                // カフェイン（上限を超えないように）
                intakeGoalRow(
                    icon: "cup.and.saucer.fill",
                    iconColor: Color.duoBrown,
                    label: "カフェイン",
                    value: Double(todayIntake.totalCaffeineMg),
                    goal: Double(intakeGoals.dailyCaffeineLimit),
                    unit: "mg",
                    formatValue: { "\(Int($0))" },
                    isReverse: true
                )

                Divider()

                // アルコール（上限を超えないように）
                intakeGoalRow(
                    icon: "wineglass.fill",
                    iconColor: Color.duoPurple,
                    label: "アルコール",
                    value: todayIntake.totalAlcoholG,
                    goal: intakeGoals.dailyAlcoholLimit,
                    unit: "g",
                    formatValue: { String(format: "%.1f", $0) },
                    isReverse: true
                )
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
    }

    // MARK: - 摂取目標行（上限・下限対応）
    private func intakeGoalRow(
        icon: String,
        iconColor: Color,
        label: String,
        value: Double,
        goal: Double,
        unit: String,
        formatValue: (Double) -> String,
        isReverse: Bool  // true = 上限（少ない方が良い）、false = 下限（多い方が良い）
    ) -> some View {
        let percent = goal > 0 ? min(Int((value / goal) * 100), 100) : 0
        let isGood = isReverse ? (value <= goal) : (value >= goal)

        return VStack(alignment: .leading, spacing: 6) {
            // ヘッダー行
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(iconColor)
                Text(label)
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(Color.duoDark)
                Spacer()
                Text("\(percent)%")
                    .font(.caption2).fontWeight(.bold)
                    .foregroundColor(isGood ? Color.duoGreen : Color.duoOrange)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background((isGood ? Color.duoGreen : Color.duoOrange).opacity(0.12))
                    .cornerRadius(5)
            }

            // 値表示 & プログレスバー
            HStack(alignment: .bottom, spacing: 6) {
                Text(value > 0 ? formatValue(value) : "—")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(isGood ? Color.duoGreen : Color.duoDark)
                Text("/ \(formatValue(goal)) \(unit)")
                    .font(.caption2).fontWeight(.semibold)
                    .foregroundColor(Color.duoSubtitle)
                    .padding(.bottom, 2)
            }

            // プログレスバー
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5)).frame(height: 6)
                    Capsule().fill(
                        LinearGradient(
                            colors: isGood ? [Color.duoGreen, Color(red: 0.57, green: 0.9, blue: 0.16)] : [iconColor.opacity(0.7), iconColor],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(6, geo.size.width * CGFloat(percent) / 100), height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - 健康目標編集シート
    private var healthGoalEditSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Apple Health目標を設定")
                    .font(.headline)
                    .foregroundColor(Color.duoDark)
                    .padding(.top, 20)

                // 睡眠時間
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "bed.double.fill")
                            .foregroundColor(Color(red: 0.451, green: 0.369, blue: 0.937))
                        Text("睡眠時間")
                            .font(.subheadline).fontWeight(.bold)
                        Spacer()
                    }
                    HStack {
                        Button {
                            if tempSleepGoal > 1.0 {
                                tempSleepGoal -= 0.5
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                                .foregroundColor(Color.duoOrange)
                        }

                        Spacer()

                        VStack(spacing: 2) {
                            Text(String(format: "%.1f", tempSleepGoal))
                                .font(.system(size: 40, weight: .black, design: .rounded))
                                .foregroundColor(Color.duoGreen)
                            Text("時間")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(Color.duoSubtitle)
                        }

                        Spacer()

                        Button {
                            tempSleepGoal += 0.5
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(Color.duoGreen)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding()
                .background(Color(red: 0.918, green: 0.902, blue: 1.0))
                .cornerRadius(12)

                // 歩数
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "figure.walk")
                            .foregroundColor(Color.duoGreen)
                        Text("歩数")
                            .font(.subheadline).fontWeight(.bold)
                        Spacer()
                    }
                    HStack {
                        Button {
                            if tempStepsGoal > 1000 {
                                tempStepsGoal -= 1000
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                                .foregroundColor(Color.duoOrange)
                        }

                        Spacer()

                        VStack(spacing: 2) {
                            Text("\(tempStepsGoal)")
                                .font(.system(size: 40, weight: .black, design: .rounded))
                                .foregroundColor(Color.duoGreen)
                            Text("歩")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(Color.duoSubtitle)
                        }

                        Spacer()

                        Button {
                            tempStepsGoal += 1000
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(Color.duoGreen)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding()
                .background(Color(red: 0.843, green: 1.0, blue: 0.722))
                .cornerRadius(12)

                // 消費カロリー
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "flame.fill")
                            .foregroundColor(Color.duoOrange)
                        Text("消費カロリー")
                            .font(.subheadline).fontWeight(.bold)
                        Spacer()
                    }
                    HStack {
                        Button {
                            if tempCaloriesGoal > 100 {
                                tempCaloriesGoal -= 50
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                                .foregroundColor(Color.duoOrange)
                        }

                        Spacer()

                        VStack(spacing: 2) {
                            Text("\(tempCaloriesGoal)")
                                .font(.system(size: 40, weight: .black, design: .rounded))
                                .foregroundColor(Color.duoGreen)
                            Text("kcal")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(Color.duoSubtitle)
                        }

                        Spacer()

                        Button {
                            tempCaloriesGoal += 50
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(Color.duoGreen)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding()
                .background(Color(red: 1.0, green: 0.953, blue: 0.878))
                .cornerRadius(12)

                Button {
                    // 目標を保存（現在はローカルのみ、将来的にFirestoreに保存）
                    // TODO: Firestoreに保存する処理を追加
                    showHealthGoalEdit = false
                } label: {
                    Text("目標を設定")
                        .font(.headline)
                        .fontWeight(.black)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [Color.duoGreen, Color(red: 0.18, green: 0.62, blue: 0.0)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                }
                .padding(.horizontal, 20)

                Spacer()
            }
            .padding(.horizontal)
            .navigationTitle("健康目標設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        showHealthGoalEdit = false
                    }
                }
            }
        }
    }

    // MARK: - カロリー目標編集シート
    private var calorieGoalEditSheet: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("1日の目標消費カロリーを設定")
                    .font(.headline)
                    .foregroundColor(Color.duoDark)
                    .padding(.top, 20)

                VStack(spacing: 16) {
                    HStack {
                        Button {
                            if tempCalorieTarget > 100 {
                                tempCalorieTarget -= 50
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.largeTitle)
                                .foregroundColor(Color.duoOrange)
                        }

                        Spacer()

                        VStack(spacing: 4) {
                            Text("\(tempCalorieTarget)")
                                .font(.system(size: 56, weight: .black, design: .rounded))
                                .foregroundColor(Color.duoGreen)
                            Text("kcal")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(Color.duoSubtitle)
                        }

                        Spacer()

                        Button {
                            tempCalorieTarget += 50
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.largeTitle)
                                .foregroundColor(Color.duoGreen)
                        }
                    }
                    .padding(.horizontal, 32)

                    Text("週間目標に基づいたデフォルト値から調整できます")
                        .font(.caption)
                        .foregroundColor(Color.duoSubtitle)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button {
                    Task {
                        await authManager.saveDailyCalorieGoal(targetCalories: tempCalorieTarget)
                        await loadData()
                        showCalorieGoalEdit = false
                    }
                } label: {
                    Text("目標を設定")
                        .font(.headline)
                        .fontWeight(.black)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [Color.duoGreen, Color(red: 0.18, green: 0.62, blue: 0.0)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                }
                .padding(.horizontal, 32)

                Spacer()
            }
            .navigationTitle("目標カロリー設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        showCalorieGoalEdit = false
                    }
                }
            }
        }
    }

    // MARK: - 90日チャレンジ
    private var challengeCard: some View {
        let streak   = authManager.userProfile?.streak ?? 0
        let progress = min(Double(streak) / 90.0, 1.0)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "flag.fill")
                    Text("90日チャレンジ").fontWeight(.black)
                }
                .font(.subheadline)
                .foregroundColor(Color.duoGreen)
                Spacer()
                Text("\(streak) / 90日")
                    .font(.caption).fontWeight(.black)
                    .foregroundColor(Color.duoGreen)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Color.duoGreen.opacity(0.12))
                    .cornerRadius(8)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5)).frame(height: 12)
                    Capsule().fill(
                        LinearGradient(colors: [Color.duoGreen, Color.duoBlue],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: max(12, geo.size.width * CGFloat(progress)), height: 12)
                }
            }
            .frame(height: 12)
            Text("毎日続けてフィットネス習慣を身につけよう！")
                .font(.caption).foregroundColor(Color.duoSubtitle)
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
    }


    // MARK: - フローティングメニューパネル
    private var floatingMenuPanel: some View {
        VStack(spacing: 0) {
            // メニュータイトル
            HStack {
                Text("メニュー")
                    .font(.headline).fontWeight(.black)
                    .foregroundColor(Color.duoDark)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showMenu = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(Color.duoSubtitle)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            // メニュー項目
            VStack(spacing: 0) {
                NavigationLink(destination: TimeSlotGoalsView()) {
                    menuRow(icon: "🕐", label: "時間帯別の目標", color: Color.duoPurple)
                }
                Divider().padding(.leading, 60)

                NavigationLink(destination: WeeklyGoalView().environmentObject(authManager)) {
                    menuRow(icon: "🎯", label: "週間目標", color: Color.duoGreen)
                }

                Divider().padding(.leading, 60)

                NavigationLink(destination: HistoryView().environmentObject(authManager)) {
                    menuRow(icon: "📅", label: "履歴", color: Color.duoBlue)
                }

                Divider().padding(.leading, 60)

                NavigationLink(destination: HelpView()) {
                    menuRow(icon: "❓", label: "ヘルプ", color: Color.duoOrange)
                }

                Divider().padding(.leading, 60)

                Button {
                    authManager.signOut()
                    showMenu = false
                } label: {
                    menuRow(icon: "🚪", label: "ログアウト", color: Color.duoRed)
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color.white)
        .cornerRadius(20, corners: [.topLeft, .topRight])
        .shadow(color: Color.black.opacity(0.2), radius: 20, y: -5)
        .ignoresSafeArea(edges: .bottom)
    }

    private func menuRow(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 16) {
            Text(icon)
                .font(.title2)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.12))
                .cornerRadius(10)

            Text(label)
                .font(.body).fontWeight(.semibold)
                .foregroundColor(Color.duoDark)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(Color.duoSubtitle)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }

    // MARK: - フォトログボタン

    // MARK: - クイックメニュー
    private var quickMenu: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 5) {
                Image(systemName: "fork.knife")
                    .foregroundColor(Color.duoOrange)
                Text("クイック記録").fontWeight(.black)
                Spacer()
            }
            .font(.subheadline)
            .foregroundColor(Color.duoDark)

            // 行1: 朝食・昼食・夕食
            HStack(spacing: 8) {
                quickIntakeButton(emoji: "🌅", label: "朝食") {
                    confirmIntake(message: "朝食 \(intakeGoals.caloriesFor(mealType: .breakfast))kcal を記録しますか？") {
                        Task {
                            await authManager.recordMeal(mealType: .breakfast)
                            await updateTimeSlotForMeal(timestamp: Date())
                            await refreshIntakeData()
                        }
                    }
                }
                quickIntakeButton(emoji: "🍱", label: "昼食") {
                    confirmIntake(message: "昼食 \(intakeGoals.caloriesFor(mealType: .lunch))kcal を記録しますか？") {
                        Task {
                            await authManager.recordMeal(mealType: .lunch)
                            await updateTimeSlotForMeal(timestamp: Date())
                            await refreshIntakeData()
                        }
                    }
                }
                quickIntakeButton(emoji: "🍽️", label: "夕食") {
                    confirmIntake(message: "夕食 \(intakeGoals.caloriesFor(mealType: .dinner))kcal を記録しますか？") {
                        Task {
                            await authManager.recordMeal(mealType: .dinner)
                            await updateTimeSlotForMeal(timestamp: Date())
                            await refreshIntakeData()
                        }
                    }
                }
            }

            // 行2: スナック・ドリンク・アルコール
            HStack(spacing: 8) {
                quickIntakeButton(emoji: "🍫", label: "スナック") {
                    confirmIntake(message: "スナック \(intakeGoals.caloriesFor(mealType: .snack))kcal を記録しますか？") {
                        Task {
                            await authManager.recordMeal(mealType: .snack)
                            await updateTimeSlotForMeal(timestamp: Date())
                            await refreshIntakeData()
                        }
                    }
                }

                // ドリンク（水 / コーヒーを選択）
                Menu {
                    Button {
                        confirmIntake(message: "水 \(intakeGoals.waterPerCup)ml を記録しますか？") {
                            Task {
                                await authManager.recordWater()
                                await updateTimeSlotForDrink(timestamp: Date())
                                await refreshIntakeData()
                            }
                        }
                    } label: { Label("💧 水", systemImage: "") }
                    Button {
                        confirmIntake(message: "コーヒー \(intakeGoals.coffeePerCup)ml (カフェイン \(intakeGoals.caffeinePerCup)mg) を記録しますか？") {
                            Task {
                                await authManager.recordCoffee()
                                await updateTimeSlotForDrink(timestamp: Date())
                                await refreshIntakeData()
                            }
                        }
                    } label: { Label("☕ コーヒー", systemImage: "") }
                } label: {
                    quickMenuItem(icon: "🥤", label: "ドリンク", color: Color.duoBlue)
                }
                Menu {
                    Button {
                        confirmIntake(message: "ビール (アルコール \(String(format: "%.1f", AlcoholType.beer.alcoholG))g) を記録しますか？") {
                            Task {
                                await authManager.recordAlcohol(alcoholType: .beer)
                                await updateTimeSlotForDrink(timestamp: Date())
                                await refreshIntakeData()
                            }
                        }
                    } label: {
                        Label("🍺 ビール", systemImage: "")
                    }
                    Button {
                        confirmIntake(message: "ワイン (アルコール \(String(format: "%.1f", AlcoholType.wine.alcoholG))g) を記録しますか？") {
                            Task {
                                await authManager.recordAlcohol(alcoholType: .wine)
                                await updateTimeSlotForDrink(timestamp: Date())
                                await refreshIntakeData()
                            }
                        }
                    } label: {
                        Label("🍷 ワイン", systemImage: "")
                    }
                    Button {
                        confirmIntake(message: "酎ハイ (アルコール \(String(format: "%.1f", AlcoholType.chuhai.alcoholG))g) を記録しますか？") {
                            Task {
                                await authManager.recordAlcohol(alcoholType: .chuhai)
                                await updateTimeSlotForDrink(timestamp: Date())
                                await refreshIntakeData()
                            }
                        }
                    } label: {
                        Label("🥃 酎ハイ", systemImage: "")
                    }
                    Button {
                        confirmIntake(message: "ノンアルコール (アルコール 0g) を記録しますか？") {
                            Task {
                                await authManager.recordAlcohol(alcoholType: .nonAlcoholic)
                                await updateTimeSlotForDrink(timestamp: Date())
                                await refreshIntakeData()
                            }
                        }
                    } label: {
                        Label("🚫 ノンアル", systemImage: "")
                    }
                } label: {
                    VStack(spacing: 5) {
                        Text("🍺").font(.title3)
                        Text("アルコール")
                            .font(.caption2).fontWeight(.bold)
                            .foregroundColor(Color.duoDark)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.duoPurple.opacity(0.12))
                    .cornerRadius(12)
                }
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
    }

    private func quickIntakeButton(emoji: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Text(emoji).font(.title3)
                Text(label)
                    .font(.caption2).fontWeight(.bold)
                    .foregroundColor(Color.duoDark)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.duoOrange.opacity(0.12))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private func quickMenuItem(icon: String, label: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Text(icon).font(.title3)
            Text(label)
                .font(.caption2).fontWeight(.bold)
                .foregroundColor(Color.duoDark)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.12))
        .cornerRadius(12)
    }

    private func emojiFor(_ name: String) -> String {
        let key = name.lowercased().replacingOccurrences(of: " ", with: "")
        let map = ["pushup": "💪", "push-up": "💪", "squat": "🏋️",
                   "situp": "🔥", "sit-up": "🔥", "lunge": "🦵",
                   "burpee": "⚡", "plank": "🧘"]
        for (k, v) in map { if key.contains(k) { return v } }
        return "🏃"
    }

    // MARK: - 摂取記録確認ヘルパー
    private func confirmIntake(message: String, action: @escaping () -> Void) {
        confirmMessage = message
        pendingIntakeAction = action
        showIntakeConfirm = true
    }

    private func refreshIntakeData() async {
        todayIntake = await authManager.getTodayIntakeSummary()
        intakeGoals = await authManager.getIntakeSettings()
    }

    // MARK: - 今日のセット構築
    private struct TodaySet: Identifiable {
        let id: String  // "am1", "pm2" などの固定ID
        let period: String
        let setNumber: Int
        let startTime: Date
        let exercises: [CompletedExercise]
        let totalReps: Int
        let totalPoints: Int
    }

    private func buildTodaySets(_ exercises: [CompletedExercise]) -> [TodaySet] {
        let sorted = exercises.sorted { $0.timestamp < $1.timestamp }
        var sessions: [[CompletedExercise]] = []
        var currentSession: [CompletedExercise] = []
        var lastTime: Date? = nil

        // 30分間隔でセッション分割
        for ex in sorted {
            if let last = lastTime, ex.timestamp.timeIntervalSince(last) <= 30 * 60 {
                currentSession.append(ex)
            } else {
                if !currentSession.isEmpty {
                    sessions.append(currentSession)
                }
                currentSession = [ex]
            }
            lastTime = ex.timestamp
        }
        if !currentSession.isEmpty {
            sessions.append(currentSession)
        }

        let calendar = Calendar.current
        var amCount = 0
        var pmCount = 0

        return sessions.map { session in
            guard let firstTime = session.first?.timestamp else {
                return TodaySet(
                    id: "empty",
                    period: "午後",
                    setNumber: 1,
                    startTime: Date(),
                    exercises: [],
                    totalReps: 0,
                    totalPoints: 0
                )
            }

            let hour = calendar.component(.hour, from: firstTime)
            let isAM = hour < 12
            let period = isAM ? "午前" : "午後"

            if isAM {
                amCount += 1
            } else {
                pmCount += 1
            }
            let setNumber = isAM ? amCount : pmCount

            // 固定IDを生成（例: "am1", "pm2"）
            let setId = "\(isAM ? "am" : "pm")\(setNumber)"

            return TodaySet(
                id: setId,
                period: period,
                setNumber: setNumber,
                startTime: firstTime,
                exercises: session,
                totalReps: session.reduce(0) { $0 + $1.reps },
                totalPoints: session.reduce(0) { $0 + $1.points }
            )
        }
    }

    // MARK: - セットサマリーボタン（折りたたみ可能）

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日(E)"
        return formatter.string(from: date)
    }

    // MARK: - 健康サマリーカード（HealthKit）
    @ViewBuilder
    private var healthSummaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // カードタイトル
            HStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .font(.subheadline)
                    .foregroundColor(Color(red: 1.0, green: 0.294, blue: 0.294))
                Text("今日の健康データ")
                    .font(.subheadline).fontWeight(.black)
                    .foregroundColor(Color.duoDark)
                Spacer()
                if !healthKit.isAuthorized {
                    Text("連動する →")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(Color.duoGreen)
                }
            }
            .padding(.bottom, 12)

            if !healthKit.isAvailable || !healthKit.isAuthorized {
                // 未連携時のプレースホルダー
                HStack(spacing: 10) {
                    Image(systemName: "heart.text.square")
                        .font(.title3)
                        .foregroundColor(Color.duoSubtitle)
                    Text("Apple Healthと連動するとデータが表示されます")
                        .font(.subheadline).foregroundColor(Color.duoSubtitle)
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 10) {
                    // 上段: 歩数 & カロリー
                    HStack(spacing: 8) {
                        healthMetricTile(
                            icon: "figure.walk",
                            value: healthKit.todaySteps > 0 ? "\(healthKit.todaySteps.formatted())" : "0",
                            unit: "歩",
                            bg: Color(red: 0.843, green: 1.0, blue: 0.722), // #D7FFB8
                            healthCategory: "StepCount"
                        )
                        healthMetricTile(
                            icon: "flame.fill",
                            value: healthKit.todayCalories > 0 ? "\(Int(healthKit.todayCalories))" : "0",
                            unit: "kcal",
                            bg: Color(red: 1.0, green: 0.953, blue: 0.878), // #FFF3E0
                            healthCategory: "ActiveEnergyBurned"
                        )
                    }

                    // 下段: 心拍数 & 睡眠
                    HStack(spacing: 8) {
                        healthMetricTile(
                            icon: "heart.fill",
                            value: healthKit.latestHeartRate > 0 ? "\(Int(healthKit.latestHeartRate))" : "—",
                            unit: "bpm",
                            bg: Color(red: 0.988, green: 0.894, blue: 0.925), // #FCE4EC
                            healthCategory: "HeartRate"
                        )
                        healthMetricTile(
                            icon: "bed.double.fill",
                            value: healthKit.lastNightTotalHours > 0.1 ? String(format: "%.1f", healthKit.lastNightTotalHours) : "—",
                            unit: "時間",
                            bg: Color(red: 0.918, green: 0.902, blue: 1.0), // #EAE6FF
                            healthCategory: "SleepAnalysis"
                        )
                    }
                }
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
        .task {
            // HealthKit権限確認と自動リクエスト
            if healthKit.isAvailable {
                if !healthKit.isAuthorized {
                    await healthKit.requestAuthorization()
                }
                // 権限取得後、データを必ず取得
                if healthKit.isAuthorized {
                    await healthKit.fetchAll()
                }
            }
        }
        .onAppear {
            // 画面表示時にも再取得（最新データ確保）
            if healthKit.isAvailable && healthKit.isAuthorized {
                Task {
                    await healthKit.fetchAll()
                }
            }
        }
    }

    private func healthMetricTile(icon: String, value: String, unit: String, bg: Color, healthCategory: String? = nil) -> some View {
        Button {
            if let category = healthCategory {
                openHealthApp(category: category)
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
                    .font(.system(size: 9)).fontWeight(.bold)
                    .foregroundColor(Color.duoSubtitle)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(bg)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private func openHealthApp(category: String) {
        if let url = URL(string: "x-apple-health://\(category)") {
            UIApplication.shared.open(url)
        }
    }

    private func openMindfulnessApp() {
        // Apple Watchのマインドフルネス（旧Breathe）アプリを起動
        // URLスキーム: com.apple.NanoMindfulness.watchkitapp://
        if let url = URL(string: "com.apple.NanoMindfulness.watchkitapp://") {
            UIApplication.shared.open(url) { success in
                if !success {
                    // Watch側のアプリが見つからない場合はiOS側のヘルスケアを開く
                    if let healthURL = URL(string: "x-apple-health://mindfulness") {
                        UIApplication.shared.open(healthURL)
                    }
                }
            }
        }
    }

    /// Apple Watchのマインドフルネスアプリを直接起動
    private func openWatchMindfulness() {
        // Watchアプリを直接起動する複数のURLスキームを試す
        let urlSchemes = [
            "com.apple.NanoMindfulness.watchkitapp://",  // マインドフルネス（旧Breathe）
            "x-apple-health://mindfulness",               // ヘルスケアのマインドフルネス
            "breathe://"                                   // 旧BreatheアプリのURLスキーム
        ]

        var openedSuccessfully = false

        for scheme in urlSchemes {
            if let url = URL(string: scheme) {
                UIApplication.shared.open(url) { success in
                    if success && !openedSuccessfully {
                        openedSuccessfully = true
                        print("[Mindfulness] Successfully opened: \(scheme)")
                    }
                }
                if openedSuccessfully {
                    break
                }
            }
        }

        // すべて失敗した場合はヘルスケアアプリを開く
        if !openedSuccessfully {
            if let healthURL = URL(string: "x-apple-health://") {
                UIApplication.shared.open(healthURL)
            }
        }
    }

    // MARK: - PFCバランス円グラフ
    private func pfcBalanceChart(_ analysis: PFCBalanceAnalysis) -> some View {
        let totalCalories = Int(healthKit.todayIntakeCalories)

        return VStack(alignment: .leading, spacing: 8) {
            // ヘッダー
            HStack {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Color.duoGreen)
                Text("PFCバランス")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.duoDark)
                Spacer()
                // 総摂取カロリー
                HStack(spacing: 2) {
                    Text("\(totalCalories)")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(Color.duoOrange)
                    Text("kcal")
                        .font(.system(size: 8))
                        .foregroundColor(Color.duoSubtitle)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.duoOrange.opacity(0.1))
                .cornerRadius(4)

                Text(analysis.rating)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(scoreColorForPFC(analysis.score))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(scoreColorForPFC(analysis.score).opacity(0.15))
                    .cornerRadius(4)
            }

            // 円グラフ + スコア
            HStack(spacing: 12) {
                // 円グラフ
                ZStack {
                    PFCPieChart(
                        proteinPercent: analysis.proteinPercent,
                        fatPercent: analysis.fatPercent,
                        carbsPercent: analysis.carbsPercent
                    )
                    .frame(width: 80, height: 80)

                    // 中央にスコア表示
                    VStack(spacing: 0) {
                        Text("\(analysis.score)")
                            .font(.system(size: 20, weight: .black))
                            .foregroundColor(scoreColorForPFC(analysis.score))
                        Text("点")
                            .font(.system(size: 8))
                            .foregroundColor(Color.duoSubtitle)
                    }
                }

                // 凡例
                VStack(alignment: .leading, spacing: 4) {
                    pfcLegendRow(
                        color: Color.duoOrange,
                        label: "P",
                        name: "たんぱく質",
                        percent: analysis.proteinPercent,
                        grams: analysis.proteinGrams
                    )
                    pfcLegendRow(
                        color: Color.duoPurple,
                        label: "F",
                        name: "脂質",
                        percent: analysis.fatPercent,
                        grams: analysis.fatGrams
                    )
                    pfcLegendRow(
                        color: Color.duoBlue,
                        label: "C",
                        name: "炭水化物",
                        percent: analysis.carbsPercent,
                        grams: analysis.carbsGrams
                    )
                }
            }

            Text("目安: P 15% / F 25% / C 60%")
                .font(.system(size: 8))
                .foregroundColor(Color.duoSubtitle)
        }
        .padding(10)
        .background(Color.duoBg)
        .cornerRadius(10)
    }

    private func pfcLegendRow(color: Color, label: String, name: String, percent: Double, grams: Double) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Color.duoDark)
            Text(name)
                .font(.system(size: 8))
                .foregroundColor(Color.duoSubtitle)
            Spacer()
            Text(String(format: "%.0f%%", percent))
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(color)
            Text(String(format: "%.0fg", grams))
                .font(.system(size: 8))
                .foregroundColor(Color.duoSubtitle)
        }
    }

    private func scoreColorForPFC(_ score: Int) -> Color {
        switch score {
        case 90...100: return .duoGreen
        case 80..<90:  return Color(red: 0.4, green: 0.8, blue: 0.2)
        case 70..<80:  return .duoOrange
        case 50..<70:  return Color(red: 1.0, green: 0.5, blue: 0.0)
        default:       return .duoRed
        }
    }

    // MARK: - 睡眠ステージバー（Dashboard用）
    private var dashboardSleepStageBar: some View {
        let segments = healthKit.sleepSegments
        let total = segments.reduce(0.0) { $0 + $1.durationHours }

        return VStack(alignment: .leading, spacing: 4) {
            if total > 0 {
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        ForEach(segments) { seg in
                            let w = max(2, geo.size.width * CGFloat(seg.durationHours / total))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(hex: seg.stage.color))
                                .frame(width: w, height: 14)
                        }
                    }
                }
                .frame(height: 14)

                // 凡例
                HStack(spacing: 10) {
                    ForEach([
                        (SleepSegment.SleepStage.deep,  "深い"),
                        (.rem,   "REM"),
                        (.core,  "コア"),
                        (.awake, "覚醒"),
                    ], id: \.0.rawValue) { stage, label in
                        HStack(spacing: 3) {
                            Circle().fill(Color(hex: stage.color)).frame(width: 6, height: 6)
                            Text(label).font(.system(size: 9)).foregroundColor(Color.duoSubtitle)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 統合睡眠カード（スコア + ステージバー）
    private var integratedSleepCard: some View {
        Button {
            if let url = URL(string: "x-apple-health://SleepAnalysis") {
                UIApplication.shared.open(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                // ヘッダー
                HStack(spacing: 4) {
                    Image(systemName: "bed.double.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 0.451, green: 0.369, blue: 0.937))
                    Text("睡眠")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.duoDark)
                    Spacer()
                }

                // データ行（スコア・レーティング・時間をすべて1行に）
                if let sleep = sleepScore, sleep.score > 0 {
                    HStack(alignment: .center, spacing: 6) {
                        // スコア
                        HStack(alignment: .bottom, spacing: 2) {
                            Text("\(sleep.score)")
                                .font(.system(size: 19, weight: .black))
                                .foregroundColor(sleepScoreColor(sleep.score))
                            Text("点")
                                .font(.system(size: 9))
                                .foregroundColor(Color.duoSubtitle)
                                .padding(.bottom, 1)
                        }
                        // レーティングバッジ
                        Text(sleep.rating)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(sleepScoreColor(sleep.score))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(sleepScoreColor(sleep.score).opacity(0.15))
                            .cornerRadius(4)
                        Spacer()
                        // 睡眠時間（深い）
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(String(format: "%.1fh", sleep.totalHours))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color.duoDark)
                            HStack(spacing: 2) {
                                Circle()
                                    .fill(Color(red: 0.109, green: 0.753, blue: 0.965))
                                    .frame(width: 4, height: 4)
                                Text(String(format: "深い%.1fh", sleep.deepHours))
                                    .font(.system(size: 8))
                                    .foregroundColor(Color.duoSubtitle)
                            }
                        }
                    }
                } else {
                    HStack(alignment: .bottom, spacing: 2) {
                        Text(healthKit.lastNightTotalHours > 0 ? String(format: "%.1f", healthKit.lastNightTotalHours) : "—")
                            .font(.system(size: 19, weight: .black))
                            .foregroundColor(healthKit.lastNightTotalHours >= 7.0 ? Color.duoGreen : Color.duoOrange)
                        Text("h")
                            .font(.system(size: 9))
                            .foregroundColor(Color.duoSubtitle)
                            .padding(.bottom, 1)
                        Spacer()
                    }
                }

                if !healthKit.sleepSegments.isEmpty {
                    dashboardSleepStageBar
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.duoBg)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 心拍数 + 心拍変動 + ストレス推定 複合タイル
    private var heartRateWithHRVItem: some View {
        HeartRateHRVItem(
            latestHeartRate: healthKit.latestHeartRate,
            latestHRV: healthKit.latestHRV
        )
    }

    // MARK: - 睡眠スコアカード
    private func sleepScoreCard(_ analysis: SleepScoreAnalysis) -> some View {
        Button {
            if let url = URL(string: "x-apple-health://SleepAnalysis") {
                UIApplication.shared.open(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                // アイコン + ラベル
                HStack(spacing: 4) {
                    Image(systemName: "bed.double.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 0.451, green: 0.369, blue: 0.937))
                    Text("睡眠スコア")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.duoDark)
                    Spacer()
                }

                // スコアと評価
                HStack(alignment: .bottom, spacing: 4) {
                    Text("\(analysis.score)")
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(sleepScoreColor(analysis.score))
                    Text("点")
                        .font(.system(size: 10))
                        .foregroundColor(Color.duoSubtitle)
                        .padding(.bottom, 2)
                    Spacer()
                }

                Text(analysis.rating)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(sleepScoreColor(analysis.score))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(sleepScoreColor(analysis.score).opacity(0.15))
                    .cornerRadius(4)

                // 睡眠時間の詳細
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("総時間:")
                            .font(.system(size: 8))
                            .foregroundColor(Color.duoSubtitle)
                        Text(String(format: "%.1fh", analysis.totalHours))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Color.duoDark)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color(red: 0.109, green: 0.753, blue: 0.965)).frame(width: 6, height: 6)
                        Text("深い: \(String(format: "%.1fh", analysis.deepHours))")
                            .font(.system(size: 8))
                            .foregroundColor(Color.duoSubtitle)
                        Circle().fill(Color(red: 0.808, green: 0.510, blue: 1.0)).frame(width: 6, height: 6)
                        Text("REM: \(String(format: "%.1fh", analysis.remHours))")
                            .font(.system(size: 8))
                            .foregroundColor(Color.duoSubtitle)
                    }
                }
                .padding(.top, 2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.duoBg)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private func sleepScoreColor(_ score: Int) -> Color {
        switch score {
        case 90...100: return .duoGreen
        case 80..<90:  return Color(red: 0.4, green: 0.8, blue: 0.2)
        case 70..<80:  return Color(red: 0.451, green: 0.369, blue: 0.937)
        case 50..<70:  return .duoOrange
        default:       return .duoRed
        }
    }

    /// 種目 ID → 推定 kcal/rep
    private static let kcalPerRep: [String: Double] = [
        "pushup": 0.5, "push-up": 0.5,
        "squat":  0.6,
        "situp":  0.3, "sit-up": 0.3,
        "lunge":  0.5,
        "burpee": 1.0,
        "plank":  0.1,
    ]

    private func loadData() async {
        guard authManager.isSignedIn else {
            isLoading = false
            return
        }

        isLoading = true

        // ① キャッシュから即時取得してスピナーを止める（空でも必ず解除）
        async let cachedEx   = authManager.getTodayExercisesFromCache()
        async let cachedSets = authManager.getDailySetsFromCache()
        todayExercises = await cachedEx
        dailySets      = await cachedSets
        recalcTotals()

        // PFCバランス分析と睡眠スコアを更新
        if healthKit.isAuthorized {
            pfcAnalysis = healthKit.analyzePFCBalance()
            sleepScore = healthKit.analyzeSleepScore()
        }

        isLoading = false

        // ② バックグラウンドでサーバーから最新値を取得して反映
        Task {
            async let freshEx   = authManager.getTodayExercises()
            async let freshSets = authManager.getDailySets()
            async let weeklyProgress = authManager.getWeeklySetProgress()
            async let calGoal = authManager.getDailyCalorieGoal()
            async let setCount = authManager.getTodaySetCount()
            async let setGoal = authManager.getDailySetGoal()
            async let intake = authManager.getTodayIntakeSummary()
            async let intakeSettings = authManager.getIntakeSettings()
            let (ex, sets, weekProg, calorie, count, goal, intakeSummary, intakeGoalSettings) = await (freshEx, freshSets, weeklyProgress, calGoal, setCount, setGoal, intake, intakeSettings)
            todayExercises = ex
            dailySets      = sets
            weeklySetProgress = weekProg
            calorieGoal = calorie
            todaySetCount = count
            dailySetGoal = goal
            intakeGoals = intakeGoalSettings

            // HealthKitとFirestoreのデータを統合
            var mergedIntake = intakeSummary
            if healthKit.isAvailable && healthKit.isAuthorized {
                // HealthKitのデータを優先（より正確なため）
                mergedIntake.totalCalories = max(Int(healthKit.todayIntakeCalories), intakeSummary.totalCalories)
                mergedIntake.totalWaterMl = max(Int(healthKit.todayIntakeWater), intakeSummary.totalWaterMl)
                mergedIntake.totalCaffeineMg = max(Int(healthKit.todayIntakeCaffeine), intakeSummary.totalCaffeineMg)
                mergedIntake.totalAlcoholG = max(healthKit.todayIntakeAlcohol, intakeSummary.totalAlcoholG)
            }
            todayIntake = mergedIntake

            // 時間帯別の進捗を再読み込み
            await timeSlotManager.loadTodayProgress()

            // PFCバランス分析と睡眠スコアを更新
            if healthKit.isAuthorized {
                pfcAnalysis = healthKit.analyzePFCBalance()
                sleepScore = healthKit.analyzeSleepScore()
            }

            recalcTotals()
            updateWidgetData()
        }
    }

    // MARK: - 時間帯の進捗を更新するヘルパー関数

    /// トレーニング完了時に時間帯の進捗を更新
    private func updateTimeSlotForTraining(timestamp: Date) async {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: timestamp)
        let timeSlot: TimeSlot

        if hour >= 6 && hour < 10 { timeSlot = .morning }
        else if hour >= 10 && hour < 14 { timeSlot = .noon }
        else if hour >= 14 && hour < 18 { timeSlot = .afternoon }
        else { timeSlot = .evening }

        await timeSlotManager.recordTrainingCompleted(at: timeSlot)
    }

    /// 食事記録時に時間帯の進捗を更新
    private func updateTimeSlotForMeal(timestamp: Date) async {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: timestamp)
        let timeSlot: TimeSlot

        if hour >= 6 && hour < 10 { timeSlot = .morning }
        else if hour >= 10 && hour < 14 { timeSlot = .noon }
        else if hour >= 14 && hour < 18 { timeSlot = .afternoon }
        else { timeSlot = .evening }

        await timeSlotManager.recordMealLog(at: timeSlot)
    }

    /// 飲み物記録時に時間帯の進捗を更新
    private func updateTimeSlotForDrink(timestamp: Date) async {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: timestamp)
        let timeSlot: TimeSlot

        if hour >= 6 && hour < 10 { timeSlot = .morning }
        else if hour >= 10 && hour < 14 { timeSlot = .noon }
        else if hour >= 14 && hour < 18 { timeSlot = .afternoon }
        else { timeSlot = .evening }

        await timeSlotManager.recordDrinkLog(at: timeSlot)
    }

    /// マインドフルネス実施時に時間帯の進捗を更新
    private func updateTimeSlotForMindfulness(timestamp: Date) async {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: timestamp)
        let timeSlot: TimeSlot

        if hour >= 6 && hour < 10 { timeSlot = .morning }
        else if hour >= 10 && hour < 14 { timeSlot = .noon }
        else if hour >= 14 && hour < 18 { timeSlot = .afternoon }
        else { timeSlot = .evening }

        await timeSlotManager.recordMindfulnessCompleted(at: timeSlot)
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        if newPhase == .active {
            print("🔄 App became active - refreshing HealthKit data")
            Task {
                if healthKit.isAvailable && healthKit.isAuthorized {
                    await healthKit.refreshMindfulness()
                }
                await timeSlotManager.loadTodayProgress()
                await timeSlotManager.updateGlobalProgressFromHealthKit()
                updateWidgetData()
            }
        } else if newPhase == .background {
            print("📲 App moved to background - flushing Widget data")
            updateWidgetData()
        }
    }

    private func updateWidgetData() {
        guard let sharedDefaults = UserDefaults(suiteName: "group.com.kfit.app") else {
            print("[Widget] ❌ Failed to access App Group UserDefaults")
            return
        }

        print("[Widget] 🔄 Updating widget data...")

        sharedDefaults.set(todaySetCount, forKey: "todaySetCount")
        sharedDefaults.set(dailySetGoal, forKey: "dailySetGoal")
        sharedDefaults.set(totalReps, forKey: "todayReps")
        sharedDefaults.set(authManager.userProfile?.streak ?? 0, forKey: "streak")
        sharedDefaults.set(totalXP, forKey: "todayXP")

        // 時間帯別の情報を追加
        let currentHour = Calendar.current.component(.hour, from: Date())
        let currentSlot: TimeSlot
        let timeSlotName: String

        if currentHour < 6 {
            currentSlot = .evening
            timeSlotName = "夜"
        } else if currentHour < 10 {
            currentSlot = .morning
            timeSlotName = "朝"
        } else if currentHour < 14 {
            currentSlot = .noon
            timeSlotName = "昼"
        } else if currentHour < 18 {
            currentSlot = .afternoon
            timeSlotName = "午後"
        } else {
            currentSlot = .evening
            timeSlotName = "夜"
        }

        if let goal = timeSlotManager.settings.goalFor(currentSlot),
           let progress = timeSlotManager.progress.progressFor(currentSlot) {
            sharedDefaults.set(timeSlotName, forKey: "currentTimeSlot")
            sharedDefaults.set(progress.trainingCompleted, forKey: "timeSlotCompleted")
            sharedDefaults.set(goal.trainingGoal, forKey: "timeSlotGoal")
        } else {
            sharedDefaults.set(timeSlotName, forKey: "currentTimeSlot")
            sharedDefaults.set(0, forKey: "timeSlotCompleted")
            sharedDefaults.set(1, forKey: "timeSlotGoal")
        }

        // 到達度情報を追加（今日1日分の全時間帯）
        var totalTrainingCompleted = 0
        var totalTrainingGoal = 0
        var totalMindfulnessCompleted = 0
        var totalMindfulnessGoal = 0
        var totalMealLogged = 0
        var totalMealGoal = 0
        var totalDrinkLogged = 0
        var totalDrinkGoal = 0

        // 今日1日分の全時間帯をカウント（ウィジェット表示用）
        for slot in TimeSlot.allCases {
            if let goal = timeSlotManager.settings.goalFor(slot),
               let progress = timeSlotManager.progress.progressFor(slot) {
                // 実際のセット数をカウント
                let setsInSlot = countSetsInTimeSlot(slot)
                totalTrainingCompleted += setsInSlot
                totalTrainingGoal += goal.trainingGoal
                totalMindfulnessCompleted += progress.mindfulnessCompleted
                totalMindfulnessGoal += goal.mindfulnessGoal

                if goal.logGoal.mealGoal > 0 {
                    totalMealGoal += goal.logGoal.mealGoal
                    totalMealLogged += progress.logProgress.mealLogged
                }
                if goal.logGoal.drinkGoal > 0 {
                    totalDrinkGoal += goal.logGoal.drinkGoal
                    totalDrinkLogged += progress.logProgress.drinkLogged
                }
            }
        }

        sharedDefaults.set(totalTrainingCompleted, forKey: "trainingCompleted")
        sharedDefaults.set(totalTrainingGoal, forKey: "trainingGoal")
        sharedDefaults.set(totalMindfulnessCompleted, forKey: "mindfulnessCompleted")
        sharedDefaults.set(totalMindfulnessGoal, forKey: "mindfulnessGoal")
        sharedDefaults.set(totalMealLogged, forKey: "mealLogged")
        sharedDefaults.set(totalMealGoal, forKey: "mealGoal")
        sharedDefaults.set(totalDrinkLogged, forKey: "drinkLogged")
        sharedDefaults.set(totalDrinkGoal, forKey: "drinkGoal")

        // カロリー収支を計算して保存（摂取 - 消費）Apple Health方式
        let totalBurned = Int(healthKit.todayRestingCalories + healthKit.todayActiveCalories)
        let totalIntake = todayIntake.totalCalories
        let calorieBalance = totalIntake - totalBurned
        sharedDefaults.set(calorieBalance, forKey: "calorieBalance")

        print("[Widget] Updated: burned=\(totalBurned), intake=\(totalIntake), balance=\(calorieBalance)")

        // 総ポイントを保存
        let totalPoints = authManager.userProfile?.totalPoints ?? 0
        sharedDefaults.set(totalPoints, forKey: "totalPoints")

        // ワークアウトとスタンド時間を保存（HealthKitの最新値を直接使用）
        let workoutMinutes = healthKit.todayWorkoutMinutes > 0
            ? healthKit.todayWorkoutMinutes
            : timeSlotManager.progress.globalProgress.workoutMinutes
        let workoutGoal = timeSlotManager.settings.globalGoals.workoutEnabled ? timeSlotManager.settings.globalGoals.workoutMinutes : 0
        let standHours = healthKit.todayStandHours > 0
            ? healthKit.todayStandHours
            : timeSlotManager.progress.globalProgress.standHours
        let standGoal = timeSlotManager.settings.globalGoals.standEnabled ? timeSlotManager.settings.globalGoals.standHours : 0

        sharedDefaults.set(workoutMinutes, forKey: "workoutMinutes")
        sharedDefaults.set(workoutGoal, forKey: "workoutGoal")
        sharedDefaults.set(standHours, forKey: "standHours")
        sharedDefaults.set(standGoal, forKey: "standGoal")

        // 確実に保存
        sharedDefaults.synchronize()

        print("[Widget] Synced all data to shared UserDefaults")

        WidgetCenter.shared.reloadAllTimelines()
    }

    private func recalcTotals() {
        totalReps     = todayExercises.reduce(0) { $0 + $1.reps }
        totalXP       = todayExercises.reduce(0) { $0 + $1.points }
        totalCalories = Int(todayExercises.reduce(0.0) { acc, ex in
            let rate = Self.kcalPerRep[ex.exerciseId.lowercased()] ?? 0.4
            return acc + Double(ex.reps) * rate
        })
    }

    private func openMindfulness() {
        // Apple Watchの呼吸アプリを開く
        if let url = URL(string: "x-apple-health://mindfulness") {
            UIApplication.shared.open(url)
        }
    }

    /// 指定された時間帯に実行されたセット数をカウント（30分以内のまとまりを1セットとする）
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
                // 同一セッション内
            } else {
                sessionCount += 1
            }
            lastTime = ex.timestamp
        }
        return sessionCount
    }
}

// MARK: - View Extensions
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

private struct HeartRateHRVItem: View {
    let latestHeartRate: Double
    let latestHRV: Double

    var body: some View {
        let stress = stressInfo(latestHRV)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Color(red: 1.0, green: 0.294, blue: 0.294))
                Text("心拍/変動/ストレス")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.duoDark)
                Spacer()
            }
            HStack(alignment: .center, spacing: 7) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .bottom, spacing: 2) {
                        Text(latestHeartRate > 0 ? "\(Int(latestHeartRate))" : "—")
                            .font(.system(size: 15, weight: .black))
                            .foregroundColor(Color.duoDark)
                        Text("bpm")
                            .font(.system(size: 9))
                            .foregroundColor(Color.duoSubtitle)
                            .padding(.bottom, 2)
                    }
                }
                Divider().frame(height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Image(systemName: "waveform.path.ecg.rectangle")
                            .font(.system(size: 8))
                            .foregroundColor(Color.duoGreen)
                        Text("HRV")
                            .font(.system(size: 9))
                            .foregroundColor(Color.duoSubtitle)
                    }
                    HStack(alignment: .bottom, spacing: 2) {
                        Text(latestHRV > 0 ? "\(Int(latestHRV))" : "—")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color.duoDark)
                        Text("ms")
                            .font(.system(size: 9))
                            .foregroundColor(Color.duoSubtitle)
                            .padding(.bottom, 1)
                    }
                }
                Divider().frame(height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("ストレス")
                        .font(.system(size: 8))
                        .foregroundColor(Color.duoSubtitle)
                    Text(stress.label)
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(stress.color)
                }
                Spacer()
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.duoBg)
        .cornerRadius(10)
    }

    // HRV SDNN ms → ストレス推定（HRVが高いほどストレス低）
    private func stressInfo(_ hrv: Double) -> (label: String, color: Color) {
        guard hrv > 0 else { return ("—", Color.duoSubtitle) }
        switch hrv {
        case 70...:   return ("低い",   Color.duoGreen)
        case 50..<70: return ("普通",   Color(red: 0.4, green: 0.75, blue: 0.1))
        case 30..<50: return ("やや高", Color.duoOrange)
        default:      return ("高い",   Color(red: 1.0, green: 0.29, blue: 0.29))
        }
    }
}

private struct CalorieBalanceBarCard: View {
    let totalConsumed: Double
    let intake: Double

    var body: some View {
        let balance = intake - totalConsumed
        let isPositive = balance > 0
        let absBalance = abs(balance)
        let circleSize: CGFloat = 35 + 20 * min(absBalance / 1000.0, 1.0)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Color.duoDark)
                Text("カロリー収支")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.duoDark)
            }
            GeometryReader { geo in
                barInner(consumed: totalConsumed, intake: intake,
                         isPositive: isPositive, absBalance: absBalance,
                         circleSize: circleSize, geo: geo)
            }
            .frame(height: 68)
        }
        .padding(8)
        .background(Color.white.opacity(0.5))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(isPositive ? Color.red.opacity(0.3) : Color.duoGreen.opacity(0.3), lineWidth: 2))
    }

    private func barInner(consumed: Double, intake: Double, isPositive: Bool,
                          absBalance: Double, circleSize: CGFloat, geo: GeometryProxy) -> some View {
        let barWidth = geo.size.width - circleSize - 12
        let maxValue = max(consumed, intake)
        let cw = max(maxValue > 0 ? (consumed / maxValue) * barWidth * 0.5 : 0, 60)
        let iw = max(maxValue > 0 ? (intake  / maxValue) * barWidth * 0.5 : 0, 60)
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 0) {
                Text("消費Cal").font(.system(size: 8, weight: .semibold)).foregroundColor(Color.duoGreen)
                    .frame(width: cw, alignment: .center)
                Text("摂取Cal").font(.system(size: 8, weight: .semibold)).foregroundColor(Color.duoRed)
                    .frame(width: iw, alignment: .center)
                Spacer()
            }
            HStack(alignment: .center, spacing: 0) {
                consumedBar(consumed: consumed, width: cw)
                intakeBar(intake: intake, width: iw)
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
                Text("\(Int(consumed))").font(.system(size: 13, weight: .black)).foregroundColor(.white)
                Text("cal").font(.system(size: 8, weight: .medium)).foregroundColor(.white.opacity(0.9))
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
                Text("\(Int(intake))").font(.system(size: 13, weight: .black)).foregroundColor(.white)
                Text("cal").font(.system(size: 8, weight: .medium)).foregroundColor(.white.opacity(0.9))
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
                        .font(.system(size: circleSize * 0.20, weight: .bold)).foregroundColor(.white)
                    Text("\(Int(absBalance))")
                        .font(.system(size: circleSize * 0.30, weight: .black)).foregroundColor(.white)
                    Text("cal")
                        .font(.system(size: circleSize * 0.13)).foregroundColor(.white.opacity(0.9))
                }
            }
            weightPrediction(isPositive: isPositive, absBalance: absBalance, grams: weightChangeG)
        }
    }

    @ViewBuilder
    private func weightPrediction(isPositive: Bool, absBalance: Double, grams: Int) -> some View {
        if isPositive {
            HStack(spacing: 1) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 6)).foregroundColor(.red)
                Text("+\(grams)g").font(.system(size: 7, weight: .bold)).foregroundColor(.red)
            }
        } else if absBalance > 0 {
            HStack(spacing: 1) {
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 6)).foregroundColor(Color.duoGreen)
                Text("-\(grams)g").font(.system(size: 7, weight: .bold)).foregroundColor(Color.duoGreen)
            }
        } else {
            HStack(spacing: 1) {
                Image(systemName: "equal.circle.fill").font(.system(size: 6)).foregroundColor(Color.duoGreen)
                Text("±0g").font(.system(size: 7, weight: .bold)).foregroundColor(Color.duoGreen)
            }
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(AuthenticationManager.shared)
}
