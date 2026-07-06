import SwiftUI
import Combine
import WatchKit

// MARK: - 共通カラー

private let duoGreen   = Color(red: 0.345, green: 0.800, blue: 0.008)
private let mindPurple = Color(red: 0.808, green: 0.510, blue: 1.000)

// MARK: - ストレスレベル判定

private func stressInfo(hrv: Double) -> (label: String, color: Color, emoji: String) {
    if hrv <= 0 { return ("不明",     .gray,                                  "❓") }
    if hrv >= 60 { return ("低い",    duoGreen,                               "😌") }
    if hrv >= 40 { return ("やや低い", Color(red: 0.60, green: 0.85, blue: 0.30), "🙂") }
    if hrv >= 20 { return ("普通",    Color(red: 1.0,  green: 0.80, blue: 0.00), "😐") }
    return ("高め", Color(red: 1.0, green: 0.40, blue: 0.30), "😰")
}

private func formatMindfulMinutes(_ minutes: Double) -> String {
    if minutes < 1 { return "\(Int(minutes * 60))秒" }
    if abs(minutes.rounded() - minutes) < 0.05 { return "\(Int(minutes.rounded()))分" }
    return String(format: "%.1f分", minutes)
}

// MARK: - WatchMindAppView（メイン）

struct WatchMindAppView: View {
    @StateObject private var healthKit = WatchHealthKitManager.shared

