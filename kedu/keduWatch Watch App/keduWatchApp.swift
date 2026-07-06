import SwiftUI

@main
struct keduWatchApp: App {
    @StateObject private var store = WatchEduStore.shared

    var body: some Scene {
        WindowGroup {
            WatchEdulingoView()
                .environmentObject(store)
        }
    }
}
