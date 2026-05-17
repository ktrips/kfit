import SwiftUI
import UserNotifications

// MARK: - リマインダーメタデータ

private struct ReminderMeta: Identifiable {
    let id: String
    let emoji: String
    let label: String
    let description: String
}

private let reminderItems: [ReminderMeta] = [
    ReminderMeta(id: NotificationManager.ID.amReminder,
                 emoji: "🌅", label: "朝のリマインダー",
                 description: "朝の時間帯の開始時に通知"),
    ReminderMeta(id: NotificationManager.ID.amFollowup,
                 emoji: "🔥", label: "朝のアラート",
                 description: "朝のトレーニングが実施されていなかった時のみ"),
    ReminderMeta(id: NotificationManager.ID.noonReminder,
                 emoji: "☀️", label: "昼のリマインダー",
                 description: "昼の時間帯の開始時に通知"),
    ReminderMeta(id: NotificationManager.ID.noonFollowup,
                 emoji: "💡", label: "昼のアラート",
                 description: "昼のトレーニングが実施されていなかった時のみ"),
    ReminderMeta(id: NotificationManager.ID.afternoonReminder,
                 emoji: "🌤️", label: "午後のリマインダー",
                 description: "午後の時間帯の開始時に通知"),
    ReminderMeta(id: NotificationManager.ID.afternoonFollowup,
                 emoji: "⚡", label: "午後のアラート",
                 description: "午後のトレーニングが実施されていなかった時のみ"),
    ReminderMeta(id: NotificationManager.ID.pmReminder,
                 emoji: "🌆", label: "夜のリマインダー",
                 description: "夜の時間帯の開始時に通知"),
    ReminderMeta(id: NotificationManager.ID.pmFollowup,
                 emoji: "🌙", label: "夜のアラート",
                 description: "夜のトレーニングが実施されていなかった時のみ"),
    ReminderMeta(id: NotificationManager.ID.streakAlert,
                 emoji: "🚨", label: "ストリーク・アラート",
                 description: "その日の記録がない時に、連続記録が途絶えちゃうよ！とアラート"),
]

// MARK: - SettingsView

