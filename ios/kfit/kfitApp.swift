import SwiftUI
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth
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
    @AppStorage(MainMenuTabPreferences.fitVisibleKey) private var fitVisible = true
    @AppStorage(MainMenuTabPreferences.goalVisibleKey) private var goalVisible = true
    @AppStorage(MainMenuTabPreferences.mindVisibleKey) private var mindVisible = false
    @AppStorage(MainMenuTabPreferences.foodVisibleKey) private var foodVisible = false
    @AppStorage(MainMenuTabPreferences.tomoVisibleKey) private var tomoVisible = false
    @AppStorage(MainMenuTabPreferences.logVisibleKey) private var logVisible = true
    @AppStorage(MainMenuTabPreferences.defaultTabKey) private var defaultTabRaw = MainMenuTab.fit.rawValue
    @AppStorage(MainMenuTabPreferences.orderKey) private var tabOrderRaw = MainMenuTabPreferences.storedOrder(from: MainMenuTabPreferences.defaultOrder)

    var body: some View {
        decoratedContent
            .onReceive(NotificationCenter.default.publisher(for: .requestStartTraining)) { _ in
                selectedTab = MainMenuTab.fit.rawValue
                showTrainingTracker = true
                iOSWatchBridge.shared.sendStartWorkoutSignal()
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestStartMindfulness)) { _ in
                showMindfulnessWidget = true
            }
            .onOpenURL { url in handleDeepLink(url) }
            .onAppear {
                selectedTab = defaultVisibleTab.rawValue
                normalizeSelection()
                checkEndOfDayCalorieTopUp()
                if let uid = Auth.auth().currentUser?.uid,
                   let name = authManager.userProfile?.username ?? Auth.auth().currentUser?.displayName {
                    Task {
                        await PendingShareProcessor.shared.processPendingShares(
                            userID: uid, userName: name
                        )
                    }
                }
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
                checkEndOfDayCalorieTopUp()
            }
            .onChange(of: fitVisible)    { _, _ in normalizeSelection() }
            .onChange(of: goalVisible)   { _, _ in normalizeSelection() }
            .onChange(of: mindVisible)   { _, _ in normalizeSelection() }
            .onChange(of: foodVisible)   { _, _ in normalizeSelection() }
            .onChange(of: tomoVisible)   { _, _ in normalizeSelection() }
            .onChange(of: defaultTabRaw) { _, _ in normalizeSelection() }
            .onChange(of: tabOrderRaw)   { _, _ in normalizeSelection() }
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
                            if isTabBarHidden { scheduleTabBarAutoReveal() }
                        }
                )

            bottomRevealZone

            tabBarRevealHandle

            compactTabBar
                .offset(y: isTabBarHidden ? 76 : 0)
                .opacity(isTabBarHidden ? 0 : 1)
                .allowsHitTesting(!isTabBarHidden)
                .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isTabBarHidden)

            if isTabBarHidden && !plus.isPlus && !promoBannerDismissed {
                plusPromoBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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

    // MARK: - Plus プロモーションバナー（Freeユーザー・タブバー非表示時）

    private var plusPromoBanner: some View {
        HStack(spacing: 10) {
            PlusBadge(size: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text("Fitingo Plus で全機能を解放")
                    .font(.system(size: 12, weight: .black))
                    .foregroundColor(Color(hex: "#FF8C00"))
                Text("AI解析・Kindle本読み放題・友達無制限")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#994D00"))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button {
                revealTabBar()
                showPlusView = true
            } label: {
                Text("詳細")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(hex: "#FF8C00"))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    promoBannerDismissed = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "#994D00").opacity(0.6))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [Color(hex: "#FFF5CC"), Color(hex: "#FFE580")],
                startPoint: .leading,
                endPoint: .trailing
            )
            .ignoresSafeArea(edges: .bottom)
        )
        .overlay(
            Rectangle()
                .fill(Color(hex: "#FFD700").opacity(0.4))
                .frame(height: 1),
            alignment: .top
        )
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isTabBarHidden)
        .onTapGesture {
            revealTabBar()
            showPlusView = true
        }
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
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            isTabBarHidden = false
            promoBannerDismissed = false  // タブバー再表示時にバナーを次回も出せるようリセット
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
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var plus: PlusManager
    @AppStorage(MainMenuTabPreferences.orderKey) private var tabOrderRaw = MainMenuTabPreferences.storedOrder(from: MainMenuTabPreferences.defaultOrder)

    @State private var showUserStatus = false
    @State private var showLogoutConfirm = false
    @State private var showPlusViewFromMenu = false

    private var allPrimaryTabs: [MainMenuTab] {
        MainMenuTabPreferences.orderedTabs(from: tabOrderRaw)
    }
    private let bookURL = URL(string: "https://fit.ktrips.net/books")!

    private var displayName: String {
        authManager.userProfile?.username
            ?? Auth.auth().currentUser?.displayName
            ?? Auth.auth().currentUser?.email?.components(separatedBy: "@").first
            ?? "ユーザー"
    }
    private var googlePhotoURL: URL? { Auth.auth().currentUser?.photoURL }

    var body: some View {
        Menu {
            // ── ユーザー情報セクション ──
            Section {
                Button {
                    showUserStatus = true
                } label: {
                    Label(
                        "\(displayName)  \(plus.isPlus ? "✦ Plus" : "Free")",
                        systemImage: plus.isPlus ? "star.circle.fill" : "person.circle"
                    )
                }
                if !plus.isPlus {
                    Button {
                        showPlusViewFromMenu = true
                    } label: {
                        Label("Plus にアップグレード", systemImage: "plus.circle.fill")
                    }
                }
                Button(role: .destructive) {
                    showLogoutConfirm = true
                } label: {
                    Label("ログアウト", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } header: {
                Text(Auth.auth().currentUser?.email ?? "")
            }

            // ── ナビゲーションセクション ──
            Section {
                ForEach(allPrimaryTabs) { tab in
                    Button { selectedTab = tab.rawValue } label: {
                        Label(tab.label, systemImage: tab.icon)
                    }
                }
                Button { showRecordMenu = true } label: {
                    Label("LOG", systemImage: "plus.circle.fill")
                }
                Button { selectedTab = 4 } label: {
                    Label("SETUP", systemImage: "gearshape.fill")
                }
                Link(destination: bookURL) {
                    Label("BOOKS", systemImage: "book.fill")
                }
            }
        } label: {
            // Google アバター > 頭文字 > ハンバーガーアイコンの優先順
            ZStack(alignment: .bottomTrailing) {
                if let url = googlePhotoURL {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                                .frame(width: 28, height: 28)
                                .clipShape(Circle())
                        } else {
                            initialsCircleLabel
                        }
                    }
                } else {
                    initialsCircleLabel
                }
                if plus.isPlus {
                    PlusBadge(size: 11).offset(x: 4, y: 4)
                }
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showUserStatus) {
            UserStatusSheet(
                onShowPlus: { showPlusViewFromMenu = true },
                onSetup: { selectedTab = 4 }
            )
            .environmentObject(authManager)
            .environmentObject(plus)
        }
        .sheet(isPresented: $showPlusViewFromMenu) {
            PlusView()
        }
        .confirmationDialog("ログアウトしますか？",
                            isPresented: $showLogoutConfirm,
                            titleVisibility: .visible) {
            Button("ログアウト", role: .destructive) {
                GIDSignIn.sharedInstance.signOut()
                try? Auth.auth().signOut()
            }
            Button("キャンセル", role: .cancel) {}
        }
    }

    // アバター頭文字サークル（メニューラベル用・小サイズ）
    private var initialsCircleLabel: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 28, height: 28)
            if let initial = displayName.first {
                Text(String(initial).uppercased())
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            } else {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .black))
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - UserStatusSheet

