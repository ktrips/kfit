import SwiftUI
import WatchKit

private let duoGreen  = Color(red: 0.345, green: 0.800, blue: 0.008)
private let duoYellow = Color(red: 1.0,   green: 0.851, blue: 0.0)

private struct FlowStep {
    let emoji: String
    let name: String
    let target: Int
    let exerciseId: String
    let xp: Int
}

private let flowSteps: [FlowStep] = [
    FlowStep(emoji: "🏋️", name: "スクワット",   target: 20, exerciseId: "squat",  xp: 2),
    FlowStep(emoji: "💪", name: "腕立て伏せ",   target: 15, exerciseId: "pushup", xp: 2),
    FlowStep(emoji: "🔥", name: "レッグレイズ", target: 15, exerciseId: "situp",  xp: 1),
    FlowStep(emoji: "🧘", name: "プランク",     target: 45, exerciseId: "plank",  xp: 1),
    FlowStep(emoji: "🦵", name: "ランジ",       target: 20, exerciseId: "lunge",  xp: 2),
]

struct WatchWorkoutFlowView: View {
    @Binding var isPresented: Bool
    @StateObject private var motionManager = WatchMotionDetectionManager()
    @State private var stepIdx = 0
    @State private var reps = 0
    @State private var totalXP = 0
    @State private var done = false
    @State private var useMotionSensor = true  // デフォルトでモーションセンサーON
    /// 各種目の完了結果を蓄積（セット完了時にまとめて送信）
    @State private var allResults: [WatchSetExercise] = []
    @State private var showGoalReached = false
    @State private var plankSeconds = 0
    @State private var plankTimer: Timer?

    private var current: FlowStep { flowSteps[stepIdx] }
    private var isLast: Bool { stepIdx == flowSteps.count - 1 }
    private var isPlank: Bool { current.exerciseId == "plank" }

    var body: some View {
        if done {
            finishView
        } else {
            ZStack {
                exerciseView
                if showGoalReached {
                    goalReachedOverlay
                }
            }
            .onChange(of: motionManager.repCount) { count in
                if useMotionSensor && !isPlank { checkGoalReached(count) }
            }
            .onChange(of: reps) { count in
                if !useMotionSensor && !isPlank { checkGoalReached(count) }
            }
            .onChange(of: plankSeconds) { secs in
                if isPlank && secs >= current.target && !showGoalReached { checkGoalReached(secs) }
            }
        }
    }