struct SettingsView: View {
    @StateObject private var notif = NotificationManager.shared
    @StateObject private var timeSlotManager = TimeSlotManager.shared
    @State private var watchAutoLaunch = iOSWatchBridge.isWatchAutoLaunchEnabled
    @State private var permStatus: UNAuthorizationStatus = .notDetermined
    @State private var showHabitStack = false
    @State private var showShortcutsGuide = false
    @State private var savedBanner = false
    @State private var setConfiguration = SetConfiguration.defaultSet
    @State private var motionSensitivity: [String: MotionSensitivity] = MotionSensitivity.defaultSettings
    @State private var showSetEditor = false
    @State private var showSensitivityEditor = false
    @State private var showIntakeSettings = false
    @State private var showLLMSettings = false
    @State private var showAddCustomGoal = false
    @State private var newGoalName = ""
    @State private var newGoalEmoji = "⭐"
    // 時間帯別カスタム活動
    @State private var activeActivitySlot: TimeSlot? = nil
    @State private var newActivityName = ""
    @State private var newActivityEmoji = "⭐"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.duoBg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    headerSection
                    permissionBanner
                    // 時間帯別の目標（インライン表示）
                    timeSlotGoalsInlineSection
                    setConfigurationSection
                    motionSensitivitySection
                    intakeSection
                    llmSection
                    reminderSection
                    watchSection
                    habitStackSection
                    linkedAppsSection
                    saveButton
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshPermStatus()
            setConfiguration = await AuthenticationManager.shared.getSetConfiguration()
            motionSensitivity = await AuthenticationManager.shared.getAllMotionSensitivity()
            await timeSlotManager.loadTodaySettings()
            await timeSlotManager.loadTodayProgress()
        }
        .sheet(isPresented: $showHabitStack) { NavigationView { HabitStackView() } }
        .sheet(isPresented: $showShortcutsGuide) { ShortcutsGuideView() }
        .sheet(isPresented: $showSetEditor) {
            SetConfigurationEditorView(configuration: $setConfiguration)
        }
        .sheet(isPresented: $showSensitivityEditor) {
            MotionSensitivityEditorView(sensitivity: $motionSensitivity)
        }
        .sheet(isPresented: $showIntakeSettings) {
            IntakeSettingsView()
        }
        .sheet(isPresented: $showLLMSettings) {
            NavigationView { LLMSettingsView() }
        }
        .sheet(isPresented: $showAddCustomGoal) {
            addCustomGoalSheet
        }
        .sheet(isPresented: Binding(
            get: { activeActivitySlot != nil },
            set: { if !$0 { activeActivitySlot = nil; newActivityName = ""; newActivityEmoji = "⭐" } }
        )) {
            addActivitySheet
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image("mascot")
                .resizable().scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.duoGreen, lineWidth: 2))
            VStack(alignment: .leading, spacing: 2) {
                Text("設定")
                    .font(.title3).fontWeight(.black).foregroundColor(Color.duoDark)
                Text("通知・連動起動のカスタマイズ")
                    .font(.caption).foregroundColor(Color.duoSubtitle)
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - 時間帯別目標（インライン）

    private var timeSlotGoalsInlineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "clock.fill", title: "時間帯別の目標",
                          subtitle: "夜中・朝・昼・午後・夜ごとに設定")

            if timeSlotManager.isLoading {
                ProgressView()
                    .tint(Color.duoGreen)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                // 1日全体の目標
                globalGoalsInline

                // 時間帯別カード
                ForEach(TimeSlot.allCases, id: \.self) { slot in
                    if let goal = timeSlotManager.settings.goalFor(slot),
                       let progress = timeSlotManager.progress.progressFor(slot) {
                        timeSlotCardInline(slot: slot, goal: goal, progress: progress)
                    }
                }
            }
        }
    }

    // MARK: - 1日全体の目標（インライン）

    private var globalGoalsInline: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("🌍").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("1日全体の目標")
                        .font(.headline).fontWeight(.black).foregroundColor(Color.duoDark)
                    Text("時間帯に関係なく1日の合計で管理")
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                }
                Spacer()
            }
            .padding(.bottom, 14)

            // ワークアウト
            let workoutOn = timeSlotManager.settings.globalGoals.workoutEnabled
            globalToggleRow(
                emoji: "🏃", label: "ワークアウト",
                badge: workoutOn ? "\(timeSlotManager.settings.globalGoals.workoutMinutes)分" : nil,
                badgeColor: Color.duoGreen,
                isOn: Binding(
                    get: { timeSlotManager.settings.globalGoals.workoutEnabled },
                    set: { v in timeSlotManager.settings.globalGoals.workoutEnabled = v; Task { await timeSlotManager.saveTodaySettings() } }
                )
            )
            if workoutOn {
                globalStepperRow(
                    label: "目標",
                    valueText: "\(timeSlotManager.settings.globalGoals.workoutMinutes)分",
                    color: Color.duoGreen,
                    value: Binding(
                        get: { timeSlotManager.settings.globalGoals.workoutMinutes },
                        set: { v in timeSlotManager.settings.globalGoals.workoutMinutes = v; Task { await timeSlotManager.saveTodaySettings() } }
                    ), in: 5...120, step: 5
                )
            }

            globalDivider

            // スタンド時間
            let standOn = timeSlotManager.settings.globalGoals.standEnabled
            globalToggleRow(
                emoji: "🕐", label: "スタンド時間",
                badge: standOn ? "\(timeSlotManager.settings.globalGoals.standHours)時間" : nil,
                badgeColor: Color.duoBlue,
                isOn: Binding(
                    get: { timeSlotManager.settings.globalGoals.standEnabled },
                    set: { v in timeSlotManager.settings.globalGoals.standEnabled = v; Task { await timeSlotManager.saveTodaySettings() } }
                )
            )
            if standOn {
                globalStepperRow(
                    label: "目標",
                    valueText: "\(timeSlotManager.settings.globalGoals.standHours)時間",
                    color: Color.duoBlue,
                    value: Binding(
                        get: { timeSlotManager.settings.globalGoals.standHours },
                        set: { v in timeSlotManager.settings.globalGoals.standHours = v; Task { await timeSlotManager.saveTodaySettings() } }
                    ), in: 1...16, step: 1
                )
            }

            globalDivider

            // PFCバランス
            let pfcOn = timeSlotManager.settings.globalGoals.pfcEnabled
            globalToggleRow(
                emoji: "🥗", label: "食事の計測（PFC）",
                badge: pfcOn ? "\(timeSlotManager.settings.globalGoals.pfcScoreThreshold)点" : nil,
                badgeColor: Color.duoOrange,
                isOn: Binding(
                    get: { timeSlotManager.settings.globalGoals.pfcEnabled },
                    set: { v in timeSlotManager.settings.globalGoals.pfcEnabled = v; Task { await timeSlotManager.saveTodaySettings() } }
                )
            )
            if pfcOn {
                globalStepperRow(
                    label: "目標スコア",
                    valueText: "\(timeSlotManager.settings.globalGoals.pfcScoreThreshold)点以上",
                    color: Color.duoOrange,
                    value: Binding(
                        get: { timeSlotManager.settings.globalGoals.pfcScoreThreshold },
                        set: { v in timeSlotManager.settings.globalGoals.pfcScoreThreshold = v; Task { await timeSlotManager.saveTodaySettings() } }
                    ), in: 50...100, step: 5
                )
            }

            globalDivider

            // 体重計測
            let weightOn = timeSlotManager.settings.globalGoals.weightEnabled
            globalToggleRow(
                emoji: "⚖️", label: "体重の計測",
                badge: weightOn ? "ON" : nil,
                badgeColor: Color.duoPurple,
                isOn: Binding(
                    get: { timeSlotManager.settings.globalGoals.weightEnabled },
                    set: { v in timeSlotManager.settings.globalGoals.weightEnabled = v; Task { await timeSlotManager.saveTodaySettings() } }
                )
            )

            globalDivider

            // カスタム目標
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("🎨").font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("カスタム目標").font(.subheadline).fontWeight(.semibold).foregroundColor(Color.duoDark)
                        Text("自由に目標を追加できます").font(.caption2).foregroundColor(Color.duoSubtitle)
                    }
                    Spacer()
                    Button { showAddCustomGoal = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundColor(Color.duoGreen)
                    }
                }
                ForEach(timeSlotManager.settings.globalGoals.customGoals) { goal in
                    HStack(spacing: 10) {
                        Text(goal.emoji).font(.title3)
                        Text(goal.name).font(.subheadline).fontWeight(.semibold).foregroundColor(Color.duoDark)
                        Spacer()
                        if timeSlotManager.progress.globalProgress.completedCustomGoalIds.contains(goal.id) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(Color.duoGreen).font(.subheadline)
                        }
                        Button {
                            timeSlotManager.settings.globalGoals.customGoals.removeAll { $0.id == goal.id }
                            Task { await timeSlotManager.saveTodaySettings() }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundColor(Color.duoRed.opacity(0.7)).font(.subheadline)
                        }
                    }.padding(.leading, 8)
                }
                if timeSlotManager.settings.globalGoals.customGoals.isEmpty {
                    Text("例: 読書📚・Duolingo🦉・禁酒🚫など")
                        .font(.caption2).foregroundColor(Color.duoSubtitle).padding(.leading, 8)
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    private var globalDivider: some View {
        Divider().padding(.vertical, 10)
    }

    private func globalToggleRow(emoji: String, label: String, badge: String?, badgeColor: Color, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 8) {
                Text(emoji).font(.title3)
                    .opacity(isOn.wrappedValue ? 1.0 : 0.35)
                Text(label)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(isOn.wrappedValue ? Color.duoDark : Color(.systemGray3))
                if let badge, isOn.wrappedValue {
                    Text(badge)
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(badgeColor)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(badgeColor.opacity(0.12))
                        .cornerRadius(6)
                }
            }
        }.tint(Color.duoGreen)
    }

    private func globalStepperRow(label: String, valueText: String, color: Color, value: Binding<Int>, in range: ClosedRange<Int>, step: Int) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption).foregroundColor(Color.duoSubtitle)
            Spacer()
            Text(valueText)
                .font(.caption).fontWeight(.bold)
                .foregroundColor(color)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(color.opacity(0.10))
                .cornerRadius(6)
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
                .fixedSize()
        }
        .padding(.leading, 40)
        .padding(.bottom, 4)
    }

    // MARK: - 時間帯別カード（インライン）

    private func reminderIds(for slot: TimeSlot) -> (reminder: String, followup: String) {
        switch slot {
        case .midnight:  return (NotificationManager.ID.amReminder,        NotificationManager.ID.amFollowup)
        case .morning:   return (NotificationManager.ID.amReminder,        NotificationManager.ID.amFollowup)
        case .noon:      return (NotificationManager.ID.noonReminder,      NotificationManager.ID.noonFollowup)
        case .afternoon: return (NotificationManager.ID.afternoonReminder, NotificationManager.ID.afternoonFollowup)
        case .evening:   return (NotificationManager.ID.pmReminder,        NotificationManager.ID.pmFollowup)
        }
    }

    private func slotStepperRow(emoji: String, label: String, valueText: String, valueColor: Color, value: Binding<Int>, in range: ClosedRange<Int>) -> some View {
        HStack(spacing: 8) {
            Text(emoji).font(.title3)
            Text(label)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundColor(Color.duoDark)
            Spacer()
            Text(valueText)
                .font(.caption).fontWeight(.bold)
                .foregroundColor(valueColor)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(valueColor.opacity(0.12))
                .cornerRadius(7)
            Stepper("", value: value, in: range)
                .labelsHidden()
                .fixedSize()
        }
    }

    private func timeSlotCardInline(slot: TimeSlot, goal: TimeSlotGoal, progress: TimeSlotProgress) -> some View {
        let ids = reminderIds(for: slot)
        return VStack(alignment: .leading, spacing: 10) {
            // ヘッダー
            HStack {
                Text(slot.emoji).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.displayName).font(.headline).fontWeight(.black).foregroundColor(Color.duoDark)
                    Text(slot.timeRange).font(.caption).foregroundColor(Color.duoSubtitle)
                }
                Spacer()
                if slot == .midnight {
                    // 睡眠達成バッジ
                    let sg = timeSlotManager.settings.globalGoals
                    let sp = timeSlotManager.progress.globalProgress
                    if sg.sleepEnabled && (sp.sleepHours > 0 || sp.sleepScore > 0) {
                        let achieved = sp.sleepHours >= Double(sg.sleepHoursGoal) && sp.sleepScore >= sg.sleepScoreThreshold
                        Image(systemName: achieved ? "checkmark.circle.fill" : "moon.zzz.fill")
                            .foregroundColor(achieved ? Color.duoGreen : Color.duoSubtitle)
                            .font(.title3)
                    }
                } else {
                    CircularProgressView(
                        progress: progress.completionRate(goal: goal),
                        isCompleted: progress.isFullyCompleted(goal: goal)
                    )
                }
            }

            Divider()

            if slot == .midnight {
                // 夜中スロット: 睡眠設定
                sleepGoalRows
                Divider()
                customActivityRows(slot: slot, goal: goal)
            } else {
                // 通常スロット
                if goal.trainingGoal > 0 {
                    slotStepperRow(
                        emoji: "💪", label: "トレーニング",
                        valueText: "\(goal.trainingGoal)セット", valueColor: Color.duoGreen,
                        value: Binding(
                            get: { goal.trainingGoal },
                            set: { v in var g = goal; g.trainingGoal = v; timeSlotManager.settings.updateGoal(g); Task { await timeSlotManager.saveTodaySettings() } }
                        ), in: 0...10
                    )
                }

                if goal.mindfulnessGoal > 0 {
                    slotStepperRow(
                        emoji: "🧘", label: "マインドフルネス",
                        valueText: "\(goal.mindfulnessGoal)回", valueColor: Color.duoPurple,
                        value: Binding(
                            get: { goal.mindfulnessGoal },
                            set: { v in var g = goal; g.mindfulnessGoal = v; timeSlotManager.settings.updateGoal(g); Task { await timeSlotManager.saveTodaySettings() } }
                        ), in: 0...10
                    )
                }

                // 未設定の項目への追加ボタン
                if goal.trainingGoal == 0 || goal.mindfulnessGoal == 0 {
                    HStack(spacing: 8) {
                        if goal.trainingGoal == 0 {
                            Button {
                                var g = goal; g.trainingGoal = 1
                                timeSlotManager.settings.updateGoal(g)
                                Task { await timeSlotManager.saveTodaySettings() }
                            } label: {
                                Label("トレーニング", systemImage: "plus.circle")
                                    .font(.caption).fontWeight(.semibold)
                                    .foregroundColor(Color.duoGreen)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.duoGreen.opacity(0.1))
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                        if goal.mindfulnessGoal == 0 {
                            Button {
                                var g = goal; g.mindfulnessGoal = 1
                                timeSlotManager.settings.updateGoal(g)
                                Task { await timeSlotManager.saveTodaySettings() }
                            } label: {
                                Label("マインドフル", systemImage: "plus.circle")
                                    .font(.caption).fontWeight(.semibold)
                                    .foregroundColor(Color.duoPurple)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.duoPurple.opacity(0.1))
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                }

                slotStepperRow(
                    emoji: "🍽️", label: "食事ログ",
                    valueText: goal.logGoal.mealGoal == 0 ? "なし" : "\(goal.logGoal.mealGoal)回",
                    valueColor: goal.logGoal.mealGoal > 0 ? Color.duoOrange : Color(.systemGray3),
                    value: Binding(
                        get: { goal.logGoal.mealGoal },
                        set: { v in var g = goal; g.logGoal.mealGoal = v; timeSlotManager.settings.updateGoal(g); Task { await timeSlotManager.saveTodaySettings() } }
                    ), in: 0...10
                )
                slotStepperRow(
                    emoji: "💧", label: "飲み物ログ",
                    valueText: goal.logGoal.drinkGoal == 0 ? "なし" : "\(goal.logGoal.drinkGoal)回",
                    valueColor: goal.logGoal.drinkGoal > 0 ? Color.duoBlue : Color(.systemGray3),
                    value: Binding(
                        get: { goal.logGoal.drinkGoal },
                        set: { v in var g = goal; g.logGoal.drinkGoal = v; timeSlotManager.settings.updateGoal(g); Task { await timeSlotManager.saveTodaySettings() } }
                    ), in: 0...10
                )

                customActivityRows(slot: slot, goal: goal)

                Divider()

                ReminderRow(
                    meta: ReminderMeta(id: ids.reminder,
                                       emoji: "🔔",
                                       label: "\(slot.displayName)のリマインダー",
                                       description: "\(slot.timeRange) 開始時に通知"),
                    config: Binding(
                        get: { notif.prefs[ids.reminder] },
                        set: { notif.prefs[ids.reminder] = $0 }
                    )
                )

                ReminderRow(
                    meta: ReminderMeta(id: ids.followup,
                                       emoji: "⚡",
                                       label: "\(slot.displayName)のアラート",
                                       description: "トレーニング未実施の時のみ通知"),
                    config: Binding(
                        get: { notif.prefs[ids.followup] },
                        set: { notif.prefs[ids.followup] = $0 }
                    )
                )
            }
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    // 夜中スロット用: 睡眠設定行
    @ViewBuilder
    private var sleepGoalRows: some View {
        let gg = timeSlotManager.settings.globalGoals
        let gp = timeSlotManager.progress.globalProgress

        // 睡眠計測トグル
        Toggle(isOn: Binding(
            get: { gg.sleepEnabled },
            set: { v in
                timeSlotManager.settings.globalGoals.sleepEnabled = v
                Task { await timeSlotManager.saveTodaySettings() }
            }
        )) {
            HStack(spacing: 8) {
                Text("😴").font(.title3)
                Text("睡眠の計測").font(.subheadline).fontWeight(.semibold).foregroundColor(Color.duoDark)
            }
        }.tint(Color.duoGreen)

        if gg.sleepEnabled {
            // 目標時間
            HStack {
                Text("目標時間:").font(.caption).foregroundColor(Color.duoSubtitle)
                Stepper("\(gg.sleepHoursGoal)時間以上",
                        value: Binding(
                            get: { gg.sleepHoursGoal },
                            set: { v in
                                timeSlotManager.settings.globalGoals.sleepHoursGoal = v
                                Task { await timeSlotManager.saveTodaySettings() }
                            }
                        ), in: 1...12, step: 1)
                .font(.subheadline).fontWeight(.bold)
            }.padding(.leading, 36)

            // 目標スコア
            HStack {
                Text("目標スコア:").font(.caption).foregroundColor(Color.duoSubtitle)
                Stepper("\(gg.sleepScoreThreshold)点以上",
                        value: Binding(
                            get: { gg.sleepScoreThreshold },
                            set: { v in
                                timeSlotManager.settings.globalGoals.sleepScoreThreshold = v
                                Task { await timeSlotManager.saveTodaySettings() }
                            }
                        ), in: 50...100, step: 5)
                .font(.subheadline).fontWeight(.bold)
            }.padding(.leading, 36)

            // 昨夜の実績
            if gp.sleepHours > 0 || gp.sleepScore > 0 {
                HStack(spacing: 10) {
                    Text("昨夜:").font(.caption).foregroundColor(Color.duoSubtitle)
                    Text(String(format: "%.1f時間", gp.sleepHours))
                        .font(.subheadline).fontWeight(.bold)
                        .foregroundColor(gp.sleepHours >= Double(gg.sleepHoursGoal) ? Color.duoGreen : Color.duoDark)
                    if gp.sleepScore > 0 {
                        Text("\(gp.sleepScore)点")
                            .font(.subheadline).fontWeight(.bold)
                            .foregroundColor(gp.sleepScore >= gg.sleepScoreThreshold ? Color.duoGreen : Color.duoDark)
                    }
                    if gp.sleepHours >= Double(gg.sleepHoursGoal) && gp.sleepScore >= gg.sleepScoreThreshold {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color.duoGreen).font(.caption)
                    }
                }.padding(.leading, 36)
            }
        }
    }

    // MARK: - カスタム目標追加シート

    private var addCustomGoalSheet: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("絵文字").font(.caption).fontWeight(.bold).foregroundColor(Color.duoSubtitle)
                    TextField("絵文字を入力（例: 📚）", text: $newGoalEmoji)
                        .font(.system(size: 36)).multilineTextAlignment(.center)
                        .padding().background(Color(.systemGray6)).cornerRadius(12)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("目標名").font(.caption).fontWeight(.bold).foregroundColor(Color.duoSubtitle)
                    TextField("例: 読書、Duolingo、禁酒…", text: $newGoalName)
                        .padding().background(Color(.systemGray6)).cornerRadius(12)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(CustomDailyGoal.presets) { preset in
                        Button {
                            newGoalEmoji = preset.emoji; newGoalName = preset.name
                        } label: {
                            VStack(spacing: 4) {
                                Text(preset.emoji).font(.title2)
                                Text(preset.name).font(.caption2).fontWeight(.bold).foregroundColor(Color.duoDark)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(newGoalName == preset.name ? Color.duoGreen.opacity(0.15) : Color(.systemGray6))
                            .cornerRadius(10)
                        }.buttonStyle(.plain)
                    }
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle("カスタム目標を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") { newGoalName = ""; newGoalEmoji = "⭐"; showAddCustomGoal = false }
                        .foregroundColor(Color.duoSubtitle)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("追加") {
                        guard !newGoalName.isEmpty else { return }
                        let goal = CustomDailyGoal(name: newGoalName, emoji: newGoalEmoji.isEmpty ? "⭐" : String(newGoalEmoji.prefix(2)))
                        timeSlotManager.settings.globalGoals.customGoals.append(goal)
                        Task { await timeSlotManager.saveTodaySettings() }
                        newGoalName = ""; newGoalEmoji = "⭐"; showAddCustomGoal = false
                    }
                    .foregroundColor(Color.duoGreen).fontWeight(.bold).disabled(newGoalName.isEmpty)
                }
            }
        }
    }


    // MARK: - 時間帯別カスタム活動（共通行）

    @ViewBuilder
    private func customActivityRows(slot: TimeSlot, goal: TimeSlotGoal) -> some View {
        HStack(spacing: 8) {
            Text("🎯").font(.title3)
            Text("カスタム").font(.subheadline).fontWeight(.semibold).foregroundColor(Color.duoDark)
            Spacer()
            Button {
                activeActivitySlot = slot
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundColor(Color.duoGreen)
            }
        }

        ForEach(goal.customActivities) { activity in
            HStack(spacing: 8) {
                Text(activity.emoji).font(.subheadline)
                Text(activity.name)
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundColor(Color.duoDark)
                Spacer()
                Button {
                    var g = goal
                    g.customActivities.removeAll { $0.id == activity.id }
                    timeSlotManager.settings.updateGoal(g)
                    Task { await timeSlotManager.saveTodaySettings() }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(Color.duoRed.opacity(0.7))
                        .font(.subheadline)
                }
            }
            .padding(.leading, 36)
        }
    }

    // MARK: - カスタム活動追加シート

    private var addActivitySheet: some View {
        let activityPresets: [CustomActivity] = [
            .duolingo, .reading, .meditation, .stretching,
            CustomActivity(name: "ジョギング", emoji: "🏃"),
            CustomActivity(name: "日記",       emoji: "📓"),
        ]
        return NavigationView {
            VStack(spacing: 20) {
                HStack(spacing: 12) {
                    TextField("絵文字", text: $newActivityEmoji)
                        .font(.system(size: 28))
                        .multilineTextAlignment(.center)
                        .frame(width: 56)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    TextField("項目名（例: 読書、ジョギング…）", text: $newActivityName)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Text("プリセットから選ぶ")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(Color.duoSubtitle)
                        .padding(.horizontal)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(activityPresets) { preset in
                            Button {
                                newActivityEmoji = preset.emoji
                                newActivityName  = preset.name
                            } label: {
                                VStack(spacing: 4) {
                                    Text(preset.emoji).font(.title2)
                                    Text(preset.name).font(.caption2).fontWeight(.bold).foregroundColor(Color.duoDark)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(newActivityName == preset.name ? Color.duoGreen.opacity(0.15) : Color(.systemGray6))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle(activeActivitySlot.map { "\($0.displayName)にカスタム項目を追加" } ?? "カスタム項目を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        newActivityName = ""; newActivityEmoji = "⭐"; activeActivitySlot = nil
                    }.foregroundColor(Color.duoSubtitle)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("追加") {
                        guard let slot = activeActivitySlot, !newActivityName.isEmpty else { return }
                        let activity = CustomActivity(
                            name: newActivityName,
                            emoji: newActivityEmoji.isEmpty ? "⭐" : String(newActivityEmoji.prefix(2))
                        )
                        if var goal = timeSlotManager.settings.goalFor(slot) {
                            goal.customActivities.append(activity)
                            timeSlotManager.settings.updateGoal(goal)
                            Task { await timeSlotManager.saveTodaySettings() }
                        }
                        newActivityName = ""; newActivityEmoji = "⭐"; activeActivitySlot = nil
                    }
                    .foregroundColor(Color.duoGreen).fontWeight(.bold)
                    .disabled(newActivityName.isEmpty)
                }
            }
        }
    }

    // MARK: - セット構成設定

    private var setConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "list.bullet", title: "1セットのメニュー",
                          subtitle: "種目と回数をカスタマイズ")

            Button {
                showSetEditor = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "list.bullet")
                        .font(.title3)
                        .foregroundColor(Color.duoGreen)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("メニューを編集")
                            .font(.subheadline).fontWeight(.bold).foregroundColor(Color.duoDark)
                        Text("\(setConfiguration.exercises.count)種目 登録済み")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                }
                .padding(14)
            }
            .background(Color.white)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        }
    }

    // MARK: - 摂取記録設定

    private var intakeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "fork.knife", title: "摂取記録",
                          subtitle: "食事・水分・コーヒー・アルコール")

            Button {
                showIntakeSettings = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundColor(Color.duoOrange)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("デフォルト設定")
                            .font(.subheadline).fontWeight(.bold).foregroundColor(Color.duoDark)
                        Text("カロリー量やアルコール種類など")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                }
                .padding(14)
            }
            .background(Color.white)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        }
    }

    // MARK: - モーション感度設定

    private var motionSensitivitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "sensor.fill", title: "モーション感度",
                          subtitle: "各種目の検出精度を調整")

            Button {
                showSensitivityEditor = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sensor.fill")
                        .font(.title3)
                        .foregroundColor(Color.duoGreen)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("感度を編集")
                            .font(.subheadline).fontWeight(.bold).foregroundColor(Color.duoDark)
                        Text("iPhone・Apple Watch共通")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                }
                .padding(14)
            }
            .background(Color.white)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        }
    }

    // MARK: - 通知権限バナー

    private var permissionBanner: some View {
        Group {
            switch permStatus {
            case .denied:
                HStack(spacing: 10) {
                    Text("🚫").font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("通知がブロックされています")
                            .font(.subheadline).fontWeight(.black)
                            .foregroundColor(Color(hex: "#7f0000"))
                        Text("設定アプリ → DuoFit → 通知 から許可してください")
                            .font(.caption)
                            .foregroundColor(Color(hex: "#7f0000"))
                    }
                    Spacer()
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("設定へ")
                            .font(.caption).fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.red)
                            .cornerRadius(8)
                    }
                }
                .padding(14)
                .background(Color(hex: "#FCE4EC"))
                .cornerRadius(14)

            case .notDetermined:
                Button {
                    Task {
                        await notif.requestPermission()
                        await refreshPermStatus()
                        if permStatus == .authorized { notif.scheduleAllDaily() }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.badge.fill")
                        Text("通知を有効にする")
                            .fontWeight(.black)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.duoGreen)
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)

            default:
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color.duoGreen)
                    Text("通知が有効です")
                        .font(.subheadline).fontWeight(.black).foregroundColor(Color.duoGreen)
                    Spacer()
                    Button {
                        notif.scheduleAllDaily()
                        notif.savePrefs()
                    } label: {
                        Text("テスト再スケジュール")
                            .font(.caption).fontWeight(.bold)
                            .foregroundColor(Color.duoGreen)
                            .underline()
                    }
                }
                .padding(12)
                .background(Color(hex: "#D7FFB8"))
                .cornerRadius(14)
            }
        }
    }

    // MARK: - LLMセクション

    private var llmSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "brain.head.profile", title: "フォトログAI",
                          subtitle: "写真から栄養素を分析")

            Button { showLLMSettings = true } label: {
                HStack(spacing: 12) {
                    Text("🤖").font(.title3).frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LLM設定")
                            .font(.subheadline).fontWeight(.bold).foregroundColor(Color.duoDark)
                        Text("OpenAI, Anthropic, Google")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color.duoSubtitle)
                }
                .padding(14)
                .background(Color.white)
                .cornerRadius(14)
                .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - リマインダーセクション（ストリークアラートのみ）

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "bell.fill", title: "ストリーク・アラート",
                          subtitle: "連続記録が途絶える前に通知")

            let streakMeta = ReminderMeta(
                id: NotificationManager.ID.streakAlert,
                emoji: "🚨",
                label: "ストリーク・アラート",
                description: "その日の記録がない時に、連続記録が途絶えちゃうよ！とアラート"
            )
            ReminderRow(
                meta: streakMeta,
                config: Binding(
                    get: { notif.prefs[NotificationManager.ID.streakAlert] },
                    set: { notif.prefs[NotificationManager.ID.streakAlert] = $0 }
                )
            )
            .background(Color.white)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        }
    }

    // MARK: - Apple Watch セクション

    private var watchSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "applewatch", title: "Apple Watch",
                          subtitle: "Watch連携の動作設定")

            VStack(spacing: 0) {
                // 自動起動トグル
                HStack(spacing: 12) {
                    Image(systemName: "applewatch.radiowaves.left.and.right")
                        .font(.title3)
                        .foregroundColor(Color.duoGreen)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("自動ワークアウト起動")
                            .font(.subheadline).fontWeight(.bold).foregroundColor(Color.duoDark)
                        Text("iOSアプリを開いたとき、Watchのワークアウトを自動開始")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                            .lineLimit(2)
                    }
                    Spacer()
                    Toggle("", isOn: $watchAutoLaunch)
                        .tint(Color.duoGreen)
                        .labelsHidden()
                }
                .padding(14)

                // 説明バナー
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption).foregroundColor(Color(hex: "#1CB0F6"))
                    Text("Watch側のアプリが起動済みのとき、iOSアプリを開くと同時にワークアウト画面へ自動遷移します")
                        .font(.caption).foregroundColor(Color(hex: "#0a6c96"))
                }
                .padding(.horizontal, 14).padding(.bottom, 12)
            }
            .background(Color.white)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        }
    }

    // MARK: - ハビットスタックセクション

    private var habitStackSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "link.circle.fill", title: "ハビットスタック",
                          subtitle: "既存の日課とトレーニングをセット")

            Button { showHabitStack = true } label: {
                HStack(spacing: 12) {
                    Text("🔗").font(.title3).frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ハビットスタックを管理")
                            .font(.subheadline).fontWeight(.bold).foregroundColor(Color.duoDark)
                        Text("歯磨き・シャワーなどの日課の後に通知")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color.duoSubtitle)
                }
                .padding(14)
                .background(Color.white)
                .cornerRadius(14)
                .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 連動アプリセクション

    private var linkedAppsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "square.stack.3d.up.fill", title: "連動アプリ",
                          subtitle: "他のアプリを開いたときDuoFitを起動")

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("🦉").font(.title3).frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iOSショートカットで自動化")
                            .font(.subheadline).fontWeight(.bold).foregroundColor(Color.duoDark)
                        Text("Duolingoなどを開いたとき、DuoFitも自動起動")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                    Spacer()
                    Button { showShortcutsGuide = true } label: {
                        Text("設定方法")
                            .font(.caption).fontWeight(.bold)
                            .foregroundColor(Color.duoGreen)
                            .underline()
                    }
                }
                .padding(14)
            }
            .background(Color.white)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        }
    }

    // MARK: - 保存ボタン

    private var saveButton: some View {
        Button {
            notif.savePrefs()
            iOSWatchBridge.isWatchAutoLaunchEnabled = watchAutoLaunch

            // 設定を保存
            Task {
                await AuthenticationManager.shared.saveSetConfiguration(setConfiguration)
                for (_, sensitivity) in motionSensitivity {
                    await AuthenticationManager.shared.saveMotionSensitivity(sensitivity)
                }
            }

            if permStatus == .authorized { notif.scheduleAllDaily() }
            withAnimation { savedBanner = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation {
                    savedBanner = false
                    dismiss() // ホーム画面に戻る
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: savedBanner ? "checkmark.circle.fill" : "square.and.arrow.down.fill")
                Text(savedBanner ? "保存しました！" : "設定を保存")
                    .fontWeight(.black)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(savedBanner ? Color(hex: "#46A302") : Color.duoGreen)
            .cornerRadius(14)
            .shadow(color: Color.duoGreen.opacity(0.3), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private func sectionHeader(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(Color.duoGreen)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.subheadline).fontWeight(.black).foregroundColor(Color.duoDark)
                Text(subtitle)
                    .font(.caption2).foregroundColor(Color.duoSubtitle)
            }
        }
        .padding(.bottom, 8)
    }

    private func refreshPermStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permStatus = settings.authorizationStatus
    }
}

