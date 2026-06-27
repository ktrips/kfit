import SwiftUI

// kmind Watch アプリ エントリーポイント
// kfitWatch の WatchHealthKitManager を「参照追加（コピーなし）」で共有します。
// ios/kfitWatch/Managers/WatchHealthKitManager.swift をターゲットに追加してください。

@main
struct kmindWatchApp: App {
    @StateObject private var healthKit = WatchHealthKitManager.shared

    var body: some Scene {
        WindowGroup {
            WatchMindAppView()
        }
    }
}