struct UserStatusSheet: View {
    var onShowPlus: () -> Void = {}
    var onSetup: () -> Void = {}
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var plus: PlusManager
    @Environment(\.dismiss) private var dismiss

    // Admin パネル用ローカル状態
    @State private var adminNewCode: String = ""
    @State private var adminCodeResult: String? = nil
    @State private var isUpdatingCode: Bool = false

    private var displayName: String {
        authManager.userProfile?.username
            ?? Auth.auth().currentUser?.displayName
            ?? Auth.auth().currentUser?.email?.components(separatedBy: "@").first
            ?? "ユーザー"
    }
    private var email: String { Auth.auth().currentUser?.email ?? "" }
    private var avatarLetter: String { String((displayName.first ?? "U")).uppercased() }
    private var googlePhotoURL: URL? { Auth.auth().currentUser?.photoURL }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // ── アバター ──
                    VStack(spacing: 10) {
                        ZStack(alignment: .bottomTrailing) {
                            avatarImage
                            if plus.isPlus {
                                PlusBadge(size: 22).offset(x: 4, y: 4)
                            }
                        }
                        Text(displayName)
                            .font(.system(size: 18, weight: .black))
                            .foregroundColor(Color.duoDark)
                        Text(email)
                            .font(.system(size: 12))
                            .foregroundColor(Color.duoSubtitle)

                        // SETUP ショートカット
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onSetup() }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 11))
                                Text("セットアップを開く")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(Color.duoSubtitle)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Color(.systemGray6))
                            .cornerRadius(20)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)

                    // ── プランステータスカード ──
                    planStatusCard

                    // ── Admin パネル ──
                    if plus.isAdmin { adminPanel }

                    // ── Free vs Plus 簡易比較（Freeの場合のみ） ──
                    if !plus.isPlus { miniComparisonSection }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
            .background(Color.duoBg.ignoresSafeArea())
            .navigationTitle("プロフィール")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .foregroundColor(Color.duoGreen)
                }
            }
        }
        .task { await plus.setup() }
    }

    // MARK: - アバター（Google 画像優先、なければ頭文字）
    @ViewBuilder
    private var avatarImage: some View {
        if let url = googlePhotoURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(
                            plus.isPlus ? Color(hex: "#FFD700") : Color.duoGreen,
                            lineWidth: 3
                        ))
                default:
                    initialsCircle
                }
            }
        } else {
            initialsCircle
        }
    }

    private var initialsCircle: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color.duoGreen, Color(hex: "#26A800")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 80, height: 80)
            Text(avatarLetter)
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundColor(.white)
        }
    }

    // MARK: プランカード

    private var planStatusCard: some View {
        HStack(spacing: 14) {
            if plus.isPlus {
                PlusBadge(size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fitingo Plus")
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(Color(hex: "#FF8C00"))
                    Text(plus.isAdmin ? "Admin アカウント"
                         : plus.codeUnlocked ? "Plusコードで解放済み"
                         : "サブスクリプション有効")
                        .font(.system(size: 12)).foregroundColor(Color.duoSubtitle)
                    Text("すべての機能が使えます ✓")
                        .font(.system(size: 11, weight: .bold)).foregroundColor(Color.duoGreen)
                }
            } else {
                ZStack {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 44, height: 44)
                    Image(systemName: "person.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Color.duoSubtitle)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Free プラン")
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(Color.duoDark)
                    Text("基本機能が無料で使えます")
                        .font(.system(size: 12)).foregroundColor(Color.duoSubtitle)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(
            plus.isPlus
            ? Color(hex: "#FFD700").opacity(0.12)
            : Color(.systemBackground)
        )
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(plus.isPlus ? Color(hex: "#FFD700").opacity(0.5) : Color(.systemGray5),
                    lineWidth: 1.5))
    }

    // MARK: - Admin パネル（コード変更）

    private var adminPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "crown.fill").foregroundColor(Color(hex: "#FFD700"))
                Text("管理者パネル")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.duoSubtitle)
            }
            .padding(.leading, 4)

            VStack(spacing: 12) {
                // 現在のコード表示
                VStack(alignment: .leading, spacing: 4) {
                    Text("現在のPlusコード")
                        .font(.system(size: 10, weight: .semibold)).foregroundColor(Color.duoSubtitle)
                    Text(plus.secretCode)
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                        .foregroundColor(Color(hex: "#FF8C00"))
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: "#FF8C00").opacity(0.08)).cornerRadius(8)
                }

                // コード変更フォーム
                HStack(spacing: 8) {
                    TextField("新しいコード", text: $adminNewCode)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(10).background(Color(.systemGray6)).cornerRadius(8)
                    Button {
                        guard !adminNewCode.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        isUpdatingCode = true
                        adminCodeResult = nil
                        Task {
                            let ok = await plus.updateSecretCode(adminNewCode)
                            adminCodeResult = ok ? "✅ 変更完了" : "❌ 失敗（Xcodeコンソールを確認）"
                            if ok { adminNewCode = "" }
                            isUpdatingCode = false
                        }
                    } label: {
                        if isUpdatingCode {
                            ProgressView().tint(.white).frame(width: 40)
                        } else {
                            Text("変更")
                        }
                    }
                    .font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color(hex: "#FF8C00")).cornerRadius(8)
                    .disabled(adminNewCode.trimmingCharacters(in: .whitespaces).isEmpty || isUpdatingCode)
                }

                if let res = adminCodeResult {
                    Text(res)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(res.hasPrefix("✅") ? Color.duoGreen : .red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14).background(Color(.systemBackground)).cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "#FFD700").opacity(0.5), lineWidth: 1.5))
        }
    }

    // MARK: 簡易比較（Freeユーザー向け）

    private var miniComparisonSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Plus にすると使えること")
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(Color.duoDark)
                Spacer()
            }

            let benefits: [(String, String)] = [
                ("🚫", "広告なし"),
                ("📊", "AI による詳細アクティビティ分析"),
                ("📸", "フォトログ AI 栄養解析"),
                ("✨", "AI スリープ・マインドコーチング"),
                ("📚", "Kindle本をWebで全文読む"),
                ("👥", "友達追加 無制限"),
                ("📱", "Plus ウィジェット"),
                ("🎨", "スパイラルテーマ 10種以上"),
                ("🔔", "全時間帯リマインダー"),
            ]
            VStack(spacing: 0) {
                ForEach(Array(benefits.enumerated()), id: \.offset) { idx, item in
                    if idx > 0 { Divider().padding(.leading, 36) }
                    HStack(spacing: 10) {
                        Text(item.0).font(.system(size: 16)).frame(width: 26)
                        Text(item.1)
                            .font(.system(size: 13))
                            .foregroundColor(Color.duoDark)
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "#FF8C00"))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(14)

            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 11)).foregroundColor(Color.duoBlue)
                Text("AI機能はSETTINGS > LLM設定でAPIキーを設定すると利用できます")
                    .font(.system(size: 10)).foregroundColor(Color.duoSubtitle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onShowPlus() }
            } label: {
                HStack(spacing: 8) {
                    PlusBadge(size: 20)
                    Text("Plus にアップグレード")
                        .font(.system(size: 14, weight: .black))
                    Text("月額¥480〜")
                        .font(.system(size: 11)).opacity(0.85)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(LinearGradient(
                    colors: [Color(hex: "#FF8C00"), Color(hex: "#FFD700")],
                    startPoint: .leading, endPoint: .trailing
                ))
                .cornerRadius(14)
                .shadow(color: Color(hex: "#FF8C00").opacity(0.35), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
        }
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
                dlog("[AppDelegate] 🏋️ Notification tapped - sending signal to Watch")
                iOSWatchBridge.shared.sendStartWorkoutSignal()
            }
        }

        completionHandler()
    }
}
