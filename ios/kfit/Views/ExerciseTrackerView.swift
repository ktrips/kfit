import SwiftUI

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

struct ExerciseTrackerView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var motionManager = MotionDetectionManager()

    @State private var selectedExercise: Exercise?
    /// true = 手動 +/- モード、false = モーション検出（デフォルト）
    @State private var isManualMode = false
    @State private var manualRepCount = 0
    /// プランク用タイマー（秒）
    @State private var plankSeconds = 0
    @State private var plankTimer: Timer?

    @State private var showCelebration = false
    @State private var earnedXP = 0
    @State private var isSubmitting = false
    @State private var pulseAnimation = false

    @Environment(\.dismiss) var dismiss

    private var isPlankSelected: Bool { isPlank(selectedExercise) }

    private var currentReps: Int {
        if isPlankSelected { return plankSeconds }
        return isManualMode ? manualRepCount : motionManager.repCount
    }

    var body: some View {
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
                        VStack(spacing: 16) {
                            exerciseGrid
                            if selectedExercise != nil {
                                repCounter
                                recordButton
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 32)
                    }
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .onChange(of: selectedExercise?.id) { _ in
            onExerciseChanged()
        }
        .onDisappear {
            motionManager.stopDetection()
            stopPlankTimer()
        }
    }

    // MARK: - ヘッダー
    private var header: some View {
        HStack(spacing: 10) {
            Image("mascot")
                .resizable().scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.duoGreen, lineWidth: 2))
                .shadow(color: Color.duoGreen.opacity(0.3), radius: 4)

            Text("トレーニング記録")
                .font(.title3).fontWeight(.black)
                .foregroundColor(.primary)

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .padding(.top, 60)
        .background(Color.white)
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 3)
    }

    // MARK: - 種目グリッド
    private var exerciseGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "figure.strengthtraining.traditional")
                Text("種目を選ぼう").fontWeight(.black)
            }
            .font(.headline)
            .foregroundColor(.primary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(authManager.exercises) { exercise in
                    let selected = selectedExercise?.id == exercise.id
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            selectedExercise = exercise
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Text(emoji(for: exercise.name))
                                .font(.system(size: 32))
                            Text(exercise.name)
                                .font(.subheadline).fontWeight(.bold)
                                .foregroundColor(selected ? .white : .primary)
                            Text("\(exercise.basePoints) XP/rep")
                                .font(.caption2)
                                .foregroundColor(selected ? Color.white.opacity(0.92) : Color.duoSubtitle)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(selected ? Color.duoGreen : Color.white)
                        .cornerRadius(16)
                        .shadow(
                            color: selected ? Color.duoGreen.opacity(0.4) : Color.black.opacity(0.06),
                            radius: selected ? 6 : 3, y: selected ? 3 : 2
                        )
                        .scaleEffect(selected ? 1.03 : 1.0)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.05), radius: 6, y: 2)
    }

    // MARK: - Repカウンター
    private var repCounter: some View {
        VStack(spacing: 16) {
            // モードバッジ
            HStack(spacing: 6) {
                if isPlankSelected {
                    Image(systemName: "timer")
                        .font(.caption).foregroundColor(Color.duoBlue)
                    Text("タイマーモード（プランク）")
                        .font(.caption).fontWeight(.bold).foregroundColor(Color.duoBlue)
                } else if isManualMode {
                    Image(systemName: "hand.tap.fill")
                        .font(.caption).foregroundColor(Color.duoOrange)
                    Text("手動入力モード")
                        .font(.caption).fontWeight(.bold).foregroundColor(Color.duoOrange)
                } else {
                    Image(systemName: "sensor.tag.radiowaves.forward.fill")
                        .font(.caption).foregroundColor(Color.duoGreen)
                        .scaleEffect(pulseAnimation ? 1.15 : 1.0)
                        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                                   value: pulseAnimation)
                    Text("モーション検出中")
                        .font(.caption).fontWeight(.bold).foregroundColor(Color.duoGreen)
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            // 大きなカウント表示
            VStack(spacing: 4) {
                Text("\(currentReps)")
                    .font(.system(size: 80, weight: .black, design: .rounded))
                    .foregroundColor(currentReps > 0 ? Color.duoGreen : Color(.systemGray3))
                    .animation(.spring(), value: currentReps)
                Text(isPlankSelected ? "秒" : "reps")
                    .font(.title3).fontWeight(.bold)
                    .foregroundColor(Color.duoSubtitle)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(currentReps > 0 ? Color.duoGreen.opacity(0.08) : Color(.systemGray6))
            )

            // モーション中：フォームスコア
            if !isManualMode && !isPlankSelected && motionManager.isDetecting {
                VStack(spacing: 6) {
                    HStack {
                        Text("フォームスコア")
                            .font(.caption).fontWeight(.semibold).foregroundColor(Color.duoSubtitle)
                        Spacer()
                        Text("\(Int(motionManager.formScore))%")
                            .font(.caption).fontWeight(.black)
                            .foregroundColor(motionManager.formScore > 80 ? Color.duoGreen : Color.duoOrange)
                    }
                    ProgressView(value: motionManager.formScore / 100)
                        .tint(motionManager.formScore > 80 ? Color.duoGreen : Color.duoOrange)
                }
            }

            // 手動モード：+/- ボタン
            if isManualMode && !isPlankSelected {
                HStack(spacing: 20) {
                    CountButton(icon: "minus", color: Color.duoRed) {
                        withAnimation(.spring()) {
                            if manualRepCount > 0 { manualRepCount -= 1 }
                        }
                    }

                    VStack(spacing: 2) {
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
                HStack(spacing: 12) {
                    if plankTimer == nil {
                        Button(action: startPlankTimer) {
                            Label("タイマー開始", systemImage: "play.circle.fill")
                                .font(Font.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.vertical, 10).padding(.horizontal, 16)
                                .background(Color.duoGreen).cornerRadius(12)
                        }
                    } else {
                        Button(action: stopPlankTimer) {
                            Label("停止", systemImage: "stop.circle.fill")
                                .font(Font.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.vertical, 10).padding(.horizontal, 16)
                                .background(Color.duoOrange).cornerRadius(12)
                        }
                    }
                    Button(action: { plankSeconds = 0; stopPlankTimer() }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(Font.system(size: 15, weight: .bold))
                            .foregroundColor(Color.duoSubtitle)
                            .padding(10)
                            .background(Color(.systemGray5)).cornerRadius(10)
                    }
                }
            }

            // XP プレビュー
            if let ex = selectedExercise, currentReps > 0 {
                HStack {
                    Image(systemName: "bolt.fill").foregroundColor(Color.duoGold)
                    Text("今回の獲得 XP")
                        .font(.subheadline).fontWeight(.semibold).foregroundColor(Color.duoDark)
                    Spacer()
                    Text("+\(currentReps * ex.basePoints) XP")
                        .font(.title3).fontWeight(.black).foregroundColor(Color.duoGold)
                }
                .padding(14)
                .background(Color.duoYellow.opacity(0.18))
                .cornerRadius(14)
            }

            // モード切り替えボタン（プランクは非表示）
            if !isPlankSelected {
                Button(action: toggleMode) {
                    HStack(spacing: 6) {
                        Image(systemName: isManualMode
                              ? "sensor.tag.radiowaves.forward.fill"
                              : "hand.tap.fill")
                            .font(.caption)
                        Text(isManualMode ? "自動検出に切り替え" : "手動入力に切り替え")
                            .font(.caption).fontWeight(.semibold)
                    }
                    .foregroundColor(isManualMode ? Color.duoGreen : Color.duoSubtitle)
                    .padding(.vertical, 8).padding(.horizontal, 14)
                    .background((isManualMode ? Color.duoGreen : Color(.systemGray4)).opacity(0.12))
                    .cornerRadius(10)
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.05), radius: 6, y: 2)
    }

    // MARK: - 記録ボタン
    private var recordButton: some View {
        Button {
            guard !isSubmitting else { return }
            submitWorkout()
        } label: {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                    Text("記録する！").fontWeight(.black)
                }
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(currentReps == 0 ? Color(.systemGray3) : Color.duoGreen)
            .cornerRadius(18)
            .shadow(
                color: currentReps > 0 ? Color.duoGreen.opacity(0.45) : .clear,
                radius: 6, y: 4
            )
        }
        .disabled(currentReps == 0 || isSubmitting)
        .animation(.easeInOut, value: currentReps)
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

    private func onExerciseChanged() {
        // リセット
        motionManager.stopDetection()
        stopPlankTimer()
        manualRepCount = 0
        plankSeconds  = 0
        isManualMode  = false

        guard let ex = selectedExercise else { return }

        if isPlank(ex) {
            // プランク → タイマーモード
        } else {
            // その他 → モーション検出を即時スタート
            let type = ExerciseType.from(exerciseId: ex.id ?? ex.name)
            motionManager.startDetection(for: type)
            withAnimation { pulseAnimation = true }
        }
    }

    private func toggleMode() {
        if isManualMode {
            // 手動 → モーション検出に切り替え
            isManualMode = false
            if let ex = selectedExercise {
                motionManager.startDetection(for: ExerciseType.from(exerciseId: ex.id ?? ex.name))
                withAnimation { pulseAnimation = true }
            }
        } else {
            // モーション → 手動に切り替え
            isManualMode = true
            motionManager.stopDetection()
            pulseAnimation = false
            manualRepCount = motionManager.repCount  // 現在のカウントを引き継ぐ
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

    private func submitWorkout() {
        guard let exercise = selectedExercise, currentReps > 0 else { return }
        stopPlankTimer()
        let formScore = (!isManualMode && !isPlankSelected) ? motionManager.formScore : 85.0
        earnedXP = currentReps * exercise.basePoints
        isSubmitting = true
        Task {
            await authManager.recordExercise(exercise, reps: currentReps, formScore: formScore)
            withAnimation(.spring(response: 0.5)) {
                isSubmitting = false
                showCelebration = true
            }
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
                .font(.system(size: 56))
                .foregroundColor(color)
                .shadow(color: color.opacity(0.35), radius: 4, y: 3)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ExerciseTrackerView()
        .environmentObject(AuthenticationManager.shared)
}