// MARK: - ReminderRow

private struct ReminderRow: View {
    let meta: ReminderMeta
    @Binding var config: ReminderConfig
    @State private var time: Date = Date()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(meta.emoji).font(.title3).frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(meta.label)
                        .font(.subheadline).fontWeight(.bold).foregroundColor(Color.duoDark)
                    Text(meta.description)
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                }
                Spacer()
                Toggle("", isOn: $config.enabled)
                    .tint(Color.duoGreen)
                    .labelsHidden()
            }
            .padding(.horizontal, 14).padding(.vertical, 12)

            if config.enabled {
                HStack(spacing: 10) {
                    Image(systemName: "clock")
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                    DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .tint(Color.duoGreen)
                        .onChange(of: time) { newVal in
                            let comps = Calendar.current.dateComponents([.hour, .minute], from: newVal)
                            config.hour   = comps.hour   ?? config.hour
                            config.minute = comps.minute ?? config.minute
                        }
                    Spacer()
                    Text(String(format: "毎日 %02d:%02d", config.hour, config.minute))
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                }
                .padding(.horizontal, 14).padding(.bottom, 12)
                .background(Color(hex: "#F0FFF0"))
            }
        }
        .onAppear {
            // config の hour/minute → Date に変換して DatePicker に渡す
            time = Calendar.current.date(
                bySettingHour: config.hour, minute: config.minute, second: 0, of: Date()
            ) ?? Date()
        }
    }
}

