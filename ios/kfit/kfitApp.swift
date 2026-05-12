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
    @State private var showRecordMenu = false

    var body: some View {
        TabView(selection: $selectedTab) {
            // ホーム
            NavigationView { DashboardView() }
                .tabItem { Label("ホーム", systemImage: "house.fill") }
                .tag(0)

            // 記録（中央ボタン）
            Color.clear
                .tabItem { Label("記録", systemImage: "plus.circle.fill") }
                .tag(1)

            // 設定（時間帯別目標を含む）
            NavigationView { SettingsView() }
                .tabItem { Label("設定", systemImage: "gearshape.fill") }
                .tag(2)

            // プラン
            NavigationView { WorkoutPlanView() }
                .tabItem { Label("プラン", systemImage: "list.bullet") }
                .tag(3)

            // その他（More）
            MoreView()
                .tabItem { Label("その他", systemImage: "ellipsis.circle.fill") }
                .tag(4)
        }
        .accentColor(Color.duoGreen)
        .onChange(of: selectedTab) { oldTab, newTab in
            if newTab == 1 {
                showRecordMenu = true
                selectedTab = 0
            }
        }
        .fullScreenCover(isPresented: $showRecordMenu) {
            RecordMenuView(isPresented: $showRecordMenu)
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

    // 通知タップ時のハンドリング
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        // アクションボタンがタップされた場合
        if response.actionIdentifier == NotificationManager.Action.startWorkout {
            print("[AppDelegate] 🏋️ Start Workout action tapped - sending signal to Watch")
            // Watchアプリを自動起動
            iOSWatchBridge.shared.sendStartWorkoutSignal()
        } else if response.actionIdentifier == NotificationManager.Action.recordWeight {
            print("[AppDelegate] ⚖️ Record Weight action tapped")
            // 体重記録画面への遷移（将来実装）
        }
        // 通知本体がタップされた場合（デフォルトアクション）
        else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            if let action = userInfo["action"] as? String {
                if action == "startWorkout" {
                    print("[AppDelegate] 🏋️ Notification tapped - sending signal to Watch")
                    // Watchアプリを自動起動
                    iOSWatchBridge.shared.sendStartWorkoutSignal()
                }
            }
        }

        completionHandler()
    }
}
