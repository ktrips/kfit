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

            ScrollViewReader { proxy in
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
                                .id("global")

                            ForEach(TimeSlot.allCases.filter { $0 != .midnight }, id: \.self) { timeSlot in
                                if let goal = timeSlotManager.settings.goalFor(timeSlot),
                                   let progress = timeSlotManager.progress.progressFor(timeSlot) {
                                    timeSlotCard(timeSlot: timeSlot, goal: goal, progress: progress)
                                        .id(timeSlot.rawValue)
                                }
                            }

                            mandalaSection(scrollProxy: proxy)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }
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

    // MARK: - Mandala Section

    private var mandalaTodayDateText: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ja_JP")
        fmt.dateFormat = "M月d日(E)"
        return fmt.string(from: Date())
    }

    private var mandalaNodeCount: (done: Int, total: Int) {
        var done = 0, total = 0
        let settings = timeSlotManager.settings
        let progress = timeSlotManager.progress
        for slot in [TimeSlot.morning, .noon, .afternoon, .evening] {
            guard let goal = settings.goalFor(slot),
                  let prog = progress.progressFor(slot) else { continue }
            if goal.trainingGoal > 0 { total += 1; if prog.trainingCompleted >= goal.trainingGoal { done += 1 } }
            if goal.mindfulnessGoal > 0 { total += 1; if prog.mindfulnessCompleted >= goal.mindfulnessGoal { done += 1 } }
            if goal.stretchGoal.enabled { total += 1; if prog.stretchSetsCompleted >= goal.stretchGoal.stretchMinutes { done += 1 } }
            if goal.logGoal.mealGoal > 0 { total += 1; if prog.logProgress.mealLogged >= goal.logGoal.mealGoal { done += 1 } }
            if goal.logGoal.drinkGoal > 0 { total += 1; if prog.logProgress.drinkLogged >= goal.logGoal.drinkGoal { done += 1 } }
            for act in goal.customActivities.filter({ $0.isEnabled }) {
                total += 1; if prog.completedActivityIds.contains(act.id) { done += 1 }
            }
        }
        return (done, total)
    }

    private func mandalaSection(scrollProxy: ScrollViewProxy) -> some View {
        let nc = mandalaNodeCount
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.duoOrange, Color(hex: "6D5DF6")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 36, height: 36)
                    Text("🌀").font(.subheadline)
                }
                Text("Mandala")
                    .font(.subheadline).fontWeight(.black)
                    .foregroundColor(Color.duoDark)
                Spacer()
                Text(mandalaTodayDateText)
                    .font(.caption2)
                    .foregroundColor(Color.duoSubtitle)
                    .layoutPriority(1)
                Text(nc.total > 0 ? "\(nc.done)/\(nc.total)" : "--")
                    .font(.caption).fontWeight(.black)
                    .foregroundColor(nc.total > 0 && nc.done == nc.total
                                     ? Color.duoGreen : Color.duoDark)
            }

            MandalaChartView(
                settings: timeSlotManager.settings,
                progress: timeSlotManager.progress,
                onTapNode: { node in
                    withAnimation(.easeInOut(duration: 0.4)) {
                        scrollProxy.scrollTo(node.slot?.rawValue ?? "global", anchor: .top)
                    }
                }
            )
            .frame(height: 370)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
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

// MARK: - TimeSlot Mandala Color

extension TimeSlot {
    var mandalaColor: Color {
        switch self {
        case .midnight:  return Color(.systemGray3)
        case .morning:   return Color.duoOrange
        case .noon:      return Color.duoYellow
        case .afternoon: return Color.duoBlue
        case .evening:   return Color.duoPurple
        }
    }
}

// MARK: - Mandala Node Type

enum MandalaNodeType {
    case training, mindfulness, stretch, meal, drink, sleep, pfc, custom
}

// MARK: - Mandala Node Data

struct MandalaNodeData: Identifiable {
    let id: String
    let emoji: String
    let label: String
    let isCompleted: Bool
    let slot: TimeSlot?
    let type: MandalaNodeType
}

