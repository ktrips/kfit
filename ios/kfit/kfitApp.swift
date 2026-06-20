import SwiftUI
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn
import UserNotifications
import WatchConnectivity

enum MainMenuTab: Int, CaseIterable, Identifiable {
    case fit = 0
    case goal = 1
    case mind = 2
    case food = 3
    case tomo = 6  // 4=Settings, 5=More are reserved

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .fit: return "ROUTIN"
        case .goal: return "FIT"
        case .mind: return "MIND"
        case .food: return "FOOD"
        case .tomo: return "TOMO"
        }
    }

    var settingsLabel: String {
        switch self {
        case .fit: return "ROUTINタブ"
        case .goal: return "FITタブ"
        case .mind: return "MINDタブ"
        case .food: return "FOODタブ"
        case .tomo: return "TOMOタブ"
        }
    }

    var icon: String {
        switch self {
        case .fit: return "house.fill"
        case .goal: return "target"
        case .mind: return "brain.head.profile"
        case .food: return "fork.knife"
        case .tomo: return "person.2.fill"
        }
    }
}

enum MainMenuTabPreferences {
    static let fitVisibleKey = "mainTab.fit.visible"
    static let goalVisibleKey = "mainTab.goal.visible"
    static let mindVisibleKey = "mainTab.mind.visible"
    static let foodVisibleKey = "mainTab.food.visible"
    static let tomoVisibleKey = "mainTab.tomo.visible"
    static let logVisibleKey = "mainTab.log.visible"
    static let defaultTabKey = "mainTab.default"
    static let orderKey = "mainTab.order"

    static let defaultOrder = [MainMenuTab.fit, .goal, .food, .mind, .tomo]

    static func visibleKey(for tab: MainMenuTab) -> String {
        switch tab {
        case .fit: return fitVisibleKey
        case .goal: return goalVisibleKey
        case .mind: return mindVisibleKey
        case .food: return foodVisibleKey
        case .tomo: return tomoVisibleKey
        }
    }

    static func orderedTabs(from storedOrder: String) -> [MainMenuTab] {
        var result = storedOrder
            .split(separator: ",")
            .compactMap { Int($0).flatMap(MainMenuTab.init(rawValue:)) }

        // 不足タブをdefaultOrderの正しい位置に挿入
        for tab in defaultOrder where !result.contains(tab) {
            let defaultIdx = defaultOrder.firstIndex(of: tab)!
            let predecessors = Set(defaultOrder.prefix(defaultIdx))
            if let insertAfterIdx = result.indices.last(where: { predecessors.contains(result[$0]) }) {
                result.insert(tab, at: result.index(after: insertAfterIdx))
            } else {
                result.insert(tab, at: 0)
            }
        }

        return result.filter { defaultOrder.contains($0) }
    }

    static func storedOrder(from tabs: [MainMenuTab]) -> String {
        tabs.map { String($0.rawValue) }.joined(separator: ",")
    }
}

extension Notification.Name {
    static let requestStartTraining   = Notification.Name("requestStartTraining")
    static let requestStartMindfulness = Notification.Name("requestStartMindfulness")
}

// MARK: - Deep Link destinations (widget → app)
enum FitingoDeepLink: String {
    case workout     = "workout"      // トレーニング開始
    case mindfulness = "mindfulness"  // 1分瞑想
    case food        = "food"         // FOODタブ
    case mind        = "mind"         // MINDタブ
    case goal        = "goal"         // FIT/GOALタブ
    case diet        = "diet"         // FIT/GOALタブ（alias）
    case record      = "record"       // 記録メニュー
    case home        = "home"         // ROUTINタブ（デフォルト）

    init?(url: URL) {
        guard url.scheme == "fitingo",
              let host = url.host,
              let link = FitingoDeepLink(rawValue: host) else { return nil }
        self = link
    }
}

