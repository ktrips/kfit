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

    private var current: FlowStep { flowSteps[stepIdx] }
    private var isLast: Bool { stepIdx == flowSteps.count - 1 }
    private var isPlank: Bool { current.exerciseId == "plank" }

    var body: some View {
        if done {
            finishView
        } else {
            exerciseView
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
                    Text("/ \(current.target)")
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

                // 手動カウントボタン（プランク時または手動モード時）
                // モーションセンサーモード時も+1ボタンを表示（テスト・補助用）
                if isPlank || !useMotionSensor {
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
        // モーションセンサー使用時はmotionManagerのrepCountを使用
        let actualReps = useMotionSensor && !isPlank ? motionManager.repCount : reps
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
