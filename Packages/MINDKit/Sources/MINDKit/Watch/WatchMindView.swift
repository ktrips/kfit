import SwiftUI

// MARK: - Watch 用 MIND メイン画面
// kfitWatch・kmindWatch の両方から使われます

public struct WatchMindView: View {
    @StateObject private var manager = MINDHealthKitManager.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // 睡眠スコア
                WatchSleepScoreCard(score: manager.sleepScore)

                // HRV（ストレスレベル）
                WatchHRVCard(hrv: manager.todayHRV)

                // 今日のマインドフルネス
                WatchMindfulnessCard(minutes: manager.todayMindfulnessMinutes)
            }
            .padding(.horizontal, 8)
        }
        .navigationTitle("MIND")
        .task {
            try? await manager.requestAuthorization()
        }
    }
}

// MARK: - 睡眠スコアカード
struct WatchSleepScoreCard: View {
    let score: SleepScore?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "moon.fill")
                    .foregroundStyle(.indigo)
                Text("睡眠")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let score {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(score.total)")
                        .font(.title2.bold())
                        .foregroundStyle(scoreColor(score.total))
                    Text("/ 100")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(score.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("データなし")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 85...: return .green
        case 70...: return .yellow
        default:    return .orange
        }
    }
}

// MARK: - HRVカード
struct WatchHRVCard: View {
    let hrv: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(.red)
                Text("HRV（ストレス）")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let hrv {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(String(format: "%.0f", hrv))
                        .font(.title2.bold())
                    Text("ms")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(HRVData(date: Date(), value: hrv).stressLevel.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("データなし")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - マインドフルネスカード
struct WatchMindfulnessCard: View {
    let minutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.purple)
                Text("瞑想")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(minutes)")
                    .font(.title2.bold())
                    .foregroundStyle(minutes >= 10 ? .green : .primary)
                Text("分 / 今日")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
