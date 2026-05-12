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
                            goals.append(goal)
                        }
                    }
                    settings = DailyTimeSlotSettings(date: today)
                    settings.goals = goals
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
                "reminderEnabled": goal.reminderEnabled
            ]
            if let reminderTime = goal.reminderTime {
                data["reminderTime"] = Timestamp(date: reminderTime)
            }
            return data
        }

        let docData: [String: Any] = [
            "goals": goalsData,
            "date": Timestamp(date: today)
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
                                prog.logProgress.mealLogged = logProgressData["mealLogged"] as? Bool ?? false
                                prog.logProgress.drinkLogged = logProgressData["drinkLogged"] as? Bool ?? false
                                prog.logProgress.mindInputLogged = logProgressData["mindInputLogged"] as? Bool ?? false
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
            } else {
                progress = DailyTimeSlotProgress(date: today)
            }
        } catch {
            print("❌ TimeSlotManager: Failed to load progress: \(error)")
            progress = DailyTimeSlotProgress(date: today)
        }
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
            "date": Timestamp(date: today)
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
            prog.logProgress.mealLogged = true
            prog.lastUpdated = Date()

            // struct全体を再作成してSwiftUIに変更を通知
            var updatedProgress = progress
            updatedProgress.updateProgress(prog)
            progress = updatedProgress

            await saveTodayProgress()
            print("✅ TimeSlot: Meal logged for \(timeSlot.displayName)")
        }
    }

    /// ログ記録（飲み物）
    func recordDrinkLog(at timeSlot: TimeSlot) async {
        if var prog = progress.progressFor(timeSlot) {
            prog.logProgress.drinkLogged = true
            prog.lastUpdated = Date()

            // struct全体を再作成してSwiftUIに変更を通知
            var updatedProgress = progress
            updatedProgress.updateProgress(prog)
            progress = updatedProgress

            await saveTodayProgress()
            print("✅ TimeSlot: Drink logged for \(timeSlot.displayName)")
        }
    }

    /// ログ記録（マインド入力）
    func recordMindInputLog(at timeSlot: TimeSlot) async {
        if var prog = progress.progressFor(timeSlot) {
            prog.logProgress.mindInputLogged = true
            prog.lastUpdated = Date()

            // struct全体を再作成してSwiftUIに変更を通知
            var updatedProgress = progress
            updatedProgress.updateProgress(prog)
            progress = updatedProgress

            await saveTodayProgress()
            print("✅ TimeSlot: Mind input logged for \(timeSlot.displayName)")
        }
    }

    // MARK: - ヘルパー

    private func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
