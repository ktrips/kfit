import SwiftUI

// MARK: - MindfulnessSessionView + StretchSessionVideo
// DashboardView.swift から抽出。kfit・kmind 両方から参照されます。

struct StretchSessionVideo: Identifiable {
    let id: String
    let name: String
    let gifName: String
    var emoji: String
    var description: String

    init(name: String, gifName: String, emoji: String = "🤸", description: String = "") {
        self.id = gifName
        self.name = name
        self.gifName = gifName
        self.emoji = emoji
        self.description = description
    }

    static let defaultStretchVideos: [StretchSessionVideo] = [
        StretchSessionVideo(name: "仰向けツイスト", gifName: "fitingo_st_twist", emoji: "🔄", description: "膝を倒して背骨をゆっくりねじる"),
        StretchSessionVideo(name: "キャットとドッグ", gifName: "fitingo_st_cat", emoji: "🐱", description: "背中を丸め、反らして繰り返す"),
        StretchSessionVideo(name: "太陽礼拝", gifName: "fitingo_st_sun", emoji: "☀️", description: "全身を使う流れるような動き"),
    ]
}
struct MindfulnessSessionView: View {
    @Environment(\.dismiss) private var dismiss

    let onComplete: (Date, Date) -> Void
    var durationSeconds: Int = 60
    var title: String = "1分呼吸"
    var completedButtonTitle: String = "完了して保存"
    var sessionVideos: [StretchSessionVideo] = []

    @State private var sessionStart = Date()
    @State private var remainingSeconds: Int
    @State private var lastBreathPhase = -1
    @State private var isCompleting = false
    @State private var selectedVideoIndex = 0

    init(
        durationSeconds: Int = 60,
        title: String = "1分呼吸",
        completedButtonTitle: String = "完了して保存",
        sessionVideos: [StretchSessionVideo] = [],
        onComplete: @escaping (Date, Date) -> Void
    ) {
        self.durationSeconds = durationSeconds
        self.title = title
        self.completedButtonTitle = completedButtonTitle
        self.sessionVideos = Array(sessionVideos.prefix(3))
        self.onComplete = onComplete
        _remainingSeconds = State(initialValue: durationSeconds)
    }

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let inhaleHapticTimer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()
    private let inhaleSeconds = 7
    private let exhaleSeconds = 8

    private var elapsedSeconds: Int { durationSeconds - remainingSeconds }
    private var progress: Double { Double(elapsedSeconds) / Double(durationSeconds) }
    private var breathCycleSeconds: Int { inhaleSeconds + exhaleSeconds }
    private var breathPhase: Int { elapsedSeconds / breathCycleSeconds }
    private var breathCyclePosition: Int { elapsedSeconds % breathCycleSeconds }
    private var isInhale: Bool { breathCyclePosition < inhaleSeconds }
    private var phaseProgress: Double {
        if isInhale {
            return Double(breathCyclePosition) / Double(inhaleSeconds)
        }
        return Double(breathCyclePosition - inhaleSeconds) / Double(exhaleSeconds)
    }
    private var stretchPhaseText: String? {
        guard durationSeconds >= 180 else { return nil }
        return "\(min(elapsedSeconds / 60 + 1, 3))/3"
    }
    private var selectedVideo: StretchSessionVideo? {
        guard !sessionVideos.isEmpty else { return nil }
        return sessionVideos[min(selectedVideoIndex, sessionVideos.count - 1)]
    }
    private var innerCircleBase: CGFloat { 70.0 }
    private var innerCircleRange: CGFloat { 160.0 }
    private var currentStretchIndex: Int {
        guard !sessionVideos.isEmpty else { return 0 }
        return min(elapsedSeconds / 60, sessionVideos.count - 1)
    }
    private var currentStretch: StretchSessionVideo? {
        guard !sessionVideos.isEmpty else { return nil }
        return sessionVideos[currentStretchIndex]
    }

    // 瞑想 or ストレッチ判定
    private var isMeditation: Bool { sessionVideos.isEmpty }

    // ストレッチ各フェーズのSFシンボル
    private var stretchIcon: String {
        switch currentStretchIndex {
        case 0: return "figure.flexibility"
        case 1: return "figure.arms.open"
        default: return "figure.cooldown"
        }
    }