// MARK: - ShortcutsGuideView

private struct ShortcutsGuideView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps = [
        ("iPhoneの「ショートカット」アプリを開く", "app.badge"),
        ("「オートメーション」タブ → 右上の「＋」", "plus.circle"),
        ("「App」を選択 → 連動させたいアプリ（例: Duolingo）を選ぶ", "app.connected.to.app.below.fill"),
        ("「開いたとき」を選択 → 「次へ」", "chevron.right.circle"),
        ("「アクションを追加」→「URLを開く」→ duofit:// を入力", "link"),
        ("「完了」で保存", "checkmark.circle.fill"),
    ]

    var body: some View {
        NavigationView {
            ZStack {
                Color.duoBg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("iOSショートカットで\n他のアプリと連動させる方法")
                            .font(.title3).fontWeight(.black)
                            .foregroundColor(Color.duoDark)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)

                        ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                            HStack(alignment: .top, spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.duoGreen)
                                        .frame(width: 28, height: 28)
                                    Text("\(idx + 1)")
                                        .font(.caption).fontWeight(.black).foregroundColor(.white)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(step.0)
                                        .font(.subheadline).fontWeight(.bold)
                                        .foregroundColor(Color.duoDark)
                                    Image(systemName: step.1)
                                        .font(.caption)
                                        .foregroundColor(Color.duoSubtitle)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                        }

                        Text("設定後はDuolingoを開くとDuoFitが自動的に前面に出てきます")
                            .font(.caption)
                            .foregroundColor(Color.duoSubtitle)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        Spacer(minLength: 40)
                    }
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("ショートカット設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .foregroundColor(Color.duoGreen)
                }
            }
        }
    }
}

