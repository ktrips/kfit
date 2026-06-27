import SwiftUI

// kmind Watch アプリ エントリーポイント
// 必要なファイルを「Add Files to target」でターゲットに追加してください（コピーなし）:
//   ios/kfitWatch/Managers/WatchHealthKitManager.swift
//   ios/kfitWatch/Managers/WatchConnectivityManager.swift

@main
struct kmindWatch_Watch_AppApp: App {
    @StateObject private var healthKit = WatchHealthKitManager.shared

    var body: some Scene {
        WindowGroup {
            WatchMindAppView()
        }
    }
}
