import SwiftUI
import GoogleMobileAds
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth
import GoogleSignIn
import UserNotifications
import WatchConnectivity

// MainMenuTab, MainMenuTabPreferences, FitingoDeepLink, Notification.Name extensions
// → Views/Components/SharedAppComponents.swift に移動済み

@main
struct kfitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authManager: AuthenticationManager
    // V1: 全タブで共有するシングルトンをアプリルートで一元管理し
    //     EnvironmentObject で配布することで独立サブスクリプションによる
    //     不要な多重再レンダリングを防ぐ
    @StateObject private var healthKit      = HealthKitManager.shared
    @StateObject private var timeSlotMgr   = TimeSlotManager.shared
    @StateObject private var photoLogMgr   = PhotoLogManager.shared
    @StateObject private var dietGoalMgr   = DietGoalManager.shared
    @StateObject private var plusMgr       = PlusManager.shared
    @AppStorage("app.colorScheme") private var colorSchemePref = "light"
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FirebaseApp.configure()
        // オフラインキャッシュを有効化（ネットワーク不調時でもデータを返す）
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings()
        Firestore.firestore().settings = settings
        _authManager = StateObject(wrappedValue: AuthenticationManager.shared)
        // 継続コホート計測: 記録保存を監視して活動日をマーク（1日1回）
        RetentionTracker.shared.startObserving()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isSignedIn {
                    MainTabView()
                        .environmentObject(authManager)
                        .environmentObject(healthKit)
                        .environmentObject(timeSlotMgr)
                        .environmentObject(photoLogMgr)
                        .environmentObject(dietGoalMgr)
                        .environmentObject(plusMgr)
                } else {
                    LoginView()
                        .environmentObject(authManager)
                }
            }
            .preferredColorScheme(colorSchemePref == "dark" ? .dark : .light)
            // セマンティックフォント(.caption/.body等)も全体的に少しだけ大きく。
            // 下限を1段階上げ、アクセシビリティでさらに大きくする設定は尊重する
            .dynamicTypeSize(.xLarge ... .accessibility3)
        }
        // アプリがフォアグラウンドになるたびに Watch へシグナルを送る
        // iOS 17+ では onChange の trailing closure は引数なし。scenePhase を直接参照する。
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                iOSWatchBridge.shared.sendStartWorkoutSignal()
                iOSWatchBridge.shared.notifyWatchAfterDirectRecord()
                Task {
                    async let calorieTopUp: () = authManager.performEndOfDayCalorieTopUpIfNeeded()
                    async let waterTopUp: () = authManager.performEndOfDayWaterTopUpIfNeeded()
                    _ = await (calorieTopUp, waterTopUp)
                    await plusMgr.setup()
                    // Duolingo等からの共有をフォアグラウンド復帰時にも処理する
                    await PendingShareProcessor.shared.processPendingShares()
                }
            } else if scenePhase == .background {
                iOSWatchBridge.shared.notifyWatchAfterDirectRecord()
            }
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    // V1: EnvironmentObject として受け取り fullScreenCover へ橋渡し
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var timeSlotMgr: TimeSlotManager
    @EnvironmentObject var photoLogMgr: PhotoLogManager
    @EnvironmentObject var dietGoalMgr: DietGoalManager
    @EnvironmentObject var plus: PlusManager
    @State private var selectedTab = 0
    @State private var showRecordMenu = false
    @State private var showTrainingTracker = false
    @State private var showMindfulnessWidget = false
    @State private var showPlusView = false
    @State private var isTabBarHidden = false
    @State private var tabBarHideWorkItem: DispatchWorkItem?
    @State private var tabBarRevealWorkItem: DispatchWorkItem?
    @State private var promoBannerDismissed = false
    // DragGesture.onChanged は 60fps で呼ばれるため、タイマーリセットを間引くフラグ
    @State private var revealSchedulePending = false
    @AppStorage(MainMenuTabPreferences.fitVisibleKey)      private var fitVisible      = true
    @AppStorage(MainMenuTabPreferences.goalVisibleKey)     private var goalVisible     = true
    @AppStorage(MainMenuTabPreferences.mindVisibleKey)     private var mindVisible     = false
    @AppStorage(MainMenuTabPreferences.foodVisibleKey)     private var foodVisible     = false
    @AppStorage(MainMenuTabPreferences.tomoVisibleKey)     private var tomoVisible     = false
    @AppStorage(MainMenuTabPreferences.goalingoVisibleKey) private var goalingoVisible = false
    @AppStorage(MainMenuTabPreferences.logVisibleKey)      private var logVisible      = true
    @AppStorage(MainMenuTabPreferences.defaultTabKey) private var defaultTabRaw = MainMenuTab.fit.rawValue
    @AppStorage(MainMenuTabPreferences.orderKey) private var tabOrderRaw = MainMenuTabPreferences.storedOrder(from: MainMenuTabPreferences.defaultOrder)

    // ── 90秒モード（5日未達成ユーザーのデフォルト画面）──
    // 5活動日を達成するまで毎回起動時に90秒モードで開始。
    // 5日達成後はダッシュボードをデフォルトにする。
    // 既存ユーザー（RetentionTracker 計測前から使用 = points>0 & activeDays==0）は除外。
    @AppStorage("simpleMode.enabled")           private var simpleModeEnabled = false
    @AppStorage("simpleMode.installedAt")       private var simpleModeInstalledAt = 0.0  // timeIntervalSince1970
    @AppStorage("simpleMode.selectedModeIndex") private var selectedModeIndex = 0        // LoginView で選択したモード
    /// セッション中に初期化済みかどうか（@State = 再起動でリセット）
    @State private var sessionInitialized = false

    // ── Good Job! 演出の状態 ──
    @State private var taskCelebration: (name: String, emoji: String)? = nil
    @State private var celebrationDismissWork: DispatchWorkItem? = nil

    // body 内で Timer.publish を直接書くと再評価毎にタイマーが再生成されて
    // カウントがリセットされるため、static で1つだけ保持する
    private static let endOfDayTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if simpleModeEnabled {
                simpleModeContent
            } else {
                decoratedContent
            }
        }
            // ── Good Job! 演出（禁酒・勉強・語学などのタスク完了時）──
            .overlay {
                if let celebration = taskCelebration {
                    GoodJobCelebrationView(
                        name: celebration.name,
                        emoji: celebration.emoji,
                        onDismiss: { dismissCelebration() }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .zIndex(99)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dailyTaskCompleted)) { note in
                let name  = note.userInfo?["name"]  as? String ?? "今日の目標"
                let emoji = note.userInfo?["emoji"] as? String ?? "🎯"
                showCelebration(name: name, emoji: emoji)
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestStartTraining)) { _ in
                selectedTab = MainMenuTab.fit.rawValue
                showTrainingTracker = true
                iOSWatchBridge.shared.sendStartWorkoutSignal()
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestStartMindfulness)) { _ in
                showMindfulnessWidget = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .duolingoShareProcessed)) { _ in
                // Duolingo 共有完了 → Tomo タブが有効ならそこへ切り替えて投稿を即表示
                if tomoVisible {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedTab = MainMenuTab.tomo.rawValue
                    }
                }
            }
            .onOpenURL { url in handleDeepLink(url) }
            .onAppear {
                selectedTab = defaultVisibleTab.rawValue
                normalizeSelection()
                checkEndOfDayCalorieTopUp()
                initializeSimpleModeIfNeeded()
                Task {
                    await PendingShareProcessor.shared.processPendingShares()
                }
            }
            .onReceive(Self.endOfDayTimer) { _ in
                checkEndOfDayCalorieTopUp()
            }
            // プロフィール読み込み完了後に 90秒モードの初期判定を行う
            .onReceive(authManager.$userProfile) { _ in
                initializeSimpleModeIfNeeded()
            }
            .onChange(of: fitVisible)      { _, _ in normalizeSelection() }
            .onChange(of: goalVisible)     { _, _ in normalizeSelection() }
            .onChange(of: mindVisible)     { _, _ in normalizeSelection() }
            .onChange(of: foodVisible)     { _, _ in normalizeSelection() }
            .onChange(of: tomoVisible)     { _, _ in normalizeSelection() }
            .onChange(of: goalingoVisible) { _, _ in normalizeSelection() }
            .onChange(of: defaultTabRaw)   { _, _ in normalizeSelection() }
            .onChange(of: tabOrderRaw)     { _, _ in normalizeSelection() }
    }

    // ── Good Job! 演出 ────────────────────────────────────────

    private func showCelebration(name: String, emoji: String) {
        celebrationDismissWork?.cancel()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            taskCelebration = (name: name, emoji: emoji)
        }
        // 2.4秒後に自動で閉じる
        let work = DispatchWorkItem { dismissCelebration() }
        celebrationDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: work)
    }

    private func dismissCelebration() {
        celebrationDismissWork?.cancel()
        celebrationDismissWork = nil
        withAnimation(.easeOut(duration: 0.25)) {
            taskCelebration = nil
        }
    }

    // ── 90秒モード ──────────────────────────────────────────

    /// 起動毎に1回だけ判定: 5日未達成ユーザーはデフォルトで90秒モードを表示する
    private func initializeSimpleModeIfNeeded() {
        guard !sessionInitialized else { return }
        guard let profile = authManager.userProfile else { return } // プロフィール取得後に再判定
        sessionInitialized = true
        if simpleModeInstalledAt == 0 { simpleModeInstalledAt = Date().timeIntervalSince1970 }

        let activeDays = RetentionTracker.shared.localActiveDayCount
        let hasRetentionData = activeDays > 0
        let isPreExistingUser = (profile.totalPoints > 0 || profile.streak > 0) && !hasRetentionData

        if isPreExistingUser {
            // RetentionTracker 導入前から使っている既存ユーザーは強制しない
            simpleModeEnabled = false
        } else {
            // 5日未達成なら90秒モード、達成済みならダッシュボード
            simpleModeEnabled = activeDays < 5
        }
    }

    private var simpleModeContent: some View {
        NinetySecondModeView(
            installedAt: Date(timeIntervalSince1970: simpleModeInstalledAt),
            onStart: {
                showTrainingTracker = true
                iOSWatchBridge.shared.sendStartWorkoutSignal()
            },
            onExit: {
                withAnimation(.easeInOut(duration: 0.3)) { simpleModeEnabled = false }
            },
            initialPage: selectedModeIndex
        )
        .fullScreenCover(isPresented: $showTrainingTracker) {
            ExerciseTrackerView(isPresented: $showTrainingTracker)
                .environmentObject(authManager)
                .environmentObject(healthKit)
                .environmentObject(timeSlotMgr)
        }
    }

    // body を分割してコンパイラの型推論タイムアウトを回避
    private var decoratedContent: some View {
        overlayStack
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .sheet(isPresented: $showPlusView) { PlusView() }
            .fullScreenCover(isPresented: $showRecordMenu) {
                RecordMenuView(isPresented: $showRecordMenu)
                    .environmentObject(authManager)
                    .environmentObject(healthKit)
                    .environmentObject(timeSlotMgr)
            }
            .fullScreenCover(isPresented: $showTrainingTracker) {
                ExerciseTrackerView(isPresented: $showTrainingTracker)
                    .environmentObject(authManager)
                    .environmentObject(healthKit)
                    .environmentObject(timeSlotMgr)
            }
            .fullScreenCover(isPresented: $showMindfulnessWidget) {
                mindfulnessSessionCover
            }
    }

    private var overlayStack: some View {
        ZStack(alignment: .bottom) {
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            if value.translation.height < -20 && !isTabBarHidden {
                                hideTabBarNow()
                            }
                            // タイマーリセットを間引く: 既にスケジュール済みなら再作成しない。
                            // スクロールが止まると revealSchedulePending が false になり
                            // 次の onChanged でタイマーが再スケジュールされる仕組み。
                            if isTabBarHidden && !revealSchedulePending {
                                revealSchedulePending = true
                                scheduleTabBarAutoReveal()
                            }
                        }
                        // onEnded での即時復元を削除: スクロール慣性が残っている間は
                        // バーを隠したままにするため自動復元タイマーに委ねる
                )

            bottomRevealZone

            tabBarRevealHandle

            compactTabBar
                .offset(y: isTabBarHidden ? 76 : 0)
                .opacity(isTabBarHidden ? 0 : 1)
                .allowsHitTesting(!isTabBarHidden)
                .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isTabBarHidden)

            if isTabBarHidden && !plus.isPlus && !promoBannerDismissed {
                RotatingAdBanner(
                    onUpgrade: { revealTabBar(); showPlusView = true },
                    onDismiss: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            promoBannerDismissed = true
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isTabBarHidden)
            }
        }
    }

    // MindfulnessSessionView を独立した computed property に切り出し
    // （複合クロージャがコンパイラの型推論タイムアウトを起こすのを防ぐため）
    private var mindfulnessSessionCover: some View {
        MindfulnessSessionView(
            durationSeconds: 60,
            title: "1分瞑想",
            completedButtonTitle: "Breatheとして保存",
            onComplete: { (startDate: Date, endDate: Date) in
                showMindfulnessWidget = false
                Task {
                    _ = await HealthKitManager.shared.saveMindfulnessSession(
                        startDate: startDate,
                        endDate: endDate,
                        durationSeconds: endDate.timeIntervalSince(startDate),
                        sessionType: "Breathe"
                    )
                }
            }
        )
    }

    @ViewBuilder
    private var mainContent: some View {
        switch selectedTab {
        case 1:  GoalView(selectedTab: $selectedTab, showRecordMenu: $showRecordMenu)
        case 2:  MindView(selectedTab: $selectedTab, showRecordMenu: $showRecordMenu)
        case 3:  FoodView(selectedTab: $selectedTab, showRecordMenu: $showRecordMenu)
        case 4:  NavigationView { SettingsView(selectedTab: $selectedTab) }
        case 5:  MoreView(selectedTab: $selectedTab, showRecordMenu: $showRecordMenu, overflowTabs: overflowPrimaryTabs)
        case 6:  TomoView(selectedTab: $selectedTab, showRecordMenu: $showRecordMenu)
        case 7:  GoalingoView(selectedTab: $selectedTab, showRecordMenu: $showRecordMenu)
        default: NavigationView { DashboardView(selectedTab: $selectedTab, showRecordMenu: $showRecordMenu) }.ignoresSafeArea(.keyboard)
        }
    }

    private var orderedPrimaryTabs: [MainMenuTab] {
        MainMenuTabPreferences.orderedTabs(from: tabOrderRaw)
    }

    private var visiblePrimaryTabs: [MainMenuTab] {
        let visible = orderedPrimaryTabs.filter { isVisible($0) }
        return visible.isEmpty ? [.fit] : visible
    }

    // タブバー: 一次タブ最大5 + SETUP固定 + MORE固定 = 最大7ボタン
    // LOGはMOREへ移動。非表示・並び替え後も可視リストの先頭から最大5つ表示
    private let maxPrimaryInBar = 5

    private var primaryTabsInBar: [MainMenuTab] {
        Array(visiblePrimaryTabs.prefix(maxPrimaryInBar))
    }

    private var overflowPrimaryTabs: [MainMenuTab] {
        Array(visiblePrimaryTabs.dropFirst(maxPrimaryInBar))
    }

    private var defaultVisibleTab: MainMenuTab {
        if let preferred = MainMenuTab(rawValue: defaultTabRaw), isVisible(preferred) {
            return preferred
        }
        return visiblePrimaryTabs.first ?? .fit
    }

    private func isVisible(_ tab: MainMenuTab) -> Bool {
        switch tab {
        case .fit:      return fitVisible
        case .goal:     return goalVisible
        case .mind:     return mindVisible
        case .food:     return foodVisible
        case .tomo:     return tomoVisible
        case .goalingo: return goalingoVisible
        }
    }

    private func normalizeSelection() {
        if selectedTab == 4 || selectedTab == 5 { return }
        guard let current = MainMenuTab(rawValue: selectedTab), isVisible(current) else {
            selectedTab = defaultVisibleTab.rawValue
            return
        }
    }

    // MARK: - Widget Deep Link Handler
    private func handleDeepLink(_ url: URL) {
        guard let link = FitingoDeepLink(url: url) else {
            selectedTab = defaultVisibleTab.rawValue
            return
        }
        switch link {
        case .workout:
            selectedTab = MainMenuTab.fit.rawValue
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showTrainingTracker = true
                iOSWatchBridge.shared.sendStartWorkoutSignal()
            }
        case .mindfulness:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showMindfulnessWidget = true
            }
        case .food:
            selectedTab = MainMenuTab.food.rawValue
        case .mind:
            selectedTab = MainMenuTab.mind.rawValue
        case .goal, .diet:
            selectedTab = MainMenuTab.goal.rawValue
        case .record:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showRecordMenu = true
            }
        case .home:
            selectedTab = defaultVisibleTab.rawValue
        }
    }

    private var bottomRevealZone: some View {
        Color.clear
            .frame(height: 34)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        if value.translation.height < -4 {
                            revealTabBar()
                        } else if value.translation.height > 10 {
                            hideTabBarNow()
                        }
                    }
            )
            .onTapGesture {
                revealTabBar()
            }
            .ignoresSafeArea(edges: .bottom)
    }

    private var tabBarRevealHandle: some View {
        Button {
            revealTabBar()
        } label: {
            Capsule()
                .fill(Color.duoGreen.opacity(0.42))
                .frame(width: 48, height: 5)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.45), lineWidth: 0.7)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 3, y: 1)
                .padding(.horizontal, 28)
                .padding(.top, 14)
                .padding(.bottom, 8)
                .background(Color.black.opacity(0.001))
        }
        .buttonStyle(.plain)
        .opacity(isTabBarHidden ? 1 : 0)
        .scaleEffect(isTabBarHidden ? 1 : 0.82)
        .allowsHitTesting(isTabBarHidden)
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    if value.translation.height < -4 {
                        revealTabBar()
                    }
                }
        )
        .padding(.bottom, 0)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isTabBarHidden)
        .ignoresSafeArea(edges: .bottom)
    }

    private var compactTabBar: some View {
        HStack(spacing: 2) {
            ForEach(primaryTabsInBar) { tab in
                tabBtn(tag: tab.rawValue, icon: tab.icon, label: tab.label)
            }
            tabBtn(tag: 4, icon: "gearshape.fill",       label: "SETUP")
            tabBtn(tag: 5, icon: "ellipsis.circle.fill", label: "MORE...")
        }
        // Dynamic Type をタブバー固定サイズにピン留め（文字を大きくしても折り返しを防ぐ）
        .dynamicTypeSize(.medium)
        .padding(.horizontal, 6)
        .padding(.top, 3)
        .padding(.bottom, 3)
        .background(
            LinearGradient(
                colors: [Color(red: 0.38, green: 0.84, blue: 0.05),
                         Color(red: 0.20, green: 0.66, blue: 0.00)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // 背景のみ下部セーフエリア（ホームインジケータ領域）まで延伸。
            // ボタンはセーフエリア内に留めて黒帯・余白を排除しつつ被りを防ぐ
            .ignoresSafeArea(edges: .bottom)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 6, y: -2)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onEnded { value in
                    if value.translation.height > 12 {
                        hideTabBarNow()
                    }
                    // 下スワイプ以外は表示を維持
                }
        )
    }

    // plusPromoBanner は RotatingAdBanner に統合済み


    private var recordBtn: some View {
        Button {
            revealTabBar()
            showRecordMenu = true
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 28, height: 28)
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    Image(systemName: "plus")
                        .font(.system(size: 15 * UIScale.font, weight: .black))
                        .foregroundColor(Color(red: 0.22, green: 0.68, blue: 0.0))
                }
                Text("LOG")
                    .font(.system(size: 9 * UIScale.font, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func tabBtn(tag: Int, icon: String, label: String) -> some View {
        let isSelected = selectedTab == tag
        return Button {
            selectedTab = tag
            revealTabBar()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundColor(isSelected ? Color(red: 0.22, green: 0.68, blue: 0.0) : .white.opacity(0.88))
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.white : Color.clear)
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func revealTabBar() {
        tabBarHideWorkItem?.cancel()
        tabBarRevealWorkItem?.cancel()
        revealSchedulePending = false
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            isTabBarHidden = false
            promoBannerDismissed = false  // タブバー再表示時にバナーを次回も出せるようリセット
        }
    }

    private func hideTabBarNow() {
        tabBarHideWorkItem?.cancel()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            isTabBarHidden = true
        }
        scheduleTabBarAutoReveal()
    }

    private func scheduleTabBarAutoHide() {
        tabBarHideWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                isTabBarHidden = true
            }
            // オートハイド後はリビールしない（スクロール再開まで待つ）
        }
        tabBarHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: workItem)
    }

    // スクロール停止後の自動復元タイマー。
    // - Free ユーザー: バナー広告を長めに見せるため 4.0s 待ってからメニューを復帰
    // - Plus ユーザー: 広告なし → 0.6s で素早く復帰
    // 下端スワイプ or ハンドルタップによる手動復元は revealTabBar() で即時実行される。
    private func scheduleTabBarAutoReveal() {
        tabBarRevealWorkItem?.cancel()
        let delay: Double = plus.isPlus ? 2.0 : 5.0
        let workItem = DispatchWorkItem { [self] in
            guard isTabBarHidden else { revealSchedulePending = false; return }
            revealSchedulePending = false
            revealTabBar()
        }
        tabBarRevealWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func checkEndOfDayCalorieTopUp() {
        Task {
            async let calorieTopUp: () = authManager.performEndOfDayCalorieTopUpIfNeeded()
            async let waterTopUp: () = authManager.performEndOfDayWaterTopUpIfNeeded()
            _ = await (calorieTopUp, waterTopUp)
        }
    }
}

