import SwiftUI
import WatchKit
import HealthKit

// MARK: - kmind Watch アプリ メイン
// kfitWatch の WatchHealthKitManager を共有して使います。
// kmind.xcodeproj で kfitWatch のファイルを「参照追加」します。

struct WatchMindAppView: View {
    @StateObject private var healthKit = WatchHealthKitManager.shared

    var body: some View {
        TabView {
            // Page 1: 睡眠スコア
            WatchSleepPage(healthKit: healthKit)
            // Page 2: HRV・ストレス
            WatchHRVPage(healthKit: healthKit)
            // Page 3: 瞑想クイックスタート
            WatchBreathePage(healthKit: healthKit)
        }
        .tabViewStyle(.page)
        .task {
            await healthKit.requestAuthorization()
            await healthKit.fetchWellnessData()  // 睡眠・HRV・マインドフルネスを取得
        }
    }
}

// MARK: - 睡眠ページ
struct WatchSleepPage: View {
    @ObservedObject var healthKit: WatchHealthKitManager

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "moon.fill")
                    .foregroundStyle(.indigo)
                    .font(.caption2)
                Text("睡眠")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if healthKit.sleepHours > 0 {
                VStack(spacing: 2) {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(String(format: "%.1f", healthKit.sleepHours))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(healthKit.sleepHours >= 7 ? .green : .orange)
                        Text("時間")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    // 睡眠スコアバー
                    let score = min(100, Int(healthKit.sleepHours / 8.0 * 100))
                    Capsule()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 6)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(score >= 80 ? Color.green : Color.orange)
                                .frame(width: CGFloat(score) / 100 * 120, height: 6)
                        }
                        .frame(width: 120)
                    Text("スコア \(score)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("データなし")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Apple Watch を\n装着して睡眠")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(10)
    }
}

// MARK: - HRVページ
struct WatchHRVPage: View {
    @ObservedObject var healthKit: WatchHealthKitManager

    private var stressLabel: String {
        guard healthKit.latestHRV > 0 else { return "—" }
        switch healthKit.latestHRV {
        case 60...: return "低ストレス"
        case 40..<60: return "中程度"
        default: return "高ストレス"
        }
    }

    private var stressColor: Color {
        guard healthKit.latestHRV > 0 else { return .secondary }
        switch healthKit.latestHRV {
        case 60...: return .green
        case 40..<60: return .yellow
        default: return .red
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(.red)
                    .font(.caption2)
                Text("HRV")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if healthKit.latestHRV > 0 {
                VStack(spacing: 2) {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(String(format: "%.0f", healthKit.latestHRV))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(stressColor)
                        Text("ms")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(stressLabel)
                        .font(.caption2)
                        .foregroundStyle(stressColor)
                }
            } else {
                Text("計測中...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Apple Watch を\n装着したまま\n少し待ってください")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(10)
    }
}

// MARK: - 瞑想クイックスタートページ
struct WatchBreathePage: View {
    @ObservedObject var healthKit: WatchHealthKitManager
    @State private var showingSession = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.purple)
                    .font(.caption2)
                Text("瞑想")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // 今日のマインドフルネス（session数 × 平均5分で概算）
            let mindMinutes = healthKit.todayMindfulnessSessions * 5
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(mindMinutes)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(mindMinutes >= 10 ? .green : .primary)
                Text("分〜")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text("今日の瞑想")
                .font(.caption2)
                .foregroundStyle(.secondary)

            // 1分瞑想ボタン
            Button {
                showingSession = true
            } label: {
                Label("1分 Start", systemImage: "play.fill")
                    .font(.caption.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
        }
        .padding(10)
        .fullScreenCover(isPresented: $showingSession) {
            WatchBreathingSessionView()
        }
    }
}

// MARK: - Watch 呼吸セッション（シンプル版）
struct WatchBreathingSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var remaining = 60
    @State private var isInhale = true
    @State private var completed = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let inhaleSeconds = 7
    private let exhaleSeconds = 8
    private var cyclePos: Int { (60 - remaining) % (inhaleSeconds + exhaleSeconds) }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.15, green: 0.08, blue: 0.42),
                         Color(red: 0.36, green: 0.14, blue: 0.68)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if completed {
                VStack(spacing: 8) {
                    Text("✅")
                        .font(.largeTitle)
                    Text("完了！")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    Button("閉じる") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.3))
                }
            } else {
                VStack(spacing: 6) {
                    Text("🧘")
                        .font(.largeTitle)
                    Text(isInhale ? "吸って" : "吐いて")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .animation(.easeInOut(duration: 0.4), value: isInhale)
                    Text("\(remaining)")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Button("中断") { dismiss() }
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .onReceive(timer) { _ in
            guard !completed else { return }
            if remaining > 0 {
                remaining -= 1
                isInhale = cyclePos < inhaleSeconds
            } else {
                completed = true
                WKInterfaceDevice.current().play(.success)
                // HealthKit に保存（WatchHealthKitManager 経由）
                Task {
                    await WatchHealthKitManager.shared.saveMindfulnessSession(
                        durationMinutes: 1,
                        sessionType: "Breathe"
                    )
                }
            }
        }
        .onAppear {
            WKInterfaceDevice.current().play(.start)
        }
    }
}
