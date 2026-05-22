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
                // Watchに最新データを送信
                iOSWatchBridge.shared.notifyWatchAfterDirectRecord()
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

    var body: some View {
        mainContent
            .safeAreaInset(edge: .bottom, spacing: 0) {
                compactTabBar
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .fullScreenCover(isPresented: $showRecordMenu) {
                RecordMenuView(isPresented: $showRecordMenu)
                    .environmentObject(authManager)
            }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch selectedTab {
        case 1:  GoalView(selectedTab: $selectedTab)
        case 2:  MindView(selectedTab: $selectedTab)
        case 4:  NavigationView { SettingsView() }
        case 5:  MoreView()
        default: NavigationView { DashboardView() }.ignoresSafeArea(.keyboard)
        }
    }

    private var compactTabBar: some View {
        HStack(spacing: 2) {
            tabBtn(tag: 0, icon: "house.fill",           label: "FIT")
            tabBtn(tag: 1, icon: "target",               label: "GOAL")
            tabBtn(tag: 2, icon: "brain.head.profile",   label: "MIND")
            recordBtn
            tabBtn(tag: 4, icon: "gearshape.fill",       label: "設定")
            tabBtn(tag: 5, icon: "ellipsis.circle.fill", label: "その他")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            LinearGradient(
                colors: [Color(red: 0.38, green: 0.84, blue: 0.05),
                         Color(red: 0.20, green: 0.66, blue: 0.00)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .shadow(color: Color.black.opacity(0.15), radius: 6, y: -2)
    }

    private var recordBtn: some View {
        Button { showRecordMenu = true } label: {
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 30, height: 30)
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(Color(red: 0.22, green: 0.68, blue: 0.0))
                }
                Text("記録")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func tabBtn(tag: Int, icon: String, label: String) -> some View {
        let isSelected = selectedTab == tag
        return Button { selectedTab = tag } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(label)
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundColor(isSelected ? Color(red: 0.22, green: 0.68, blue: 0.0) : .white.opacity(0.88))
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.white : Color.clear)
            )
            .frame(maxWidth: .infinity)
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