// MARK: - GoodJobCelebrationView
// 禁酒・勉強・語学などその日のタスクを完了した時に表示する称賛オーバーレイ。
// TimeSlotManager が .dailyTaskCompleted を post → MainTabView の overlay が表示する。

struct GoodJobCelebrationView: View {
    let name: String
    let emoji: String
    let onDismiss: () -> Void

    @State private var mascotScale: CGFloat = 0.5
    @State private var praiseLine: String = GoodJobCelebrationView.praises.randomElement() ?? ""

    private static let praises = [
        "その調子！継続は力なり💪",
        "小さな一歩が大きな変化に！",
        "今日もえらい！明日も会おうね",
        "できたね！この積み重ねが実績になる",
        "ナイス！やる気が続く人はこうやって作られる",
        "完璧！今日のあなたは昨日より強い",
    ]

    var body: some View {
        ZStack {
            // 背景（タップで即閉じ）
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 14) {
                Image("fitingo_button_mascot")
                    .resizable().scaledToFit()
                    .frame(width: 110, height: 110)
                    .scaleEffect(mascotScale)

                Text("Good Job!")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundColor(Color.duoGreen)

                HStack(spacing: 6) {
                    Text(emoji).font(.system(size: 22))
                    Text("\(name) 完了！")
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .foregroundColor(.duoDark)
                }

                Text(praiseLine)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.duoSubtitle)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.duoGreen.opacity(0.35), radius: 24, y: 10)
            )
            .padding(.horizontal, 40)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.55).delay(0.05)) {
                mascotScale = 1.0
            }
        }
    }
}

