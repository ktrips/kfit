import SwiftUI

struct TimeSlotGoalsView: View {
    @StateObject private var timeSlotManager = TimeSlotManager.shared
    @StateObject private var notif = NotificationManager.shared
    @StateObject private var healthKit = HealthKitManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var widgetProgressPercent: Int = 0
    @State private var streakPickerTime: Date = Date()
    @State private var goals: [String: TimeSlotGoal] = [:]
    @State private var reminderPickerTimes: [String: Date] = [:]
    @State private var expandingSlot: String? = nil
    @State private var newActivityName: String = ""
    @State private var newActivityEmoji: String = ""
    @State private var intakeGoals = IntakeSettings.defaultSettings

    private let activeSlots: [TimeSlot] = [.morning, .noon, .afternoon, .evening]
    private let standColor = Color(red: 0.0, green: 0.6, blue: 0.85)

    // HealthKit実施時間ベースで計算したスパイラルノード
    private var precomputedMandalaNodes: [MandalaNodeData] {
        let cal = Calendar.current

        // 時間帯別: マインドフルネス（HK優先、なければFirestore）
        var mindfulMinutes: [String: Int] = [:]
        // 時間帯別: 水分（HK）
        var slotWaterMl: [String: Int] = [:]
        // 時間帯別: カロリー（HK）
        var slotMealKcal: [String: Int] = [:]
        // 時間帯別: トレーニング（Firestoreのスロット別カウント）
        var slotTrainingCounts: [String: Int] = [:]

        for slot in activeSlots {
            let prog = timeSlotManager.progress.progressFor(slot)
            let goal = timeSlotManager.settings.goalFor(slot)

            // トレーニング: Firestoreのスロット別カウント（実施時にスロットへ記録済み）
            slotTrainingCounts[slot.rawValue] = prog?.trainingCompleted ?? 0

            // マインドフルネス: HKセッションをスロット時間帯でフィルタ
            let stretchGoalMin = goal?.stretchGoal.stretchMinutes ?? 3
            let stretchMin = (prog?.stretchSetsCompleted ?? 0) * stretchGoalMin
            let hkMin = healthKit.todayMindfulnessSamples
                .filter { let h = cal.component(.hour, from: $0.startDate)
                          return h >= slot.startHour && h < slot.endHour }
                .reduce(0) { $0 + max(1, Int($1.durationMinutes.rounded())) }
            let firestoreMin = (prog?.mindfulnessCompleted ?? 0)
            mindfulMinutes[slot.rawValue] = (hkMin > 0 ? hkMin : firestoreMin) + stretchMin

            // 水分: HK水分サンプルをスロット時間帯でフィルタ
            slotWaterMl[slot.rawValue] = Int(healthKit.todayWaterSamples
                .filter { let h = cal.component(.hour, from: $0.startDate)
                          return h >= slot.startHour && h < slot.endHour }
                .reduce(0.0) { $0 + $1.value })

            // カロリー: HK食事サンプルをスロット時間帯でフィルタ
            slotMealKcal[slot.rawValue] = Int(healthKit.todayMealSamples
                .filter { let h = cal.component(.hour, from: $0.startDate)
                          return h >= slot.startHour && h < slot.endHour }
                .reduce(0.0) { $0 + $1.value })
        }

        // 1日合計: トレーニング
        let totalTrainingDone = slotTrainingCounts.values.reduce(0, +)
        let totalTrainingGoal = activeSlots.reduce(0) {
            $0 + (timeSlotManager.settings.goalFor($1)?.trainingGoal ?? 0)
        }
        let dailyTrainingDone = totalTrainingGoal > 0 && totalTrainingDone >= totalTrainingGoal

        // 1日合計: マインドフルネス（瞑想のみ目標）
        let totalMindfulDone = mindfulMinutes.values.reduce(0, +)
        let totalMindfulGoal = activeSlots.reduce(0) {
            $0 + (timeSlotManager.settings.goalFor($1)?.mindfulnessGoal ?? 0)
        }
        let dailyMindfulnessDone = totalMindfulGoal > 0 && totalMindfulDone >= totalMindfulGoal

        // 1日合計: 瞑想+ストレッチ+スタンド統合
        let totalMindfulStandGoal = activeSlots.reduce(0) { sum, slot in
            guard let g = timeSlotManager.settings.goalFor(slot) else { return sum }
            let stretchMin = g.stretchGoal.enabled ? g.stretchGoal.stretchMinutes : 0
            let standMin   = g.standGoal.enabled   ? g.standGoal.standMinutes   : 0
            return sum + g.mindfulnessGoal + stretchMin + standMin
        }
        let totalMindfulStandActual = activeSlots.reduce(0) { sum, slot in
            let prog     = timeSlotManager.progress.progressFor(slot)
            let goalInfo = timeSlotManager.settings.goalFor(slot)
            let rawMAS   = mindfulMinutes[slot.rawValue] ?? 0
            guard let goalInfo, goalInfo.standGoal.enabled else { return sum + rawMAS }
            let standGoalMin = goalInfo.standGoal.standMinutes
            let hasHKStand = healthKit.todayMindfulnessSamples
                .filter { let h = Calendar.current.component(.hour, from: $0.startDate)
                          return h >= slot.startHour && h < slot.endHour }
                .contains { max(1, Int($0.durationMinutes.rounded())) >= standGoalMin }
            let firestoreStand = (prog?.standCompleted ?? 0) >= 1
            let standActual = (hasHKStand || firestoreStand) ? standGoalMin : 0
            let mindAndStretch = hasHKStand ? max(0, rawMAS - standGoalMin) : rawMAS
            return sum + mindAndStretch + standActual
        }
        let dailyMindfulAndStandDone = totalMindfulStandGoal > 0
            && totalMindfulStandActual >= totalMindfulStandGoal

        // 1日合計: カロリー・水分
        let dailyCalorieDone = Int(healthKit.todayIntakeCalories) >= intakeGoals.dailyCalorieGoal
        let dailyWaterDone   = Int(healthKit.todayIntakeWater)    >= intakeGoals.dailyWaterGoal

        // アクティビティリング
        let activityRingsDone = healthKit.activityMoveCalories >= healthKit.activityMoveGoal
            && healthKit.activityExerciseMinutes >= healthKit.activityExerciseGoal

        // 今日の Edu 履歴（写真ログ・共有投稿など）
        let eduStart = Calendar.current.startOfDay(for: Date())
        let todayAllEduItems = EduLogManager.shared.history.filter { $0.timestamp >= eduStart }
        // wd-study（曜日別の勉強目標）は語学・勉強系のみを対象にする
        let todayEduCount = todayAllEduItems.filter { item in
            let name = item.activityName
            return name.localizedCaseInsensitiveContains("Duolingo")
                || name == "語学" || name.contains("語学")
                || name == "勉強" || name == "読書"
        }.count
        // スパイラルのカスタム活動照合はカテゴリを限定せず、今日投稿された
        // 全アイテムの activityName と一致すれば完了扱いにする（読書に限らず
        // 瞑想・ストレッチ・コーヒーなど任意のカスタム活動に対応）
        let todayEduActivityNames = Set(todayAllEduItems.map { $0.activityName }).subtracting([""])

        return MandalaChartView.buildNodes(
            settings: timeSlotManager.settings,
            progress: timeSlotManager.progress,
            activityRingsDone: activityRingsDone,
            slotTrainingCounts: slotTrainingCounts,
            slotMindfulMinutes: mindfulMinutes,
            slotWaterMl: slotWaterMl,
            slotMealKcal: slotMealKcal,
            dailyCalorieDone: dailyCalorieDone,
            dailyWaterDone: dailyWaterDone,
            totalDailyCalorieGoal: intakeGoals.dailyCalorieGoal,
            totalDailyWaterGoal: intakeGoals.dailyWaterGoal,
            dailyTrainingDone: dailyTrainingDone,
            dailyMindfulnessDone: dailyMindfulnessDone,
            dailyMindfulAndStandDone: dailyMindfulAndStandDone,
            loggedCompletionIds: MandalaCompletionLogger.shared.todayCompletedIds,
            todayEduItemCount: todayEduCount,
            todayEduActivityNames: todayEduActivityNames
        )
    }

