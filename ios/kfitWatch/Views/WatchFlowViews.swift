import SwiftUI
import WatchKit
import Combine

// MARK: - WKExtendedRuntimeSession デリゲートヘルパー

/// フロービューが WKExtendedRuntimeSession を開始する際に設定する軽量 delegate クラス。
/// kfit Watch と kmind Watch で共有される。
final class WatchRuntimeSessionDelegate: NSObject, WKExtendedRuntimeSessionDelegate {
    var onInvalidate: ((WKExtendedRuntimeSessionInvalidationReason, Error?) -> Void)?

    func extendedRuntimeSessionDidStart(_ session: WKExtendedRuntimeSession) {}
    func extendedRuntimeSessionWillExpire(_ session: WKExtendedRuntimeSession) {}
    func extendedRuntimeSession(
        _ session: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        onInvalidate?(reason, error)
    }
}

/// WKExtendedRuntimeSession を delegate 付きで開始するヘルパー。
/// 画面をオンに保つためだけの補助セッション。
/// 権限不足・システム制限で即時無効化されても呼び出し元には通知しない（タイマーや保存は継続）。
@discardableResult
func startExtendedSession(
    onInvalidate: ((WKExtendedRuntimeSessionInvalidationReason, Error?) -> Void)? = nil
) -> (session: WKExtendedRuntimeSession, delegate: WatchRuntimeSessionDelegate) {
    let delegate = WatchRuntimeSessionDelegate()
    // 起動直後の即時無効化（error / suppressedBySystem）では onInvalidate を呼ばない
    delegate.onInvalidate = { reason, error in
        switch reason {
        case .error, .suppressedBySystem:
            // 画面オフになるだけ — セッション本体は継続させる
            return
        default:
            onInvalidate?(reason, error)
        }
    }
    let session = WKExtendedRuntimeSession()
    session.delegate = delegate
    session.start()
    return (session, delegate)
}

// MARK: - BreathingBackground（呼吸アニメーション背景）

struct BreathingBackground: View {
    let isInhaling: Bool
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [color.opacity(0.28), color.opacity(0.06), .clear],
                        center: .center,
                        startRadius: 8,
                        endRadius: 95
                    )
                )
                .frame(width: 190, height: 190)
                .scaleEffect(isInhaling ? 1.38 : 0.68)
                .blur(radius: 2)
                .offset(y: 8)

            Circle()
                .stroke(color.opacity(0.18), lineWidth: 2)
                .frame(width: 138, height: 138)
                .scaleEffect(isInhaling ? 1.55 : 0.78)
                .offset(y: 8)
        }
        .animation(.easeInOut(duration: isInhaling ? 5.8 : 6.8), value: isInhaling)
        .allowsHitTesting(false)
    }
}

// MARK: - WatchBreatheFlowView（1分瞑想フロー）