// HeaderNavigationMenu, UserStatusSheet
// → Views/Components/SharedAppComponents.swift に移動済み


// MARK: - RotatingAdBanner
// Free ユーザーがタブバーを隠している間に表示される回転バナー広告。
// 表示種別は 6 秒ごとに自動切替。将来的に Google AdMob バナーを挿入できるスロットを確保。
//
// ── AdMob 有効化手順 ──────────────────────────────────────────────────
// 1. Podfile に pod 'Google-Mobile-Ads-SDK' を追加して pod install
// 2. Info.plist に GADApplicationIdentifier（AdMob App ID）を追加
// 3. このファイル冒頭に `import GoogleMobileAds` を追加
// 4. AdSlot.admob の case と GADBannerViewRepresentable のコメントを解除
// 5. adUnitID を本番 Ad Unit ID（例: ca-app-pub-xxxx/yyyy）に変更
// ────────────────────────────────────────────────────────────────────

// 表示順: Plus(1/3) → AdMob(1/3) → AdMob(1/3) のサイクル
private enum AdSlot: CaseIterable, Hashable {
    case plus
    case admob1
    case admob2
}

struct RotatingAdBanner: View {
    var onUpgrade: () -> Void = {}
    var onDismiss: () -> Void = {}

    @State private var slotIndex = 0
    private let slots = AdSlot.allCases
    // body 再評価毎の Timer 再生成（=ローテーションのリセット）を防ぐため static で保持
    private static let rotateTimer = Timer.publish(every: 12, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // .id() を外して View の再生成（=GADBannerView.makeUIView + banner.load）を防ぐ。
            // スロット種別が同じ場合（admob1→admob2）は同一インスタンスを使い回す。
            slotView(slots[slotIndex % slots.count])
                .id(slots[slotIndex % slots.count])   // slotIndex ではなく slot の種別で id 管理
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
                .animation(.easeInOut(duration: 0.35), value: slotIndex)

            // 閉じるボタン
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .onReceive(Self.rotateTimer) { _ in
            withAnimation { slotIndex += 1 }
        }
    }

