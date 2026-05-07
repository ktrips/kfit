import SwiftUI
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn
import UserNotifications
import WatchConnectivity

@main
struct kfitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authManager: AuthenticationManager
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
            if authManager.isSignedIn {
                MainTabView()
                    .environmentObject(authManager)
            } else {
                LoginView()
                    .environmentObject(authManager)
            }
        }
        // アプリがフォアグラウンドになるたびに Watch へシグナルを送る
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                iOSWatchBridge.shared.sendStartWorkoutSignal()
            }
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var selectedTab = 0
    @State private var showTracker = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationView { DashboardView() }
                .tabItem { Label("ホーム", systemImage: "house.fill") }
                .tag(0)

            NavigationView { WorkoutPlanView() }
                .tabItem { Label("プラン", systemImage: "list.bullet") }
                .tag(1)

            Color.clear
                .tabItem { Label("記録", systemImage: "plus.circle.fill") }
                .tag(2)

            NavigationView { WeeklyGoalView() }
                .tabItem { Label("週間", systemImage: "flag.fill") }
                .tag(3)

            NavigationView { HistoryView() }
                .tabItem { Label("履歴", systemImage: "calendar") }
                .tag(4)

            NavigationView { HelpView() }
                .tabItem { Label("ヘルプ", systemImage: "questionmark.circle.fill") }
                .tag(5)

            NavigationView { HealthView() }
                .tabItem { Label("健康", systemImage: "heart.fill") }
                .tag(6)

            NavigationView { SettingsView() }
                .tabItem { Label("設定", systemImage: "gearshape.fill") }
                .tag(7)
        }
        .accentColor(Color.duoGreen)
        .onChange(of: selectedTab) { oldTab, newTab in
            if newTab == 2 {
                showTracker = true
                selectedTab = 0
            }
        }
        .fullScreenCover(isPresented: $showTracker) {
            ExerciseTrackerView()
                .environmentObject(authManager)
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

    // 通知タップ時のハンドリング（将来的に特定画面へ遷移可能）
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
