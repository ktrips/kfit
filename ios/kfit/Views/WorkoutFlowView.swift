import SwiftUI

private let flowSteps: [(emoji: String, name: String, target: Int, id: String, xp: Int)] = [
    ("🏋️", "スクワット", 20, "squat", 2),
    ("💪", "腕立て伏せ", 15, "pushup", 2),
    ("🔥", "腹筋", 15, "situp", 1),
    ("🧘", "プランク", 45, "plank", 1),
    ("🦵", "ランジ", 20, "lunge", 2),
]

struct WorkoutFlowView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var motionManager = MotionDetectionManager()
    @Environment(\.dismiss) var dismiss

    @State private var stepIdx = 0
    @State private var reps = 0
    @State private var totalXP = 0
    @State private var done = false
    @State private var useMotion = true
    @State private var plankSeconds = 0
    @State private var plankTimer: Timer?
    @State private var results: [(name: String, emoji: String, reps: Int, xp: Int)] = []

    private var current: (emoji: String, name: String, target: Int, id: String, xp: Int) {
        flowSteps[stepIdx]
    }
    private var isLast: Bool { stepIdx == flowSteps.count - 1 }
    private var isPlank: Bool { current.id == "plank" }

    var body: some View {
        ZStack {
            Color.duoBg.ignoresSafeArea()
            if done {
                celebrationView
            } else {
                exerciseView
            }
        }
    }

    private var exerciseView: some View {
        VStack(spacing: 16) {
            progressDots

            Text(current.emoji).font(.system(size: 60))
            Text(current.name)
                .font(.title2).fontWeight(.black)
                .foregroundColor(Color.duoGreen)

            Text("\(displayReps)")
                .font(.system(size: 72, weight: .black, design: .rounded))
                .foregroundColor(Color.duoGreen)
            Text("/ \(current.target)")
                .font(.title3).foregroundColor(Color.duoSubtitle)

            if !isPlank && useMotion {
                HStack {
                    Circle().fill(Color.duoGreen).frame(width: 8, height: 8)
                    Text("モーション検出中")
                        .font(.caption).foregroundColor(Color.duoGreen)
                }
            }

            Spacer()

            if !useMotion || isPlank {
                Button { reps += 1 } label: {
                    Text("+1").font(.largeTitle).fontWeight(.black)
                        .foregroundColor(.white).frame(maxWidth: .infinity)
                        .padding(.vertical, 20).background(Color.duoGreen)
                        .cornerRadius(16)
                }
                .padding(.horizontal)
            }

            Button { advance() } label: {
                Text(isLast ? "完了" : "次へ").font(.headline).fontWeight(.bold)
                    .foregroundColor(.white).frame(maxWidth: .infinity)
                    .padding(.vertical, 16).background(Color.duoBlue)
                    .cornerRadius(16)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .onAppear {
            if !isPlank && useMotion {
                startMotion()
            }
        }
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<flowSteps.count, id: \.self) { i in
                Circle()
                    .fill(i < stepIdx ? Color.duoGreen : i == stepIdx ? Color.duoBlue : Color.gray.opacity(0.3))
                    .frame(width: i == stepIdx ? 12 : 8, height: i == stepIdx ? 12 : 8)
            }
        }
        .padding(.top, 60)
    }

    private var celebrationView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image("mascot").resizable().scaledToFill()
                .frame(width: 120, height: 120).clipShape(Circle())
            Text("完了！🎉").font(.largeTitle).fontWeight(.black)
                .foregroundColor(Color.duoGreen)
            Text("+\(totalXP) XP").font(.system(size: 48, weight: .black))
                .foregroundColor(Color.duoGold)
            Spacer()
            Button { dismiss() } label: {
                Text("ホームへ").font(.headline).fontWeight(.bold)
                    .foregroundColor(.white).frame(maxWidth: .infinity)
                    .padding(.vertical, 18).background(Color.duoGreen)
                    .cornerRadius(16)
            }
            .padding(.horizontal).padding(.bottom, 40)
        }
    }

    private var displayReps: Int {
        if isPlank { return plankSeconds }
        if useMotion { return motionManager.repCount }
        return reps
    }

    private func startMotion() {
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
    }

    private func advance() {
        let actualReps = displayReps
        let xp = actualReps * current.xp
        totalXP += xp
        results.append((current.name, current.emoji, actualReps, xp))

        Task {
            await authManager.recordExerciseDirect(
                exerciseId: current.id,
                exerciseName: current.name,
                reps: actualReps,
                points: xp
            )
        }

        motionManager.stopDetection()

        if isLast {
            done = true
        } else {
            stepIdx += 1
            reps = 0
            if !isPlank && useMotion {
                startMotion()
            }
        }
    }
}
