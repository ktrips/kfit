import SwiftUI
import WatchKit

@main
struct kfitWatchApp: App {
    @StateObject private var connectivity = WatchConnectivityManager.shared

    var body: some Scene {
        WindowGroup {
            if connectivity.isPlus {
                WatchDashboardView()
                    .environmentObject(connectivity)
            } else {
                WatchPlusGateView()
                    .environmentObject(connectivity)
            }
        }
    }
}

// MARK: - Plus ゲートスクリーン（Free ユーザー向け）
struct WatchPlusGateView: View {
    @EnvironmentObject private var connectivity: WatchConnectivityManager

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "lock.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(Color(red: 1.0, green: 0.753, blue: 0.0))
                    .padding(.top, 8)

                Text("Fitingo Plus")
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(.white)

                Text("Watch アプリは\nPlus 限定です")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)

                Divider().padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 5) {
                    WatchGateFeatureRow(icon: "figure.run.circle.fill",  text: "モーション運動検出")
                    WatchGateFeatureRow(icon: "chart.bar.xaxis",         text: "進捗ウィジェット")
                    WatchGateFeatureRow(icon: "drop.fill",               text: "水分・摂取ログ")
                    WatchGateFeatureRow(icon: "brain.head.profile",      text: "マインドフルネス")
                }
                .padding(.horizontal, 8)

                Text("iPhoneの Fitingo アプリで\nPlus にアップグレード")
                    .font(.system(size: 10))
                    .foregroundColor(Color(red: 1.0, green: 0.753, blue: 0.0))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
            }
        }
        .background(Color.black)
    }
}

private struct WatchGateFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(Color(red: 1.0, green: 0.753, blue: 0.0))
                .frame(width: 16)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
            Spacer()
        }
    }
}
