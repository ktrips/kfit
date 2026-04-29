import SwiftUI
import WatchKit

struct WatchQuickWorkoutView: View {
    @Binding var isPresented: Bool
    @StateObject private var motionManager = WatchMotionDetectionManager()

    @State private var selectedType: ExerciseType = .pushup
    /// false = モーション検出（デフォルト）、true = 手動 +/-
    @State private var isManualMode = false
    @State private var manualRepCount = 0
    @State private var workoutStarted = false
    @State private var showCelebration = false
    @State private var earnedXP = 0

    private var currentReps: Int {
        isManualMode ? manualRepCount : motionManager.repCount
    }

    var body: some View {
        if showCelebration {
            celebrationView
        } else if workoutStarted {
            activeWorkoutView
        } else {
            exercisePickerView
        }
    }

    // MARK: - 種目選択（タップで即開始）
    private var exercisePickerView: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text("種目を選んでタップ")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(ExerciseType.allCases, id: \.self) { type in
                    Button(action: { startWorkout(type: type) }) {
                        HStack(spacing: 8) {
                            Text(type.icon).font(.title3)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(type.rawValue)
                                    .font(.subheadline).fontWeight(.bold)
                                    .foregroundColor(.white)
                                Text("\(type.xpPerRep) XP/rep")
                                    .font(.caption2).foregroundColor(.white.opacity(0.75))
                            }
                            Spacer()
                            Image(systemName: "play.fill")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.vertical, 8).padding(.horizontal, 10)
                        .background(Color.green)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }

    // MARK: - トレーニング中
    private var activeWorkoutView: some View {
        VStack(spacing: 0) {
            // ヘッダー（種目名 + モードアイコン）
            HStack(spacing: 4) {
                Text(selectedType.icon).font(.caption)
                Text(selectedType.rawValue)
                    .font(.caption2).fontWeight(.bold)
                    .foregroundColor(isManualMode ? .orange : .green)
                Spacer()
                Image(systemName: isManualMode ? "hand.tap.fill" : "sensor.tag.radiowaves.forward.fill")
                    .font(.caption2)
                    .foregroundColor(isManualMode ? .orange : .green)
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)

            // 大きなカウント
            Text("\(currentReps)")
                .font(.system(size: 52, weight: .black, design: .rounded))
                .foregroundColor(currentReps > 0 ? .green : .gray)
                .frame(maxWidth: .infinity)
                .contentTransition(.numericText())
                .animation(.spring(), value: currentReps)
                .padding(.top, 2)

            // モーション中：フォームスコア
            if !isManualMode {
                HStack(spacing: 4) {
                    Image(systemName: motionManager.formScore > 80
                          ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(motionManager.formScore > 80 ? .green : .orange)
                    Text("\(Int(motionManager.formScore))%")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundColor(motionManager.formScore > 80 ? .green : .orange)
                }
            }

            // 手動モード：+/- ボタン
            if isManualMode {
                HStack(spacing: 16) {
                    Button(action: { if manualRepCount > 0 { manualRepCount -= 1 } }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2).foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    Button(action: { manualRepCount += 1 }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2).foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }

            Spacer(minLength: 4)

            // 下部ボタン（完了 / 切り替え / キャンセル）
            VStack(spacing: 4) {
                // モード切り替え（小ボタン）
                Button(action: toggleMode) {
                    Text(isManualMode ? "自動検出に切替" : "手動入力に切替")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isManualMode ? .green : .orange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background((isManualMode ? Color.green : Color.orange).opacity(0.18))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                HStack(spacing: 6) {
                    Button(action: finishWorkout) {
                        Text("✓ 完了")
                            .font(.caption).fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                            .padding(.vertical, 6)
                            .background(currentReps > 0 ? Color.blue : Color.gray)
                            .cornerRadius(6)
                    }
                    .disabled(currentReps == 0)

                    Button(action: cancelWorkout) {
                        Text("✕")
                            .font(.caption).fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                            .padding(.vertical, 6)
                            .background(Color.red)
                            .cornerRadius(6)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
    }

    // MARK: - XPセレブレーション
    private var celebrationView: some View {
        VStack(spacing: 8) {
            Image("mascot")
                .resizable().scaledToFit()
                .frame(width: 60, height: 60)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.green, lineWidth: 2))

            Text("やったー！")
                .font(.system(.headline, design: .rounded)).fontWeight(.black)
                .foregroundColor(.green)

            HStack(spacing: 4) {
                Text("⭐")
                Text("+\(earnedXP) XP")
                    .font(.title2).fontWeight(.black)
                    .foregroundColor(Color(red: 0.7, green: 0.52, blue: 0))
            }

            Button(action: { isPresented = false }) {
                Text("完了")
                    .font(.caption).fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .padding(.vertical, 6)
                    .background(Color.green)
                    .cornerRadius(6)
            }
        }
        .padding()
    }

    // MARK: - アクション

    private func startWorkout(type: ExerciseType) {
        selectedType  = type
        isManualMode  = false
        manualRepCount = 0
        workoutStarted = true
        motionManager.startDetection(for: type)
        WKInterfaceDevice.current().play(.start)
    }

    private func toggleMode() {
        if isManualMode {
            // 手動 → モーション
            isManualMode = false
            motionManager.startDetection(for: selectedType)
        } else {
            // モーション → 手動（現在のカウントを引き継ぐ）
            manualRepCount = motionManager.repCount
            isManualMode = true
            motionManager.stopDetection()
        }
        WKInterfaceDevice.current().play(.click)
    }

    private func finishWorkout() {
        motionManager.stopDetection()
        earnedXP = currentReps * selectedType.xpPerRep

        let workout = WorkoutData(
            exerciseName: selectedType.rawValue,
            reps: currentReps,
            points: earnedXP,
            timestamp: Date()
        )
        WatchConnectivityManager.shared.sendWorkout(workout)
        WatchConnectivityManager.shared.addRecentWorkout("\(currentReps) \(selectedType.rawValue)")
        WatchConnectivityManager.shared.todayReps += currentReps
        WatchConnectivityManager.shared.todayXP   += earnedXP

        WKInterfaceDevice.current().play(.success)
        withAnimation { showCelebration = true }
    }

    private func cancelWorkout() {
        motionManager.stopDetection()
        manualRepCount = 0
        workoutStarted = false
        isPresented = false
    }
}

#Preview {
    WatchQuickWorkoutView(isPresented: .constant(true))
}