// MARK: - SetConfigurationEditorView

struct SetConfigurationEditorView: View {
    @Binding var configuration: SetConfiguration
    @Environment(\.dismiss) private var dismiss
    @State private var editingExercises: [ExerciseInSet]

    init(configuration: Binding<SetConfiguration>) {
        self._configuration = configuration
        self._editingExercises = State(initialValue: configuration.wrappedValue.exercises.sorted { $0.order < $1.order })
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.duoBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle.fill").font(.caption).foregroundColor(Color(hex: "#1CB0F6"))
                            Text("1セットで行う種目と回数を設定します。順番はドラッグで変更できます。").font(.caption).foregroundColor(Color(hex: "#0a6c96"))
                        }.padding(12).background(Color(hex: "#E5F8FF")).cornerRadius(12)
                        VStack(spacing: 12) {
                            ForEach(Array(editingExercises.enumerated()), id: \.element.id) { index, exercise in
                                ExerciseRowEditor(exercise: $editingExercises[index], onDelete: { editingExercises.remove(at: index) })
                            }
                            .onMove { from, to in editingExercises.move(fromOffsets: from, toOffset: to); updateOrder() }
                        }
                        Button { addExercise() } label: {
                            HStack(spacing: 8) { Image(systemName: "plus.circle.fill"); Text("種目を追加").fontWeight(.bold) }
                                .foregroundColor(Color.duoGreen).frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color.duoGreen.opacity(0.1)).cornerRadius(12)
                        }.buttonStyle(.plain)
                        Spacer(minLength: 20)
                    }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 20)
                }
            }
            .navigationTitle("メニュー編集").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("完了") { configuration.exercises = editingExercises; dismiss() }.fontWeight(.bold) }
            }
        }
    }
    private func updateOrder() { for (index, _) in editingExercises.enumerated() { editingExercises[index].order = index } }
    private func addExercise() { editingExercises.append(ExerciseInSet(exerciseId: "pushup", exerciseName: "腕立て伏せ", targetReps: 10, order: editingExercises.count)) }
}

