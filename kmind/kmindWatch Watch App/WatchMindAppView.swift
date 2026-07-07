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

// MARK: - ムーミン名言（Watchローカル定義）

private struct WatchMoominQuote {
    let text: String
    let speaker: String
}

/// HRVから計算したストレスラベルに応じたムーミン名言を返す。
/// 日付をシードにして毎日変わる一言。
private func moominQuoteForWatch(stressLabel: String) -> WatchMoominQuote {
    let quotes: [WatchMoominQuote]
    switch stressLabel {
    case "低い":
        quotes = [
            WatchMoominQuote(text: "長い旅行に必要なのは大きなカバンじゃなく、口ずさめる一つの歌さ", speaker: "スナフキン"),
            WatchMoominQuote(text: "これから、なにもかもがうまくいくんだ", speaker: "ムーミントロール"),
            WatchMoominQuote(text: "生きるなんて、だれにだってできるじゃないか", speaker: "ムーミンパパ"),
            WatchMoominQuote(text: "月の光をごらんよ。なんてあったかいんだろ。ぼく、飛べそうな気がするよ！", speaker: "ムーミントロール"),
            WatchMoominQuote(text: "友だちが、それぞれ自分にぴったりのことを見つけられるのって、うれしいものでしょ？", speaker: "ムーミンママ"),
        ]
    case "やや低い":
        quotes = [
            WatchMoominQuote(text: "大切なのは、自分のしたいことを自分で知ってるってことだよ", speaker: "スナフキン"),
            WatchMoominQuote(text: "「そのうち」なんて当てにならないな。いまがその時さ", speaker: "スナフキン"),
            WatchMoominQuote(text: "さあ、明日もまた、長い一日になるでしょうよ。しかも、はじめからおわりまで自分のものよ。とてもすてきなことじゃない！", speaker: "ムーミンママ"),
            WatchMoominQuote(text: "今夜は歌のことだけを考えよう。明日は明日の風が吹くさ", speaker: "スナフキン"),
            WatchMoominQuote(text: "心の繋がった仲間こそ、ルビーにも勝る美しいルビーさ。", speaker: "スナフキン"),
        ]
    case "普通":
        quotes = [
            WatchMoominQuote(text: "ちょっと眠るよ。頭はほったらかしておくと、よく働くものなんだ", speaker: "ムーミンパパ"),
            WatchMoominQuote(text: "あんまりおおげさに考えすぎないようにしろよ", speaker: "スナフキン"),
            WatchMoominQuote(text: "明日という日があるじゃないの", speaker: "ムーミンママ"),
            WatchMoominQuote(text: "もう泣くのはやめて、サンドイッチを食べなよ。", speaker: "ムーミントロール"),
            WatchMoominQuote(text: "ものごとって、みんなとてもあいまいなのよ。まさにそのことが、わたしを安心させるんだけれどもね", speaker: "トゥーティッキ"),
        ]
    case "高め":
        quotes = [
            WatchMoominQuote(text: "どんなことでも、自分で見つけださなきゃいけないものよ。そうして自分ひとりで、それを乗りこえるんだわ", speaker: "トゥーティッキ"),
            WatchMoominQuote(text: "本当の勇気とは自分の弱い心に打ち勝つことだよ", speaker: "スナフキン"),
            WatchMoominQuote(text: "あのさ、たたかうってことをおぼえないかぎり、あんたには自分の顔を持てるわけないわ", speaker: "リトルミイ"),
            WatchMoominQuote(text: "ほら、元気をなくしてはだめだよ。もう一回！", speaker: "ヘムレン"),
            WatchMoominQuote(text: "おだやかな人生なんてあるわけがない", speaker: "スナフキン"),
        ]
    default: // "不明"
        quotes = [
            WatchMoominQuote(text: "ね、なにが起こったって、わたしにはちゃんとあなたがわかるのよ", speaker: "ムーミンママ"),
            WatchMoominQuote(text: "なんでも自分のものにして、持って帰ろうとすると、むずかしくなっちゃうんだよ", speaker: "スナフキン"),
            WatchMoominQuote(text: "ときどき、どうしてもひとりになりたいっていうきみの気持ちを、ぼくはもちろんよくわかるんだ", speaker: "ムーミントロール"),
            WatchMoominQuote(text: "人の目なんか気にしないで、思うとおりに暮らしていればいいのさ", speaker: "スナフキン"),
            WatchMoominQuote(text: "故郷は別にないさ、強いて言えば地球かな", speaker: "スナフキン"),
        ]
    }
    let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
    return quotes[dayOfYear % quotes.count]
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

                // ── ムーミン名言カード ────────────────────
                moominQuoteCard

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

    // MARK: - ムーミン名言カード

    private var moominQuoteCard: some View {
        let stress = stressInfo(hrv: healthKit.latestHRV)
        let quote  = moominQuoteForWatch(stressLabel: stress.label)
        let accent = stress.label == "不明" ? mindPurple : stress.color
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text("🌿").font(.system(size: 11))
                Text("あなたへの一言")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(accent)
                Spacer()
                Text("Moomin")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(accent.opacity(0.6))
            }
            Text("「\(quote.text)」")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
            HStack {
                Spacer()
                Text("— \(quote.speaker)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(accent.opacity(0.8))
                    .italic()
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(accent.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(accent.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(10)
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