    // MARK: - 各スロットのビュー
    @ViewBuilder
    private func slotView(_ slot: AdSlot) -> some View {
        switch slot {
        case .plus:
            plusBanner
        case .admob1, .admob2:
            GADBannerViewRepresentable(adUnitID: "ca-app-pub-5882080850213183/5404288349")
                .frame(height: 50)
                .background(Color.white)
        }
    }

    // ── Plus アップグレードバナー ──
    private var plusBanner: some View {
        HStack(spacing: 10) {
            PlusBadge(size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Fitingo Plus で全機能を解放")
                    .font(.system(size: 12, weight: .black))
                    .foregroundColor(Color(hex: "#FF8C00"))
                Text("AI解析・Kindle本読み放題・広告なし")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#994D00"))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button {
                onUpgrade()
            } label: {
                Text("詳細")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color(hex: "#FF8C00"))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [Color(hex: "#FFF5CC"), Color(hex: "#FFE580")],
                startPoint: .leading, endPoint: .trailing
            )
            .ignoresSafeArea(edges: .bottom)
        )
        .overlay(Rectangle().fill(Color(hex: "#FFD700").opacity(0.4)).frame(height: 1), alignment: .top)
        .onTapGesture { onUpgrade() }
    }

}

// MARK: - AdMob バナービュー

