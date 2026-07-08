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
                    await authManager.performEndOfDayCalorieTopUpIfNeeded()
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

    // ── 90秒モード（新規ユーザー向け 1 画面オンボーディング）──
    // 5タブを見せず「今日の90秒」だけの画面で開始し、7活動日で全機能を開放する。
    // 既存ユーザー（XP/ストリークあり）には初期化時に無効化する。
    @AppStorage("simpleMode.enabled")     private var simpleModeEnabled = false
    @AppStorage("simpleMode.initialized") private var simpleModeInitialized = false
    @AppStorage("simpleMode.installedAt") private var simpleModeInstalledAt = 0.0  // timeIntervalSince1970

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

    // ── 90秒モード ──────────────────────────────────────────

    /// 初回起動時のみ判定: 実績のない新規ユーザーだけ 90秒モードで開始する
    private func initializeSimpleModeIfNeeded() {
        guard !simpleModeInitialized else { return }
        guard let profile = authManager.userProfile else { return } // プロフィール取得後に再判定
        simpleModeInitialized = true
        simpleModeInstalledAt = Date().timeIntervalSince1970
        let isExistingUser = profile.totalPoints > 0 || profile.streak > 0
            || RetentionTracker.shared.localActiveDayCount > 0
        simpleModeEnabled = !isExistingUser
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
            }
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
            await authManager.performEndOfDayCalorieTopUpIfNeeded()
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

// MARK: - 90秒モード（新規ユーザー向け 1 画面オンボーディング）
// 5タブ・機能説明を見せず「今日の90秒」だけに絞る。初回起動から60秒以内に
// 最初の1セットを完了させることが目的（docs/SamBezThieMuskJobs_plan.md Musk 案2 / Jobs 5-4）。
// 7活動日で全機能を開放。右下のリンクからいつでも全機能に切り替え可能。

struct NinetySecondModeView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var timeSlotMgr: TimeSlotManager
    let installedAt: Date
    let onStart: () -> Void
    let onExit: () -> Void

    private var todayTraining: Int {
        TimeSlot.allCases.reduce(0) { $0 + (timeSlotMgr.progress.progressFor($1)?.trainingCompleted ?? 0) }
    }
    private var doneToday: Bool { todayTraining > 0 }
    private var activeDays: Int { RetentionTracker.shared.localActiveDayCount }
    private var graduated: Bool { activeDays >= 7 }

    var body: some View {
        ZStack {
            Color.duoBg.ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()

                // ストリーク
                HStack(spacing: 6) {
                    Text("🔥").font(.system(size: 22))
                    Text("\(max(authManager.userProfile?.streak ?? 0, doneToday ? 1 : 0))日連続")
                        .font(.system(size: 17, weight: .black))
                        .foregroundColor(.duoDark)
                }

                // メインボタン
                Button(action: onStart) {
                    VStack(spacing: 10) {
                        Text(doneToday ? "✅" : "💪").font(.system(size: 56))
                        Text(doneToday ? "今日は完了！" : "今日の90秒")
                            .font(.system(size: 26, weight: .black))
                            .foregroundColor(.white)
                        Text(doneToday ? "もう1セットやる" : "スクワット5回だけ")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .frame(width: 240, height: 240)
                    .background(
                        Circle().fill(doneToday ? Color.duoBlue : Color.duoGreen)
                            .shadow(color: (doneToday ? Color.duoBlue : Color.duoGreen).opacity(0.4),
                                    radius: 18, y: 8)
                    )
                }
                .buttonStyle(.plain)

                Text("数えるのも、記録するのも、iPhoneがやります。\nあなたは、やるだけ。")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.duoSubtitle)
                    .multilineTextAlignment(.center)

                // 7日進捗ドット
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(0..<7, id: \.self) { i in
                            Circle()
                                .fill(i < activeDays ? Color.duoGreen : Color.gray.opacity(0.25))
                                .frame(width: 14, height: 14)
                        }
                    }
                    Text(graduated ? "🎉 7日続きました！" : "あと\(max(0, 7 - activeDays))日で全機能が開放")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(graduated ? .duoOrange : .duoSubtitle)
                }

                if graduated {
                    Button(action: onExit) {
                        Text("全機能を開く →")
                            .font(.system(size: 16, weight: .black))
                            .foregroundColor(.white)
                            .padding(.horizontal, 28).padding(.vertical, 14)
                            .background(Capsule().fill(Color.duoOrange))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(action: onExit) {
                    Text("すべての機能を見る")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.duoSubtitle)
                        .underline()
                }
                .buttonStyle(.plain)
                .padding(.bottom, 18)
            }
            .padding(.horizontal, 24)
        }
        .task {
            await timeSlotMgr.loadTodayProgress()
        }
        // 最初の1セット完了までの秒数を計測（90秒モードの検証指標）
        .onReceive(NotificationCenter.default.publisher(for: .timeSlotProgressDidSave)) { _ in
            if todayTraining > 0 {
                RetentionTracker.shared.recordFirstSetLatency(installedAt: installedAt)
            }
        }
    }
}
