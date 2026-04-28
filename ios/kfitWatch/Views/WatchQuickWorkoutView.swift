import SwiftUI
import WatchKit

struct WatchQuickWorkoutView: View {
    @Binding var isPresented: Bool
    @StateObject private var motionManager = WatchMotionDetectionManager()
    @State private var selectedExerciseType: ExerciseType = .pushup
    @State private var isUsingMotion = true
    @State private var manualRepCount = 0
    @State private var showCalibration = false
    @State private var showCelebration = false
    @State private var earnedXP = 0

    private let xpPerRep: [ExerciseType: Int] = [
        .pushup: 2,
        .squat: 2,
        .situp: 1,
    ]

    var currentReps: Int {
        isUsingMotion ? motionManager.repCount : manualRepCount
    }

    var body: some View {
        if showCelebration {
            celebrationView
        } else {
            TabView {
                exerciseSelectionPage
                if motionManager.isDetecting { repCounterPage }
                settingsPage
            }
            .tabViewStyle(.page)
        }
    }

    // MARK: - 種目選択
    private var exerciseSelectionPage: some View {
        VStack(spacing: 8) {
            Text("種目")
                .font(.headline)
                .foregroundColor(.green)

            Picker("種目", selection: $selectedExerciseType) {
                ForEach(ExerciseType.allCases, id: \.self) { type in
                    Text("\(type.icon) \(type.rawValue)").tag(type)
                }
            }
            .pickerStyle(.wheel)

            Spacer()

            if !motionManager.isDetecting {
                Button(action: startWorkout) {
                    Text("▶ 開始")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .cornerRadius(6)
                }
            }
        }
        .padding()
    }

    // MARK: - Repカウンター
    private var repCounterPage: some View {
        VStack(spacing: 8) {
            Text(selectedExerciseType.rawValue)
                .font(.caption2)
                .foregroundColor(.gray)

            Text("\(currentReps)")
                .font(.system(size: 44, weight: .black))
                .foregroundColor(.green)

            if isUsingMotion {
                HStack(spacing: 4) {
                    Image(systemName: motionManager.formScore > 80 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundColor(motionManager.formScore > 80 ? .green : .orange)
                    Text("\(Int(motionManager.formScore))%")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
            } else {
                HStack(spacing: 12) {
                    Button(action: { if manualRepCount > 0 { manualRepCount -= 1 } }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3).foregroundColor(.red)
                    }
                    Button(action: { manualRepCount += 1 }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3).foregroundColor(.green)
                    }
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Button(action: finishWorkout) {
                    Text("✓ 完了")
                        .font(.caption).fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .cornerRadius(4)
                }
                Button(action: cancelWorkout) {
                    Text("✕")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                        .padding(.vertical, 6)
                        .background(Color.red)
                        .cornerRadius(4)
                }
            }
        }
        .padding()
    }

    // MARK: - 設定
    private var settingsPage: some View {
        VStack(spacing: 10) {
            Text("設定")
                .font(.headline)

            Toggle("モーション検出", isOn: $isUsingMotion)
                .tint(.green)
                .onChange(of: isUsingMotion) { newValue in
                    if newValue && !motionManager.isDetecting {
                        showCalibration = true
                    }
                }

            if isUsingMotion {
                Button(action: { showCalibration = true }) {
                    Text("キャリブレーション")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                        .padding(.vertical, 6)
                        .background(Color.orange)
                        .cornerRadius(4)
                }
            }

            Spacer()

            Text(motionManager.isDetecting ? "検出中..." : "待機中")
                .font(.caption2).foregroundColor(.gray)
        }
        .padding()
        .sheet(isPresented: $showCalibration) {
            CalibrationView(isPresented: $showCalibration, motionManager: motionManager)
        }
    }

    // MARK: - XPセレブレーション
    private var celebrationView: some View {
        VStack(spacing: 10) {
            Image("mascot")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.green, lineWidth: 2))

            Text("やったー！")
                .font(.system(.headline, design: .rounded))
                .fontWeight(.black)
                .foregroundColor(.green)

            Text("+\(earnedXP) XP")
                .font(.title2)
                .fontWeight(.black)
                .foregroundColor(.yellow)

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
    private func startWorkout() {
        if isUsingMotion {
            motionManager.startDetection(for: selectedExerciseType)
        } else {
            motionManager.isDetecting = true
            manualRepCount = 0
        }
    }

    private func finishWorkout() {
        motionManager.stopDetection()
        earnedXP = currentReps * (xpPerRep[selectedExerciseType] ?? 1)

        // iOS アプリへデータ送信
        let workout = WorkoutData(
            exerciseName: selectedExerciseType.rawValue,
            reps: currentReps,
            points: earnedXP,
            timestamp: Date()
        )
        WatchConnectivityManager.shared.sendWorkout(workout)
        WatchConnectivityManager.shared.addRecentWorkout("\(currentReps) \(selectedExerciseType.rawValue)")
        WatchConnectivityManager.shared.todayReps += currentReps
        WatchConnectivityManager.shared.todayXP += earnedXP

        WKInterfaceDevice.current().play(.success)

        withAnimation { showCelebration = true }
    }

    private func cancelWorkout() {
        motionManager.stopDetection()
        manualRepCount = 0
        isPresented = false
    }
}

struct CalibrationView: View {
    @Binding var isPresented: Bool
    let motionManager: WatchMotionDetectionManager
    @State private var isCalibrating = false
    @State private var countDown = 3

    var body: some View {
        VStack(spacing: 12) {
            Text("キャリブレーション")
                .font(.headline)

            if !isCalibrating {
                VStack(spacing: 10) {
                    Text("腕を静止させてください")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.gray)

                    Button(action: startCalibration) {
                        Text("開始")
                            .font(.caption).fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .cornerRadius(4)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Text("静止中...")
                        .font(.caption).foregroundColor(.gray)

                    Text("\(countDown)")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.orange)
                        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                            if countDown > 1 { countDown -= 1 } else {
                                isCalibrating = false
                                isPresented = false
                            }
                        }
                }
            }

            Spacer()

            Button(action: { isPresented = false }) {
                Text("閉じる")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .padding(.vertical, 6)
                    .background(Color.gray)
                    .cornerRadius(4)
            }
        }
        .padding()
    }

    private func startCalibration() {
        isCalibrating = true
        countDown = 3
        motionManager.calibrate()
    }
}

#Preview {
    WatchQuickWorkoutView(isPresented: .constant(true))
}