struct GADBannerViewRepresentable: UIViewRepresentable {
    let adUnitID: String

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = adUnitID
        banner.rootViewController = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first?.rootViewController
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 通知デリゲートを自身に設定（フォアグラウンドでも通知を表示するため）
        UNUserNotificationCenter.current().delegate = self

        // 通知権限をリクエストし、許可後に全通知をスケジュール
        Task { @MainActor in
            let granted = await NotificationManager.shared.requestPermission()
            if granted {
                NotificationManager.shared.scheduleAllDaily()
                HabitStackManager.shared.rescheduleAll()
            }
        }

        // Apple Watch → iPhone ブリッジを起動
        _ = iOSWatchBridge.shared
        // アプリ起動時に現在の Plus 状態を Watch へ即時送信
        iOSWatchBridge.shared.sendPlusStatusToWatch(isPlus: PlusManager.shared.isPlus)

        return true
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool { return GIDSignIn.sharedInstance.handle(url) }

    // フォアグラウンド中でも通知バナーを表示する
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    // 通知タップ時のハンドリング
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        // アクションボタンがタップされた場合
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            if let action = userInfo["action"] as? String, action == "startWorkout" {
                dlog("[AppDelegate] 🏋️ Notification tapped - sending signal to Watch")
                iOSWatchBridge.shared.sendStartWorkoutSignal()
            }
        }

        completionHandler()
    }
}

// MARK: - 90秒モード種別

/// FIT / FOOD / EDU それぞれの 90 秒モードを表す。
enum NinetySecondModeType: Int, CaseIterable {
    case fit  = 0
    case food = 1
    case edu  = 2
    case diet = 3

    /// 見出し「今度こそ、続く」の下に表示するモード名（かっこ書き）
    var modeName: String {
        switch self {
        case .fit:  return "筋トレ"
        case .food: return "食事ログ"
        case .edu:  return "語学"
        case .diet: return "ダイエット"
        }
    }

    /// 下部に表示するシンプルな案内メッセージ（ボタンではなくプレーンテキスト）
    var simpleActionMessage: String {
        switch self {
        case .fit:  return "90秒始める、それだけ"
        case .diet: return "測る、それだけ"
        case .food: return "食事を撮る、それだけ"
        case .edu:  return "Fitingoを送る、それだけ"
        }
    }

    var accentColor: Color {
        switch self {
        case .fit:  return Color.duoGreen
        case .food: return Color.duoOrange
        case .edu:  return Color.duoBlue
        case .diet: return Color.duoPurple
        }
    }

    var backgroundColors: [Color] {
        switch self {
        case .fit:  return [Color(hex: "#F0FFF4"), Color.white]
        case .food: return [Color(hex: "#FFF8F0"), Color.white]
        case .edu:  return [Color(hex: "#EFF6FF"), Color.white]
        case .diet: return [Color(hex: "#F8F0FF"), Color.white]
        }
    }

    var illustrationEmoji: String {
        switch self {
        case .fit:  return "💪"
        case .food: return "🍱"
        case .edu:  return "📚"
        case .diet: return "⚖️"
        }
    }
}

// MARK: - DIET 90秒 体重記録シート

/// DIET モードのボタンから表示する体重記録シート。
/// 手入力 / Withings連携 / 写真アップロード の3択を提供する。
struct Diet90sWeightSheet: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @Environment(\.dismiss) private var dismiss

    let onPhoto: () -> Void

    @State private var manualInput: String = ""
    @State private var isSaving = false
    @State private var savedMessage: String? = nil
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {

                // ── ヘッダー ──────────────────────────────────────────
                VStack(spacing: 6) {
                    Text("⚖️").font(.system(size: 44))
                    Text("体重を記録")
                        .font(.title3).fontWeight(.black)
                        .foregroundColor(Color.duoDark)
                    Text("Apple Health に記録されると自動で完了判定されます")
                        .font(.system(size: 11))
                        .foregroundColor(.duoSubtitle)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 20)
                .padding(.bottom, 16)

                Divider()

                ScrollView {
                    VStack(spacing: 12) {

                        // ── 手入力 ────────────────────────────────────
                        VStack(alignment: .leading, spacing: 8) {
                            Label("手入力", systemImage: "keyboard")
                                .font(.subheadline.bold())
                                .foregroundColor(.duoPurple)

                            HStack(spacing: 10) {
                                TextField("例: 65.4", text: $manualInput)
                                    .keyboardType(.decimalPad)
                                    .focused($inputFocused)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 11)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                                    .font(.system(size: 20, weight: .bold, design: .rounded))

                                Text("kg")
                                    .font(.headline)
                                    .foregroundColor(.duoSubtitle)

                                Button {
                                    saveManualWeight()
                                } label: {
                                    if isSaving {
                                        ProgressView()
                                            .frame(width: 60, height: 42)
                                    } else {
                                        Text("保存")
                                            .font(.headline.bold())
                                            .foregroundColor(.white)
                                            .frame(width: 60, height: 42)
                                            .background(Capsule().fill(Color.duoPurple))
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(isSaving || manualInputKg == nil)
                            }

                            if let msg = savedMessage {
                                Text(msg)
                                    .font(.caption.bold())
                                    .foregroundColor(msg.contains("✅") ? Color.duoGreen : Color.duoRed)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.duoPurple.opacity(0.06)))
                        .padding(.horizontal, 16)

                        // ── Withings 連携 ─────────────────────────────
                        Button { openWithings() } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "scalemass.fill")
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Withingsを開く")
                                        .font(.headline).fontWeight(.black)
                                    Text("スマート体重計と連携して計測")
                                        .font(.caption)
                                        .opacity(0.8)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.subheadline)
                            }
                            .foregroundColor(Color(hex: "#00A6A6"))
                            .padding(.horizontal, 20).padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 16)
                                .fill(Color(hex: "#00A6A6").opacity(0.08)))
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)

                        // ── 写真アップロード ───────────────────────────
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                onPhoto()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "camera.fill")
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("写真で記録する")
                                        .font(.headline).fontWeight(.black)
                                    Text("体型写真を撮って変化を記録")
                                        .font(.caption)
                                        .opacity(0.8)
                                }
                                Spacer()
                            }
                            .foregroundColor(Color.duoBlue)
                            .padding(.horizontal, 20).padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 16)
                                .fill(Color.duoBlue.opacity(0.08)))
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)

                        Spacer().frame(height: 20)
                    }
                    .padding(.top, 12)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .font(.subheadline.bold())
                        .foregroundColor(.duoPurple)
                }
            }
        }
        .onAppear { inputFocused = true }
    }

    private var manualInputKg: Double? {
        let s = manualInput.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let v = Double(s), v > 20, v < 300 else { return nil }
        return v
    }

    private func saveManualWeight() {
        guard let kg = manualInputKg else { return }
        isSaving = true
        inputFocused = false
        Task {
            let ok = await healthKit.saveBodyMass(kg: kg)
            await MainActor.run {
                isSaving = false
                savedMessage = ok ? "✅ \(String(format: "%.1f", kg)) kg を記録しました" : "⚠️ 保存に失敗しました"
                if ok {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() }
                }
            }
        }
    }

    private func openWithings() {
        dismiss()
        let schemes = ["wiscale2://", "healthmate://", "withings://"]
        let appStore = URL(string: "https://apps.apple.com/app/id542701020")!
        if let url = schemes.compactMap({ URL(string: $0) })
                            .first(where: { UIApplication.shared.canOpenURL($0) }) {
            UIApplication.shared.open(url)
        } else {
            UIApplication.shared.open(appStore)
        }
    }
}

