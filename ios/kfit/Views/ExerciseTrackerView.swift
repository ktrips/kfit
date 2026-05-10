import SwiftUI
import UIKit

private let exerciseEmoji: [String: String] = [
    "pushup": "💪", "push-up": "💪",
    "squat": "🏋️", "situp": "🔥", "sit-up": "🔥",
    "lunge": "🦵", "burpee": "⚡", "plank": "🧘"
]

private func emoji(for name: String) -> String {
    let key = name.lowercased().replacingOccurrences(of: " ", with: "")
    for (k, v) in exerciseEmoji { if key.contains(k) { return v } }
    return "🏃"
}

private func isPlank(_ exercise: Exercise?) -> Bool {
    let id = (exercise?.id ?? exercise?.name ?? "").lowercased()
    return id.contains("plank")
}

// 固定の連続フロー（Watchと同じ）
private let flowSteps: [(emoji: String, name: String, target: Int, id: String, xp: Int)] = [
    ("🏋️", "スクワット", 20, "squat", 2),
    ("💪", "腕立て伏せ", 15, "pushup", 2),
    ("🔥", "腹筋", 15, "situp", 1),
    ("🧘", "プランク", 45, "plank", 1),
    ("🦵", "ランジ", 20, "lunge", 2),
]

struct ExerciseTrackerView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var motionManager = MotionDetectionManager()
    @Environment(\.dismiss) var dismiss

    // フロー管理
    @State private var stepIdx = 0
    @State private var showCelebration = false
    @State private var showGoalReached = false
    @State private var earnedXP = 0
    @State private var isSubmitting = false

    // 現在の種目の記録
    @State private var isManualMode = false
    @State private var manualRepCount = 0
    @State private var plankSeconds = 0
    @State private var plankTimer: Timer?
    @State private var pulseAnimation = false

    /// セット内の記録済み種目
    @State private var completedExercises: [(name: String, emoji: String, reps: Int, points: Int)] = []

    private var current: (emoji: String, name: String, target: Int, id: String, xp: Int) {
        flowSteps[stepIdx]
    }
    private var isLast: Bool { stepIdx == flowSteps.count - 1 }
    private var isPlankSelected: Bool { current.id == "plank" }

    private var currentReps: Int {
        if isPlankSelected { return plankSeconds }
        return isManualMode ? manualRepCount : motionManager.repCount
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [Color.duoGreen.opacity(0.08), Color.duoBg],
                    startPoint: .top, endPoint: .bottom
                ).ignoresSafeArea()

                if showCelebration {
                    celebrationView
                } else {
                    VStack(spacing: 0) {
                        header
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 10) {
                                progressDots
                                if !completedExercises.isEmpty {
                                    completedList
                                }
                                currentExerciseCard
                                repCounter
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                            .padding(.bottom, geometry.safeAreaInsets.bottom + 70)
                        }
                    }

                    VStack {
                        Spacer()
                        recordButton
                            .padding(.horizontal, 12)
                            .padding(.bottom, max(geometry.safeAreaInsets.bottom, 8))
                            .padding(.top, 8)
                            .background(
                                Rectangle()
                                    .fill(Color.duoBg.opacity(0.98))
                                    .ignoresSafeArea(edges: .bottom)
                            )
                    }
                }

                if showGoalReached {
                    goalReachedOverlay
                }
            }
            .ignoresSafeArea()
        }
        .persistentSystemOverlays(.hidden)
        .onAppear {
            startCurrentExercise()
        }
        .onDisappear {
            motionManager.stopDetection()
            stopPlankTimer()
        }
        .onChange(of: motionManager.repCount) { count in
            guard !isManualMode && !isPlankSelected else { return }
            if count == current.target && !showGoalReached { triggerGoalReached() }
        }
        .onChange(of: manualRepCount) { count in
            guard isManualMode && !isPlankSelected else { return }
            if count == current.target && !showGoalReached { triggerGoalReached() }
        }
        .onChange(of: plankSeconds) { seconds in
            guard isPlankSelected else { return }
            if seconds == current.target && !showGoalReached { triggerGoalReached() }
        }
    }

    // MARK: - 進捗ドット
    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<flowSteps.count, id: \.self) { i in
                Circle()
                    .fill(i < stepIdx ? Color.duoGreen : i == stepIdx ? Color.duoBlue : Color.gray.opacity(0.3))
                    .frame(width: i == stepIdx ? 10 : 7, height: i == stepIdx ? 10 : 7)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - 現在の種目カード
    private var currentExerciseCard: some View {
        VStack(spacing: 12) {
            Text(current.emoji).font(.system(size: 70))
            Text(current.name)
                .font(.title2).fontWeight(.black)
                .foregroundColor(Color.duoGreen)
            if isPlankSelected {
                Text("目標: \(current.target) 秒")
                    .font(.caption).foregroundColor(Color.duoSubtitle)
            } else {
                Text("目標: \(current.target) 回")
                    .font(.caption).foregroundColor(Color.duoSubtitle)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - ヘッダー（コンパクト）
    private var header: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 3) {
                    Image("mascot")
                        .resizable().scaledToFill()
                        .frame(width: 14, height: 14)
                        .clipShape(Circle())

                    Text("トレーニング")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.duoDark)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color.duoSubtitle)
                        .padding(3)
                        .background(Color.white.opacity(0.8))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, geometry.safeAreaInsets.top > 0 ? geometry.safeAreaInsets.top + 2 : 6)
            .padding(.bottom, 1)
            .background(Color.duoBg.opacity(0.95))
        }
        .frame(height: 28)
    }

    // MARK: - Repカウンター
    private var repCounter: some View {
        VStack(spacing: 12) {
            // モードバッジ
            HStack(spacing: 4) {
                if isPlankSelected {
                    Image(systemName: "timer")
                        .font(.caption2).foregroundColor(Color.duoBlue)
                    Text("タイマー")
                        .font(.caption2).fontWeight(.bold).foregroundColor(Color.duoBlue)
                } else if isManualMode {
                    Image(systemName: "hand.tap.fill")
                        .font(.caption2).foregroundColor(Color.duoOrange)
                    Text("手動入力")
                        .font(.caption2).fontWeight(.bold).foregroundColor(Color.duoOrange)
                } else {
                    Image(systemName: "sensor.tag.radiowaves.forward.fill")
                        .font(.caption2).foregroundColor(Color.duoGreen)
                        .scaleEffect(pulseAnimation ? 1.15 : 1.0)
                        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                                   value: pulseAnimation)
                    Text("モーション検出中")
                        .font(.caption2).fontWeight(.bold).foregroundColor(Color.duoGreen)
                }
                Spacer()
            }
            .padding(.horizontal, 2)

            // 大きなカウント表示
            VStack(spacing: 2) {
                Text("\(currentReps)")
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundColor(currentReps > 0 ? Color.duoGreen : Color(.systemGray3))
                    .animation(.spring(), value: currentReps)
                Text(isPlankSelected ? "秒" : "reps")
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(Color.duoSubtitle)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(currentReps > 0 ? Color.duoGreen.opacity(0.08) : Color(.systemGray6))
            )

            // モーション中：フォームスコア
            if !isManualMode && !isPlankSelected && motionManager.isDetecting {
                VStack(spacing: 4) {
                    HStack {
                        Text("フォーム")
                            .font(.caption2).fontWeight(.semibold).foregroundColor(Color.duoSubtitle)
                        Spacer()
                        Text("\(Int(motionManager.formScore))%")
                            .font(.caption2).fontWeight(.black)
                            .foregroundColor(motionManager.formScore > 80 ? Color.duoGreen : Color.duoOrange)
                    }
                    ProgressView(value: motionManager.formScore / 100)
                        .tint(motionManager.formScore > 80 ? Color.duoGreen : Color.duoOrange)
                }
            }

            // 手動モード：+/- ボタン
            if isManualMode && !isPlankSelected {
                HStack(spacing: 16) {
                    CountButton(icon: "minus", color: Color.duoRed) {
                        withAnimation(.spring()) {
                            if manualRepCount > 0 { manualRepCount -= 1 }
                        }
                    }

                    VStack(spacing: 1) {
                        Text("タップで")
                            .font(.caption2).foregroundColor(Color.duoSubtitle)
                        Text("カウント")
                            .font(.caption2).foregroundColor(Color.duoSubtitle)
                    }

                    CountButton(icon: "plus", color: Color.duoGreen) {
                        withAnimation(.spring()) { manualRepCount += 1 }
                    }
                }
            }

            // プランク：タイマー操作
            if isPlankSelected {
                HStack(spacing: 10) {
                    if plankTimer == nil {
                        Button(action: startPlankTimer) {
                            Label("開始", systemImage: "play.circle.fill")
                                .font(Font.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.vertical, 8).padding(.horizontal, 14)
                                .background(Color.duoGreen).cornerRadius(10)
                        }
                    } else {
                        Button(action: stopPlankTimer) {
                            Label("停止", systemImage: "stop.circle.fill")
                                .font(Font.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.vertical, 8).padding(.horizontal, 14)
                                .background(Color.duoOrange).cornerRadius(10)
                        }
                    }
                    Button(action: { plankSeconds = 0; stopPlankTimer() }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(Font.system(size: 14, weight: .bold))
                            .foregroundColor(Color.duoSubtitle)
                            .padding(8)
                            .background(Color(.systemGray5)).cornerRadius(8)
                    }
                }
            }

            // XP プレビュー
            if currentReps > 0 {
                HStack {
                    Image(systemName: "bolt.fill").foregroundColor(Color.duoGold)
                    Text("獲得 XP")
                        .font(.caption).fontWeight(.semibold).foregroundColor(Color.duoDark)
                    Spacer()
                    Text("+\(currentReps * current.xp) XP")
                        .font(.callout).fontWeight(.black).foregroundColor(Color.duoGold)
                }
                .padding(10)
                .background(Color.duoYellow.opacity(0.18))
                .cornerRadius(12)
            }

            // モード切り替えボタン（プランクは非表示）
            if !isPlankSelected {
                Button(action: { isManualMode.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: isManualMode
                              ? "sensor.tag.radiowaves.forward.fill"
                              : "hand.tap.fill")
                            .font(.caption2)
                        Text(isManualMode ? "自動検出に切替" : "手動入力に切替")
                            .font(.caption2).fontWeight(.semibold)
                    }
                    .foregroundColor(isManualMode ? Color.duoGreen : Color.duoSubtitle)
                    .padding(.vertical, 6).padding(.horizontal, 12)
                    .background((isManualMode ? Color.duoGreen : Color(.systemGray4)).opacity(0.12))
                    .cornerRadius(8)
                }
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - 記録ボタン（次へ/完了）
    private var recordButton: some View {
        Button {
            guard !isSubmitting else { return }
            advance()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isLast ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                Text(isLast ? "完了！" : "次へ").fontWeight(.black)
            }
            .font(.subheadline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isLast ? Color.duoGreen : Color.duoBlue)
            .cornerRadius(14)
            .shadow(
                color: isLast ? Color.duoGreen.opacity(0.45) : Color.duoBlue.opacity(0.45),
                radius: 4, y: 3
            )
        }
        .disabled(isSubmitting)
    }

    // MARK: - 完了リスト
    private var completedList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("完了")
                .font(.caption2).fontWeight(.bold).foregroundColor(Color.duoSubtitle)
            ForEach(0..<completedExercises.count, id: \.self) { idx in
                let item = completedExercises[idx]
                HStack {
                    Text(item.emoji).font(.callout)
                    Text(item.name).font(.caption).fontWeight(.medium)
                    Spacer()
                    if item.name.lowercased().contains("プランク") {
                        Text("\(item.reps)秒").font(.caption2).foregroundColor(Color.duoSubtitle)
                    } else {
                        Text("\(item.reps)回").font(.caption2).foregroundColor(Color.duoSubtitle)
                    }
                    Text("+\(item.points)").font(.caption2).fontWeight(.bold).foregroundColor(Color.duoGold)
                }
                .padding(.vertical, 6)
            }
        }
        .padding(12)
        .background(Color.duoYellow.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - 目標達成フラッシュ
    private var goalReachedOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("🎯")
                    .font(.system(size: 72))
                Text("Good job!")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundColor(Color.duoGreen)
                if isPlankSelected {
                    Text("目標 \(current.target) 秒 達成！")
                        .font(.headline).fontWeight(.bold)
                        .foregroundColor(.white)
                } else {
                    Text("目標 \(current.target) 回 達成！")
                        .font(.headline).fontWeight(.bold)
                        .foregroundColor(.white)
                }
                Text("続けても記録できます 💪")
                    .font(.subheadline).foregroundColor(.white.opacity(0.75))
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.black.opacity(0.85))
                    .shadow(color: Color.duoGreen.opacity(0.4), radius: 20)
            )
            .padding(32)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.85)))
    }

    // MARK: - セレブレーション
    private var celebrationView: some View {
        ZStack {
            Color.duoGreen.opacity(0.07).ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                Image("mascot")
                    .resizable().scaledToFill()
                    .frame(width: 150, height: 150)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.duoGreen, lineWidth: 5))
                    .shadow(color: Color.duoGreen.opacity(0.5), radius: 20)

                VStack(spacing: 10) {
                    Text("やったー！🎉")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundColor(Color.duoGreen)

                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                        Text("+\(earnedXP) XP").fontWeight(.black)
                    }
                    .font(.largeTitle)
                    .foregroundColor(Color.duoGold)
                    .padding(.horizontal, 28).padding(.vertical, 14)
                    .background(
                        Capsule().fill(Color.duoYellow.opacity(0.25))
                            .overlay(Capsule().stroke(Color.duoYellow.opacity(0.5), lineWidth: 2))
                    )

                    Text("この調子で続けよう！")
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(Color.duoSubtitle)
                }

                Spacer()

                Button { dismiss() } label: {
                    Text("ダッシュボードへ戻る")
                        .font(.headline).fontWeight(.black)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.duoGreen)
                        .cornerRadius(18)
                        .shadow(color: Color.duoGreen.opacity(0.4), radius: 6, y: 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - ロジック

    private func triggerGoalReached() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            showGoalReached = true
        }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { showGoalReached = false }
        }
    }

    private func startPlankTimer() {
        plankTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in plankSeconds += 1 }
        }
    }

    private func stopPlankTimer() {
        plankTimer?.invalidate()
        plankTimer = nil
    }

    // 現在の種目のモーション検出を開始
    private func startCurrentExercise() {
        guard !isPlankSelected && !isManualMode else { return }

        let type: ExerciseType
        switch current.id {
        case "pushup": type = .pushup
        case "squat": type = .squat
        case "situp": type = .situp
        case "lunge": type = .lunge
        case "burpee": type = .burpee
        default: return
        }

        motionManager.startDetection(for: type)
        pulseAnimation = true
    }

    // 次の種目へ進む / セット完了
    private func advance() {
        stopPlankTimer()
        motionManager.stopDetection()

        let xp = currentReps * current.xp
        earnedXP += xp
        completedExercises.append((current.name, current.emoji, currentReps, xp))

        // 記録を保存
        Task {
            await authManager.recordExerciseDirect(
                exerciseId: current.id,
                exerciseName: current.name,
                reps: currentReps,
                points: xp
            )
        }

        if isLast {
            // 全種目完了
            isSubmitting = true
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    isSubmitting = false
                    showCelebration = true
                }
            }
        } else {
            // 次の種目へ
            stepIdx += 1
            manualRepCount = 0
            plankSeconds = 0
            pulseAnimation = false
            startCurrentExercise()
        }
    }
}

// MARK: - +/- ボタン
private struct CountButton: View {
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "\(icon).circle.fill")
                .font(.system(size: 48))
                .foregroundColor(color)
                .shadow(color: color.opacity(0.35), radius: 3, y: 2)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ExerciseTrackerView()
        .environmentObject(AuthenticationManager.shared)
}
