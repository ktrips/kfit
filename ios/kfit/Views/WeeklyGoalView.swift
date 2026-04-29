import SwiftUI

struct WeeklyGoalView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var goals: [WeeklyGoal] = []
    @State private var progress: [String: Int] = [:]
    @State private var drafts: [String: Int] = [:]
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var isLoading = true
    @State private var saved = false

    private let goalColors: [(bg: Color, fg: Color)] = [
        (Color.duoGreen.opacity(0.12), Color.duoGreen),
        (Color.duoBlue.opacity(0.12), Color.duoBlue),
        (Color.duoOrange.opacity(0.12), Color.duoOrange),
        (Color.duoPurple.opacity(0.12), Color.duoPurple),
        (Color.duoRed.opacity(0.12), Color.duoRed),
        (Color.duoYellow.opacity(0.12), Color.duoYellow),
    ]

    private func weekLabel() -> String {
        let cal = Calendar.current
        let today = Date()
        let wd = cal.component(.weekday, from: today)
        let diff = wd == 1 ? -6 : 2 - wd
        let mon = cal.date(byAdding: .day, value: diff, to: today) ?? today
        let sun = cal.date(byAdding: .day, value: 6, to: mon) ?? today
        let fmt = DateFormatter(); fmt.dateFormat = "M/d"
        return "\(fmt.string(from: mon)) 〜 \(fmt.string(from: sun))"
    }

    private func activeDays() -> Int {
        let wd = Calendar.current.component(.weekday, from: Date())
        return min(wd == 1 ? 6 : wd - 1, 5)
    }

    var body: some View {
        ZStack {
            Color.duoBg.ignoresSafeArea()
            if isLoading {
                VStack(spacing: 16) {
                    Image("mascot").resizable().scaledToFill()
                        .frame(width: 80, height: 80).clipShape(Circle())
                    Text("読み込み中…").font(.subheadline).foregroundColor(.secondary)
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        // ヒント
                        HStack(spacing: 10) {
                            Text("💡").font(.headline)
                            Text("1日の目標 × 5日（週2日休息）= 週間目標")
                                .font(.caption).fontWeight(.bold).foregroundColor(Color.duoBlue)
                        }
                        .padding(12)
                        .background(Color.duoBlue.opacity(0.1)).cornerRadius(14)

                        if !goals.isEmpty && !isEditing {
                            overallProgress
                            ForEach(Array(goals.enumerated()), id: \.element.id) { i, goal in
                                goalCard(goal, colorIdx: i)
                            }
                            Button { isEditing = true } label: {
                                Text("✏️ 目標を編集").fontWeight(.black)
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .foregroundColor(Color.duoGreen)
                                    .background(Color.duoGreen.opacity(0.1))
                                    .cornerRadius(14)
                            }
                        } else if isEditing || goals.isEmpty {
                            editCard
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("週間目標")
        .task { await loadData() }
    }

    private var overallProgress: some View {
        let active = activeDays()
        let totalExp  = goals.reduce(0) { $0 + $1.dailyReps * active }
        let totalDone = goals.reduce(0) { $0 + (progress[$1.exerciseId] ?? 0) }
        let pct = totalExp > 0 ? min(Double(totalDone) / Double(totalExp), 1.0) : 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(pct >= 1 ? "🎉 今週の目標達成！" : "🎯 今週の総合進捗")
                    .font(.headline).fontWeight(.black)
                Spacer()
                Text("\(Int(pct * 100))%")
                    .font(.title3).fontWeight(.black)
                    .foregroundColor(pct >= 1 ? Color.duoGreen : Color.duoYellow)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5)).frame(height: 12)
                    Capsule()
                        .fill(LinearGradient(colors: [Color.duoGreen, Color.duoBlue],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(12, geo.size.width * CGFloat(pct)), height: 12)
                }
            }.frame(height: 12)
            Text("\(totalDone) / \(totalExp) rep（今日まで目標）")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(16).background(Color.white).cornerRadius(18)
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
    }

    private func goalCard(_ goal: WeeklyGoal, colorIdx: Int) -> some View {
        let col = goalColors[colorIdx % goalColors.count]
        let active = activeDays()
        let done = progress[goal.exerciseId] ?? 0
        let expected = goal.dailyReps * active
        let pct = expected > 0 ? min(Double(done) / Double(expected), 1.0) : 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(emojiFor(goal.exerciseId)).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.exerciseName).font(.subheadline).fontWeight(.black)
                    Text("\(done) / \(expected) rep（今日まで）")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Text("\(Int(pct * 100))%")
                    .font(.title3).fontWeight(.black).foregroundColor(col.fg)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5)).frame(height: 10)
                    Capsule().fill(col.fg)
                        .frame(width: max(10, geo.size.width * CGFloat(pct)), height: 10)
                }
            }.frame(height: 10)
            HStack {
                Text("1日 \(goal.dailyReps) rep × \(active)日経過")
                    .font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text("週間: \(done)/\(goal.targetReps)")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(16).background(Color.white).cornerRadius(18)
        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
    }

    private var editCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("1日の目標rep数を設定").font(.headline).fontWeight(.black)

            ForEach(Array(authManager.exercises.enumerated()), id: \.element.id) { i, ex in
                let col = goalColors[i % goalColors.count]
                let daily = drafts[ex.id ?? ""] ?? 0
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Text(emojiFor(ex.id ?? "")).font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.name).font(.subheadline).fontWeight(.black)
                            Text("\(ex.basePoints) XP / rep")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    HStack(spacing: 12) {
                        Button {
                            let key = ex.id ?? ""
                            drafts[key] = max(0, (drafts[key] ?? 0) - 5)
                        } label: {
                            Text("−").font(.title2).fontWeight(.black)
                                .frame(width: 40, height: 40)
                                .foregroundColor(col.fg)
                                .background(col.bg).cornerRadius(12)
                        }
                        VStack(spacing: 2) {
                            Text("\(daily)").font(.title2).fontWeight(.black).foregroundColor(col.fg)
                            Text("rep/日").font(.caption2).foregroundColor(.secondary)
                        }
                        .frame(minWidth: 60)
                        Button {
                            let key = ex.id ?? ""
                            drafts[key] = (drafts[key] ?? 0) + 5
                        } label: {
                            Text("＋").font(.title2).fontWeight(.black)
                                .frame(width: 40, height: 40)
                                .foregroundColor(.white)
                                .background(col.fg).cornerRadius(12)
                        }
                        Spacer()
                        if daily > 0 {
                            Text("週間: \(daily * 5) rep")
                                .font(.caption).fontWeight(.bold).foregroundColor(col.fg)
                        }
                    }
                }
                .padding(14).background(col.bg).cornerRadius(16)
            }

            HStack(spacing: 10) {
                if !goals.isEmpty {
                    Button { isEditing = false } label: {
                        Text("キャンセル").fontWeight(.black)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .foregroundColor(.secondary)
                            .background(Color(.systemGray5)).cornerRadius(14)
                    }
                }
                Button { Task { await saveGoals() } } label: {
                    Text(isSaving ? "保存中…" : saved ? "✓ 保存済み！" : "目標を保存").fontWeight(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .foregroundColor(.white)
                        .background(drafts.values.allSatisfy { $0 == 0 } ? Color(.systemGray3) : Color.duoGreen)
                        .cornerRadius(14)
                }
                .disabled(isSaving || drafts.values.allSatisfy { $0 == 0 })
            }
        }
        .padding(16).background(Color.white).cornerRadius(18)
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
    }

    private func loadData() async {
        async let g = authManager.getWeeklyGoals()
        async let p = authManager.getWeeklyProgress()
        let (fetchedGoals, fetchedProgress) = await (g, p)
        goals = fetchedGoals
        progress = fetchedProgress
        var d: [String: Int] = [:]
        for ex in authManager.exercises {
            let existing = fetchedGoals.first { $0.exerciseId == ex.id }
            d[ex.id ?? ""] = existing?.dailyReps ?? 0
        }
        drafts = d
        if goals.isEmpty { isEditing = true }
        isLoading = false
    }

    private func saveGoals() async {
        isSaving = true
        let newGoals: [WeeklyGoal] = authManager.exercises.compactMap { ex in
            let daily = drafts[ex.id ?? ""] ?? 0
            guard daily > 0, let id = ex.id else { return nil }
            return WeeklyGoal(exerciseId: id, exerciseName: ex.name, dailyReps: daily, targetReps: daily * 5)
        }
        await authManager.setWeeklyGoals(newGoals)
        goals = newGoals
        isSaving = false
        isEditing = false
        saved = true
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        saved = false
    }

    private func emojiFor(_ id: String) -> String {
        let map = ["pushup": "💪", "push-up": "💪", "squat": "🏋️",
                   "situp": "🔥", "sit-up": "🔥", "lunge": "🦵",
                   "burpee": "⚡", "plank": "🧘"]
        return map[id.lowercased()] ?? "🏃"
    }
}
