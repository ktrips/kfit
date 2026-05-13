import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
class TimeSlotManager: ObservableObject {
    static let shared = TimeSlotManager()

    @Published var settings: DailyTimeSlotSettings = DailyTimeSlotSettings()
    @Published var progress: DailyTimeSlotProgress = DailyTimeSlotProgress()
    @Published var isLoading = false

    private let db = Firestore.firestore()

    private init() {}

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
                                logGoal.mealRequired = logGoalData["mealRequired"] as? Bool ?? true
                                logGoal.drinkRequired = logGoalData["drinkRequired"] as? Bool ?? true
                                logGoal.mindInputRequired = logGoalData["mindInputRequired"] as? Bool ?? false
                            }

                            var goal = TimeSlotGoal(timeSlot: timeSlot, trainingGoal: trainingGoal, mindfulnessGoal: mindfulnessGoal, logGoal: logGoal)
                            goal.reminderEnabled = goalData["reminderEnabled"] as? Bool ?? false
                            if let timestamp = goalData["reminderTime"] as? Timestamp {
                                goal.reminderTime = timestamp.dateValue()
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
                    settings = DailyTimeSlotSettings(date: today)
                    settings.goals = goals
                }

                // 1日全体の目標を読み込み
                if let globalGoalsData = data["globalGoals"] as? [String: Any] {
                    var globalGoals = DailyGlobalGoals()
                    globalGoals.workoutEnabled = globalGoalsData["workoutEnabled"] as? Bool ?? false
                    globalGoals.workoutMinutes = globalGoalsData["workoutMinutes"] as? Int ?? 15
                    globalGoals.standEnabled = globalGoalsData["standEnabled"] as? Bool ?? false
                    globalGoals.standHours = globalGoalsData["standHours"] as? Int ?? 12
                    settings.globalGoals = globalGoals
                }
            } else {
                // デフォルト設定を作成
                settings = DailyTimeSlotSettings(date: today)
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
                    "mealRequired": goal.logGoal.mealRequired,
                    "drinkRequired": goal.logGoal.drinkRequired,
                    "mindInputRequired": goal.logGoal.mindInputRequired
                ],
                "reminderEnabled": goal.reminderEnabled,
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

        let docData: [String: Any] = [
            "goals": goalsData,
            "date": Timestamp(date: today),
            "globalGoals": [
                "workoutEnabled": settings.globalGoals.workoutEnabled,
                "workoutMinutes": settings.globalGoals.workoutMinutes,
                "standEnabled": settings.globalGoals.standEnabled,
                "standHours": settings.globalGoals.standHours
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
    func loadTodayProgress() async {
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

                            if let timestamp = progData["lastUpdated"] as? Timestamp {
                                prog.lastUpdated = timestamp.dateValue()
                            }
                            progressList.append(prog)
                        }
                    }
                    progress = DailyTimeSlotProgress(date: today)
                    progress.progress = progressList
                }

                // 1日全体の実績を読み込み
                if let globalProgressData = data["globalProgress"] as? [String: Any] {
                    var globalProgress = DailyGlobalProgress()
                    globalProgress.workoutMinutes = globalProgressData["workoutMinutes"] as? Int ?? 0
                    globalProgress.standHours = globalProgressData["standHours"] as? Int ?? 0
                    if let timestamp = globalProgressData["lastUpdated"] as? Timestamp {
                        globalProgress.lastUpdated = timestamp.dateValue()
                    }
                    progress.globalProgress = globalProgress
                }
            } else {
                progress = DailyTimeSlotProgress(date: today)
            }

            // HealthKitから最新のワークアウトとスタンド時間を取得
            await updateGlobalProgressFromHealthKit()
        } catch {
            print("❌ TimeSlotManager: Failed to load progress: \(error)")
            progress = DailyTimeSlotProgress(date: today)
        }
    }

    /// HealthKitから1日全体の実績を更新
    func updateGlobalProgressFromHealthKit() async {
        let healthKit = HealthKitManager.shared
        guard healthKit.isAuthorized else { return }

        progress.globalProgress.workoutMinutes = await healthKit.fetchTodayWorkout()
        progress.globalProgress.standHours = await healthKit.fetchTodayStand()
        progress.globalProgress.lastUpdated = Date()

        // Firestoreにも保存
        await saveTodayProgress()
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
                "lastUpdated": Timestamp(date: prog.lastUpdated)
            ]
        }

        let docData: [String: Any] = [
            "progress": progressData,
            "date": Timestamp(date: today),
            "globalProgress": [
                "workoutMinutes": progress.globalProgress.workoutMinutes,
                "standHours": progress.globalProgress.standHours,
                "lastUpdated": Timestamp(date: progress.globalProgress.lastUpdated)
            ]
        ]

        do {
            try await db.collection("users").document(userId)
                .collection("time-slot-progress").document(dateStr).setData(docData)
            print("✅ TimeSlotManager: Saved progress for \(dateStr)")
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

            // struct全体を再作成してSwiftUIに変更を通知
            var updatedProgress = progress
            updatedProgress.updateProgress(prog)
            progress = updatedProgress

            await saveTodayProgress()
            print("✅ TimeSlot: Training recorded for \(timeSlot.displayName) - \(prog.trainingCompleted)")
        }
    }

    /// マインドフルネス完了を記録
    func recordMindfulnessCompleted(at timeSlot: TimeSlot) async {
        if var prog = progress.progressFor(timeSlot) {
            prog.mindfulnessCompleted += 1
            prog.lastUpdated = Date()

            // struct全体を再作成してSwiftUIに変更を通知
            var updatedProgress = progress
            updatedProgress.updateProgress(prog)
            progress = updatedProgress

            await saveTodayProgress()
            print("✅ TimeSlot: Mindfulness recorded for \(timeSlot.displayName) - \(prog.mindfulnessCompleted)")
        }
    }

    /// ログ記録（食事）
    func recordMealLog(at timeSlot: TimeSlot) async {
        if var prog = progress.progressFor(timeSlot) {
            prog.logProgress.mealLogged += 1
            prog.lastUpdated = Date()

            // struct全体を再作成してSwiftUIに変更を通知
            var updatedProgress = progress
            updatedProgress.updateProgress(prog)
            progress = updatedProgress

            await saveTodayProgress()
            print("✅ TimeSlot: Meal logged for \(timeSlot.displayName) - Total: \(prog.logProgress.mealLogged)")
        }
    }

    /// ログ記録（飲み物）
    func recordDrinkLog(at timeSlot: TimeSlot) async {
        if var prog = progress.progressFor(timeSlot) {
            prog.logProgress.drinkLogged += 1
            prog.lastUpdated = Date()

            // struct全体を再作成してSwiftUIに変更を通知
            var updatedProgress = progress
            updatedProgress.updateProgress(prog)
            progress = updatedProgress

            await saveTodayProgress()
            print("✅ TimeSlot: Drink logged for \(timeSlot.displayName) - Total: \(prog.logProgress.drinkLogged)")
        }
    }

    /// ログ記録（マインド入力）
    func recordMindInputLog(at timeSlot: TimeSlot) async {
        if var prog = progress.progressFor(timeSlot) {
            prog.logProgress.mindInputLogged += 1
            prog.lastUpdated = Date()

            // struct全体を再作成してSwiftUIに変更を通知
            var updatedProgress = progress
            updatedProgress.updateProgress(prog)
            progress = updatedProgress

            await saveTodayProgress()
            print("✅ TimeSlot: Mind input logged for \(timeSlot.displayName) - Total: \(prog.logProgress.mindInputLogged)")
        }
    }

    // MARK: - ヘルパー

    private func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
