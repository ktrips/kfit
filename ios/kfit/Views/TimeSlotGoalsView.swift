import SwiftUI

struct TimeSlotGoalsView: View {
    @StateObject private var timeSlotManager = TimeSlotManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showAddCustomGoal = false
    @State private var newGoalName = ""
    @State private var newGoalEmoji = "⭐"

    var body: some View {
        ZStack {
            Color.duoBg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    headerSection

                    if timeSlotManager.isLoading {
                        ProgressView()
                            .tint(Color.duoGreen)
                            .scaleEffect(1.4)
                            .padding(.vertical, 40)
                    } else {
                        // 1日全体の目標セクション
                        globalGoalsSection

                        ForEach(TimeSlot.allCases.filter { $0 != .midnight }, id: \.self) { timeSlot in
                            if let goal = timeSlotManager.settings.goalFor(timeSlot),
                               let progress = timeSlotManager.progress.progressFor(timeSlot) {
                                timeSlotCard(timeSlot: timeSlot, goal: goal, progress: progress)
                            }
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("時間帯別の目標")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("完了") {
                    dismiss()
                }
                .foregroundColor(Color.duoGreen)
                .fontWeight(.bold)
            }
        }
        .task {
            await timeSlotManager.loadTodaySettings()
            await timeSlotManager.loadTodayProgress()
        }
    }

    // MARK: - Global Goals Section

    private var globalGoalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ヘッダー
            HStack {
                Text("🌍")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("1日全体の目標")
                        .font(.headline).fontWeight(.black)
                        .foregroundColor(Color.duoDark)
                    Text("時間帯に関係なく1日の合計で管理")
                        .font(.caption)
                        .foregroundColor(Color.duoSubtitle)
                }
                Spacer()
            }