// MARK: - Mandala Chart View

struct MandalaChartView: View {
    let settings: DailyTimeSlotSettings
    let progress: DailyTimeSlotProgress
    let onTapNode: (MandalaNodeData) -> Void

    @State private var appeared = false
    @State private var pulseCenter = false

    private let minRadius: Double = 42

    var nodes: [MandalaNodeData] { Self.buildNodes(settings: settings, progress: progress) }

    static func buildNodes(settings: DailyTimeSlotSettings, progress: DailyTimeSlotProgress) -> [MandalaNodeData] {
        var result: [MandalaNodeData] = []

        // 1日合計を事前集計して、1日目標達成済みかチェック
        let activeSlots: [TimeSlot] = [.morning, .noon, .afternoon, .evening]
        var totalTrainingCompleted = 0, totalTrainingGoal = 0
        var totalMindfulnessCompleted = 0, totalMindfulnessGoal = 0
        var totalStretchCompleted = 0, totalStretchGoal = 0
        var totalMealLogged = 0, totalMealGoal = 0
        var totalDrinkLogged = 0, totalDrinkGoal = 0
        for slot in activeSlots {
            guard let goal = settings.goalFor(slot), let prog = progress.progressFor(slot) else { continue }
            totalTrainingCompleted += prog.trainingCompleted
            totalTrainingGoal += goal.trainingGoal
            totalMindfulnessCompleted += prog.mindfulnessCompleted
            totalMindfulnessGoal += goal.mindfulnessGoal
            if goal.stretchGoal.enabled {
                totalStretchCompleted += prog.stretchSetsCompleted
                totalStretchGoal += goal.stretchGoal.stretchMinutes
            }
            totalMealLogged += prog.logProgress.mealLogged
            totalMealGoal += goal.logGoal.mealGoal
            totalDrinkLogged += prog.logProgress.drinkLogged
            totalDrinkGoal += goal.logGoal.drinkGoal
        }
        // グローバル設定が有効な場合はそちらの目標値を優先
        if settings.globalGoals.mealEnabled && settings.globalGoals.dailyMealKcal > 0 {
            totalMealGoal = settings.globalGoals.dailyMealKcal
        }
        if settings.globalGoals.drinkEnabled && settings.globalGoals.dailyDrinkMl > 0 {
            totalDrinkGoal = settings.globalGoals.dailyDrinkMl
        }
        let dailyTrainingDone = totalTrainingGoal > 0 && totalTrainingCompleted >= totalTrainingGoal
        let dailyMindfulnessDone = totalMindfulnessGoal > 0 && totalMindfulnessCompleted >= totalMindfulnessGoal
        let dailyStretchDone = totalStretchGoal > 0 && totalStretchCompleted >= totalStretchGoal
        let dailyMealDone = totalMealGoal > 0 && totalMealLogged >= totalMealGoal
        let dailyDrinkDone = totalDrinkGoal > 0 && totalDrinkLogged >= totalDrinkGoal

        for slot in activeSlots {
            guard let goal = settings.goalFor(slot),
                  let prog = progress.progressFor(slot) else { continue }

            if goal.trainingGoal > 0 {
                for i in 1...goal.trainingGoal {
                    result.append(MandalaNodeData(
                        id: "\(slot.rawValue)-training-\(i)",
                        emoji: "💪",
                        label: "トレーニング",
                        isCompleted: dailyTrainingDone || prog.trainingCompleted >= i,
                        slot: slot,
                        type: .training
                    ))
                }
            }
            if goal.mindfulnessGoal > 0 {
                result.append(MandalaNodeData(
                    id: "\(slot.rawValue)-mindfulness",
                    emoji: "🧘",
                    label: "マインドフルネス",
                    isCompleted: dailyMindfulnessDone || prog.mindfulnessCompleted >= goal.mindfulnessGoal,
                    slot: slot,
                    type: .mindfulness
                ))
            }
            if goal.stretchGoal.enabled && goal.stretchGoal.stretchMinutes > 0 {
                let stretchUnits = max(1, goal.stretchGoal.stretchMinutes / 3)
                for i in 1...stretchUnits {
                    result.append(MandalaNodeData(
                        id: "\(slot.rawValue)-stretch-\(i)",
                        emoji: "🤸",
                        label: "ストレッチ",
                        isCompleted: dailyStretchDone || prog.stretchSetsCompleted >= i * 3,
                        slot: slot,
                        type: .stretch
                    ))
                }
            }
            if goal.logGoal.mealGoal > 0 {
                let mealEmoji: String = {
                    switch slot {
                    case .midnight:  return "🌙"
                    case .morning:   return "🥐"
                    case .noon:      return "🍱"
                    case .afternoon: return "🍎"
                    case .evening:   return "🍛"
                    }
                }()
                result.append(MandalaNodeData(
                    id: "\(slot.rawValue)-meal",
                    emoji: mealEmoji,
                    label: "食事",
                    isCompleted: dailyMealDone || prog.logProgress.mealLogged >= goal.logGoal.mealGoal,
                    slot: slot,
                    type: .meal
                ))
            }
            if goal.logGoal.drinkGoal > 0 {
                result.append(MandalaNodeData(
                    id: "\(slot.rawValue)-drink",
                    emoji: "💧",
                    label: "水分",
                    isCompleted: dailyDrinkDone || prog.logProgress.drinkLogged >= goal.logGoal.drinkGoal,
                    slot: slot,
                    type: .drink
                ))
            }
            for activity in goal.customActivities.filter({ $0.isEnabled }) {
                result.append(MandalaNodeData(
                    id: "\(slot.rawValue)-\(activity.id)",
                    emoji: activity.emoji,
                    label: activity.name,
                    isCompleted: prog.completedActivityIds.contains(activity.id),
                    slot: slot,
                    type: .custom
                ))
            }
        }

        // 1日全体のカスタム目標
        for goal in settings.globalGoals.customGoals.filter({ $0.isEnabled }) {
            result.append(MandalaNodeData(
                id: "global-\(goal.id)",
                emoji: goal.emoji,
                label: goal.name,
                isCompleted: progress.globalProgress.completedCustomGoalIds.contains(goal.id),
                slot: nil,
                type: .custom
            ))
        }
        if settings.globalGoals.sleepEnabled {
            let g = settings.globalGoals
            let p = progress.globalProgress
            result.append(MandalaNodeData(
                id: "global-sleep",
                emoji: "😴",
                label: "睡眠",
                isCompleted: p.sleepHours >= Double(g.sleepHoursGoal) && p.sleepScore >= g.sleepScoreThreshold,
                slot: nil,
                type: .sleep
            ))
        }
        if settings.globalGoals.pfcEnabled {
            result.append(MandalaNodeData(
                id: "global-pfc",
                emoji: "🥗",
                label: "PFC",
                isCompleted: progress.globalProgress.pfcScore >= settings.globalGoals.pfcScoreThreshold,
                slot: nil,
                type: .pfc
            ))
        }

        // 今日の曜日別カスタム目標
        let weekdayNum: Int = {
            let wd = Calendar.current.component(.weekday, from: Date())
            return wd == 1 ? 7 : wd - 1  // Calendar: 1=Sun → 1=月…7=日
        }()
        if let data = UserDefaults.standard.data(forKey: "weekdayGoals_v1"),
           let wdGoals = try? JSONDecoder().decode([WeekdayGoal].self, from: data),
           let wg = wdGoals.first(where: { $0.weekday == weekdayNum && $0.hasAnyGoal }) {
            let gp = progress.globalProgress
            if wg.studyEnabled {
                result.append(MandalaNodeData(
                    id: "wd-study",
                    emoji: "📚",
                    label: "勉強",
                    isCompleted: gp.completedCustomGoalIds.contains("wd_study_\(weekdayNum)"),
                    slot: nil,
                    type: .custom
                ))
            }
            if wg.noAlcoholEnabled {
                result.append(MandalaNodeData(
                    id: "wd-noalcohol",
                    emoji: "🚫",
                    label: "禁酒",
                    isCompleted: gp.completedCustomGoalIds.contains("wd_noalcohol_\(weekdayNum)"),
                    slot: nil,
                    type: .custom
                ))
            }
            for cg in wg.customGoals {
                result.append(MandalaNodeData(
                    id: "wd-\(cg.id.uuidString)",
                    emoji: cg.emoji,
                    label: cg.name,
                    isCompleted: gp.completedCustomGoalIds.contains("wd_\(cg.id.uuidString)"),
                    slot: nil,
                    type: .custom
                ))
            }
        }

        // 毎日のカスタム目標
        if let data = UserDefaults.standard.data(forKey: "dailyFixedGoals_v1"),
           let fixed = try? JSONDecoder().decode(DailyFixedGoals.self, from: data) {
            let gp = progress.globalProgress
            for cg in fixed.customGoals {
                result.append(MandalaNodeData(
                    id: "daily-\(cg.id.uuidString)",
                    emoji: cg.emoji,
                    label: cg.name,
                    isCompleted: gp.completedCustomGoalIds.contains("daily_custom_\(cg.id.uuidString)"),
                    slot: nil,
                    type: .custom
                ))
            }
        }

        return Array(result.prefix(40))
    }