    var body: some View {
        ZStack {
            Color.duoBg.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        if timeSlotManager.isLoading {
                            ProgressView()
                                .tint(Color.duoGreen)
                                .scaleEffect(1.4)
                                .padding(.vertical, 40)
                        } else {
                            ForEach(activeSlots, id: \.self) { slot in
                                timeSlotCard(slot: slot)
                            }
                            mandalaSection(scrollProxy: proxy)
                            streakAlertSection
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }
                .refreshable {
                    await loadAll()
                    await HealthKitManager.shared.fetchGoalHealth(force: true)
                    widgetProgressPercent = UserDefaults(suiteName: "group.com.kfit.app")?.integer(forKey: "progressPercent") ?? 0
                }
            }
        }
        .navigationTitle("時間帯別の目標")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("完了") { dismiss() }
                    .foregroundColor(Color.duoGreen)
                    .fontWeight(.bold)
            }
        }
        .task { await loadAll() }
    }

    // MARK: - Load / Save

    private func loadAll() async {
        await timeSlotManager.loadTodaySettings()
        await timeSlotManager.loadTodayProgress()
        async let loadedIntake = AuthenticationManager.shared.getIntakeSettings()
        async let _ = HealthKitManager.shared.fetchIntakeHealth(force: false)
        intakeGoals = await loadedIntake
        widgetProgressPercent = UserDefaults(suiteName: "group.com.kfit.app")?.integer(forKey: "progressPercent") ?? 0
        for slot in activeSlots {
            goals[slot.rawValue] = timeSlotManager.settings.goalFor(slot) ?? TimeSlotGoal(timeSlot: slot)
        }
        for slot in activeSlots {
            let id = notifId(for: slot)
            let cfg = notif.prefs[id]
            reminderPickerTimes[slot.rawValue] = Calendar.current.date(
                bySettingHour: cfg.hour, minute: cfg.minute, second: 0, of: Date()
            ) ?? Date()
        }
        let sc = notif.prefs[NotificationManager.ID.streakAlert]
        streakPickerTime = Calendar.current.date(
            bySettingHour: sc.hour, minute: sc.minute, second: 0, of: Date()
        ) ?? Date()
    }

    private func notifId(for slot: TimeSlot) -> String {
        switch slot {
        case .morning:   return NotificationManager.ID.amReminder
        case .noon:      return NotificationManager.ID.noonReminder
        case .afternoon: return NotificationManager.ID.afternoonReminder
        case .evening:   return NotificationManager.ID.pmReminder
        default:         return ""
        }
    }

    private func modifyGoal(slot: TimeSlot, update: (inout TimeSlotGoal) -> Void) {
        var g = goals[slot.rawValue] ?? TimeSlotGoal(timeSlot: slot)
        update(&g)
        goals[slot.rawValue] = g
        timeSlotManager.settings.updateGoal(g)
        timeSlotManager.saveGoalTemplate()
        Task { await timeSlotManager.saveTodaySettings() }
    }

    // MARK: - Time Slot Card

    private func timeSlotCard(slot: TimeSlot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // ヘッダー
            HStack(spacing: 10) {
                Text(slot.emoji).font(.title2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(slot.displayName)
                        .font(.headline).fontWeight(.black).foregroundColor(Color.duoDark)
                    Text(slot.timeRange)
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)

            Divider()

            reminderRow(slot: slot)

            Divider()

            counterRow(icon: "💪", label: "トレーニング", color: Color.duoGreen,
                       value: goals[slot.rawValue]?.trainingGoal ?? 1, min: 0, max: 10,
                       onMinus: { modifyGoal(slot: slot) { $0.trainingGoal = max(0, $0.trainingGoal - 1) } },
                       onPlus:  { modifyGoal(slot: slot) { $0.trainingGoal = min(10, $0.trainingGoal + 1) } })

            Divider().padding(.leading, 44)

            counterRow(icon: "🧘", label: "マインドフルネス（分）", color: Color.duoPurple,
                       value: goals[slot.rawValue]?.mindfulnessGoal ?? 1, min: 0, max: 60,
                       onMinus: { modifyGoal(slot: slot) { $0.mindfulnessGoal = max(0, $0.mindfulnessGoal - 1) } },
                       onPlus:  { modifyGoal(slot: slot) { $0.mindfulnessGoal = min(60, $0.mindfulnessGoal + 1) } })

            Divider().padding(.leading, 44)

            standRow(slot: slot)

            Divider()

            customActivitiesSection(slot: slot)
        }
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - Reminder Row

    private func reminderRow(slot: TimeSlot) -> some View {
        let id = notifId(for: slot)
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "bell.fill")
                    .font(.subheadline)
                    .foregroundColor(notif.prefs[id].enabled ? Color.duoOrange : Color(.systemGray3))
                    .frame(width: 28)
                Text("リマインダー")
                    .font(.subheadline).fontWeight(.semibold).foregroundColor(Color.duoDark)
                Spacer()
                if notif.prefs[id].enabled {
                    Text(String(format: "%02d:%02d", notif.prefs[id].hour, notif.prefs[id].minute))
                        .font(.caption).fontWeight(.bold).foregroundColor(Color.duoOrange)
                }
                Toggle("", isOn: Binding(
                    get: { notif.prefs[id].enabled },
                    set: { v in
                        var cfg = notif.prefs[id]
                        cfg.enabled = v
                        notif.prefs[id] = cfg
                        notif.savePrefs()
                        notif.applyOne(id: id)
                    }
                ))
                .tint(Color.duoOrange)
                .labelsHidden()
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            if notif.prefs[id].enabled {
                reminderTimePicker(slot: slot, id: id)
            }
        }
    }

    private func reminderTimePicker(slot: TimeSlot, id: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "clock")
                .font(.caption).foregroundColor(Color.duoSubtitle)
            DatePicker("",
                selection: Binding(
                    get: { reminderPickerTimes[slot.rawValue] ?? Date() },
                    set: { newVal in
                        reminderPickerTimes[slot.rawValue] = newVal
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: newVal)
                        var cfg = notif.prefs[id]
                        cfg.hour   = comps.hour   ?? cfg.hour
                        cfg.minute = comps.minute ?? cfg.minute
                        notif.prefs[id] = cfg
                        notif.savePrefs()
                        notif.applyOne(id: id)
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(Color.duoOrange)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
        .background(Color.duoOrange.opacity(0.05))
    }

    // MARK: - Counter Row

    private func counterRow(icon: String, label: String, color: Color, value: Int, min: Int, max: Int,
                             onMinus: @escaping () -> Void, onPlus: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(icon).font(.title3).frame(width: 28)
            Text(label)
                .font(.subheadline).fontWeight(.semibold).foregroundColor(Color.duoDark)
            Spacer()
            HStack(spacing: 2) {
                Button(action: onMinus) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundColor(value > min ? color : Color(.systemGray4))
                }
                .disabled(value <= min).buttonStyle(.plain)

                Text("\(value)")
                    .font(.title3).fontWeight(.black).foregroundColor(Color.duoDark)
                    .frame(width: 36)

                Button(action: onPlus) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(value < max ? color : Color(.systemGray4))
                }
                .disabled(value >= max).buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: - Stand Row

    private func standRow(slot: TimeSlot) -> some View {
        HStack(spacing: 10) {
            Text("🧍").font(.title3).frame(width: 28)
            Text("20分スタンド")
                .font(.subheadline).fontWeight(.semibold).foregroundColor(Color.duoDark)
            Spacer()
            Toggle("", isOn: Binding(
                get: { goals[slot.rawValue]?.standGoal.enabled ?? false },
                set: { v in modifyGoal(slot: slot) { $0.standGoal.enabled = v } }
            ))
            .tint(standColor).labelsHidden()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: - Custom Activities Section

    private func customActivitiesSection(slot: TimeSlot) -> some View {
        let activities = goals[slot.rawValue]?.customActivities ?? []
        let isExpanding = expandingSlot == slot.rawValue

        return VStack(alignment: .leading, spacing: 0) {
            if !activities.isEmpty {
                ForEach(activities) { activity in
                    HStack(spacing: 10) {
                        Text(activity.emoji).font(.title3).frame(width: 28)
                        Text(activity.name)
                            .font(.subheadline).fontWeight(.semibold).foregroundColor(Color.duoDark)
                        Spacer()
                        Button {
                            modifyGoal(slot: slot) { $0.customActivities.removeAll { $0.id == activity.id } }
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundColor(Color(.systemGray3))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    Divider().padding(.leading, 44)
                }
            }

            if isExpanding {
                let presets: [CustomActivity] = [
                    .duolingo, .reading, .meditation, .stretching,
                    .toothbrushing, .coffee, .study, .webPost,
                ]
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(presets) { preset in
                            Button {
                                newActivityEmoji = preset.emoji
                                newActivityName  = preset.name
                            } label: {
                                HStack(spacing: 4) {
                                    Text(preset.emoji).font(.caption)
                                    Text(preset.name).font(.caption2).fontWeight(.bold)
                                }
                                .foregroundColor(Color.duoDark)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(newActivityName == preset.name ? Color.duoGreen.opacity(0.18) : Color(.systemGray6))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 8)

                HStack(spacing: 8) {
                    TextField("絵", text: $newActivityEmoji)
                        .font(.title3).multilineTextAlignment(.center)
                        .frame(width: 44, height: 36)
                        .background(Color(.systemGray6)).cornerRadius(8)
                    TextField("項目名を入力", text: $newActivityName)
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                        .background(Color(.systemGray6)).cornerRadius(8)
                    Button {
                        let emoji = newActivityEmoji.isEmpty ? "⭐" : String(newActivityEmoji.prefix(2))
                        let name  = newActivityName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        modifyGoal(slot: slot) { $0.customActivities.append(CustomActivity(name: name, emoji: emoji)) }
                        newActivityName  = ""
                        newActivityEmoji = ""
                        expandingSlot = nil
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2).foregroundColor(Color.duoGreen)
                    }
                    .buttonStyle(.plain)
                    .disabled(newActivityName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.duoGreen.opacity(0.04))
            }

            Button {
                if isExpanding {
                    expandingSlot    = nil
                    newActivityName  = ""
                    newActivityEmoji = ""
                } else {
                    expandingSlot    = slot.rawValue
                    newActivityName  = ""
                    newActivityEmoji = ""
                }
            } label: {
                Label(isExpanding ? "キャンセル" : "カスタム項目を追加",
                      systemImage: isExpanding ? "xmark" : "plus")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(isExpanding ? Color.duoSubtitle : Color.duoGreen)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(isExpanding ? Color(.systemGray6).opacity(0.5) : Color.duoGreen.opacity(0.07))
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
        }
    }

    // MARK: - Streak Alert Section

    private var streakAlertSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "bell.fill")
                    .font(.subheadline)
                    .foregroundColor(Color.duoGreen)
                VStack(alignment: .leading, spacing: 0) {
                    Text("ストリーク・アラート")
                        .font(.subheadline).fontWeight(.black).foregroundColor(Color.duoDark)
                    Text("連続記録が途絶える前に通知")
                        .font(.caption2).foregroundColor(Color.duoSubtitle)
                }
            }
            .padding(.bottom, 4)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("🚨").font(.title3).frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ストリーク・アラート")
                            .font(.subheadline).fontWeight(.bold).foregroundColor(Color.duoDark)
                        Text("その日の記録がない時に、連続記録が途絶えちゃうよ！とアラート")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { notif.prefs[NotificationManager.ID.streakAlert].enabled },
                        set: { v in
                            var cfg = notif.prefs[NotificationManager.ID.streakAlert]
                            cfg.enabled = v
                            notif.prefs[NotificationManager.ID.streakAlert] = cfg
                            notif.savePrefs()
                            notif.applyOne(id: NotificationManager.ID.streakAlert)
                        }
                    ))
                    .tint(Color.duoGreen)
                    .labelsHidden()
                }
                .padding(.horizontal, 14).padding(.vertical, 12)

                if notif.prefs[NotificationManager.ID.streakAlert].enabled {
                    HStack(spacing: 10) {
                        Image(systemName: "clock")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                        DatePicker("", selection: $streakPickerTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .tint(Color.duoGreen)
                            .onChange(of: streakPickerTime) { _, newVal in
                                let comps = Calendar.current.dateComponents([.hour, .minute], from: newVal)
                                var cfg = notif.prefs[NotificationManager.ID.streakAlert]
                                cfg.hour   = comps.hour   ?? cfg.hour
                                cfg.minute = comps.minute ?? cfg.minute
                                notif.prefs[NotificationManager.ID.streakAlert] = cfg
                                notif.savePrefs()
                                notif.applyOne(id: NotificationManager.ID.streakAlert)
                            }
                        Spacer()
                        Text(String(format: "毎日 %02d:%02d",
                                    notif.prefs[NotificationManager.ID.streakAlert].hour,
                                    notif.prefs[NotificationManager.ID.streakAlert].minute))
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                    .padding(.horizontal, 14).padding(.bottom, 12)
                    .background(Color(hex: "#F0FFF0"))
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        }
    }

    // MARK: - Mandala Section

    // DateFormatter は生成コストが高いため static で一度だけ生成
    private static let mandalaDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日(E)"
        return f
    }()

    private var mandalaTodayDateText: String {
        Self.mandalaDateFmt.string(from: Date())
    }

    private var mandalaNodeCount: (done: Int, total: Int) {
        var done = 0, total = 0
        let settings = timeSlotManager.settings
        let progress = timeSlotManager.progress
        for slot in [TimeSlot.morning, .noon, .afternoon, .evening] {
            guard let goal = settings.goalFor(slot),
                  let prog = progress.progressFor(slot) else { continue }
            if goal.trainingGoal > 0 { total += 1; if prog.trainingCompleted >= goal.trainingGoal { done += 1 } }
            if goal.mindfulnessGoal > 0 {
                total += 1
                let mindfulMinutes = prog.mindfulnessCompleted * 1 + prog.stretchSetsCompleted * 3
                if mindfulMinutes >= goal.mindfulnessGoal { done += 1 }
            }
            if goal.standGoal.enabled { total += 1; if prog.standCompleted >= 1 { done += 1 } }
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
                Text(widgetProgressPercent > 0 ? "\(widgetProgressPercent)%" : (nc.total > 0 ? "\(nc.done)/\(nc.total)" : "--"))
                    .font(.caption).fontWeight(.black)
                    .foregroundColor(widgetProgressPercent >= 100 || (widgetProgressPercent == 0 && nc.total > 0 && nc.done == nc.total)
                                     ? Color.duoGreen : Color.duoDark)
            }

            MandalaChartView(
                settings: timeSlotManager.settings,
                progress: timeSlotManager.progress,
                precomputedNodes: precomputedMandalaNodes,
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
                .font(.system(size: 10 * UIScale.font, weight: .bold))
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
    case training, mindfulness, stretch, stand, meal, drink, sleep, pfc, custom, weight, activity
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
    var activityRingsDone: Bool = false
    var dailyCalorieDone: Bool = false
    var dailyWaterDone: Bool = false
    /// 外部で事前計算済みのノードを渡す場合はこちらを使う（HealthKit実績反映済み）
    var precomputedNodes: [MandalaNodeData]? = nil
    let onTapNode: (MandalaNodeData) -> Void
    /// スパイラル中心の丸をタップしたときの処理（トレーニング画面起動など）
    var onTapCenter: (() -> Void)? = nil
    /// ImageRenderer によるオフスクリーン画像書き出し用モード。
    /// - .onAppear のフェードインアニメーションを待たずに最初から完全表示状態にする
    /// - ノードを Button ではなく非インタラクティブな View で描画する
    ///   （ImageRenderer は Button でラップされたラベルを描画しないことがあるため）
    var isSnapshotMode: Bool = false

    @State private var appeared = false
    @State private var pulseCenter = false
    @State private var centerTapped = false

    // buildNodes() は UserDefaults 読み込みを含む高コスト処理のため、
    // 毎回 computed property で呼ぶと1レンダリングで80回以上実行されてしまう。
    // body で1度だけ計算して全体に渡す設計に変更。
    static func adaptiveNodeSize(count: Int) -> CGFloat {
        switch count {
        case 0...6:   return 58
        case 7...10:  return 52
        case 11...16: return 46
        default:      return 42
        }
    }

    static func minRadius(nodeSize: CGFloat) -> Double { Double(nodeSize) * (44.0 / 36.0) }
    static func nodeSpacing(nodeSize: CGFloat) -> Double { Double(nodeSize) + 14 }

    /// - slotTrainingCounts: 各スロットの実際のセット数（countSetsInTimeSlot結果）。
    /// EduLog の activityName とスパイラルのカスタム活動名が対応するか判定する。
    /// 完全一致・部分一致・Duolingo↔語学 などのクロスマッチに対応。
    static func eduActivityNameMatchesSpiral(edu: String, spiral: String) -> Bool {
        let e = edu.lowercased().trimmingCharacters(in: .whitespaces)
        let s = spiral.lowercased().trimmingCharacters(in: .whitespaces)
        if e == s { return true }
        if e.contains(s) || s.contains(e) { return true }
        // Duolingo ↔ 語学 / 英語 / 中国語 など
        let isDuolingoEdu = e.contains("duolingo") || e.contains("デュオリンゴ")
        let isSpiralLang  = s == "語学" || s.contains("語学") || s.contains("duolingo")
            || s.contains("英語") || s.contains("中国語") || s.contains("韓国語")
            || s.contains("フランス語") || s.contains("スペイン語")
        if isDuolingoEdu && isSpiralLang { return true }
        return false
    }

    ///   nilの場合は prog.trainingCompleted にフォールバック。
    /// - slotMindfulMinutes: 各スロットの実際のマインドフルネス分数（HealthKit+stretch合算）。
    ///   nilの場合は prog.mindfulnessCompleted にフォールバック。
    static func buildNodes(
        settings: DailyTimeSlotSettings,
        progress: DailyTimeSlotProgress,
        activityRingsDone: Bool = false,
        slotTrainingCounts: [String: Int]? = nil,
        slotMindfulMinutes: [String: Int]? = nil,
        slotWaterMl: [String: Int]? = nil,
        slotMealKcal: [String: Int]? = nil,      // 時間帯別の実際のカロリー摂取量（HealthKit）
        dailyCalorieDone: Bool = false,
        dailyWaterDone: Bool = false,
        totalDailyCalorieGoal: Int = 0,          // 1日合計カロリー目標（1/4判定用）
        totalDailyWaterGoal: Int = 0,            // 1日合計水分目標 ml（1/4判定用）
        dailyTrainingDone: Bool = false,
        dailyMindfulnessDone: Bool = false,
        dailyMindfulAndStandDone: Bool = false,  // 瞑想+ストレッチ+スタンドの統合日次達成
        loggedCompletionIds: Set<String> = [],   // MandalaCompletionLogger からの確定済み完了ID
        fixedGoals fixedGoalsOverride: DailyFixedGoals? = nil,  // 呼び出し側がキャッシュ済みなら渡す（UserDefaults/JSONデコード回避）
        todayEduItemCount: Int = 0,               // 今日の Duolingo / 語学履歴件数
        todayEduActivityNames: Set<String> = []   // 今日の Edu 履歴 activityName 一覧（カスタム活動と照合）
    ) -> [MandalaNodeData] {
        var result: [MandalaNodeData] = []

        let fixedGoals: DailyFixedGoals? = fixedGoalsOverride ?? {
            guard let data = UserDefaults.standard.data(forKey: "dailyFixedGoals_v1"),
                  let fixed = try? JSONDecoder().decode(DailyFixedGoals.self, from: data) else { return nil }
            return fixed
        }()
        let foodEnabled = fixedGoals?.foodEnabled ?? true

        let activeSlots: [TimeSlot] = [.morning, .noon, .afternoon, .evening]
        var completedActivityNames: Set<String> = []
        for slot in activeSlots {
            guard let goal = settings.goalFor(slot), let prog = progress.progressFor(slot) else { continue }
            for activity in goal.customActivities where activity.isEnabled && prog.completedActivityIds.contains(activity.id) {
                completedActivityNames.insert(activity.name)
            }
        }

        for slot in activeSlots {
            guard let goal = settings.goalFor(slot),
                  let prog = progress.progressFor(slot) else { continue }

            // 実際のセット数を優先（countSetsInTimeSlot結果）、なければFirestoreの値
            let actualTrainingCount = slotTrainingCounts?[slot.rawValue] ?? prog.trainingCompleted
            // 実際のマインドフルネス分数を優先、なければFirestoreの値
            let actualMindfulMinutes = slotMindfulMinutes?[slot.rawValue]
                ?? (prog.mindfulnessCompleted * 1 + prog.stretchSetsCompleted * 3)

            if goal.trainingGoal > 0 {
                for i in 1...goal.trainingGoal {
                    result.append(MandalaNodeData(
                        id: "\(slot.rawValue)-training-\(i)",
                        emoji: "💪",
                        label: "トレーニング",
                        isCompleted: dailyTrainingDone || actualTrainingCount >= i,
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
                    isCompleted: dailyMindfulAndStandDone || dailyMindfulnessDone || actualMindfulMinutes >= goal.mindfulnessGoal,
                    slot: slot,
                    type: .mindfulness
                ))
            }
            if goal.standGoal.enabled {
                result.append(MandalaNodeData(
                    id: "\(slot.rawValue)-stand",
                    emoji: "🧍",
                    label: "\(goal.standGoal.standMinutes)分スタンド",
                    isCompleted: dailyMindfulAndStandDone || prog.standCompleted >= 1,
                    slot: slot,
                    type: .stand
                ))
            }
            if foodEnabled && goal.logGoal.mealGoal > 0 {
                let mealEmoji: String = {
                    switch slot {
                    case .midnight:  return "🌙"
                    case .morning:   return "🥐"
                    case .noon:      return "🍱"
                    case .afternoon: return "🍎"
                    case .evening:   return "🍛"
                    }
                }()
                let mealBaseName: String = {
                    switch slot {
                    case .midnight:  return "夜食"
                    case .morning:   return "朝食"
                    case .noon:      return "昼食"
                    case .afternoon: return "午後の食事"
                    case .evening:   return "夕食"
                    }
                }()
                let mealLabel = "\(mealBaseName) \(goal.logGoal.mealGoal)kcal"
                // 時間帯別の実際のカロリー摂取量（HealthKit優先、なければ Firestore）
                let slotActualMealKcal = slotMealKcal?[slot.rawValue] ?? prog.logProgress.mealLogged
                result.append(MandalaNodeData(
                    id: "\(slot.rawValue)-meal",
                    emoji: mealEmoji,
                    label: mealLabel,
                    // その時間帯に食事記録が1件でもあれば完了。
                    // 1日全体のカロリー目標達成済みならすべて完了。
                    isCompleted: dailyCalorieDone || slotActualMealKcal > 0,
                    slot: slot,
                    type: .meal
                ))
            }
            if foodEnabled && goal.logGoal.drinkGoal > 0 {
                // 時間帯別の水分摂取量（ml）を使って達成判定
                let slotActualWaterMl = slotWaterMl?[slot.rawValue] ?? prog.logProgress.drinkLogged
                // 1日合計目標の 1/4 以上摂取していれば、その時間帯は達成
                let waterQuarterGoal = totalDailyWaterGoal > 0 ? totalDailyWaterGoal / 4 : goal.logGoal.drinkGoal
                result.append(MandalaNodeData(
                    id: "\(slot.rawValue)-drink",
                    emoji: "💧",
                    label: "水分",
                    isCompleted: dailyWaterDone || slotActualWaterMl >= waterQuarterGoal,
                    slot: slot,
                    type: .drink
                ))
            }
            for activity in goal.customActivities.filter({ $0.isEnabled }) {
                // EduLog 履歴との名前照合（Duolingo/語学/勉強/読書 などを自動完了）
                let eduDone = todayEduActivityNames.contains { eduName in
                    eduActivityNameMatchesSpiral(edu: eduName, spiral: activity.name)
                }
                result.append(MandalaNodeData(
                    id: "\(slot.rawValue)-\(activity.id)",
                    emoji: activity.emoji,
                    label: activity.name,
                    isCompleted: eduDone
                        || completedActivityNames.contains(activity.name)
                        || prog.completedActivityIds.contains(activity.id),
                    slot: slot,
                    type: .custom
                ))
            }
        }

        // 睡眠ノード（毎日の設定を参照）
        if let fixed = fixedGoals {
            let p = progress.globalProgress
            if fixed.sleepEnabled {
                result.append(MandalaNodeData(
                    id: "global-sleep",
                    emoji: "😴",
                    label: "睡眠",
                    isCompleted: p.sleepHours >= Double(fixed.sleepHoursGoal) || p.sleepScore >= settings.globalGoals.sleepScoreThreshold,
                    slot: nil,
                    type: .sleep
                ))
            }
            if fixed.weightEnabled {
                result.append(MandalaNodeData(
                    id: "global-weight",
                    emoji: "⚖️",
                    label: "体重計測",
                    isCompleted: p.weightMeasured,
                    slot: nil,
                    type: .weight
                ))
            }
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
            if wg.exerciseEnabled {
                result.append(MandalaNodeData(
                    id: "wd-activity",
                    emoji: "🏃",
                    label: "アクティビティ",
                    isCompleted: activityRingsDone,
                    slot: nil,
                    type: .activity
                ))
            }
            if wg.studyEnabled {
                // completedCustomGoalIds に登録済み、または今日の Edu 履歴が1件以上あれば完了
                let studyDone = gp.completedCustomGoalIds.contains("wd_study_\(weekdayNum)")
                    || todayEduItemCount > 0
                result.append(MandalaNodeData(
                    id: "wd-study",
                    emoji: "📚",
                    label: "勉強",
                    isCompleted: studyDone,
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
        if let fixed = fixedGoals {
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

        // ログ済みID（MandalaCompletionLogger）をフォールバックとして補完：
        // 進捗データ未反映でもタップ時刻の記録があれば完了表示する。
        let patched: [MandalaNodeData] = result.map { node in
            guard !node.isCompleted, loggedCompletionIds.contains(node.id) else { return node }
            return MandalaNodeData(
                id: node.id, emoji: node.emoji, label: node.label,
                isCompleted: true, slot: node.slot, type: node.type
            )
        }

        return Array(patched.prefix(40))
    }

    @ViewBuilder
    private func legendCell(label: String, color: Color, done: Int, total: Int) -> some View {
        HStack(spacing: 2) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(total > 0 ? "\(label)(\(done)/\(total))" : label)
                .font(.system(size: 9 * UIScale.font, weight: .semibold))
                .lineLimit(1)
                .foregroundColor(total > 0 && done == total ? color : Color.duoSubtitle)
        }
        .padding(.horizontal, 3).padding(.vertical, 1)
        .background(total > 0 && done == total ? color.opacity(0.12) : Color.clear)
        .cornerRadius(3)
    }

    var body: some View {
        // precomputedNodes が渡されている場合（DashboardView の MandalaSpiralCard）は
        // HealthKit 実績・時間帯別データを反映した事前計算済みノードをそのまま使う。
        // 渡されていない場合は従来通り buildNodes() で計算（TimeSlotGoalsView など）。
        let nodes     = precomputedNodes ?? Self.buildNodes(settings: settings, progress: progress, activityRingsDone: activityRingsDone, dailyCalorieDone: dailyCalorieDone, dailyWaterDone: dailyWaterDone)
        let nodeSize  = Self.adaptiveNodeSize(count: nodes.count)
        let minR      = Self.minRadius(nodeSize: nodeSize)
        let spacing   = Self.nodeSpacing(nodeSize: nodeSize)
        let allDone   = nodes.filter(\.isCompleted).count
        let allTotal  = nodes.count

        return GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let canvasR = size / 2 - 6
                let (positions, nodeAngles) = Self.computePositionsStatic(
                    nodes: nodes, minRadius: minR, nodeSpacing: spacing,
                    center: center, canvasR: canvasR
                )

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
                    Group {
                        if isSnapshotMode {
                            MandalaNodeSnapshotView(node: node, nodeSize: nodeSize)
                        } else {
                            MandalaNodeButton(
                                node: node,
                                delay: Double(index) * 0.045,
                                appeared: appeared,
                                nodeSize: nodeSize,
                                action: { onTapNode(node) }
                            )
                        }
                    }
                    .frame(width: nodeSize, height: nodeSize)
                    .position(pos)
                }

                // 中心プログレス（タップでトレーニング画面を起動）
                centerCircle(nodes: nodes)
                    .scaleEffect(centerTapped ? 0.88 : (pulseCenter ? 1.07 : 1.0))
                    .animation(
                        .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                        value: pulseCenter
                    )
                    .contentShape(Circle())
                    .onTapGesture {
                        guard let onTapCenter else { return }
                        withAnimation(.spring(response: 0.18, dampingFraction: 0.6)) { centerTapped = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            centerTapped = false
                            onTapCenter()
                        }
                    }
                    .position(center)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        }
        .task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            pulseCenter = true
        }
    }

    // MARK: - Spiral helpers

    /// Archimedean spiral with adaptive Δθ: pitch = 2πb = D → guaranteed no cross-arm or consecutive overlap
    /// static 化: minRadius/nodeSpacing を引数で受け取ることで self.nodes の再計算を防ぐ
    static func computePositionsStatic(nodes: [MandalaNodeData], minRadius: Double, nodeSpacing: Double,
                                       center: CGPoint, canvasR: Double) -> (positions: [CGPoint], angles: [Double]) {
        let count = nodes.count
        guard count > 0 else { return ([], []) }
        let D: Double = nodeSpacing
        let b = D / (2 * .pi)
        var positions: [CGPoint] = []
        var angles: [Double] = []
        var angle = -Double.pi / 2
        var r = minRadius
        for _ in 0..<count {
            let cr = min(r, canvasR)
            positions.append(CGPoint(x: center.x + cr * cos(angle), y: center.y + cr * sin(angle)))
            angles.append(angle)
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
                .frame(width: 84, height: 84)
                .shadow(color: .black.opacity(0.12), radius: 6)

            // 外側リング：時間帯別タスク割合（背景トラック）
            Circle()
                .stroke(Color(.systemGray6), lineWidth: 5.5)
                .frame(width: 76, height: 76)

            // 外側リング：時間帯カラーセグメント
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                Circle()
                    .trim(from: seg.start, to: seg.end)
                    .stroke(seg.color, style: StrokeStyle(lineWidth: 5.5, lineCap: .butt))
                    .frame(width: 76, height: 76)
                    .rotationEffect(.degrees(-90))
            }

            // 内側リング：実際の進捗（背景トラック）
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 4)
                .frame(width: 62, height: 62)

            // 内側リング：グリーン進捗
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.duoGreen, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 62, height: 62)
                .rotationEffect(.degrees(-90))

            let pctColor: Color = progress >= 1.0   ? Color(hex: "#4CAF50")
                                : progress >= 0.7   ? Color(hex: "#A5D63B")
                                : progress >= 0.4   ? Color(hex: "#FFD700")
                                : progress >= 0.01  ? Color(hex: "#FF9500")
                                : Color(.systemGray3)
            VStack(spacing: -2) {
                Text("\(Int(progress * 100))")
                    .font(.system(size: 20 * UIScale.font, weight: .black, design: .rounded))
                    .foregroundColor(pctColor)
                Text("%")
                    .font(.system(size: 11 * UIScale.font, weight: .bold, design: .rounded))
                    .foregroundColor(pctColor.opacity(0.7))
            }
        }
    }
}

// MARK: - Mandala Node Face
// ノードの見た目本体（円・絵文字・完了時グロー）。MandalaNodeButton（インタラクティブ）と
// MandalaNodeSnapshotView（ImageRenderer での画像書き出し用・Button 非使用）の両方で共有する。

struct MandalaNodeFace: View {
    let node: MandalaNodeData
    var nodeSize: CGFloat = 36

    private var emojiSize: CGFloat { nodeSize * (21.5 / 36.0) }
    private var glowSize: CGFloat { nodeSize + 14 }

    private var nodeColor: Color {
        node.slot?.mandalaColor ?? Color(hex: "CE82FF")
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(nodeColor.opacity(node.isCompleted ? 0.88 : 0.07))
            Circle()
                .strokeBorder(nodeColor, lineWidth: node.isCompleted ? 2.5 : 1)
                .opacity(node.isCompleted ? 1.0 : 0.22)
            Text(node.emoji)
                .font(.system(size: emojiSize))
                .opacity(node.isCompleted ? 1.0 : 0.55)
        }
        .scaleEffect(node.isCompleted ? 1.1 : 1.0)
        // 完了時の外縁グロー
        .overlay(
            node.isCompleted
                ? Circle()
                    .strokeBorder(nodeColor.opacity(0.55), lineWidth: 3)
                    .frame(width: glowSize, height: glowSize)
                : nil
        )
    }
}

// MARK: - Mandala Node Button

struct MandalaNodeButton: View {
    let node: MandalaNodeData
    let delay: Double
    let appeared: Bool
    var nodeSize: CGFloat = 36
    let action: () -> Void

    @State private var tapped = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.6)) { tapped = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                tapped = false
                action()
            }
        } label: {
            MandalaNodeFace(node: node, nodeSize: nodeSize)
        }
        .buttonStyle(.plain)
        .scaleEffect(tapped ? 0.82 : 1.0)
        .scaleEffect(appeared ? 1.0 : 0.0)
        .opacity(appeared ? 1.0 : 0.0)
        .animation(
            .spring(response: 0.44, dampingFraction: 0.68).delay(delay),
            value: appeared
        )
    }
}

// MARK: - Mandala Node Snapshot View
// ImageRenderer での画像書き出し専用。MandalaNodeButton と見た目は同じだが
// Button でラップしない（ImageRenderer は Button ラベルを描画できないことがあるため）。

struct MandalaNodeSnapshotView: View {
    let node: MandalaNodeData
    var nodeSize: CGFloat = 36

    var body: some View {
        MandalaNodeFace(node: node, nodeSize: nodeSize)
    }
}

#Preview {
    NavigationView {
        TimeSlotGoalsView()
    }
}