// MARK: - 90秒モード 共通カードビュー

struct NinetySecondModeCard: View {
    let mode: NinetySecondModeType
    let doneToday: Bool
    let streak: Int
    let activeDays: Int
    let graduated: Bool
    /// FOOD モード用：直近フォト（外から注入）
    var photoThumbnails: [UIImage] = []
    let onAction: () -> Void
    let onExit: () -> Void

    @AppStorage("ninety.topWindowVisible") private var topWindowVisible: Bool = true
    @State private var pulseScale: CGFloat = 1.0
    @State private var showBurst = false
    @State private var slideIndex: Int = 0

    private var accent: Color { mode.accentColor }

    // MARK: body
    var body: some View {
        ZStack {
            LinearGradient(colors: mode.backgroundColors, startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Fitingo ロゴマーク ─────────────────────────────────────
                Image("fitingo_fire")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .padding(.top, 12)

                Spacer().frame(height: 10)

                // ── 連続日数（あと◯日で全開放）＋ 5日チェックマーク ─────────
                streakHeader

                Spacer().frame(height: 18)

                // ── 大見出し：今度こそ、続く／「モード名」────────────────
                VStack(spacing: 2) {
                    Text("今度こそ、続く")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundColor(accent)
                        .shadow(color: accent.opacity(0.15), radius: 4, y: 2)
                    Text("「\(mode.modeName)」")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundColor(accent.opacity(0.85))
                }
                .multilineTextAlignment(.center)

                Spacer().frame(height: 16)

                // ── コンテンツエリア（FIT/DIET のみ表示。FOOD/EDU は非表示）─────
                if mode == .fit || mode == .diet {
                    if topWindowVisible {
                        ZStack(alignment: .topTrailing) {
                            contentArea
                            // 隠すボタン
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    topWindowVisible = false
                                }
                            } label: {
                                Image(systemName: "chevron.up.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.white, accent.opacity(0.6))
                                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    } else {
                        // 表示ボタン（コンパクト）
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                topWindowVisible = true
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.down.circle.fill")
                                    .font(.system(size: 16))
                                Text("動画を表示")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(accent)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Capsule().fill(accent.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }

                Spacer().frame(height: 14)

                // ── メインアクションボタン ─────────────────────────────────
                mainActionButton

                Spacer().frame(height: 14)

                // ── シンプルな案内メッセージ（ボタンではなくプレーンテキスト）───
                if doneToday {
                    // 実施後はシンプルな完了メッセージだけ（中心ボタンでもう1回できる）
                    Text("✅ 今日は完了！")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(.duoDark)
                } else {
                    Text(mode.simpleActionMessage)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(.duoDark)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }

                Spacer()

                if graduated {
                    Button(action: onExit) {
                        HStack(spacing: 6) {
                            Text("全機能を開く")
                                .font(.system(size: 15, weight: .black))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .black))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 28).padding(.vertical, 12)
                        .background(Capsule().fill(Color.duoOrange))
                        .shadow(color: Color.duoOrange.opacity(0.3), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 8)
                }

                // 卒業後は「全機能を開く」ボタンがあるためリンクは非表示（表示の重複を避ける）
                if !graduated {
                    Button(action: onExit) {
                        Text("すべての機能を見る")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.duoSubtitle)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 20)
                } else {
                    Spacer().frame(height: 20)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulseScale = 1.04
            }
        }
        // FOOD: 5秒ごとにフォトスライド
        .task(id: "photoSlide_\(mode.rawValue.description)") {
            // FOOD と EDU どちらも 5 秒スライド
            guard (mode == .food || mode == .edu), !photoThumbnails.isEmpty else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !photoThumbnails.isEmpty else { continue }
                withAnimation(.easeInOut(duration: 0.6)) {
                    slideIndex = (slideIndex + 1) % photoThumbnails.count
                }
            }
        }
    }

    // MARK: コンテンツエリア（モード別）
    @ViewBuilder private var contentArea: some View {
        switch mode {
        case .fit:
            // ワークアウトGIFがそのままアクショントリガー
            Button(action: triggerAction) {
                GIFAnimationView(gifName: "fitingo_workout")
                    .frame(width: 190, height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .scaleEffect(showBurst ? 0.92 : pulseScale)
                    .shadow(color: accent.opacity(0.25), radius: 16, y: 8)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulseScale)

        case .food:
            // 直近フォトのスライドショー。窓全体がアクショントリガー（スワイプはページ送り）
            ZStack {
                if photoThumbnails.isEmpty {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(accent.opacity(0.08))
                        .frame(maxWidth: .infinity)
                        .frame(height: 156)
                        .overlay(Text("📷").font(.system(size: 64)))
                } else {
                    TabView(selection: $slideIndex) {
                        ForEach(Array(photoThumbnails.enumerated()), id: \.offset) { i, img in
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 156)
                                .clipped()
                                .tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 156)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    // スライドカウンターインジケータ
                    .overlay(alignment: .bottomTrailing) {
                        HStack(spacing: 4) {
                            ForEach(0..<photoThumbnails.count, id: \.self) { i in
                                Circle()
                                    .fill(i == slideIndex ? Color.white : Color.white.opacity(0.4))
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .contentShape(Rectangle())
            .scaleEffect(showBurst ? 0.97 : 1.0)
            .onTapGesture { triggerAction() }

        case .edu:
            // 直近 Duolingo 投稿のスライドショー（FOOD と同じ構造）
            ZStack {
                if photoThumbnails.isEmpty {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(accent.opacity(0.08))
                        .frame(maxWidth: .infinity)
                        .frame(height: 156)
                        .overlay(Text("📚").font(.system(size: 64)))
                } else {
                    TabView(selection: $slideIndex) {
                        ForEach(Array(photoThumbnails.enumerated()), id: \.offset) { i, img in
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 156)
                                .clipped()
                                .tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 156)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(alignment: .bottomTrailing) {
                        HStack(spacing: 4) {
                            ForEach(0..<photoThumbnails.count, id: \.self) { i in
                                Circle()
                                    .fill(i == slideIndex ? Color.white : Color.white.opacity(0.4))
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .padding(8)
                    }
                }
            }

        case .diet:
            // Fitingo ボタン画像がそのままアクショントリガー（旧: ⚖️の静的ボックス）
            Button(action: triggerAction) {
                Image("fitingo_button_mascot")
                    .resizable().scaledToFit()
                    .frame(width: 190, height: 190)
                    .scaleEffect(showBurst ? 0.92 : pulseScale)
                    .shadow(color: accent.opacity(0.25), radius: 16, y: 8)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulseScale)
        }
    }

    // MARK: メインアクションボタン（モード別: FOOD/EDUのみ。FIT/DIETはcontentAreaに統合済み）
    @ViewBuilder private var mainActionButton: some View {
        switch mode {
        case .fit, .diet:
            EmptyView()

        case .food:
            // AI食事フォトログ（Routine の photoLogButton スタイル）
            Button(action: triggerAction) {
                HStack(spacing: 16) {
                    // 最近の写真サムネイル or カメラアイコン
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.22))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.55), lineWidth: 1.2)
                            )
                            .frame(width: 76, height: 76)
                        if let firstPhoto = photoThumbnails.first {
                            Image(uiImage: firstPhoto)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 76, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        } else {
                            VStack(spacing: 3) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("AI")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundColor(.white.opacity(0.95))
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("📸 AI食事フォトログ")
                            .font(.system(size: 18, weight: .black))
                            .foregroundColor(.white)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        if photoThumbnails.isEmpty {
                            Text("写真を撮ってAIカロリー計算")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white.opacity(0.92))
                        } else {
                            Text("最近の記録 \(photoThumbnails.count)件")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.92))
                        }
                    }
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 22)
                .background(
                    Color.instagramGradient
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: Color.orange.opacity(0.35), radius: 14, y: 6)
                .padding(.horizontal, 20)
                .scaleEffect(showBurst ? 0.96 : 1.0)
            }
            .buttonStyle(.plain)

        case .edu:
            // Duolingo 記録ボタン（例文作成 + 発話）
            Button(action: triggerAction) {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.22))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.55), lineWidth: 1.2)
                            )
                            .frame(width: 76, height: 76)
                        if let firstThumb = photoThumbnails.first {
                            Image(uiImage: firstThumb)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 76, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        } else {
                            Text("📚")
                                .font(.system(size: 38))
                        }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("📚 Duolingo記録")
                            .font(.system(size: 18, weight: .black))
                            .foregroundColor(.white)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        if photoThumbnails.isEmpty {
                            Text("スクショをアップしてAI例文 & 発話")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white.opacity(0.92))
                        } else {
                            Text("最近の記録 \(photoThumbnails.count)件")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.92))
                        }
                    }
                    Spacer()
                    Image(systemName: "waveform")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 22)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "#1CB0F6"), Color(hex: "#0D8EC9")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: Color.duoBlue.opacity(0.4), radius: 14, y: 6)
                .padding(.horizontal, 20)
                .scaleEffect(showBurst ? 0.96 : 1.0)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 連続日数（あと◯日で全開放）＋ 5日チェックマーク（ヘッダー用・1行＋ドット）
    private var streakHeader: some View {
        VStack(spacing: 10) {
            // Fitingo ◯日連続（あと◯日で全開放）
            Group {
                HStack(spacing: 6) {
                    Image("fitingo_mascot")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 24, height: 24)
                        .clipShape(Circle())
                    Text("\(streak)日連続")
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(.duoDark)
                }
                +
                Text(graduated ? "　🎉全機能開放中！" : "（あと\(max(0, 5 - activeDays))日で全開放）")
                    .font(.system(size: 20, weight: .black))
                    .foregroundColor(.duoDark)
                +
                Text(graduated ? "　🎉全機能開放中！" : "（あと\(max(0, 5 - activeDays))日で全開放）")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(graduated ? .duoOrange : Color(.secondaryLabel))
            }
            .multilineTextAlignment(.center)
            // ドット
            HStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { i in
                    ZStack {
                        Circle()
                            .fill(i < activeDays ? accent : Color(.systemGray5))
                            .frame(width: 20, height: 20)
                            .shadow(color: i < activeDays ? accent.opacity(0.4) : .clear, radius: 4, y: 2)
                        if i < activeDays {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
        }
    }

    // MARK: トリガーヘルパー
    private func triggerAction() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { showBurst = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            showBurst = false
            onAction()
        }
    }
}

