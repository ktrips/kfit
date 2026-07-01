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

    init() {
        FirebaseApp.configure()
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
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
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
