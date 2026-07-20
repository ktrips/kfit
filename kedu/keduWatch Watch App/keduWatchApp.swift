import SwiftUI

@main
struct keduWatchApp: App {
    @StateObject private var store = WatchEduStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchEdulingoView()
                .environmentObject(store)
        }
        .onChange(of: scenePhase) { phase in
            // 手首を上げて再表示するたびに applicationContext を再読 + 最新データを要求
            // （onAppear はビュー生成時の1回しか呼ばれないため、ここで補完する）
            if phase == .active {
                store.requestSync(playHaptic: false)
            }
        }
    }
}