    // 背景グラデーション（種別で色分け）
    private var bgGradient: LinearGradient {
        isMeditation
            ? LinearGradient(
                colors: [Color(red: 0.15, green: 0.08, blue: 0.42),
                         Color(red: 0.36, green: 0.14, blue: 0.68)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(
                colors: [Color(red: 0.04, green: 0.26, blue: 0.54),
                         Color(red: 0.06, green: 0.55, blue: 0.66)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // リング・ハイライト色
    private var accentColor: Color {
        isMeditation
            ? Color(red: 0.80, green: 0.62, blue: 1.0)
            : Color(red: 0.35, green: 0.90, blue: 1.0)
    }

    // セッションのメリット説明文
    private var benefitText: String {
        isMeditation
            ? "深呼吸でコルチゾールを下げ、\n集中力と自律神経を整える1分間"
            : "肩・首・背中をほぐして血流を改善\n疲れをリセットする3分間のケア"
    }

    var body: some View {
        GeometryReader { geo in
            let ringSize = min(geo.size.width, geo.size.height) * 0.82
            ZStack {
                bgGradient.ignoresSafeArea()

                VStack(spacing: 0) {

                    // ── 右上 × ボタン ──
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14 * UIScale.font, weight: .bold))
                                .foregroundColor(.white.opacity(0.75))
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    // ── タイトル＋説明 ──
                    VStack(spacing: 8) {
                        Text(isMeditation ? "🧘" : "🤸")
                            .font(.system(size: 44 * UIScale.font))
                        Text(title)
                            .font(.system(size: 36 * UIScale.font, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text(benefitText)
                            .font(.system(size: 13 * UIScale.font, weight: .semibold))
                            .foregroundColor(.white.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 28)
                    }
                    .padding(.vertical, 10)

                    // ── ストレッチ：フェーズステッパー ──
                    if !isMeditation && !sessionVideos.isEmpty {
                        HStack(spacing: 0) {
                            ForEach(0..<sessionVideos.count, id: \.self) { i in
                                HStack(spacing: 0) {
                                    ZStack {
                                        Circle()
                                            .fill(i <= currentStretchIndex
                                                  ? accentColor
                                                  : Color.white.opacity(0.22))
                                            .frame(width: 26, height: 26)
                                        Text("\(i + 1)")
                                            .font(.system(size: 12 * UIScale.font, weight: .black, design: .rounded))
                                            .foregroundColor(i <= currentStretchIndex ? Color(red:0.04,green:0.26,blue:0.54) : .white.opacity(0.7))
                                    }
                                    if i < sessionVideos.count - 1 {
                                        Rectangle()
                                            .fill(i < currentStretchIndex ? accentColor : Color.white.opacity(0.22))
                                            .frame(width: 32, height: 2)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 8)
                        .animation(.easeInOut(duration: 0.4), value: currentStretchIndex)
                    }

                    Spacer(minLength: 8)

                    // ── メインリング ──
                    ZStack {
                        // 背景トラック
                        Circle()
                            .stroke(Color.white.opacity(0.18), lineWidth: 16)
                            .frame(width: ringSize, height: ringSize)

                        // 進捗アーク
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(accentColor,
                                    style: StrokeStyle(lineWidth: 16, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: ringSize, height: ringSize)
                            .animation(.easeInOut(duration: 0.35), value: progress)

                        // 呼吸バブル（拡縮）
                        let innerBase = ringSize * 0.25
                        let innerRange = ringSize * 0.55
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [accentColor.opacity(0.38), Color.clear],
                                    center: .center,
                                    startRadius: 0, endRadius: ringSize * 0.38
                                )
                            )
                            .frame(
                                width:  isInhale ? innerBase + innerRange * phaseProgress
                                                 : (innerBase + innerRange) - innerRange * phaseProgress,
                                height: isInhale ? innerBase + innerRange * phaseProgress
                                                 : (innerBase + innerRange) - innerRange * phaseProgress
                            )
                            .animation(.easeInOut(duration: 1.0), value: remainingSeconds)

                        // リング内コンテンツ
                        if isMeditation {
                            meditationRingContent
                        } else {
                            stretchRingContent
                        }
                    }

                    Spacer(minLength: 8)

                    // ── リング下の補足 ──
                    // （リングは上下の Spacer で画面中央に配置）
                    if isMeditation {
                        meditationTip
                    } else if let stretch = currentStretch {
                        stretchDescriptionRow(stretch: stretch)
                    }

                    Spacer(minLength: 12)

                    // ── 中断ボタン ──
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "stop.circle")
                                .font(.system(size: 16 * UIScale.font, weight: .semibold))
                            Text("中断する")
                                .font(.system(size: 16 * UIScale.font, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 40)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.14))
                        .cornerRadius(28)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28)
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 36)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            sessionStart = Date()
            UIApplication.shared.isIdleTimerDisabled = true
            playBreathHaptic()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onReceive(timer) { _ in
            guard !isCompleting else { return }
            if remainingSeconds > 0 {
                remainingSeconds -= 1
                if breathPhase != lastBreathPhase {
                    lastBreathPhase = breathPhase
                    playPhaseChangeHaptic()
                }
                if remainingSeconds == 0 {
                    completeSession()
                }
            } else {
                completeSession()
            }
        }
        .onReceive(inhaleHapticTimer) { _ in
            guard !isCompleting, remainingSeconds > 0, isInhale else { return }
            playInhalePulseHaptic()
        }
    }

    // ── 瞑想リング内コンテンツ ──
    private var meditationRingContent: some View {
        VStack(spacing: 8) {
            Text("🧘")
                .font(.system(size: 38 * UIScale.font))
            Text(isInhale ? "吸って" : "吐いて")
                .font(.system(size: 36 * UIScale.font, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Text(isInhale ? "ゆっくり鼻から" : "力を抜いて")
                .font(.system(size: 15 * UIScale.font, weight: .semibold))
                .foregroundColor(.white.opacity(0.82))
                .animation(.easeInOut(duration: 0.4), value: isInhale)
            Text("\(remainingSeconds)")
                .font(.system(size: 50 * UIScale.font, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
        }
    }

    // ── ストレッチリング内コンテンツ ──
    private var stretchRingContent: some View {
        VStack(spacing: 6) {
            Image(systemName: stretchIcon)
                .font(.system(size: 40 * UIScale.font, weight: .medium))
                .foregroundColor(accentColor)
                .shadow(color: accentColor.opacity(0.4), radius: 6)
                .animation(.easeInOut(duration: 0.4), value: currentStretchIndex)

            if let stretch = currentStretch {
                Text(stretch.name)
                    .font(.system(size: 20 * UIScale.font, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .animation(.easeInOut(duration: 0.4), value: currentStretchIndex)
            }

            HStack(spacing: 6) {
                Text(isInhale ? "💨" : "😮‍💨")
                    .font(.system(size: 18 * UIScale.font))
                Text(isInhale ? "吸って" : "吐いて")
                    .font(.system(size: 22 * UIScale.font, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }
            .animation(.easeInOut(duration: 0.4), value: isInhale)

            Text("\(remainingSeconds)")
                .font(.system(size: 44 * UIScale.font, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
        }
    }

    // ── 瞑想ヒント（リング下） ──
    private var meditationTip: some View {
        HStack(spacing: 6) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 13 * UIScale.font))
                .foregroundColor(accentColor)
            Text("目を閉じて、呼吸だけに意識を向けて")
                .font(.system(size: 14 * UIScale.font, weight: .semibold))
                .foregroundColor(.white.opacity(0.80))
        }
        .padding(.bottom, 6)
    }

    // ── ストレッチ説明（リング下） ──
    private func stretchDescriptionRow(stretch: StretchSessionVideo) -> some View {
        VStack(spacing: 4) {
            Text(stretch.description)
                .font(.system(size: 14 * UIScale.font, weight: .semibold))
                .foregroundColor(.white.opacity(0.80))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .padding(.bottom, 6)
        .animation(.easeInOut(duration: 0.5), value: currentStretchIndex)
    }

    private func completeSession() {
        guard !isCompleting else { return }
        isCompleting = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onComplete(sessionStart, sessionStart.addingTimeInterval(TimeInterval(durationSeconds)))
        dismiss()
    }

    private func playBreathHaptic() {
        if isInhale {
            playInhalePulseHaptic()
        } else {
            playPhaseChangeHaptic()
        }
    }

    private func playInhalePulseHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.42)
    }

    private func playPhaseChangeHaptic() {
        let generator = UIImpactFeedbackGenerator(style: isInhale ? .light : .medium)
        generator.prepare()
        generator.impactOccurred(intensity: isInhale ? 0.55 : 0.80)
    }
}