struct WatchBreatheFlowView: View {
    @Binding var isPresented: Bool
    @ObservedObject private var healthKit = WatchHealthKitManager.shared
    @State private var elapsedSeconds = 0
    @State private var isSaving = false
    @State private var didComplete = false
    @State private var inhaleHapticTask: Task<Void, Never>?
    @State private var completionHapticTask: Task<Void, Never>?
    @State private var beforeVitals: WatchWellnessVitals? = nil
    @State private var sessionStartDate = Date()
    @State private var animIsInhaling: Bool = false
    @State private var extSession: WKExtendedRuntimeSession?
    @State private var extDelegate: WatchRuntimeSessionDelegate?

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var cycleSecond: Int { elapsedSeconds % 13 }
    private var isInhaling: Bool { cycleSecond < 6 }
    private var cue: String { isInhaling ? "ゆっくり吸う" : "ゆっくり吐く" }
    private var remainingSeconds: Int { max(0, 60 - elapsedSeconds) }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.30, green: 0.18, blue: 0.52), Color(red: 0.48, green: 0.28, blue: 0.68)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            BreathingBackground(isInhaling: animIsInhaling, color: .white)

            VStack(spacing: 8) {
                Text("1分瞑想")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(.white)

                Text(cue)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(.white)

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.22), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: CGFloat(elapsedSeconds) / 60.0)
                        .stroke(.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(remainingSeconds)s")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                }
                .frame(width: 62, height: 62)

                if healthKit.averageHeartRate > 0 || healthKit.latestHRV > 0 {
                    HStack(spacing: 14) {
                        if healthKit.averageHeartRate > 0 {
                            VStack(spacing: 1) {
                                Text("\(healthKit.averageHeartRate)")
                                    .font(.system(size: 15, weight: .black))
                                    .foregroundColor(.white)
                                Text("BPM")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        if healthKit.latestHRV > 0 {
                            VStack(spacing: 1) {
                                Text(String(format: "%.0f", healthKit.latestHRV))
                                    .font(.system(size: 15, weight: .black))
                                    .foregroundColor(.white)
                                Text("HRV")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }
                }

                if isSaving {
                    ProgressView().tint(.white)
                }
            }
            .padding(10)
        }
        .onAppear {
            sessionStartDate = Date()
            WKInterfaceDevice.current().play(.start)
            startInhaleHaptics()
            let (s, d) = startExtendedSession { _, _ in
                DispatchQueue.main.async { isPresented = false }
            }
            extSession = s
            extDelegate = d
            Task {
                let v = await healthKit.measureCurrentWellnessVitals()
                await MainActor.run { beforeVitals = v }
            }
        }
        .onDisappear {
            inhaleHapticTask?.cancel()
            completionHapticTask?.cancel()
            extSession?.invalidate()
            extSession = nil
            extDelegate = nil
        }
        .onReceive(timer) { _ in
            guard !didComplete else { return }
            let newSeconds = Int(Date().timeIntervalSince(sessionStartDate))
            let prev = elapsedSeconds
            elapsedSeconds = newSeconds
            if isInhaling != animIsInhaling { animIsInhaling = isInhaling }
            if newSeconds % 13 == 0 && newSeconds > 0 && newSeconds != prev {
                startInhaleHaptics()
            }
            if newSeconds >= 60 {
                completeBreathe()
            }
        }
    }

    private func startInhaleHaptics() {
        inhaleHapticTask?.cancel()
        inhaleHapticTask = Task {
            for _ in 0..<46 {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    WKInterfaceDevice.current().play(.click)
                }
                try? await Task.sleep(nanoseconds: 130_000_000)
            }
        }
    }

    private func completeBreathe() {
        didComplete = true
        isSaving = true
        inhaleHapticTask?.cancel()
        playCompletionHaptic()
        let capturedBefore = beforeVitals
        let startDate = sessionStartDate
        Task {
            let after = await healthKit.measureCurrentWellnessVitals()
            let impact: WatchMindfulnessImpact? = capturedBefore.map {
                WatchMindfulnessImpact(sessionType: "Breathe", startDate: startDate, endDate: Date(), before: $0, after: after)
            }
            await healthKit.saveMindfulnessSession(durationMinutes: 1, sessionType: "Breathe", impact: impact)
            await healthKit.fetchTodayMindfulness()
            await MainActor.run {
                isSaving = false
                isPresented = false
            }
        }
    }

    private func playCompletionHaptic() {
        completionHapticTask?.cancel()
        completionHapticTask = Task {
            for index in 0..<4 {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    WKInterfaceDevice.current().play(index % 2 == 0 ? .notification : .success)
                }
                try? await Task.sleep(nanoseconds: 220_000_000)
            }
        }
    }
}

// MARK: - WatchStretchFlowView（3分ストレッチフロー）