@main
struct kfitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authManager: AuthenticationManager
    @AppStorage("app.colorScheme") private var colorSchemePref = "light"
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FirebaseApp.configure()
        // オフラインキャッシュを有効化（ネットワーク不調時でもデータを返す）
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings()
        Firestore.firestore().settings = settings
        _authManager = StateObject(wrappedValue: AuthenticationManager.shared)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isSignedIn {
                    MainTabView()
                        .environmentObject(authManager)
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
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                iOSWatchBridge.shared.sendStartWorkoutSignal()
                // Watchに最新データを送信
                iOSWatchBridge.shared.notifyWatchAfterDirectRecord()
                Task {
                    await authManager.performEndOfDayCalorieTopUpIfNeeded()
                }
            } else if newPhase == .background {
                // バックグラウンド移行時もWatchに最新データを送信（ApplicationContext経由）
                iOSWatchBridge.shared.notifyWatchAfterDirectRecord()
            }
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var selectedTab = 0
    @State private var showRecordMenu = false
    @State private var showTrainingTracker = false
    @State private var showMindfulnessWidget = false
    @State private var isTabBarHidden = false
    @State private var tabBarHideWorkItem: DispatchWorkItem?
    @State private var tabBarRevealWorkItem: DispatchWorkItem?
    @AppStorage(MainMenuTabPreferences.fitVisibleKey) private var fitVisible = true
    @AppStorage(MainMenuTabPreferences.goalVisibleKey) private var goalVisible = false
    @AppStorage(MainMenuTabPreferences.mindVisibleKey) private var mindVisible = false
    @AppStorage(MainMenuTabPreferences.foodVisibleKey) private var foodVisible = true
    @AppStorage(MainMenuTabPreferences.tomoVisibleKey) private var tomoVisible = true
    @AppStorage(MainMenuTabPreferences.logVisibleKey) private var logVisible = true
    @AppStorage(MainMenuTabPreferences.defaultTabKey) private var defaultTabRaw = MainMenuTab.fit.rawValue
    @AppStorage(MainMenuTabPreferences.orderKey) private var tabOrderRaw = MainMenuTabPreferences.storedOrder(from: MainMenuTabPreferences.defaultOrder)

    var body: some View {
        ZStack(alignment: .bottom) {
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            if value.translation.height < -20 && !isTabBarHidden {
                                hideTabBarNow()
                            }
                            // スクロール中はリビールタイマーをリセット
                            if isTabBarHidden {
                                scheduleTabBarAutoReveal()
                            }
                        }
                )

            bottomRevealZone

            tabBarRevealHandle

            compactTabBar
                .offset(y: isTabBarHidden ? 76 : 0)
                .opacity(isTabBarHidden ? 0 : 1)
                .allowsHitTesting(!isTabBarHidden)
                .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isTabBarHidden)
        }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .fullScreenCover(isPresented: $showRecordMenu) {
                RecordMenuView(isPresented: $showRecordMenu)
                    .environmentObject(authManager)
            }
            .fullScreenCover(isPresented: $showTrainingTracker) {
                ExerciseTrackerView(isPresented: $showTrainingTracker)
                    .environmentObject(authManager)
            }
            .fullScreenCover(isPresented: $showMindfulnessWidget) {
                MindfulnessSessionView(
                    durationSeconds: 60,
                    title: "1分瞑想",
                    completedButtonTitle: "Breatheとして保存"
                ) { startDate, endDate in
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
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestStartTraining)) { _ in
                selectedTab = MainMenuTab.fit.rawValue
                showTrainingTracker = true
                iOSWatchBridge.shared.sendStartWorkoutSignal()
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestStartMindfulness)) { _ in
                showMindfulnessWidget = true
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .onAppear {
                selectedTab = defaultVisibleTab.rawValue
                normalizeSelection()
                checkEndOfDayCalorieTopUp()
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
                checkEndOfDayCalorieTopUp()
            }
            .onChange(of: fitVisible) { _, _ in normalizeSelection() }
            .onChange(of: goalVisible) { _, _ in normalizeSelection() }
            .onChange(of: mindVisible) { _, _ in normalizeSelection() }
            .onChange(of: foodVisible) { _, _ in normalizeSelection() }
            .onChange(of: tomoVisible) { _, _ in normalizeSelection() }
            .onChange(of: defaultTabRaw) { _, _ in normalizeSelection() }
            .onChange(of: tabOrderRaw) { _, _ in normalizeSelection() }
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
        case .fit: return fitVisible
        case .goal: return goalVisible
        case .mind: return mindVisible
        case .food: return foodVisible
        case .tomo: return tomoVisible
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
                    .font(.system(size: 15 * UIScale.font, weight: .semibold))
                Text(label)
                    .font(.system(size: 9 * UIScale.font, weight: .bold))
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
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            isTabBarHidden = false
        }
        // スクロール開始まで出っ放し — オートハイドは行わない
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

    // スクロール停止から3.5秒後に自動表示
    private func scheduleTabBarAutoReveal() {
        tabBarRevealWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            guard isTabBarHidden else { return }
            revealTabBar()
        }
        tabBarRevealWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: workItem)
    }

    private func checkEndOfDayCalorieTopUp() {
        Task {
            await authManager.performEndOfDayCalorieTopUpIfNeeded()
        }
    }
}

struct HeaderNavigationMenu: View {
    @Binding var selectedTab: Int
    @Binding var showRecordMenu: Bool
    @AppStorage(MainMenuTabPreferences.fitVisibleKey) private var fitVisible = true
    @AppStorage(MainMenuTabPreferences.goalVisibleKey) private var goalVisible = false
    @AppStorage(MainMenuTabPreferences.mindVisibleKey) private var mindVisible = false
    @AppStorage(MainMenuTabPreferences.foodVisibleKey) private var foodVisible = true
    @AppStorage(MainMenuTabPreferences.tomoVisibleKey) private var tomoVisible = true
    @AppStorage(MainMenuTabPreferences.logVisibleKey) private var logVisible = true
    @AppStorage(MainMenuTabPreferences.orderKey) private var tabOrderRaw = MainMenuTabPreferences.storedOrder(from: MainMenuTabPreferences.defaultOrder)

    private var visiblePrimaryTabs: [MainMenuTab] {
        let ordered = MainMenuTabPreferences.orderedTabs(from: tabOrderRaw)
        let visible = ordered.filter { tab in
            switch tab {
            case .fit: return fitVisible
            case .goal: return goalVisible
            case .mind: return mindVisible
            case .food: return foodVisible
            case .tomo: return tomoVisible
            }
        }
        return visible.isEmpty ? [.fit] : visible
    }

    var body: some View {
        Menu {
            ForEach(visiblePrimaryTabs) { tab in
                Button {
                    selectedTab = tab.rawValue
                } label: {
                    Label(tab.label, systemImage: tab.icon)
                }
            }
            if logVisible {
                Button {
                    showRecordMenu = true
                } label: {
                    Label("LOG", systemImage: "plus.circle.fill")
                }
            }
            Button {
                selectedTab = 4
            } label: {
                Label("SETUP", systemImage: "gearshape.fill")
            }
            Button {
                selectedTab = 5
            } label: {
                Label("MORE...", systemImage: "ellipsis.circle.fill")
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13 * UIScale.font, weight: .black))
                .foregroundColor(.white)
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(0.18))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
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
                print("[AppDelegate] 🏋️ Notification tapped - sending signal to Watch")
                iOSWatchBridge.shared.sendStartWorkoutSignal()
            }
        }

        completionHandler()
    }
}