            // アクティビティリング目標
            Toggle(isOn: Binding(
                get: { timeSlotManager.settings.globalGoals.activityEnabled },
                set: { newValue in
                    timeSlotManager.settings.globalGoals.activityEnabled = newValue
                    Task { await timeSlotManager.saveTodaySettings() }
                }
            )) {
                HStack(spacing: 8) {
                    Text("🏃")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("アクティビティリング")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(Color.duoDark)
                        Text("Move・Exercise・Standのリングをすべて閉じる")
                            .font(.caption2)
                            .foregroundColor(Color.duoSubtitle)
                    }
                }
            }
            .tint(Color.duoGreen)

            Divider()

            // 睡眠計測目標
            Toggle(isOn: Binding(
                get: { timeSlotManager.settings.globalGoals.sleepEnabled },
                set: { newValue in
                    timeSlotManager.settings.globalGoals.sleepEnabled = newValue
                    Task { await timeSlotManager.saveTodaySettings() }
                }
            )) {
                HStack(spacing: 8) {
                    Text("😴")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("睡眠の計測")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(Color.duoDark)
                        Text("睡眠スコアを計測")
                            .font(.caption2)
                            .foregroundColor(Color.duoSubtitle)
                    }
                }
            }
            .tint(Color.duoGreen)

            if timeSlotManager.settings.globalGoals.sleepEnabled {
                HStack {
                    Text("目標時間:")
                        .font(.caption)
                        .foregroundColor(Color.duoSubtitle)
                    Stepper("\(timeSlotManager.settings.globalGoals.sleepHoursGoal)時間以上",
                           value: Binding(
                               get: { timeSlotManager.settings.globalGoals.sleepHoursGoal },
                               set: { newValue in
                                   timeSlotManager.settings.globalGoals.sleepHoursGoal = newValue
                                   Task { await timeSlotManager.saveTodaySettings() }
                               }
                           ),
                           in: 1...12,
                           step: 1)
                    .font(.subheadline).fontWeight(.bold)
                }
                .padding(.leading, 40)

                HStack {
                    Text("目標スコア:")
                        .font(.caption)
                        .foregroundColor(Color.duoSubtitle)
                    Stepper("\(timeSlotManager.settings.globalGoals.sleepScoreThreshold)点以上",
                           value: Binding(
                               get: { timeSlotManager.settings.globalGoals.sleepScoreThreshold },
                               set: { newValue in
                                   timeSlotManager.settings.globalGoals.sleepScoreThreshold = newValue
                                   Task { await timeSlotManager.saveTodaySettings() }
                               }
                           ),
                           in: 50...100,
                           step: 5)
                    .font(.subheadline).fontWeight(.bold)
                }
                .padding(.leading, 40)

                // 進捗表示（睡眠時間・スコア）
                if timeSlotManager.progress.globalProgress.sleepHours > 0 || timeSlotManager.progress.globalProgress.sleepScore > 0 {
                    let hours = timeSlotManager.progress.globalProgress.sleepHours
                    let score = timeSlotManager.progress.globalProgress.sleepScore
                    let hoursGoal = timeSlotManager.settings.globalGoals.sleepHoursGoal
                    let scoreGoal = timeSlotManager.settings.globalGoals.sleepScoreThreshold
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Text("昨夜:")
                                .font(.caption)
                                .foregroundColor(Color.duoSubtitle)
                            Text(String(format: "%.1f時間", hours))
                                .font(.subheadline).fontWeight(.bold)
                                .foregroundColor(hours >= Double(hoursGoal) ? Color.duoGreen : Color.duoDark)
                        }
                        if score > 0 {
                            HStack(spacing: 4) {
                                Text("\(score)点")
                                    .font(.subheadline).fontWeight(.bold)
                                    .foregroundColor(score >= scoreGoal ? Color.duoGreen : Color.duoDark)
                                if hours >= Double(hoursGoal) && score >= scoreGoal {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Color.duoGreen)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    .padding(.leading, 40)
                }
            }

            Divider()

            // 食事の計測（PFCバランス）目標
            Toggle(isOn: Binding(
                get: { timeSlotManager.settings.globalGoals.pfcEnabled },
                set: { newValue in
                    timeSlotManager.settings.globalGoals.pfcEnabled = newValue
                    Task { await timeSlotManager.saveTodaySettings() }
                }
            )) {
                HStack(spacing: 8) {
                    Text("🍽️")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("食事の計測")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(Color.duoDark)
                        Text("PFCバランスを計測")
                            .font(.caption2)
                            .foregroundColor(Color.duoSubtitle)
                    }
                }
            }
            .tint(Color.duoGreen)

            if timeSlotManager.settings.globalGoals.pfcEnabled {
                HStack {
                    Text("目標:")
                        .font(.caption)
                        .foregroundColor(Color.duoSubtitle)
                    Stepper("\(timeSlotManager.settings.globalGoals.pfcScoreThreshold)点以上",
                           value: Binding(
                               get: { timeSlotManager.settings.globalGoals.pfcScoreThreshold },
                               set: { newValue in
                                   timeSlotManager.settings.globalGoals.pfcScoreThreshold = newValue
                                   Task { await timeSlotManager.saveTodaySettings() }
                               }
                           ),
                           in: 50...100,
                           step: 5)
                    .font(.subheadline).fontWeight(.bold)
                }
                .padding(.leading, 40)

                // 進捗表示（PFCバランススコア）
                if timeSlotManager.progress.globalProgress.pfcScore > 0 {
                    HStack(spacing: 8) {
                        Text("今日:")
                            .font(.caption)
                            .foregroundColor(Color.duoSubtitle)
                        Text("\(timeSlotManager.progress.globalProgress.pfcScore)点")
                            .font(.subheadline).fontWeight(.bold)
                            .foregroundColor(
                                timeSlotManager.progress.globalProgress.pfcScore >= timeSlotManager.settings.globalGoals.pfcScoreThreshold
                                ? Color.duoGreen : Color.duoDark
                            )
                        if timeSlotManager.progress.globalProgress.pfcScore >= timeSlotManager.settings.globalGoals.pfcScoreThreshold {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color.duoGreen)
                                .font(.caption)
                        }
                    }
                    .padding(.leading, 40)
                }
            }

            Divider()

            // 食事カロリー目標（1日合計）
            Toggle(isOn: Binding(
                get: { timeSlotManager.settings.globalGoals.mealEnabled },
                set: { newValue in
                    timeSlotManager.settings.globalGoals.mealEnabled = newValue
                    Task { await timeSlotManager.saveTodaySettings() }
                }
            )) {
                HStack(spacing: 8) {
                    Text("🍱")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("食事カロリー目標")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(Color.duoDark)
                        Text("1日の合計摂取カロリー目標")
                            .font(.caption2)
                            .foregroundColor(Color.duoSubtitle)
                    }
                }
            }
            .tint(Color.duoOrange)

            if timeSlotManager.settings.globalGoals.mealEnabled {
                HStack {
                    Text("1日の目標:")
                        .font(.caption)
                        .foregroundColor(Color.duoSubtitle)
                    Stepper("\(timeSlotManager.settings.globalGoals.dailyMealKcal) kcal",
                           value: Binding(
                               get: { timeSlotManager.settings.globalGoals.dailyMealKcal },
                               set: { newValue in
                                   timeSlotManager.settings.globalGoals.dailyMealKcal = newValue
                                   Task { await timeSlotManager.saveTodaySettings() }
                               }
                           ),
                           in: 500...4000,
                           step: 100)
                    .font(.subheadline).fontWeight(.bold)
                }
                .padding(.leading, 40)

                let totalMealLogged = TimeSlot.allCases.reduce(0) { sum, s in
                    sum + (timeSlotManager.progress.progressFor(s)?.logProgress.mealLogged ?? 0)
                }
                let mealGoal = timeSlotManager.settings.globalGoals.dailyMealKcal
                if totalMealLogged > 0 {
                    HStack(spacing: 8) {
                        Text("今日:")
                            .font(.caption)
                            .foregroundColor(Color.duoSubtitle)
                        Text("\(totalMealLogged) / \(mealGoal) kcal")
                            .font(.subheadline).fontWeight(.bold)
                            .foregroundColor(totalMealLogged >= mealGoal ? Color.duoGreen : Color.duoDark)
                        if totalMealLogged >= mealGoal {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color.duoGreen)
                                .font(.caption)
                        }
                    }
                    .padding(.leading, 40)
                }
            }

            Divider()

            // 水分目標（1日合計）
            Toggle(isOn: Binding(
                get: { timeSlotManager.settings.globalGoals.drinkEnabled },
                set: { newValue in
                    timeSlotManager.settings.globalGoals.drinkEnabled = newValue
                    Task { await timeSlotManager.saveTodaySettings() }
                }
            )) {
                HStack(spacing: 8) {
                    Text("💧")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("水分目標")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(Color.duoDark)
                        Text("1日の合計水分摂取量目標")
                            .font(.caption2)
                            .foregroundColor(Color.duoSubtitle)
                    }
                }
            }
            .tint(Color.duoBlue)

            if timeSlotManager.settings.globalGoals.drinkEnabled {
                HStack {
                    Text("1日の目標:")
                        .font(.caption)
                        .foregroundColor(Color.duoSubtitle)
                    Stepper("\(timeSlotManager.settings.globalGoals.dailyDrinkMl) ml",
                           value: Binding(
                               get: { timeSlotManager.settings.globalGoals.dailyDrinkMl },
                               set: { newValue in
                                   timeSlotManager.settings.globalGoals.dailyDrinkMl = newValue
                                   Task { await timeSlotManager.saveTodaySettings() }
                               }
                           ),
                           in: 500...5000,
                           step: 100)
                    .font(.subheadline).fontWeight(.bold)
                }
                .padding(.leading, 40)

                let totalDrinkLogged = TimeSlot.allCases.reduce(0) { sum, s in
                    sum + (timeSlotManager.progress.progressFor(s)?.logProgress.drinkLogged ?? 0)
                }
                let drinkGoal = timeSlotManager.settings.globalGoals.dailyDrinkMl
                if totalDrinkLogged > 0 {
                    HStack(spacing: 8) {
                        Text("今日:")
                            .font(.caption)
                            .foregroundColor(Color.duoSubtitle)
                        Text("\(totalDrinkLogged) / \(drinkGoal) ml")
                            .font(.subheadline).fontWeight(.bold)
                            .foregroundColor(totalDrinkLogged >= drinkGoal ? Color.duoGreen : Color.duoDark)
                        if totalDrinkLogged >= drinkGoal {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color.duoGreen)
                                .font(.caption)
                        }
                    }
                    .padding(.leading, 40)
                }
            }

            Divider()

            // 体重計測目標
            Toggle(isOn: Binding(
                get: { timeSlotManager.settings.globalGoals.weightEnabled },
                set: { newValue in
                    timeSlotManager.settings.globalGoals.weightEnabled = newValue
                    Task { await timeSlotManager.saveTodaySettings() }
                }
            )) {
                HStack(spacing: 8) {
                    Text("⚖️")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("体重の計測")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(Color.duoDark)
                        Text("毎日1回体重を記録（Apple Health連携）")
                            .font(.caption2)
                            .foregroundColor(Color.duoSubtitle)
                    }
                }
            }
            .tint(Color.duoGreen)

            if timeSlotManager.settings.globalGoals.weightEnabled {
                HStack(spacing: 8) {
                    Text("今日:")
                        .font(.caption)
                        .foregroundColor(Color.duoSubtitle)
                    if timeSlotManager.progress.globalProgress.weightMeasured {
                        Text("計測済み ✅")
                            .font(.subheadline).fontWeight(.bold)
                            .foregroundColor(Color.duoGreen)
                    } else {
                        Text("未計測")
                            .font(.subheadline).fontWeight(.bold)
                            .foregroundColor(Color.duoDark)
                    }
                }
                .padding(.leading, 40)
            }

            Divider()

            // カスタム目標セクション
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("🎨")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("カスタム目標")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(Color.duoDark)
                        Text("自由に目標を追加できます")
                            .font(.caption2)
                            .foregroundColor(Color.duoSubtitle)
                    }
                    Spacer()
                    Button {
                        showAddCustomGoal = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(Color.duoGreen)
                    }
                }

                // 既存カスタム目標リスト
                ForEach(timeSlotManager.settings.globalGoals.customGoals) { goal in
                    let isCompleted = timeSlotManager.progress.globalProgress.completedCustomGoalIds.contains(goal.id)
                    HStack(spacing: 10) {
                        // 完了トグルボタン
                        Button {
                            Task { await timeSlotManager.toggleCustomGoal(id: goal.id) }
                        } label: {
                            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundColor(isCompleted ? Color.duoGreen : Color(uiColor: .systemGray3))
                        }
                        .buttonStyle(.plain)

                        Text(goal.emoji)
                            .font(.title3)
                        Text(goal.name)
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(isCompleted ? Color.duoGreen : Color.duoDark)
                            .strikethrough(isCompleted, color: Color.duoGreen.opacity(0.6))
                        Spacer()
                        // 削除ボタン
                        Button {
                            timeSlotManager.settings.globalGoals.customGoals.removeAll { $0.id == goal.id }
                            Task { await timeSlotManager.saveTodaySettings() }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(Color.duoRed.opacity(0.5))
                                .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.leading, 4)
                }

                // プリセット提案（目標が0件のとき）
                if timeSlotManager.settings.globalGoals.customGoals.isEmpty {
                    Text("例: 読書📚・Duolingo🦉・禁酒🚫など")
                        .font(.caption2)
                        .foregroundColor(Color.duoSubtitle)
                        .padding(.leading, 8)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .sheet(isPresented: $showAddCustomGoal) {
            addCustomGoalSheet
        }
    }

    // MARK: - カスタム目標追加シート

    private var addCustomGoalSheet: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("絵文字")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(Color.duoSubtitle)
                    TextField("絵文字を入力（例: 📚）", text: $newGoalEmoji)
                        .font(.system(size: 36))
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("目標名")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(Color.duoSubtitle)
                    TextField("例: 読書、Duolingo、禁酒…", text: $newGoalName)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                }

                // プリセット選択
                VStack(alignment: .leading, spacing: 8) {
                    Text("プリセットから選ぶ")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(Color.duoSubtitle)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(CustomDailyGoal.presets) { preset in
                            Button {
                                newGoalEmoji = preset.emoji
                                newGoalName = preset.name
                            } label: {
                                VStack(spacing: 4) {
                                    Text(preset.emoji).font(.title2)
                                    Text(preset.name).font(.caption2).fontWeight(.bold)
                                        .foregroundColor(Color.duoDark)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    newGoalName == preset.name
                                    ? Color.duoGreen.opacity(0.15)
                                    : Color(.systemGray6)
                                )
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("カスタム目標を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        newGoalName = ""
                        newGoalEmoji = "⭐"
                        showAddCustomGoal = false
                    }
                    .foregroundColor(Color.duoSubtitle)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("追加") {
                        guard !newGoalName.isEmpty else { return }
                        let newGoal = CustomDailyGoal(
                            name: newGoalName,
                            emoji: newGoalEmoji.isEmpty ? "⭐" : String(newGoalEmoji.prefix(2))
                        )
                        timeSlotManager.settings.globalGoals.customGoals.append(newGoal)
                        Task { await timeSlotManager.saveTodaySettings() }
                        newGoalName = ""
                        newGoalEmoji = "⭐"
                        showAddCustomGoal = false
                    }
                    .foregroundColor(Color.duoGreen)
                    .fontWeight(.bold)
                    .disabled(newGoalName.isEmpty)
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.duoGreen, Color(hex: "#58CC02").opacity(0.7)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 52, height: 52)
                    Image(systemName: "clock.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("時間帯別の目標設定")
                        .font(.title3).fontWeight(.black).foregroundColor(Color.duoDark)
                    Text("1日を5つの時間帯に分けて管理")
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                }
                Spacer()
            }

            Text("夜中・朝・昼・午後・夜の時間帯ごとに、トレーニング、マインドフルネス、ログ記録の目標を設定できます。")
                .font(.caption)
                .foregroundColor(Color.duoSubtitle)
                .padding(.top, 4)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Time Slot Card

    private func timeSlotCard(timeSlot: TimeSlot, goal: TimeSlotGoal, progress: TimeSlotProgress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // ヘッダー
            HStack {
                Text(timeSlot.emoji)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(timeSlot.displayName)
                        .font(.headline).fontWeight(.black)
                        .foregroundColor(Color.duoDark)
                    Text(timeSlot.timeRange)
                        .font(.caption)
                        .foregroundColor(Color.duoSubtitle)
                }
                Spacer()

                // 達成率
                let rate = progress.completionRate(goal: goal)
                CircularProgressView(progress: rate, isCompleted: progress.isFullyCompleted(goal: goal))
            }

            Divider()

            // トレーニング目標
            goalRow(
                icon: "💪",
                label: "トレーニング",
                current: progress.trainingCompleted,
                goal: goal.trainingGoal,
                color: Color.duoGreen
            )

            // マインドフルネス目標
            goalRow(
                icon: "🧘",
                label: "マインドフルネス",
                current: progress.mindfulnessCompleted,
                goal: goal.mindfulnessGoal,
                color: Color.duoPurple
            )

            // ストレッチ・ヨガ目標（夜中以外、有効時のみ）
            if timeSlot != .midnight && goal.stretchGoal.enabled {
                let stretchColor = Color(red: 0.22, green: 0.75, blue: 0.56)
                goalRow(
                    icon: "🤸",
                    label: "ストレッチ・ヨガ",
                    current: progress.stretchSetsCompleted,
                    goal: goal.stretchGoal.stretchMinutes,
                    color: stretchColor
                )
            }

            // ログ目標（マインド入力のみ。食事・水分は1日全体の目標で管理）
            if goal.logGoal.mindInputRequired {
                logGoalRow(logGoal: goal.logGoal, logProgress: progress.logProgress)
            }

            // カスタムアクティビティ（完了ボタン付き）
            if !goal.customActivities.filter({ $0.isEnabled }).isEmpty {
                Divider()
                ForEach(goal.customActivities.filter { $0.isEnabled }) { activity in
                    customActivityRow(activity: activity, timeSlot: timeSlot, progress: progress)
                }
            }

            // 編集ボタン
            NavigationLink {
                TimeSlotGoalEditView(timeSlot: timeSlot)
            } label: {
                HStack {
                    Image(systemName: "pencil")
                    Text("目標を編集")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .foregroundColor(Color.duoGreen)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.duoGreen.opacity(0.1))
                .cornerRadius(10)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - Goal Row

    private func goalRow(icon: String, label: String, current: Int, goal: Int, color: Color) -> some View {
        HStack(spacing: 12) {
            Text(icon)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(Color.duoDark)

                HStack(spacing: 8) {
                    Text("\(current) / \(goal)")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(current >= goal ? Color.duoGreen : Color.duoSubtitle)

                    // プログレスバー
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(.systemGray5))
                                .frame(height: 4)
                            Capsule()
                                .fill(color)
                                .frame(width: goal > 0 ? min(geo.size.width, geo.size.width * CGFloat(current) / CGFloat(goal)) : 0, height: 4)
                        }
                    }
                    .frame(height: 4)
                }
            }

            Spacer()

            if current >= goal {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color.duoGreen)
                    .font(.title3)
            }
        }
    }

    // MARK: - Log Goal Row

    private func logGoalRow(logGoal: LogGoal, logProgress: LogProgress) -> some View {
        HStack(spacing: 12) {
            Text("📝")
                .font(.title3)

            VStack(alignment: .leading, spacing: 6) {
                Text("ログ記録")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(Color.duoDark)

                HStack(spacing: 8) {
                    logBadge(label: "マインド", completed: logProgress.mindInputLogged)
                }
            }

            Spacer()

            if logProgress.mindInputLogged > 0 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color.duoGreen)
                    .font(.title3)
            }
        }
    }

    // MARK: - Custom Activity Row

    private func customActivityRow(activity: CustomActivity, timeSlot: TimeSlot, progress: TimeSlotProgress) -> some View {
        let isCompleted = progress.completedActivityIds.contains(activity.id)
        return HStack(spacing: 12) {
            Text(activity.emoji)
                .font(.title3)
            Text(activity.name)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundColor(isCompleted ? Color.duoGreen : Color.duoDark)
                .strikethrough(isCompleted, color: Color.duoGreen.opacity(0.6))
            Spacer()
            Button {
                Task { await timeSlotManager.toggleCustomActivity(id: activity.id, at: timeSlot) }
            } label: {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isCompleted ? Color.duoGreen : Color(uiColor: .systemGray3))
            }
            .buttonStyle(.plain)
        }
    }

    private func logBadge(label: String, completed: Int) -> some View {
        HStack(spacing: 4) {
            if completed != 0 {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(Color.duoGreen)
            }
            Text(label)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(completed != 0 ? Color.duoGreen : Color.duoSubtitle)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(completed != 0 ? Color.duoGreen.opacity(0.1) : Color(.systemGray6))
        .cornerRadius(6)
    }
}

// MARK: - Circular Progress View

struct CircularProgressView: View {
    let progress: Double
    let isCompleted: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 4)
                .frame(width: 44, height: 44)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(isCompleted ? Color.duoGreen : Color.duoOrange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 44, height: 44)
                .rotationEffect(.degrees(-90))

            Text("\(Int(progress * 100))%")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(isCompleted ? Color.duoGreen : Color.duoDark)
        }
    }
}

#Preview {
    NavigationView {
        TimeSlotGoalsView()
    }
}
