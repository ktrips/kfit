import SwiftUI
import GoogleSignIn
import FirebaseCore

// MARK: - kedu アプリ エントリーポイント
// Duolingo・読書・勉強・語学 に特化した学習フィードアプリ（Edulingo）。
// Firebase / Firestore で kfit と同じデータを共有します。

@main
struct keduApp: App {

    @StateObject private var auth = AuthenticationManager.shared
    @StateObject private var plus = PlusManager.shared
    @StateObject private var photoLogManager = PhotoLogManager.shared
    @StateObject private var eduLogManager = EduLogManager.shared
    @Environment(\.scenePhase) private var scenePhase

    /// "auto" / "light" / "dark"
    @AppStorage("keduColorScheme") private var colorSchemePref: String = "auto"

    private var preferredColorScheme: ColorScheme? {
        switch colorSchemePref {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil   // auto = システム設定に従う
        }
    }

    init() {
        FirebaseApp.configure()
        // WatchConnectivity を起動直後に確立する。
        // Watch からの sendMessage でバックグラウンド起動された場合、
        // WindowGroup の .task は実行されないことがあるため、ここで delegate を立てる。
        Task { @MainActor in
            WatchEduSender.shared.activate()
        }
    }

    // WatchConnectivity セッションをアプリ起動直後に確立（EdulingoView 表示前に送信できるよう）
    private func activateWatchSession() {
        WatchEduSender.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isSignedIn {
                    keduContentView()
                        .environmentObject(auth)
                        .environmentObject(plus)
                        .environmentObject(photoLogManager)
                        .environmentObject(eduLogManager)
                } else {
                    EdulingoLoginView()
                        .environmentObject(auth)
                }
            }
            .preferredColorScheme(preferredColorScheme)
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
            .task {
                // WatchConnectivity を早期確立（ログイン状態に関わらず）
                activateWatchSession()
                // EduLogManager の初期ロードが完了してから送信（1秒後）
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                WatchEduSender.shared.sendCachedItems()
            }
            .onChange(of: scenePhase) { phase in
                // バックグラウンドから復帰するたびに Watch へ最新状態を再送する。
                // kfit 側で投稿 → kedu を開いた、というフローで Watch を最新化する経路。
                // （Firestore 再取得は WatchEduSender 側で 20 秒スロットル済み）
                if phase == .active {
                    WatchEduSender.shared.sendCachedItems()
                }
            }
        }
    }
}

// MARK: - コンテンツルート（Edulingo）
struct keduContentView: View {
    @EnvironmentObject private var auth: AuthenticationManager
    @EnvironmentObject private var plus: PlusManager
    @EnvironmentObject private var photoLogManager: PhotoLogManager

    var body: some View {
        EdulingoView()
            .environmentObject(auth)
            .environmentObject(plus)
            .environmentObject(photoLogManager)
    }
}
