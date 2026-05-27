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
    private var lastStatsPayloadSignature: String?
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
    static let watchAutoLaunchKey = "fitingo.watchAutoLaunch"

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
                let summary = await AuthenticationManager.shared.getTodayActivitySummary()
                let todayExercises = await AuthenticationManager.shared.getTodayExercises()
                sendStatsToWatch(streak: stats.streak, todayReps: stats.todayReps, todayXP: stats.todayXP,
                                 todaySets: summary.completedSets, todayExercises: todayExercises)
                return
            }

            // ③ stats リクエスト（Watch 起動時）
            if (message["action"] as? String) == "request_stats" {
                let force = message["force"] as? Bool ?? false
                let profile = AuthenticationManager.shared.userProfile
                Task {
                    if force {
                        lastStatsSendTime = nil
                        lastStatsPayloadSignature = nil
                        await HealthKitManager.shared.fetchWatchSnapshotHealth(force: true)
                        await TimeSlotManager.shared.loadTodayProgress(syncHealthKit: false)
                    } else {
                        await HealthKitManager.shared.fetchWatchSnapshotHealth()
                    }
                    let summary = await AuthenticationManager.shared.getTodayActivitySummary()
                    let todayExercises = await AuthenticationManager.shared.getTodayExercises()
                    self.sendStatsToWatch(
                        streak:    profile?.streak ?? 0,
                        todayReps: summary.exerciseReps,
                        todayXP:   summary.exercisePoints,
                        todaySets: summary.completedSets,
                        todayExercises: todayExercises,
                        force: force
                    )
                }
                return
            }

            // ④ Watch側でマインドフルネス完了
            if (message["action"] as? String) == "mindfulness_completed" {
                Task {
                    print("[iOSWatchBridge] 🧘 Watch mindfulness completed — refreshing HealthKit")
                    await HealthKitManager.shared.refreshMindfulness()
                    // TimeSlotManagerの合計とHealthKitの差分だけ記録（二重カウント防止）
                    let hkCount = HealthKitManager.shared.todayMindfulnessSessions
                    let totalInSlots = TimeSlot.allCases.compactMap {
                        TimeSlotManager.shared.progress.progressFor($0)?.mindfulnessCompleted
                    }.reduce(0, +)
                    let needed = hkCount - totalInSlots
                    if needed > 0 {
                        let currentSlot = TimeSlot.current()
                        for _ in 0..<needed {
                            await TimeSlotManager.shared.recordMindfulnessCompleted(at: currentSlot)
                        }
                        print("[iOSWatchBridge] ✅ Recorded \(needed) mindfulness to \(currentSlot.displayName)")
                    }
                    let profile = AuthenticationManager.shared.userProfile
                    let summary = await AuthenticationManager.shared.getTodayActivitySummary()
                    let exercises = await AuthenticationManager.shared.getTodayExercises()
                    self.sendStatsToWatch(streak: profile?.streak ?? 0, todayReps: summary.exerciseReps, todayXP: summary.exercisePoints, todaySets: summary.completedSets, todayExercises: exercises)
                }
                return
            }

            // ⑤ 摂取記録（Watch からの記録）
            if (message["action"] as? String) == "record_intake" {
                let type = message["type"] as? String ?? ""
                let subtype = message["subtype"] as? String

                Task {
                    let timestamp = Date()
                    let calendar = Calendar.current
                    let hour = calendar.component(.hour, from: timestamp)
                    let timeSlot: TimeSlot

                    if hour < 6 { timeSlot = .midnight }
                    else if hour < 10 { timeSlot = .morning }
                    else if hour < 14 { timeSlot = .noon }
                    else if hour < 18 { timeSlot = .afternoon }
                    else { timeSlot = .evening }

                    switch type {
                    case "meal":
                        if let mealTypeStr = subtype {
                            if let mealType = MealType(rawValue: mealTypeStr) {
                                let calories = IntakeSettings.defaultSettings.caloriesFor(mealType: mealType)
                                await TimeSlotManager.shared.recordMealLog(at: timeSlot, calories: calories)
                                await AuthenticationManager.shared.recordMeal(mealType: mealType)
                                print("[iOSWatchBridge] ✅ 食事記録完了: \(mealType.rawValue) \(calories)kcal at \(timeSlot.displayName)")
                            }
                        }
                    case "water", "coffee", "alcohol":
                        let drinkMl: Int
                        if type == "water" {
                            drinkMl = IntakeSettings.defaultSettings.waterPerCup
                        } else if type == "coffee" {
                            drinkMl = IntakeSettings.defaultSettings.coffeePerCup
                        } else if let alcoholTypeStr = subtype,
                                  let alcoholType = AlcoholType(rawValue: alcoholTypeStr) {
                            drinkMl = alcoholType.amountMl
                        } else {
                            drinkMl = 200
                        }
                        await TimeSlotManager.shared.recordDrinkLog(at: timeSlot, ml: drinkMl)
                        if type == "water" {
                            await AuthenticationManager.shared.recordWater()
                        } else if type == "coffee" {
                            await AuthenticationManager.shared.recordCoffee()
                        } else if let alcoholType = AlcoholType(rawValue: subtype ?? "") {
                            await AuthenticationManager.shared.recordAlcohol(alcoholType: alcoholType)
                        }
                        print("[iOSWatchBridge] ✅ ドリンク記録完了: \(type) \(drinkMl)ml at \(timeSlot.displayName)")
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
                    let summary = await AuthenticationManager.shared.getTodayActivitySummary()
                    let todayExercises = await AuthenticationManager.shared.getTodayExercises()
                    self.sendStatsToWatch(
                        streak: profile?.streak ?? 0,
                        todayReps: summary.exerciseReps,
                        todayXP: summary.exercisePoints,
                        todaySets: summary.completedSets,
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
                let summary = await AuthenticationManager.shared.getTodayActivitySummary()
                let todayExercises = await AuthenticationManager.shared.getTodayExercises()
                sendStatsToWatch(streak: stats.streak, todayReps: stats.todayReps, todayXP: stats.todayXP,
                                 todaySets: summary.completedSets, todayExercises: todayExercises)
            }
        }
    }

    // iOS側で直接記録した後にWatchへ通知
    func notifyWatchAfterDirectRecord() {
        Task {
            let profile = AuthenticationManager.shared.userProfile
            let summary = await AuthenticationManager.shared.getTodayActivitySummary()
            let todayExercises = await AuthenticationManager.shared.getTodayExercises()
            sendStatsToWatch(
                streak: profile?.streak ?? 0,
                todayReps: summary.exerciseReps,
                todayXP: summary.exercisePoints,
                todaySets: summary.completedSets,
                todayExercises: todayExercises
            )
        }
    }

    // 時間帯別の進捗を返す（DashboardView.updateWidgetData が書き込む共有 UserDefaults を読む）
    private func calculateTimeSlotProgress() async -> TimeSlotProgressData {
        // updateWidgetData() が常に最新値を group.com.kfit.app に書き込んでいる。
        // それをそのまま読むことで iOS の進捗バー表示と完全に一致する。
        if let ud = UserDefaults(suiteName: "group.com.kfit.app") {
            let totalTraining      = ud.integer(forKey: "trainingCompleted")
            let totalTrainingGoal  = ud.integer(forKey: "trainingGoal")
            let totalMindfulness   = ud.integer(forKey: "mindfulnessCompleted")
            let totalMindfulnessGoal = ud.integer(forKey: "mindfulnessGoal")
            let totalMealLogged    = ud.integer(forKey: "mealLogged")
            let totalMealGoal      = ud.integer(forKey: "mealGoal")
            let totalDrinkLogged   = ud.integer(forKey: "drinkLogged")
            let totalDrinkGoal     = ud.integer(forKey: "drinkGoal")

            // 少なくとも目標が設定されていれば有効なデータとみなす
            if totalTrainingGoal > 0 || totalMindfulnessGoal > 0 {
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
        }

        // フォールバック: UserDefaults にデータがない場合はリアルタイム計算
        let timeSlotManager = TimeSlotManager.shared
        await timeSlotManager.loadTodaySettings()
        await timeSlotManager.loadTodayProgress()
        let todayExercises = await AuthenticationManager.shared.getTodayExercises()
        let calendar = Calendar.current
        var totalTraining = 0
        var totalTrainingGoal = 0
        var totalMindfulnessGoal = 0
        var totalMealLogged = 0
        var totalMealGoal = 0
        var totalDrinkLogged = 0
        var totalDrinkGoal = 0

        for slot in TimeSlot.allCases {
            if let goal = timeSlotManager.settings.goalFor(slot),
               let progress = timeSlotManager.progress.progressFor(slot) {
                let slotExercises = todayExercises.filter { exercise in
                    let hour = calendar.component(.hour, from: exercise.timestamp)
                    return hour >= slot.startHour && hour < slot.endHour
                }.sorted { $0.timestamp < $1.timestamp }
                var setsInSlot = 0
                var lastTime: Date? = nil
                for ex in slotExercises {
                    if let last = lastTime, ex.timestamp.timeIntervalSince(last) <= 30 * 60 {
                    } else {
                        setsInSlot += 1
                    }
                    lastTime = ex.timestamp
                }
                totalTraining += setsInSlot
                totalTrainingGoal += goal.trainingGoal
                totalMindfulnessGoal += goal.mindfulnessGoal
                if goal.logGoal.mealGoal > 0 {
                    totalMealGoal += goal.logGoal.mealGoal
                    totalMealLogged += progress.logProgress.mealLogged
                }
                if goal.logGoal.drinkGoal > 0 {
                    totalDrinkGoal += goal.logGoal.drinkGoal
                    totalDrinkLogged += progress.logProgress.drinkLogged
                }
            }
        }
        return TimeSlotProgressData(
            totalTraining: totalTraining,
            totalTrainingGoal: totalTrainingGoal,
            totalMindfulness: HealthKitManager.shared.todayMindfulnessSessions,
            totalMindfulnessGoal: totalMindfulnessGoal,
            totalMealLogged: totalMealLogged,
            totalMealGoal: totalMealGoal,
            totalDrinkLogged: totalDrinkLogged,
            totalDrinkGoal: totalDrinkGoal
        )
    }

    // iOS → Watch: 更新後の数値を送信
    private func sendStatsToWatch(streak: Int, todayReps: Int, todayXP: Int, todaySets: Int = 0, todayExercises: [CompletedExercise] = [], force: Bool = false) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        var payload: [String: Any] = [
            "streak":    streak,
            "todayReps": todayReps,
            "todayXP":   todayXP,
            "todaySets": todaySets,
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

            let watchFaceTasks = await buildWatchFaceTasks()
            if let data = try? JSONEncoder().encode(watchFaceTasks) {
                payload["watchFaceTasks"] = data
            }

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
            let summary = await AuthenticationManager.shared.getTodayActivitySummary()
            let intakeGoals = await AuthenticationManager.shared.getIntakeSettings()
            payload["intakeCalories"] = summary.intakeCalories
            payload["intakeCaloriesGoal"] = intakeGoals.dailyCalorieGoal
            payload["intakeWater"] = summary.intakeWaterMl
            payload["intakeWaterGoal"] = intakeGoals.dailyWaterGoal
            payload["intakeCaffeine"] = summary.intakeCaffeineMg
            payload["intakeCaffeineLimit"] = intakeGoals.dailyCaffeineLimit
            payload["intakeAlcohol"] = summary.intakeAlcoholG
            payload["intakeAlcoholLimit"] = intakeGoals.dailyAlcoholLimit

            print("[iOSWatchBridge] 📤 Sending intake data to Watch: cal=\(summary.intakeCalories), water=\(summary.intakeWaterMl)ml, caffeine=\(summary.intakeCaffeineMg)mg, alcohol=\(String(format: "%.1f", summary.intakeAlcoholG))g")

            // 摂取記録のデフォルト設定を含める（Watch用）
            payload["breakfastCalories"] = intakeGoals.breakfastCalories
            payload["lunchCalories"] = intakeGoals.lunchCalories
            payload["dinnerCalories"] = intakeGoals.dinnerCalories
            payload["snackCalories"] = intakeGoals.snackCalories
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
            payload["todayMealLogged"] = summary.mealCount > 0

            // HealthKitデータを含める
            let healthKit = HealthKitManager.shared
            payload["todaySteps"] = Int(healthKit.todaySteps)
            payload["todayActiveCalories"] = Int(healthKit.todayActiveCalories)
            payload["todayRestingCalories"] = Int(healthKit.todayRestingCalories)
            payload["todayTotalCalories"] = Int(healthKit.todayTotalCalories)
            payload["latestHeartRate"] = Int(healthKit.latestHeartRate)
            payload["lastNightTotalHours"] = healthKit.lastNightTotalHours
            payload["latestBodyMass"] = healthKit.latestBodyMass
            payload["latestBodyFatPercentage"] = healthKit.latestBodyFatPercentage
            payload["todayMindfulnessSessions"] = healthKit.todayMindfulnessSessions
            payload["todayMindfulnessMinutes"] = healthKit.todayMindfulnessMinutes
            payload["todayWorkoutMinutes"] = healthKit.todayWorkoutMinutes

            print("[iOSWatchBridge] 📤 Sending HealthKit data to Watch: steps=\(Int(healthKit.todaySteps)), cal=\(Int(healthKit.todayTotalCalories)), workout=\(healthKit.todayWorkoutMinutes), mindfulness=\(healthKit.todayMindfulnessSessions)")

            let signature = self.statsPayloadSignature(for: payload)
            if !force,
               let lastSend = self.lastStatsSendTime,
               Date().timeIntervalSince(lastSend) < self.statsDebounceInterval,
               signature == self.lastStatsPayloadSignature {
                print("[iOSWatchBridge] Stats送信スキップ（デバウンス）")
                return
            }
            if !force, signature == self.lastStatsPayloadSignature {
                print("[iOSWatchBridge] Stats送信スキップ（差分なし）")
                return
            }
            self.lastStatsPayloadSignature = signature
            self.lastStatsSendTime = Date()

            if session.isReachable {
                session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
            } else {
                try? session.updateApplicationContext(payload)
            }
        }
    }

    private func statsPayloadSignature(for payload: [String: Any]) -> String {
        payload.keys.sorted().map { key in
            "\(key)=\(signatureValue(payload[key]))"
        }.joined(separator: "|")
    }

    private func signatureValue(_ value: Any?) -> String {
        switch value {
        case let value as Data:
            return value.base64EncodedString()
        case let value as Date:
            return String(format: "%.0f", value.timeIntervalSince1970)
        case let value as Double:
            return String(format: "%.3f", value)
        case let value as Float:
            return String(format: "%.3f", value)
        case let value as NSNumber:
            return value.stringValue
        case let value as String:
            return value
        case let value as Bool:
            return value ? "true" : "false"
        case .none:
            return "nil"
        default:
            return String(describing: value)
        }
    }

    private func buildWatchFaceTasks() async -> [WatchFaceTaskConfigForWatch] {
        let timeSlotManager = TimeSlotManager.shared
        await timeSlotManager.loadTodaySettings()
        await timeSlotManager.loadTodayProgress(syncHealthKit: true)
        let todayExercises = await AuthenticationManager.shared.getTodayExercises()
        let calendar = Calendar.current

        func countSets(in slot: TimeSlot) -> Int {
            let slotExercises = todayExercises.filter { exercise in
                let hour = calendar.component(.hour, from: exercise.timestamp)
                return hour >= slot.startHour && hour < slot.endHour
            }.sorted { $0.timestamp < $1.timestamp }

            var setCount = 0
            var lastTime: Date?
            for exercise in slotExercises {
                if let lastTime, exercise.timestamp.timeIntervalSince(lastTime) <= 30 * 60 {
                    // 同じ30分内の種目は同一セットとして扱う
                } else {
                    setCount += 1
                }
                lastTime = exercise.timestamp
            }
            return setCount
        }

        func mealSubtype(for slot: TimeSlot) -> String {
            switch slot {
            case .midnight: return "snack"
            case .morning: return "breakfast"
            case .noon: return "lunch"
            case .afternoon: return "snack"
            case .evening: return "dinner"
            }
        }

        func mealEmoji(for slot: TimeSlot) -> String {
            switch slot {
            case .midnight: return "🍃"
            case .morning: return "🍳"
            case .noon: return "🍱"
            case .afternoon: return "🍃"
            case .evening: return "🍽️"
            }
        }

        var tasks: [WatchFaceTaskConfigForWatch] = []
        for slot in TimeSlot.allCases {
            guard let goal = timeSlotManager.settings.goalFor(slot),
                  let progress = timeSlotManager.progress.progressFor(slot) else { continue }
            let prefix = slot.rawValue

            if goal.trainingGoal > 0 {
                let setsCompleted = max(progress.trainingCompleted, countSets(in: slot))
                for index in 1...goal.trainingGoal {
                    tasks.append(WatchFaceTaskConfigForWatch(
                        id: "\(prefix)-training-\(index)",
                        emoji: "💪",
                        color: "training",
                        isDone: setsCompleted >= index,
                        actionType: "training",
                        mealSubtype: nil,
                        intakeMessage: ""
                    ))
                }
            }

            if goal.logGoal.mealGoal > 0 {
                let subtype = mealSubtype(for: slot)
                tasks.append(WatchFaceTaskConfigForWatch(
                    id: "\(prefix)-meal",
                    emoji: mealEmoji(for: slot),
                    color: "meal",
                    isDone: progress.logProgress.mealLogged >= goal.logGoal.mealGoal,
                    actionType: "meal",
                    mealSubtype: subtype,
                    intakeMessage: "\(slot.displayName)の食事を追加しますか？"
                ))
            }

            if goal.logGoal.drinkGoal > 0 {
                tasks.append(WatchFaceTaskConfigForWatch(
                    id: "\(prefix)-drink",
                    emoji: "💧",
                    color: "water",
                    isDone: progress.logProgress.drinkLogged >= goal.logGoal.drinkGoal,
                    actionType: "water",
                    mealSubtype: nil,
                    intakeMessage: "\(slot.displayName)の水分を追加しますか？"
                ))
            }

            if goal.logGoal.mindInputRequired {
                tasks.append(WatchFaceTaskConfigForWatch(
                    id: "\(prefix)-mind-input",
                    emoji: "📝",
                    color: "mind",
                    isDone: progress.logProgress.mindInputLogged > 0,
                    actionType: "custom",
                    mealSubtype: nil,
                    intakeMessage: ""
                ))
            }

            if goal.mindfulnessGoal > 0 {
                for index in 1...goal.mindfulnessGoal {
                    tasks.append(WatchFaceTaskConfigForWatch(
                        id: "\(prefix)-mindfulness-\(index)",
                        emoji: "🧘",
                        color: "mind",
                        isDone: progress.mindfulnessCompleted >= index,
                        actionType: "mindfulness",
                        mealSubtype: nil,
                        intakeMessage: ""
                    ))
                }
            }

            if goal.stretchGoal.enabled && goal.stretchGoal.stretchMinutes > 0 && slot != .midnight {
                tasks.append(WatchFaceTaskConfigForWatch(
                    id: "\(prefix)-stretch",
                    emoji: "🤸",
                    color: "stretch",
                    isDone: progress.stretchSetsCompleted >= goal.stretchGoal.stretchMinutes,
                    actionType: "stretch",
                    mealSubtype: nil,
                    intakeMessage: ""
                ))
            }

            for activity in goal.customActivities where activity.isEnabled {
                tasks.append(WatchFaceTaskConfigForWatch(
                    id: "\(prefix)-custom-\(activity.id)",
                    emoji: activity.emoji,
                    color: "custom",
                    isDone: progress.completedActivityIds.contains(activity.id),
                    actionType: "custom",
                    mealSubtype: nil,
                    intakeMessage: ""
                ))
            }
        }
        return tasks
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
    let setId: String?
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

struct WatchFaceTaskConfigForWatch: Codable {
    let id: String
    let emoji: String
    let color: String
    let isDone: Bool
    let actionType: String
    let mealSubtype: String?
    let intakeMessage: String
}
