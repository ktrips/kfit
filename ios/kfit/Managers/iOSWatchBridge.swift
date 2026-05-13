import WatchConnectivity
import Foundation

/// Apple Watch → iPhone へのワークアウトデータ受信ブリッジ
///
/// Watch でトレーニングを記録すると WatchConnectivity 経由で通知が来る。
/// 受信後に NotificationManager.handleWorkoutRecorded() を呼び出すことで、
/// Watch 側で記録しても iPhone・Watch の通知キャンセルが機能する。
@MainActor
final class iOSWatchBridge: NSObject, WCSessionDelegate {
    static let shared = iOSWatchBridge()

    // パフォーマンス最適化: デバウンス
    private var lastStatsSendTime: Date?
    private let statsDebounceInterval: TimeInterval = 2.0 // 2秒以内の重複送信を防ぐ

    private override init() {
        super.init()
        activate()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Watch 自動起動の UserDefaults キー（SettingsView と共有）
    static let watchAutoLaunchKey = "duofit.watchAutoLaunch"

    /// Watch 自動起動が有効かどうか（デフォルト: true）
    static var isWatchAutoLaunchEnabled: Bool {
        get {
            let stored = UserDefaults.standard.object(forKey: watchAutoLaunchKey)
            return stored == nil ? true : UserDefaults.standard.bool(forKey: watchAutoLaunchKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: watchAutoLaunchKey) }
    }

    /// iOSアプリ起動時に Watch へ「ワークアウト開始」シグナルを送る
    ///
    /// Watch アプリが前面にある場合は sendMessage でリアルタイム起動。
    /// バックグラウンド・未起動の場合は updateApplicationContext で
    /// 「次に Watch アプリを開いたとき自動開始」にフォールバックする。
    /// ユーザーが設定で無効にしている場合は何もしない。
    func sendStartWorkoutSignal() {
        guard Self.isWatchAutoLaunchEnabled else {
            print("[iOSWatchBridge] Watch自動起動はユーザーによって無効化されています")
            return
        }
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        let payload: [String: Any] = ["action": "start_workout", "ts": Date().timeIntervalSince1970]

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                print("[iOSWatchBridge] sendMessage error: \(error)")
            }
        } else {
            // Watch が非到達 → Application Context に保存（Watch 次回起動時に読まれる）
            try? session.updateApplicationContext(payload)
        }
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error { print("[iOSWatchBridge] activation error: \(error)") }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    // Watch からワークアウトデータを受信
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            // ① 種目ごとのデータ（通知キャンセル用）
            if let workoutData = message["workout"] as? Data,
               let workout = try? JSONDecoder().decode(WatchWorkoutData.self, from: workoutData) {
                print("[iOSWatchBridge] 種目受信: \(workout.exerciseName) \(workout.reps)rep")
                await AuthenticationManager.shared.recordWatchWorkout(workout)
                return
            }

            // ② セット完了（全種目まとめて）
            if let setData = message["completed_set"] as? Data,
               let set = try? JSONDecoder().decode(WatchSetData.self, from: setData) {
                print("[iOSWatchBridge] セット完了受信: \(set.totalReps)rep / \(set.totalXP)XP")
                let stats = await AuthenticationManager.shared.recordWatchCompletedSet(set)
                let todayExercises = await AuthenticationManager.shared.getTodayExercises()
                sendStatsToWatch(streak: stats.streak, todayReps: stats.todayReps, todayXP: stats.todayXP, todayExercises: todayExercises)
                return
            }

            // ③ stats リクエスト（Watch 起動時）
            if (message["action"] as? String) == "request_stats" {
                let profile = AuthenticationManager.shared.userProfile
                // 今日の運動データを取得（非同期）
                Task {
                    let todayExercises = await AuthenticationManager.shared.getTodayExercises()
                    let todayReps = todayExercises.reduce(0) { $0 + $1.reps }
                    let todayXP = todayExercises.reduce(0) { $0 + $1.points }
                    self.sendStatsToWatch(
                        streak:    profile?.streak ?? 0,
                        todayReps: todayReps,
                        todayXP:   todayXP,
                        todayExercises: todayExercises
                    )
                }
                return
            }