struct ExerciseRowEditor: View {
    @Binding var exercise: ExerciseInSet
    let onDelete: () -> Void
    private let availableExercises = [("pushup","腕立て伏せ","💪"),("squat","スクワット","🏋️"),("situp","腹筋","🔥"),("lunge","ランジ","🦵"),("burpee","バーピー","⚡"),("plank","プランク","🧘")]
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "line.3.horizontal").font(.caption).foregroundColor(Color.duoSubtitle)
                Menu { ForEach(availableExercises, id: \.0) { id, name, emoji in Button { exercise.exerciseId = id; exercise.exerciseName = name } label: { Label("\(emoji) \(name)", systemImage: exercise.exerciseId == id ? "checkmark" : "") } } } label: {
                    HStack(spacing: 6) { if let ex = availableExercises.first(where: { $0.0 == exercise.exerciseId }) { Text(ex.2).font(.title3); Text(ex.1).font(.subheadline).fontWeight(.bold).foregroundColor(Color.duoDark) }; Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundColor(Color.duoSubtitle) }
                }
                Spacer()
                HStack(spacing: 8) {
                    Button { if exercise.targetReps > 5 { exercise.targetReps -= 5 } } label: { Image(systemName: "minus.circle.fill").font(.title3).foregroundColor(exercise.targetReps > 5 ? Color.duoGreen : Color.gray.opacity(0.3)) }.disabled(exercise.targetReps <= 5)
                    Text("\(exercise.targetReps)").font(.title3).fontWeight(.black).foregroundColor(Color.duoDark).frame(width: 40)
                    Button { if exercise.targetReps < 50 { exercise.targetReps += 5 } } label: { Image(systemName: "plus.circle.fill").font(.title3).foregroundColor(exercise.targetReps < 50 ? Color.duoGreen : Color.gray.opacity(0.3)) }.disabled(exercise.targetReps >= 50)
                }
                Button { onDelete() } label: { Image(systemName: "trash").font(.caption).foregroundColor(Color.red.opacity(0.7)) }
            }.padding(14)
        }.background(Color.white).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - MotionSensitivityEditorView

