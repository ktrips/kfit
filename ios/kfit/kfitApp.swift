import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct kfitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authManager: AuthenticationManager

    init() {
        FirebaseApp.configure()
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
        }
        .accentColor(Color.duoGreen)
        .onChange(of: selectedTab) { tab in
            if tab == 2 {
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

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool { return true }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool { return GIDSignIn.sharedInstance.handle(url) }
}