    @State private var showBreatheFlow  = false
    @State private var showStretchFlow  = false
    @State private var showStandFlow    = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {

                // ── ストレスカード（更新ボタン内蔵）─────────
                stressCard

                // ── マインドフルネスボタン ────────────────
                mindfulnessButton

                // ── 3分ストレッチボタン ───────────────────
                stretchButton

                // ── 20分スタンドボタン ────────────────────
                standButton

                // ── 今日の記録 ────────────────────────────
                mindfulnessHistorySection

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 8)
            .padding(.top, 2)
            .padding(.bottom, 6)
        }
        .task {
            await healthKit.requestAuthorization()
            await healthKit.fetchWellnessData()
        }
        .fullScreenCover(isPresented: $showBreatheFlow) {
            WatchBreatheFlowView(isPresented: $showBreatheFlow)
        }
        .fullScreenCover(isPresented: $showStretchFlow) {
            WatchStretchFlowView(isPresented: $showStretchFlow)
        }
        .fullScreenCover(isPresented: $showStandFlow) {
            WatchStandFlowView(isPresented: $showStandFlow)
        }
    }

    // MARK: - ストレスカード

    private var stressCard: some View {
        let stress = stressInfo(hrv: healthKit.latestHRV)
        return ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                // 心拍数
                VStack(spacing: 3) {
                    Text("❤️").font(.system(size: 18))
                    Text(healthKit.averageHeartRate > 0 ? "\(healthKit.averageHeartRate)" : "—")
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(.white)
                    Text("bpm").font(.system(size: 9)).foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1, height: 40)

                // HRV
                VStack(spacing: 3) {
                    Text("💓").font(.system(size: 18))
                    Text(healthKit.latestHRV > 0 ? String(format: "%.0f", healthKit.latestHRV) : "—")
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(.white)
                    Text("ms HRV").font(.system(size: 9)).foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1, height: 40)

                // ストレス
                VStack(spacing: 3) {
                    Text(stress.emoji).font(.system(size: 18))
                    Text(stress.label)
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(stress.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("ストレス").font(.system(size: 9)).foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 6)

            // 更新ボタン（右上）
            Button {
                Task { await healthKit.fetchWellnessData(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(4)
            }
            .buttonStyle(.plain)
        }
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
    }

    // MARK: - マインドフルネスボタン

    private var mindfulnessButton: some View {
        Button { showBreatheFlow = true } label: {
            VStack(spacing: 6) {
                Text("🧘").font(.system(size: 30))
                Text("マインドフルネス")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Text("1分 呼吸瞑想")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.65))
                if healthKit.todayMindfulnessSessions > 0 {
                    Text("今日 \(healthKit.todayMindfulnessSessions)回実施済み")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(duoGreen)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [mindPurple, Color(red: 0.58, green: 0.32, blue: 0.76)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - ストレッチボタン

    private var stretchButton: some View {
        Button { showStretchFlow = true } label: {
            VStack(spacing: 5) {
                Text("🤸").font(.system(size: 26))
                Text("3分ストレッチ")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                Text("Reflectとして保存")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.65))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.35, green: 0.80, blue: 0.55),
                             Color(red: 0.10, green: 0.62, blue: 0.75)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - スタンドボタン

    private var standButton: some View {
        Button { showStandFlow = true } label: {
            VStack(spacing: 5) {
                Text("🍅").font(.system(size: 26))
                Text("20分スタンド")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                Text("立って作業に集中")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.99, green: 0.55, blue: 0.12),
                             Color(red: 0.94, green: 0.27, blue: 0.15)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 今日のマインドフルネス履歴

    private var mindfulnessHistorySection: some View {
        let samples = healthKit.todayMindfulnessSamples.sorted { $0.startDate > $1.startDate }
        let impacts = healthKit.mindfulnessImpactHistory
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text("🧘").font(.system(size: 11))
                Text("今日のマインドフル")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Text("\(samples.count)件")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
            }

            if samples.isEmpty {
                Text("まだ記録はありません")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(samples.prefix(4)) { session in
                    let matchedImpact = impacts.first { impact in
                        abs(impact.startDate.timeIntervalSince(session.startDate)) < 300
                    }
                    mindfulnessHistoryRow(session, impact: matchedImpact)
                }
            }
        }
        .padding(7)
        .background(Color.white.opacity(0.07))
        .cornerRadius(10)
    }

    private func mindfulnessHistoryRow(_ session: WatchMindfulnessSession,
                                       impact: WatchMindfulnessImpact? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(session.emoji).font(.system(size: 12))
                VStack(alignment: .leading, spacing: 0) {
                    Text(session.typeLabel)
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.white)
                    Text(session.sourceLabel)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.white.opacity(0.52))
                        .lineLimit(1)
                }
                Spacer()
                Text(formatMindfulMinutes(session.durationMinutes))
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(
                        session.typeLabel == "3分ストレッチ"
                        ? Color(red: 0.82, green: 0.51, blue: 1.0) : duoGreen
                    )
            }

            let hkHR  = session.averageHeartRate
            let hkHRV = session.averageHRV
            let displayHR  = hkHR  > 0 ? hkHR  : (impact?.after.heartRate ?? 0)
            let displayHRV = hkHRV > 0 ? hkHRV : (impact?.after.hrv ?? 0)

            if displayHR > 0 || displayHRV > 0 {
                HStack(spacing: 6) {
                    if displayHR > 0 {
                        HStack(spacing: 2) {
                            Text("❤️").font(.system(size: 8))
                            Text("\(Int(displayHR))")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.85))
                            Text("bpm")
                                .font(.system(size: 7))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    if displayHRV > 0 {
                        HStack(spacing: 2) {
                            Text("💙").font(.system(size: 8))
                            Text("\(Int(displayHRV))")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.85))
                            Text("ms")
                                .font(.system(size: 7))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    if let imp = impact, imp.before.hrv > 0, imp.after.hrv > 0 {
                        let delta = imp.stressDelta
                        let ds = delta == 0 ? "±0" : (delta > 0 ? "+\(delta)" : "\(delta)")
                        let dc: Color = delta < 0 ? duoGreen : delta > 0 ? Color(red: 1, green: 0.4, blue: 0.3) : .gray
                        HStack(spacing: 1) {
                            Text("ストレス").font(.system(size: 7)).foregroundColor(.white.opacity(0.5))
                            Text(ds).font(.system(size: 9, weight: .black)).foregroundColor(dc)
                        }
                    }
                }
                .padding(.leading, 17)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.06))
        .cornerRadius(7)
    }
}
// MARK: - フロービュー（WatchFlowViews.swift に定義済み）
// BreathingBackground, WatchBreatheFlowView, WatchStretchFlowView, WatchStandFlowView は
// ios/kfitWatch/Views/WatchFlowViews.swift を参照（kfit Watch との共有）