struct MotionSensitivityEditorView: View {
    @Binding var sensitivity: [String: MotionSensitivity]
    @Environment(\.dismiss) private var dismiss
    @State private var editingSensitivity: [String: MotionSensitivity]
    private let exercises = [("pushup","腕立て伏せ","💪"),("squat","スクワット","🏋️"),("situp","腹筋","🔥"),("lunge","ランジ","🦵"),("burpee","バーピー","⚡")]
    init(sensitivity: Binding<[String: MotionSensitivity]>) { self._sensitivity = sensitivity; self._editingSensitivity = State(initialValue: sensitivity.wrappedValue) }
    var body: some View {
        NavigationView {
            ZStack {
                Color.duoBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle.fill").font(.caption).foregroundColor(Color(hex: "#1CB0F6"))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("モーションセンサーの感度を調整します。").font(.caption).foregroundColor(Color(hex: "#0a6c96"))
                                Text("• 感度：低い=大きな動きのみ検出、高い=小さな動きも検出").font(.caption).foregroundColor(Color(hex: "#0a6c96"))
                                Text("• 間隔：短い=速い動きも検出、長い=ゆっくりした動きのみ").font(.caption).foregroundColor(Color(hex: "#0a6c96"))
                            }
                        }.padding(12).background(Color(hex: "#E5F8FF")).cornerRadius(12)
                        ForEach(exercises, id: \.0) { id, name, emoji in if let sens = editingSensitivity[id] { SensitivityRowEditor(exerciseName: "\(emoji) \(name)", sensitivity: Binding(get: { sens }, set: { editingSensitivity[id] = $0 })) } }
                        Button { editingSensitivity = MotionSensitivity.defaultSettings } label: {
                            HStack(spacing: 8) { Image(systemName: "arrow.counterclockwise"); Text("デフォルトに戻す").fontWeight(.bold) }
                                .foregroundColor(Color.duoSubtitle).frame(maxWidth: .infinity).padding(.vertical, 14).background(Color.white).cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.duoSubtitle.opacity(0.3), lineWidth: 1))
                        }.buttonStyle(.plain)
                        Spacer(minLength: 20)
                    }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 20)
                }
            }
            .navigationTitle("感度設定").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("完了") { sensitivity = editingSensitivity; dismiss() }.fontWeight(.bold) }
            }
        }
    }
}

