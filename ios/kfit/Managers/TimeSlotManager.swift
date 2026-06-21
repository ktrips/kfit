import Foundation
import FirebaseAuth
import FirebaseFirestore

extension Notification.Name {
    static let timeSlotProgressDidSave = Notification.Name("timeSlotProgressDidSave")
}

@MainActor
class TimeSlotManager: ObservableObject {
    static let shared = TimeSlotManager()

    @Published var settings: DailyTimeSlotSettings = DailyTimeSlotSettings()
    @Published var progress: DailyTimeSlotProgress = DailyTimeSlotProgress()
    @Published var isLoading = false

    private let db = Firestore.firestore()
    // LOW(M-6): 保存デバウンス — 500ms 以内の連続 record* 呼び出しを1回の Firestore 書き込みに集約
    private var pendingSaveTask: Task<Void, Never>?

    private init() {}

    private func debouncedSave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await saveTodayProgress()
        }
    }

    // MARK: - 設定の読み込み

    /// 今日の時間帯別目標設定を取得
    func loadTodaySettings() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }

        let today = Calendar.current.startOfDay(for: Date())
        let dateStr = dateString(from: today)

        do {
            let doc = try await db.collection("users").document(userId)
                .collection("time-slot-goals").document(dateStr).getDocument()

            if doc.exists, let data = doc.data() {
                // Firestoreから読み込み
                if let goalsData = data["goals"] as? [[String: Any]] {
                    var goals: [TimeSlotGoal] = []
                    for goalData in goalsData {
                        if let slotStr = goalData["timeSlot"] as? String,
                           let timeSlot = TimeSlot(rawValue: slotStr),
                           let trainingGoal = goalData["trainingGoal"] as? Int,
                           let mindfulnessGoal = goalData["mindfulnessGoal"] as? Int {

                            var logGoal = LogGoal()
                            if let logGoalData = goalData["logGoal"] as? [String: Any] {
                                if let mg = logGoalData["mealGoal"] as? Int {
                                    // 旧フォーマット（回数=1-10）は400kcalデフォルトに移行
                                    logGoal.mealGoal = mg <= 10 && mg > 0 ? 400 : mg
                                } else {
                                    logGoal.mealGoal = (logGoalData["mealRequired"] as? Bool ?? true) ? 400 : 0
                                }
                                if let dg = logGoalData["drinkGoal"] as? Int {
                                    // 旧フォーマット（回数=1-10）は400mlデフォルトに移行
                                    logGoal.drinkGoal = dg <= 10 && dg > 0 ? 400 : dg
                                } else {
                                    logGoal.drinkGoal = (logGoalData["drinkRequired"] as? Bool ?? true) ? 400 : 0
                                }
                                logGoal.mindInputRequired = logGoalData["mindInputRequired"] as? Bool ?? false
                            }

                            var goal = TimeSlotGoal(timeSlot: timeSlot, trainingGoal: trainingGoal, mindfulnessGoal: mindfulnessGoal, logGoal: logGoal)
                            goal.reminderEnabled = goalData["reminderEnabled"] as? Bool ?? false
                            if let timestamp = goalData["reminderTime"] as? Timestamp {
                                goal.reminderTime = timestamp.dateValue()
                            }

                            // ストレッチ・ヨガ目標を読み込み
                            if let stretchData = goalData["stretchGoal"] as? [String: Any] {
                                goal.stretchGoal.enabled = stretchData["enabled"] as? Bool ?? false
                                goal.stretchGoal.stretchMinutes = stretchData["stretchMinutes"] as? Int
                                    ?? stretchData["stretchCount"] as? Int
                                    ?? stretchData["setsGoal"] as? Int ?? 3
                            }

                            // 20分スタンド目標を読み込み
                            if let standData = goalData["standGoal"] as? [String: Any] {
                                goal.standGoal.enabled = standData["enabled"] as? Bool ?? false
                                goal.standGoal.standMinutes = standData["standMinutes"] as? Int ?? 20
                            }

                            // カスタムアクティビティを読み込み
                            if let activitiesData = goalData["customActivities"] as? [[String: Any]] {
                                var activities: [CustomActivity] = []
                                for actData in activitiesData {
                                    if let id = actData["id"] as? String,
                                       let name = actData["name"] as? String,
                                       let emoji = actData["emoji"] as? String {
                                        let isEnabled = actData["isEnabled"] as? Bool ?? true
                                        activities.append(CustomActivity(id: id, name: name, emoji: emoji, isEnabled: isEnabled))
                                    }
                                }
                                goal.customActivities = activities
                            }

                            goals.append(goal)
                        }
                    }
                    // デフォルト設定（全スロット含む）をベースに、Firestoreのデータでマージ
                    settings = DailyTimeSlotSettings(date: today)
                    for goal in goals {
                        settings.updateGoal(goal)
                    }
                }

                // 1日全体の目標を読み込み
                if let globalGoalsData = data["globalGoals"] as? [String: Any] {
                    var globalGoals = DailyGlobalGoals()
                    globalGoals.activityEnabled = globalGoalsData["activityEnabled"] as? Bool ?? false
                    globalGoals.workoutEnabled = globalGoalsData["workoutEnabled"] as? Bool ?? false
                    globalGoals.workoutMinutes = globalGoalsData["workoutMinutes"] as? Int ?? 15
                    globalGoals.standEnabled = globalGoalsData["standEnabled"] as? Bool ?? false
                    globalGoals.standHours = globalGoalsData["standHours"] as? Int ?? 12
                    globalGoals.sleepEnabled = globalGoalsData["sleepEnabled"] as? Bool ?? false
                    globalGoals.sleepHoursGoal = globalGoalsData["sleepHoursGoal"] as? Int ?? 6
                    globalGoals.sleepScoreThreshold = globalGoalsData["sleepScoreThreshold"] as? Int ?? 80
                    globalGoals.pfcEnabled = globalGoalsData["pfcEnabled"] as? Bool ?? false
                    globalGoals.pfcScoreThreshold = globalGoalsData["pfcScoreThreshold"] as? Int ?? 80
                    globalGoals.mindfulnessEnabled = globalGoalsData["mindfulnessEnabled"] as? Bool ?? true
                    globalGoals.weightEnabled = globalGoalsData["weightEnabled"] as? Bool ?? false
                    globalGoals.mealEnabled = globalGoalsData["mealEnabled"] as? Bool ?? true
                    globalGoals.dailyMealKcal = globalGoalsData["dailyMealKcal"] as? Int ?? 2000
                    globalGoals.drinkEnabled = globalGoalsData["drinkEnabled"] as? Bool ?? true
                    globalGoals.dailyDrinkMl = globalGoalsData["dailyDrinkMl"] as? Int ?? 2000
                    if let customGoalsData = globalGoalsData["customGoals"] as? [[String: Any]] {
                        globalGoals.customGoals = customGoalsData.compactMap { g -> CustomDailyGoal? in
                            guard let id = g["id"] as? String,
                                  let name = g["name"] as? String,
                                  let emoji = g["emoji"] as? String else { return nil }
                            return CustomDailyGoal(id: id, name: name, emoji: emoji,
                                                   isEnabled: g["isEnabled"] as? Bool ?? true)
                        }
                    }
                    settings.globalGoals = globalGoals
                }
                // グローバル食事・水分目標をスロットに反映
                applyGlobalMealDrinkToSlots()
            } else {
                // 新しい日：前回保存したテンプレートから目標を引き継ぐ
                if let template = loadGoalTemplate() {
                    settings = DailyTimeSlotSettings(date: today)
                    for goal in template.goals { settings.updateGoal(goal) }
                    settings.globalGoals = template.globalGoals
                } else {
                    settings = DailyTimeSlotSettings(date: today)
                }
                applyGlobalMealDrinkToSlots()
                await saveTodaySettings()
            }
        } catch {
            print("❌ TimeSlotManager: Failed to load settings: \(error)")
            settings = DailyTimeSlotSettings(date: today)
        }
    }

    /// 今日の設定を保存
    func saveTodaySettings() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let today = Calendar.current.startOfDay(for: Date())
        let dateStr = dateString(from: today)

        let goalsData = settings.goals.map { goal -> [String: Any] in
            var data: [String: Any] = [
                "timeSlot": goal.timeSlot.rawValue,
                "trainingGoal": goal.trainingGoal,
                "mindfulnessGoal": goal.mindfulnessGoal,
                "logGoal": [
                    "mealGoal": goal.logGoal.mealGoal,
                    "drinkGoal": goal.logGoal.drinkGoal,
                    "mindInputRequired": goal.logGoal.mindInputRequired
                ],
                "reminderEnabled": goal.reminderEnabled,
                "stretchGoal": [
                    "enabled": goal.stretchGoal.enabled,
                    "stretchMinutes": goal.stretchGoal.stretchMinutes
                ],
                "standGoal": [
                    "enabled": goal.standGoal.enabled,
                    "standMinutes": goal.standGoal.standMinutes
                ],
                "customActivities": goal.customActivities.map { activity in
                    [
                        "id": activity.id,
                        "name": activity.name,
                        "emoji": activity.emoji,
                        "isEnabled": activity.isEnabled
                    ]
                }
            ]
            if let reminderTime = goal.reminderTime {
                data["reminderTime"] = Timestamp(date: reminderTime)
            }
            return data
        }

        let customGoalsData = settings.globalGoals.customGoals.map { g -> [String: Any] in
            ["id": g.id, "name": g.name, "emoji": g.emoji, "isEnabled": g.isEnabled]
        }

        let docData: [String: Any] = [
            "goals": goalsData,
            "date": Timestamp(date: today),
            "globalGoals": [
                "activityEnabled": settings.globalGoals.activityEnabled,
                "workoutEnabled": settings.globalGoals.workoutEnabled,
                "workoutMinutes": settings.globalGoals.workoutMinutes,
                "standEnabled": settings.globalGoals.standEnabled,
                "standHours": settings.globalGoals.standHours,
                "sleepEnabled": settings.globalGoals.sleepEnabled,
                "sleepHoursGoal": settings.globalGoals.sleepHoursGoal,
                "sleepScoreThreshold": settings.globalGoals.sleepScoreThreshold,
                "pfcEnabled": settings.globalGoals.pfcEnabled,
                "pfcScoreThreshold": settings.globalGoals.pfcScoreThreshold,
                "mindfulnessEnabled": settings.globalGoals.mindfulnessEnabled,
                "weightEnabled": settings.globalGoals.weightEnabled,
                "mealEnabled": settings.globalGoals.mealEnabled,
                "dailyMealKcal": settings.globalGoals.dailyMealKcal,
                "drinkEnabled": settings.globalGoals.drinkEnabled,
                "dailyDrinkMl": settings.globalGoals.dailyDrinkMl,
                "customGoals": customGoalsData
            ]
        ]

        do {
            try await db.collection("users").document(userId)
                .collection("time-slot-goals").document(dateStr).setData(docData)
            print("✅ TimeSlotManager: Saved settings for \(dateStr)")
        } catch {
            print("❌ TimeSlotManager: Failed to save settings: \(error)")
        }
    }

    // MARK: - 実績の読み込み・更新

    /// 今日の時間帯別実績を取得
    func loadTodayProgress(syncHealthKit: Bool = true) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let today = Calendar.current.startOfDay(for: Date())
        let dateStr = dateString(from: today)

        do {
            let doc = try await db.collection("users").document(userId)
                .collection("time-slot-progress").document(dateStr).getDocument()

            if doc.exists, let data = doc.data() {
                if let progressData = data["progress"] as? [[String: Any]] {
                    var progressList: [TimeSlotProgress] = []
                    for progData in progressData {
                        if let slotStr = progData["timeSlot"] as? String,
                           let timeSlot = TimeSlot(rawValue: slotStr) {
                            var prog = TimeSlotProgress(timeSlot: timeSlot)
                            prog.trainingCompleted = progData["trainingCompleted"] as? Int ?? 0
                            prog.mindfulnessCompleted = progData["mindfulnessCompleted"] as? Int ?? 0
                            prog.stretchSetsCompleted = progData["stretchSetsCompleted"] as? Int ?? 0
                            prog.standCompleted = progData["standCompleted"] as? Int ?? 0

                            if let logProgressData = progData["logProgress"] as? [String: Any] {
                                // Bool型との後方互換性のため、BoolとIntの両方をサポート
                                if let mealBool = logProgressData["mealLogged"] as? Bool {
                                    prog.logProgress.mealLogged = mealBool ? 1 : 0
                                } else {
                                    prog.logProgress.mealLogged = logProgressData["mealLogged"] as? Int ?? 0
                                }

                                if let drinkBool = logProgressData["drinkLogged"] as? Bool {
                                    prog.logProgress.drinkLogged = drinkBool ? 1 : 0
                                } else {
                                    prog.logProgress.drinkLogged = logProgressData["drinkLogged"] as? Int ?? 0
                                }

                                if let mindBool = logProgressData["mindInputLogged"] as? Bool {
                                    prog.logProgress.mindInputLogged = mindBool ? 1 : 0
                                } else {
                                    prog.logProgress.mindInputLogged = logProgressData["mindInputLogged"] as? Int ?? 0
                                }
                            }

                            prog.completedActivityIds = Set(progData["completedActivityIds"] as? [String] ?? [])

                            if let timestamp = progData["lastUpdated"] as? Timestamp {
                                prog.lastUpdated = timestamp.dateValue()
                            }
                            progressList.append(prog)
                        }
                    }
                    // デフォルト設定（全スロット含む）をベースにマージ
                    progress = DailyTimeSlotProgress(date: today)
                    for prog in progressList {
                        progress.updateProgress(prog)
                    }
                }

                // 1日全体の実績を読み込み
                if let globalProgressData = data["globalProgress"] as? [String: Any] {
                    var globalProgress = DailyGlobalProgress()
                    globalProgress.workoutMinutes = globalProgressData["workoutMinutes"] as? Int ?? 0
                    globalProgress.standHours = globalProgressData["standHours"] as? Int ?? 0
                    globalProgress.sleepHours = globalProgressData["sleepHours"] as? Double ?? 0.0
                    globalProgress.sleepScore = globalProgressData["sleepScore"] as? Int ?? 0
                    globalProgress.pfcScore = globalProgressData["pfcScore"] as? Int ?? 0
                    globalProgress.weightMeasured = globalProgressData["weightMeasured"] as? Bool ?? false
                    let firestoreIds = globalProgressData["completedCustomGoalIds"] as? [String] ?? []
                    // UserDefaults キャッシュとマージして、Firestore 書き込み中の競合による消失を防ぐ
                    let cachedIds = loadCustomGoalIdsFromCache()
                    globalProgress.completedCustomGoalIds = Array(Set(firestoreIds + cachedIds))
                    if let timestamp = globalProgressData["lastUpdated"] as? Timestamp {
                        globalProgress.lastUpdated = timestamp.dateValue()
                    }
                    progress.globalProgress = globalProgress
                }
            } else {
                progress = DailyTimeSlotProgress(date: today)
            }

            if syncHealthKit {
                await updateGlobalProgressFromHealthKit()
            } else {
                await syncMealProgressFromDietGoal(saveProgress: false)
            }
        } catch {
            print("❌ TimeSlotManager: Failed to load progress: \(error)")
            progress = DailyTimeSlotProgress(date: today)
        }
    }

    /// HealthKitから1日全体の実績を更新
    func updateGlobalProgressFromHealthKit() async {
        let healthKit = HealthKitManager.shared
        guard healthKit.isAuthorized else {
            await syncMealProgressFromDietGoal(saveProgress: false)
            await saveTodayProgress()
            return
        }

        progress.globalProgress.workoutMinutes = healthKit.todayWorkoutMinutes > 0
            ? healthKit.todayWorkoutMinutes
            : await healthKit.fetchTodayWorkout()
        progress.globalProgress.standHours = healthKit.todayStandHours > 0
            ? healthKit.todayStandHours
            : await healthKit.fetchTodayStand()

        // 睡眠データを更新（ユーザー設定の目標時間を渡して同じ数値をカードと今日の状況で共有）
        let sleepAnalysis = healthKit.analyzeSleepScore(targetHours: Double(settings.globalGoals.sleepHoursGoal))
        progress.globalProgress.sleepHours = healthKit.lastNightTotalHours
        progress.globalProgress.sleepScore = sleepAnalysis.score

        // PFCバランススコアを更新
        let pfcAnalysis = healthKit.analyzePFCBalance()
        progress.globalProgress.pfcScore = pfcAnalysis.score

        // 体重計測を確認（今日計測されたデータがあれば達成）
        progress.globalProgress.weightMeasured = healthKit.todayBodyMassMeasurements > 0

        progress.globalProgress.lastUpdated = Date()

        // HealthKitの水分・食事サンプル、またはダイエット目標の自動摂取を時間帯別進捗に反映
        await syncIntakeFromHealthKit()

        // ReflectセッションからストレッチセットをSync
        await syncStretchFromHealthKit()

        // 歯磨きイベントをカスタムアクティビティにSync
        await syncToothbrushingFromHealthKit()

        // Firestoreにも保存
        await saveTodayProgress()
    }

    /// マインドフルネスセッション（種類不問）から1回で目標分数に達したらストレッチとしてSync
    func syncStretchFromHealthKit() async {
        let hk = HealthKitManager.shared
        guard hk.isAuthorized else { return }

        let cal = Calendar.current
        let allSessions = hk.todayMindfulnessSamples
        var changed = false

        // セッションを時間帯別に事前グループ化 — スロット数×セッション数の二重ループを回避
        var sessionsBySlot: [TimeSlot: [MindfulSession]] = [:]
        for session in allSessions {
            let hour = cal.component(.hour, from: session.startDate)
            let slot: TimeSlot
            if hour < 6 { slot = .midnight }
            else if hour < 10 { slot = .morning }
            else if hour < 14 { slot = .noon }
            else if hour < 18 { slot = .afternoon }
            else { slot = .evening }
            sessionsBySlot[slot, default: []].append(session)
        }

        for slot in TimeSlot.allCases where slot != .midnight {
            guard var prog = progress.progressFor(slot),
                  let goal = settings.goalFor(slot),
                  goal.stretchGoal.enabled else { continue }

            let sessions = sessionsBySlot[slot] ?? []
            let maxSingle = sessions.map { $0.durationMinutes }.max() ?? 0.0
            let target = Double(goal.stretchGoal.stretchMinutes)
            let newCompleted = maxSingle >= target ? goal.stretchGoal.stretchMinutes : Int(maxSingle)

            if prog.stretchSetsCompleted != newCompleted {
                prog.stretchSetsCompleted = newCompleted
                prog.lastUpdated = Date()
                var updated = progress
                updated.updateProgress(prog)
                progress = updated
                changed = true
            }
        }

        if changed {
            print("[TimeSlot] 🤸 Synced stretch from single mindfulness session")
        }
    }

    /// HealthKitの歯磨きイベントを、対応する時間帯の「歯磨き・フロス」カスタムアクティビティに反映
    func syncToothbrushingFromHealthKit() async {
        let hk = HealthKitManager.shared
        guard hk.isAuthorized else { return }

        let toothbrushingDates = hk.todayToothbrushingSamples
        guard !toothbrushingDates.isEmpty else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var changed = false

        for slot in TimeSlot.allCases {
            guard var prog = progress.progressFor(slot),
                  let goal = settings.goalFor(slot) else { continue }

            let slotStart = cal.date(bySettingHour: slot.startHour, minute: 0, second: 0, of: today) ?? today
            let slotEnd: Date = slot.endHour >= 24
                ? (cal.date(byAdding: .day, value: 1, to: today) ?? today)
                : (cal.date(bySettingHour: slot.endHour, minute: 0, second: 0, of: today) ?? today)

            let hasEvent = toothbrushingDates.contains { $0 >= slotStart && $0 < slotEnd }
            guard hasEvent else { continue }

            var slotChanged = false
            for activity in goal.customActivities where activity.isEnabled && activity.name.contains("歯磨き") {
                if !prog.completedActivityIds.contains(activity.id) {
                    prog.completedActivityIds.insert(activity.id)
                    slotChanged = true
                }
            }
            if slotChanged {
                var updated = progress
                updated.updateProgress(prog)
                progress = updated
                changed = true
            }
        }

        if changed {
            await saveTodayProgress()
            print("[TimeSlot] 🦷 Synced toothbrushing from HealthKit")
        }
    }

    /// HealthKitの水分・食事サンプルを時間帯別進捗に反映
    func syncIntakeFromHealthKit() async {
        let hk = HealthKitManager.shared
        guard hk.isAuthorized else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        syncMealGoalFromDietGoal()
        let useHealthKitForMeal = DietGoalManager.shared.settings.useHealthKitForIntake
        if useHealthKitForMeal {
            await hk.fetchIntakeHealth()
        }

        // サンプルを時間帯別に事前グループ化 — O(n×m) フィルタを O(n+m) に改善
        let slotBounds: [(TimeSlot, Date, Date)] = TimeSlot.allCases.map { slot in
            let start = cal.date(bySettingHour: slot.startHour, minute: 0, second: 0, of: today) ?? today
            let end: Date = slot.endHour >= 24
                ? (cal.date(byAdding: .day, value: 1, to: today) ?? today)
                : (cal.date(bySettingHour: slot.endHour, minute: 0, second: 0, of: today) ?? today)
            return (slot, start, end)
        }

        var waterBySlot: [TimeSlot: Double] = [:]
        for sample in hk.todayWaterSamples {
            if let (slot, _, _) = slotBounds.first(where: { sample.startDate >= $1 && sample.startDate < $2 }) {
                waterBySlot[slot, default: 0] += sample.value
            }
        }
        var mealBySlot: [TimeSlot: Double] = [:]
        if useHealthKitForMeal {
            for sample in hk.todayMealSamples {
                if let (slot, _, _) = slotBounds.first(where: { sample.startDate >= $1 && sample.startDate < $2 }) {
                    mealBySlot[slot, default: 0] += sample.value
                }
            }
        }

        var changed = false
        let now = Date()

        for slot in TimeSlot.allCases {
            guard var prog = progress.progressFor(slot) else { continue }

            let newDrink = max(prog.logProgress.drinkLogged, Int(waterBySlot[slot] ?? 0))
            let newMeal = useHealthKitForMeal
                ? Int(mealBySlot[slot] ?? 0)
                : prog.logProgress.mealLogged

            if prog.logProgress.drinkLogged != newDrink || prog.logProgress.mealLogged != newMeal {
                prog.logProgress.drinkLogged = newDrink
                prog.logProgress.mealLogged  = newMeal
                prog.lastUpdated = now
                var updated = progress
                updated.updateProgress(prog)
                progress = updated
                changed = true
            }
        }

        if changed {
            print("[TimeSlot] 💧🍽️ Synced water/meal intake from HealthKit to time slots")
        }
    }

    /// ダイエット目標の摂取カロリー設定を時間帯目標へ反映
    func syncMealGoalFromDietGoal() {
        let dietSettings = DietGoalManager.shared.settings
        settings.globalGoals.mealEnabled = true
        settings.globalGoals.dailyMealKcal = dietSettings.dailyIntakeGoal
        applyGlobalMealDrinkToSlots()
    }

    /// Apple Healthを使わない場合は、到達済み時間帯の食事カロリーを自動実績として反映
    func syncMealProgressFromDietGoal(saveProgress: Bool = true) async {
        syncMealGoalFromDietGoal()
        if DietGoalManager.shared.settings.useHealthKitForIntake {
            await syncIntakeFromHealthKit()
            if saveProgress {
                await saveTodayProgress()
            }
            return
        }

        // Non-HealthKit path: meal progress is set only via explicit recordMealLog() calls.
        // Do not auto-complete based on time.
    }

    /// 今日の実績を保存
    func saveTodayProgress() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let today = Calendar.current.startOfDay(for: Date())
        let dateStr = dateString(from: today)

        let progressData = progress.progress.map { prog -> [String: Any] in
            [
                "timeSlot": prog.timeSlot.rawValue,
                "trainingCompleted": prog.trainingCompleted,
                "mindfulnessCompleted": prog.mindfulnessCompleted,
                "logProgress": [
                    "mealLogged": prog.logProgress.mealLogged,
                    "drinkLogged": prog.logProgress.drinkLogged,
                    "mindInputLogged": prog.logProgress.mindInputLogged
                ],
                "stretchSetsCompleted": prog.stretchSetsCompleted,
                "standCompleted": prog.standCompleted,
                "completedActivityIds": Array(prog.completedActivityIds),
                "lastUpdated": Timestamp(date: prog.lastUpdated)
            ]
        }

        let docData: [String: Any] = [
            "progress": progressData,
            "date": Timestamp(date: today),
            "globalProgress": [
                "workoutMinutes": progress.globalProgress.workoutMinutes,
                "standHours": progress.globalProgress.standHours,
                "sleepHours": progress.globalProgress.sleepHours,
                "sleepScore": progress.globalProgress.sleepScore,
                "pfcScore": progress.globalProgress.pfcScore,
                "weightMeasured": progress.globalProgress.weightMeasured,
                "completedCustomGoalIds": progress.globalProgress.completedCustomGoalIds,
                "lastUpdated": Timestamp(date: progress.globalProgress.lastUpdated)
            ]
        ]

        do {
            try await db.collection("users").document(userId)
                .collection("time-slot-progress").document(dateStr).setData(docData)
            print("✅ TimeSlotManager: Saved progress for \(dateStr)")
            // DashboardViewにUserDefaults更新を依頼してからウィジェットをリロードさせる
            NotificationCenter.default.post(name: .timeSlotProgressDidSave, object: nil)
        } catch {
            print("❌ TimeSlotManager: Failed to save progress: \(error)")
        }
    }

    // MARK: - 実績更新ヘルパー

    /// トレーニング完了を記録
    func recordTrainingCompleted(at timeSlot: TimeSlot) async {
        if var prog = progress.progressFor(timeSlot) {
            prog.trainingCompleted += 1
            prog.lastUpdated = Date()
            var updatedProgress = progress
            updatedProgress.updateProgress(prog)
            progress = updatedProgress
            debouncedSave()  // LOW(M-6): デバウンス保存
            print("✅ TimeSlot: Training recorded for \(timeSlot.displayName) - \(prog.trainingCompleted)")
        }
    }

    /// マインドフルネス完了を記録
    func recordMindfulnessCompleted(at timeSlot: TimeSlot) async {
        if var prog = progress.progressFor(timeSlot) {
            prog.mindfulnessCompleted += 1
            prog.lastUpdated = Date()
            var updatedProgress = progress
            updatedProgress.updateProgress(prog)
            progress = updatedProgress
            debouncedSave()  // LOW(M-6): デバウンス保存
            print("✅ TimeSlot: Mindfulness recorded for \(timeSlot.displayName) - \(prog.mindfulnessCompleted)")
        }
    }

    /// 20分スタンド完了を記録（タイマー完了 or Watchの連続スタンド検知時）
    func recordStandCompleted(at timeSlot: TimeSlot) async {
        if var prog = progress.progressFor(timeSlot) {
            guard prog.standCompleted < 1 else { return }
            prog.standCompleted = 1
            prog.lastUpdated = Date()
            var updatedProgress = progress
            updatedProgress.updateProgress(prog)
            progress = updatedProgress
            debouncedSave()  // LOW(M-6): デバウンス保存
            print("✅ TimeSlot: Stand recorded for \(timeSlot.displayName)")
        }
    }

    /// ログ記録（食事）
    func recordMealLog(at timeSlot: TimeSlot, calories: Int = 400) async {
        if var prog = progress.progressFor(timeSlot) {
            prog.logProgress.mealLogged += calories
            prog.lastUpdated = Date()
            var updatedProgress = progress
            updatedProgress.updateProgress(prog)
            progress = updatedProgress
            debouncedSave()  // LOW(M-6): デバウンス保存
            print("✅ TimeSlot: Meal logged for \(timeSlot.displayName) - Total: \(prog.logProgress.mealLogged)")
        }
    }

    /// ログ記録（飲み物）
    func recordDrinkLog(at timeSlot: TimeSlot, ml: Int = 200) async {
        if var prog = progress.progressFor(timeSlot) {
            prog.logProgress.drinkLogged += ml
            prog.lastUpdated = Date()
            var updatedProgress = progress
            updatedProgress.updateProgress(prog)
            progress = updatedProgress
            debouncedSave()  // LOW(M-6): デバウンス保存
            print("✅ TimeSlot: Drink logged for \(timeSlot.displayName) - Total: \(prog.logProgress.drinkLogged)")
        }
    }

    /// ログ記録（マインド入力）
    func recordMindInputLog(at timeSlot: TimeSlot) async {
        if var prog = progress.progressFor(timeSlot) {
            prog.logProgress.mindInputLogged += 1
            prog.lastUpdated = Date()
            var updatedProgress = progress
            updatedProgress.updateProgress(prog)
            progress = updatedProgress
            debouncedSave()  // LOW(M-6): デバウンス保存
            print("✅ TimeSlot: Mind input logged for \(timeSlot.displayName) - Total: \(prog.logProgress.mindInputLogged)")
        }
    }

    // MARK: - カスタム目標のトグル

    /// カスタム目標達成状態の UserDefaults キャッシュキー（日付別）
    private func customGoalCacheKey() -> String {
        let dateStr = dateString(from: Calendar.current.startOfDay(for: Date()))
        return "completedCustomGoalIds_v1_\(dateStr)"
    }

    /// カスタム目標IDリストを UserDefaults にも即時保存
    private func saveCustomGoalIdsToCache(_ ids: [String]) {
        UserDefaults.standard.set(ids, forKey: customGoalCacheKey())
    }

    /// UserDefaults キャッシュからカスタム目標IDリストを読み込む
    private func loadCustomGoalIdsFromCache() -> [String] {
        UserDefaults.standard.stringArray(forKey: customGoalCacheKey()) ?? []
    }

    /// カスタム目標の達成状態をトグル
    func toggleCustomGoal(id: String) async {
        var updatedProgress = progress
        if updatedProgress.globalProgress.completedCustomGoalIds.contains(id) {
            updatedProgress.globalProgress.completedCustomGoalIds.removeAll { $0 == id }
        } else {
            updatedProgress.globalProgress.completedCustomGoalIds.append(id)
        }
        updatedProgress.globalProgress.lastUpdated = Date()
        progress = updatedProgress
        // UserDefaults に即時保存（Firestore 書き込み中の競合を防ぐ）
        saveCustomGoalIdsToCache(progress.globalProgress.completedCustomGoalIds)
        await saveTodayProgress()
    }

    /// 時間帯別カスタム活動の達成状態をトグル
    func toggleCustomActivity(id: String, at timeSlot: TimeSlot) async {
        if var prog = progress.progressFor(timeSlot) {
            let wasCompleted = prog.completedActivityIds.contains(id)
            if wasCompleted {
                prog.completedActivityIds.remove(id)
            } else {
                prog.completedActivityIds.insert(id)
                // 歯磨き・フロスをHealthKitに記録
                let activityName = settings.goalFor(timeSlot)?.customActivities.first { $0.id == id }?.name ?? ""
                if activityName.contains("歯磨き") {
                    await HealthKitManager.shared.saveToothbrushing(durationSeconds: 60, timestamp: Date())
                }
            }
            prog.lastUpdated = Date()
            var updatedProgress = progress
            updatedProgress.updateProgress(prog)
            progress = updatedProgress
            await saveTodayProgress()
            print("✅ TimeSlot: CustomActivity \(id) toggled for \(timeSlot.displayName)")
        }
    }

    // MARK: - グローバル食事・水分目標をスロットに反映

    func applyGlobalMealDrinkToSlots() {
        let drinkPerSlot = settings.globalGoals.drinkEnabled ? settings.globalGoals.dailyDrinkMl / 4 : 0

        for slot in TimeSlot.allCases {
            if var goal = settings.goalFor(slot) {
                goal.logGoal.mealGoal = mealGoal(for: slot)
                goal.logGoal.drinkGoal = slot == .midnight ? 0 : drinkPerSlot
                settings.updateGoal(goal)
            }
        }
    }

    // MARK: - 食事カロリー配分（IntakeSettings連動）

    private static let mealDistKey = "kfit_meal_distribution_v2"

    /// IntakeSettings の食事カロリーを配分として保存
    static func updateMealDistribution(breakfast: Int, lunch: Int, snack: Int, dinner: Int) {
        UserDefaults.standard.set([breakfast, lunch, snack, dinner], forKey: mealDistKey)
    }

    private static func loadMealDistribution() -> (b: Int, l: Int, s: Int, d: Int) {
        if let arr = UserDefaults.standard.array(forKey: mealDistKey) as? [Int], arr.count == 4 {
            return (arr[0], arr[1], arr[2], arr[3])
        }
        return (400, 600, 200, 800)
    }

    private func mealGoal(for slot: TimeSlot) -> Int {
        guard settings.globalGoals.mealEnabled else { return 0 }
        let total = settings.globalGoals.dailyMealKcal
        let dist = TimeSlotManager.loadMealDistribution()
        let baseTotal = dist.b + dist.l + dist.s + dist.d
        guard baseTotal > 0 else { return 0 }
        let morning   = Int(Double(total) * Double(dist.b) / Double(baseTotal))
        let noon      = Int(Double(total) * Double(dist.l) / Double(baseTotal))
        let afternoon = Int(Double(total) * Double(dist.s) / Double(baseTotal))
        switch slot {
        case .midnight:  return 0
        case .morning:   return morning
        case .noon:      return noon
        case .afternoon: return afternoon
        case .evening:   return total - morning - noon - afternoon
        }
    }

    private func scheduledMealLogged(for slot: TimeSlot, now: Date) -> Int {
        guard slot != .midnight else { return 0 }
        let today = Calendar.current.startOfDay(for: now)
        let slotStart = Calendar.current.date(bySettingHour: slot.startHour, minute: 0, second: 0, of: today) ?? today
        return now >= slotStart ? mealGoal(for: slot) : 0
    }

    // MARK: - 目標テンプレート（日付をまたいで設定を引き継ぐ）

    private static let goalTemplateKey = "kfit_timeslot_goals_template_v1"

    /// 現在の目標設定をUserDefaultsにテンプレートとして保存
    func saveGoalTemplate() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: TimeSlotManager.goalTemplateKey)
        }
    }

    private func loadGoalTemplate() -> DailyTimeSlotSettings? {
        guard let data = UserDefaults.standard.data(forKey: TimeSlotManager.goalTemplateKey),
              let s = try? JSONDecoder().decode(DailyTimeSlotSettings.self, from: data)
        else { return nil }
        return s
    }

    // MARK: - ヘルパー

    private func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Mandala Completion Logger