// MARK: - 90秒モードハブ（FIT / DIET / FOOD / EDU を横スワイプで切替）
// 5タブ・機能説明を見せず「今日の90秒」だけに絞る。初回起動から60秒以内に
// 最初の1セットを完了させることが目的（docs/SamBezThieMuskJobs_plan.md Musk 案2 / Jobs 5-4）。
// 5活動日で全機能を開放。右下のリンクからいつでも全機能に切り替え可能。

struct NinetySecondModeView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var timeSlotMgr: TimeSlotManager
    @StateObject private var photoLogMgr = PhotoLogManager.shared
    @StateObject private var eduLogMgr   = EduLogManager.shared
    let installedAt: Date
    let onStart: () -> Void
    let onExit: () -> Void
    /// 設定画面からのプレビュー表示時は true（firstSetSeconds 計測を行わない）
    var isPreview: Bool = false
    /// LoginView で選択したモードのインデックス（0=FIT, 1=DIET, 2=FOOD, 3=EDU）
    var initialPage: Int = 0

    @State private var selectedPage: Int = 0
    @State private var showFoodLog    = false
    @State private var showEduLog     = false
    @State private var showDietSheet  = false
    @State private var showDietPhoto  = false
    @State private var showGraduationCard = false
    @AppStorage("ninety.graduationCardShown") private var graduationCardShown = false

    /// 直近 5 件の食事フォト（スライド用に高解像度）
    private var recentFoodThumbnails: [UIImage] {
        photoLogMgr.history.prefix(5).compactMap { $0.thumbnail }
    }
    /// 直近 5 件の EDU（Duolingo）投稿サムネイル
    private var recentEduThumbnails: [UIImage] {
        eduLogMgr.history.prefix(5).compactMap { $0.thumbnail }
    }

    private var todayTraining: Int {
        TimeSlot.allCases.reduce(0) { $0 + (timeSlotMgr.progress.progressFor($1)?.trainingCompleted ?? 0) }
    }
    private var doneToday: Bool  { todayTraining > 0 }
    private var activeDays: Int  { RetentionTracker.shared.localActiveDayCount }
    private var graduated: Bool  { activeDays >= 5 }
    private var streak: Int      { max(authManager.userProfile?.streak ?? 0, doneToday ? 1 : 0) }

    // モード選択カスタムドット（TabViewの標準ドットとボタンの重なりを防ぐため独立配置）
    private var modePageDots: some View {
        HStack(spacing: 8) {
            ForEach(NinetySecondModeType.allCases, id: \.rawValue) { m in
                let isSelected = m.rawValue == selectedPage
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected
                          ? NinetySecondModeType(rawValue: selectedPage)!.accentColor
                          : Color(.systemGray4))
                    .frame(width: isSelected ? 28 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.25), value: selectedPage)
                    .onTapGesture { withAnimation { selectedPage = m.rawValue } }
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    var body: some View {
        VStack(spacing: 0) {
            modePageDots

            TabView(selection: $selectedPage) {
            // ── FIT ────────────────────────────────────────────
            NinetySecondModeCard(
                mode: .fit,
                doneToday: doneToday,
                streak: streak,
                activeDays: activeDays,
                graduated: graduated,
                onAction: onStart,
                onExit: onExit
            )
            .tag(0)

            // ── DIET ───────────────────────────────────────────
            NinetySecondModeCard(
                mode: .diet,
                doneToday: doneToday,
                streak: streak,
                activeDays: activeDays,
                graduated: graduated,
                onAction: { showDietSheet = true },
                onExit: onExit
            )
            .tag(1)

            // ── FOOD ───────────────────────────────────────────
            NinetySecondModeCard(
                mode: .food,
                doneToday: doneToday,
                streak: streak,
                activeDays: activeDays,
                graduated: graduated,
                photoThumbnails: recentFoodThumbnails,
                onAction: { showFoodLog = true },
                onExit: onExit
            )
            .tag(2)

            // ── EDU ────────────────────────────────────────────
            NinetySecondModeCard(
                mode: .edu,
                doneToday: doneToday,
                streak: streak,
                activeDays: activeDays,
                graduated: graduated,
                photoThumbnails: recentEduThumbnails,
                onAction: { showEduLog = true },
                onExit: onExit
            )
            .tag(3)
            }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .task { await timeSlotMgr.loadTodayProgress() }
        .onReceive(NotificationCenter.default.publisher(for: .timeSlotProgressDidSave)) { _ in
            if !isPreview && todayTraining > 0 {
                RetentionTracker.shared.recordFirstSetLatency(installedAt: installedAt)
            }
        }
        // 選択したモードのページから開始
        .onAppear {
            selectedPage = initialPage
            checkGraduationCard()
        }
        .onChange(of: graduated) { _, newValue in if newValue { checkGraduationCard() } }
        .sheet(isPresented: $showGraduationCard) {
            GraduationShareSheet(onExit: onExit)
        }
        // ── FOOD: フォトログを全画面表示 ──────────────────────────
        .fullScreenCover(isPresented: $showFoodLog) {
            PhotoLogView()
        }
        // ── EDU: 語学フォトログシートを表示 ──────────────────────
        .sheet(isPresented: $showEduLog) {
            EduPhotoLogSheet(
                nodeEmoji: "📚",
                nodeName: "語学",
                onComplete: { _, _, _, _ in
                    showEduLog = false
                }
            )
        }
        // ── DIET: 体重記録シートを表示 ────────────────────────────
        .sheet(isPresented: $showDietSheet) {
            Diet90sWeightSheet(
                onPhoto: { showDietPhoto = true }
            )
            .environmentObject(HealthKitManager.shared)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        // ── DIET 写真: 体重フォトログ ──────────────────────────────
        .sheet(isPresented: $showDietPhoto) {
            EduPhotoLogSheet(
                nodeEmoji: "⚖️",
                nodeName: "体重ログ",
                onComplete: { _, _, _, _ in
                    showDietPhoto = false
                }
            )
        }
        } // VStack
    }

    private func checkGraduationCard() {
        guard graduated, !graduationCardShown, !isPreview else { return }
        graduationCardShown = true
        // 少し遅延してシートを表示（TabView 初期化と競合しないよう）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            showGraduationCard = true
        }
    }
}

