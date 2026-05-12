import SwiftUI
import UIKit
import HealthKit
import WidgetKit


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

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.duoBg.ignoresSafeArea()

                // メインコンテンツ
                VStack(spacing: 0) {
                    if isLoading {
                        Spacer()
                        ProgressView().tint(Color.duoGreen).scaleEffect(1.4)
                        Spacer()
                    } else {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 10) {
                                dailySetsCard
                                quickMenu
                                calorieAndWeightCard
                                weeklyGoalCard
                                challengeCard
                                habitStackCard
                            }
                            .padding(.horizontal, 10)
                            .padding(.top, 0)
                            .padding(.bottom, 60)
                        }
                        .padding(.top, geometry.safeAreaInsets.top + 8)
                    }
                }

                // 固定ヘッダー（最上部）
                VStack(spacing: 0) {
                    heroSection
                    Spacer()
                }
                .zIndex(1)


                // ハンバーガーメニュー（オーバーレイ）
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
            .ignoresSafeArea()
        }
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showTracker) {
            ExerciseTrackerView(isPresented: $showTracker)
                .environmentObject(authManager)
        }
        .onChange(of: showTracker) { _, newValue in
            if !newValue {
                // ExerciseTrackerViewが閉じられた時にデータを再読み込み
                Task {
                    print("🔄 ExerciseTrackerView閉じた - データ再読み込み")
                    await loadData()
                }
            }
        }
        .sheet(isPresented: $showHabits) {
            NavigationView { HabitStackView() }
        }
        .sheet(isPresented: $showCalorieGoalEdit) {
            calorieGoalEditSheet
        }
        .sheet(isPresented: $showHealthGoalEdit) {
            healthGoalEditSheet
        }
        .sheet(isPresented: $showIntakeGoalEdit) {
            IntakeSettingsView()
                .environmentObject(authManager)
        }
        .alert(confirmMessage, isPresented: $showIntakeConfirm) {
            Button("キャンセル", role: .cancel) { }
            Button("記録する") {
                pendingIntakeAction?()
                pendingIntakeAction = nil
            }
        }
        .onAppear {
            withAnimation { mascotBounce = true }
            // 初回のみloadDataを実行
            if !hasLoadedOnce {
                hasLoadedOnce = true
                isLoading = true
                Task {
                    print("🟢 DashboardView.onAppear - loadDataを開始")
                    // HealthKit権限をリクエスト
                    if healthKit.isAvailable && !healthKit.isAuthorized {
                        await healthKit.requestAuthorization()
                    }
                    // 時間帯別のデータを読み込み
                    await timeSlotManager.loadTodaySettings()
                    await timeSlotManager.loadTodayProgress()
                    await loadData()
                }
            } else {
                print("⚠️ DashboardView.onAppear - 既にロード済み、スキップ")
            }
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

    // MARK: - ヒーロー（極小1行バー）
    private var heroSection: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [Color.duoGreen, Color(red: 0.18, green: 0.58, blue: 0.0)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                HStack(spacing: 0) {
                    // ── ロゴ ──────────────────
                    HStack(spacing: 2) {
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

                    Spacer()

                    // ── 統計 2項目（横1列）- 連続記録と直近の時間帯セット状況 ───
                    currentTimeSlotStats

                }
                .padding(.horizontal, 8)
                .padding(.top, geometry.safeAreaInsets.top)
                .padding(.bottom, 0)
            }
        }
        .frame(height: (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 44) + 8)
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

        // トータルのトレーニング実績と目標
        let totalTrainingCompleted = completedSlots.reduce(0) { sum, slot in
            sum + (timeSlotManager.progress.progressFor(slot)?.trainingCompleted ?? 0)
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

        // トータルのログ完了状況（各時間帯で1つでも完了していればtrue）
        let anyMealLogged = completedSlots.contains { slot in
            timeSlotManager.progress.progressFor(slot)?.logProgress.mealLogged ?? false
        }
        let anyDrinkLogged = completedSlots.contains { slot in
            timeSlotManager.progress.progressFor(slot)?.logProgress.drinkLogged ?? false
        }
        let totalLogCompleted = (anyMealLogged ? 1 : 0) + (anyDrinkLogged ? 1 : 0)
        let totalLogGoal = 2

        return HStack(spacing: 6) {
            // 1. 連続記録
            miniStat("🔥", "\(authManager.userProfile?.streak ?? 0)", "")

            // 2. トレーニング到達度
            let trainingComplete = totalTrainingGoal > 0 && totalTrainingCompleted >= totalTrainingGoal
            HStack(spacing: 1) {
                Text("💪").font(.system(size: 11))
                Text("\(totalTrainingCompleted)/\(max(totalTrainingGoal, 1))")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(trainingComplete ? Color.white : Color.white.opacity(0.8))
                if trainingComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.white)
                }
            }

            // 3. マインドフル実施
            if totalMindfulnessGoal > 0 {
                let mindfulnessComplete = totalMindfulnessCompleted >= totalMindfulnessGoal
                HStack(spacing: 1) {
                    Text("🧘").font(.system(size: 11))
                    if mindfulnessComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: "circle")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }

            // 4. ログ入力完了
            let logComplete = totalLogCompleted >= totalLogGoal
            HStack(spacing: 1) {
                Text("🍽️").font(.system(size: 11))
                if logComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
    }

    private func miniStat(_ icon: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 1) {
            Text(icon).font(.system(size: 11))
            Text(value)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 9))
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
                return progress.isFullyCompleted(goal: goal)
            }
            return false
        }.count

        // トータル進捗を計算（経過した時間帯の合計）
        var totalTraining = 0
        var totalTrainingGoal = 0
        var totalMindfulness = 0
        var totalMindfulnessGoal = 0

        for slot in visibleSlots {
            if let goal = timeSlotManager.settings.goalFor(slot),
               let progress = timeSlotManager.progress.progressFor(slot) {
                totalTraining += progress.trainingCompleted
                totalTrainingGoal += goal.trainingGoal
                totalMindfulness += progress.mindfulnessCompleted
                totalMindfulnessGoal += goal.mindfulnessGoal
            }
        }

        return VStack(alignment: .leading, spacing: 0) {
            // ヘッダー（タップで展開）
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showTodayRecords.toggle()
                }
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    // タイトル行
                    HStack(spacing: 6) {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.seal.fill")
                            Text("今日のセット状況").fontWeight(.black)
                        }
                        .font(.headline)
                        .foregroundColor(Color.duoDark)

                        Spacer()

                        if totalCompletedSlots == totalSlotsToShow {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("完璧！")
                                    .font(.caption).fontWeight(.black)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.duoGreen)
                            .cornerRadius(20)
                        } else {
                            Text("\(totalCompletedSlots)/\(totalSlotsToShow) 完了")
                                .font(.caption).fontWeight(.bold)
                                .foregroundColor(Color.duoOrange)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Color.duoOrange.opacity(0.12))
                                .cornerRadius(20)
                        }

                        Image(systemName: showTodayRecords ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(Color.duoGreen)
                    }

                    Divider()

                    // トータル進捗（経過時間帯の合計）
                    if totalSlotsToShow > 1 {
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Text("💪").font(.caption)
                                Text("トータル \(totalTraining)/\(totalTrainingGoal)")
                                    .font(.caption).fontWeight(.bold)
                                    .foregroundColor(totalTraining >= totalTrainingGoal ? Color.duoGreen : Color.duoDark)
                            }
                            HStack(spacing: 4) {
                                Text("🧘").font(.caption)
                                Text("\(totalMindfulness)/\(totalMindfulnessGoal)")
                                    .font(.caption).fontWeight(.bold)
                                    .foregroundColor(totalMindfulness >= totalMindfulnessGoal ? Color.duoGreen : Color.duoDark)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(Color.duoGreen.opacity(0.08))
                        .cornerRadius(8)

                        Divider()
                    }

                    // 時間帯別の進捗（現在時刻までの時間帯のみ表示）
                    VStack(spacing: 8) {
                        ForEach(visibleSlots, id: \.rawValue) { slot in
                            timeSlotRow(for: slot)
                        }
                    }

                    // 達成メッセージ
                    if totalCompletedSlots == totalSlotsToShow {
                        HStack(spacing: 6) {
                            Image("mascot")
                                .resizable().scaledToFill()
                                .frame(width: 22, height: 22).clipShape(Circle())
                            Text(totalSlotsToShow == 4 ? "全時間帯の目標達成！素晴らしい一日🎉" : "ここまでの目標達成！順調です💪")
                                .font(.caption).fontWeight(.bold).foregroundColor(Color.duoGreen)
                        }
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

            // トレーニング開始ボタン
            VStack(spacing: 0) {
                Divider()
                    .padding(.horizontal, 16)

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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
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
                .padding(.vertical, 12)
            }

            // 今日の記録（展開時のみ表示）
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
            .padding(.bottom, 12)
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

        return HStack(spacing: 8) {
            // 時間帯アイコンと名前
            Text(slot.emoji).font(.subheadline)
            Text(slot.displayName)
                .font(.caption).fontWeight(.semibold).foregroundColor(Color.duoDark)
                .frame(width: 36, alignment: .leading)

            // トレーニング進捗
            if let goal = goal, goal.trainingGoal > 0 {
                HStack(spacing: 2) {
                    Text("💪").font(.caption2)
                    Text("\(progress?.trainingCompleted ?? 0)/\(goal.trainingGoal)")
                        .font(.caption2).fontWeight(.medium)
                        .foregroundColor((progress?.trainingCompleted ?? 0) >= goal.trainingGoal ? Color.duoGreen : Color.duoSubtitle)
                }
            }

            // マインドフルネス進捗
            if let goal = goal, goal.mindfulnessGoal > 0 {
                HStack(spacing: 2) {
                    if (progress?.mindfulnessCompleted ?? 0) >= goal.mindfulnessGoal {
                        Text("🧘").font(.caption2)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(Color.duoGreen)
                    } else {
                        Text("🧘").font(.caption2).opacity(0.5)
                        Text("\(progress?.mindfulnessCompleted ?? 0)/\(goal.mindfulnessGoal)")
                            .font(.caption2).fontWeight(.medium)
                            .foregroundColor(Color.duoSubtitle)
                    }
                }
            }

            Spacer()

            // ログ進捗バッジ
            if let goal = goal, let progress = progress {
                HStack(spacing: 3) {
                    if goal.logGoal.mealRequired {
                        Image(systemName: progress.logProgress.mealLogged ? "fork.knife.circle.fill" : "fork.knife.circle")
                            .font(.caption)
                            .foregroundColor(progress.logProgress.mealLogged ? Color.duoGreen : Color(.systemGray4))
                    }
                    if goal.logGoal.drinkRequired {
                        Image(systemName: progress.logProgress.drinkLogged ? "drop.circle.fill" : "drop.circle")
                            .font(.caption)
                            .foregroundColor(progress.logProgress.drinkLogged ? Color.duoBlue : Color(.systemGray4))
                    }
                    if goal.logGoal.mindInputRequired {
                        Image(systemName: progress.logProgress.mindInputLogged ? "brain.head.profile.fill" : "brain.head.profile")
                            .font(.caption)
                            .foregroundColor(progress.logProgress.mindInputLogged ? Color.duoPurple : Color(.systemGray4))
                    }
                }
            }

            // 完了マーク
            if let goal = goal, let progress = progress, progress.isFullyCompleted(goal: goal) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(Color.duoGreen)
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
                // 2列グリッド表示
                VStack(spacing: 8) {
                    // 行1: 睡眠 | 体重・体脂肪
                    HStack(spacing: 8) {
                        compactHealthItem(
                            icon: "bed.double.fill",
                            iconColor: Color(red: 0.451, green: 0.369, blue: 0.937),
                            label: "睡眠",
                            value: healthKit.lastNightTotalHours,
                            goal: 7.0,
                            unit: "h",
                            formatValue: { String(format: "%.1f", $0) }
                        )
                        bodyWeightFatCard
                    }

                    // 行2: 歩数 | 活動カロリー
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
                        compactHealthItem(
                            icon: "flame.fill",
                            iconColor: Color.duoOrange,
                            label: "活動Cal",
                            value: healthKit.todayActiveCalories,
                            goal: Double(calorieGoal.targetCalories),
                            unit: "kcal",
                            formatValue: { "\(Int($0))" }
                        )
                    }

                    // 行3: 総消費カロリー
                    compactHealthItem(
                        icon: "sum",
                        iconColor: Color.duoGreen,
                        label: "総消費カロリー",
                        value: healthKit.todayTotalCalories,
                        goal: nil,
                        unit: "kcal",
                        formatValue: { "\(Int($0))" }
                    )

                    // 行4: 摂取カロリー
                    compactHealthItem(
                        icon: "fork.knife",
                        iconColor: Color.duoRed,
                        label: "摂取カロリー",
                        value: Double(todayIntake.totalCalories),
                        goal: Double(intakeGoals.dailyCalorieGoal),
                        unit: "kcal",
                        formatValue: { "\(Int($0))" }
                    )

                    // カロリー収支バー
                    calorieBalanceBarCard

                    // 行5: 心拍数 | マインドフルネス
                    HStack(spacing: 8) {
                        compactHealthItem(
                            icon: "heart.fill",
                            iconColor: Color(red: 1.0, green: 0.294, blue: 0.294),
                            label: "心拍数",
                            value: healthKit.latestHeartRate,
                            goal: nil,
                            unit: "bpm",
                            formatValue: { "\(Int($0))" }
                        )
                        compactHealthItem(
                            icon: "brain.head.profile",
                            iconColor: Color.duoPurple,
                            label: "マインドフル",
                            value: healthKit.todayMindfulnessMinutes,
                            goal: nil,
                            unit: "分",
                            formatValue: { String(format: "%.0f", $0) + " (\(healthKit.todayMindfulnessSessions)回)" }
                        )
                    }

                    // 行6: 水分 | カフェイン | アルコール
                    HStack(spacing: 8) {
                        compactHealthItemThird(
                            icon: "drop.fill",
                            iconColor: Color.duoBlue,
                            label: "水分",
                            value: Double(todayIntake.totalWaterMl),
                            goal: Double(intakeGoals.dailyWaterGoal),
                            unit: "ml",
                            formatValue: { "\(Int($0))" }
                        )
                        compactHealthItemThird(
                            icon: "cup.and.saucer.fill",
                            iconColor: Color.duoBrown,
                            label: "カフェイン",
                            value: Double(todayIntake.totalCaffeineMg),
                            goal: Double(intakeGoals.dailyCaffeineLimit),
                            unit: "mg",
                            formatValue: { "\(Int($0))" },
                            isReverse: true
                        )
                        compactHealthItemThird(
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
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
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
        isReverse: Bool = false
    ) -> some View {
        let percent = goal != nil && goal! > 0 ? Int((value / goal!) * 100) : 0
        let isOver = goal != nil && value > goal!
        let isGood = goal == nil ? (value > 0) : (isReverse ? (value <= goal!) : (value >= goal!))
        let displayColor = (isOver && isReverse) ? Color.red : (isGood ? Color.duoGreen : Color.duoOrange)

        return VStack(alignment: .leading, spacing: 4) {
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
        isReverse: Bool = false
    ) -> some View {
        let percent = goal != nil && goal! > 0 ? Int((value / goal!) * 100) : 0
        let isOver = goal != nil && value > goal!
        let isGood = goal == nil ? (value > 0) : (isReverse ? (value <= goal!) : (value >= goal!))
        let displayColor = (isOver && isReverse) ? Color.red : (isGood ? Color.duoGreen : Color.duoOrange)

        return VStack(alignment: .center, spacing: 3) {
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
                }

                Divider()
                    .frame(height: 20)

                // 体脂肪
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .bottom, spacing: 2) {
                        Text(healthKit.latestBodyFatPercentage > 0 ? String(format: "%.1f", healthKit.latestBodyFatPercentage) : "—")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(healthKit.latestBodyFatPercentage > 0 ? Color.duoGreen : Color.duoDark)
                        Text("%")
                            .font(.system(size: 9))
                            .foregroundColor(Color.duoSubtitle)
                            .padding(.bottom, 1)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.duoBlue.opacity(0.08))
        .cornerRadius(8)
    }

    // MARK: - カロリー収支バーカード
    private var calorieBalanceBarCard: some View {
        let totalConsumed = healthKit.todayTotalCalories
        let intake = Double(todayIntake.totalCalories)
        let balance = intake - totalConsumed
        let isPositive = balance > 0
        let absBalance = abs(balance)
        let maxValue = max(totalConsumed, intake)

        // 収支の大きさに応じて円のサイズを変更（最小40、最大65）
        let circleSize: CGFloat = {
            let baseSize: CGFloat = 40
            let maxSize: CGFloat = 65
            let sizeFactor = min(absBalance / 1000.0, 1.0)  // 1000kcalで最大サイズ
            return baseSize + (maxSize - baseSize) * sizeFactor
        }()

        return VStack(alignment: .leading, spacing: 8) {
            // タイトル
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Color.duoDark)
                Text("カロリー収支")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.duoDark)
            }

            // 横バーグラフ（ラベル付き）
            GeometryReader { geo in
                let circleSpace = circleSize + 12
                let barWidth = geo.size.width - circleSpace
                let consumedWidth = maxValue > 0 ? (totalConsumed / maxValue) * barWidth * 0.5 : 0
                let intakeWidth = maxValue > 0 ? (intake / maxValue) * barWidth * 0.5 : 0

                VStack(spacing: 4) {
                    // ラベル行（バーの真上）
                    HStack(spacing: 0) {
                        Text("消費Cal")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color.duoGreen)
                            .frame(width: max(consumedWidth, 60), alignment: .center)
                        Text("摂取Cal")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color.duoRed)
                            .frame(width: max(intakeWidth, 60), alignment: .center)
                        Spacer()
                    }

                    // バーと収支円
                    HStack(spacing: 0) {
                        // 左側: 総消費カロリー（グリーン）
                        HStack(spacing: 2) {
                            Spacer()
                            Text("\(Int(totalConsumed))")
                                .font(.system(size: 13, weight: .black))
                                .foregroundColor(.white)
                            Text("cal")
                                .font(.system(size: 7, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                                .padding(.bottom, 1)
                        }
                        .frame(width: max(consumedWidth, 60), height: 32)
                        .background(Color.duoGreen)
                        .cornerRadius(6, corners: [.topLeft, .bottomLeft])

                        // 右側: 摂取カロリー（レッド）
                        HStack(spacing: 2) {
                            Text("\(Int(intake))")
                                .font(.system(size: 13, weight: .black))
                                .foregroundColor(.white)
                            Text("cal")
                                .font(.system(size: 7, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                                .padding(.bottom, 1)
                            Spacer()
                        }
                        .frame(width: max(intakeWidth, 60), height: 32)
                        .background(Color.duoRed)
                        .cornerRadius(6, corners: [.topRight, .bottomRight])

                        Spacer()
                            .frame(width: 8)

                        // 収支円（コンパクト）
                        ZStack {
                            Circle()
                                .fill(isPositive ? Color.red : Color.duoGreen)
                                .frame(width: circleSize, height: circleSize)
                                .shadow(color: (isPositive ? Color.red : Color.duoGreen).opacity(0.3), radius: 3, y: 1)
                            VStack(spacing: 0) {
                                Text(isPositive ? "+" : "-")
                                    .font(.system(size: circleSize * 0.22, weight: .bold))
                                    .foregroundColor(.white)
                                Text("\(Int(absBalance))")
                                    .font(.system(size: circleSize * 0.32, weight: .black))
                                    .foregroundColor(.white)
                                Text("cal")
                                    .font(.system(size: circleSize * 0.14))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                    }
                }
            }
            .frame(height: 60)

            // 傾向表示
            HStack(spacing: 8) {
                if isPositive {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color.red)
                        Text("太り傾向")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.red)
                    }
                } else if balance < 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color.duoGreen)
                        Text("痩せ傾向")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.duoGreen)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "equal.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color.duoGreen)
                        Text("バランス")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.duoGreen)
                    }
                }

                Spacer()

                // 体重変化予測
                if absBalance > 0 {
                    let kgPerDay = absBalance / 7200.0
                    Text("約\(String(format: "%.2f", kgPerDay))kg/日")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.duoDark)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.systemGray6))
                        .cornerRadius(5)
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.5))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isPositive ? Color.red.opacity(0.3) : Color.duoGreen.opacity(0.3), lineWidth: 2)
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

            // 食事
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

            // 水分・コーヒー・アルコール
            HStack(spacing: 8) {
                quickIntakeButton(emoji: "💧", label: "水") {
                    confirmIntake(message: "水 \(intakeGoals.waterPerCup)ml を記録しますか？") {
                        Task {
                            await authManager.recordWater()
                            await updateTimeSlotForDrink(timestamp: Date())
                            await refreshIntakeData()
                        }
                    }
                }
                quickIntakeButton(emoji: "☕", label: "コーヒー") {
                    confirmIntake(message: "コーヒー \(intakeGoals.coffeePerCup)ml (カフェイン \(intakeGoals.caffeinePerCup)mg) を記録しますか？") {
                        Task {
                            await authManager.recordCoffee()
                            await updateTimeSlotForDrink(timestamp: Date())
                            await refreshIntakeData()
                        }
                    }
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
                            bg: Color(red: 0.843, green: 1.0, blue: 0.722) // #D7FFB8
                        )
                        healthMetricTile(
                            icon: "flame.fill",
                            value: healthKit.todayCalories > 0 ? "\(Int(healthKit.todayCalories))" : "0",
                            unit: "kcal",
                            bg: Color(red: 1.0, green: 0.953, blue: 0.878) // #FFF3E0
                        )
                    }

                    // 下段: 心拍数 & 睡眠
                    HStack(spacing: 8) {
                        healthMetricTile(
                            icon: "heart.fill",
                            value: healthKit.latestHeartRate > 0 ? "\(Int(healthKit.latestHeartRate))" : "—",
                            unit: "bpm",
                            bg: Color(red: 0.988, green: 0.894, blue: 0.925) // #FCE4EC
                        )
                        healthMetricTile(
                            icon: "bed.double.fill",
                            value: healthKit.lastNightTotalHours > 0.1 ? String(format: "%.1f", healthKit.lastNightTotalHours) : "—",
                            unit: "時間",
                            bg: Color(red: 0.918, green: 0.902, blue: 1.0) // #EAE6FF
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

    private func healthMetricTile(icon: String, value: String, unit: String, bg: Color) -> some View {
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

    private func updateWidgetData() {
        guard let sharedDefaults = UserDefaults(suiteName: "group.com.kfit.app") else { return }
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

#Preview {
    DashboardView()
        .environmentObject(AuthenticationManager.shared)
}
