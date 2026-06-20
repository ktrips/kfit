import SwiftUI
import UIKit
import HealthKit
import WidgetKit
import PhotosUI

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

                // 中央の円（ドーナツ型にする）
                Circle()
                    .fill(Color(.systemBackground))
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

// MARK: - アクティビティリングビュー

struct ActivityRingView: View {
    let progress: Double
    let color: Color
    let diameter: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(1.0, max(0, progress))))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)
        }
        .frame(width: diameter, height: diameter)
    }
}

/// DispatchWorkItemをSwiftUIの@Stateに入れると毎回の代入で再レンダリングが
/// トリガーされる。このクラスはObservableObjectだが@Publishedプロパティを
/// 持たないため、workItemの更新がDashboardViewの再レンダリングを起こさない。
private final class DashboardDebouncer: ObservableObject {
    var widgetUpdate: DispatchWorkItem?
    var widgetReload: DispatchWorkItem?
}

struct DashboardView: View {

    // DateFormatter は生成コストが高いため static で一度だけ生成
    private static let hhmm: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let hm: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "H:mm"; return f
    }()
    private static let mdE: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日(E)"
        return f
    }()
    private static let slashMdE: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d(E)"
        return f
    }()

    @Binding var selectedTab: Int
    @Binding var showRecordMenu: Bool
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var habitManager = HabitStackManager.shared
    @StateObject private var healthKit    = HealthKitManager.shared
    @StateObject private var timeSlotManager = TimeSlotManager.shared
    @StateObject private var dietGoalManager = DietGoalManager.shared
    @StateObject private var photoLogManager = PhotoLogManager.shared
    @StateObject private var completionLogger = MandalaCompletionLogger.shared
    // フォトログ集計キャッシュ（photoLogManager.history 変化時のみ再計算）
    @State private var cachedPhotoLogTotals: (protein: Double, fat: Double, carbs: Double, calories: Int) = (0, 0, 0, 0)
    @State private var todayExercises: [CompletedExercise] = []
    @State private var totalReps     = 0
    @State private var totalCalories = 0
    @State private var totalXP      = 0
    @State private var weeklyXP     = 0
    @State private var weeklyBaseXP = 0  // 今週の今日より前の合計XP（再計算用）
    @State private var todaySetCount = 0  // 今日完了したセット数
    @State private var dailySetGoal  = 2  // 1日の目標セット数
    @State private var dailySets    = DailySets(amSets: 0, pmSets: 0)  // 元の型を保持
    @State private var weeklySetProgress = WeeklySetProgress(completedSets: 0, dailyGoal: 2)
    @State private var calorieGoal = DailyCalorieGoal()
    @State private var isLoading    = false  // 初期値をfalseに変更
    @State private var mascotBounce = false
    @State private var showDrinkToast = false  // 水分記録後のトースト表示
    @State private var showTracker  = false
    @State private var showHabits   = false
    @State private var hasLoadedOnce = false  // 1度だけロード実行するフラグ
    @State private var expandedSetId: String? = nil  // 展開中のセットID
    @State private var showCalorieGoalEdit = false  // カロリー目標編集モーダル
    @State private var showPointsDetail   = false  // ポイント詳細シート
    @State private var tempCalorieTarget = 500  // 一時的なカロリー目標
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
    @State private var showMindfulnessSession = false  // アプリ内呼吸セッション
    @State private var showStretchSession = false  // アプリ内ストレッチセッション
    @State private var showStandSession = false  // 20分スタンドポモドーロセッション
    @State private var showTrainingVideo = false  // トレーニング動画GIFの表示状態
    @State private var trainingVideoIndex = 0  // ホーム動画GIFの再生位置
    @State private var pfcAnalysis: PFCBalanceAnalysis?  // PFCバランス分析結果
    @State private var sleepScore: SleepScoreAnalysis?  // 睡眠スコア分析結果
    @State private var lastWidgetPayloadHash = ""
    @StateObject private var debouncer = DashboardDebouncer()
    @State private var showMandalaDetail = false
    @State private var selectedMandalaNode: MandalaNodeData? = nil
    @State private var showEduPhotoLog = false
    @State private var eduPhotoLogNode: MandalaNodeData? = nil
    @State private var lastLoadDataTime: Date? = nil
    @State private var todayWeekdayGoal: WeekdayGoal? = nil
    @State private var dailyFixedGoals: DailyFixedGoals = DailyFixedGoals()
    @AppStorage("mainTab.food.visible") private var foodTabVisible = true
    @AppStorage("mainTab.mind.visible") private var mindTabVisible = false
    @AppStorage("mainTab.goal.visible") private var goalTabVisible = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        coreView
            .onChange(of: healthKit.todayMindfulnessSessions) { oldValue, newValue in
                handleMindfulnessChange(old: oldValue, new: newValue)
                scheduleWidgetDataUpdate()
            }
            .onChange(of: healthKit.todayActiveCalories) { _, _ in scheduleWidgetDataUpdate() }
            .onChange(of: healthKit.todayRestingCalories) { _, _ in scheduleWidgetDataUpdate() }
            .onChange(of: healthKit.todayWorkoutMinutes) { _, _ in scheduleWidgetDataUpdate() }
            .onChange(of: healthKit.todayStandHours) { _, _ in scheduleWidgetDataUpdate() }
            .onChange(of: healthKit.todayIntakeWater) { _, _ in scheduleWidgetDataUpdate() }
            .onChange(of: healthKit.todayBodyMassMeasurements) { _, _ in scheduleWidgetDataUpdate() }
            .onChange(of: healthKit.lastNightTotalHours) { _, _ in scheduleWidgetDataUpdate() }
            .onChange(of: todayIntake.totalCalories) { _, _ in scheduleWidgetDataUpdate() }
            .onChange(of: todaySetCount) { _, _ in scheduleWidgetDataUpdate() }
            .onChange(of: photoLogManager.history.count) { _, _ in recomputePhotoLogTotals() }
            .onReceive(NotificationCenter.default.publisher(for: .timeSlotProgressDidSave)) { _ in
                updateWidgetData()
            }
            .onReceive(Timer.publish(every: 600, on: .main, in: .common).autoconnect()) { _ in
                Task { await periodicWidgetSync() }
            }
            .onAppear {
                withAnimation { mascotBounce = true }
                recomputePhotoLogTotals()
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
                headerInfoBar
                if isLoading {
                    Spacer()
                    ProgressView().tint(Color.duoGreen).scaleEffect(1.4)
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            dailySetsCard
                            quickMenu
                            if goalTabVisible && healthKit.isAvailable && healthKit.isAuthorized {
                                activityRingsCard
                                calorieBalanceBarCard
                            }
                            if healthKit.isAvailable && healthKit.isAuthorized {
                                if foodTabVisible { foodCard }
                                if mindTabVisible { mindHealthCard }
                            }
                            pointsCard
                            challengeCard
                            habitStackCard
                            bookPromoSection
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                        .padding(.bottom, 60)
                    }
                    .refreshable {
                        await refreshFromHealthKit()
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
        // 水分記録トースト
        .overlay(alignment: .top) {
            if showDrinkToast {
                HStack(spacing: 8) {
                    Text("💧")
                        .font(.title3)
                    Text("水分200ml")
                        .font(.subheadline).fontWeight(.black)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.duoBlue.opacity(0.92))
                .clipShape(Capsule())
                .shadow(color: Color.duoBlue.opacity(0.35), radius: 8, y: 4)
                .padding(.top, 56)
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .onChange(of: showTracker) { _, newValue in
            if !newValue {
                Task {
                    print("🔄 ExerciseTrackerView閉じた - データ再読み込み")
                    await loadData()
                }
            }
        }
        // シート・アラート群をbackgroundに移すことで、メインコンテンツの
        // SwiftUI描画ツリー深度を16段階削減しスタックオーバーフローを防止
        .background(coreViewModals)
    }

    // MARK: - シート・アラート群（描画深度削減のためbackground分離）
    private var coreViewModals: some View {
        Color.clear
            .fullScreenCover(isPresented: $showTracker) {
                ExerciseTrackerView(isPresented: $showTracker)
                    .environmentObject(authManager)
            }
            .sheet(isPresented: $showHabits) { NavigationView { HabitStackView() } }
            .sheet(isPresented: $showMandalaDetail) { NavigationView { TimeSlotGoalsView() } }
            .sheet(isPresented: $showPointsDetail) { pointsDetailSheet }
            .sheet(isPresented: $showCalorieGoalEdit) { calorieGoalEditSheet }
            .sheet(isPresented: $showHealthGoalEdit) { healthGoalEditSheet }
            .sheet(isPresented: $showIntakeGoalEdit) {
                IntakeSettingsView().environmentObject(authManager)
            }
            .sheet(item: $selectedMandalaNode) { node in
                GoalCompletionSheet(
                    emoji: node.emoji,
                    name: node.label,
                    isDone: node.isCompleted,
                    onComplete: {
                        selectedMandalaNode = nil
                        let isDrink = node.type == .drink
                        Task {
                            await handleMandalaComplete(node)
                            if isDrink {
                                await MainActor.run {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        showDrinkToast = true
                                    }
                                }
                                try? await Task.sleep(nanoseconds: 2_200_000_000)
                                await MainActor.run {
                                    withAnimation(.easeOut(duration: 0.4)) {
                                        showDrinkToast = false
                                    }
                                }
                            }
                        }
                    },
                    onPhotoTap: node.type == .meal ? {
                        selectedMandalaNode = nil
                        showPhotoLog = true
                    } : node.type == .custom ? {
                        eduPhotoLogNode = node
                        selectedMandalaNode = nil
                        showEduPhotoLog = true
                    } : nil,
                    isRecordType: node.type == .meal || node.type == .drink
                )
                .presentationDetents([.height(290)])
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $showPhotoLog) { PhotoLogView() }
            .sheet(isPresented: $showEduPhotoLog) {
                if let node = eduPhotoLogNode {
                    EduPhotoLogSheet(
                        nodeEmoji: node.emoji,
                        nodeName: node.label,
                        onComplete: { saveToFeed, isPublic, image, comment in
                            showEduPhotoLog = false
                            Task {
                                await handleMandalaComplete(node)
                                if saveToFeed {
                                    EduLogManager.shared.addItem(
                                        activityName: node.label,
                                        activityEmoji: node.emoji,
                                        comment: comment,
                                        image: image,
                                        isPublic: isPublic
                                    )
                                }
                            }
                        }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
            .fullScreenCover(isPresented: $showMindfulnessSession) {
                MindfulnessSessionView(
                    durationSeconds: 60,
                    title: "1分瞑想",
                    completedButtonTitle: "Breatheとして保存"
                ) { startDate, endDate in
                    Task {
                        let saved = await healthKit.saveMindfulnessSession(
                            startDate: startDate,
                            endDate: endDate,
                            durationSeconds: 60,
                            sessionType: "Breathe"
                        )
                        if saved {
                            await healthKit.refreshMindfulness()
                        }
                        updateWidgetData()
                    }
                }
            }
            .fullScreenCover(isPresented: $showStretchSession) {
                MindfulnessSessionView(
                    durationSeconds: 180,
                    title: "3分ストレッチ",
                    completedButtonTitle: "Reflectとして保存",
                    sessionVideos: StretchSessionVideo.defaultStretchVideos
                ) { startDate, endDate in
                    Task {
                        let saved = await healthKit.saveMindfulnessSession(
                            startDate: startDate,
                            endDate: endDate,
                            durationSeconds: 180,
                            sessionType: "Reflect"
                        )
                        if saved {
                            await healthKit.refreshMindfulness()
                        }
                        updateWidgetData()
                    }
                }
            }
            .fullScreenCover(isPresented: $showStandSession) {
                StandPomodoroView(durationSeconds: 20 * 60) {
                    Task {
                        let slot = TimeSlot.current()
                        await timeSlotManager.recordStandCompleted(at: slot)
                        let endDate = Date()
                        let startDate = endDate.addingTimeInterval(-20 * 60)
                        let saved = await healthKit.saveMindfulnessSession(
                            startDate: startDate,
                            endDate: endDate,
                            durationSeconds: 20 * 60,
                            sessionType: "Stand"
                        )
                        if saved { await healthKit.refreshMindfulness() }
                        updateWidgetData()
                    }
                }
            }
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

            VStack(spacing: 8) {
                compactMindfulnessCTA(
                    icon: "🧘",
                    title: "マインドフルネス",
                    subtitle: "1分瞑想",
                    colors: [Color.duoPurple, Color(red: 0.58, green: 0.32, blue: 0.76)]
                ) {
                    openMindfulness()
                }

                compactMindfulnessCTA(
                    icon: "🤸",
                    title: "マインドフルネス",
                    subtitle: "3分ストレッチ",
                    colors: [Color.duoBlue, Color.duoPurple]
                ) {
                    openStretch()
                }

            }
            .padding(.horizontal, 8)
            .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 0 : 8)
            .padding(.top, 2)
            .background(
                Color.duoBg
                    .shadow(color: Color.black.opacity(0.05), radius: 3, y: -1)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .frame(height: 184)
    }

    private func compactMindfulnessCTA(
        icon: String,
        title: String,
        subtitle: String,
        colors: [Color],
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(icon)
                    .font(.system(size: 17 * UIScale.font))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.22))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11 * UIScale.font, weight: .bold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.85))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: colors.first?.opacity(0.3) ?? Color.black.opacity(0.15), radius: 6, y: 2)
            )
        }
        .buttonStyle(.plain)
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
                            HStack(spacing: 0) {
                                Text("Routin").foregroundColor(Color(red: 1.0, green: 0.29, blue: 0.10))
                                Text("go").foregroundColor(.white)
                            }
                            .font(.system(size: 10 * UIScale.font, weight: .black, design: .rounded))
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

    // MARK: - ヘッダー情報バー（上部固定・ステータスバーまで緑で延伸）
    private var headerInfoBar: some View {
        headerInfoContent
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [Color.duoGreen, Color(red: 0.18, green: 0.58, blue: 0.0)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .ignoresSafeArea(edges: .top)
            )
    }

    // MARK: - ヘッダー情報カード（メインコンテンツ最上部）
    private var headerInfoContent: some View {
        ZStack {
            HStack {
                // 左側: ロゴ
                HStack(spacing: 2) {
                    Image("mascot")
                        .resizable().scaledToFill()
                        .frame(width: 16, height: 16)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 0.4))
                    HStack(spacing: 0) {
                        Text("Routin").foregroundColor(Color(red: 1.0, green: 0.29, blue: 0.10))
                        Text("go").foregroundColor(.white)
                    }
                    .font(.system(size: 16 * UIScale.font, weight: .black, design: .rounded))
                }

                Spacer()

                // 右側: 数値情報
                HStack(spacing: 8) {
                    // 連続記録 + 日付
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 14 * UIScale.font))
                            .foregroundColor(.orange)
                        Text("\(authManager.userProfile?.streak ?? 0)日")
                            .font(.system(size: 10 * UIScale.font, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Text(mandalaDateLabel)
                            .font(.system(size: 10 * UIScale.font, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.85))
                    }

                    // Mandala時間帯進捗率
                    let nc = mandalaOverallCount
                    if nc.total > 0 {
                        let pct = Int(Double(nc.done) / Double(nc.total) * 100)
                        Text("\(pct)%")
                            .font(.system(size: 10 * UIScale.font, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(pct >= 80 ? Color.duoYellow : .white)
                    }
                }
                .padding(.trailing, 6)

                HeaderNavigationMenu(selectedTab: $selectedTab, showRecordMenu: $showRecordMenu)
            }
        }
    }

    // MARK: - ヘッダー計算プロパティ

    private var completionPercentage: Int {
        let totalGoals = timeSlotManager.settings.goals.reduce(0) { $0 + $1.trainingGoal + $1.mindfulnessGoal }
        guard totalGoals > 0 else { return 0 }

        let totalCompleted = timeSlotManager.progress.progress.reduce(0) { $0 + $1.trainingCompleted + $1.mindfulnessCompleted }
        return min(100, Int((Double(totalCompleted) / Double(totalGoals)) * 100))
    }

    private var todayCurrentProgressPercent: Int {
        let activeSlots: [TimeSlot] = [.morning, .noon, .afternoon, .evening]

        var totalTrainingCompleted = 0, totalTrainingGoal = 0
        var totalMindfulMinutes = 0, totalMindfulnessGoal = 0
        var totalMealGoal = 0
        var totalDrinkGoal = 0
        var totalCustomCompleted = 0, totalCustomGoal = 0
        var totalStand = 0, totalStandGoal = 0

        for slot in activeSlots {
            guard let goal = timeSlotManager.settings.goalFor(slot),
                  let progress = timeSlotManager.progress.progressFor(slot) else { continue }
            totalTrainingCompleted += countSetsInTimeSlot(slot)
            totalTrainingGoal += goal.trainingGoal
            totalMindfulMinutes += progress.mindfulnessCompleted * 1 + progress.stretchSetsCompleted * 3
            totalMindfulnessGoal += goal.mindfulnessGoal
            totalMealGoal += goal.logGoal.mealGoal
            totalDrinkGoal += goal.logGoal.drinkGoal
            if goal.standGoal.enabled {
                totalStandGoal += 1
                totalStand += min(1, progress.standCompleted)
            }
            let enabled = goal.customActivities.filter { $0.isEnabled }
            totalCustomGoal += enabled.count
            totalCustomCompleted += enabled.filter { progress.completedActivityIds.contains($0.id) }.count
        }

        var totalGoals = 0
        var completedGoals = 0

        if totalTrainingGoal > 0    { totalGoals += 1; if totalTrainingCompleted >= totalTrainingGoal    { completedGoals += 1 } }
        if totalMindfulnessGoal > 0 { totalGoals += 1; if totalMindfulMinutes    >= totalMindfulnessGoal { completedGoals += 1 } }
        if totalStandGoal > 0       { totalGoals += 1; if totalStand             >= totalStandGoal       { completedGoals += 1 } }
        if totalMealGoal > 0        { totalGoals += 1; if effectiveMealLogged    >= totalMealGoal        { completedGoals += 1 } }
        if totalDrinkGoal > 0       { totalGoals += 1; if Int(healthKit.todayIntakeWater) >= totalDrinkGoal { completedGoals += 1 } }
        if totalCustomGoal > 0      { totalGoals += 1; if totalCustomCompleted   >= totalCustomGoal      { completedGoals += 1 } }

        // 毎日の設定（全曜日共通・Apple Health自動）
        if dailyFixedGoals.foodEnabled   { totalGoals += 1; if healthKit.todayIntakeCalories >= 2000               { completedGoals += 1 } }
        if dailyFixedGoals.weightEnabled { totalGoals += 1; if healthKit.todayBodyMassMeasurements > 0             { completedGoals += 1 } }
        if dailyFixedGoals.sleepEnabled {
            totalGoals += 1
            let sleepDone = healthKit.lastNightTotalHours >= Double(dailyFixedGoals.sleepHoursGoal)
                || timeSlotManager.progress.globalProgress.sleepScore >= timeSlotManager.settings.globalGoals.sleepScoreThreshold
            if sleepDone { completedGoals += 1 }
        }

        // 曜日毎の目標（Apple Health自動チェック + 手動）
        if let wg = todayWeekdayGoal {
            let gp = timeSlotManager.progress.globalProgress
            if wg.exerciseEnabled {
                totalGoals += 1
                let activityDone = healthKit.activityMoveGoal > 0 && healthKit.activityMoveCalories >= healthKit.activityMoveGoal
                    && healthKit.activityExerciseGoal > 0 && Double(healthKit.activityExerciseMinutes) >= Double(healthKit.activityExerciseGoal)
                    && healthKit.activityStandGoal > 0 && Double(healthKit.activityStandHours) >= Double(healthKit.activityStandGoal)
                if activityDone { completedGoals += 1 }
            }
            if wg.studyEnabled    { totalGoals += 1; if gp.completedCustomGoalIds.contains("wd_study_\(wg.weekday)")     { completedGoals += 1 } }
            if wg.noAlcoholEnabled { totalGoals += 1; if gp.completedCustomGoalIds.contains("wd_noalcohol_\(wg.weekday)") { completedGoals += 1 } }
            for cg in wg.customGoals { totalGoals += 1; if gp.completedCustomGoalIds.contains("wd_\(cg.id.uuidString)") { completedGoals += 1 } }
        }
        // 毎日のカスタム目標（曜日に関わらず常にカウント）
        let gpCustom = timeSlotManager.progress.globalProgress
        for cg in dailyFixedGoals.customGoals {
            totalGoals += 1
            if gpCustom.completedCustomGoalIds.contains("daily_custom_\(cg.id.uuidString)") { completedGoals += 1 }
        }

        return totalGoals > 0 ? Int(Double(completedGoals) / Double(totalGoals) * 100) : 0
    }

    private var calorieBalance: Int {
        let consumed = Int(healthKit.todayIntakeCalories)
        let burned = Int(healthKit.todayActiveCalories + healthKit.todayRestingCalories)
        return consumed - burned
    }

    // MARK: - フォトログ（今日分）の集計
    // キャッシュから読む（onChange で photoLogManager.history 変化時のみ再計算）
    private var photoLogTotalsToday: (protein: Double, fat: Double, carbs: Double, calories: Int) {
        cachedPhotoLogTotals
    }

    private func recomputePhotoLogTotals() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        cachedPhotoLogTotals = photoLogManager.history
            .filter { cal.startOfDay(for: $0.timestamp) == today }
            .reduce(into: (0.0, 0.0, 0.0, 0)) { acc, item in
                acc.0 += item.analyzedNutrition.protein
                acc.1 += item.analyzedNutrition.fat
                acc.2 += item.analyzedNutrition.carbs
                acc.3 += item.analyzedNutrition.calories
            }
    }

    private var combinedProtein: Double { healthKit.todayIntakeProtein + cachedPhotoLogTotals.protein }
    private var combinedFat: Double { healthKit.todayIntakeFat + cachedPhotoLogTotals.fat }
    private var combinedCarbs: Double { healthKit.todayIntakeCarbs + cachedPhotoLogTotals.carbs }
    private var combinedIntakeCalories: Int { effectiveIntakeCalories + cachedPhotoLogTotals.calories }

    private var effectiveMealLogged: Int {
        if dietGoalManager.settings.useHealthKitForIntake {
            return Int(healthKit.todayIntakeCalories)
        }
        return TimeSlot.allCases.reduce(0) { sum, slot in
            sum + (timeSlotManager.progress.progressFor(slot)?.logProgress.mealLogged ?? 0)
        }
    }

    private var effectiveIntakeCalories: Int {
        dietGoalManager.settings.useHealthKitForIntake ? Int(healthKit.todayIntakeCalories) : effectiveMealLogged
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
        let totalMealLogged = effectiveMealLogged
        let totalMealGoal = completedSlots.reduce(0) { sum, slot in
            sum + (timeSlotManager.settings.goalFor(slot)?.logGoal.mealGoal ?? 0)
        }
        let totalDrinkLogged = Int(healthKit.todayIntakeWater)
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
        // 毎日の設定（全曜日共通・headerCard用）
        if dailyFixedGoals.foodEnabled {
            totalGoals += 1; if healthKit.todayIntakeCalories >= 2000 { completedGoals += 1 }
        }
        if dailyFixedGoals.weightEnabled {
            totalGoals += 1; if healthKit.todayBodyMassMeasurements > 0 { completedGoals += 1 }
        }
        if dailyFixedGoals.sleepEnabled {
            totalGoals += 1
            let sleepDone2 = healthKit.lastNightTotalHours >= Double(dailyFixedGoals.sleepHoursGoal) || timeSlotManager.progress.globalProgress.sleepScore >= timeSlotManager.settings.globalGoals.sleepScoreThreshold
            if sleepDone2 { completedGoals += 1 }
        }
        // 曜日毎の目標（headerCard用）
        if let wg = todayWeekdayGoal {
            let gp2 = timeSlotManager.progress.globalProgress
            if wg.exerciseEnabled {
                totalGoals += 1
                if healthKit.activityMoveCalories >= healthKit.activityMoveGoal
                    && healthKit.activityExerciseMinutes >= healthKit.activityExerciseGoal
                    && healthKit.activityStandHours >= healthKit.activityStandGoal
                    && healthKit.activityMoveGoal > 0 { completedGoals += 1 }
            }
            if wg.studyEnabled {
                totalGoals += 1
                if gp2.completedCustomGoalIds.contains("wd_study_\(wg.weekday)") { completedGoals += 1 }
            }
            if wg.noAlcoholEnabled {
                totalGoals += 1
                if gp2.completedCustomGoalIds.contains("wd_noalcohol_\(wg.weekday)") { completedGoals += 1 }
            }
            for cg in wg.customGoals {
                totalGoals += 1
                if gp2.completedCustomGoalIds.contains("wd_\(cg.id.uuidString)") { completedGoals += 1 }
            }
        }
        for cg in dailyFixedGoals.customGoals {
            totalGoals += 1
            if timeSlotManager.progress.globalProgress.completedCustomGoalIds.contains("daily_custom_\(cg.id.uuidString)") { completedGoals += 1 }
        }

        let progressPercent = todayCurrentProgressPercent
        let totalConsumed = healthKit.todayTotalCalories
        let intake = healthKit.todayIntakeCalories
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
                            HStack(spacing: 0) {
                                Text("Routin").foregroundColor(Color(red: 1.0, green: 0.29, blue: 0.10))
                                Text("go").foregroundColor(.white)
                            }
                            .font(.system(size: 12 * UIScale.font, weight: .black, design: .rounded))
                        }

                        // 統計情報
                        HStack(spacing: 8) {
                            compactStat(icon: "🔥", value: "\(authManager.userProfile?.streak ?? 0)")
                            compactStat(icon: "📊", value: "\(progressPercent)%")
                            compactStat(icon: balance >= 0 ? "📈" : "📉", value: balance >= 0 ? "+\(Int(balance))" : "\(Int(balance))")
                            compactStat(icon: "⭐", value: "\(authManager.userProfile?.totalPoints ?? 0)")
                        }
                        .padding(.trailing, 48)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }

                HeaderNavigationMenu(selectedTab: $selectedTab, showRecordMenu: $showRecordMenu)
                    .padding(.top, geometry.safeAreaInsets.top + 8)
                    .padding(.trailing, 10)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: geometry.safeAreaInsets.top + 50)
        }
        .frame(height: 94)
    }

    private func compactStat(icon: String, value: String) -> some View {
        HStack(spacing: 1) {
            Text(icon).font(.system(size: 10 * UIScale.font))
            Text(value)
                .font(.system(size: 10 * UIScale.font, weight: .black, design: .rounded))
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

        // 食事は設定に応じてApple Healthまたはダイエット目標の自動実績を使用
        let totalMealLogged = effectiveMealLogged
        let totalMealGoal = completedSlots.reduce(0) { sum, slot in
            sum + (timeSlotManager.settings.goalFor(slot)?.logGoal.mealGoal ?? 0)
        }
        let totalDrinkLogged = Int(healthKit.todayIntakeWater)
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

        // 毎日の設定（全曜日共通・currentTimeSlotStats用）
        if dailyFixedGoals.foodEnabled {
            totalGoals += 1; if healthKit.todayIntakeCalories >= 2000 { completedGoals += 1 }
        }
        if dailyFixedGoals.weightEnabled {
            totalGoals += 1; if healthKit.todayBodyMassMeasurements > 0 { completedGoals += 1 }
        }
        if dailyFixedGoals.sleepEnabled {
            totalGoals += 1
            let sleepDone3 = healthKit.lastNightTotalHours >= Double(dailyFixedGoals.sleepHoursGoal) || timeSlotManager.progress.globalProgress.sleepScore >= timeSlotManager.settings.globalGoals.sleepScoreThreshold
            if sleepDone3 { completedGoals += 1 }
        }
        // 曜日毎の目標（currentTimeSlotStats用）
        if let wg = todayWeekdayGoal {
            let gp3 = timeSlotManager.progress.globalProgress
            if wg.exerciseEnabled {
                totalGoals += 1
                if healthKit.activityMoveCalories >= healthKit.activityMoveGoal
                    && healthKit.activityExerciseMinutes >= healthKit.activityExerciseGoal
                    && healthKit.activityStandHours >= healthKit.activityStandGoal
                    && healthKit.activityMoveGoal > 0 { completedGoals += 1 }
            }
            if wg.studyEnabled {
                totalGoals += 1
                if gp3.completedCustomGoalIds.contains("wd_study_\(wg.weekday)") { completedGoals += 1 }
            }
            if wg.noAlcoholEnabled {
                totalGoals += 1
                if gp3.completedCustomGoalIds.contains("wd_noalcohol_\(wg.weekday)") { completedGoals += 1 }
            }
            for cg in wg.customGoals {
                totalGoals += 1
                if gp3.completedCustomGoalIds.contains("wd_\(cg.id.uuidString)") { completedGoals += 1 }
            }
            for cg in dailyFixedGoals.customGoals {
                totalGoals += 1
                if gp3.completedCustomGoalIds.contains("daily_custom_\(cg.id.uuidString)") { completedGoals += 1 }
            }
        }

        let progressPercent = todayCurrentProgressPercent

        // カロリー収支を計算
        let totalConsumed = healthKit.todayTotalCalories
        let intake = healthKit.todayIntakeCalories
        let balance = intake - totalConsumed
        let isPositive = balance > 0

        return HStack(spacing: 3) {
            // 1. 連続記録
            miniStat("🔥", "\(authManager.userProfile?.streak ?? 0)", "")

            // 2. トータル進捗％
            HStack(spacing: 1) {
                Text("📊").font(.system(size: 9 * UIScale.font))
                Text("\(progressPercent)%")
                    .font(.system(size: 9 * UIScale.font, weight: .black, design: .rounded))
                    .foregroundColor(progressPercent == 100 ? Color.white : Color.white.opacity(0.8))
                if progressPercent == 100 {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 7 * UIScale.font))
                        .foregroundColor(.white)
                }
            }

            // 3. カロリー収支
            HStack(spacing: 1) {
                Text(isPositive ? "📈" : "📉").font(.system(size: 9 * UIScale.font))
                Text(isPositive ? "+" : "")
                    .font(.system(size: 7 * UIScale.font, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                Text("\(Int(abs(balance)))")
                    .font(.system(size: 9 * UIScale.font, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }

            // 4. 総ポイント数
            HStack(spacing: 1) {
                Text("⭐").font(.system(size: 9 * UIScale.font))
                Text("\(authManager.userProfile?.totalPoints ?? 0)")
                    .font(.system(size: 9 * UIScale.font, weight: .black, design: .rounded))
                    .foregroundColor(Color.duoYellow)
            }
        }
    }

    private func miniStat(_ icon: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 1) {
            Text(icon).font(.system(size: 9 * UIScale.font))
            Text(value)
                .font(.system(size: 9 * UIScale.font, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 7 * UIScale.font))
                .foregroundColor(Color.white.opacity(0.7))
        }
    }

    /// 回数＋カロリーを2行で表示するヘッダー統計アイテム
    @ViewBuilder
    private func repCalStat(reps: Int, kcal: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("⚡").font(.system(size: 9 * UIScale.font))
                Text("\(reps)回")
                    .font(.system(size: 10 * UIScale.font, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }
            Text("\(kcal)kcal")
                .font(.system(size: 8 * UIScale.font, weight: .bold))
                .foregroundColor(Color.white.opacity(0.8))
        }
    }

    // MARK: - 今日のセット状況カード
    private var dailySetsCard: some View {
        let mandalaNodes = currentMandalaNodes
        return VStack(alignment: .leading, spacing: 0) {
            Divider().padding(.horizontal, 16)

            DailySetsMandalaSectionView(
                mandalaNodes: mandalaNodes,
                timeSlotManager: timeSlotManager,
                healthKit: healthKit,
                showTracker: $showTracker,
                showMindfulnessSession: $showMindfulnessSession,
                showStretchSession: $showStretchSession,
                showStandSession: $showStandSession,
                showMandalaDetail: $showMandalaDetail,
                selectedMandalaNode: $selectedMandalaNode,
                dailyCalorieDone: dailyCalorieDone,
                dailyWaterDone: dailyWaterDone
            )

            // 展開ボタン + アコーディオン（独立 View でスタックオーバーフローを防止）
            DailySetsExpandableSection(
                timeSlotManager: timeSlotManager,
                healthKit: healthKit,
                todayExercises: todayExercises,
                mandalaContextLabel: mandalaContextString(mandalaNodes),
                dailyCalorieGoal: intakeGoals.dailyCalorieGoal,
                dailyWaterGoal: intakeGoals.dailyWaterGoal
            )

            dailySetsCardButtons
        }
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 5, y: 2)
    }

    // MARK: - 今日の状況カード ヘルパー（スタックオーバーフロー防止のため分離）

    @ViewBuilder
    private func dailySetsCardGreenHeader(
        dateStr: String,
        streak: Int,
        progressPercent: Int,
        allGoalsCompleted: Bool,
        showBadge: Bool,
        isExpanded: Bool
    ) -> some View {
        let pColor: Color = progressPercent >= 70 ? Color.duoGreen
            : progressPercent >= 40 ? Color(hex: "#FF9600")
            : Color(hex: "#FF4B4B")
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 46, height: 46)
                Image("fitingo_simple")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 38, height: 38)
                    .clipShape(Circle())
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(dateStr)
                    .font(.headline).fontWeight(.black)
                    .foregroundColor(.white)
                Text("今日のROUTIN")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.8))
            }
            Spacer()
            HStack(spacing: 3) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12 * UIScale.font))
                    .foregroundColor(Color(red: 1.0, green: 0.65, blue: 0.0))
                Text("\(streak)日")
                    .font(.subheadline).fontWeight(.black)
                    .foregroundColor(.white)
            }
            if showBadge {
                if allGoalsCompleted {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle.fill").font(.caption)
                        Text("完了!").font(.caption).fontWeight(.black)
                    }
                    .foregroundColor(Color.duoGreen)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color(.systemBackground))
                    .cornerRadius(20)
                } else {
                    Text("\(progressPercent)%")
                        .font(.caption).fontWeight(.black)
                        .foregroundColor(pColor)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color(.systemBackground))
                        .cornerRadius(20)
                }
            }
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [Color(red: 0.30, green: 0.75, blue: 0.35), Color(red: 0.18, green: 0.55, blue: 0.22)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
    }

    @ViewBuilder
    private func dailySetsCardStatsArea(
        progressPercent: Int,
        showBar: Bool,
        totalTraining: Int, totalTrainingGoal: Int,
        totalMindfulness: Int, totalMindfulnessGoal: Int,
        totalMealLogged: Int, totalMealGoal: Int,
        totalDrinkLogged: Int, totalDrinkGoal: Int,
        totalCustomCompleted: Int, totalCustomGoal: Int,
        totalStretch: Int, totalStretchGoal: Int,
        completedSlots: Int, totalSlots: Int,
        isExpanded: Bool
    ) -> some View {
        let remaining = totalSlots - completedSlots
        let msg: String = completedSlots == totalSlots
            ? (totalSlots == 4 ? "全時間帯の目標達成！完璧な一日🎉" : "ここまでの時間帯を全部達成💪")
            : completedSlots == 0
            ? "まず1つ目の時間帯を達成しよう！"
            : "あと\(remaining)つの時間帯で本日完全達成！"
        let msgGreen = completedSlots == totalSlots

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(msg)
                    .font(.system(size: 11 * UIScale.font))
                    .fontWeight(msgGreen ? .bold : .regular)
                    .foregroundColor(msgGreen ? Color.duoGreen : Color.duoSubtitle)
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoSubtitle)
            }
            .padding(.top, 2)
        }
        .padding(16)
    }

    @ViewBuilder
    private func dailySetsCardGlobalRow(
        gp: DailyGlobalProgress,
        gg: DailyGlobalGoals,
        sleepAchieved: Bool, pfcAchieved: Bool,
        totalCustomCompleted: Int, totalCustomGoal: Int
    ) -> some View {
        HStack(spacing: 8) {
            if gp.sleepScore > 0 {
                HStack(spacing: 3) {
                    Text("😴").font(.caption)
                    Text("\(gp.sleepScore)").font(.caption).fontWeight(.bold)
                        .foregroundColor(sleepAchieved ? Color.duoGreen : Color.duoDark)
                }
            }
            if gp.pfcScore > 0 {
                HStack(spacing: 3) {
                    Text("🥗").font(.caption)
                    Text("\(gp.pfcScore)").font(.caption).fontWeight(.bold)
                        .foregroundColor(pfcAchieved ? Color.duoGreen : Color.duoDark)
                }
            }
            if gp.weightMeasured {
                HStack(spacing: 3) {
                    Text("⚖️").font(.caption)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoGreen)
                }
            }
            if gg.activityEnabled {
                ZStack {
                    ActivityRingView(
                        progress: healthKit.activityMoveGoal > 0 ? healthKit.activityMoveCalories / healthKit.activityMoveGoal : 0,
                        color: Color(red: 0.98, green: 0.07, blue: 0.31),
                        diameter: 28, lineWidth: 3
                    )
                    ActivityRingView(
                        progress: healthKit.activityExerciseGoal > 0 ? Double(healthKit.activityExerciseMinutes) / Double(healthKit.activityExerciseGoal) : 0,
                        color: Color(red: 0.57, green: 0.91, blue: 0.16),
                        diameter: 20, lineWidth: 3
                    )
                    ActivityRingView(
                        progress: healthKit.activityStandGoal > 0 ? Double(healthKit.activityStandHours) / Double(healthKit.activityStandGoal) : 0,
                        color: Color(red: 0.12, green: 0.89, blue: 0.94),
                        diameter: 12, lineWidth: 3
                    )
                }
                .frame(width: 28, height: 28)
            }
            Spacer()
            if totalCustomGoal > 0 {
                HStack(spacing: 2) {
                    Text("🎯").font(.caption)
                    Text("\(totalCustomCompleted)/\(totalCustomGoal)")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundColor(totalCustomCompleted >= totalCustomGoal ? Color.duoGreen : Color.duoDark)
                }
            }
        }
    }

    // MARK: - 今日の統合履歴（フォトログ下）


    // MARK: - Reflect履歴セクション（展開時）

    private func reflectHistorySection(sessions: [MindfulSession]) -> some View {
        let timeFmt = DashboardView.hhmm
        let totalMinutes = sessions.reduce(0.0) { $0 + $1.durationMinutes }

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("💭")
                    .font(.caption)
                Text("Reflect")
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(Color.duoDark)
                Text("\(sessions.count)回")
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(Color.duoPurple)
                Spacer()
                Text("合計 \(Int(totalMinutes))分")
                    .font(.caption2).fontWeight(.semibold)
                    .foregroundColor(Color.duoSubtitle)
            }

            ForEach(sessions) { session in
                HStack(spacing: 8) {
                    Text(timeFmt.string(from: session.startDate))
                        .font(.system(size: 12 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)
                        .frame(width: 42, alignment: .leading)
                    Text(String(format: "%.0f分", session.durationMinutes))
                        .font(.system(size: 12 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor(Color.duoPurple)
                    Spacer()
                    let stretchCount = Int(session.durationMinutes)
                    if stretchCount > 0 {
                        HStack(spacing: 3) {
                            Text("🤸")
                                .font(.system(size: 11 * UIScale.font))
                            Text("×\(stretchCount)")
                                .font(.system(size: 11 * UIScale.font, weight: .semibold))
                                .foregroundColor(Color(red: 0.22, green: 0.75, blue: 0.56))
                        }
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.duoPurple.opacity(0.06))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - 体重計測履歴セクション（展開時）

    private var bodyMassHistorySection: some View {
        let dateFmt = DashboardView.slashMdE
        let timeFmt = DashboardView.hhmm
        let recent = Array(healthKit.bodyMassHistory.prefix(7))

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "scalemass.fill")
                    .font(.caption2)
                    .foregroundColor(Color(hex: "#1CB0F6"))
                Text("体重計測履歴")
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(Color.duoDark)
                Spacer()
                if let change = healthKit.weeklyBodyMassChange {
                    let sign = change >= 0 ? "+" : ""
                    let col: Color = change > 0 ? Color(hex: "#FF9600") : change < 0 ? Color.duoGreen : Color.duoSubtitle
                    Text("\(sign)\(String(format: "%.1f", change)) kg / 7日")
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundColor(col)
                }
            }

            ForEach(recent) { record in
                HStack(spacing: 8) {
                    Text(dateFmt.string(from: record.measuredAt))
                        .font(.system(size: 11 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)
                        .frame(width: 70, alignment: .leading)
                    Text(timeFmt.string(from: record.measuredAt))
                        .font(.system(size: 11 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)
                    Spacer()
                    Text(String(format: "%.1f kg", record.kg))
                        .font(.system(size: 12 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor(Color.duoDark)
                    let isToday = Calendar.current.isDateInToday(record.measuredAt)
                    if isToday {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11 * UIScale.font))
                            .foregroundColor(Color.duoGreen)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Calendar.current.isDateInToday(record.measuredAt)
                    ? Color.duoGreen.opacity(0.07)
                    : Color(.systemGray6))
                .cornerRadius(8)
            }
        }
    }

    private var dailySetsCardButtons: some View {
        DailySetsCardButtonsView(
            trainingVideoPlaylist: trainingVideoPlaylist,
            mascotBounce: mascotBounce,
            showTrainingVideo: $showTrainingVideo,
            trainingVideoIndex: $trainingVideoIndex,
            onStartTracker: { showTracker = true },
            onOpenMindfulness: openMindfulness,
            onOpenStretch: openStretch,
            onOpenStand: openStand,
            onOpenPhotoLog: { showPhotoLog = true },
            angerLevel: computeAngerLevel(),
            todaySessions: TimeSlot.allCases.reduce(0) { $0 + countSetsInTimeSlot($1) },
            dailyGoal: fitingoDailyGoal(),
            fitingoMessage: { sessions, goal, behind in fitingoMessage(sessions: sessions, dailyGoal: goal, isBehind: behind) }
        )
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
                    .font(.system(size: 28 * UIScale.font, weight: .black, design: .rounded))
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
        .background(Color(.systemBackground))
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

            // マインドフルネス記録（個別セッション）
            if !healthKit.todayMindfulnessSamples.isEmpty {
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Text("🧘").font(.caption)
                        Text("マインドフルネス")
                            .font(.caption).fontWeight(.black)
                            .foregroundColor(Color.duoPurple)
                        Text("·")
                            .font(.caption2).foregroundColor(Color.duoSubtitle)
                        Text("計\(Int(healthKit.todayMindfulnessMinutes))分")
                            .font(.caption2).foregroundColor(Color.duoSubtitle)
                        Spacer()
                        Text("\(healthKit.todayMindfulnessSamples.count)セッション")
                            .font(.caption2).fontWeight(.bold)
                            .foregroundColor(Color.duoPurple.opacity(0.7))
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 2)

                    ForEach(healthKit.todayMindfulnessSamples) { session in
                        mindfulSessionRow(session)
                    }
                }
                .background(Color.duoPurple.opacity(0.05))
                .cornerRadius(10)
                .padding(.horizontal, 16)
            }

            // 水分記録（200ml以上のサンプル）
            let significantWater = healthKit.todayWaterSamples.filter { $0.value >= 200 }
            if !significantWater.isEmpty {
                intakeSampleSection(
                    icon: "💧", title: "水分記録",
                    total: "計\(Int(healthKit.todayIntakeWater))ml",
                    color: Color.duoBlue,
                    samples: significantWater,
                    unit: "ml"
                )
            }

            // 食事記録（400kcal以上のサンプル）
            let significantMeals = healthKit.todayMealSamples.filter { $0.value >= 400 }
            if !significantMeals.isEmpty {
                intakeSampleSection(
                    icon: "🍽️", title: "食事記録",
                    total: "計\(Int(healthKit.todayIntakeCalories))kcal",
                    color: Color.duoOrange,
                    samples: significantMeals,
                    unit: "kcal"
                )
            }

            Spacer(minLength: 12)
        }
    }

    // MARK: - マインドフルネスセッション行
    private func mindfulSessionRow(_ session: MindfulSession) -> some View {
        let timeFmt = DashboardView.hhmm
        let durationText: String = {
            let totalSec = Int(session.durationMinutes * 60)
            let m = totalSec / 60
            let s = totalSec % 60
            if m == 0 { return "\(s)秒" }
            if s == 0 { return "\(m)分" }
            return "\(m)分\(s)秒"
        }()
        let isReflect = session.sessionTypeLabel == "Reflect"
        let japaneseLabel = isReflect ? "3分ストレッチ" : (session.sessionTypeLabel == "Breathe" ? "1分瞑想" : session.sessionTypeLabel)
        let xp = isReflect ? 30 : 10

        return HStack(spacing: 8) {
            // ソース別アイコン
            Text(session.sessionEmoji)
                .font(.system(size: 12 * UIScale.font))
                .frame(width: 24, height: 24)
                .background(Color.duoPurple.opacity(0.15))
                .clipShape(Circle())
            // セッション種別ラベル（日本語）+ 時刻
            VStack(alignment: .leading, spacing: 1) {
                Text(japaneseLabel)
                    .font(.caption2).fontWeight(.bold)
                    .foregroundColor(Color.duoDark)
                    .lineLimit(1)
                Text(timeFmt.string(from: session.startDate))
                    .font(.system(size: 9 * UIScale.font))
                    .foregroundColor(Color.duoSubtitle)
            }
            Spacer()
            // 平均心拍・HRV
            if session.averageHeartRate > 0 || session.averageHRV > 0 {
                HStack(spacing: 6) {
                    if session.averageHeartRate > 0 {
                        HStack(spacing: 2) {
                            Text("❤️").font(.system(size: 9 * UIScale.font))
                            Text("\(Int(session.averageHeartRate))")
                                .font(.system(size: 9 * UIScale.font, weight: .bold))
                                .foregroundColor(Color(red: 1.0, green: 0.294, blue: 0.294))
                        }
                    }
                    if session.averageHRV > 0 {
                        HStack(spacing: 2) {
                            Text("💙").font(.system(size: 9 * UIScale.font))
                            Text("\(Int(session.averageHRV))")
                                .font(.system(size: 9 * UIScale.font, weight: .bold))
                                .foregroundColor(Color(hex: "#1CB0F6"))
                        }
                    }
                }
            }
            // XPバッジ
            Text("+\(xp) XP")
                .font(.system(size: 9 * UIScale.font, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "#FDCB6E"))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color(hex: "#FDCB6E").opacity(0.15))
                .cornerRadius(6)
            // 時間
            Text(durationText)
                .font(.caption2).fontWeight(.bold)
                .foregroundColor(Color.duoPurple)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10 * UIScale.font))
                .foregroundColor(Color.duoPurple)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - 摂取サンプルセクション（水分・食事）
    private func intakeSampleSection(icon: String, title: String, total: String, color: Color, samples: [DietarySample], unit: String) -> some View {
        let timeFmt = DashboardView.hhmm
        return VStack(spacing: 2) {
            HStack(spacing: 6) {
                Text(icon).font(.caption)
                Text(title)
                    .font(.caption).fontWeight(.black)
                    .foregroundColor(color)
                Spacer()
                Text(total)
                    .font(.caption2).foregroundColor(Color.duoSubtitle)
            }
            .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 2)

            ForEach(samples) { sample in
                HStack(spacing: 8) {
                    Text(icon)
                        .font(.system(size: 11 * UIScale.font))
                        .frame(width: 22, height: 22)
                        .background(color.opacity(0.15))
                        .clipShape(Circle())
                    Text(timeFmt.string(from: sample.startDate))
                        .font(.caption2).foregroundColor(Color.duoSubtitle)
                    Spacer()
                    Text("\(Int(sample.value))\(unit)")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundColor(color)
                }
                .padding(.horizontal, 12).padding(.vertical, 4)
            }
        }
        .background(color.opacity(0.05))
        .cornerRadius(10)
        .padding(.horizontal, 16)
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
                        .background(Color(.systemBackground))
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
                        .font(.system(size: 12 * UIScale.font))
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

    // MARK: - 時間帯別アクティビティアイコン（スタックオーバーフロー防止のため分離）

    private func progressCheckIcon(emoji: String, done: Bool, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(emoji).font(.caption)
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.caption2)
                .foregroundColor(done ? color : Color(.systemGray4))
        }
    }

    // MARK: - 1日全体の達成フラグ（スロットアイコン用）

    private var dailyTrainingAllDone: Bool {
        let slots: [TimeSlot] = [.morning, .noon, .afternoon, .evening]
        let totalGoal = slots.reduce(0) { $0 + (timeSlotManager.settings.goalFor($1)?.trainingGoal ?? 0) }
        let totalDone = slots.reduce(0) { $0 + countSetsInTimeSlot($1) }
        return totalGoal > 0 && totalDone >= totalGoal
    }

    private var dailyMindfulnessAllDone: Bool {
        let slots: [TimeSlot] = [.morning, .noon, .afternoon, .evening]
        let totalGoal = slots.reduce(0) { $0 + (timeSlotManager.settings.goalFor($1)?.mindfulnessGoal ?? 0) }
        let totalDone = slots.reduce(0) {
            let prog = timeSlotManager.progress.progressFor($1)
            return $0 + (prog?.mindfulnessCompleted ?? 0) * 1 + (prog?.stretchSetsCompleted ?? 0) * 3
        }
        return totalGoal > 0 && totalDone >= totalGoal
    }

    private var dailyStandAllDone: Bool {
        [TimeSlot.morning, .noon, .afternoon, .evening].contains {
            (timeSlotManager.settings.goalFor($0)?.standGoal.enabled == true) &&
            (timeSlotManager.progress.progressFor($0)?.standCompleted ?? 0) >= 1
        }
    }

    private var dailyCompletedActivityNames: Set<String> {
        var names: Set<String> = []
        for slot in [TimeSlot.morning, .noon, .afternoon, .evening] {
            guard let goal = timeSlotManager.settings.goalFor(slot),
                  let prog = timeSlotManager.progress.progressFor(slot) else { continue }
            for activity in goal.customActivities where activity.isEnabled && prog.completedActivityIds.contains(activity.id) {
                names.insert(activity.name)
            }
        }
        return names
    }

    private func slotActivityIcons(goal: TimeSlotGoal?, progress: TimeSlotProgress?, slot: TimeSlot) -> some View {
        let standColor = Color(red: 0.0, green: 0.6, blue: 0.85)
        let mindfulMinutes = (progress?.mindfulnessCompleted ?? 0) * 1 + (progress?.stretchSetsCompleted ?? 0) * 3

        let trainingDone = dailyTrainingAllDone || (goal.map { countSetsInTimeSlot(slot) >= $0.trainingGoal } ?? false)
        let mindDone = dailyMindfulnessAllDone || (goal.map { mindfulMinutes >= $0.mindfulnessGoal } ?? false)
        let standDone = dailyStandAllDone || (progress?.standCompleted ?? 0) >= 1
        let customs = goal?.customActivities.filter { $0.isEnabled } ?? []

        return HStack(spacing: 2) {
            if let goal = goal, goal.trainingGoal > 0 {
                progressCheckIcon(emoji: "💪", done: trainingDone, color: Color.duoGreen)
            }
            if let goal = goal, goal.mindfulnessGoal > 0 {
                progressCheckIcon(emoji: "🧘", done: mindDone, color: Color.duoGreen)
            }
            if let goal = goal, slot != .midnight, goal.standGoal.enabled {
                progressCheckIcon(emoji: "🧍", done: standDone, color: standColor)
            }
            ForEach(customs) { act in
                slotCustomActivityIcon(act: act, progress: progress, slot: slot)
            }
        }
    }

    private func slotCustomActivityIcon(act: CustomActivity, progress: TimeSlotProgress?, slot: TimeSlot) -> some View {
        let done = dailyCompletedActivityNames.contains(act.name) || (progress?.completedActivityIds.contains(act.id) ?? false)
        return Button {
            Task { await timeSlotManager.toggleCustomActivity(id: act.id, at: slot) }
        } label: {
            progressCheckIcon(emoji: act.emoji, done: done, color: Color.duoGreen)
        }
        .buttonStyle(.plain)
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
                    .font(.system(size: 9 * UIScale.font))
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
                                    .font(.system(size: 9 * UIScale.font))
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
                slotActivityIcons(goal: goal, progress: progress, slot: slot)
            }

            Spacer()

            // ログ進捗バッジ（夜中以外）- 目標達成でチェック
            if slot != .midnight, let goal = goal, let progress = progress {
                HStack(spacing: 4) {
                    if goal.logGoal.mealGoal > 0 {
                        let mealDone = progress.logProgress.mealLogged >= goal.logGoal.mealGoal
                        Image(systemName: mealDone ? "fork.knife.circle.fill" : "fork.knife.circle")
                            .font(.title3)
                            .foregroundColor(mealDone ? Color.duoGreen : Color(.systemGray4))
                    }
                    if goal.logGoal.drinkGoal > 0 {
                        let drinkDone = progress.logProgress.drinkLogged >= goal.logGoal.drinkGoal
                        Image(systemName: drinkDone ? "drop.circle.fill" : "drop.circle")
                            .font(.title3)
                            .foregroundColor(drinkDone ? Color.duoBlue : Color(.systemGray4))
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - ハビットスタックカード
    // MARK: - Mandala Card

    private var mandalaDateLabel: String { DashboardView.mdE.string(from: Date()) }

    // MARK: - 日次目標達成フラグ（HealthKit + アプリ記録の合算で判定）

    /// 1日の食事カロリー合計（HealthKit と Firestore スロット記録の大きい方）
    private var bestDailyMealKcal: Int {
        let fromApp = [TimeSlot.morning, .noon, .afternoon, .evening].reduce(0) { sum, slot in
            sum + (timeSlotManager.progress.progressFor(slot)?.logProgress.mealLogged ?? 0)
        }
        return max(Int(healthKit.todayIntakeCalories), fromApp)
    }

    /// 1日の水分摂取量 ml 合計（HealthKit と Firestore スロット記録の大きい方）
    private var bestDailyWaterMl: Int {
        // Firestore: drinkLogged はすでに ml 単位で累積保存されている
        let fromApp = [TimeSlot.morning, .noon, .afternoon, .evening].reduce(0) { sum, slot in
            sum + (timeSlotManager.progress.progressFor(slot)?.logProgress.drinkLogged ?? 0)
        }
        return max(Int(healthKit.todayIntakeWater), fromApp)
    }

    /// 日次カロリー目標達成: 全スロットの食事アイコンを一括完了にする
    private var dailyCalorieDone: Bool {
        bestDailyMealKcal >= intakeGoals.dailyCalorieGoal
    }

    /// 日次水分目標達成: 全スロットの水分アイコンを一括完了にする
    private var dailyWaterDone: Bool {
        bestDailyWaterMl >= intakeGoals.dailyWaterGoal
    }

    // buildNodes() を1回だけ呼び出し、他のプロパティで再利用する
    // 時間帯カードと同じ実績ソース（countSetsInTimeSlot / HealthKit）を使い、スパイラルの完了を正確に反映する
    private var currentMandalaNodes: [MandalaNodeData] {
        let activeSlots: [TimeSlot] = [.morning, .noon, .afternoon, .evening]

        // トレーニング: countSetsInTimeSlot() の結果（実際の運動履歴ベース）
        var trainCounts: [String: Int] = [:]
        for slot in activeSlots {
            trainCounts[slot.rawValue] = countSetsInTimeSlot(slot)
        }

        // マインドフルネス: Firestore prog + HealthKitのセッション数をスロット時間帯で振り分け
        var mindfulMinutes: [String: Int] = [:]
        for slot in activeSlots {
            let prog = timeSlotManager.progress.progressFor(slot)
            let goal = timeSlotManager.settings.goalFor(slot)
            // ストレッチ目標分数（設定値を使用。未設定時は3分）
            let stretchGoalMin = (goal?.stretchGoal.stretchMinutes ?? 3)
            let stretchMin = (prog?.stretchSetsCompleted ?? 0) * stretchGoalMin
            // HealthKit のマインドフルネスセッションをスロット時間帯でフィルタ
            let hkMin: Int = healthKit.todayMindfulnessSamples
                .filter { session in
                    let h = Calendar.current.component(.hour, from: session.startDate)
                    return h >= slot.startHour && h < slot.endHour
                }
                .reduce(0) { $0 + max(1, Int($1.durationMinutes.rounded())) }
            // HKデータがあればそれを使用（実施時間ベース）。なければFirestoreのカウントにフォールバック
            let firestoreMin = (prog?.mindfulnessCompleted ?? 0) * 1
            mindfulMinutes[slot.rawValue] = (hkMin > 0 ? hkMin : firestoreMin) + stretchMin
        }

        // 時間帯別の実際の水分摂取量（HealthKit: ml）
        var slotWaterMl: [String: Int] = [:]
        for slot in activeSlots {
            slotWaterMl[slot.rawValue] = Int(healthKit.todayWaterSamples
                .filter { let h = Calendar.current.component(.hour, from: $0.startDate)
                    return h >= slot.startHour && h < slot.endHour }
                .reduce(0.0) { $0 + $1.value })
        }

        // 時間帯別の実際のカロリー摂取量（HealthKit: kcal）
        var slotMealKcal: [String: Int] = [:]
        for slot in activeSlots {
            slotMealKcal[slot.rawValue] = Int(healthKit.todayMealSamples
                .filter { let h = Calendar.current.component(.hour, from: $0.startDate)
                    return h >= slot.startHour && h < slot.endHour }
                .reduce(0.0) { $0 + $1.value })
        }

        // 1日合計のトレーニング完了・目標を計算
        let totalTrainingDone = activeSlots.reduce(0) { $0 + (trainCounts[$1.rawValue] ?? 0) }
        let totalTrainingGoal = activeSlots.reduce(0) { $0 + (timeSlotManager.settings.goalFor($1)?.trainingGoal ?? 0) }
        let dailyTrainingDone = totalTrainingGoal > 0 && totalTrainingDone >= totalTrainingGoal

        // 1日合計のマインドフルネス完了・目標を計算（瞑想のみ）
        let totalMindfulDone = mindfulMinutes.values.reduce(0, +)
        let totalMindfulGoal = activeSlots.reduce(0) { $0 + (timeSlotManager.settings.goalFor($1)?.mindfulnessGoal ?? 0) }
        let dailyMindfulnessDone = totalMindfulGoal > 0 && totalMindfulDone >= totalMindfulGoal

        // ── マインドフルネス統合目標（瞑想 + ストレッチ + スタンド合計分） ──
        // 目標: 各スロットの (瞑想分 + ストレッチ分 + スタンド分) の総和
        let totalMindfulStandGoal = activeSlots.reduce(0) { sum, slot in
            guard let goal = timeSlotManager.settings.goalFor(slot) else { return sum }
            let mindMin   = goal.mindfulnessGoal                                           // 1セッション=1分
            let stretchMin = goal.stretchGoal.enabled ? goal.stretchGoal.stretchMinutes : 0
            let standMin   = goal.standGoal.enabled   ? goal.standGoal.standMinutes   : 0
            return sum + mindMin + stretchMin + standMin
        }
        // 実績: mindfulMinutes には瞑想+ストレッチが既に含まれる。スタンドを加算
        // HK mindfulness セッションにスタンドタイマーセッションも含まれるため、HK から検出
        let totalMindfulStandActual = activeSlots.reduce(0) { sum, slot in
            let prog     = timeSlotManager.progress.progressFor(slot)
            let goalInfo = timeSlotManager.settings.goalFor(slot)
            let rawMindAndStretch = mindfulMinutes[slot.rawValue] ?? 0

            guard let goalInfo, goalInfo.standGoal.enabled else {
                return sum + rawMindAndStretch
            }
            let standGoalMin = goalInfo.standGoal.standMinutes

            // HK の同スロット内に standGoalMin 分以上の mindfulness セッションがあれば
            // スタンドタイマー達成とみなす（スタンドタイマーは HK に mindfulness として記録される）
            let hasHKStand = healthKit.todayMindfulnessSamples
                .filter { let h = Calendar.current.component(.hour, from: $0.startDate)
                          return h >= slot.startHour && h < slot.endHour }
                .contains { max(1, Int($0.durationMinutes.rounded())) >= standGoalMin }
            let firestoreStandDone = (prog?.standCompleted ?? 0) >= 1
            let standActual = (hasHKStand || firestoreStandDone) ? standGoalMin : 0

            // HK スタンドセッション分は mindfulMinutes に含まれているため二重計上を防止
            let mindAndStretch = hasHKStand ? max(0, rawMindAndStretch - standGoalMin) : rawMindAndStretch

            return sum + mindAndStretch + standActual
        }
        // 統合目標達成 → 瞑想・ストレッチ・スタンド全アイコンを一括完了
        let dailyMindfulAndStandDone = totalMindfulStandGoal > 0
            && totalMindfulStandActual >= totalMindfulStandGoal

        return MandalaChartView.buildNodes(
            settings: timeSlotManager.settings,
            progress: timeSlotManager.progress,
            activityRingsDone: healthKit.activityMoveCalories >= healthKit.activityMoveGoal &&
                healthKit.activityExerciseMinutes >= healthKit.activityExerciseGoal,
            slotTrainingCounts: trainCounts,
            slotMindfulMinutes: mindfulMinutes,
            slotWaterMl: slotWaterMl,
            slotMealKcal: slotMealKcal,
            dailyCalorieDone: dailyCalorieDone,
            dailyWaterDone: dailyWaterDone,
            totalDailyCalorieGoal: intakeGoals.dailyCalorieGoal,
            totalDailyWaterGoal: intakeGoals.dailyWaterGoal,
            dailyTrainingDone: dailyTrainingDone,
            dailyMindfulnessDone: dailyMindfulnessDone,
            dailyMindfulAndStandDone: dailyMindfulAndStandDone,
            loggedCompletionIds: MandalaCompletionLogger.shared.todayCompletedIds
        )
    }

    private var currentMandalaHour: Int { Calendar.current.component(.hour, from: Date()) }

    private var mandalaVisibleSlots: [TimeSlot] {
        let h = currentMandalaHour
        if h < 10 { return [.morning] }
        else if h < 14 { return [.morning, .noon] }
        else if h < 18 { return [.morning, .noon, .afternoon] }
        else { return [.morning, .noon, .afternoon, .evening] }
    }

    private func mandalaContextString(_ nodes: [MandalaNodeData]) -> String {
        let hour = currentMandalaHour
        let currentSlot: TimeSlot? = {
            if hour >= 5 && hour < 10 { return .morning }
            else if hour >= 10 && hour < 14 { return .noon }
            else if hour >= 14 && hour < 18 { return .afternoon }
            else if hour >= 18 { return .evening }
            return nil
        }()
        if let slot = currentSlot {
            let slotNodes = nodes.filter { $0.slot == slot }
            let incomplete = slotNodes.filter { !$0.isCompleted }
            if let first = incomplete.first {
                return "\(first.emoji) \(first.label)を記録しましょう"
            } else if !slotNodes.isEmpty {
                return "\(slot.displayName)のタスク完了！このまま継続"
            }
        }
        let todayIncomplete = nodes.filter { $0.slot == nil && !$0.isCompleted }
        if let first = todayIncomplete.first {
            return "\(first.emoji) \(first.label)を記録しましょう"
        }
        return "今日のタスクはすべて完了！"
    }

    private var mandalaOverallCount: (done: Int, total: Int) {
        let visibleSlotSet = Set(mandalaVisibleSlots)
        let nodes = currentMandalaNodes
        let visible = nodes.filter { $0.slot == nil || visibleSlotSet.contains($0.slot!) }
        return (visible.filter(\.isCompleted).count, visible.count)
    }

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
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
    }


    // MARK: - 本の紹介カード
    private var bookPromoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("関連情報")
                .font(.caption).fontWeight(.black)
                .foregroundColor(Color.duoSubtitle)
                .textCase(.uppercase)
                .tracking(1.5)
                .padding(.horizontal, 4)

            // iOSアプリ（App Store）
            Link(destination: URL(string: "https://apps.apple.com/app/fitingo/id000000000")!) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Color.black)
                            .frame(width: 48, height: 48)
                        Image(systemName: "applelogo")
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fitingo iOS アプリ")
                            .font(.subheadline).fontWeight(.black)
                            .foregroundColor(Color.duoDark)
                        Text("Apple Watch連携・モーションセンサーで本格トレーニング")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                            .lineLimit(1)
                        Text("App Store でダウンロード")
                            .font(.caption2).fontWeight(.bold)
                            .foregroundColor(Color.duoGreen)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundColor(Color.duoSubtitle)
                }
                .padding(14)
                .background(Color(.systemBackground))
                .cornerRadius(14)
                .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
            }

            // AppleWatch Diet 本
            Link(destination: URL(string: "https://amzn.to/43GSmB6")!) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.9, green: 0.97, blue: 0.93))
                            .frame(width: 48, height: 48)
                        Text("⌚").font(.title2)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AppleWatch Diet Ultra2")
                            .font(.subheadline).fontWeight(.black)
                            .foregroundColor(Color.duoDark)
                        Text("Apple Watchで痩せる100のメソッド")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                            .lineLimit(1)
                        Text("📖 Kindle で読む")
                            .font(.caption2).fontWeight(.bold)
                            .foregroundColor(Color(red: 0.85, green: 0.55, blue: 0.0))
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundColor(Color.duoSubtitle)
                }
                .padding(14)
                .background(Color(.systemBackground))
                .cornerRadius(14)
                .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
            }

            // Cursor + Claude 本
            Link(destination: URL(string: "https://amzn.to/43GSmB6")!) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.93, green: 0.95, blue: 1.0))
                            .frame(width: 48, height: 48)
                        Text("📱").font(.title2)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cursor + Claude で iOS アプリを作る")
                            .font(.subheadline).fontWeight(.black)
                            .foregroundColor(Color.duoDark)
                        Text("週末だけで iPhone・Apple Watch アプリを個人開発")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                            .lineLimit(1)
                        Text("📖 Kindle で読む")
                            .font(.caption2).fontWeight(.bold)
                            .foregroundColor(Color(red: 0.85, green: 0.55, blue: 0.0))
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundColor(Color.duoSubtitle)
                }
                .padding(14)
                .background(Color(.systemBackground))
                .cornerRadius(14)
                .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
            }
        }
        .padding(4)
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
                    Button {
                        Task {
                            await healthKit.fetchDashboardHealth(force: true)
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
    private var conditionalSleepCard: AnyView {
        dailyFixedGoals.sleepEnabled
            ? AnyView(integratedSleepCard) : AnyView(EmptyView())
    }

    private var conditionalActivityCard: AnyView {
        todayWeekdayGoal?.exerciseEnabled == true
            ? AnyView(activityRingsCard) : AnyView(EmptyView())
    }

    private var healthMetricsGrid: some View {
        AnyView(healthMetricsGridBottom)
    }

    private var conditionalHeartRateCard: AnyView {
        AnyView(heartRateWithHRVItem)
    }

    @ViewBuilder
    private var healthMetricsGridBottom: some View {
        EmptyView()
    }

    // MARK: - FOODカード（PFCリング + 水分/カフェイン/アルコール）
    private var foodCard: some View {
        let pfcScore = pfcAnalysis?.score ?? 0
        let totalCal = todayIntake.totalCalories > 0 ? todayIntake.totalCalories : Int(healthKit.todayIntakeCalories)

        return Button {
            selectedTab = MainMenuTab.food.rawValue
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // ヘッダー
                HStack(spacing: 4) {
                    Text("FOOD")
                        .font(.system(size: 8 * UIScale.font, weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.duoGreen)
                        .cornerRadius(4)
                    Spacer()
                    if totalCal > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 8 * UIScale.font))
                                .foregroundColor(Color.duoOrange)
                            Text("\(totalCal)")
                                .font(.system(size: 10 * UIScale.font, weight: .black))
                                .foregroundColor(Color.duoOrange)
                            Text("kcal")
                                .font(.system(size: 8 * UIScale.font))
                                .foregroundColor(Color.duoSubtitle)
                        }
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.duoOrange.opacity(0.1))
                        .cornerRadius(6)
                    }
                    if pfcScore > 0 {
                        Text("\(pfcScore)点")
                            .font(.system(size: 10 * UIScale.font, weight: .bold))
                            .foregroundColor(scoreColorForPFC(pfcScore))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(scoreColorForPFC(pfcScore).opacity(0.15))
                            .cornerRadius(8)
                        if let rating = pfcAnalysis?.rating {
                            Text(rating)
                                .font(.system(size: 10 * UIScale.font, weight: .black))
                                .foregroundColor(scoreColorForPFC(pfcScore))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(scoreColorForPFC(pfcScore).opacity(0.12))
                                .cornerRadius(8)
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoSubtitle.opacity(0.5))
                }

                HStack(spacing: 12) {
                    // PFCリング
                    if let analysis = pfcAnalysis, analysis.score > 0 {
                        ZStack {
                            PFCPieChart(
                                proteinPercent: analysis.proteinPercent,
                                fatPercent: analysis.fatPercent,
                                carbsPercent: analysis.carbsPercent
                            )
                            .frame(width: 54, height: 54)
                            VStack(spacing: 0) {
                                Text("\(analysis.score)")
                                    .font(.system(size: 15 * UIScale.font, weight: .black))
                                    .foregroundColor(scoreColorForPFC(analysis.score))
                                Text("点")
                                    .font(.system(size: 7 * UIScale.font))
                                    .foregroundColor(Color.duoSubtitle)
                            }
                        }
                        .frame(width: 54, height: 54)
                    } else {
                        ZStack {
                            Circle()
                                .stroke(Color(.systemGray5), lineWidth: 5)
                                .frame(width: 54, height: 54)
                            Image(systemName: "chart.pie")
                                .font(.system(size: 20 * UIScale.font))
                                .foregroundColor(Color.duoSubtitle.opacity(0.4))
                        }
                        .frame(width: 54, height: 54)
                    }

                    // 水分 / カフェイン / アルコール
                    VStack(alignment: .leading, spacing: 5) {
                        foodMiniRow(icon: "drop.fill", color: Color.duoBlue,
                                    label: "水分",
                                    value: Double(todayIntake.totalWaterMl),
                                    goal: Double(intakeGoals.dailyWaterGoal),
                                    unit: "ml",
                                    format: { "\(Int($0))" },
                                    isReverse: false)
                        Divider()
                        foodMiniRow(icon: "cup.and.saucer.fill", color: Color.duoBrown,
                                    label: "カフェイン",
                                    value: Double(todayIntake.totalCaffeineMg),
                                    goal: Double(intakeGoals.dailyCaffeineLimit),
                                    unit: "mg",
                                    format: { "\(Int($0))" },
                                    isReverse: true)
                        Divider()
                        foodMiniRow(icon: "wineglass.fill", color: Color.duoPurple,
                                    label: "アルコール",
                                    value: todayIntake.totalAlcoholG,
                                    goal: intakeGoals.dailyAlcoholLimit,
                                    unit: "g",
                                    format: { String(format: "%.1f", $0) },
                                    isReverse: true)
                    }

                    Spacer()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func foodMiniRow(icon: String, color: Color, label: String,
                              value: Double, goal: Double?, unit: String,
                              format: (Double) -> String, isReverse: Bool) -> some View {
        let percent  = goal != nil && goal! > 0 ? Int((value / goal!) * 100) : 0
        let isOver   = goal != nil && value > goal!
        let dispColor: Color
        if label == "水分" {
            dispColor = percent >= 100 ? .duoGreen : percent >= 70 ? .duoGreen.opacity(0.8) : .duoOrange
        } else {
            dispColor = (isOver || percent >= 100) ? .red : percent >= 70 ? .duoOrange : .duoGreen
        }
        return AnyView(HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8 * UIScale.font))
                .foregroundColor(color)
                .frame(width: 12)
            Text(label)
                .font(.system(size: 8 * UIScale.font, weight: .bold))
                .foregroundColor(Color.duoSubtitle)
            Spacer()
            if let g = goal, g > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(value > 0 ? format(value) : "0")
                        .font(.system(size: 11 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor((isOver && isReverse) ? .red : dispColor)
                    Text("/\(format(g))")
                        .font(.system(size: 8 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)
                    Text(unit)
                        .font(.system(size: 8 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)
                }
            } else {
                HStack(spacing: 1) {
                    Text(value > 0 ? format(value) : "—")
                        .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor((isOver && isReverse) ? .red : dispColor)
                    Text(unit)
                        .font(.system(size: 8 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)
                }
            }
        })
    }

    // MARK: - FITカード（アクティビティリング + 体重・セット数）

    private var activityRingsCard: some View {
        let moveColor     = Color(red: 0.98, green: 0.07, blue: 0.31)
        let exerciseColor = Color(red: 0.57, green: 0.91, blue: 0.16)
        let standColor    = Color(red: 0.12, green: 0.89, blue: 0.94)
        let moveP     = healthKit.activityMoveGoal > 0
            ? min(healthKit.activityMoveCalories / healthKit.activityMoveGoal, 1.0) : 0
        let exerciseP = healthKit.activityExerciseGoal > 0
            ? min(Double(healthKit.activityExerciseMinutes) / Double(healthKit.activityExerciseGoal), 1.0) : 0
        let standP    = healthKit.activityStandGoal > 0
            ? min(Double(healthKit.activityStandHours) / Double(healthKit.activityStandGoal), 1.0) : 0
        let activeCount = (healthKit.activityMoveGoal > 0 ? 1 : 0)
            + (healthKit.activityExerciseGoal > 0 ? 1 : 0)
            + (healthKit.activityStandGoal > 0 ? 1 : 0)
        let activityScore = activeCount > 0
            ? Int((moveP + exerciseP + standP) / Double(activeCount) * 100) : 0
        let nowHour = Calendar.current.component(.hour, from: Date())
        let nowMin  = Calendar.current.component(.minute, from: Date())
        let nowDec  = Double(nowHour) + Double(nowMin) / 60.0
        let expectedPace: Double = nowDec <= 6 ? 0 : nowDec >= 24 ? 1 : (nowDec - 6) / 18.0
        let paceDiff = activityScore - Int(expectedPace * 100)
        let (paceLabel, paceColor): (String, Color) = {
            if nowDec < 6 { return ("開始前", Color.duoSubtitle) }
            if activityScore >= 100 { return ("達成！", Color.duoGreen) }
            if paceDiff >= 0 { return ("順調", Color.duoGreen) }
            if paceDiff >= -15 { return ("やや遅れ", Color(hex: "#FF9600")) }
            return ("遅れ気味", Color(hex: "#FF4B4B"))
        }()

        return Button { selectedTab = MainMenuTab.goal.rawValue } label: {
            VStack(alignment: .leading, spacing: 8) {
                // ─── ヘッダー ───
                HStack(spacing: 6) {
                    Text("FIT")
                        .font(.system(size: 8 * UIScale.font, weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color(hex: "#FF9600"))
                        .cornerRadius(4)
                    Spacer()
                    HStack(spacing: 2) {
                        Text("🔥").font(.system(size: 11 * UIScale.font))
                        Text("\(Int(healthKit.todayTotalCalories)) kcal")
                            .font(.system(size: 9 * UIScale.font, weight: .bold))
                            .foregroundColor(Color.duoDark)
                    }
                    if activeCount > 0 {
                        Text("\(activityScore)%")
                            .font(.system(size: 9 * UIScale.font, weight: .black, design: .rounded))
                            .foregroundColor(paceColor)
                        Text(paceLabel)
                            .font(.system(size: 9 * UIScale.font, weight: .bold))
                            .foregroundColor(paceColor)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(paceColor.opacity(0.12))
                            .cornerRadius(6)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color.duoSubtitle)
                }

                Divider()

                // ─── リング＋実績 ───
                HStack(spacing: 10) {
                    // ─── アクティビティリング ───
                    ZStack {
                        ActivityRingView(progress: moveP,     color: moveColor,     diameter: 62, lineWidth: 8)
                        ActivityRingView(progress: exerciseP, color: exerciseColor, diameter: 45, lineWidth: 8)
                        ActivityRingView(progress: standP,    color: standColor,    diameter: 28, lineWidth: 8)
                    }
                    .frame(width: 62, height: 62)

                    // ─── ムーブ・エクサ・スタンド ───
                    VStack(alignment: .leading, spacing: 5) {
                        fitMetricRow(color: moveColor,     label: "ムーブ",  value: "\(Int(healthKit.activityMoveCalories))",  unit: "kcal")
                        fitMetricRow(color: exerciseColor, label: "エクサ",  value: "\(healthKit.activityExerciseMinutes)",     unit: "分")
                        fitMetricRow(color: standColor,    label: "スタンド", value: "\(healthKit.activityStandHours)",          unit: "h")
                    }

                    Divider().frame(height: 54)

                    // ─── 体重・体脂肪 / セット・歩数 ───
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 10) {
                            if healthKit.latestBodyMass > 0 {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(String(format: "%.1fkg", healthKit.latestBodyMass))
                                        .font(.system(size: 11 * UIScale.font, weight: .black, design: .rounded))
                                        .foregroundColor(Color.duoDark)
                                    if let ch = healthKit.weeklyBodyMassChange {
                                        Text(String(format: "%+.1f/週", ch))
                                            .font(.system(size: 8 * UIScale.font, weight: .semibold))
                                            .foregroundColor(ch > 0.05 ? Color(hex: "#FF4B4B") : ch < -0.05 ? Color.duoGreen : Color.duoSubtitle)
                                    }
                                }
                            }
                            if healthKit.latestBodyFatPercentage > 0 {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(String(format: "%.1f%%", healthKit.latestBodyFatPercentage))
                                        .font(.system(size: 11 * UIScale.font, weight: .black, design: .rounded))
                                        .foregroundColor(Color.duoDark)
                                    if let ch = healthKit.weeklyBodyFatChange {
                                        Text(String(format: "%+.1f%%/週", ch))
                                            .font(.system(size: 8 * UIScale.font, weight: .semibold))
                                            .foregroundColor(ch > 0.05 ? Color(hex: "#FF4B4B") : ch < -0.05 ? Color.duoGreen : Color.duoSubtitle)
                                    }
                                }
                            }
                        }
                        HStack(spacing: 10) {
                            HStack(spacing: 3) {
                                Text("💪").font(.system(size: 10 * UIScale.font))
                                Text("\(todaySetCount)/\(dailySetGoal)")
                                    .font(.system(size: 11 * UIScale.font, weight: .black, design: .rounded))
                                    .foregroundColor(todaySetCount >= dailySetGoal ? Color.duoGreen : Color.duoDark)
                                Text("set")
                                    .font(.system(size: 8 * UIScale.font))
                                    .foregroundColor(Color.duoSubtitle)
                            }
                            HStack(spacing: 3) {
                                Text("👟").font(.system(size: 10 * UIScale.font))
                                Text(formatSteps(healthKit.todaySteps))
                                    .font(.system(size: 11 * UIScale.font, weight: .black, design: .rounded))
                                    .foregroundColor(Color.duoDark)
                                if healthKit.todaySteps < 1000 {
                                    Text("歩")
                                        .font(.system(size: 8 * UIScale.font))
                                        .foregroundColor(Color.duoSubtitle)
                                }
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
            .padding(12)
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func formatSteps(_ steps: Int) -> String {
        guard steps > 0 else { return "—" }
        if steps >= 1000 {
            return String(format: "%.1fk", Double(steps) / 1000.0)
        }
        return "\(steps)"
    }

    private func fitMetricRow(color: Color, label: String, value: String, unit: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(value)
                .font(.system(size: 10 * UIScale.font, weight: .black, design: .rounded))
                .foregroundColor(Color.duoDark)
            Text(unit)
                .font(.system(size: 8 * UIScale.font))
                .foregroundColor(Color.duoSubtitle)
        }
    }

    // MARK: - ポイントカード
    private var pointsCard: some View {
        Button { showPointsDetail = true } label: {
            VStack(alignment: .leading, spacing: 12) {
                // ヘッダー
                HStack(spacing: 5) {
                    Image(systemName: "star.fill")
                        .foregroundColor(Color.duoGold)
                    Text("ポイント")
                        .fontWeight(.black)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(Color.duoSubtitle)
                }
                .font(.caption)
                .foregroundColor(Color.duoDark)

                // ポイント表示（横一線に並べる）
                HStack(spacing: 0) {
                    // 今日のポイント
                    VStack(alignment: .leading, spacing: 3) {
                        Text("今日")
                            .font(.caption2)
                            .foregroundColor(Color.duoSubtitle)
                        HStack(alignment: .bottom, spacing: 2) {
                            Text("\(totalXP)")
                                .font(.system(size: 22 * UIScale.font, weight: .black, design: .rounded))
                                .foregroundColor(Color.duoGreen)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text("XP")
                                .font(.system(size: 8 * UIScale.font, weight: .bold))
                                .foregroundColor(Color.duoSubtitle)
                                .padding(.bottom, 3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider().frame(height: 28)

                    // 今週のポイント（月〜日）
                    VStack(alignment: .leading, spacing: 3) {
                        Text("今週")
                            .font(.caption2)
                            .foregroundColor(Color.duoSubtitle)
                        HStack(alignment: .bottom, spacing: 2) {
                            Text("\(weeklyXP)")
                                .font(.system(size: 22 * UIScale.font, weight: .black, design: .rounded))
                                .foregroundColor(Color.duoBlue)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text("XP")
                                .font(.system(size: 8 * UIScale.font, weight: .bold))
                                .foregroundColor(Color.duoSubtitle)
                                .padding(.bottom, 3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 10)

                    Divider().frame(height: 28)

                    // 総ポイント
                    VStack(alignment: .leading, spacing: 3) {
                        Text("総ポイント")
                            .font(.caption2)
                            .foregroundColor(Color.duoSubtitle)
                        HStack(alignment: .bottom, spacing: 2) {
                            Text("\(authManager.userProfile?.totalPoints ?? 0)")
                                .font(.system(size: 22 * UIScale.font, weight: .black, design: .rounded))
                                .foregroundColor(Color.duoOrange)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text("XP")
                                .font(.system(size: 8 * UIScale.font, weight: .bold))
                                .foregroundColor(Color.duoSubtitle)
                                .padding(.bottom, 3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 10)
                }
            }
            .padding(12)
            .background(Color(.systemBackground))
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
                    .font(.system(size: 10 * UIScale.font))
                    .foregroundColor(iconColor)
                Text(label)
                    .font(.system(size: 10 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoDark)
                Spacer()
                // 目標がある場合は％を表示
                if let _ = goal {
                    VStack(spacing: 0) {
                        Text("\(percent)%")
                            .font(.system(size: 9 * UIScale.font, weight: .bold))
                            .foregroundColor(displayColor)
                        if isOver && isReverse {
                            Text("過剰")
                                .font(.system(size: 7 * UIScale.font, weight: .bold))
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
                    .font(.system(size: 16 * UIScale.font, weight: .black, design: .rounded))
                    .foregroundColor((isOver && isReverse) ? Color.red : (isGood ? Color.duoGreen : Color.duoDark))
                Text(unit)
                    .font(.system(size: 9 * UIScale.font))
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
                .font(.system(size: 16 * UIScale.font))
                .foregroundColor(iconColor)

            // ラベル
            Text(label)
                .font(.system(size: 8 * UIScale.font, weight: .bold))
                .foregroundColor(Color.duoDark)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            // 値表示
            VStack(spacing: 1) {
                Text(value > 0 ? formatValue(value) : "—")
                    .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                    .foregroundColor((isOver && isReverse) ? Color.red : (isGood ? Color.duoGreen : Color.duoDark))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(unit)
                    .font(.system(size: 7 * UIScale.font))
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
                    .font(.system(size: 7 * UIScale.font, weight: .bold))
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
                .font(.system(size: 22 * UIScale.font))
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
                    .font(.system(size: 10 * UIScale.font))
                    .foregroundColor(Color.duoBlue)
                Text("体重・体脂肪")
                    .font(.system(size: 10 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoDark)
            }

            HStack(spacing: 8) {
                // 体重
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .bottom, spacing: 2) {
                        Text(healthKit.latestBodyMass > 0 ? String(format: "%.1f", healthKit.latestBodyMass) : "—")
                            .font(.system(size: 16 * UIScale.font, weight: .black, design: .rounded))
                            .foregroundColor(healthKit.latestBodyMass > 0 ? Color.duoGreen : Color.duoDark)
                        Text("kg")
                            .font(.system(size: 9 * UIScale.font))
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
                            .font(.system(size: 16 * UIScale.font, weight: .black, design: .rounded))
                            .foregroundColor(healthKit.latestBodyFatPercentage > 0 ? Color.duoGreen : Color.duoDark)
                        Text("%")
                            .font(.system(size: 9 * UIScale.font))
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

    // MARK: - 今日の消費カロリーカード
    private var totalCaloriesCard: some View {
        let total    = healthKit.todayTotalCalories
        let resting  = healthKit.todayRestingCalories
        let active   = healthKit.todayActiveCalories
        let restFrac = total > 0 ? min(resting / total, 1.0) : 0.0
        let actFrac  = total > 0 ? min(active  / total, 1.0) : 0.0
        let darkGreen  = Color(red: 0.10, green: 0.52, blue: 0.10)
        let brightGreen = Color(red: 0.35, green: 0.85, blue: 0.25)

        return VStack(alignment: .leading, spacing: 8) {
            // ヘッダー + 合計値
            HStack(alignment: .bottom) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12 * UIScale.font))
                        .foregroundColor(darkGreen)
                    Text("今日の消費カロリー")
                        .font(.system(size: 12 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoDark)
                }
                Spacer()
                HStack(alignment: .bottom, spacing: 3) {
                    Text(total > 0 ? "\(Int(total))" : "—")
                        .font(.system(size: 22 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor(darkGreen)
                    Text("kcal")
                        .font(.system(size: 10 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)
                        .padding(.bottom, 3)
                }
            }

            // 積み上げバー
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5)).frame(height: 8)
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(darkGreen)
                            .frame(width: geo.size.width * CGFloat(restFrac), height: 8)
                        Rectangle()
                            .fill(brightGreen)
                            .frame(width: geo.size.width * CGFloat(actFrac), height: 8)
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: 8)

            // 凡例
            HStack(spacing: 12) {
                legendDot(color: darkGreen,
                          label: "安静時", value: resting > 0 ? "\(Int(resting)) kcal" : "—")
                legendDot(color: brightGreen,
                          label: "活動", value: active > 0 ? "\(Int(active)) kcal" : "—")
                Spacer()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
    }

    private func legendDot(color: Color, label: String, value: String) -> some View {
        HStack(spacing: 2) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 7 * UIScale.font))
                .foregroundColor(Color.duoSubtitle)
            Text(value)
                .font(.system(size: 7 * UIScale.font, weight: .bold))
                .foregroundColor(Color.duoDark)
        }
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
            Text(arrow).font(.system(size: 8 * UIScale.font, weight: .bold)).foregroundColor(color)
            Text(delta == 0 ? "0\(unit)" : "\(fmt)\(unit)")
                .font(.system(size: 8 * UIScale.font, weight: .bold)).foregroundColor(color)
            Text("7日").font(.system(size: 7 * UIScale.font)).foregroundColor(Color.duoSubtitle)
        }
    }

    // MARK: - カロリー収支バーカード
    private var calorieBalanceBarCard: some View {
        CalorieBalanceBarCard(
            totalConsumed: healthKit.todayTotalCalories,
            intake: healthKit.todayIntakeCalories,
            latestBodyMass: healthKit.latestBodyMass,
            latestBodyFatPercentage: healthKit.latestBodyFatPercentage,
            weeklyBodyMassChange: healthKit.weeklyBodyMassChange,
            weeklyBodyFatChange: healthKit.weeklyBodyFatChange
        )
        .onTapGesture { openHealthApp(category: "ActiveEnergyBurned") }
    }

    // MARK: - 旧カロリー収支カード（削除予定）
    private var calorieBalanceCard: some View {
        let totalConsumed = healthKit.todayTotalCalories  // 安静時＋アクティブ
        let intake = healthKit.todayIntakeCalories
        let balance = intake - totalConsumed
        let isPositive = balance > 0
        let absBalance = abs(balance)

        return VStack(alignment: .leading, spacing: 6) {
            // ヘッダー
            HStack(spacing: 4) {
                Image(systemName: "equal.circle.fill")
                    .font(.system(size: 10 * UIScale.font))
                    .foregroundColor(isPositive ? Color.red : Color.duoBlue)
                Text("カロリー収支")
                    .font(.system(size: 10 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoDark)
                Spacer()
            }

            // 収支表示
            HStack(alignment: .bottom, spacing: 4) {
                Text(isPositive ? "+" : "-")
                    .font(.system(size: 18 * UIScale.font, weight: .black, design: .rounded))
                    .foregroundColor(isPositive ? Color.red : Color.duoBlue)
                Text("\(Int(absBalance))")
                    .font(.system(size: 20 * UIScale.font, weight: .black, design: .rounded))
                    .foregroundColor(isPositive ? Color.red : Color.duoBlue)
                Text("kcal")
                    .font(.system(size: 9 * UIScale.font))
                    .foregroundColor(Color.duoSubtitle)
                    .padding(.bottom, 2)
            }

            // 傾向表示
            HStack(spacing: 4) {
                if isPositive {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 10 * UIScale.font))
                        .foregroundColor(Color.red)
                    Text("太り傾向")
                        .font(.system(size: 9 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.red)
                } else if balance < 0 {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 10 * UIScale.font))
                        .foregroundColor(Color.duoBlue)
                    Text("痩せ傾向")
                        .font(.system(size: 9 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoBlue)
                } else {
                    Image(systemName: "equal.circle.fill")
                        .font(.system(size: 10 * UIScale.font))
                        .foregroundColor(Color.duoGreen)
                    Text("バランス")
                        .font(.system(size: 9 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoGreen)
                }

                Spacer()

                // 7,200kcalで約1kg換算
                if absBalance > 0 {
                    let kgPerDay = absBalance / 7200.0
                    Text("約\(String(format: "%.2f", kgPerDay))kg/日")
                        .font(.system(size: 8 * UIScale.font))
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
                    .font(.system(size: 20 * UIScale.font, weight: .black, design: .rounded))
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
                        .font(.system(size: 10 * UIScale.font))
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
                        .font(.system(size: 10 * UIScale.font))
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
                    .font(.system(size: 10 * UIScale.font)).fontWeight(.semibold)
                    .foregroundColor(Color.duoSubtitle)
            } else {
                Text("✅ 今日の測定完了！")
                    .font(.system(size: 10 * UIScale.font)).fontWeight(.semibold)
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
                    value: Double(effectiveIntakeCalories),
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
        .background(Color(.systemBackground))
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
                    .font(.system(size: 20 * UIScale.font, weight: .black, design: .rounded))
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
                                .font(.system(size: 40 * UIScale.font, weight: .black, design: .rounded))
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
                                .font(.system(size: 40 * UIScale.font, weight: .black, design: .rounded))
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
                                .font(.system(size: 40 * UIScale.font, weight: .black, design: .rounded))
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

    // MARK: - ポイント詳細シート
    private var pointsDetailSheet: some View {
        let totalPoints = authManager.userProfile?.totalPoints ?? 0

        // 種目別に集計
        struct ExerciseSummary: Identifiable {
            let id = UUID()
            let name: String
            let emoji: String
            let totalReps: Int
            let totalPoints: Int
            let count: Int
        }
        var summaryMap: [String: (emoji: String, reps: Int, pts: Int, count: Int)] = [:]
        for ex in todayExercises {
            let emoji: String = {
                let lower = ex.exerciseName.lowercased()
                if lower.contains("push") || lower.contains("プッシュ") || lower.contains("腕立て") { return "💪" }
                if lower.contains("squat") || lower.contains("スクワット") { return "🏋️" }
                if lower.contains("sit") || lower.contains("腹筋") { return "🔥" }
                if lower.contains("lunge") || lower.contains("ランジ") { return "🦵" }
                if lower.contains("plank") || lower.contains("プランク") { return "🧘" }
                return "⚡"
            }()
            let cur = summaryMap[ex.exerciseName] ?? (emoji, 0, 0, 0)
            summaryMap[ex.exerciseName] = (emoji, cur.reps + ex.reps, cur.pts + ex.points, cur.count + 1)
        }
        let summaries = summaryMap.map { name, v in
            ExerciseSummary(name: name, emoji: v.emoji, totalReps: v.reps, totalPoints: v.pts, count: v.count)
        }.sorted { $0.totalPoints > $1.totalPoints }

        // マインドフルネスXP集計
        let mindfulSamples = healthKit.todayMindfulnessSamples
        let mindfulXP = mindfulSamples.reduce(0) { total, s in
            total + (s.sessionTypeLabel == "Reflect" ? 30 : 10)
        }

        return NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // サマリーカード
                    HStack(spacing: 0) {
                        VStack(spacing: 4) {
                            Text("今日のXP")
                                .font(.caption).foregroundColor(Color.duoSubtitle)
                            Text("\(totalXP)")
                                .font(.system(size: 36 * UIScale.font, weight: .black, design: .rounded))
                                .foregroundColor(Color.duoGreen)
                            Text("XP")
                                .font(.caption2).foregroundColor(Color.duoSubtitle)
                        }
                        .frame(maxWidth: .infinity)

                        Rectangle().fill(Color(.systemGray5)).frame(width: 1, height: 60)

                        VStack(spacing: 4) {
                            Text("累計XP")
                                .font(.caption).foregroundColor(Color.duoSubtitle)
                            Text("\(totalPoints)")
                                .font(.system(size: 36 * UIScale.font, weight: .black, design: .rounded))
                                .foregroundColor(Color.duoOrange)
                            Text("XP")
                                .font(.caption2).foregroundColor(Color.duoSubtitle)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 16)
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)

                    if summaries.isEmpty && mindfulSamples.isEmpty {
                        VStack(spacing: 12) {
                            Text("💪").font(.system(size: 48 * UIScale.font))
                            Text("今日はまだトレーニングを記録していません")
                                .font(.subheadline).foregroundColor(Color.duoSubtitle)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(32)
                    } else {
                        // 種目別内訳
                        if !summaries.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("💪 トレーニング内訳")
                                    .font(.caption).fontWeight(.bold)
                                    .foregroundColor(Color.duoSubtitle)
                                    .padding(.horizontal, 4)

                                VStack(spacing: 0) {
                                    ForEach(Array(summaries.enumerated()), id: \.element.id) { idx, s in
                                        HStack(spacing: 12) {
                                            Text(s.emoji)
                                                .font(.title3)
                                                .frame(width: 36, height: 36)
                                                .background(Color.duoGreen.opacity(0.1))
                                                .clipShape(Circle())

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(s.name)
                                                    .font(.subheadline).fontWeight(.semibold)
                                                    .foregroundColor(Color.duoDark)
                                                Text("\(s.count)セット · \(s.totalReps) rep")
                                                    .font(.caption2).foregroundColor(Color.duoSubtitle)
                                            }

                                            Spacer()

                                            Text("+\(s.totalPoints) XP")
                                                .font(.system(size: 15 * UIScale.font, weight: .black, design: .rounded))
                                                .foregroundColor(Color.duoGold)
                                                .padding(.horizontal, 8).padding(.vertical, 4)
                                                .background(Color.duoYellow.opacity(0.2))
                                                .cornerRadius(8)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)

                                        if idx < summaries.count - 1 {
                                            Divider().padding(.leading, 64)
                                        }
                                    }
                                }
                                .background(Color(.systemBackground))
                                .cornerRadius(16)
                                .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
                            }
                        }

                        // マインドフルネス内訳
                        if !mindfulSamples.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("🧘 マインドフルネス内訳")
                                    .font(.caption).fontWeight(.bold)
                                    .foregroundColor(Color.duoSubtitle)
                                    .padding(.horizontal, 4)

                                VStack(spacing: 0) {
                                    ForEach(Array(mindfulSamples.enumerated()), id: \.element.id) { idx, s in
                                        let isReflect = s.sessionTypeLabel == "Reflect"
                                        let xp = isReflect ? 30 : 10
                                        let label = isReflect ? "3分ストレッチ" : "1分瞑想"
                                        HStack(spacing: 12) {
                                            Text(s.sessionEmoji)
                                                .font(.title3)
                                                .frame(width: 36, height: 36)
                                                .background(Color.duoPurple.opacity(0.1))
                                                .clipShape(Circle())

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(label)
                                                    .font(.subheadline).fontWeight(.semibold)
                                                    .foregroundColor(Color.duoDark)
                                                HStack(spacing: 6) {
                                                    Text(String(format: "%.0f分", s.durationMinutes))
                                                        .font(.caption2).foregroundColor(Color.duoPurple)
                                                    if s.averageHeartRate > 0 {
                                                        Text("❤️ \(Int(s.averageHeartRate))")
                                                            .font(.caption2).foregroundColor(Color.duoSubtitle)
                                                    }
                                                    if s.averageHRV > 0 {
                                                        Text("💙 \(Int(s.averageHRV))")
                                                            .font(.caption2).foregroundColor(Color.duoSubtitle)
                                                    }
                                                }
                                            }

                                            Spacer()

                                            Text("+\(xp) XP")
                                                .font(.system(size: 15 * UIScale.font, weight: .black, design: .rounded))
                                                .foregroundColor(Color(hex: "#FDCB6E"))
                                                .padding(.horizontal, 8).padding(.vertical, 4)
                                                .background(Color(hex: "#FDCB6E").opacity(0.15))
                                                .cornerRadius(8)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)

                                        if idx < mindfulSamples.count - 1 {
                                            Divider().padding(.leading, 64)
                                        }
                                    }
                                }
                                .background(Color(.systemBackground))
                                .cornerRadius(16)
                                .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
                            }
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding(20)
            }
            .background(Color.duoBg.ignoresSafeArea())
            .navigationTitle("⭐ ポイント詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { showPointsDetail = false }
                        .foregroundColor(Color.duoGreen).fontWeight(.bold)
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
                                .font(.system(size: 56 * UIScale.font, weight: .black, design: .rounded))
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
        .background(Color(.systemBackground))
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
        .background(Color(.systemBackground))
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

    // MARK: - MINDヘルスカード（calorieAndWeightCard内で使用）
    private var mindHealthCard: some View {
        let avgHRV = healthKit.todayAvgHRV > 0 ? healthKit.todayAvgHRV : healthKit.latestHRV
        let avgHR  = healthKit.todayAvgHeartRate > 0 ? healthKit.todayAvgHeartRate : healthKit.latestHeartRate
        let stress = dashboardStressInfo(avgHRV)

        let mindMinutesText: String = {
            let m = healthKit.todayMindfulnessMinutes
            if m <= 0 { return "—" }
            if m < 1  { return "\(Int((m * 60).rounded()))秒" }
            return "\(Int(m.rounded()))分"
        }()
        let daylightText = healthKit.todayDaylightMinutes > 0
            ? "\(Int(healthKit.todayDaylightMinutes))分" : "—"

        let sleepHoursText: String = {
            let h = healthKit.lastNightTotalHours
            guard h > 0 else { return "" }
            return String(format: "%.1f", h) + "h"
        }()
        let sleepScoreColor: Color = {
            guard let s = sleepScore, s.score > 0 else { return Color.duoSubtitle }
            switch s.score {
            case 90...100: return Color(hex: "#1CB0F6")
            case 80..<90:  return Color.duoGreen
            case 70..<80:  return Color(hex: "#FF9600")
            default:       return Color(hex: "#FF4B4B")
            }
        }()

        return Button {
            selectedTab = MainMenuTab.mind.rawValue
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // ヘッダー行: 左にMINDラベル、右に睡眠情報
                HStack(spacing: 4) {
                    Text("MIND")
                        .font(.system(size: 8 * UIScale.font, weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.duoPurple)
                        .cornerRadius(4)
                    Spacer()
                    // 睡眠時間・スコア・状況
                    if !sleepHoursText.isEmpty || (sleepScore?.score ?? 0) > 0 {
                        HStack(spacing: 5) {
                            if !sleepHoursText.isEmpty {
                                Text("睡眠時間")
                                    .font(.system(size: 9 * UIScale.font, weight: .bold))
                                    .foregroundColor(Color.duoSubtitle)
                                Text(sleepHoursText)
                                    .font(.system(size: 11 * UIScale.font, weight: .bold))
                                    .foregroundColor(Color(hex: "#CE82FF"))
                            }
                            if let s = sleepScore, s.score > 0 {
                                Text("\(s.score)")
                                    .font(.system(size: 11 * UIScale.font, weight: .black))
                                    .foregroundColor(sleepScoreColor)
                                Text(s.rating)
                                    .font(.system(size: 10 * UIScale.font, weight: .bold))
                                    .foregroundColor(sleepScoreColor)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(sleepScoreColor.opacity(0.15))
                                    .cornerRadius(8)
                            }
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoSubtitle.opacity(0.5))
                }

                // 本体: 睡眠リング（左・二段に渡る）+ 右側二段
                HStack(alignment: .top, spacing: 8) {
                    if let s = sleepScore, s.score > 0 {
                        SleepScoreRingView(sleep: s, size: 48)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        // 中段: 平均心拍 / 平均HRV / ストレス
                        HStack(alignment: .center, spacing: 7) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("平均心拍")
                                    .font(.system(size: 8 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                                HStack(alignment: .bottom, spacing: 2) {
                                    Text(avgHR > 0 ? "\(Int(avgHR))" : "—")
                                        .font(.system(size: 15 * UIScale.font, weight: .black))
                                        .foregroundColor(Color(red: 1.0, green: 0.294, blue: 0.294))
                                    Text("bpm")
                                        .font(.system(size: 9 * UIScale.font)).foregroundColor(Color.duoSubtitle).padding(.bottom, 1)
                                }
                            }
                            Divider().frame(height: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("平均HRV")
                                    .font(.system(size: 8 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                                HStack(alignment: .bottom, spacing: 2) {
                                    Text(avgHRV > 0 ? "\(Int(avgHRV))" : "—")
                                        .font(.system(size: 15 * UIScale.font, weight: .black))
                                        .foregroundColor(Color(hex: "#1CB0F6"))
                                    Text("ms")
                                        .font(.system(size: 9 * UIScale.font)).foregroundColor(Color.duoSubtitle).padding(.bottom, 1)
                                }
                            }
                            Divider().frame(height: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("ストレス")
                                    .font(.system(size: 8 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                                Text(stress.score >= 0 ? stress.label : "—")
                                    .font(.system(size: 13 * UIScale.font, weight: .black))
                                    .foregroundColor(stress.score >= 0 ? stress.color : Color.duoSubtitle)
                            }
                            Spacer()
                        }

                        Divider()

                        // 下段: マインドフル回数・分数・日光下時間
                        HStack(spacing: 14) {
                            HStack(spacing: 3) {
                                Text("🧘").font(.system(size: 12 * UIScale.font))
                                Text(healthKit.todayMindfulnessSessions > 0 ? "\(healthKit.todayMindfulnessSessions)回" : "—")
                                    .font(.system(size: 11 * UIScale.font, weight: .bold))
                                    .foregroundColor(Color(hex: "#CE82FF"))
                            }
                            HStack(spacing: 3) {
                                Text("⏱").font(.system(size: 12 * UIScale.font))
                                Text(mindMinutesText)
                                    .font(.system(size: 11 * UIScale.font, weight: .bold))
                                    .foregroundColor(Color(hex: "#1CB0F6"))
                            }
                            HStack(spacing: 3) {
                                Text("☀️").font(.system(size: 12 * UIScale.font))
                                Text(daylightText)
                                    .font(.system(size: 11 * UIScale.font, weight: .bold))
                                    .foregroundColor(Color(hex: "#FFCC00"))
                            }
                            Spacer()
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .cornerRadius(10)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func dashboardStressInfo(_ hrv: Double) -> (score: Int, label: String, color: Color) {
        guard hrv > 0 else { return (-1, "—", Color.duoSubtitle) }
        let score: Int = {
            if hrv >= 80 { return max(0, Int((1.0 - (hrv - 80.0) / 80.0) * 20.0)) }
            if hrv >= 60 { return 20 + Int((80.0 - hrv) / 20.0 * 20.0) }
            if hrv >= 40 { return 40 + Int((60.0 - hrv) / 20.0 * 20.0) }
            if hrv >= 20 { return 60 + Int((40.0 - hrv) / 20.0 * 20.0) }
            return min(100, 80 + Int((20.0 - hrv) / 20.0 * 20.0))
        }()
        switch score {
        case ..<30: return (score, "低い",  Color.duoGreen)
        case ..<55: return (score, "普通",  Color(red: 0.4, green: 0.75, blue: 0.1))
        case ..<75: return (score, "やや高", Color.duoOrange)
        default:    return (score, "高い",  Color(hex: "#FF4B4B"))
        }
    }

    // MARK: - MINDサマリーカード（スクロール内用 ※現在未使用）
    private var mindSummaryCard: some View {
        Button {
            selectedTab = MainMenuTab.mind.rawValue
        } label: {
            HStack(spacing: 0) {
                // ラベル列
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 11 * UIScale.font, weight: .black))
                            .foregroundColor(Color(hex: "#CE82FF"))
                        Text("MIND")
                            .font(.system(size: 11 * UIScale.font, weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: "#CE82FF"))
                    }
                    Text("タップで詳細を見る")
                        .font(.system(size: 8 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoSubtitle)
                }
                .frame(minWidth: 72, alignment: .leading)

                Spacer(minLength: 8)

                // 3メトリクスタイル
                HStack(spacing: 6) {
                    mindMiniTile(
                        icon: "🧘",
                        label: "回数",
                        value: healthKit.todayMindfulnessSessions > 0 ? "\(healthKit.todayMindfulnessSessions)" : "—",
                        color: Color(hex: "#CE82FF")
                    )
                    mindMiniTile(
                        icon: "⏱",
                        label: "分数",
                        value: healthKit.todayMindfulnessMinutes > 0
                            ? (healthKit.todayMindfulnessMinutes < 1
                               ? "\(Int((healthKit.todayMindfulnessMinutes * 60).rounded()))秒"
                               : "\(Int(healthKit.todayMindfulnessMinutes.rounded()))分")
                            : "—",
                        color: Color(hex: "#1CB0F6")
                    )
                    mindMiniTile(
                        icon: "☀️",
                        label: "日光下",
                        value: healthKit.todayDaylightMinutes > 0 ? "\(Int(healthKit.todayDaylightMinutes))分" : "—",
                        color: Color(hex: "#FFCC00")
                    )
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoSubtitle.opacity(0.6))
                    .padding(.leading, 6)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func mindMiniTile(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(icon).font(.system(size: 14 * UIScale.font))
            Text(value)
                .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 8 * UIScale.font, weight: .bold))
                .foregroundColor(Color.duoSubtitle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(color.opacity(0.10))
        .cornerRadius(10)
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
                            await updateTimeSlotForMeal(timestamp: Date(), calories: intakeGoals.caloriesFor(mealType: .breakfast))
                            await refreshIntakeData()
                        }
                    }
                }
                quickIntakeButton(emoji: "🍱", label: "昼食") {
                    confirmIntake(message: "昼食 \(intakeGoals.caloriesFor(mealType: .lunch))kcal を記録しますか？") {
                        Task {
                            await authManager.recordMeal(mealType: .lunch)
                            await updateTimeSlotForMeal(timestamp: Date(), calories: intakeGoals.caloriesFor(mealType: .lunch))
                            await refreshIntakeData()
                        }
                    }
                }
                quickIntakeButton(emoji: "🍽️", label: "夕食") {
                    confirmIntake(message: "夕食 \(intakeGoals.caloriesFor(mealType: .dinner))kcal を記録しますか？") {
                        Task {
                            await authManager.recordMeal(mealType: .dinner)
                            await updateTimeSlotForMeal(timestamp: Date(), calories: intakeGoals.caloriesFor(mealType: .dinner))
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
                            await updateTimeSlotForMeal(timestamp: Date(), calories: intakeGoals.caloriesFor(mealType: .snack))
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
                                await updateTimeSlotForDrink(timestamp: Date(), ml: intakeGoals.waterPerCup)
                                await refreshIntakeData()
                            }
                        }
                    } label: { Label("💧 水", systemImage: "") }
                    Button {
                        confirmIntake(message: "コーヒー \(intakeGoals.coffeePerCup)ml (カフェイン \(intakeGoals.caffeinePerCup)mg) を記録しますか？") {
                            Task {
                                await authManager.recordCoffee()
                                await updateTimeSlotForDrink(timestamp: Date(), ml: intakeGoals.coffeePerCup)
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
                                await updateTimeSlotForDrink(timestamp: Date(), ml: AlcoholType.beer.amountMl)
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
                                await updateTimeSlotForDrink(timestamp: Date(), ml: AlcoholType.wine.amountMl)
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
                                await updateTimeSlotForDrink(timestamp: Date(), ml: AlcoholType.chuhai.amountMl)
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
                                await updateTimeSlotForDrink(timestamp: Date(), ml: 350)
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
        .background(Color(.systemBackground))
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

    private func timeString(_ date: Date) -> String { DashboardView.hhmm.string(from: date) }
    private func formatDate(_ date: Date) -> String { DashboardView.mdE.string(from: date) }
    private func formatHeaderDate(_ date: Date) -> String { DashboardView.slashMdE.string(from: date) }

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
                            value: healthKit.todaySteps > 0 ? "\(healthKit.todaySteps)" : "0",
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
        .background(Color(.systemBackground))
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
                    await healthKit.fetchDashboardHealth()
                }
            }
        }
        .onAppear {
            // 画面表示時にも再取得（最新データ確保）
            if healthKit.isAvailable && healthKit.isAuthorized {
                Task {
                    await healthKit.fetchDashboardHealth()
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
                    .font(.system(size: 9 * UIScale.font)).fontWeight(.bold)
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

    // MARK: - PFCバランス円グラフ
    private func pfcBalanceChart(_ analysis: PFCBalanceAnalysis) -> some View {
        let totalCalories = Int(healthKit.todayIntakeCalories)

        return VStack(alignment: .leading, spacing: 8) {
            // ヘッダー
            HStack {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 12 * UIScale.font))
                    .foregroundColor(Color.duoGreen)
                Text("PFCバランス")
                    .font(.system(size: 12 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoDark)
                Spacer()
                // 総摂取カロリー
                HStack(spacing: 2) {
                    Text("\(totalCalories)")
                        .font(.system(size: 13 * UIScale.font, weight: .black))
                        .foregroundColor(Color.duoOrange)
                    Text("kcal")
                        .font(.system(size: 9 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.duoOrange.opacity(0.1))
                .cornerRadius(10)

                Text(analysis.rating)
                    .font(.system(size: 11 * UIScale.font, weight: .bold))
                    .foregroundColor(scoreColorForPFC(analysis.score))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(scoreColorForPFC(analysis.score).opacity(0.15))
                    .cornerRadius(10)
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
                            .font(.system(size: 22 * UIScale.font, weight: .black))
                            .foregroundColor(scoreColorForPFC(analysis.score))
                        Text("点")
                            .font(.system(size: 9 * UIScale.font))
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
                .font(.system(size: 9 * UIScale.font))
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
                .font(.system(size: 11 * UIScale.font, weight: .bold))
                .foregroundColor(Color.duoDark)
            Text(name)
                .font(.system(size: 9 * UIScale.font))
                .foregroundColor(Color.duoSubtitle)
            Spacer()
            Text(String(format: "%.0f%%", percent))
                .font(.system(size: 11 * UIScale.font, weight: .bold))
                .foregroundColor(color)
            Text(String(format: "%.0fg", grams))
                .font(.system(size: 9 * UIScale.font))
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
                            Text(label).font(.system(size: 9 * UIScale.font)).foregroundColor(Color.duoSubtitle)
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
            VStack(alignment: .leading, spacing: 6) {
                // ヘッダー
                HStack(spacing: 4) {
                    Image(systemName: "bed.double.fill")
                        .font(.system(size: 12 * UIScale.font))
                        .foregroundColor(Color(red: 0.451, green: 0.369, blue: 0.937))
                    Text("睡眠スコア")
                        .font(.system(size: 12 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoDark)
                    Spacer()
                    if let sleep = sleepScore, sleep.score > 0 {
                        HStack(spacing: 4) {
                            Text("\(sleep.score)")
                                .font(.system(size: 14 * UIScale.font, weight: .black, design: .rounded))
                                .foregroundColor(sleepScoreColor(sleep.score))
                            Text(sleep.rating)
                                .font(.system(size: 11 * UIScale.font, weight: .bold))
                                .foregroundColor(sleepScoreColor(sleep.score))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(sleepScoreColor(sleep.score).opacity(0.15))
                                .cornerRadius(10)
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)
                }

                if let sleep = sleepScore, sleep.score > 0 {
                    HStack(alignment: .center, spacing: 8) {
                        SleepScoreRingView(sleep: sleep)
                        VStack(alignment: .leading, spacing: 4) {
                            sleepBulletRow(
                                color: Color(red: 0.44, green: 0.52, blue: 0.90),
                                label: "睡眠時間",
                                value: "\(sleep.durationScore)/50",
                                note: String(format: "%.1fh/%.0fh", sleep.totalHours, sleep.targetHours)
                            )
                            sleepBulletRow(
                                color: Color(red: 0.22, green: 0.80, blue: 0.72),
                                label: "就寝時刻",
                                value: "\(sleep.bedtimeScore)/30",
                                note: {
                                    if let t = sleep.firstSleepTime {
                                        return DashboardView.hm.string(from: t)
                                    }
                                    return "—"
                                }()
                            )
                            sleepBulletRow(
                                color: Color(red: 0.95, green: 0.48, blue: 0.40),
                                label: "睡眠中断",
                                value: "\(sleep.interruptionScore)/20",
                                note: sleep.awakeHours < 0.1 ? "なし" : String(format: "%.0f分", sleep.awakeHours * 60)
                            )
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                    HStack(alignment: .bottom, spacing: 2) {
                        Text(healthKit.lastNightTotalHours > 0 ? String(format: "%.1f", healthKit.lastNightTotalHours) : "—")
                            .font(.system(size: 19 * UIScale.font, weight: .black))
                            .foregroundColor(healthKit.lastNightTotalHours >= 7.0 ? Color.duoGreen : Color.duoOrange)
                        Text("h")
                            .font(.system(size: 9 * UIScale.font))
                            .foregroundColor(Color.duoSubtitle)
                            .padding(.bottom, 1)
                        Spacer()
                    }
                }

            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.duoBg)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private func sleepBulletRow(color: Color, label: String, value: String, note: String = "") -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Group {
                if note.isEmpty {
                    Text("\(label): \(value)")
                        .font(.system(size: 11 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color.duoDark)
                } else {
                    Text("\(label): \(value) ")
                        .font(.system(size: 11 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color.duoDark)
                    + Text("(\(note))")
                        .font(.system(size: 9 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)
                }
            }
        }
    }

    // MARK: - 心拍数 + 心拍変動 + ストレス推定 複合タイル
    private var heartRateWithHRVItem: some View {
        HeartRateHRVItem(
            latestHeartRate: healthKit.latestHeartRate,
            latestHRV: healthKit.latestHRV,
            avgHeartRate: healthKit.todayAvgHeartRate,
            avgHRV: healthKit.todayAvgHRV
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
                        .font(.system(size: 10 * UIScale.font))
                        .foregroundColor(Color(red: 0.451, green: 0.369, blue: 0.937))
                    Text("睡眠スコア")
                        .font(.system(size: 10 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoDark)
                    Spacer()
                }

                // スコアと評価
                HStack(alignment: .bottom, spacing: 4) {
                    Text("\(analysis.score)")
                        .font(.system(size: 22 * UIScale.font, weight: .black))
                        .foregroundColor(sleepScoreColor(analysis.score))
                    Text("点")
                        .font(.system(size: 10 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)
                        .padding(.bottom, 2)
                    Spacer()
                }

                Text(analysis.rating)
                    .font(.system(size: 9 * UIScale.font, weight: .bold))
                    .foregroundColor(sleepScoreColor(analysis.score))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(sleepScoreColor(analysis.score).opacity(0.15))
                    .cornerRadius(4)

                // 睡眠時間の詳細
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("総時間:")
                            .font(.system(size: 8 * UIScale.font))
                            .foregroundColor(Color.duoSubtitle)
                        Text(String(format: "%.1fh", analysis.totalHours))
                            .font(.system(size: 8 * UIScale.font, weight: .bold))
                            .foregroundColor(Color.duoDark)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color(red: 0.109, green: 0.753, blue: 0.965)).frame(width: 6, height: 6)
                        Text("深い: \(String(format: "%.1fh", analysis.deepHours))")
                            .font(.system(size: 8 * UIScale.font))
                            .foregroundColor(Color.duoSubtitle)
                        Circle().fill(Color(red: 0.808, green: 0.510, blue: 1.0)).frame(width: 6, height: 6)
                        Text("REM: \(String(format: "%.1fh", analysis.remHours))")
                            .font(.system(size: 8 * UIScale.font))
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

    // MARK: - 睡眠スコア 三分割リング

    private struct SleepScoreRingView: View {
        let sleep: SleepScoreAnalysis
        var size: CGFloat = 52

        private var lw: CGFloat { size * 0.11 }
        private let gap: Double = 0.018

        private let durColor  = Color(red: 0.44, green: 0.52, blue: 0.90)
        private let bedColor  = Color(red: 0.22, green: 0.80, blue: 0.72)
        private let intrColor = Color(red: 0.95, green: 0.48, blue: 0.40)

        private var durExtent: Double  { 0.50 - gap }
        private var bedExtent: Double  { 0.30 - gap }
        private var intrExtent: Double { 0.20 - gap }

        private var dRatio: Double { min(Double(sleep.durationScore)     / 50.0, 1.0) }
        private var bRatio: Double { min(Double(sleep.bedtimeScore)      / 30.0, 1.0) }
        private var iRatio: Double { min(Double(sleep.interruptionScore) / 20.0, 1.0) }

        private var scoreColor: Color {
            switch sleep.score {
            case 90...100: return Color(red: 0.27, green: 0.76, blue: 0.20)
            case 80..<90:  return Color(red: 0.27, green: 0.76, blue: 0.20)
            case 70..<80:  return Color(red: 0.45, green: 0.37, blue: 0.94)
            case 50..<70:  return Color(red: 1.00, green: 0.60, blue: 0.00)
            default:       return Color(red: 0.95, green: 0.25, blue: 0.25)
            }
        }

        var body: some View {
            ZStack {
                ZStack {
                    Circle().trim(from: 0.0, to: durExtent)
                        .stroke(durColor.opacity(0.18), style: StrokeStyle(lineWidth: lw, lineCap: .butt))
                    if dRatio > 0.001 {
                        Circle().trim(from: 0.0, to: durExtent * dRatio)
                            .stroke(durColor, style: StrokeStyle(lineWidth: lw, lineCap: .round))
                    }
                    Circle().trim(from: 0.50, to: 0.50 + bedExtent)
                        .stroke(bedColor.opacity(0.18), style: StrokeStyle(lineWidth: lw, lineCap: .butt))
                    if bRatio > 0.001 {
                        Circle().trim(from: 0.50, to: 0.50 + bedExtent * bRatio)
                            .stroke(bedColor, style: StrokeStyle(lineWidth: lw, lineCap: .round))
                    }
                    Circle().trim(from: 0.80, to: 0.80 + intrExtent)
                        .stroke(intrColor.opacity(0.18), style: StrokeStyle(lineWidth: lw, lineCap: .butt))
                    if iRatio > 0.001 {
                        Circle().trim(from: 0.80, to: 0.80 + intrExtent * iRatio)
                            .stroke(intrColor, style: StrokeStyle(lineWidth: lw, lineCap: .round))
                    }
                }
                .rotationEffect(.degrees(-30))

                // 中央スコア
                Text("\(sleep.score)")
                    .font(.system(size: size * 0.30, weight: .black, design: .rounded))
                    .foregroundColor(scoreColor)
            }
            .frame(width: size, height: size)
        }
    }

    private func sleepScoreBreakdownRow(icon: String, label: String, detail: String, pts: Int, maxPts: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8 * UIScale.font))
                .foregroundColor(Color.duoSubtitle)
                .frame(width: 10)
            Text(label)
                .font(.system(size: 9 * UIScale.font))
                .foregroundColor(Color.duoSubtitle)
            Text(detail)
                .font(.system(size: 9 * UIScale.font, weight: .semibold))
                .foregroundColor(Color.duoDark)
            Spacer()
            Text("\(pts)/\(maxPts)点")
                .font(.system(size: 9 * UIScale.font, weight: .bold))
                .foregroundColor(pts >= maxPts ? Color.duoGreen : Color.duoSubtitle)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(Color.gray.opacity(0.06))
        .cornerRadius(6)
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

    private func loadTodayWeekdayGoal() {
        // 毎日の設定を読み込む
        if let data = UserDefaults.standard.data(forKey: "dailyFixedGoals_v1"),
           let saved = try? JSONDecoder().decode(DailyFixedGoals.self, from: data) {
            dailyFixedGoals = saved
        }
        // 曜日毎の目標を読み込む
        guard let data = UserDefaults.standard.data(forKey: "weekdayGoals_v1"),
              let goals = try? JSONDecoder().decode([WeekdayGoal].self, from: data) else {
            todayWeekdayGoal = nil
            return
        }
        let weekday = Calendar.current.component(.weekday, from: Date())
        let mapped = weekday == 1 ? 7 : weekday - 1  // Calendar: 1=Sun,2=Mon→ 1=月,...,7=日
        todayWeekdayGoal = goals.first(where: { $0.weekday == mapped && $0.hasAnyGoal })
    }

    private func refreshFromHealthKit() async {
        guard authManager.isSignedIn else { return }

        // HealthKitを強制再同期（TTLバイパス）
        if healthKit.isAvailable && healthKit.isAuthorized {
            await healthKit.fetchAll(force: true)
            pfcAnalysis = healthKit.analyzePFCBalance()
            sleepScore  = healthKit.analyzeSleepScore(
                targetHours: Double(dailyFixedGoals.sleepHoursGoal)
            )
        }

        // 時間帯別の実績を再読み込み（HealthKit同期付き）
        await timeSlotManager.loadTodayProgress(syncHealthKit: true)

        // Firestoreからも最新の摂取・運動データを取得
        async let freshEx     = authManager.getTodayExercises()
        async let freshIntake = authManager.getTodayIntakeSummary()
        let (ex, intake) = await (freshEx, freshIntake)

        todayExercises = ex
        var mergedIntake = intake
        if healthKit.isAvailable && healthKit.isAuthorized {
            mergedIntake.totalCalories   = max(Int(healthKit.todayIntakeCalories), intake.totalCalories)
            mergedIntake.totalWaterMl    = max(Int(healthKit.todayIntakeWater),    intake.totalWaterMl)
            mergedIntake.totalCaffeineMg = max(Int(healthKit.todayIntakeCaffeine), intake.totalCaffeineMg)
            mergedIntake.totalAlcoholG   = max(healthKit.todayIntakeAlcohol,       intake.totalAlcoholG)
        }
        todayIntake = mergedIntake

        recomputePhotoLogTotals()
        recalcTotals()
        updateWidgetData()
    }

    private func loadData() async {
        guard authManager.isSignedIn else {
            isLoading = false
            return
        }

        // 1.5秒以内の重複呼び出しをスキップ（デバウンス）
        if let last = lastLoadDataTime, Date().timeIntervalSince(last) < 1.5 {
            return
        }
        lastLoadDataTime = Date()

        loadTodayWeekdayGoal()
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
            async let freshEx        = authManager.getTodayExercises()
            async let freshSets      = authManager.getDailySets()
            async let weeklyProgress = authManager.getWeeklySetProgress()
            async let calGoal        = authManager.getDailyCalorieGoal()
            async let setCount       = authManager.getTodaySetCount()
            async let setGoal        = authManager.getDailySetGoal()
            async let intake         = authManager.getTodayIntakeSummary()
            async let intakeSettings = authManager.getIntakeSettings()
            async let wXP            = authManager.getThisWeekXP()
            let (ex, sets, weekProg, calorie, count, goal, intakeSummary, intakeGoalSettings, fetchedWeeklyXP)
                = await (freshEx, freshSets, weeklyProgress, calGoal, setCount, setGoal, intake, intakeSettings, wXP)

            // 今日分のexercise XPを週合計から引いて「今日より前の分」を保持
            let todayExXP = ex.reduce(0) { $0 + $1.points }
            weeklyBaseXP = max(0, fetchedWeeklyXP - todayExXP)
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
                mergedIntake.totalCalories  = max(Int(healthKit.todayIntakeCalories), intakeSummary.totalCalories)
                mergedIntake.totalWaterMl   = max(Int(healthKit.todayIntakeWater),    intakeSummary.totalWaterMl)
                mergedIntake.totalCaffeineMg = max(Int(healthKit.todayIntakeCaffeine), intakeSummary.totalCaffeineMg)
                mergedIntake.totalAlcoholG  = max(healthKit.todayIntakeAlcohol,       intakeSummary.totalAlcoholG)
            }
            todayIntake = mergedIntake

            // 時間帯別の進捗を再読み込み
            await timeSlotManager.loadTodayProgress()

            // 体重履歴を取得（展開時に表示）
            if healthKit.isAvailable && healthKit.isAuthorized {
                await healthKit.fetchBodyMassHistory(days: 7)
            }

            // PFCバランス分析・睡眠スコアを最終更新（1回だけ）
            if healthKit.isAuthorized {
                pfcAnalysis = healthKit.analyzePFCBalance()
                sleepScore  = healthKit.analyzeSleepScore(
                    targetHours: Double(dailyFixedGoals.sleepHoursGoal)
                )
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

    /// 食事記録時に時間帯の進捗を更新（カロリーを加算）
    private func updateTimeSlotForMeal(timestamp: Date, calories: Int) async {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: timestamp)
        let timeSlot: TimeSlot

        if hour >= 6 && hour < 10 { timeSlot = .morning }
        else if hour >= 10 && hour < 14 { timeSlot = .noon }
        else if hour >= 14 && hour < 18 { timeSlot = .afternoon }
        else { timeSlot = .evening }

        await timeSlotManager.recordMealLog(at: timeSlot, calories: calories)
    }

    /// Mandalaノードの完了処理（ノードIDに基づいてルーティング）
    private func handleMandalaComplete(_ node: MandalaNodeData) async {
        let weekdayNum: Int = {
            let wd = Calendar.current.component(.weekday, from: Date())
            return wd == 1 ? 7 : wd - 1
        }()
        let id = node.id
        // タップ前の完了状態（トグル判定に使用）
        let wasCompleted = node.isCompleted

        if id == "wd-study" {
            await timeSlotManager.toggleCustomGoal(id: "wd_study_\(weekdayNum)")
        } else if id == "wd-noalcohol" {
            await timeSlotManager.toggleCustomGoal(id: "wd_noalcohol_\(weekdayNum)")
        } else if id.hasPrefix("wd-") {
            let uuid = String(id.dropFirst(3))
            await timeSlotManager.toggleCustomGoal(id: "wd_\(uuid)")
        } else if id.hasPrefix("daily-") {
            let uuid = String(id.dropFirst(6))
            await timeSlotManager.toggleCustomGoal(id: "daily_custom_\(uuid)")
        } else if id.hasSuffix("-meal") {
            let mealType: MealType
            let calories: Int
            switch node.slot {
            case .morning:   mealType = .breakfast; calories = 400
            case .noon:      mealType = .lunch;     calories = 600
            case .afternoon: mealType = .snack;     calories = 200
            case .evening:   mealType = .dinner;    calories = 800
            default:         mealType = .breakfast; calories = 400
            }
            await authManager.recordMeal(mealType: mealType)
            await updateTimeSlotForMeal(timestamp: Date(), calories: calories)
            await refreshIntakeData()
        } else if id.hasSuffix("-drink") {
            await authManager.recordWater()
            await updateTimeSlotForDrink(timestamp: Date(), ml: 200)
            await refreshIntakeData()
        } else if let slot = node.slot {
            let slotPrefix = "\(slot.rawValue)-"
            if id.hasPrefix(slotPrefix) {
                let activityId = String(id.dropFirst(slotPrefix.count))
                await timeSlotManager.toggleCustomActivity(id: activityId, at: slot)
            }
        }

        // --- 完了時刻をローカルログに確実記録（Firestore 反映遅延の補完）---
        let logger = MandalaCompletionLogger.shared
        if wasCompleted {
            // トグルで取り消した場合はログからも削除
            logger.remove(nodeId: node.id)
        } else {
            // 新規完了：アイコンID・時刻・スロット名を記録
            logger.record(
                nodeId: node.id,
                emoji: node.emoji,
                name: node.label,
                slot: node.slot?.rawValue
            )
        }
    }

    /// 飲み物記録時に時間帯の進捗を更新（mlを加算）
    private func updateTimeSlotForDrink(timestamp: Date, ml: Int) async {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: timestamp)
        let timeSlot: TimeSlot

        if hour >= 6 && hour < 10 { timeSlot = .morning }
        else if hour >= 10 && hour < 14 { timeSlot = .noon }
        else if hour >= 14 && hour < 18 { timeSlot = .afternoon }
        else { timeSlot = .evening }

        await timeSlotManager.recordDrinkLog(at: timeSlot, ml: ml)
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
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let lastDate = lastLoadDataTime.map { cal.startOfDay(for: $0) } ?? Date.distantPast
            if lastDate < today {
                // 日付が変わっていたら設定・進捗を完全リロード
                print("🗓 Date changed - reloading settings and progress")
                Task {
                    await timeSlotManager.loadTodaySettings()
                    await timeSlotManager.loadTodayProgress(syncHealthKit: true)
                    lastLoadDataTime = nil
                    await loadData()
                }
            } else {
                // 前回ロードから10分以上経過した場合のみ再取得（バッテリー節約）
                let isStale = lastLoadDataTime.map { Date().timeIntervalSince($0) > 600 } ?? true
                if isStale {
                    print("🔄 App became active (stale data) - refreshing HealthKit data")
                    Task { await periodicWidgetSync() }
                } else {
                    print("✅ App became active (fresh data) - skipping refresh")
                }
            }
        } else if newPhase == .background {
            print("📲 App moved to background - flushing Widget data")
            updateWidgetData()
        }
    }

    private func periodicWidgetSync() async {
        guard healthKit.isAvailable && healthKit.isAuthorized else { return }
        print("⏱ [Widget] Syncing HealthKit data...")
        await healthKit.fetchDashboardHealth()
        await timeSlotManager.loadTodayProgress(syncHealthKit: false)
        await timeSlotManager.updateGlobalProgressFromHealthKit()
        updateWidgetData()
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
               let prog = timeSlotManager.progress.progressFor(slot) {
                // 永続化されたTimeSlot進捗を使用（Firestore依存のcountSetsより正確）
                totalTrainingCompleted += prog.trainingCompleted
                totalTrainingGoal += goal.trainingGoal
                // マインドフルネスは分換算（瞑想1回=1分、ストレッチ1セット=3分）
                totalMindfulnessCompleted += prog.mindfulnessCompleted * 1 + prog.stretchSetsCompleted * 3
                totalMindfulnessGoal += goal.mindfulnessGoal

                if goal.logGoal.mealGoal > 0 {
                    totalMealGoal += goal.logGoal.mealGoal
                }
                if goal.logGoal.drinkGoal > 0 {
                    totalDrinkGoal += goal.logGoal.drinkGoal
                }
            }
        }

        totalMealLogged = effectiveMealLogged
        totalDrinkLogged = Int(healthKit.todayIntakeWater)

        sharedDefaults.set(totalTrainingCompleted, forKey: "trainingCompleted")
        sharedDefaults.set(totalTrainingGoal, forKey: "trainingGoal")
        sharedDefaults.set(totalMindfulnessCompleted, forKey: "mindfulnessCompleted")
        sharedDefaults.set(totalMindfulnessGoal, forKey: "mindfulnessGoal")
        sharedDefaults.set(totalMealLogged, forKey: "mealLogged")
        sharedDefaults.set(totalMealGoal, forKey: "mealGoal")
        sharedDefaults.set(totalDrinkLogged, forKey: "drinkLogged")
        sharedDefaults.set(totalDrinkGoal, forKey: "drinkGoal")
        sharedDefaults.set(todayCurrentProgressPercent, forKey: "progressPercent")

        // カロリー収支を計算して保存（摂取 - 消費）Apple Health方式
        let totalBurned = Int(healthKit.todayRestingCalories + healthKit.todayActiveCalories)
        let totalIntake = Int(healthKit.todayIntakeCalories)
        let calorieBalance = totalIntake - totalBurned
        sharedDefaults.set(calorieBalance, forKey: "calorieBalance")

        print("[Widget] Updated: burned=\(totalBurned), intake=\(totalIntake), balance=\(calorieBalance)")

        // 総ポイントを保存
        let totalPoints = authManager.userProfile?.totalPoints ?? 0
        sharedDefaults.set(totalPoints, forKey: "totalPoints")

        // ワークアウト・スタンド（HealthKit実績のみ保存、目標は廃止）
        sharedDefaults.set(healthKit.todayWorkoutMinutes, forKey: "workoutMinutes")
        sharedDefaults.set(0, forKey: "workoutGoal")
        sharedDefaults.set(healthKit.todayStandHours, forKey: "standHours")
        sharedDefaults.set(0, forKey: "standGoal")

        let payloadHash = [
            todaySetCount, dailySetGoal, totalReps, authManager.userProfile?.streak ?? 0,
            totalXP, totalTrainingCompleted, totalTrainingGoal, totalMindfulnessCompleted,
            totalMindfulnessGoal, totalMealLogged, totalMealGoal, totalDrinkLogged, totalDrinkGoal,
            calorieBalance, totalPoints, healthKit.todayWorkoutMinutes, healthKit.todayStandHours,
            todayCurrentProgressPercent
        ].map(String.init).joined(separator: "|")

        guard payloadHash != lastWidgetPayloadHash else {
            print("[Widget] Skipped reload - payload unchanged")
            return
        }
        lastWidgetPayloadHash = payloadHash

        print("[Widget] Synced changed data to shared UserDefaults")
        scheduleWidgetReload()
    }

    /// HealthKitプロパティが同時に複数変化しても updateWidgetData() を1回だけ呼ぶ
    /// debouncer は @StateObject のため workItem 更新は再レンダリングを起こさない
    private func scheduleWidgetDataUpdate() {
        debouncer.widgetUpdate?.cancel()
        let workItem = DispatchWorkItem { updateWidgetData() }
        debouncer.widgetUpdate = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func scheduleWidgetReload() {
        debouncer.widgetReload?.cancel()
        let workItem = DispatchWorkItem {
            WidgetCenter.shared.reloadAllTimelines()
            print("[Widget] Reloaded timelines")
        }
        debouncer.widgetReload = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    private func recalcTotals() {
        totalReps     = todayExercises.reduce(0) { $0 + $1.reps }
        let mindfulXP = healthKit.todayMindfulnessSamples.reduce(0) { total, s in
            total + (s.sessionTypeLabel == "Reflect" ? 30 : 10)
        }
        totalXP       = todayExercises.reduce(0) { $0 + $1.points } + mindfulXP
        weeklyXP      = weeklyBaseXP + totalXP
        totalCalories = Int(todayExercises.reduce(0.0) { acc, ex in
            let rate = Self.kcalPerRep[ex.exerciseId.lowercased()] ?? 0.4
            return acc + Double(ex.reps) * rate
        })

        // 1日の目標達成ボーナス（+50XP、1日1回限り）
        Task {
            if dailySetGoal > 0 && todaySetCount >= dailySetGoal {
                await authManager.checkAndAwardDailyBonus(type: "training", points: 50)
            }
            let mindGoal = TimeSlot.allCases.reduce(0) {
                $0 + (timeSlotManager.settings.goalFor($1)?.mindfulnessGoal ?? 0)
            }
            if mindGoal > 0 && healthKit.todayMindfulnessSessions >= mindGoal {
                await authManager.checkAndAwardDailyBonus(type: "mindfulness", points: 50)
            }
        }
    }

    private func openMindfulness() {
        showMindfulnessSession = true
    }

    private func openStretch() {
        showStretchSession = true
    }

    private func openStand() {
        showStandSession = true
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

    private func computeAngerLevel() -> Double {
        let currentHour = Calendar.current.component(.hour, from: Date())
        var missedSets = 0
        var totalExpectedSets = 0
        for slot in TimeSlot.allCases {
            guard slot != .midnight,
                  let goal = timeSlotManager.settings.goalFor(slot),
                  goal.trainingGoal > 0,
                  currentHour >= slot.endHour else { continue }
            totalExpectedSets += goal.trainingGoal
            missedSets += max(0, goal.trainingGoal - countSetsInTimeSlot(slot))
        }
        guard totalExpectedSets > 0 else { return 0 }
        return min(1.0, Double(missedSets) / Double(totalExpectedSets))
    }

    private func fitingoDailyGoal() -> Int {
        let timeSlotGoal = TimeSlot.allCases.reduce(0) { total, slot in
            total + (timeSlotManager.settings.goalFor(slot)?.trainingGoal ?? 0)
        }
        return max(max(dailySetGoal, timeSlotGoal), 1)
    }

    private func fitingoMessage(sessions: Int, dailyGoal: Int, isBehind: Bool) -> String {
        if sessions == 0 && !isBehind {
            return "今日のROUTINを始めよう！"
        }
        if sessions < dailyGoal {
            return "まだ全然終わってないよ！今すぐやろう！"
        }
        return "今日のROUTIN達成！よくやったね！🎉"
    }

    private var trainingVideoPlaylist: [(name: String, gifName: String)] {
        [
            ("スクワット", "fitingo_wo_squat"),
            ("腕立て", "fItingo_wo_pushups"),
            ("腹筋", "fItingo_wo_pushups"),
            ("ランジ", "fitingo_wo_range"),
            ("レッグレイズ", "fitingo_wo_legs"),
            ("バーピー", "fitingo_wo_burpee"),
            ("その他トレーニング", "fitingo_workout"),
        ]
    }

}

// MARK: - View Extensions
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

// MARK: - デイリーセットカード ボタン群（独立Viewでレンダリング境界を作り、スタックオーバーフローを防止）

private struct DailySetsCardButtonsView: View {
    let trainingVideoPlaylist: [(name: String, gifName: String)]
    let mascotBounce: Bool
    @Binding var showTrainingVideo: Bool
    @Binding var trainingVideoIndex: Int
    let onStartTracker: () -> Void
    let onOpenMindfulness: () -> Void
    let onOpenStretch: () -> Void
    let onOpenStand: () -> Void
    let onOpenPhotoLog: () -> Void
    let angerLevel: Double
    let todaySessions: Int
    let dailyGoal: Int
    let fitingoMessage: (Int, Int, Bool) -> String

    var body: some View {
        VStack(spacing: 0) {
            Divider().padding(.horizontal, 16)

            fitingoButton
            TrainingVideoButton(
                playlist: trainingVideoPlaylist,
                showTrainingVideo: $showTrainingVideo,
                trainingVideoIndex: $trainingVideoIndex
            )

            VStack(spacing: 8) {
                actionButton(icon: "🧘", title: "マインドフルネス", subtitle: "1分瞑想",
                             color: Color.duoPurple, action: onOpenMindfulness)
                actionButton(icon: "🤸", title: "マインドフルネス", subtitle: "3分ストレッチ",
                             color: Color.duoBlue, action: onOpenStretch)
                actionButton(icon: "🍅", title: "20分スタンドタイマー",
                             subtitle: "立って作業に集中（ポモドーロ）",
                             color: Color(red: 0.94, green: 0.27, blue: 0.15), action: onOpenStand)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            photoLogButton
        }
    }

    private var fitingoButton: some View {
        let isBehind = (todaySessions > 0 && todaySessions < dailyGoal) || angerLevel > 0.5
        let isAngry = isBehind || angerLevel > 0.5
        let isWarning = !isAngry && angerLevel > 0.3
        let progressDeficit = max(0.0, 1.0 - Double(todaySessions) / Double(max(dailyGoal, 1)))
        let severity = max(angerLevel, isBehind ? progressDeficit : 0)
        let bgColors: [Color] = !isBehind && todaySessions == 0
            ? [Color(hex: "#F5FFF3"), Color(hex: "#DDFBFF")]
            : severity < 0.35
            ? [Color(hex: "#E8FFB8"), Color(hex: "#6FE8D8")]
            : severity < 0.7
            ? [Color(hex: "#FFD66E"), Color(hex: "#FF9F2E")]
            : [Color(hex: "#FF7A45"), Color(hex: "#D62828")]
        let usesDarkText = (!isBehind && todaySessions == 0) || severity < 0.35
        let imageName: String = (isAngry || isWarning) ? "fitingo_fire"
            : ((!isAngry && !isWarning && (todaySessions == 0 || Calendar.current.component(.hour, from: Date()) < 12 || Double(todaySessions) / Double(max(dailyGoal, 1)) >= 0.6)) ? "fitingo_jdi" : "fitingo_button_mascot")
        let message = fitingoMessage(todaySessions, dailyGoal, isBehind)
        return FitingoStartButton(
            message: message,
            imageName: imageName,
            bgColors: bgColors,
            usesDarkText: usesDarkText,
            mascotBounce: mascotBounce,
            onTap: onStartTracker
        )
    }

    private func actionButton(icon: String, title: String, subtitle: String,
                               color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(icon)
                    .font(.system(size: 22 * UIScale.font))
                    .frame(width: 42, height: 42)
                    .background(color.opacity(0.2))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor(color)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 13 * UIScale.font, weight: .bold, design: .rounded))
                        .foregroundColor(color.opacity(0.7))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [color.opacity(0.15), color.opacity(0.08)],
                               startPoint: .leading, endPoint: .trailing)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            )
        }
        .buttonStyle(.plain)
    }

    private var photoLogButton: some View {
        Button(action: onOpenPhotoLog) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.duoOrange, Color(red: 1.0, green: 0.55, blue: 0.1)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 42, height: 42)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 18 * UIScale.font))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("フォトログ")
                        .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor(Color.duoDark)
                    Text("AI食事分析")
                        .font(.system(size: 13 * UIScale.font, weight: .bold, design: .rounded))
                        .foregroundColor(Color.duoSubtitle)
                }
                Spacer()
                Image(systemName: "chevron.right.circle.fill")
                    .font(.callout)
                    .foregroundColor(Color.duoOrange.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [Color.duoOrange.opacity(0.10), Color(red: 1.0, green: 0.55, blue: 0.1).opacity(0.06)],
                    startPoint: .leading, endPoint: .trailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

// MARK: - fitingoスタートボタン（独立Viewでレンダリング境界を作り、スタックオーバーフローを防止）

private struct FitingoStartButton: View {
    let message: String
    let imageName: String
    let bgColors: [Color]
    let usesDarkText: Bool
    let mascotBounce: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                LinearGradient(colors: bgColors, startPoint: .topLeading, endPoint: .bottomTrailing)

                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(mascotBounce ? 1.03 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                        value: mascotBounce
                    )
                    .clipped()

                LinearGradient(
                    colors: [.clear, Color.black.opacity(usesDarkText ? 0.16 : 0.36)],
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
}

// MARK: - トレーニング動画ボタン（独立Viewでレンダリング境界を作り、スタックオーバーフローを防止）

private struct TrainingVideoButton: View {
    let playlist: [(name: String, gifName: String)]
    @Binding var showTrainingVideo: Bool
    @Binding var trainingVideoIndex: Int

    private var currentVideo: (name: String, gifName: String) {
        playlist.isEmpty ? ("", "") : playlist[trainingVideoIndex % playlist.count]
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    showTrainingVideo.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9 * UIScale.font, weight: .regular))
                        .foregroundColor(Color.duoGreen)
                    Text("トレーニング動画")
                        .font(.system(size: 11 * UIScale.font, weight: .thin))
                        .foregroundColor(Color.duoSubtitle)
                    Spacer()
                    Image(systemName: showTrainingVideo ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9 * UIScale.font, weight: .light))
                        .foregroundColor(Color.duoSubtitle)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            if showTrainingVideo {
                trainingVideoExpanded
            }
        }
        .onReceive(Timer.publish(every: 5.0, on: .main, in: .common).autoconnect()) { _ in
            guard showTrainingVideo, !playlist.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                trainingVideoIndex = (trainingVideoIndex + 1) % playlist.count
            }
        }
    }

    private var trainingVideoExpanded: some View {
        let video = currentVideo
        let count = max(playlist.count, 1)
        return VStack(spacing: 6) {
            HStack {
                Text(video.name)
                    .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                    .foregroundColor(Color.duoDark)
                    .lineLimit(1)
                Spacer()
                Text("\((trainingVideoIndex % count) + 1)/\(count)")
                    .font(.system(size: 11 * UIScale.font, weight: .bold, design: .rounded))
                    .foregroundColor(Color.duoSubtitle)
            }
            .padding(.horizontal, 4)

            GeometryReader { geo in
                GIFAnimationView(gifName: video.gifName)
                    .id(video.gifName)
                    .frame(width: geo.size.width, height: geo.size.width * 9.0 / 16.0)
                    .background(Color.black.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .clipped()
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .padding(.horizontal, 8)
        .background(Color.white.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}

// MARK: - マンダラセクション（dailySetsCard からの分離によるスタック分割）
// dailySetsCard.getter 内で直接 MandalaSpiralCard を構築すると
// SwiftUI レンダリングスタックが溢れるため、独立した View struct で境界を作る。

private struct DailySetsMandalaSectionView: View {
    let mandalaNodes: [MandalaNodeData]
    @ObservedObject var timeSlotManager: TimeSlotManager
    @ObservedObject var healthKit: HealthKitManager
    @Binding var showTracker: Bool
    @Binding var showMindfulnessSession: Bool
    @Binding var showStretchSession: Bool
    @Binding var showStandSession: Bool
    @Binding var showMandalaDetail: Bool
    @Binding var selectedMandalaNode: MandalaNodeData?
    var dailyCalorieDone: Bool = false
    var dailyWaterDone: Bool = false

    var body: some View {
        MandalaSpiralCard(
            nodes: mandalaNodes,
            timeSlotManager: timeSlotManager,
            healthKit: healthKit,
            showTracker: $showTracker,
            showMindfulnessSession: $showMindfulnessSession,
            showStretchSession: $showStretchSession,
            showStandSession: $showStandSession,
            showMandalaDetail: $showMandalaDetail,
            selectedMandalaNode: $selectedMandalaNode,
            dailyCalorieDone: dailyCalorieDone,
            dailyWaterDone: dailyWaterDone
        )
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}

// MARK: - マンダラ螺旋カード（独立Viewでレンダリング境界を作り、スタックオーバーフローを防止）

private struct MandalaSpiralCard: View {
    let nodes: [MandalaNodeData]
    @ObservedObject var timeSlotManager: TimeSlotManager
    @ObservedObject var healthKit: HealthKitManager
    @Binding var showTracker: Bool
    @Binding var showMindfulnessSession: Bool
    @Binding var showStretchSession: Bool
    @Binding var showStandSession: Bool
    @Binding var showMandalaDetail: Bool
    @Binding var selectedMandalaNode: MandalaNodeData?
    var dailyCalorieDone: Bool = false
    var dailyWaterDone: Bool = false
    @AppStorage("studyBookUrl") private var studyBookUrl = "https://yonda.ktrips.net"

    private var currentHour: Int { Calendar.current.component(.hour, from: Date()) }

    private var visibleSlots: [TimeSlot] {
        let h = currentHour
        if h < 10 { return [.morning] }
        else if h < 14 { return [.morning, .noon] }
        else if h < 18 { return [.morning, .noon, .afternoon] }
        else { return [.morning, .noon, .afternoon, .evening] }
    }

    private var visibleCount: (done: Int, total: Int) {
        let set = Set(visibleSlots)
        let visible = nodes.filter { $0.slot == nil || set.contains($0.slot!) }
        return (visible.filter(\.isCompleted).count, visible.count)
    }

    private var motivationMessage: String {
        let set = Set(visibleSlots)
        let pending = nodes
            .filter { $0.slot == nil || set.contains($0.slot!) }
            .filter { !$0.isCompleted }
        if pending.isEmpty { return "🎉 全達成！" }
        if pending.count == 1 { return "\(pending[0].emoji) \(pending[0].label)" }
        let icons = pending.prefix(3).map(\.emoji).joined()
        return "\(icons) あと\(pending.count)つ"
    }

    private var motivationBadge: some View {
        Text(motivationMessage)
            .font(.system(size: 11 * UIScale.font, weight: .semibold, design: .rounded))
            .foregroundColor(Color.duoSubtitle)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.systemBackground).opacity(0.85))
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(0.06), radius: 2, y: 1)
    }

    private var activityRingsDone: Bool {
        healthKit.activityMoveCalories >= healthKit.activityMoveGoal &&
            healthKit.activityExerciseMinutes >= healthKit.activityExerciseGoal
    }

    var body: some View {
        let nc = visibleCount
        return chart
            .frame(height: 340)
            .padding(.top, 1)
            .padding(.bottom, 1)
            .overlay(alignment: .top) { legendOverlay }
            .overlay(alignment: .topLeading) {
                HStack(alignment: .top, spacing: 6) {
                    if nc.total > 0 {
                        progressBadge(done: nc.done, total: nc.total, label: "現時点")
                    }
                    motivationBadge
                }
                .padding(.leading, 10)
                .padding(.top, 34)
            }
            .overlay(alignment: .topTrailing) {
                settingsButton
                    .padding(.trailing, 4)
            }
    }

    private var chart: some View {
        MandalaChartView(
            settings: timeSlotManager.settings,
            progress: timeSlotManager.progress,
            activityRingsDone: activityRingsDone,
            dailyCalorieDone: dailyCalorieDone,
            dailyWaterDone: dailyWaterDone,
            precomputedNodes: nodes,
            onTapNode: { node in
                switch node.type {
                case .training:       showTracker = true
                case .mindfulness:    showMindfulnessSession = true
                case .stretch:        showStretchSession = true
                case .stand:          showStandSession = true
                case .sleep, .activity: break
                case .weight:
                    // Withingsアプリを開く（複数スキームを試してApp Storeへフォールバック）
                    let withingsSchemes = ["wiscale2://", "healthmate://", "withings://"]
                    let withingsAppStore = URL(string: "https://apps.apple.com/app/id542701020")!
                    if let scheme = withingsSchemes
                        .compactMap({ URL(string: $0) })
                        .first(where: { UIApplication.shared.canOpenURL($0) }) {
                        UIApplication.shared.open(scheme)
                    } else {
                        UIApplication.shared.open(withingsAppStore)
                    }
                case .pfc:            showMandalaDetail = true
                case .meal, .drink:   selectedMandalaNode = node
                case .custom:
                    // 勉強アイコンは登録URLを開く
                    if node.id == "wd-study",
                       let url = URL(string: studyBookUrl.hasPrefix("http") ? studyBookUrl : "https://\(studyBookUrl)") {
                        UIApplication.shared.open(url)
                    } else {
                        selectedMandalaNode = node
                    }
                }
            }
        )
    }

    private var settingsButton: some View {
        Button { showMandalaDetail = true } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 12 * UIScale.font))
                .foregroundColor(Color.duoOrange)
                .padding(7)
                .background(Color(.systemBackground).opacity(0.88))
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.08), radius: 2, y: 1)
        }
        .padding(.top, 34)
        .padding(.trailing, 4)
    }


    private func progressBadge(done: Int, total: Int, label: String) -> some View {
        let pct = total > 0 ? Double(done) / Double(total) : 0.0
        let numColor: Color = done == total ? Color.duoGreen
            : pct >= 0.5 ? Color.duoOrange
            : Color.duoSubtitle
        return VStack(spacing: 0) {
            Text("\(done)/\(total)")
                .font(.system(size: 12 * UIScale.font, weight: .black, design: .rounded))
                .foregroundColor(numColor)
            Text(label)
                .font(.system(size: 8 * UIScale.font, weight: .semibold))
                .foregroundColor(Color.duoSubtitle)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color(.systemBackground).opacity(0.85))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.06), radius: 2, y: 1)
    }

    private var legendOverlay: some View {
        legendRow
            .padding(.vertical, 3)
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground).opacity(0.82))
            .cornerRadius(6)
            .shadow(color: Color.black.opacity(0.06), radius: 2, y: 1)
            .padding(.top, 6)
            .padding(.horizontal, 6)
    }

    private var legendRow: some View {
        let todayNodes = nodes.filter { $0.slot == nil }
        return HStack(spacing: 2) {
            legendCell(label: "今日", color: Color(hex: "CE82FF"),
                       done: todayNodes.filter(\.isCompleted).count, total: todayNodes.count)
            ForEach(visibleSlots, id: \.self) { slot in
                slotLegend(slot: slot)
            }
        }
    }

    private func slotLegend(slot: TimeSlot) -> some View {
        let sn = nodes.filter { $0.slot == slot }
        return legendCell(label: slot.displayName, color: slot.mandalaColor,
                          done: sn.filter(\.isCompleted).count, total: sn.count)
    }

    private func legendCell(label: String, color: Color, done: Int, total: Int) -> some View {
        let achieved = total > 0 && done == total
        return HStack(spacing: 2) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(total > 0 ? "\(label) \(done)/\(total)" : label)
                .font(.system(size: 9 * UIScale.font, weight: .semibold))
                .lineLimit(1)
                .foregroundColor(achieved ? color : Color.duoSubtitle)
        }
        .padding(.horizontal, 3).padding(.vertical, 1)
        .background(achieved ? color.opacity(0.12) : Color.clear)
        .cornerRadius(3)
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
    var avgHeartRate: Double = 0
    var avgHRV: Double = 0

    var body: some View {
        let instantStress = stressInfo(latestHRV)
        let avgStress = stressInfo(avgHRV > 0 ? avgHRV : latestHRV)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10 * UIScale.font))
                    .foregroundColor(Color(red: 1.0, green: 0.294, blue: 0.294))
                Text("心拍/ストレス")
                    .font(.system(size: 10 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoDark)
                Spacer()
                // 平均HRV由来のストレス指数をヘッダー右端に色付き数値＋状態バッジで表示
                if avgStress.score >= 0 {
                    HStack(spacing: 4) {
                        HStack(spacing: 2) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 8 * UIScale.font))
                                .foregroundColor(avgStress.color)
                            Text("\(avgStress.score)")
                                .font(.system(size: 11 * UIScale.font, weight: .black))
                                .foregroundColor(avgStress.color)
                        }
                        Text(avgStress.label)
                            .font(.system(size: 11 * UIScale.font, weight: .bold))
                            .foregroundColor(avgStress.color)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(avgStress.color.opacity(0.15))
                            .cornerRadius(10)
                    }
                }
            }
            HStack(alignment: .center, spacing: 7) {
                // 最新心拍
                VStack(alignment: .leading, spacing: 1) {
                    Text("最新").font(.system(size: 8 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                    HStack(alignment: .bottom, spacing: 2) {
                        Text(latestHeartRate > 0 ? "\(Int(latestHeartRate))" : "—")
                            .font(.system(size: 15 * UIScale.font, weight: .black))
                            .foregroundColor(Color.duoDark)
                        Text("bpm")
                            .font(.system(size: 9 * UIScale.font))
                            .foregroundColor(Color.duoSubtitle)
                            .padding(.bottom, 2)
                    }
                }
                Divider().frame(height: 28)
                // 最新HRV
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Image(systemName: "waveform.path.ecg.rectangle")
                            .font(.system(size: 8 * UIScale.font))
                            .foregroundColor(Color.duoGreen)
                        Text("HRV").font(.system(size: 9 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                    }
                    HStack(alignment: .bottom, spacing: 2) {
                        Text(latestHRV > 0 ? "\(Int(latestHRV))" : "—")
                            .font(.system(size: 15 * UIScale.font, weight: .bold))
                            .foregroundColor(Color.duoDark)
                        Text("ms")
                            .font(.system(size: 9 * UIScale.font))
                            .foregroundColor(Color.duoSubtitle)
                            .padding(.bottom, 1)
                    }
                }
                Divider().frame(height: 28)
                // ストレス（その時点のHRVによるラベル）
                VStack(alignment: .leading, spacing: 1) {
                    Text("ストレス").font(.system(size: 8 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                    Text(instantStress.label)
                        .font(.system(size: 13 * UIScale.font, weight: .black))
                        .foregroundColor(instantStress.color)
                }
                Divider().frame(height: 28)
                // 平均心拍・平均HRV
                VStack(alignment: .leading, spacing: 1) {
                    Text("平均").font(.system(size: 8 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                    HStack(spacing: 4) {
                        HStack(alignment: .bottom, spacing: 1) {
                            Text(avgHeartRate > 0 ? "\(Int(avgHeartRate))" : "—")
                                .font(.system(size: 13 * UIScale.font, weight: .bold))
                                .foregroundColor(Color.duoDark)
                            Text("bpm")
                                .font(.system(size: 8 * UIScale.font))
                                .foregroundColor(Color.duoSubtitle)
                                .padding(.bottom, 1)
                        }
                        Text("/")
                            .font(.system(size: 9 * UIScale.font))
                            .foregroundColor(Color.duoSubtitle)
                        HStack(alignment: .bottom, spacing: 1) {
                            Text(avgHRV > 0 ? "\(Int(avgHRV))" : "—")
                                .font(.system(size: 13 * UIScale.font, weight: .bold))
                                .foregroundColor(Color.duoGreen)
                            Text("ms")
                                .font(.system(size: 8 * UIScale.font))
                                .foregroundColor(Color.duoSubtitle)
                                .padding(.bottom, 1)
                        }
                    }
                }
                Spacer()
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.duoBg)
        .cornerRadius(10)
    }

    // 平均HRV → ストレス指数（0–100）+ ラベル + 色
    private func stressInfo(_ hrv: Double) -> (score: Int, label: String, color: Color) {
        guard hrv > 0 else { return (-1, "—", Color.duoSubtitle) }
        let score: Int = {
            if hrv >= 100 { return 5 }
            if hrv >= 80  { return Int(5  + (100 - hrv) / 20 * 10) }
            if hrv >= 60  { return Int(15 + (80  - hrv) / 20 * 20) }
            if hrv >= 40  { return Int(35 + (60  - hrv) / 20 * 25) }
            if hrv >= 20  { return Int(60 + (40  - hrv) / 20 * 20) }
            return Int(min(95, 80 + (20 - hrv) / 20 * 15))
        }()
        switch score {
        case ..<30: return (score, "低い",   Color.duoGreen)
        case ..<55: return (score, "普通",   Color(red: 0.4, green: 0.75, blue: 0.1))
        case ..<75: return (score, "やや高", Color.duoOrange)
        default:    return (score, "高い",   Color(hex: "#FF4B4B"))
        }
    }
}

// MARK: - 週間カロリー収支カード

private struct WeeklyDayBarView: View {
    let day: DailyCalorieBalance
    let maxAbs: Int
    let halfBarH: CGFloat

    var body: some View {
        let bal = day.balance
        let barH = maxAbs > 0 ? max(CGFloat(bal != 0 ? 2 : 0), halfBarH * CGFloat(abs(bal)) / CGFloat(maxAbs)) : 0

        VStack(spacing: 2) {
            // 収支ラベル
            Text(bal != 0 ? (bal >= 0 ? "+" : "") + "\(bal)" : "")
                .font(.system(size: 7 * UIScale.font, weight: .bold))
                .foregroundColor(bal <= 0 ? Color.duoGreen : Color(hex: "#FF4B4B"))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(height: 10)

            // 上半分：赤字バー（消費オーバー＝収支マイナス→緑）
            ZStack(alignment: .bottom) {
                Color.clear.frame(height: halfBarH)
                if bal < 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.duoGreen.opacity(0.85))
                        .frame(height: min(barH, halfBarH))
                }
            }

            // 中心線
            Rectangle()
                .fill(Color(.systemGray3))
                .frame(height: 0.5)

            // 下半分：余剰バー（摂取オーバー＝収支プラス→赤）
            ZStack(alignment: .top) {
                Color.clear.frame(height: halfBarH)
                if bal > 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: "#FF4B4B").opacity(0.75))
                        .frame(height: min(barH, halfBarH))
                }
            }

            // 曜日ラベル
            Text(day.dayLabel)
                .font(.system(size: 9 * UIScale.font, weight: .semibold))
                .foregroundColor(Color.duoSubtitle)

            // 体重
            if let mass = day.bodyMass {
                Text(String(format: "%.1f", mass))
                    .font(.system(size: 7 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoDark)
                    .lineLimit(1)
            } else {
                Text("—")
                    .font(.system(size: 7 * UIScale.font))
                    .foregroundColor(Color(.systemGray4))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WeeklyCalorieCard: View {
    let data: [DailyCalorieBalance]
    var dailyGoal: Int = -150  // DietGoalManager から渡される（デフォルト -150）

    private let halfBarH: CGFloat = 32
    private var weeklyGoal: Int { dailyGoal * 7 }

    private func statusBadge(weekTotal: Int) -> (label: String, color: Color) {
        let today = Calendar.current.startOfDay(for: Date())
        let daysElapsed = max(1, data.filter { Calendar.current.startOfDay(for: $0.date) <= today }.count)
        let expected = daysElapsed * dailyGoal
        if weekTotal <= weeklyGoal       { return ("達成！", Color.duoGreen) }
        if weekTotal <= expected         { return ("順調", Color(hex: "#1CB0F6")) }
        if weekTotal < expected / 2      { return ("注意", Color(hex: "#FF9600")) }
        return ("危険", Color(hex: "#FF4B4B"))
    }

    var body: some View {
        let weekTotal = data.reduce(0) { $0 + $1.balance }
        let weightImpactKg = Double(weekTotal) / 7700.0
        let maxAbs = max(data.map { abs($0.balance) }.max() ?? 0, 300)
        let badge = statusBadge(weekTotal: weekTotal)

        // 月曜比の体重差分
        let mondayMass = data.first?.bodyMass
        let latestMass = data.last(where: { $0.bodyMass != nil })?.bodyMass
        let massDiff: Double? = (mondayMass != nil && latestMass != nil) ? latestMass! - mondayMass! : nil
        let diffColor: Color = (massDiff ?? 0) < 0 ? Color.duoGreen
            : (massDiff ?? 0) > 0 ? Color(hex: "#FF4B4B")
            : Color.duoSubtitle

        VStack(alignment: .leading, spacing: 10) {
            // ヘッダー
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 11 * UIScale.font, weight: .bold))
                    .foregroundColor(Color(hex: "#FF9600"))
                Text("週間カロリー")
                    .font(.system(size: 11 * UIScale.font, weight: .black))
                    .foregroundColor(Color.duoDark)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 5) {
                        Text((weekTotal >= 0 ? "+" : "") + "\(weekTotal) kcal")
                            .font(.system(size: 12 * UIScale.font, weight: .black))
                            .foregroundColor(weekTotal > 0 ? Color(hex: "#FF4B4B") : Color.duoGreen)
                        Text(badge.label)
                            .font(.system(size: 9 * UIScale.font, weight: .black))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(badge.color)
                            .cornerRadius(6)
                    }
                    HStack(spacing: 5) {
                        Text((weightImpactKg >= 0 ? "+" : "") + String(format: "%.2f", weightImpactKg) + " kg")
                            .font(.system(size: 10 * UIScale.font, weight: .bold))
                            .foregroundColor(weightImpactKg > 0 ? Color(hex: "#FF4B4B").opacity(0.8) : Color.duoGreen.opacity(0.8))
                        if let diff = massDiff {
                            Text((diff >= 0 ? "+" : "") + String(format: "%.1f", diff) + "kg")
                                .font(.system(size: 9 * UIScale.font, weight: .bold))
                                .foregroundColor(diffColor)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(diffColor.opacity(0.1))
                                .cornerRadius(5)
                        }
                    }
                }
            }

            // 日別バー
            HStack(alignment: .center, spacing: 4) {
                ForEach(data) { day in
                    WeeklyDayBarView(day: day, maxAbs: maxAbs, halfBarH: halfBarH)
                }
            }

            // 凡例
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1).fill(Color.duoGreen.opacity(0.85)).frame(width: 10, height: 4)
                    Text("消費オーバー").font(.system(size: 9 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1).fill(Color(hex: "#FF4B4B").opacity(0.75)).frame(width: 10, height: 4)
                    Text("摂取オーバー").font(.system(size: 9 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                }
                Spacer()
                Text("目標: 1日-\(abs(dailyGoal))kcal")
                    .font(.system(size: 9 * UIScale.font))
                    .foregroundColor(Color.duoSubtitle)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
    }
}

// MARK: - カロリー収支バーカード

private struct CalorieBalanceBarCard: View {
    let totalConsumed: Double
    let intake: Double
    var latestBodyMass: Double = 0
    var latestBodyFatPercentage: Double = 0
    var weeklyBodyMassChange: Double? = nil
    var weeklyBodyFatChange: Double? = nil

    var body: some View {
        let balance = intake - totalConsumed
        let isPositive = balance > 0
        let absBalance = abs(balance)
        let circleSize: CGFloat = 35 + 20 * min(absBalance / 1000.0, 1.0)

        let calLabel: String = {
            if balance < -500 { return "大幅減" }
            if balance < 0    { return "良好" }
            if balance < 300  { return "普通" }
            return "過剰"
        }()
        let calColor: Color = {
            if balance < 0    { return Color.duoGreen }
            if balance < 300  { return Color(hex: "#FFD900") }
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
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(calColor.opacity(0.15))
                        .cornerRadius(10)
                }
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
                Text("消費Cal").font(.system(size: 8 * UIScale.font, weight: .semibold)).foregroundColor(Color.duoGreen)
                    .frame(width: cw, alignment: .center)
                Text("摂取Cal").font(.system(size: 8 * UIScale.font, weight: .semibold)).foregroundColor(Color.duoRed)
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
                Text("\(Int(consumed))").font(.system(size: 13 * UIScale.font, weight: .black)).foregroundColor(.white)
                Text("cal").font(.system(size: 8 * UIScale.font, weight: .medium)).foregroundColor(.white.opacity(0.9))
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
                Text("\(Int(intake))").font(.system(size: 13 * UIScale.font, weight: .black)).foregroundColor(.white)
                Text("cal").font(.system(size: 8 * UIScale.font, weight: .medium)).foregroundColor(.white.opacity(0.9))
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
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 6 * UIScale.font)).foregroundColor(.red)
                Text("+\(grams)g").font(.system(size: 7 * UIScale.font, weight: .bold)).foregroundColor(.red)
            }
        } else if absBalance > 0 {
            HStack(spacing: 1) {
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 6 * UIScale.font)).foregroundColor(Color.duoGreen)
                Text("-\(grams)g").font(.system(size: 7 * UIScale.font, weight: .bold)).foregroundColor(Color.duoGreen)
            }
        } else {
            HStack(spacing: 1) {
                Image(systemName: "equal.circle.fill").font(.system(size: 6 * UIScale.font)).foregroundColor(Color.duoGreen)
                Text("±0g").font(.system(size: 7 * UIScale.font, weight: .bold)).foregroundColor(Color.duoGreen)
            }
        }
    }
}

struct StretchSessionVideo: Identifiable {
    let id: String
    let name: String
    let gifName: String
    var emoji: String
    var description: String

    init(name: String, gifName: String, emoji: String = "🤸", description: String = "") {
        self.id = gifName
        self.name = name
        self.gifName = gifName
        self.emoji = emoji
        self.description = description
    }

    static let defaultStretchVideos: [StretchSessionVideo] = [
        StretchSessionVideo(name: "仰向けツイスト", gifName: "fitingo_st_twist", emoji: "🔄", description: "膝を倒して背骨をゆっくりねじる"),
        StretchSessionVideo(name: "キャットとドッグ", gifName: "fitingo_st_cat", emoji: "🐱", description: "背中を丸め、反らして繰り返す"),
        StretchSessionVideo(name: "太陽礼拝", gifName: "fitingo_st_sun", emoji: "☀️", description: "全身を使う流れるような動き"),
    ]
}

struct MindfulnessSessionView: View {
    @Environment(\.dismiss) private var dismiss

    let onComplete: (Date, Date) -> Void
    var durationSeconds: Int = 60
    var title: String = "1分呼吸"
    var completedButtonTitle: String = "完了して保存"
    var sessionVideos: [StretchSessionVideo] = []

    @State private var sessionStart = Date()
    @State private var remainingSeconds: Int
    @State private var lastBreathPhase = -1
    @State private var isCompleting = false
    @State private var selectedVideoIndex = 0

    init(
        durationSeconds: Int = 60,
        title: String = "1分呼吸",
        completedButtonTitle: String = "完了して保存",
        sessionVideos: [StretchSessionVideo] = [],
        onComplete: @escaping (Date, Date) -> Void
    ) {
        self.durationSeconds = durationSeconds
        self.title = title
        self.completedButtonTitle = completedButtonTitle
        self.sessionVideos = Array(sessionVideos.prefix(3))
        self.onComplete = onComplete
        _remainingSeconds = State(initialValue: durationSeconds)
    }

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let inhaleHapticTimer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()
    private let inhaleSeconds = 7
    private let exhaleSeconds = 8

    private var elapsedSeconds: Int { durationSeconds - remainingSeconds }
    private var progress: Double { Double(elapsedSeconds) / Double(durationSeconds) }
    private var breathCycleSeconds: Int { inhaleSeconds + exhaleSeconds }
    private var breathPhase: Int { elapsedSeconds / breathCycleSeconds }
    private var breathCyclePosition: Int { elapsedSeconds % breathCycleSeconds }
    private var isInhale: Bool { breathCyclePosition < inhaleSeconds }
    private var phaseProgress: Double {
        if isInhale {
            return Double(breathCyclePosition) / Double(inhaleSeconds)
        }
        return Double(breathCyclePosition - inhaleSeconds) / Double(exhaleSeconds)
    }
    private var stretchPhaseText: String? {
        guard durationSeconds >= 180 else { return nil }
        return "\(min(elapsedSeconds / 60 + 1, 3))/3"
    }
    private var selectedVideo: StretchSessionVideo? {
        guard !sessionVideos.isEmpty else { return nil }
        return sessionVideos[min(selectedVideoIndex, sessionVideos.count - 1)]
    }
    private var ringSize: CGFloat { 280 }
    private var innerCircleBase: CGFloat { 70.0 }
    private var innerCircleRange: CGFloat { 160.0 }
    private var currentStretchIndex: Int {
        guard !sessionVideos.isEmpty else { return 0 }
        return min(elapsedSeconds / 60, sessionVideos.count - 1)
    }
    private var currentStretch: StretchSessionVideo? {
        guard !sessionVideos.isEmpty else { return nil }
        return sessionVideos[currentStretchIndex]
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.duoPurple, Color(red: 0.35, green: 0.55, blue: 1.0), Color.duoGreen.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack(alignment: .leading) {
                    Text(title)
                        .font(.system(size: 17 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15 * UIScale.font, weight: .black))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.20), lineWidth: 12)
                        .frame(width: ringSize, height: ringSize)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: ringSize, height: ringSize)
                        .animation(.easeInOut(duration: 0.35), value: progress)

                    Circle()
                        .fill(Color.white.opacity(0.24))
                        .frame(
                            width: isInhale ? innerCircleBase + innerCircleRange * phaseProgress : (innerCircleBase + innerCircleRange) - innerCircleRange * phaseProgress,
                            height: isInhale ? innerCircleBase + innerCircleRange * phaseProgress : (innerCircleBase + innerCircleRange) - innerCircleRange * phaseProgress
                        )
                        .animation(.easeInOut(duration: 1.0), value: remainingSeconds)

                    VStack(spacing: 8) {
                        Text(isInhale ? "吸って" : "吐いて")
                            .font(.system(size: 34 * UIScale.font, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text(isInhale ? "ゆっくり鼻から" : "力を抜いて")
                            .font(.system(size: 15 * UIScale.font, weight: .bold))
                            .foregroundColor(.white.opacity(0.82))
                        Text("\(remainingSeconds)")
                            .font(.system(size: 42 * UIScale.font, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .monospacedDigit()
                    }
                }

                if sessionVideos.isEmpty {
                    Text("目を瞑って、深い呼吸で、今に集中して下さい")
                        .font(.system(size: 15 * UIScale.font, weight: .semibold))
                        .foregroundColor(.white.opacity(0.82))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                } else if let stretch = currentStretch {
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            Text("\(currentStretchIndex + 1)/3")
                                .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.white.opacity(0.22))
                                .cornerRadius(6)
                            Text(stretch.name)
                                .font(.system(size: 20 * UIScale.font, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                        }
                        Text(stretch.description)
                            .font(.system(size: 14 * UIScale.font, weight: .semibold))
                            .foregroundColor(.white.opacity(0.82))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .animation(.easeInOut(duration: 0.5), value: currentStretchIndex)
                }

                Spacer()
            }
        }
        .onAppear {
            sessionStart = Date()
            UIApplication.shared.isIdleTimerDisabled = true
            playBreathHaptic()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onReceive(timer) { _ in
            guard !isCompleting else { return }
            if remainingSeconds > 0 {
                remainingSeconds -= 1
                if breathPhase != lastBreathPhase {
                    lastBreathPhase = breathPhase
                    playPhaseChangeHaptic()
                }
                if remainingSeconds == 0 {
                    completeSession()
                }
            } else {
                completeSession()
            }
        }
        .onReceive(inhaleHapticTimer) { _ in
            guard !isCompleting, remainingSeconds > 0, isInhale else { return }
            playInhalePulseHaptic()
        }
    }

    private func completeSession() {
        guard !isCompleting else { return }
        isCompleting = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onComplete(sessionStart, sessionStart.addingTimeInterval(TimeInterval(durationSeconds)))
        dismiss()
    }

    private func playBreathHaptic() {
        if isInhale {
            playInhalePulseHaptic()
        } else {
            playPhaseChangeHaptic()
        }
    }

    private func playInhalePulseHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.42)
    }

    private func playPhaseChangeHaptic() {
        let generator = UIImpactFeedbackGenerator(style: isInhale ? .light : .medium)
        generator.prepare()
        generator.impactOccurred(intensity: isInhale ? 0.55 : 0.80)
    }
}

// MARK: - PFCミニリング（P=赤, F=オレンジ, C=緑）
struct ArcSegment: Shape {
    let startFraction: Double
    let endFraction: Double
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.addArc(
            center: center, radius: radius,
            startAngle: .degrees(-90 + 360 * startFraction),
            endAngle: .degrees(-90 + 360 * endFraction),
            clockwise: false
        )
        return path
    }
}

struct PFCMiniRingView: View {
    let proteinKcal: Double
    let fatKcal: Double
    let carbsKcal: Double
    let diameter: CGFloat
    let lineWidth: CGFloat
    var centerText: String? = nil
    var centerTextColor: Color = Color.duoDark

    var body: some View {
        let total = proteinKcal + fatKcal + carbsKcal
        let pFrac = total > 0 ? proteinKcal / total : 0
        let fFrac = total > 0 ? fatKcal / total : 0

        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.15), lineWidth: lineWidth)
            if total > 0 {
                ArcSegment(startFraction: 0, endFraction: pFrac)
                    .stroke(Color(red: 0.98, green: 0.07, blue: 0.31), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                ArcSegment(startFraction: pFrac, endFraction: pFrac + fFrac)
                    .stroke(Color(hex: "#FF9600"), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                ArcSegment(startFraction: pFrac + fFrac, endFraction: 1.0)
                    .stroke(Color(hex: "#58CC02"), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            }
            if let text = centerText {
                Text(text)
                    .font(.system(size: diameter * 0.264, weight: .black, design: .rounded))
                    .foregroundColor(centerTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

struct SleepMiniRingView: View {
    let hours: Double
    let goal: Double
    let diameter: CGFloat
    let lineWidth: CGFloat
    let ringColor: Color

    var body: some View {
        let fraction = goal > 0 ? min(1.0, hours / goal) : 0
        let achieved = hours >= goal && goal > 0
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.15), lineWidth: lineWidth)
            if hours > 0 {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(achieved ? ringColor : ringColor.opacity(0.7),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            let label: String = hours > 0
                ? (hours >= 1 ? String(format: "%.1f", hours) : String(format: "%dm", Int(hours * 60)))
                : "—"
            Text(label)
                .font(.system(size: diameter * 0.22, weight: .black, design: .rounded))
                .foregroundColor(achieved ? ringColor : Color.duoDark)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
        .frame(width: diameter, height: diameter)
    }
}

private struct DailyGoalPickerButton: View {
    let emoji: String
    let name: String
    let isDone: Bool
    let onComplete: () -> Void

    @State private var showSheet = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Text(emoji).font(.system(size: 22 * UIScale.font))
                Circle()
                    .fill(isDone ? Color.duoGreen : Color.duoRed)
                    .frame(width: 8, height: 8)
                    .offset(x: 2, y: 2)
            }
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            GoalCompletionSheet(
                emoji: emoji,
                name: name,
                isDone: isDone,
                onComplete: {
                    onComplete()
                    showSheet = false
                }
            )
            .presentationDetents([.height(290)])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - EDUフォトログシート

private struct EduPhotoLogSheet: View {
    let nodeEmoji: String
    let nodeName: String
    let onComplete: (Bool, Bool, UIImage?, String) -> Void

    @State private var selectedImage: UIImage? = nil
    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var comment: String = ""
    @State private var saveToFeed: Bool = true
    @State private var isPublic: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(nodeEmoji).font(.system(size: 44 * UIScale.font))
                Text(nodeName).font(.title3).fontWeight(.black).foregroundColor(Color.duoDark)
            }
            .padding(.top, 20).padding(.bottom, 14)

            Divider()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    // 写真選択
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        if let image = selectedImage {
                            Image(uiImage: image)
                                .resizable().scaledToFill()
                                .frame(maxWidth: .infinity).frame(height: 160)
                                .cornerRadius(12).clipped()
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6))
                                .frame(maxWidth: .infinity).frame(height: 90)
                                .overlay {
                                    VStack(spacing: 6) {
                                        Image(systemName: "camera.fill")
                                            .font(.title2).foregroundColor(Color.duoBlue)
                                        Text("写真を選択（任意）")
                                            .font(.caption).foregroundColor(Color.duoBlue)
                                    }
                                }
                        }
                    }

                    // コメント入力
                    TextField("タイトル・メモ（本のタイトル・学んだこと等）", text: $comment)
                        .font(.body)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .submitLabel(.done)
                        .onSubmit {
                            UIApplication.shared.sendAction(
                                #selector(UIResponder.resignFirstResponder),
                                to: nil, from: nil, for: nil
                            )
                        }

                    // フィードに追加（Dailyフィード + TOMOフィードを同時制御）
                    Toggle(isOn: Binding(
                        get: { saveToFeed },
                        set: { v in saveToFeed = v; isPublic = v }
                    )) {
                        HStack(spacing: 6) {
                            Image(systemName: saveToFeed ? "rectangle.stack.fill" : "rectangle.stack")
                                .foregroundColor(saveToFeed ? Color.duoGreen : Color.duoSubtitle)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("フィードに追加")
                                    .font(.subheadline).fontWeight(.semibold)
                                Text(saveToFeed ? "Dailyフィード・TOMOフィードに公開" : "フィードには追加しない")
                                    .font(.caption)
                                    .foregroundColor(Color.duoSubtitle)
                            }
                        }
                    }
                    .tint(Color.duoGreen)

                    // 記録ボタン
                    Button {
                        onComplete(saveToFeed, isPublic, selectedImage, comment)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill").font(.title3)
                            Text("記録する").font(.headline).fontWeight(.black)
                            Spacer()
                        }
                        .foregroundColor(Color.duoGreen)
                        .padding(.horizontal, 20).padding(.vertical, 14)
                        .background(Color.duoGreen.opacity(0.1))
                        .cornerRadius(14)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedImage = image
                }
            }
        }
    }
}

private struct GoalCompletionSheet: View {
    let emoji: String
    let name: String
    let isDone: Bool
    let onComplete: () -> Void
    var onPhotoTap: (() -> Void)? = nil
    var isRecordType: Bool = false

    @State private var pickerItem: PhotosPickerItem? = nil

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(emoji)
                    .font(.system(size: 44 * UIScale.font))
                Text(name)
                    .font(.title3).fontWeight(.black)
                    .foregroundColor(Color.duoDark)
                if isDone {
                    Label("達成済み", systemImage: "checkmark.circle.fill")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(Color.duoGreen)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 18)

            Divider()

            VStack(spacing: 10) {
                // 完了ボタン
                Button {
                    onComplete()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isDone
                              ? "arrow.uturn.backward.circle.fill"
                              : "checkmark.circle.fill")
                            .font(.title3)
                        Text(isDone ? "完了を取り消す" : (isRecordType ? "記録する" : "完了する"))
                            .font(.headline).fontWeight(.black)
                        Spacer()
                    }
                    .foregroundColor(isDone ? Color.duoRed : Color.duoGreen)
                    .padding(.horizontal, 20).padding(.vertical, 14)
                    .background((isDone ? Color.duoRed : Color.duoGreen).opacity(0.1))
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)

                // 写真で記録（フォトログ or ライブラリ選択）
                if let onPhotoTap {
                    Button {
                        onPhotoTap()
                    } label: {
                        photoButtonLabel
                    }
                    .buttonStyle(.plain)
                } else {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        photoButtonLabel
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer()
        }
        .onChange(of: pickerItem) { _, item in
            guard item != nil else { return }
            onComplete()
            pickerItem = nil
        }
    }

    private var photoButtonLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.title3)
            Text("写真で記録する")
                .font(.headline).fontWeight(.black)
            Spacer()
        }
        .foregroundColor(Color(hex: "#1CB0F6"))
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(Color(hex: "#1CB0F6").opacity(0.1))
        .cornerRadius(14)
    }
}

// MARK: - 20分スタンドポモドーロタイマー

// MARK: - トマト柑橘スライス Shape

private struct TomatoSliceShape: Shape {
    let segments: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let innerRadius = radius * 0.28
        let anglePerSegment = (2.0 * Double.pi) / Double(segments)
        let gapAngle = anglePerSegment * 0.08

        for i in 0..<segments {
            let startAngle = Double(i) * anglePerSegment - Double.pi / 2 + gapAngle
            let endAngle = startAngle + anglePerSegment - gapAngle * 2

            // セグメントの外側アーク
            path.move(to: CGPoint(
                x: center.x + innerRadius * cos(startAngle),
                y: center.y + innerRadius * sin(startAngle)
            ))
            path.addLine(to: CGPoint(
                x: center.x + radius * cos(startAngle),
                y: center.y + radius * sin(startAngle)
            ))
            path.addArc(center: center, radius: radius,
                        startAngle: .radians(startAngle),
                        endAngle: .radians(endAngle), clockwise: false)
            path.addLine(to: CGPoint(
                x: center.x + innerRadius * cos(endAngle),
                y: center.y + innerRadius * sin(endAngle)
            ))
            path.addArc(center: center, radius: innerRadius,
                        startAngle: .radians(endAngle),
                        endAngle: .radians(startAngle), clockwise: true)
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - 20分スタンド ポモドーロタイマー（トマトデザイン）

struct StandPomodoroView: View {
    @Environment(\.dismiss) private var dismiss

    let durationSeconds: Int
    let onComplete: () -> Void

    @State private var remainingSeconds: Int
    @State private var timerFinished = false   // タイマー自然終了フラグ
    @State private var showCompletion = false  // 完了画面表示フラグ
    @State private var pulse = false
    @State private var completionPulse = false
    @State private var hapticTimer: Timer?

    init(durationSeconds: Int = 20 * 60, onComplete: @escaping () -> Void) {
        self.durationSeconds = durationSeconds
        self.onComplete = onComplete
        _remainingSeconds = State(initialValue: durationSeconds)
    }

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let tomatoRed      = Color(red: 0.94, green: 0.27, blue: 0.15)
    private let tomatoOrange   = Color(red: 0.99, green: 0.55, blue: 0.12)
    private let tomatoLight    = Color(red: 1.0,  green: 0.88, blue: 0.84)
    private let tomatoDark     = Color(red: 0.55, green: 0.08, blue: 0.02)
    private let bgTop          = Color(red: 0.99, green: 0.97, blue: 0.96)
    private let bgBottom       = Color(red: 0.98, green: 0.93, blue: 0.91)
    private let completionGreen = Color(red: 0.15, green: 0.72, blue: 0.38)

    private var elapsedSeconds: Int { durationSeconds - remainingSeconds }
    private var progress: Double {
        durationSeconds > 0 ? Double(elapsedSeconds) / Double(durationSeconds) : 0
    }
    private var remainProgress: Double { progress }
    private var timeText: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            // タイマー進行画面
            if !showCompletion {
                timerScreen
            } else {
                // 完了画面（タイマー自然終了時のみ）
                completionScreen
            }
        }
        .onAppear { pulse = true }
        .onReceive(timer) { _ in
            guard !timerFinished else { return }
            if remainingSeconds > 0 {
                remainingSeconds -= 1
            } else {
                // タイマー自然終了 → 完了画面へ（記録はまだしない）
                timerFinished = true
                showCompletion = true
                startCompletionHaptics()
            }
        }
        .onDisappear { stopHaptics() }
    }

    // MARK: - タイマー進行画面

    private var timerScreen: some View {
        VStack(spacing: 0) {
            // 右上クローズボタン
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15 * UIScale.font, weight: .bold))
                        .foregroundColor(tomatoDark.opacity(0.45))
                        .padding(10)
                        .background(tomatoRed.opacity(0.08))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()

            VStack(spacing: 4) {
                Text("スタンドポモドーロ")
                    .font(.system(size: 13 * UIScale.font, weight: .semibold, design: .rounded))
                    .foregroundColor(tomatoRed.opacity(0.65))
                    .tracking(1.5)
                Text("20分間、立って集中")
                    .font(.system(size: 17 * UIScale.font, weight: .black, design: .rounded))
                    .foregroundColor(tomatoDark)
            }
            .padding(.bottom, 28)

            // トマト柑橘タイマー
            ZStack {
                Circle()
                    .stroke(tomatoLight, lineWidth: 18)
                Circle()
                    .trim(from: 0, to: CGFloat(remainProgress))
                    .stroke(
                        AngularGradient(colors: [tomatoOrange, tomatoRed, tomatoOrange], center: .center),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.8), value: remainProgress)

                ZStack {
                    TomatoSliceShape(segments: 8)
                        .fill(tomatoOrange.opacity(0.80))
                        .frame(width: 176, height: 176)
                    TomatoSliceShape(segments: 8)
                        .fill(RadialGradient(
                            colors: [Color.white.opacity(0.30), Color.clear],
                            center: .center, startRadius: 0, endRadius: 80
                        ))
                        .frame(width: 176, height: 176)
                    Circle()
                        .fill(bgTop)
                        .frame(width: 52, height: 52)
                    VStack(spacing: 2) {
                        Text(timeText)
                            .font(.system(size: 26 * UIScale.font, weight: .black, design: .rounded))
                            .foregroundColor(tomatoDark)
                            .monospacedDigit()
                        Text("残り")
                            .font(.system(size: 9 * UIScale.font, weight: .bold, design: .rounded))
                            .foregroundColor(tomatoDark.opacity(0.5))
                    }
                }
                .scaleEffect(pulse ? 1.015 : 1.0)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulse)
            }
            .frame(width: 240, height: 240)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 11 * UIScale.font))
                    .foregroundColor(tomatoOrange)
                Text("立つことで集中力・代謝がアップ！")
                    .font(.system(size: 12 * UIScale.font, weight: .medium, design: .rounded))
                    .foregroundColor(tomatoDark.opacity(0.45))
            }
            .padding(.bottom, 20)

            // 途中完了ボタン（明示的な完了）
            Button { finishAndRecord() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 16 * UIScale.font, weight: .bold))
                    Text("完了にする")
                        .font(.system(size: 16 * UIScale.font, weight: .black, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(LinearGradient(colors: [tomatoOrange, tomatoRed],
                                           startPoint: .leading, endPoint: .trailing))
                .cornerRadius(18)
                .shadow(color: tomatoRed.opacity(0.25), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
    }

    // MARK: - 完了画面（タイマー自然終了後）

    private var completionScreen: some View {
        VStack(spacing: 24) {
            Spacer()

            // 完了アニメーション
            ZStack {
                Circle()
                    .fill(completionGreen.opacity(0.15))
                    .frame(width: 200, height: 200)
                    .scaleEffect(completionPulse ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                               value: completionPulse)

                Circle()
                    .fill(completionGreen.opacity(0.25))
                    .frame(width: 160, height: 160)

                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64 * UIScale.font))
                        .foregroundColor(completionGreen)
                    Text("20分完了！")
                        .font(.system(size: 22 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor(Color(red: 0.08, green: 0.28, blue: 0.15))
                    Text("お疲れ様でした")
                        .font(.system(size: 14 * UIScale.font, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(red: 0.08, green: 0.28, blue: 0.15).opacity(0.6))
                }
            }

            Spacer()

            // 閉じるボタンで記録確定
            Button { finishAndRecord() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18 * UIScale.font, weight: .bold))
                    Text("記録して閉じる")
                        .font(.system(size: 17 * UIScale.font, weight: .black, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(LinearGradient(colors: [completionGreen, Color(red: 0.08, green: 0.55, blue: 0.28)],
                                           startPoint: .leading, endPoint: .trailing))
                .cornerRadius(18)
                .shadow(color: completionGreen.opacity(0.5), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 50)
        }
        .onAppear { completionPulse = true }
    }

    // MARK: - ハプティクス

    private func startCompletionHaptics() {
        // 連続ハプティクスで気づかせる（2秒おきに3回）
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
        hapticTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { t in
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        // 10秒後に自動停止
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { stopHaptics() }
    }

    private func stopHaptics() {
        hapticTimer?.invalidate()
        hapticTimer = nil
    }

    // MARK: - 記録・終了

    private func finishAndRecord() {
        stopHaptics()
        onComplete()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { dismiss() }
    }
}

// MARK: - DailySetsExpandableSection
// 展開ボタンと展開コンテンツを独立Viewに分離し、DashboardView の再レンダリングを防ぐ
private struct DailySetsExpandableSection: View {
    @ObservedObject var timeSlotManager: TimeSlotManager
    @ObservedObject var healthKit: HealthKitManager
    let todayExercises: [CompletedExercise]
    let mandalaContextLabel: String
    let dailyCalorieGoal: Int
    let dailyWaterGoal: Int

    @State private var showTodayRecords = false
    @State private var expandedSetIds: Set<Int> = []

    private var visibleSlots: [TimeSlot] {
        let h = Calendar.current.component(.hour, from: Date())
        let all: [TimeSlot] = [.morning, .noon, .afternoon, .evening]
        if h < 6 { return all }
        else if h < 10 { return [.morning] }
        else if h < 14 { return [.morning, .noon] }
        else if h < 18 { return [.morning, .noon, .afternoon] }
        else { return all }
    }

    var body: some View {
        Group {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showTodayRecords.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(mandalaContextLabel)
                        .font(.caption2)
                        .foregroundColor(Color.duoSubtitle)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: showTodayRecords ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoSubtitle)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if showTodayRecords {
                VStack(spacing: 0) {
                    Divider().padding(.horizontal, 16)
                    VStack(spacing: 10) {
                        ForEach(visibleSlots, id: \.rawValue) { slot in
                            timeSlotRow(for: slot)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }

            if showTodayRecords {
                TodayHistorySection(
                    todayExercises: todayExercises,
                    mindfulSessions: healthKit.todayMindfulnessSamples.sorted { $0.startDate < $1.startDate },
                    mealSamples: healthKit.todayMealSamples.sorted { $0.startDate < $1.startDate },
                    waterSamples: healthKit.todayWaterSamples.sorted { $0.startDate < $1.startDate },
                    toothbrushingSamples: healthKit.todayToothbrushingSamples.sorted(),
                    bodyMassRecord: healthKit.todayBodyMassRecord,
                    latestBodyFatPercentage: healthKit.latestBodyFatPercentage,
                    expandedSetIds: $expandedSetIds,
                    mindfulGoalMinutes: totalMindfulGoalMinutes,
                    dailyCalorieGoal: dailyCalorieGoal,
                    dailyWaterGoal: dailyWaterGoal
                )
            }
        }
    }

    // MARK: Helpers

    private func countSetsInTimeSlot(_ slot: TimeSlot) -> Int {
        let cal = Calendar.current
        let inSlot = todayExercises
            .filter { let h = cal.component(.hour, from: $0.timestamp); return h >= slot.startHour && h < slot.endHour }
            .sorted { $0.timestamp < $1.timestamp }
        guard !inSlot.isEmpty else { return 0 }
        var count = 0; var lastTime: Date? = nil
        for ex in inSlot {
            if let last = lastTime, ex.timestamp.timeIntervalSince(last) <= 30 * 60 { }
            else { count += 1 }
            lastTime = ex.timestamp
        }
        return count
    }

    /// その時間帯に記録された食事カロリーの合計（kcal）
    private func caloriesInSlot(_ slot: TimeSlot) -> Double {
        let cal = Calendar.current
        return healthKit.todayMealSamples
            .filter { let h = cal.component(.hour, from: $0.startDate); return h >= slot.startHour && h < slot.endHour }
            .reduce(0.0) { $0 + $1.value }
    }

    /// その時間帯に記録された水分量の合計（ml）
    private func waterInSlot(_ slot: TimeSlot) -> Double {
        let cal = Calendar.current
        return healthKit.todayWaterSamples
            .filter { let h = cal.component(.hour, from: $0.startDate); return h >= slot.startHour && h < slot.endHour }
            .reduce(0.0) { $0 + $1.value }
    }

    private var totalMindfulGoalMinutes: Int {
        // 表示用: HealthKit の mindfulness セッションで追跡される瞑想+スタンドの合計目標
        // （ストレッチは Firestore のみ管理のため除外）
        [TimeSlot.morning, .noon, .afternoon, .evening].reduce(0) {
            guard let goal = timeSlotManager.settings.goalFor($1) else { return $0 }
            let standMin = goal.standGoal.enabled ? goal.standGoal.standMinutes : 0
            return $0 + goal.mindfulnessGoal + standMin
        }
    }

    private var dailyTrainingAllDone: Bool {
        let slots: [TimeSlot] = [.morning, .noon, .afternoon, .evening]
        let goal = slots.reduce(0) { $0 + (timeSlotManager.settings.goalFor($1)?.trainingGoal ?? 0) }
        let done = slots.reduce(0) { $0 + countSetsInTimeSlot($1) }
        return goal > 0 && done >= goal
    }
    private var dailyMindfulnessAllDone: Bool {
        let slots: [TimeSlot] = [.morning, .noon, .afternoon, .evening]
        let goal = slots.reduce(0) { $0 + (timeSlotManager.settings.goalFor($1)?.mindfulnessGoal ?? 0) }
        let done = slots.reduce(0) {
            let p = timeSlotManager.progress.progressFor($1)
            return $0 + (p?.mindfulnessCompleted ?? 0) + (p?.stretchSetsCompleted ?? 0) * 3
        }
        return goal > 0 && done >= goal
    }
    private var dailyStandAllDone: Bool {
        [TimeSlot.morning, .noon, .afternoon, .evening].contains {
            timeSlotManager.settings.goalFor($0)?.standGoal.enabled == true &&
            (timeSlotManager.progress.progressFor($0)?.standCompleted ?? 0) >= 1
        }
    }
    private var dailyCompletedActivityNames: Set<String> {
        var names = Set<String>()
        for slot in [TimeSlot.morning, .noon, .afternoon, .evening] {
            guard let goal = timeSlotManager.settings.goalFor(slot),
                  let prog = timeSlotManager.progress.progressFor(slot) else { continue }
            for act in goal.customActivities where act.isEnabled && prog.completedActivityIds.contains(act.id) {
                names.insert(act.name)
            }
        }
        return names
    }

    private func progressCheckIcon(emoji: String, done: Bool, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(emoji).font(.caption)
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.caption2)
                .foregroundColor(done ? color : Color(.systemGray4))
        }
    }

    private func slotCustomActivityIcon(act: CustomActivity, progress: TimeSlotProgress?, slot: TimeSlot) -> some View {
        let done = dailyCompletedActivityNames.contains(act.name) || (progress?.completedActivityIds.contains(act.id) ?? false)
        return Button {
            Task { await timeSlotManager.toggleCustomActivity(id: act.id, at: slot) }
        } label: {
            progressCheckIcon(emoji: act.emoji, done: done, color: Color.duoGreen)
        }
        .buttonStyle(.plain)
    }

    private func slotActivityIcons(goal: TimeSlotGoal?, progress: TimeSlotProgress?, slot: TimeSlot) -> some View {
        let standColor = Color(red: 0.0, green: 0.6, blue: 0.85)
        let mindMin = (progress?.mindfulnessCompleted ?? 0) + (progress?.stretchSetsCompleted ?? 0) * 3
        let trainingDone = dailyTrainingAllDone || (goal.map { countSetsInTimeSlot(slot) >= $0.trainingGoal } ?? false)
        let mindDone = dailyMindfulnessAllDone || (goal.map { mindMin >= $0.mindfulnessGoal } ?? false)
        let standDone = dailyStandAllDone || (progress?.standCompleted ?? 0) >= 1
        let customs = goal?.customActivities.filter { $0.isEnabled } ?? []
        return HStack(spacing: 2) {
            if let g = goal, g.trainingGoal > 0 {
                progressCheckIcon(emoji: "💪", done: trainingDone, color: Color.duoGreen)
            }
            if let g = goal, g.mindfulnessGoal > 0 {
                progressCheckIcon(emoji: "🧘", done: mindDone, color: Color.duoGreen)
            }
            if let g = goal, slot != .midnight, g.standGoal.enabled {
                progressCheckIcon(emoji: "🧍", done: standDone, color: standColor)
            }
            ForEach(customs) { act in
                slotCustomActivityIcon(act: act, progress: progress, slot: slot)
            }
        }
    }

    private func timeSlotRow(for slot: TimeSlot) -> some View {
        let goal = timeSlotManager.settings.goalFor(slot)
        let progress = timeSlotManager.progress.progressFor(slot)
        let gp = timeSlotManager.progress.globalProgress
        let gg = timeSlotManager.settings.globalGoals
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(slot.emoji).font(.subheadline)
                    Text(slot.displayName)
                        .font(.caption).fontWeight(.semibold).foregroundColor(Color.duoDark)
                }
                Text("~\(slot.endHour):00")
                    .font(.system(size: 9 * UIScale.font)).foregroundColor(Color.duoSubtitle)
            }
            .frame(width: 50, alignment: .leading)
            if slot == .midnight {
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
                                    .font(.system(size: 9 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                            }
                            if achieved {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2).foregroundColor(Color.duoGreen)
                            }
                        }
                    } else {
                        HStack(spacing: 3) {
                            Text("😴").font(.caption)
                            Text("データなし").font(.caption2).foregroundColor(Color.duoSubtitle)
                        }
                    }
                }
            } else {
                slotActivityIcons(goal: goal, progress: progress, slot: slot)
            }
            Spacer()
            if slot != .midnight, let goal = goal {
                HStack(spacing: 4) {
                    if goal.logGoal.mealGoal > 0 {
                        // 1日の目標の1/4をその時間帯の完了閾値とし、
                        // 1日合計が目標に達したら全スロット完了扱い
                        // 集計済みプロパティを使用（body内でのreduce()を排除）
                        let totalCalories = healthKit.todayIntakeCalories
                        let slotCalories  = caloriesInSlot(slot)
                        let mealDone = totalCalories >= Double(dailyCalorieGoal)
                            || slotCalories >= Double(dailyCalorieGoal) / 4.0
                        Image(systemName: mealDone ? "fork.knife.circle.fill" : "fork.knife.circle")
                            .font(.title3).foregroundColor(mealDone ? Color.duoGreen : Color(.systemGray4))
                    }
                    if goal.logGoal.drinkGoal > 0 {
                        // 水分も同様に1日の目標の1/4をその時間帯の完了閾値とする
                        // 集計済みプロパティを使用（body内でのreduce()を排除）
                        let totalWater = healthKit.todayIntakeWater
                        let slotWater  = waterInSlot(slot)
                        let drinkDone = totalWater >= Double(dailyWaterGoal)
                            || slotWater >= Double(dailyWaterGoal) / 4.0
                        Image(systemName: drinkDone ? "drop.circle.fill" : "drop.circle")
                            .font(.title3).foregroundColor(drinkDone ? Color.duoBlue : Color(.systemGray4))
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - TodayHistorySection
private struct TodayHistorySection: View {
    let todayExercises: [CompletedExercise]
    let mindfulSessions: [MindfulSession]
    let mealSamples: [DietarySample]
    let waterSamples: [DietarySample]
    let toothbrushingSamples: [Date]
    let bodyMassRecord: BodyMassRecord?
    let latestBodyFatPercentage: Double
    @Binding var expandedSetIds: Set<Int>
    var mindfulGoalMinutes: Int = 0
    var dailyCalorieGoal: Int = 0
    var dailyWaterGoal: Int = 0

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    struct ExerciseSetGroup: Identifiable {
        let id: Int
        let slotLabel: String
        let setNum: Int
        let startTime: Date
        let exercises: [CompletedExercise]
    }

    private var exerciseSets: [ExerciseSetGroup] {
        let sorted = todayExercises.sorted { $0.timestamp < $1.timestamp }
        var rawGroups: [(slotLabel: String, exercises: [CompletedExercise])] = []
        let gap: TimeInterval = 30 * 60
        for ex in sorted {
            let h = Calendar.current.component(.hour, from: ex.timestamp)
            let label: String
            if h < 6 { label = "夜中" } else if h < 10 { label = "朝" }
            else if h < 14 { label = "昼" } else if h < 18 { label = "午後" }
            else { label = "夜" }
            if let last = rawGroups.last,
               last.slotLabel == label,
               let prev = last.exercises.last,
               ex.timestamp.timeIntervalSince(prev.timestamp) < gap {
                rawGroups[rawGroups.count - 1].exercises.append(ex)
            } else {
                rawGroups.append((slotLabel: label, exercises: [ex]))
            }
        }
        var counters: [String: Int] = [:]
        return rawGroups.enumerated().map { idx, g in
            counters[g.slotLabel, default: 0] += 1
            return ExerciseSetGroup(
                id: idx,
                slotLabel: g.slotLabel,
                setNum: counters[g.slotLabel]!,
                startTime: g.exercises.first!.timestamp,
                exercises: g.exercises
            )
        }
    }

    var body: some View {
        let timeFmt = Self.timeFmt
        let sets = exerciseSets
        let toothColor = Color(hex: "#4DB6AC")

        let hasAny = !todayExercises.isEmpty || !mindfulSessions.isEmpty
            || bodyMassRecord != nil || !mealSamples.isEmpty
            || !waterSamples.isEmpty || !toothbrushingSamples.isEmpty

        if hasAny {
            VStack(spacing: 0) {
                Divider().padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 12) {
                    if !todayExercises.isEmpty {
                        sectionGroup(icon: "💪", label: "トレーニング") {
                            VStack(spacing: 4) {
                                ForEach(sets) { set in
                                    setGroupRow(set: set, timeFmt: timeFmt,
                                                isExpanded: expandedSetIds.contains(set.id)) {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            if expandedSetIds.contains(set.id) { expandedSetIds.remove(set.id) }
                                            else { expandedSetIds.insert(set.id) }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if !mindfulSessions.isEmpty {
                        let mindfulDoneMin = Int(mindfulSessions.reduce(0.0) { $0 + $1.durationMinutes }.rounded())
                        let mindfulProg = mindfulGoalMinutes > 0 ? "\(mindfulDoneMin)/\(mindfulGoalMinutes)分" : nil
                        sectionGroup(icon: "🧘", label: "マインドフルネス",
                                     progress: mindfulProg, progressDone: mindfulGoalMinutes > 0 && mindfulDoneMin >= mindfulGoalMinutes) {
                            mindfulnessRows(sessions: mindfulSessions,
                                            color: Color(hex: "#CE93D8"),
                                            timeFmt: timeFmt)
                        }
                    }

                    if let rec = bodyMassRecord {
                        sectionGroup(icon: "⚖️", label: "体重") {
                            HStack(spacing: 8) {
                                Text(timeFmt.string(from: rec.measuredAt))
                                    .font(.system(size: 11 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                                    .frame(width: 38, alignment: .leading)
                                Spacer()
                                if latestBodyFatPercentage > 0 {
                                    Text(String(format: "%.1f%%", latestBodyFatPercentage))
                                        .font(.system(size: 11 * UIScale.font, weight: .semibold))
                                        .foregroundColor(Color.duoSubtitle)
                                }
                                Text(String(format: "%.1f kg", rec.kg))
                                    .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                                    .foregroundColor(Color.duoDark)
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11 * UIScale.font)).foregroundColor(Color.duoGreen)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color(hex: "#1CB0F6").opacity(0.07))
                            .cornerRadius(6)
                        }
                    }

                    if !mealSamples.isEmpty {
                        let mealTotalKcal = Int(mealSamples.reduce(0.0) { $0 + $1.value })
                        let mealProg = dailyCalorieGoal > 0 ? "\(mealTotalKcal)/\(dailyCalorieGoal)kcal" : nil
                        sectionGroup(icon: "🍽️", label: "食事",
                                     progress: mealProg, progressDone: dailyCalorieGoal > 0 && mealTotalKcal >= dailyCalorieGoal) {
                            VStack(spacing: 4) {
                                ForEach(mealSamples) { s in
                                    HStack(spacing: 6) {
                                        Text(timeFmt.string(from: s.startDate))
                                            .font(.system(size: 11 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                                            .frame(width: 38, alignment: .leading)
                                        Spacer()
                                        Text(String(format: "%.0f kcal", s.value))
                                            .font(.system(size: 11 * UIScale.font, weight: .black))
                                            .foregroundColor(Color.duoOrange)
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.duoOrange.opacity(0.06))
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }

                    if !waterSamples.isEmpty {
                        let waterTotalMl = Int(waterSamples.reduce(0.0) { $0 + $1.value })
                        let waterProg = dailyWaterGoal > 0 ? "\(waterTotalMl)/\(dailyWaterGoal)ml" : nil
                        sectionGroup(icon: "💧", label: "水分",
                                     progress: waterProg, progressDone: dailyWaterGoal > 0 && waterTotalMl >= dailyWaterGoal) {
                            VStack(spacing: 4) {
                                ForEach(waterSamples) { s in
                                    HStack(spacing: 6) {
                                        Text(timeFmt.string(from: s.startDate))
                                            .font(.system(size: 11 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                                            .frame(width: 38, alignment: .leading)
                                        Spacer()
                                        Text(String(format: "%.0f ml", s.value))
                                            .font(.system(size: 11 * UIScale.font, weight: .black))
                                            .foregroundColor(Color.duoBlue)
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.duoBlue.opacity(0.06))
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }

                    if !toothbrushingSamples.isEmpty {
                        sectionGroup(icon: "🦷", label: "歯磨き・フロス") {
                            VStack(spacing: 4) {
                                ForEach(Array(toothbrushingSamples.enumerated()), id: \.offset) { _, date in
                                    HStack(spacing: 6) {
                                        Text(timeFmt.string(from: date))
                                            .font(.system(size: 11 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                                            .frame(width: 38, alignment: .leading)
                                        Text("1分歯磨き・フロス")
                                            .font(.system(size: 10 * UIScale.font, weight: .black))
                                            .foregroundColor(toothColor)
                                        Spacer()
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 11 * UIScale.font)).foregroundColor(toothColor)
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(toothColor.opacity(0.07))
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder
    private func sectionGroup<Content: View>(icon: String, label: String,
                                              progress: String? = nil, progressDone: Bool = false,
                                              @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(icon).font(.caption)
                Text(label).font(.caption).fontWeight(.bold).foregroundColor(Color.duoDark)
                Spacer()
                if let prog = progress {
                    Text(prog)
                        .font(.system(size: 10 * UIScale.font, weight: .bold, design: .rounded))
                        .foregroundColor(progressDone ? Color.duoGreen : Color.duoSubtitle)
                }
            }
            content()
        }
    }

    private func setGroupRow(set: ExerciseSetGroup, timeFmt: DateFormatter,
                              isExpanded: Bool, onToggle: @escaping () -> Void) -> some View {
        let totalReps = set.exercises.reduce(0) { $0 + $1.reps }
        let totalXP   = set.exercises.reduce(0) { $0 + $1.points }
        let names     = set.exercises.map { $0.exerciseName }.joined(separator: "・")
        return VStack(spacing: 2) {
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(timeFmt.string(from: set.startTime))
                            .font(.system(size: 11 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                            .frame(width: 38, alignment: .leading)
                        Text("\(set.slotLabel)セット\(set.setNum)")
                            .font(.system(size: 11 * UIScale.font, weight: .black)).foregroundColor(Color.duoGreen)
                        Spacer()
                        Text("\(totalReps) rep")
                            .font(.system(size: 11 * UIScale.font, weight: .black)).foregroundColor(Color.duoGreen)
                        Text("+\(totalXP) XP")
                            .font(.system(size: 10 * UIScale.font)).foregroundColor(Color.duoGold)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                    }
                    Text(names)
                        .font(.system(size: 10 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                        .padding(.leading, 44)
                        .lineLimit(2)
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(Color.duoGreen.opacity(0.08))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(set.exercises, id: \.timestamp) { ex in
                    HStack(spacing: 6) {
                        Spacer().frame(width: 46)
                        Text(ex.exerciseName)
                            .font(.system(size: 11 * UIScale.font, weight: .semibold)).foregroundColor(Color.duoDark)
                        Spacer()
                        Text("\(ex.reps) rep")
                            .font(.system(size: 10 * UIScale.font, weight: .black)).foregroundColor(Color.duoGreen)
                        Text("+\(ex.points) XP")
                            .font(.system(size: 10 * UIScale.font)).foregroundColor(Color.duoGold)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.duoGreen.opacity(0.03))
                    .cornerRadius(4)
                }
            }
        }
    }

    private func mindfulnessRows(sessions: [MindfulSession], color: Color,
                                  timeFmt: DateFormatter) -> some View {
        VStack(spacing: 4) {
            ForEach(sessions) { s in
                HStack(spacing: 6) {
                    Text(timeFmt.string(from: s.startDate))
                        .font(.system(size: 11 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                        .frame(width: 38, alignment: .leading)
                    Spacer()
                    Text("\(Int(s.durationMinutes))分")
                        .font(.system(size: 11 * UIScale.font, weight: .black)).foregroundColor(color)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(color.opacity(0.07))
                .cornerRadius(6)
            }
        }
    }
}

#Preview {
    DashboardView(selectedTab: .constant(0), showRecordMenu: .constant(false))
        .environmentObject(AuthenticationManager.shared)
}