    @ViewBuilder
    private func legendCell(label: String, color: Color, done: Int, total: Int) -> some View {
        HStack(spacing: 2) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(total > 0 ? "\(label)(\(done)/\(total))" : label)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .foregroundColor(total > 0 && done == total ? color : Color.duoSubtitle)
        }
        .padding(.horizontal, 3).padding(.vertical, 1)
        .background(total > 0 && done == total ? color.opacity(0.12) : Color.clear)
        .cornerRadius(3)
    }

    var body: some View {
        let nodes = self.nodes  // 1回だけ計算（UserDefaults読み込み含む）
        let hour = Calendar.current.component(.hour, from: Date())
        let visibleSlots: [TimeSlot] = {
            if hour < 10 { return [.morning] }
            else if hour < 14 { return [.morning, .noon] }
            else if hour < 18 { return [.morning, .noon, .afternoon] }
            else { return [.morning, .noon, .afternoon, .evening] }
        }()
        let todayNodes   = nodes.filter { $0.slot == nil }
        let allDone      = nodes.filter(\.isCompleted).count
        let allTotal     = nodes.count

        return VStack(spacing: 2) {
            // 時間帯凡例（今日 + 現在時刻までのスロット）
            HStack(spacing: 2) {
                legendCell(label: "今日", color: Color(hex: "CE82FF"),
                           done: todayNodes.filter(\.isCompleted).count, total: todayNodes.count)
                ForEach(visibleSlots, id: \.self) { slot in
                    let sn = nodes.filter { $0.slot == slot }
                    legendCell(label: slot.displayName, color: slot.mandalaColor,
                               done: sn.filter(\.isCompleted).count, total: sn.count)
                }
                Spacer(minLength: 0)
            }

            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let canvasR = size / 2 - 14
                let (positions, nodeAngles) = computePositions(center: center, canvasR: canvasR)

            ZStack {
                // 背景円
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(.systemGray6).opacity(0.14), Color(.systemGray5).opacity(0.22)],
                            center: .center,
                            startRadius: 4,
                            endRadius: size * 0.48
                        )
                    )
                    .frame(width: size - 16, height: size - 16)
                    .position(center)

                // 背景スパイラルレール（淡い溝）
                fullSpiralPath(positions: positions, angles: nodeAngles, center: center)
                    .stroke(Color(.systemGray4).opacity(0.18), lineWidth: 1)

                // 中心→最初のノードの接続
                if let first = positions.first {
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: first)
                    }
                    .stroke(Color(.systemGray3).opacity(0.4), lineWidth: 5)
                }

                // ノード間の滑らかな弧（曼荼羅風数珠繋ぎ）
                if nodes.count >= 2 {
                    ForEach(0..<(nodes.count - 1), id: \.self) { i in
                        let segColor = nodes[i].slot?.mandalaColor ?? Color(hex: "CE82FF")
                        let segOpacity = nodes[i].isCompleted ? 0.52 : 0.16
                        smoothArcPath(from: i, to: i + 1, positions: positions, angles: nodeAngles, center: center)
                            .stroke(segColor.opacity(segOpacity), lineWidth: 16)
                    }
                }

                // ノードボタン
                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    let pos = index < positions.count ? positions[index] : center
                    MandalaNodeButton(
                        node: node,
                        delay: Double(index) * 0.045,
                        appeared: appeared,
                        action: { onTapNode(node) }
                    )
                    .frame(width: 36, height: 36)
                    .position(pos)
                }

                // 中心プログレス
                centerCircle(nodes: nodes)
                    .position(center)
                    .scaleEffect(pulseCenter ? 1.07 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                        value: pulseCenter
                    )
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if allTotal > 0 {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(allDone)/\(allTotal)")
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(allDone == allTotal ? Color.duoGreen : Color.duoDark)
                    Text("全体")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color.duoSubtitle)
                }
                .padding(8)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { pulseCenter = true }
        }
        }  // end VStack
    }

    // MARK: - Spiral helpers

    /// Archimedean spiral with adaptive Δθ: pitch = 2πb = D → guaranteed no cross-arm or consecutive overlap
    private func computePositions(center: CGPoint, canvasR: Double) -> (positions: [CGPoint], angles: [Double]) {
        let count = nodes.count
        guard count > 0 else { return ([], []) }
        let D: Double = 46          // minimum center-to-center spacing (node 36pt + 10pt gap)
        let b = D / (2 * .pi)       // growth rate: pitch 2πb = D
        var positions: [CGPoint] = []
        var angles: [Double] = []
        var angle = -Double.pi / 2  // start pointing upward
        var r = minRadius
        for _ in 0..<count {
            let cr = min(r, canvasR)
            positions.append(CGPoint(x: center.x + cr * cos(angle), y: center.y + cr * sin(angle)))
            angles.append(angle)
            // Δθ ≈ D / √(r² + b²) keeps chord between consecutive nodes ≈ D
            let dt = D / sqrt(r * r + b * b)
            angle += dt
            r = minRadius + b * (angle + .pi / 2)
        }
        return (positions, angles)
    }

    // ノードi→ノードi+1 を螺旋曲線に沿って滑らかに繋ぐ弧
    private func smoothArcPath(from startIdx: Int, to endIdx: Int,
                                positions: [CGPoint], angles: [Double],
                                center: CGPoint) -> Path {
        guard startIdx < positions.count, endIdx < positions.count else { return Path() }
        let a0 = angles[startIdx], a1 = angles[endIdx]
        let r0 = hypot(positions[startIdx].x - center.x, positions[startIdx].y - center.y)
        let r1 = hypot(positions[endIdx].x - center.x, positions[endIdx].y - center.y)
        let steps = 24
        return Path { path in
            for step in 0...steps {
                let t = Double(step) / Double(steps)
                let a = a0 + (a1 - a0) * t
                let r = r0 + (r1 - r0) * t
                let point = CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
                step == 0 ? path.move(to: point) : path.addLine(to: point)
            }
        }
    }

    // 背景レール：ノード位置を繋ぐ連続した螺旋を描く
    private func fullSpiralPath(positions: [CGPoint], angles: [Double], center: CGPoint) -> Path {
        guard positions.count >= 2 else { return Path() }
        return Path { path in
            for i in 0..<(positions.count - 1) {
                let a0 = angles[i], a1 = angles[i + 1]
                let r0 = hypot(positions[i].x - center.x, positions[i].y - center.y)
                let r1 = hypot(positions[i + 1].x - center.x, positions[i + 1].y - center.y)
                let steps = 12
                for step in 0...steps {
                    let t = Double(step) / Double(steps)
                    let a = a0 + (a1 - a0) * t
                    let r = r0 + (r1 - r0) * t
                    let pt = CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
                    if i == 0 && step == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
            }
        }
    }

    private struct RingSegment {
        let color: Color
        let start: Double
        let end: Double
    }

    private func buildRingSegments(nodes: [MandalaNodeData]) -> [RingSegment] {
        let total = nodes.count
        guard total > 0 else { return [] }
        let slotOrder: [(TimeSlot?, Color)] = [
            (.morning,   TimeSlot.morning.mandalaColor),
            (.noon,      TimeSlot.noon.mandalaColor),
            (.afternoon, TimeSlot.afternoon.mandalaColor),
            (.evening,   TimeSlot.evening.mandalaColor),
            (nil,        Color(hex: "CE82FF"))
        ]
        let gap = 0.008
        var result: [RingSegment] = []
        var cum = 0.0
        for (slot, color) in slotOrder {
            let count = nodes.filter { $0.slot == slot }.count
            guard count > 0 else { continue }
            let fraction = Double(count) / Double(total)
            let segEnd = cum + fraction - gap
            if segEnd > cum { result.append(RingSegment(color: color, start: cum, end: segEnd)) }
            cum += fraction
        }
        return result
    }

    @ViewBuilder
    private func centerCircle(nodes: [MandalaNodeData]) -> some View {
        let total = nodes.count
        let completed = nodes.filter(\.isCompleted).count
        let progress = total > 0 ? Double(completed) / Double(total) : 0.0
        let segments = buildRingSegments(nodes: nodes)
        ZStack {
            Circle()
                .fill(Color(.systemBackground))
                .frame(width: 72, height: 72)
                .shadow(color: .black.opacity(0.12), radius: 6)

            // 外側リング：時間帯別タスク割合（背景トラック）
            Circle()
                .stroke(Color(.systemGray6), lineWidth: 5.5)
                .frame(width: 64, height: 64)

            // 外側リング：時間帯カラーセグメント
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                Circle()
                    .trim(from: seg.start, to: seg.end)
                    .stroke(seg.color, style: StrokeStyle(lineWidth: 5.5, lineCap: .butt))
                    .frame(width: 64, height: 64)
                    .rotationEffect(.degrees(-90))
            }

            // 内側リング：実際の進捗（背景トラック）
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 4)
                .frame(width: 52, height: 52)

            // 内側リング：グリーン進捗
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.duoGreen, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 52, height: 52)
                .rotationEffect(.degrees(-90))

            VStack(spacing: -1) {
                Text("\(Int(progress * 100))")
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(Color.duoDark)
                Text("%")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color.duoSubtitle)
            }
        }
    }
}