// MARK: - 5日達成 共有カード シート

/// 5日連続達成時に一度だけ表示される共有シート。
/// カード画像を ImageRenderer で生成し UIActivityViewController で共有する。
struct GraduationShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onExit: () -> Void

    @State private var showShareVC = false
    @State private var renderedImage: UIImage? = nil

    private let lpURL = "https://kfitapp.web.app"

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer().frame(height: 4)

                cardView
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(color: .black.opacity(0.10), radius: 20, y: 8)
                    .padding(.horizontal, 28)

                Text("仲間に広めて、一緒に始めよう")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.duoSubtitle)

                Button {
                    renderAndShare()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .bold))
                        Text("SNSでシェアする")
                            .font(.system(size: 17, weight: .black))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Color(hex: "#58CC02")))
                    .shadow(color: Color(hex: "#46A302").opacity(0.35), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 28)

                Button {
                    dismiss()
                    onExit()
                } label: {
                    Text("全機能を開く →")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.duoOrange)
                        .underline()
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .navigationTitle("5日達成！🎉")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
        .sheet(isPresented: $showShareVC) {
            if let img = renderedImage {
                GradShareActivityVC(items: [img, shareText])
            }
        }
    }

    private var shareText: String {
        "5日続けました！\n今度こそ、続く。\n#Fitingo #今度こそ続く\n\(lpURL)"
    }

    // MARK: カードビュー（ImageRenderer でも同じビューを使用）

    private var cardView: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#F0FFF4"), Color(hex: "#DCFCE7")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(spacing: 16) {
                Text("🎉")
                    .font(.system(size: 64))
                VStack(spacing: 6) {
                    Text("5日、続きました。")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "#1f1f1f"))
                    Text("今度こそ、続く。")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "#58CC02"))
                }
                HStack(spacing: 14) {
                    ForEach(["💪", "⚖️", "🍱", "📚"], id: \.self) { e in
                        Text(e).font(.system(size: 28))
                    }
                }
                .padding(.top, 4)
                Divider().padding(.horizontal, 32)
                VStack(spacing: 2) {
                    Text("Fitingo")
                        .font(.system(size: 15, weight: .black))
                        .foregroundColor(Color(hex: "#58CC02"))
                    Text("kfitapp.web.app")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#999999"))
                }
            }
            .padding(36)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(4/5, contentMode: .fit)
    }

    private func renderAndShare() {
        let renderer = ImageRenderer(
            content: cardView.frame(width: 360, height: 450)
        )
        renderer.scale = 3.0
        guard let img = renderer.uiImage else { return }
        renderedImage = img
        showShareVC = true
    }
}

private struct GradShareActivityVC: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
