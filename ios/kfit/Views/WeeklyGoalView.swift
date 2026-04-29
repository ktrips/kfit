import SwiftUI

struct WeeklyGoalView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss

    @State private var goals: [WeeklyGoal] = []
    @State private var progress: [String: Int] = [:]
    @State private var isLoading = true
    @State private var isEditing = false
    @State private var draftDailyReps: [String: Int] = [:]

    private let activeDays = 5  // 週7日 − 休息2日

    var body: some View {
        ZStack {
            Color.duoBg.ignoresSafeArea()
            Group {
                if isLoading {
                    VStack(spacing: 16) {
                        Image("mascot")
                            .resizable().scaledToFit().frame(width: 72, height: 72)
                            .clipShape(Circle())
                        Text("読み込み中...")
                            .foregroundColor(Color.duoDark).font(.subheadline).fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            weekLabel
                            if isEditing { editSection } else { viewSection }
                            Spacer(minLength: 40)
                        }
                        .padding(.top, 8)
                    }
                }
            }
            .navigationTitle("🎯 週間目標")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "保存" : "編集") {
                        if isEditing { Task { await save() } }
                        else         { startEditing() }
                    }
                    .fontWeight(.bold)
                    .foregroundColor(Color.duoGreen)
                }
                if isEditing {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("キャンセル") {
                            isEditing = false
                        }
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
        .task { await loadData() }
    }

    // MARK: - 週ラベル
    private var weekLabel: some View {
        Text(currentWeekLabel())
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 20)
    }

    // MARK: - 閲覧モード
    private var viewSection: some View {
        VStack(spacing: 12) {
            if goals.isEmpty {
                VStack(spacing: 16) {
                    Image("mascot")
                        .resizable().scaledToFit().frame(width: 80, height: 80)
                        .clipShape(Circle()).opacity(0.8)
                    Text("週間目標が設定されていません")
                        .foregroundColor(Color.duoDark).font(.subheadline).fontWeight(.semibold)
                    Button(action: startEditing) {
                        Text("目標を設定する")
                            .font(.headline).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color.duoGreen).cornerRadius(14)
                            .shadow(color: Color.duoGreen.opacity(0.4), radius: 4, y: 3)
                    }
                }
                .padding(24)
                .background(Color.white).cornerRadius(16)
                .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
                .padding(.horizontal, 20)
            } else {
                // 全体進捗
                overallProgress
                // 種目別
                ForEach(goals) { goal in
                    goalProgressCard(goal)
                }
            }
        }
    }

    private var overallProgress: some View {
        let totalDone     = goals.reduce(0) { $0 + (progress[$1.exerciseId] ?? 0) }
        let totalExpected = goals.reduce(0) { $0 + $1.dailyReps * activeDaysElapsed() }
        let pct = totalExpected > 0 ? min(Double(totalDone) / Double(totalExpected), 1.0) : 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("週間達成率")
                    .font(.headline).fontWeight(.bold).foregroundColor(Color.duoDark)
                Spacer()
                Text("\(Int(pct * 100))%")
                    .font(.title3).fontWeight(.black)
                    .foregroundColor(pct >= 1 ? Color.duoGreen : Color.duoBlue)
            }
            progressBar(value: pct, color: pct >= 1 ? Color.duoGreen : Color.duoBlue)
            Text("\(totalDone) / \(totalExpected) rep（\(activeDaysElapsed())日経過）")
                .font(.caption).foregroundColor(Color.duoSubtitle)
        }
        .padding(20)
        .background(Color.white).cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
        .padding(.horizontal, 20)
    }

    private func goalProgressCard(_ goal: WeeklyGoal) -> some View {
        let done     = progress[goal.exerciseId] ?? 0
        let expected = goal.dailyReps * activeDaysElapsed()
        let pct = expected > 0 ? min(Double(done) / Double(expected), 1.0) : 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(goal.exerciseName)
                    .font(.subheadline).fontWeight(.bold).foregroundColor(Color.duoDark)
                Spacer()
                Text("\(done) / \(expected)")
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(pct >= 1 ? Color.duoGreen : Color.duoSubtitle)
            }
            progressBar(value: pct, color: pct >= 1 ? Color.duoGreen : Color.duoBlue)
            Text("1日 \(goal.dailyReps) rep・週合計目標 \(goal.targetReps) rep")
                .font(.caption2).foregroundColor(Color.duoSubtitle)
        }
        .padding(16)
        .background(Color.white).cornerRadius(14)
        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
        .padding(.horizontal, 20)
    }

    // MARK: - 編集モード
    private var editSection: some View {
        VStack(spacing: 12) {
            Text("各種目の1日目標 rep 数を設定してください")
                .font(.caption).fontWeight(.medium).foregroundColor(Color.duoSubtitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

            ForEach(authManager.exercises) { exercise in
                editRow(exercise)
            }
        }
    }

    private func editRow(_ exercise: Exercise) -> some View {
        let key = exercise.id ?? exercise.name
        let current = draftDailyReps[key] ?? 0

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.subheadline).fontWeight(.bold).foregroundColor(Color.duoDark)
                Text("\(current * activeDays) rep / 週")
                    .font(.caption2).foregroundColor(Color.duoSubtitle)
            }
            Spacer()

            HStack(spacing: 8) {
                Button(action: {
                    draftDailyReps[key] = max(0, current - 5)
                }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3).foregroundColor(Color.duoRed)
                }

                Text("\(current)")
                    .font(.title3).fontWeight(.black)
                    .foregroundColor(Color.duoGreen)
                    .frame(minWidth: 40, alignment: .center)

                Button(action: {
                    draftDailyReps[key] = current + 5
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3).foregroundColor(Color.duoGreen)
                }
            }
        }
        .padding(16)
        .background(Color.white).cornerRadius(14)
        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
        .padding(.horizontal, 20)
    }

    // MARK: - ヘルパー
    private func progressBar(value: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().foregroundColor(Color(.systemGray5)).frame(height: 10)
                Capsule().foregroundColor(color)
                    .frame(width: geo.size.width * CGFloat(value), height: 10)
            }
        }
        .frame(height: 10)
    }

    private func activeDaysElapsed() -> Int {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceMonday = weekday == 1 ? 6 : weekday - 2
        return min(max(daysSinceMonday + 1, 1), activeDays)
    }

    private func currentWeekLabel() -> String {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysToMonday = weekday == 1 ? -6 : 2 - weekday
        let monday = calendar.date(byAdding: .day, value: daysToMonday, to: today) ?? today
        let sunday = calendar.date(byAdding: .day, value: 6, to: monday) ?? today
        let fmt = DateFormatter(); fmt.dateFormat = "M/d"
        return "\(fmt.string(from: monday)) 〜 \(fmt.string(from: sunday))"
    }

    // MARK: - データ操作
    private func loadData() async {
        isLoading = true
        async let g = authManager.getWeeklyGoals()
        async let p = authManager.getWeeklyProgress()
        goals    = await g
        progress = await p
        isLoading = false
    }

    private func startEditing() {
        draftDailyReps = [:]
        for exercise in authManager.exercises {
            let key = exercise.id ?? exercise.name
            let existing = goals.first { $0.exerciseId == key }
            draftDailyReps[key] = existing?.dailyReps ?? 0
        }
        isEditing = true
    }

    private func save() async {
        let newGoals: [WeeklyGoal] = authManager.exercises.compactMap { exercise in
            let key = exercise.id ?? exercise.name
            let daily = draftDailyReps[key] ?? 0
            guard daily > 0 else { return nil }
            return WeeklyGoal(
                exerciseId: key,
                exerciseName: exercise.name,
                dailyReps: daily,
                targetReps: daily * activeDays
            )
        }
        await authManager.setWeeklyGoals(newGoals)
        goals = newGoals
        progress = await authManager.getWeeklyProgress()
        isEditing = false
    }
}

#Preview {
    WeeklyGoalView()
        .environmentObject(AuthenticationManager.shared)
}