    // MARK: - 目標達成オーバーレイ
    private var goalReachedOverlay: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 8) {
                Text("🎯").font(.system(size: 36))
                Text("Good job!")
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.black)
                    .foregroundColor(duoGreen)
                Text("目標達成！続けてOK")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(16)
            .background(Color.black.opacity(0.8))
            .cornerRadius(16)
        }
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: showGoalReached)
    }

    private func checkGoalReached(_ count: Int) {
        if count == current.target && !showGoalReached {
            showGoalReached = true
            WKInterfaceDevice.current().play(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                showGoalReached = false
            }
        }
    }

    // MARK: - 種目画面
    private var exerciseView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    ForEach(0..<flowSteps.count, id: \.self) { i in
                        Circle()
                            .fill(i < stepIdx ? duoGreen :
                                  i == stepIdx ? Color.white :
                                  Color.white.opacity(0.3))
                            .frame(width: i == stepIdx ? 9 : 6,
                                   height: i == stepIdx ? 9 : 6)
                    }
                }
                .padding(.top, 4)

                Text(current.emoji).font(.system(size: 34))

                HStack(spacing: 4) {
                    Text(current.name)
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.black)
                        .foregroundColor(duoGreen)

                    // モーションセンサー切り替え（プランク以外）
                    if !isPlank {
                        Button {
                            useMotionSensor.toggle()
                            if useMotionSensor {
                                startMotionDetection()
                            } else {
                                motionManager.stopDetection()
                            }
                        } label: {
                            Image(systemName: useMotionSensor ? "sensor.fill" : "hand.tap.fill")
                                .font(.system(size: 10))
                                .foregroundColor(useMotionSensor ? duoGreen : .gray)
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(spacing: 0) {
                    Text("\(displayReps)")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("/ \(current.target)\(isPlank ? "秒" : "回")")
                        .font(.caption2)
                        .foregroundColor(Color.white.opacity(0.5))
                }

                // モーション検出中の表示
                if useMotionSensor && motionManager.isDetecting && !isPlank {
                    VStack(spacing: 2) {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(duoGreen)
                                .frame(width: 5, height: 5)
                            Text("検出中")
                                .font(.system(size: 9))
                                .foregroundColor(duoGreen)
                        }
                        Text("加速度: \(String(format: "%.2f", motionManager.currentAcceleration))G")
                            .font(.system(size: 8))
                            .foregroundColor(.gray)
                    }
                }

                // プランク: タイマー開始/停止ボタン
                if isPlank {
                    Button {
                        if plankTimer == nil {
                            startPlankTimer()
                            WKInterfaceDevice.current().play(.click)
                        } else {
                            stopPlankTimer()
                            WKInterfaceDevice.current().play(.click)
                        }
                    } label: {
                        Text(plankTimer == nil ? "▶ 開始" : "⏸ 停止")
                            .font(.system(.headline, design: .rounded))
                            .fontWeight(.black)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(plankTimer == nil ? duoGreen : Color.orange)
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                } else if !useMotionSensor {
                    Button {
                        reps += 1
                        WKInterfaceDevice.current().play(.click)
                    } label: {
                        Text("＋1")
                            .font(.system(.headline, design: .rounded))
                            .fontWeight(.black)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(duoGreen)
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                } else if useMotionSensor && !isPlank {
                    // モーション検出モード時：補助的な+1ボタン（薄く表示）
                    Button {
                        reps += 1
                        WKInterfaceDevice.current().play(.click)
                    } label: {
                        Text("手動+1")
                            .font(.system(size: 9))
                            .fontWeight(.bold)
                            .foregroundColor(duoGreen)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(duoGreen.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }

                Button { advance() } label: {
                    Text(isLast ? "完了 ✓" : "次へ →")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(duoGreen)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(duoGreen.opacity(0.15))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
        }
        .onAppear {
            if useMotionSensor && !isPlank {
                startMotionDetection()
            }
        }
        .onDisappear {
            motionManager.stopDetection()
            stopPlankTimer()
        }
    }

    // 表示用カウント（プランクは秒数、モーションONは検出値、それ以外は手動）
    private var displayReps: Int {
        if isPlank { return plankSeconds }
        if useMotionSensor { return motionManager.repCount }
        return reps
    }

    // モーション検出開始
    private func startMotionDetection() {
        guard !isPlank else {
            print("⚠️ WatchFlow: Skipping motion detection for plank")
            return
        }

        let exerciseType: ExerciseType
        switch current.exerciseId {
        case "pushup": exerciseType = .pushup
        case "squat": exerciseType = .squat
        case "situp": exerciseType = .situp
        case "lunge": exerciseType = .lunge
        case "burpee": exerciseType = .burpee
        default:
            print("⚠️ WatchFlow: Unknown exercise type: \(current.exerciseId)")
            return
        }

        print("🟢 WatchFlow: Starting motion detection for \(current.name)")
        motionManager.startDetection(for: exerciseType)
    }

    // MARK: - プランクタイマー
    private func startPlankTimer() {
        plankTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in plankSeconds += 1 }
        }
    }

    private func stopPlankTimer() {
        plankTimer?.invalidate()
        plankTimer = nil
    }

    // MARK: - 完了画面
    private var finishView: some View {
        VStack(spacing: 8) {
            Image("mascot")
                .resizable().scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(Circle())
                .overlay(Circle().stroke(duoGreen, lineWidth: 2))

            Text("完了！🎉")
                .font(.system(.headline, design: .rounded))
                .fontWeight(.black)
                .foregroundColor(duoGreen)

            Text("+\(totalXP) XP")
                .font(.title2).fontWeight(.black)
                .foregroundColor(duoYellow)

            Button { isPresented = false } label: {
                Text("ホームへ")
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(duoGreen)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
    }

    // MARK: - 次の種目へ
    private func advance() {
        stopPlankTimer()
        let actualReps: Int
        if isPlank {
            actualReps = plankSeconds
        } else if useMotionSensor {
            actualReps = motionManager.repCount
        } else {
            actualReps = reps
        }
        let xp = actualReps * current.xp
        totalXP += xp

        // 通知キャンセル用に種目ごとに即送信
        let workout = WorkoutData(
            exerciseId: current.exerciseId,
            exerciseName: current.name,
            reps: actualReps,
            points: xp,
            timestamp: Date()
        )
        WatchConnectivityManager.shared.sendWorkout(workout)
        WatchConnectivityManager.shared.addRecentWorkout("\(current.emoji) \(current.name) \(actualReps)rep")
        WatchConnectivityManager.shared.todayReps += actualReps
        WatchConnectivityManager.shared.todayXP += xp

        // セット完了用に結果を蓄積
        allResults.append(WatchSetExercise(
            exerciseId: current.exerciseId,
            exerciseName: current.name,
            reps: actualReps,
            points: xp
        ))

        // モーション検出を停止
        motionManager.stopDetection()

        WKInterfaceDevice.current().play(.success)

        if isLast {
            // 全種目完了 → まとめてセット記録を送信
            let setData = WatchSetData(
                exercises: allResults,
                totalXP: totalXP,
                totalReps: allResults.reduce(0) { $0 + $1.reps },
                timestamp: Date()
            )
            WatchConnectivityManager.shared.sendCompletedSet(setData)
            WatchConnectivityManager.shared.todaySets += 1
            done = true
        } else {
            stepIdx += 1
            reps = 0
            plankSeconds = 0

            // 次の種目でモーション検出を開始
            if useMotionSensor && !isPlank {
                startMotionDetection()
            }
        }
    }
}