// MARK: - Mandala Node Button

struct MandalaNodeButton: View {
    let node: MandalaNodeData
    let delay: Double
    let appeared: Bool
    let action: () -> Void

    @State private var tapped = false

    private var nodeColor: Color {
        node.slot?.mandalaColor ?? Color(hex: "CE82FF")
    }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.6)) { tapped = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                tapped = false
                action()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(nodeColor.opacity(node.isCompleted ? 0.88 : 0.07))
                Circle()
                    .strokeBorder(nodeColor, lineWidth: node.isCompleted ? 2.5 : 1)
                    .opacity(node.isCompleted ? 1.0 : 0.22)
                Text(node.emoji)
                    .font(.system(size: 15))
                    .opacity(node.isCompleted ? 1.0 : 0.55)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(node.isCompleted ? 1.1 : 1.0)
        .scaleEffect(tapped ? 0.82 : 1.0)
        .scaleEffect(appeared ? 1.0 : 0.0)
        .opacity(appeared ? 1.0 : 0.0)
        .animation(
            .spring(response: 0.44, dampingFraction: 0.68).delay(delay),
            value: appeared
        )
        // 完了時の外縁グロー
        .overlay(
            node.isCompleted
                ? Circle()
                    .strokeBorder(nodeColor.opacity(0.55), lineWidth: 3)
                    .frame(width: 50, height: 50)
                : nil
        )
    }
}

#Preview {
    NavigationView {
        TimeSlotGoalsView()
    }
}