struct WatchStretchFlowView: View {
    @Binding var isPresented: Bool
    @ObservedObject private var healthKit = WatchHealthKitManager.shared
    @State private var elapsedSeconds = 0
    @State private var isSaving = false
    @State private var didComplete = false
    @State private var inhaleHapticTask: Task<Void, Never>?
    @State private var completionHapticTask: Task<Void, Never>?
    @State private var milestoneHapticTask: Task<Void, Never>?
    @State private var beforeVitals: WatchWellnessVitals? = nil
    @State private var sessionStartDate = Date()
    @State private var animIsInhaling: Bool = false
    @State private var extSession: WKExtendedRuntimeSession?
    @State private var extDelegate: WatchRuntimeSessionDelegate?

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let poses: [(emoji: String, title: String, cue: String)] = [
        ("🔄", "仰向けツイスト", "膝を倒して背骨をゆっくりねじり、呼吸を続ける"),
        ("🐱", "猫伸びのポーズ", "四つ這いで背中を丸め、次に反らして繰り返す"),
        ("🙏", "礼拝のポーズ", "手を合わせ胸の前で深呼吸、全身の力を抜く"),
    ]

    private var phaseIndex: Int { min(elapsedSeconds / 60, poses.count - 1) }
    private var currentPose: (emoji: String, title: String, cue: String) { poses[phaseIndex] }
    private var secondsInPhase: Int { elapsedSeconds % 60 }
    private var remainingSeconds: Int { max(0, 180 - elapsedSeconds) }
    private var breathCycleSecond: Int { secondsInPhase % 13 }
    private var isInhaling: Bool { breathCycleSecond < 6 }
    private var breathCue: String { isInhaling ? "ゆっくり吸う" : "ゆっくり吐く" }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.62, blue: 0.76), Color(red: 0.35, green: 0.80, blue: 0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            BreathingBackground(isInhaling: animIsInhaling, color: .white)

            VStack(spacing: 7) {
                Text("3分ストレッチ")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(.white)

                Text("\(phaseIndex + 1)/3")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Color.white.opacity(0.22))
                    .cornerRadius(6)

                Text(breathCue)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(.white)

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.22), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: CGFloat(elapsedSeconds) / 180.0)
                        .stroke(.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(remainingSeconds)s")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                }
                .frame(width: 58, height: 58)

                if healthKit.averageHeartRate > 0 || healthKit.latestHRV > 0 {
                    HStack(spacing: 14) {
                        if healthKit.averageHeartRate > 0 {
                            VStack(spacing: 1) {
                                Text("\(healthKit.averageHeartRate)")
                                    .font(.system(size: 15, weight: .black))
                                    .foregroundColor(.white)
                                Text("BPM")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        if healthKit.latestHRV > 0 {
                            VStack(spacing: 1) {
                                Text(String(format: "%.0f", healthKit.latestHRV))
                                    .font(.system(size: 15, weight: .black))
                                    .foregroundColor(.white)
                                Text("HRV")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }
                }

                if isSaving {
                    ProgressView().tint(.white)
                }
            }
            .padding(10)
        }
        .onAppear {
            sessionStartDate = Date()
            WKInterfaceDevice.current().play(.start)
            startInhaleHaptics()
            let (s, d) = startExtendedSession { _, _ in
                DispatchQueue.main.async { isPresented = false }
            }
            extSession = s
            extDelegate = d
            Task {
                let v = await healthKit.measureCurrentWellnessVitals()
                await MainActor.run { beforeVitals = v }
            }
        }
        .onDisappear {
            inhaleHapticTask?.cancel()
            completionHapticTask?.cancel()
            milestoneHapticTask?.cancel()
            extSession?.invalidate()
            extSession = nil
            extDelegate = nil
        }
        .onReceive(timer) { _ in
            guard !didComplete else { return }
            let newSeconds = Int(Date().timeIntervalSince(sessionStartDate))
            elapsedSeconds = newSeconds
            if isInhaling != animIsInhaling { animIsInhaling = isInhaling }
            playBreathingHapticIfNeeded()
            if newSeconds >= 180 {
                completeStretch()
            }
        }
    }

    private func playBreathingHapticIfNeeded() {
        if elapsedSeconds % 60 == 0 && elapsedSeconds > 0 && elapsedSeconds < 180 {
            playMilestoneHaptic()
            return
        }
        if elapsedSeconds % 13 == 0 {
            startInhaleHaptics()
        }
    }

    private func playMilestoneHaptic() {
        inhaleHapticTask?.cancel()
        milestoneHapticTask?.cancel()
        milestoneHapticTask = Task {
            for _ in 0..<3 {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    WKInterfaceDevice.current().play(.notification)
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    private func startInhaleHaptics() {
        inhaleHapticTask?.cancel()
        inhaleHapticTask = Task {
            for _ in 0..<46 {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    WKInterfaceDevice.current().play(.click)
                }
                try? await Task.sleep(nanoseconds: 130_000_000)
            }
        }
    }

    private func completeStretch() {
        didComplete = true
        isSaving = true
        inhaleHapticTask?.cancel()
        playCompletionHaptic()
        let capturedBefore = beforeVitals
        let startDate = sessionStartDate
        Task {
            let after = await healthKit.measureCurrentWellnessVitals()
            let impact: WatchMindfulnessImpact? = capturedBefore.map {
                WatchMindfulnessImpact(sessionType: "Reflect", startDate: startDate, endDate: Date(), before: $0, after: after)
            }
            await healthKit.saveMindfulnessSession(durationMinutes: 3, sessionType: "Reflect", impact: impact)
            await healthKit.fetchTodayMindfulness()
            await MainActor.run {
                isSaving = false
                isPresented = false
            }
        }
    }

    private func playCompletionHaptic() {
        completionHapticTask?.cancel()
        completionHapticTask = Task {
            for index in 0..<4 {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    WKInterfaceDevice.current().play(index % 2 == 0 ? .notification : .success)
                }
                try? await Task.sleep(nanoseconds: 220_000_000)
            }
        }
    }
}

// MARK: - WatchStandFlowView（20分スタンドポモドーロ）

struct WatchStandFlowView: View {
    @Binding var isPresented: Bool
    @State private var elapsedSeconds = 0
    @State private var isSaving = false
    @State private var didComplete = false
    @State private var sessionStartDate = Date()
    @State private var extSession: WKExtendedRuntimeSession?
    @State private var extDelegate: WatchRuntimeSessionDelegate?
    @State private var completionHapticTask: Task<Void, Never>?
    @State private var showCompletion = false
    @State private var completionPulse = false

    private let totalSeconds = 20 * 60
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let tomatoRed      = Color(red: 0.94, green: 0.27, blue: 0.15)
    private let tomatoOrange   = Color(red: 0.99, green: 0.55, blue: 0.12)
    private let tomatoDark     = Color(red: 0.45, green: 0.06, blue: 0.01)
    private let completionGreen = Color(red: 0.15, green: 0.72, blue: 0.38)

    private var remainingSeconds: Int { max(0, totalSeconds - elapsedSeconds) }
    private var remainProgress: Double { min(1.0, Double(elapsedSeconds) / Double(totalSeconds)) }
    private var timeText: String {
        String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.18, green: 0.05, blue: 0.02), Color(red: 0.30, green: 0.10, blue: 0.03)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            if showCompletion {
                watchCompletionScreen
            } else {
                watchTimerScreen
            }
        }
        .onAppear {
            sessionStartDate = Date()
            WKInterfaceDevice.current().play(.start)
            let (s, d) = startExtendedSession { _, _ in
                DispatchQueue.main.async { isPresented = false }
            }
            extSession = s
            extDelegate = d
        }
        .onDisappear {
            completionHapticTask?.cancel()
            extSession?.invalidate()
            extSession = nil
            extDelegate = nil
        }
        .onReceive(timer) { _ in
            guard !didComplete else { return }
            elapsedSeconds = Int(Date().timeIntervalSince(sessionStartDate))
            if elapsedSeconds % 60 == 0 && elapsedSeconds > 0 && elapsedSeconds < totalSeconds {
                WKInterfaceDevice.current().play(.click)
            }
            if elapsedSeconds >= totalSeconds && !showCompletion {
                showCompletion = true
                startCompletionHaptics()
            }
        }
    }

    // MARK: - タイマー進行画面

    private var watchTimerScreen: some View {
        VStack(spacing: 6) {
            VStack(spacing: 1) {
                Text("🍅 20分スタンド")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(tomatoOrange)
                Text("ポモドーロで集中")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(tomatoOrange.opacity(0.75))
            }

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(remainProgress))
                    .stroke(
                        AngularGradient(colors: [tomatoOrange, tomatoRed, tomatoOrange], center: .center),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.8), value: remainProgress)

                ZStack {
                    Circle()
                        .fill(RadialGradient(
                            colors: [Color(red: 0.98, green: 0.32, blue: 0.17),
                                     Color(red: 0.62, green: 0.07, blue: 0.03)],
                            center: UnitPoint(x: 0.38, y: 0.32),
                            startRadius: 2, endRadius: 28
                        ))
                        .frame(width: 54, height: 54)
                    Ellipse()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 16, height: 10)
                        .offset(x: -9, y: -11)
                        .blur(radius: 2)
                    Text(timeText)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: Color(red: 0.4, green: 0.0, blue: 0.0).opacity(0.6), radius: 1, y: 1)
                        .monospacedDigit()
                    Ellipse()
                        .fill(Color(red: 0.16, green: 0.58, blue: 0.16))
                        .frame(width: 13, height: 5)
                        .rotationEffect(.degrees(38))
                        .offset(x: -8, y: -30)
                    Ellipse()
                        .fill(Color(red: 0.16, green: 0.58, blue: 0.16))
                        .frame(width: 13, height: 5)
                        .rotationEffect(.degrees(-38))
                        .offset(x: 8, y: -30)
                    Capsule()
                        .fill(Color(red: 0.13, green: 0.54, blue: 0.13))
                        .frame(width: 5, height: 11)
                        .offset(y: -33)
                }
            }
            .frame(width: 90, height: 90)

            Button { finishAndRecord() } label: {
                Text("完了にする")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(LinearGradient(colors: [tomatoOrange, tomatoRed],
                                               startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - 完了画面

    private var watchCompletionScreen: some View {
        VStack(spacing: 10) {
            Spacer()
            ZStack {
                Circle()
                    .fill(tomatoRed.opacity(0.18))
                    .frame(width: 100, height: 100)
                    .scaleEffect(completionPulse ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                               value: completionPulse)
                Text("🍅")
                    .font(.system(size: 52))
            }
            Text("ポモドーロ達成！")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundColor(tomatoOrange)
            Text("20分、よく立ってました！")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            Button { finishAndRecord() } label: {
                Text("記録して閉じる")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(LinearGradient(colors: [completionGreen, Color(red: 0.08, green: 0.55, blue: 0.28)],
                                               startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .onAppear { completionPulse = true }
    }

    // MARK: - ハプティクス・記録

    private func startCompletionHaptics() {
        playCompletionHaptic()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { WKInterfaceDevice.current().play(.success) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { WKInterfaceDevice.current().play(.success) }
    }

    private func finishAndRecord() {
        guard !didComplete else { return }
        didComplete = true
        isSaving = true
        WatchConnectivityManager.shared.sendStandCompleted()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isSaving = false
            isPresented = false
        }
    }

    private func playCompletionHaptic() {
        completionHapticTask?.cancel()
        completionHapticTask = Task {
            for index in 0..<4 {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    WKInterfaceDevice.current().play(index % 2 == 0 ? .notification : .success)
                }
                try? await Task.sleep(nanoseconds: 220_000_000)
            }
        }
    }
}
