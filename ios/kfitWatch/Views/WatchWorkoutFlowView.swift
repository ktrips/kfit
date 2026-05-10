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
                if !useMotionSensor || isPlank { checkGoalReached(count) }
            }
            .onChange(of: stepIdx) { _ in
                // プランクの画面に移ったら自動的にタイマー開始
                if isPlank {
                    print("🔵 WatchFlow: Plank screen detected - auto-starting timer")
                    startMotionDetection()
                }
            }
        }
    }

    // MARK: - 目標達成オーバーレイ
    private var goalReachedOverlay: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 10) {
                Text("🎉")
                    .font(.system(size: 48))
                    .scaleEffect(showGoalReached ? 1.2 : 0.5)
                    .animation(.spring(response: 0.5, dampingFraction: 0.5).delay(0.1), value: showGoalReached)

                Text("Good Job!")
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.black)
                    .foregroundColor(duoGreen)
                    .scaleEffect(showGoalReached ? 1.0 : 0.8)
                    .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.2), value: showGoalReached)

                Text("目標達成！")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.9))
                    .scaleEffect(showGoalReached ? 1.0 : 0.8)
                    .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.3), value: showGoalReached)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(duoGreen, lineWidth: 2)
                    )
            )
            .scaleEffect(showGoalReached ? 1.0 : 0.5)
        }
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: showGoalReached)
    }

    private func checkGoalReached(_ count: Int) {
        if count == current.target && !showGoalReached {
            showGoalReached = true

            // 強力なハプティックフィードバック（3回連続）
            WKInterfaceDevice.current().play(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                WKInterfaceDevice.current().play(.success)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                WKInterfaceDevice.current().play(.success)
            }

            // オーバーレイを3秒間表示
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                showGoalReached = false
            }
        }
    }

    // MARK: - 種目画面
    private var exerciseView: some View {
        VStack(spacing: 3) {
            // プログレスインジケーター（より小さく）
            HStack(spacing: 4) {
                ForEach(0..<flowSteps.count, id: \.self) { i in
                    Circle()
                        .fill(i < stepIdx ? duoGreen :
                              i == stepIdx ? Color.white :
                              Color.white.opacity(0.3))
                        .frame(width: i == stepIdx ? 7 : 5,
                               height: i == stepIdx ? 7 : 5)
                }
            }
            .padding(.top, 2)

            Text(current.emoji).font(.system(size: 28))

            HStack(spacing: 3) {
                Text(current.name)
                    .font(.system(size: 11))
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
                            .font(.system(size: 8))
                            .foregroundColor(useMotionSensor ? duoGreen : .gray)
                    }
                    .buttonStyle(.plain)
                }
            }

            // プランクの場合：タイマー表示
            if isPlank {
                VStack(spacing: 1) {
                    Text("\(motionManager.plankElapsedSeconds)")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("秒")
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.7))

                    if motionManager.plankCompleted {
                        Text("🎉 Good Job!")
                            .font(.system(size: 12))
                            .fontWeight(.black)
                            .foregroundColor(duoGreen)
                            .padding(.top, 2)
                    } else {
                        Text("目標: 45秒")
                            .font(.system(size: 9))
                            .foregroundColor(Color.white.opacity(0.5))
                            .padding(.top, 1)
                    }
                }
            } else {
                // 通常の種目：回数表示
                VStack(spacing: 0) {
                    Text("\(displayReps)")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("/ \(current.target)")
                        .font(.system(size: 11))
                        .foregroundColor(Color.white.opacity(0.5))
                }
            }

            // モーション検出中の表示（より小さく）
            if useMotionSensor && motionManager.isDetecting && !isPlank {
                HStack(spacing: 2) {
                    Circle()
                        .fill(duoGreen)
                        .frame(width: 4, height: 4)
                    Text("検出中")
                        .font(.system(size: 8))
                        .foregroundColor(duoGreen)
                }
            }

            Spacer()

            // ボタンエリア（コンパクト）
            VStack(spacing: 4) {
                // プランクの場合：ボタンなし（タイマーのみ）
                // 手動カウントボタン（プランク時以外の手動モード時）
                if !isPlank {
                    if !useMotionSensor {
                        Button {
                            reps += 1
                            WKInterfaceDevice.current().play(.click)
                        } label: {
                            Text("＋1")
                                .font(.system(size: 14))
                                .fontWeight(.black)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(duoGreen)
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    } else {
                        // モーション検出モード時：補助的な+1ボタン（薄く表示）
                        Button {
                            reps += 1
                            WKInterfaceDevice.current().play(.click)
                        } label: {
                            Text("手動+1")
                                .font(.system(size: 8))
                                .fontWeight(.bold)
                                .foregroundColor(duoGreen)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                                .background(duoGreen.opacity(0.1))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button { advance() } label: {
                    Text(isLast ? "完了 ✓" : "次へ →")
                        .font(.system(size: 11)).fontWeight(.bold)
                        .foregroundColor(duoGreen)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(duoGreen.opacity(0.15))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
        .onAppear {
            // プランクの場合は自動的にタイマー開始
            if isPlank {
                print("🔵 WatchFlow: Plank onAppear - auto-starting timer")
                startMotionDetection()
            } else if useMotionSensor {
                // 通常の種目でモーションセンサー有効時
                startMotionDetection()
            }
        }
        .onDisappear {
            motionManager.stopDetection()
        }
    }

    // 表示用のreps（モーションセンサー使用時はmotionManagerから取得）
    private var displayReps: Int {
        if useMotionSensor && !isPlank {
            return motionManager.repCount
        }
        return reps
    }

    // モーション検出開始
    private func startMotionDetection() {
        let exerciseType: ExerciseType
        switch current.exerciseId {
        case "pushup": exerciseType = .pushup
        case "squat": exerciseType = .squat
        case "situp": exerciseType = .situp
        case "lunge": exerciseType = .lunge
        case "burpee": exerciseType = .burpee
        case "plank": exerciseType = .plank  // プランクを追加
        default:
            print("⚠️ WatchFlow: Unknown exercise type: \(current.exerciseId)")
            return
        }

        print("🟢 WatchFlow: Starting motion detection for \(current.name)")
        motionManager.startDetection(for: exerciseType)
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
        // プランクの場合：秒数を回数として記録（1秒=1rep扱い）
        // モーションセンサー使用時はmotionManagerのrepCountを使用
        let actualReps: Int
        if isPlank {
            actualReps = motionManager.plankElapsedSeconds  // プランクは秒数
        } else {
            actualReps = useMotionSensor ? motionManager.repCount : reps
        }

        let xp = isPlank ? (motionManager.plankCompleted ? 5 : 0) : (actualReps * current.xp)
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
            done = true
        } else {
            stepIdx += 1
            reps = 0

            // 次の種目でモーション検出を開始
            if useMotionSensor && !isPlank {
                startMotionDetection()
            }
        }
    }
}