struct SensitivityRowEditor: View {
    let exerciseName: String
    @Binding var sensitivity: MotionSensitivity
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(exerciseName).font(.headline).fontWeight(.bold).foregroundColor(Color.duoDark)
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("感度").font(.subheadline).foregroundColor(Color.duoSubtitle); Spacer(); Text(sensitivityLabel(sensitivity.threshold)).font(.caption).fontWeight(.bold).foregroundColor(Color.duoGreen) }
                HStack(spacing: 8) { Text("低").font(.caption2).foregroundColor(Color.duoSubtitle); Slider(value: $sensitivity.threshold, in: 0.02...0.20, step: 0.02).tint(Color.duoGreen); Text("高").font(.caption2).foregroundColor(Color.duoSubtitle) }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("最小間隔").font(.subheadline).foregroundColor(Color.duoSubtitle); Spacer(); Text(String(format: "%.1f秒", sensitivity.minInterval)).font(.caption).fontWeight(.bold).foregroundColor(Color.duoGreen) }
                HStack(spacing: 8) { Text("短").font(.caption2).foregroundColor(Color.duoSubtitle); Slider(value: $sensitivity.minInterval, in: 0.3...2.0, step: 0.1).tint(Color.duoGreen); Text("長").font(.caption2).foregroundColor(Color.duoSubtitle) }
            }
        }.padding(14).background(Color.white).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }
    private func sensitivityLabel(_ threshold: Double) -> String {
        switch threshold { case 0...0.05: return "最高"; case 0.05...0.08: return "高"; case 0.08...0.12: return "中"; case 0.12...0.16: return "低"; default: return "最低" }
    }
}

#Preview {
    NavigationView { SettingsView() }
}