            // ④ 摂取記録（Watch からの記録）
            if (message["action"] as? String) == "record_intake" {
                let type = message["type"] as? String ?? ""
                let subtype = message["subtype"] as? String

                Task {
                    let timestamp = Date()
                    let calendar = Calendar.current
                    let hour = calendar.component(.hour, from: timestamp)
                    let timeSlot: TimeSlot

                    if hour >= 6 && hour < 10 { timeSlot = .morning }
                    else if hour >= 10 && hour < 14 { timeSlot = .noon }
                    else if hour >= 14 && hour < 18 { timeSlot = .afternoon }
                    else { timeSlot = .evening }

                    switch type {
                    case "meal":
                        if let mealTypeStr = subtype {
                            if let mealType = MealType(rawValue: mealTypeStr) {
                                await AuthenticationManager.shared.recordMeal(mealType: mealType)
                                await TimeSlotManager.shared.recordMealLog(at: timeSlot)
                                print("[iOSWatchBridge] ✅ 食事記録完了: \(mealType.rawValue) at \(timeSlot.displayName)")
                            }
                        }
                    case "water", "coffee", "alcohol":
                        if type == "water" {
                            await AuthenticationManager.shared.recordWater()
                        } else if type == "coffee" {
                            await AuthenticationManager.shared.recordCoffee()
                        } else if let alcoholTypeStr = subtype {
                            if let alcoholType = AlcoholType(rawValue: alcoholTypeStr) {
                                await AuthenticationManager.shared.recordAlcohol(alcoholType: alcoholType)
                            }
                        }
                        await TimeSlotManager.shared.recordDrinkLog(at: timeSlot)
                        print("[iOSWatchBridge] ✅ ドリンク記録完了: \(type) at \(timeSlot.displayName)")
                    default:
                        break
                    }

                    // 摂取記録後、少し待ってからTimeSlotManagerの最新データを再読み込み
                    // （Firestoreへの保存が完了するまで待つ）
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
                    await TimeSlotManager.shared.loadTodayProgress()
                    print("[iOSWatchBridge] 📊 TimeSlotProgress再読み込み完了")

                    // 最新データをWatchに送信
                    let profile = AuthenticationManager.shared.userProfile
                    let todayExercises = await AuthenticationManager.shared.getTodayExercises()
                    let todayReps = todayExercises.reduce(0) { $0 + $1.reps }
                    let todayXP = todayExercises.reduce(0) { $0 + $1.points }
                    self.sendStatsToWatch(
                        streak: profile?.streak ?? 0,
                        todayReps: todayReps,
                        todayXP: todayXP,
                        todayExercises: todayExercises
                    )
                }
                return
            }
        }
    }

    // バックグラウンド時に届いたコンテキストも処理
    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in
            if let workoutData = applicationContext["pendingWorkout"] as? Data,
               let workout = try? JSONDecoder().decode(WatchWorkoutData.self, from: workoutData) {
                await AuthenticationManager.shared.recordWatchWorkout(workout)
            }

            if let setData = applicationContext["pendingCompletedSet"] as? Data,
               let set = try? JSONDecoder().decode(WatchSetData.self, from: setData) {
                let stats = await AuthenticationManager.shared.recordWatchCompletedSet(set)
                let todayExercises = await AuthenticationManager.shared.getTodayExercises()
                sendStatsToWatch(streak: stats.streak, todayReps: stats.todayReps, todayXP: stats.todayXP, todayExercises: todayExercises)
            }
        }
    }

    // iOS側で直接記録した後にWatchへ通知
    func notifyWatchAfterDirectRecord() {
        Task {
            let profile = AuthenticationManager.shared.userProfile
            let todayExercises = await AuthenticationManager.shared.getTodayExercises()
            let todayReps = todayExercises.reduce(0) { $0 + $1.reps }
            let todayXP   = todayExercises.reduce(0) { $0 + $1.points }
            sendStatsToWatch(
                streak: profile?.streak ?? 0,
                todayReps: todayReps,
                todayXP: todayXP,
                todayExercises: todayExercises
            )
        }
    }

    // 時間帯別の進捗を計算
    private func calculateTimeSlotProgress() async -> TimeSlotProgressData {
        let currentHour = Calendar.current.component(.hour, from: Date())
        var visibleSlots: [TimeSlot]

        if currentHour < 6 {
            visibleSlots = TimeSlot.allCases
        } else if currentHour < 10 {
            visibleSlots = [.morning]
        } else if currentHour < 14 {
            visibleSlots = [.morning, .noon]
        } else if currentHour < 18 {
            visibleSlots = [.morning, .noon, .afternoon]
        } else {
            visibleSlots = TimeSlot.allCases
        }

        var totalTraining = 0
        var totalTrainingGoal = 0
        var totalMindfulness = 0
        var totalMindfulnessGoal = 0
        var totalMealLogged = 0
        var totalMealGoal = 0
        var totalDrinkLogged = 0
        var totalDrinkGoal = 0

        let timeSlotManager = TimeSlotManager.shared
        await timeSlotManager.loadTodayProgress()

        // 今日の運動記録を取得
        let todayExercises = await AuthenticationManager.shared.getTodayExercises()
        let calendar = Calendar.current

        for slot in visibleSlots {
            if let goal = timeSlotManager.settings.goalFor(slot),
               let progress = timeSlotManager.progress.progressFor(slot) {
                // トレーニングは実際のセット数をカウント（iOS側と同じロジック）
                let setsInSlot = todayExercises.filter { exercise in
                    let hour = calendar.component(.hour, from: exercise.timestamp)
                    return hour >= slot.startHour && hour < slot.endHour
                }.count
                totalTraining += setsInSlot
                totalTrainingGoal += goal.trainingGoal

                totalMindfulness += progress.mindfulnessCompleted
                totalMindfulnessGoal += goal.mindfulnessGoal

                if goal.logGoal.mealRequired {
                    totalMealGoal += 1
                    totalMealLogged += progress.logProgress.mealLogged
                }
                if goal.logGoal.drinkRequired {
                    totalDrinkGoal += 1
                    totalDrinkLogged += progress.logProgress.drinkLogged
                }
            }
        }

        return TimeSlotProgressData(
            totalTraining: totalTraining,
            totalTrainingGoal: totalTrainingGoal,
            totalMindfulness: totalMindfulness,
            totalMindfulnessGoal: totalMindfulnessGoal,
            totalMealLogged: totalMealLogged,
            totalMealGoal: totalMealGoal,
            totalDrinkLogged: totalDrinkLogged,
            totalDrinkGoal: totalDrinkGoal
        )
    }

    // iOS → Watch: 更新後の数値を送信
    private func sendStatsToWatch(streak: Int, todayReps: Int, todayXP: Int, todayExercises: [CompletedExercise] = []) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        // デバウンス: 2秒以内の重複送信を防ぐ
        if let lastSend = lastStatsSendTime, Date().timeIntervalSince(lastSend) < statsDebounceInterval {
            print("[iOSWatchBridge] Stats送信スキップ（デバウンス）")
            return
        }
        lastStatsSendTime = Date()

        var payload: [String: Any] = [
            "streak":    streak,
            "todayReps": todayReps,
            "todayXP":   todayXP,
        ]

        // 目標カロリー情報 & 統一指標を取得して送信
        Task {
            let calorieGoal = await AuthenticationManager.shared.getDailyCalorieGoal()
            payload["calorieTarget"] = calorieGoal.targetCalories
            payload["calorieConsumed"] = calorieGoal.consumedCalories
            payload["caloriePercent"] = calorieGoal.percentAchieved

            // 統一指標: 時間帯別の進捗を計算して送信
            let timeSlotProgress = await calculateTimeSlotProgress()
            payload["totalTraining"] = timeSlotProgress.totalTraining
            payload["totalTrainingGoal"] = timeSlotProgress.totalTrainingGoal
            payload["totalMindfulness"] = timeSlotProgress.totalMindfulness
            payload["totalMindfulnessGoal"] = timeSlotProgress.totalMindfulnessGoal
            payload["totalMealLogged"] = timeSlotProgress.totalMealLogged
            payload["totalMealGoal"] = timeSlotProgress.totalMealGoal
            payload["totalDrinkLogged"] = timeSlotProgress.totalDrinkLogged
            payload["totalDrinkGoal"] = timeSlotProgress.totalDrinkGoal

            // 後方互換性: セット数も送信
            let todaySetCount = await AuthenticationManager.shared.getTodaySetCount()
            let dailySetGoal = await AuthenticationManager.shared.getDailySetGoal()
            payload["todaySetCount"] = todaySetCount
            payload["dailySetGoal"] = dailySetGoal

            // モーション感度設定をWatchに送信
            let motionSensitivity = await AuthenticationManager.shared.getAllMotionSensitivity()
            var sensitivityData: [[String: Any]] = []
            for (exerciseId, sens) in motionSensitivity {
                sensitivityData.append([
                    "exerciseId": exerciseId,
                    "threshold": sens.threshold,
                    "minInterval": sens.minInterval
                ])
            }
            if let data = try? JSONSerialization.data(withJSONObject: sensitivityData) {
                payload["motionSensitivity"] = data
            }

            // 今日の運動記録を含める
            if !todayExercises.isEmpty {
                let watchExercises = todayExercises.map { ex in
                    CompletedExerciseForWatch(
                        exerciseId: ex.exerciseId,
                        exerciseName: ex.exerciseName,
                        reps: ex.reps,
                        points: ex.points,
                        timestamp: ex.timestamp
                    )
                }
                if let data = try? JSONEncoder().encode(watchExercises) {
                    payload["todayExercises"] = data
                }
            }

            // 摂取データを含める
            let intakeData = await AuthenticationManager.shared.getTodayIntakeSummary()
            let intakeGoals = await AuthenticationManager.shared.getIntakeSettings()
            payload["intakeCalories"] = intakeData.totalCalories
            payload["intakeCaloriesGoal"] = intakeGoals.dailyCalorieGoal
            payload["intakeWater"] = intakeData.totalWaterMl
            payload["intakeWaterGoal"] = intakeGoals.dailyWaterGoal
            payload["intakeCaffeine"] = intakeData.totalCaffeineMg
            payload["intakeCaffeineLimit"] = intakeGoals.dailyCaffeineLimit
            payload["intakeAlcohol"] = intakeData.totalAlcoholG
            payload["intakeAlcoholLimit"] = intakeGoals.dailyAlcoholLimit

            print("[iOSWatchBridge] 📤 Sending intake data to Watch: cal=\(intakeData.totalCalories), water=\(intakeData.totalWaterMl)ml, caffeine=\(intakeData.totalCaffeineMg)mg, alcohol=\(String(format: "%.1f", intakeData.totalAlcoholG))g")

            // 摂取記録のデフォルト設定を含める（Watch用）
            payload["breakfastCalories"] = intakeGoals.breakfastCalories
            payload["lunchCalories"] = intakeGoals.lunchCalories
            payload["dinnerCalories"] = intakeGoals.dinnerCalories
            payload["waterPerCup"] = intakeGoals.waterPerCup
            payload["coffeePerCup"] = intakeGoals.coffeePerCup
            payload["caffeinePerCup"] = intakeGoals.caffeinePerCup
            if let beerSetting = intakeGoals.settingFor(alcoholType: .beer) {
                payload["beerAlcoholG"] = beerSetting.alcoholG
            }
            if let wineSetting = intakeGoals.settingFor(alcoholType: .wine) {
                payload["wineAlcoholG"] = wineSetting.alcoholG
            }
            if let chuhaiSetting = intakeGoals.settingFor(alcoholType: .chuhai) {
                payload["chuhaiAlcoholG"] = chuhaiSetting.alcoholG
            }

            // ログ入力状態を含める
            payload["todayMealLogged"] = !intakeData.meals.isEmpty

            if session.isReachable {
                session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
            } else {
                try? session.updateApplicationContext(payload)
            }
        }
    }
}

/// Watch 側の WorkoutData と共通のシリアライズ構造
struct WatchWorkoutData: Codable {
    let exerciseId: String
    let exerciseName: String
    let reps: Int
    let points: Int
    let timestamp: Date
}

/// Watch 側の WatchSetData と共通のシリアライズ構造（iOS 側ミラー）
/// Watchセット内の個別種目
struct WatchSetExercise: Codable {
    let exerciseId: String
    let exerciseName: String
    let reps: Int
    let points: Int
}

struct WatchSetData: Codable {
    let exercises: [WatchSetExercise]
    let totalXP: Int
    let totalReps: Int
    let timestamp: Date
}

/// Watch に送信する運動記録（CompletedExercise から変換）
struct CompletedExerciseForWatch: Codable {
    let exerciseId: String
    let exerciseName: String
    let reps: Int
    let points: Int
    let timestamp: Date
}

/// 時間帯別の進捗データ
struct TimeSlotProgressData {
    let totalTraining: Int
    let totalTrainingGoal: Int
    let totalMindfulness: Int
    let totalMindfulnessGoal: Int
    let totalMealLogged: Int
    let totalMealGoal: Int
    let totalDrinkLogged: Int
    let totalDrinkGoal: Int
}
