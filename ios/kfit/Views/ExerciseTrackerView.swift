import SwiftUI

struct ExerciseTrackerView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var motionManager = MotionDetectionManager()
    @State private var selectedExercise: Exercise?
    @State private var manualRepCount = 0
    @State private var isUsingMotionDetection = false
    @State private var showCelebration = false
    @State private var earnedXP = 0
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.duoBg.ignoresSafeArea()

            if showCelebration {
                celebrationView
            } else {
                VStack(spacing: 0) {
                    // ヘッダー
                    HStack(spacing: 12) {
                        Image("mascot")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.duoGreen, lineWidth: 2))

                        Text("トレーニング記録")
                            .font(.title3)
                            .fontWeight(.black)
                            .foregroundColor(Color.duoGreen)

                        Spacer()

                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color.white)
                    .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)

                    ScrollView {
                        VStack(spacing: 20) {
                            // 種目選択
                            exerciseSelectionCard

                            // repカウンター
                            if selectedExercise != nil {
                                repCounterCard
                                submitButton
                            }

                            Spacer(minLength: 40)
                        }
                        .padding(.vertical, 20)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .onDisappear { motionManager.stopDetection() }
    }

    // MARK: - 種目選択
    private var exerciseSelectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("種目を選択")
                .font(.headline)
                .fontWeight(.bold)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(authManager.exercises) { exercise in
                    Button(action: { selectedExercise = exercise }) {
                        Text(exercise.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(selectedExercise?.id == exercise.id ? Color.duoGreen : Color(.systemGray5))
                            .foregroundColor(selectedExercise?.id == exercise.id ? .white : .primary)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selectedExercise?.id == exercise.id ? Color.duoGreen : Color.clear, lineWidth: 2)
                            )
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
        .padding(.horizontal, 20)
    }

    // MARK: - Repカウンター
    private var repCounterCard: some View {
        guard let exercise = selectedExercise else { return AnyView(EmptyView()) }

        let reps = isUsingMotionDetection ? motionManager.repCount : manualRepCount
        let xp = reps * exercise.basePoints

        return AnyView(
            VStack(spacing: 16) {
                // Rep表示
                VStack(spacing: 8) {
                    Text("Rep数")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("\(reps)")
                        .font(.system(size: 64, weight: .black))
                        .foregroundColor(Color.duoGreen)

                    if !isUsingMotionDetection {
                        HStack(spacing: 24) {
                            Button(action: { if manualRepCount > 0 { manualRepCount -= 1 } }) {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundColor(Color.duoRed)
                            }
                            Button(action: { manualRepCount += 1 }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundColor(Color.duoGreen)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(Color.duoGreen.opacity(0.08))
                .cornerRadius(16)

                // XP計算
                HStack {
                    Text("獲得XP")
                        .font(.headline)
                    Spacer()
                    Text("+\(xp) XP")
                        .font(.title3)
                        .fontWeight(.black)
                        .foregroundColor(Color.duoYellow)
                }
                .padding(16)
                .background(Color.duoYellow.opacity(0.1))
                .cornerRadius(12)

                // フォームスコア（モーション使用時）
                if isUsingMotionDetection {
                    HStack {
                        Text("フォームスコア")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(motionManager.formScore))%")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(motionManager.formScore > 80 ? Color.duoGreen : Color.duoOrange)
                    }
                    ProgressView(value: motionManager.formScore / 100)
                        .tint(motionManager.formScore > 80 ? Color.duoGreen : Color.duoOrange)
                }

                // モーション検出トグル
                Toggle("モーション自動検出（iPhone）", isOn: $isUsingMotionDetection)
                    .tint(Color.duoGreen)
                    .onChange(of: isUsingMotionDetection) { _, newValue in
                        if newValue {
                            motionManager.startDetection(for: .pushup)
                        } else {
                            motionManager.stopDetection()
                        }
                    }
            }
            .padding(20)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
            .padding(.horizontal, 20)
        )
    }

    // MARK: - 送信ボタン
    private var submitButton: some View {
        let reps = isUsingMotionDetection ? motionManager.repCount : manualRepCount
        return Button(action: submitWorkout) {
            Text("✓ トレーニングを記録")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(reps == 0 ? Color(.systemGray4) : Color.duoGreen)
                .cornerRadius(14)
                .shadow(color: reps == 0 ? .clear : Color.duoGreen.opacity(0.4), radius: 4, y: 3)
        }
        .disabled(reps == 0)
        .padding(.horizontal, 20)
    }

    // MARK: - セレブレーション画面
    private var celebrationView: some View {
        VStack(spacing: 32) {
            Spacer()

            Image("mascot")
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.duoGreen, lineWidth: 4))
                .shadow(color: Color.duoOrange.opacity(0.6), radius: 20)

            VStack(spacing: 12) {
                Text("やったー！🎉")
                    .font(.system(size: 36, weight: .black))
                    .foregroundColor(Color.duoGreen)

                Text("+\(earnedXP) XP 獲得！")
                    .font(.title)
                    .fontWeight(.black)
                    .foregroundColor(Color.duoYellow)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.duoYellow.opacity(0.15))
                    .cornerRadius(16)

                Text("この調子で続けよう！")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { dismiss() }) {
                Text("ダッシュボードに戻る")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.duoGreen)
                    .cornerRadius(14)
                    .shadow(color: Color.duoGreen.opacity(0.4), radius: 4, y: 3)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color.duoBg.ignoresSafeArea())
    }

    // MARK: - 送信処理
    private func submitWorkout() {
        guard let exercise = selectedExercise else { return }
        let reps = isUsingMotionDetection ? motionManager.repCount : manualRepCount
        let formScore = isUsingMotionDetection ? motionManager.formScore : 85.0
        earnedXP = reps * exercise.basePoints

        Task {
            await authManager.recordExercise(exercise, reps: reps, formScore: formScore)
            withAnimation(.spring()) {
                showCelebration = true
            }
        }
    }
}

#Preview {
    ExerciseTrackerView()
        .environmentObject(AuthenticationManager.shared)
}
