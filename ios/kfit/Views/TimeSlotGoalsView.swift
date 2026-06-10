import SwiftUI

struct TimeSlotGoalsView: View {
    @StateObject private var timeSlotManager = TimeSlotManager.shared
    @StateObject private var notif = NotificationManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var widgetProgressPercent: Int = 0
    @State private var streakPickerTime: Date = Date()
    @State private var goals: [String: TimeSlotGoal] = [:]
    @State private var reminderPickerTimes: [String: Date] = [:]
    @State private var expandingSlot: String? = nil
    @State private var newActivityName: String = ""
    @State private var newActivityEmoji: String = ""

    private let activeSlots: [TimeSlot] = [.morning, .noon, .afternoon, .evening]
    private let standColor = Color(red: 0.0, green: 0.6, blue: 0.85)

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
    let onTapNode: (MandalaNodeData) -> Void

    @State private var appeared = false
    @State private var pulseCenter = false

    // buildNodes() は UserDefaults 読み込みを含む高コスト処理のため、
    // 毎回 computed property で呼ぶと1レンダリングで80回以上実行されてしまう。
    // body で1度だけ計算して全体に渡す設計に変更。
    static func adaptiveNodeSize(count: Int) -> CGFloat {
        switch count {
        case 0...6:   return 52
        case 7...10:  return 46
        case 11...16: return 40
        default:      return 36
        }
    }

    static func minRadius(nodeSize: CGFloat) -> Double { Double(nodeSize) * (42.0 / 36.0) }
    static func nodeSpacing(nodeSize: CGFloat) -> Double { Double(nodeSize) + 10 }

    /// - slotTrainingCounts: 各スロットの実際のセット数（countSetsInTimeSlot結果）。
    ///   nilの場合は prog.trainingCompleted にフォールバック。
    /// - slotMindfulMinutes: 各スロットの実際のマインドフルネス分数（HealthKit+stretch合算）。
    ///   nilの場合は prog.mindfulnessCompleted にフォールバック。
    static func buildNodes(
        settings: DailyTimeSlotSettings,
        progress: DailyTimeSlotProgress,
        activityRingsDone: Bool = false,
        slotTrainingCounts: [String: Int]? = nil,
        slotMindfulMinutes: [String: Int]? = nil,
        dailyCalorieDone: Bool = false,
        dailyWaterDone: Bool = false
    ) -> [MandalaNodeData] {
        var result: [MandalaNodeData] = []

        let fixedGoals: DailyFixedGoals? = {
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
                        isCompleted: actualTrainingCount >= i,
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
                    isCompleted: actualMindfulMinutes >= goal.mindfulnessGoal,
                    slot: slot,
                    type: .mindfulness
                ))
            }
            if goal.standGoal.enabled {
                result.append(MandalaNodeData(
                    id: "\(slot.rawValue)-stand",
                    emoji: "🧍",
                    label: "20分スタンド",
                    isCompleted: prog.standCompleted >= 1,
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
                result.append(MandalaNodeData(
                    id: "\(slot.rawValue)-meal",
                    emoji: mealEmoji,
                    label: mealLabel,
                    isCompleted: dailyCalorieDone || prog.logProgress.mealLogged >= goal.logGoal.mealGoal,
                    slot: slot,
                    type: .meal
                ))
            }
            if foodEnabled && goal.logGoal.drinkGoal > 0 {
                result.append(MandalaNodeData(
                    id: "\(slot.rawValue)-drink",
                    emoji: "💧",
                    label: "水分 \(goal.logGoal.drinkGoal)ml",
                    isCompleted: dailyWaterDone || prog.logProgress.drinkLogged >= goal.logGoal.drinkGoal,
                    slot: slot,
                    type: .drink
                ))
            }
            for activity in goal.customActivities.filter({ $0.isEnabled }) {
                result.append(MandalaNodeData(
                    id: "\(slot.rawValue)-\(activity.id)",
                    emoji: activity.emoji,
                    label: activity.name,
                    isCompleted: completedActivityNames.contains(activity.name) || prog.completedActivityIds.contains(activity.id),
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
        // buildNodes() は高コスト処理（UserDefaults読込）なので body で1度だけ計算し、
        // adaptiveNodeSize / minRadius / nodeSpacing にも同じ値を使いまわす
        let nodes     = Self.buildNodes(settings: settings, progress: progress, activityRingsDone: activityRingsDone, dailyCalorieDone: dailyCalorieDone, dailyWaterDone: dailyWaterDone)
        let nodeSize  = Self.adaptiveNodeSize(count: nodes.count)
        let minR      = Self.minRadius(nodeSize: nodeSize)
        let spacing   = Self.nodeSpacing(nodeSize: nodeSize)
        let allDone   = nodes.filter(\.isCompleted).count
        let allTotal  = nodes.count

        return GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let canvasR = size / 2 - 14
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
                    MandalaNodeButton(
                        node: node,
                        delay: Double(index) * 0.045,
                        appeared: appeared,
                        nodeSize: nodeSize,
                        action: { onTapNode(node) }
                    )
                    .frame(width: nodeSize, height: nodeSize)
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
    var nodeSize: CGFloat = 36
    let action: () -> Void

    private var emojiSize: CGFloat { nodeSize * (15.0 / 36.0) }
    private var glowSize: CGFloat { nodeSize + 14 }

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
                    .font(.system(size: emojiSize))
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
                    .frame(width: glowSize, height: glowSize)
                : nil
        )
    }
}

#Preview {
    NavigationView {
        TimeSlotGoalsView()
    }
}