/// スパイラルアイコンの完了をアイコンID＋時刻で確実に記録・保存するロガー。
/// UserDefaults に日付別 JSON として永続化し、アプリ再起動後も表示に反映する。
struct MandalaCompletionRecord: Codable, Identifiable {
    var id: String = UUID().uuidString
    var nodeId: String
    var nodeEmoji: String
    var nodeName: String
    var completedAt: Date
    var slotName: String?   // "morning" / "noon" / "afternoon" / "evening" / nil(global)
}

@MainActor
class MandalaCompletionLogger: ObservableObject {
    static let shared = MandalaCompletionLogger()

    @Published private(set) var todayRecords: [MandalaCompletionRecord] = []

    private var allRecords: [String: [MandalaCompletionRecord]] = [:]
    private let storageKey = "mandalaCompletionLog_v1"

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private init() { load() }

    // MARK: - Public API

    /// ノード完了を記録する（同一nodeIdの既存エントリは上書き）。
    func record(nodeId: String, emoji: String, name: String, slot: String?) {
        let key = todayKey()
        let record = MandalaCompletionRecord(
            nodeId: nodeId, nodeEmoji: emoji, nodeName: name,
            completedAt: Date(), slotName: slot
        )
        if allRecords[key] == nil { allRecords[key] = [] }
        allRecords[key]?.removeAll { $0.nodeId == nodeId }
        allRecords[key]?.append(record)
        todayRecords = allRecords[key] ?? []
        persist()
    }

    /// ノード完了を取り消す（トグル時）。
    func remove(nodeId: String) {
        let key = todayKey()
        allRecords[key]?.removeAll { $0.nodeId == nodeId }
        todayRecords = allRecords[key] ?? []
        persist()
    }

    /// 今日完了済みのノードIDセット（buildNodes に渡す）。
    var todayCompletedIds: Set<String> {
        Set(todayRecords.map { $0.nodeId })
    }

    /// 指定日の完了記録（全件）。
    func records(for date: Date) -> [MandalaCompletionRecord] {
        allRecords[Self.df.string(from: date)] ?? []
    }

    // MARK: - Persistence

    private func todayKey() -> String { Self.df.string(from: Date()) }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(allRecords) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([String: [MandalaCompletionRecord]].self, from: data) {
            allRecords = decoded
            todayRecords = allRecords[todayKey()] ?? []
        }
    }
}
