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
    @State private var stepIdx = 0
    @State private var reps = 0
    @State private var totalXP = 0
    @State private var done = false
    /// 各種目の完了結果を蓄積（セット完了時にまとめて送信）
    @State private var allResults: [WatchSetExercise] = []

    private var current: FlowStep { flowSteps[stepIdx] }
    private var isLast: Bool { stepIdx == flowSteps.count - 1 }

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

                Text(current.name)
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.black)
                    .foregroundColor(duoGreen)

                VStack(spacing: 0) {
                    Text("\(reps)")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("/ \(current.target)")
                        .font(.caption2)
                        .foregroundColor(Color.white.opacity(0.5))
                }

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
        let xp = reps * current.xp
        totalXP += xp

        // 通知キャンセル用に種目ごとに即送信
        let workout = WorkoutData(
            exerciseId: current.exerciseId,
            exerciseName: current.name,
            reps: reps,
            points: xp,
            timestamp: Date()
        )
        WatchConnectivityManager.shared.sendWorkout(workout)
        WatchConnectivityManager.shared.addRecentWorkout("\(current.emoji) \(current.name) \(reps)rep")
        WatchConnectivityManager.shared.todayReps += reps
        WatchConnectivityManager.shared.todayXP += xp

        // セット完了用に結果を蓄積
        allResults.append(WatchSetExercise(
            exerciseId: current.exerciseId,
            exerciseName: current.name,
            reps: reps,
            points: xp
        ))

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
        }
    }
}
