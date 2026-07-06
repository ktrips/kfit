import Combine
import WatchConnectivity
import Foundation
import FirebaseFirestore
import FirebaseAuth

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
    private var lastStatsRequestTime: Date?
    private let statsRequestCacheInterval: TimeInterval = 5.0 // 5秒以内のfetchをスキップ
    private var lastStatsFetchTime: Date?            // 重いフェッチを最後に開始した時刻
    private var pendingStatsTask: Task<Void, Never>? // 末尾集約用の遅延送信タスク

    // Plus 状態変化の監視
    private var plusCancellable: AnyCancellable?

    private override init() {
        super.init()
        activate()
        observePlusStatus()
    }

    /// PlusManager.isPlus が変化したとき即座に Watch へ通知
    private func observePlusStatus() {
        plusCancellable = PlusManager.shared.$isPlus
            .dropFirst()            // 初期値は sendStats 経由で送られるのでスキップ
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isPlus in
                self?.sendPlusStatusToWatch(isPlus: isPlus)
            }
    }

    /// Plus 状態だけを Watch へ即時送信（Application Context 経由でオフラインも対応）
    func sendPlusStatusToWatch(isPlus: Bool) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let payload: [String: Any] = ["isPlus": isPlus]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: { error in
                dlog("[iOSWatchBridge] sendPlusStatus error: \(error) – falling back to context")
                try? session.updateApplicationContext(payload)
            })
        } else {
            try? session.updateApplicationContext(payload)
        }
        dlog("[iOSWatchBridge] 📤 Plus status sent to Watch: \(isPlus)")
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
            dlog("[iOSWatchBridge] Watch自動起動はユーザーによって無効化されています")
            return
        }
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        let payload: [String: Any] = ["action": "start_workout", "ts": Date().timeIntervalSince1970]

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                dlog("[iOSWatchBridge] sendMessage error: \(error)")
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
        if let error { dlog("[iOSWatchBridge] activation error: \(error)") }
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
                dlog("[iOSWatchBridge] 種目受信: \(workout.exerciseName) \(workout.reps)rep")
                await AuthenticationManager.shared.recordWatchWorkout(workout)
                return
            }

            // ② セット完了（全種目まとめて）
            if let setData = message["completed_set"] as? Data,
               let set = try? JSONDecoder().decode(WatchSetData.self, from: setData) {
                dlog("[iOSWatchBridge] セット完了受信: \(set.totalReps)rep / \(set.totalXP)XP")
                let stats = await AuthenticationManager.shared.recordWatchCompletedSet(set)
                await sendStatsAfterSet(stats)
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
                        lastStatsRequestTime = nil
                        await HealthKitManager.shared.fetchWatchSnapshotHealth(force: true)
                        await TimeSlotManager.shared.loadTodayProgress(syncHealthKit: false)
                    } else if let lastReq = lastStatsRequestTime,
                              Date().timeIntervalSince(lastReq) < statsRequestCacheInterval {
                        // 5秒以内の再リクエスト: fetch をスキップして前回の結果を再送
                        dlog("[iOSWatchBridge] request_stats キャッシュ利用（fetch スキップ）")
                        await self.fetchAndSendStats(force: false)
                        return
                    } else {
                        lastStatsRequestTime = Date()
                        await HealthKitManager.shared.fetchWatchSnapshotHealth()
                    }
                    await self.fetchAndSendStats(force: force)
                }
                return
            }

            // ④ Watch側でマインドフルネス完了
            if (message["action"] as? String) == "mindfulness_completed" {
                Task {
                    dlog("[iOSWatchBridge] 🧘 Watch mindfulness completed — refreshing HealthKit")
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
                        dlog("[iOSWatchBridge] ✅ Recorded \(needed) mindfulness to \(currentSlot.displayName)")
                    }
                    await self.fetchAndSendStats()
                }
                return
            }

            // ④-2 Watch側で20分スタンド完了
            if (message["action"] as? String) == "stand_completed" {
                Task {
                    let currentSlot = TimeSlot.current()
                    await TimeSlotManager.shared.recordStandCompleted(at: currentSlot)
                    await Self.saveMindfulStandSession(at: currentSlot)
                    dlog("[iOSWatchBridge] 🧍 Watch stand completed at \(currentSlot.displayName)")
                }
                return
            }

            // ⑤-pre フィードリクエスト（Watch 起動時 / 手動同期）
            if (message["action"] as? String) == "request_feed" {
                Task { await self.sendFeedToWatch() }
                return
            }

            // ⑤ 摂取記録（Watch からの記録）
            if (message["action"] as? String) == "record_intake" {
                let type = message["type"] as? String ?? ""
                let subtype = message["subtype"] as? String

                Task {
                    let hour = Calendar.current.component(.hour, from: Date())
                    let timeSlot = TimeSlot.forHour(hour)

                    switch type {
                    case "meal":
                        if let mealTypeStr = subtype {
                            if let mealType = MealType(rawValue: mealTypeStr) {
                                let calories = IntakeSettings.defaultSettings.caloriesFor(mealType: mealType)
                                await TimeSlotManager.shared.recordMealLog(at: timeSlot, calories: calories)
                                await AuthenticationManager.shared.recordMeal(mealType: mealType)
                                dlog("[iOSWatchBridge] ✅ 食事記録完了: \(mealType.rawValue) \(calories)kcal at \(timeSlot.displayName)")
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
                        dlog("[iOSWatchBridge] ✅ ドリンク記録完了: \(type) \(drinkMl)ml at \(timeSlot.displayName)")
                    default:
                        break
                    }

                    // M5: 固定スリープ後の再フェッチを廃止。
                    // Firestoreへの書き込みはローカルキャッシュに即時反映されるため
                    // 500ms の固定待機 + 全ドキュメント再読み込みは不要。
                    // インメモリの progress は上記の record* 呼び出し内で更新済み。
                    dlog("[iOSWatchBridge] 📊 摂取記録完了（インメモリ状態を使用）")

                    // 最新データをWatchに送信
                    await self.fetchAndSendStats()
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
                await sendStatsAfterSet(stats)
            }

            if (applicationContext["action"] as? String) == "stand_completed" {
                let slot = TimeSlot.current()
                await TimeSlotManager.shared.recordStandCompleted(at: slot)
                await Self.saveMindfulStandSession(at: slot)
                dlog("[iOSWatchBridge] 🧍 Watch stand completed (context)")
            }
        }
    }

    // 20分スタンド完了をHealthKitにマインドフルセッションとして保存し、TimeSlotに反映
    private static func saveMindfulStandSession(at slot: TimeSlot) async {
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-20 * 60)
        let saved = await HealthKitManager.shared.saveMindfulnessSession(
            startDate: startDate,
            endDate: endDate,
            durationSeconds: 20 * 60,
            sessionType: "Stand"
        )
        guard saved else { return }
        await HealthKitManager.shared.refreshMindfulness()
        let hkCount = HealthKitManager.shared.todayMindfulnessSessions
        let totalInSlots = TimeSlot.allCases.compactMap {
            TimeSlotManager.shared.progress.progressFor($0)?.mindfulnessCompleted
        }.reduce(0, +)
        let needed = hkCount - totalInSlots
        if needed > 0 {
            for _ in 0..<needed {
                await TimeSlotManager.shared.recordMindfulnessCompleted(at: slot)
            }
        }
    }

    // iOS側で直接記録した後にWatchへ通知
    func notifyWatchAfterDirectRecord() {
        Task { await fetchAndSendStats() }
    }

    // MARK: - Watch送信共通ヘルパー

    /// profile取得 → summary取得 → exercises取得 → sendStatsToWatch の共通パターン
    private func fetchAndSendStats(force: Bool = false) async {
        let profile = AuthenticationManager.shared.userProfile
        let summary = await AuthenticationManager.shared.getTodayActivitySummary()
        let exercises = await AuthenticationManager.shared.getTodayExercises()
        sendStatsToWatch(
            streak: profile?.streak ?? 0,
            todayReps: summary.exerciseReps,
            todayXP: summary.exercisePoints,
            todaySets: summary.completedSets,
            todayExercises: exercises,
            force: force
        )
    }

    /// recordWatchCompletedSet の返り値を使って summary + exercises だけ追加取得して送信
    private func sendStatsAfterSet(_ stats: (streak: Int, todayReps: Int, todayXP: Int)) async {
        let summary = await AuthenticationManager.shared.getTodayActivitySummary()
        let exercises = await AuthenticationManager.shared.getTodayExercises()
        sendStatsToWatch(
            streak: stats.streak,
            todayReps: stats.todayReps,
            todayXP: stats.todayXP,
            todaySets: summary.completedSets,
            todayExercises: exercises
        )
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

            let manager = TimeSlotManager.shared
            let totalStand = TimeSlot.allCases.reduce(0) { acc, slot in
                guard let goal = manager.settings.goalFor(slot), goal.standGoal.enabled else { return acc }
                return acc + (manager.progress.progressFor(slot)?.standCompleted ?? 0)
            }
            let totalStandGoal = TimeSlot.allCases.filter {
                manager.settings.goalFor($0)?.standGoal.enabled == true
            }.count

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
                    totalDrinkGoal: totalDrinkGoal,
                    totalStand: totalStand,
                    totalStandGoal: totalStandGoal
                )
            }
        }

        // フォールバック: UserDefaults にデータがない場合はリアルタイム計算
        let timeSlotManager = TimeSlotManager.shared
        await timeSlotManager.loadTodaySettings()
        await timeSlotManager.loadTodayProgress()
        var totalTraining = 0
        var totalTrainingGoal = 0
        var totalMindfulness = 0
        var totalMindfulnessGoal = 0
        var totalMealLogged = 0
        var totalMealGoal = 0
        var totalDrinkLogged = 0
        var totalDrinkGoal = 0
        var totalStandFallback = 0
        var totalStandGoalFallback = 0

        for slot in TimeSlot.allCases {
            if let goal = timeSlotManager.settings.goalFor(slot),
               let progress = timeSlotManager.progress.progressFor(slot) {
                // 永続化されたTimeSlot進捗を使用（Firestore依存より正確）
                totalTraining += progress.trainingCompleted
                totalTrainingGoal += goal.trainingGoal
                // マインドフルネスは分換算（瞑想1回=1分、ストレッチ1セット=3分、ポモドーロ1回=20分）
                totalMindfulness += progress.mindfulnessCompleted * 1 + progress.stretchSetsCompleted * 3 + progress.standCompleted * 20
                let standGoalMinutes = (goal.standGoal.enabled && goal.timeSlot != .midnight) ? 20 : 0
                totalMindfulnessGoal += goal.mindfulnessGoal + standGoalMinutes
                if goal.logGoal.mealGoal > 0 {
                    totalMealGoal += goal.logGoal.mealGoal
                    totalMealLogged += progress.logProgress.mealLogged
                }
                if goal.logGoal.drinkGoal > 0 {
                    totalDrinkGoal += goal.logGoal.drinkGoal
                    totalDrinkLogged += progress.logProgress.drinkLogged
                }
                if goal.standGoal.enabled {
                    totalStandGoalFallback += 1
                    totalStandFallback += progress.standCompleted
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
            totalDrinkGoal: totalDrinkGoal,
            totalStand: totalStandFallback,
            totalStandGoal: totalStandGoalFallback
        )
    }

    // iOS → Watch: 更新後の数値を送信
    private func sendStatsToWatch(streak: Int, todayReps: Int, todayXP: Int, todaySets: Int = 0, todayExercises: [CompletedExercise] = [], force: Bool = false) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        // フェッチ前デバウンス: payload 構築には Firestore/HealthKit の重い読み取りが多数伴う。
        // force でない連続呼び出しは末尾の1回に集約し、無駄なフェッチ自体を回避する。
        if !force {
            let now = Date()
            if let lastFetch = lastStatsFetchTime,
               now.timeIntervalSince(lastFetch) < statsDebounceInterval {
                pendingStatsTask?.cancel()
                let delay = statsDebounceInterval - now.timeIntervalSince(lastFetch)
                pendingStatsTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    guard !Task.isCancelled, let self else { return }
                    self.pendingStatsTask = nil
                    self.sendStatsToWatch(streak: streak, todayReps: todayReps, todayXP: todayXP,
                                          todaySets: todaySets, todayExercises: todayExercises, force: false)
                }
                return
            }
            lastStatsFetchTime = now
            pendingStatsTask?.cancel()
            pendingStatsTask = nil
        } else {
            lastStatsFetchTime = Date()
        }

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
            payload["totalStand"] = timeSlotProgress.totalStand
            payload["totalStandGoal"] = timeSlotProgress.totalStandGoal

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

            dlog("[iOSWatchBridge] 📤 Sending intake data to Watch: cal=\(summary.intakeCalories), water=\(summary.intakeWaterMl)ml, caffeine=\(summary.intakeCaffeineMg)mg, alcohol=\(String(format: "%.1f", summary.intakeAlcoholG))g")

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

            // Plus状態を含める（Watch側のゲート制御に使用）
            payload["isPlus"] = PlusManager.shared.isPlus

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

            dlog("[iOSWatchBridge] 📤 Sending HealthKit data to Watch: steps=\(Int(healthKit.todaySteps)), cal=\(Int(healthKit.todayTotalCalories)), workout=\(healthKit.todayWorkoutMinutes), mindfulness=\(healthKit.todayMindfulnessSessions)")

            let signature = self.statsPayloadSignature(for: payload)
            if !force,
               let lastSend = self.lastStatsSendTime,
               Date().timeIntervalSince(lastSend) < self.statsDebounceInterval,
               signature == self.lastStatsPayloadSignature {
                dlog("[iOSWatchBridge] Stats送信スキップ（デバウンス）")
                return
            }
            if !force, signature == self.lastStatsPayloadSignature {
                dlog("[iOSWatchBridge] Stats送信スキップ（差分なし）")
                return
            }
            self.lastStatsPayloadSignature = signature
            self.lastStatsSendTime = Date()

            if session.isReachable {
                session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
            } else {
                try? session.updateApplicationContext(payload)
            }

            // コンプリケーション更新: 重要な指標のみ高優先度で送信
            self.transferComplicationStats(session: session)
        }
    }

    /// Watch コンプリケーション専用の軽量データを高優先度で転送する
    /// transferCurrentComplicationUserInfo は1日50件の上限があるため
    /// 軽量なペイロード（watch_* 相当値のみ）を送る
    private func transferComplicationStats(session: WCSession) {
        guard session.activationState == .activated else { return }
        guard session.isComplicationEnabled else { return }

        if let ud = UserDefaults(suiteName: "group.com.kfit.app") {
            let complicationPayload: [String: Any] = [
                "complication_update": true,
                "watch_totalTraining":      ud.integer(forKey: "trainingCompleted"),
                "watch_totalTrainingGoal":  ud.integer(forKey: "trainingGoal"),
                "watch_totalMindfulness":   ud.integer(forKey: "mindfulnessCompleted"),
                "watch_totalMindfulnessGoal": ud.integer(forKey: "mindfulnessGoal"),
                "watch_totalMeal":          ud.integer(forKey: "mealLogged"),
                "watch_totalMealGoal":      ud.integer(forKey: "mealGoal"),
            ]
            session.transferCurrentComplicationUserInfo(complicationPayload)
            dlog("[iOSWatchBridge] 📲 Transferred complication stats to Watch")
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

    // MARK: - iOS → Watch: フィード投稿送信
    private func sendFeedToWatch() async {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }

        // 自分の投稿（EduLogManager）
        var items: [WatchFeedItemForTransfer] = EduLogManager.shared.history.prefix(20).map {
            WatchFeedItemForTransfer(
                id: $0.id,
                timestamp: $0.timestamp,
                activityName: $0.activityName,
                activityEmoji: $0.activityEmoji,
                comment: $0.comment,
                authorName: $0.authorName.isEmpty
                    ? (AuthenticationManager.shared.userProfile?.username ?? "Me") : $0.authorName,
                likeCount: $0.likeCount,
                calories: $0.calories,
                isOwn: true
            )
        }

        // 友達の投稿（Firestore から直近7日間を最大20件取得）
        if let uid = Auth.auth().currentUser?.uid {
            let friendItems = await fetchFriendFeedForWatch(uid: uid)
            items.append(contentsOf: friendItems)
        }

        items.sort { $0.timestamp > $1.timestamp }
        let payload30 = Array(items.prefix(30))
        guard let data = try? JSONEncoder().encode(payload30) else { return }
        session.sendMessage(["feedItems": data], replyHandler: nil, errorHandler: nil)
        dlog("[iOSWatchBridge] 📤 フィード \(payload30.count) 件を Watch に送信")
    }

    private func fetchFriendFeedForWatch(uid: String) async -> [WatchFeedItemForTransfer] {
        let db = Firestore.firestore()
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()

        let friendIds: [String]
        do {
            let snap = try await db.collection("friendships")
                .whereField("members", arrayContains: uid)
                .getDocuments()
            friendIds = snap.documents.compactMap { doc -> String? in
                let members = doc.data()["members"] as? [String] ?? []
                return members.first(where: { $0 != uid })
            }
        } catch {
            dlog("[iOSWatchBridge] 友達ID取得失敗: \(error)")
            return []
        }
        guard !friendIds.isEmpty else { return [] }

        var result: [WatchFeedItemForTransfer] = []
        for fid in friendIds.prefix(5) {
            guard let snap = try? await db.collection("publicProfiles").document(fid)
                .collection("posts")
                .whereField("timestamp", isGreaterThan: Timestamp(date: cutoff))
                .order(by: "timestamp", descending: true)
                .limit(to: 10)
                .getDocuments() else { continue }
            for doc in snap.documents {
                let d = doc.data()
                result.append(WatchFeedItemForTransfer(
                    id: "friend_\(fid)_\(doc.documentID)",
                    timestamp: (d["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
                    activityName: d["activityName"] as? String ?? "",
                    activityEmoji: d["activityEmoji"] as? String ?? "",
                    comment: d["comment"] as? String ?? "",
                    authorName: d["authorName"] as? String ?? "TOMO",
                    likeCount: d["likeCount"] as? Int ?? 0,
                    calories: d["calories"] as? Int,
                    isOwn: false
                ))
            }
        }
        return result
    }

    private func buildWatchFaceTasks() async -> [WatchFaceTaskConfigForWatch] {
        // M4: 毎呼び出しで全 HK+Firestore 同期を走らせないよう変更。
        // 設定はキャッシュ済みのインメモリ状態を参照するだけにし、
        // 呼び出し元が必要に応じて loadTodayProgress を事前に呼ぶ。
        let timeSlotManager = TimeSlotManager.shared

        let settings = timeSlotManager.settings
        let prog = timeSlotManager.progress
        let activeSlots: [TimeSlot] = [.morning, .noon, .afternoon, .evening]

        // 1日合計を事前集計（iOS buildNodes() と同じロジック）
        var totalTrainingCompleted = 0, totalTrainingGoal = 0
        var totalMindfulMinutes = 0, totalMindfulnessGoal = 0
        var totalMealLogged = 0, totalMealGoal = 0
        var totalDrinkLogged = 0, totalDrinkGoal = 0
        var dailyStandDone = false
        var completedActivityNames: Set<String> = []

        for slot in activeSlots {
            guard let goal = settings.goalFor(slot), let p = prog.progressFor(slot) else { continue }
            totalTrainingCompleted += p.trainingCompleted
            totalTrainingGoal += goal.trainingGoal
            totalMindfulMinutes += p.mindfulnessCompleted * 1 + p.stretchSetsCompleted * 3
            totalMindfulnessGoal += goal.mindfulnessGoal
            totalMealLogged += p.logProgress.mealLogged
            totalMealGoal += goal.logGoal.mealGoal
            totalDrinkLogged += p.logProgress.drinkLogged
            totalDrinkGoal += goal.logGoal.drinkGoal
            if goal.standGoal.enabled && p.standCompleted >= 1 { dailyStandDone = true }
            for activity in goal.customActivities where activity.isEnabled && p.completedActivityIds.contains(activity.id) {
                completedActivityNames.insert(activity.name)
            }
        }

        let dailyTrainingDone    = totalTrainingGoal > 0    && totalTrainingCompleted >= totalTrainingGoal
        let dailyMindfulnessDone = totalMindfulnessGoal > 0 && totalMindfulMinutes    >= totalMindfulnessGoal
        let dailyMealDone        = totalMealGoal > 0        && totalMealLogged        >= totalMealGoal
        let dailyDrinkDone       = totalDrinkGoal > 0       && totalDrinkLogged       >= totalDrinkGoal

        var tasks: [WatchFaceTaskConfigForWatch] = []

        for slot in activeSlots {
            guard let goal = settings.goalFor(slot),
                  let p = prog.progressFor(slot) else { continue }
            let prefix = slot.rawValue

            if goal.trainingGoal > 0 {
                for i in 1...goal.trainingGoal {
                    tasks.append(WatchFaceTaskConfigForWatch(
                        id: "\(prefix)-training-\(i)",
                        emoji: "💪",
                        color: "training",
                        isDone: dailyTrainingDone || p.trainingCompleted >= i,
                        actionType: "training",
                        mealSubtype: nil,
                        intakeMessage: ""
                    ))
                }
            }

            if goal.mindfulnessGoal > 0 {
                let slotMindfulMinutes = p.mindfulnessCompleted * 1 + p.stretchSetsCompleted * 3
                tasks.append(WatchFaceTaskConfigForWatch(
                    id: "\(prefix)-mindfulness",
                    emoji: "🧘",
                    color: "mind",
                    isDone: dailyMindfulnessDone || slotMindfulMinutes >= goal.mindfulnessGoal,
                    actionType: "mindfulness",
                    mealSubtype: nil,
                    intakeMessage: ""
                ))
            }

            if goal.standGoal.enabled {
                tasks.append(WatchFaceTaskConfigForWatch(
                    id: "\(prefix)-stand",
                    emoji: "🧍",
                    color: "stand",
                    isDone: dailyStandDone || p.standCompleted >= 1,
                    actionType: "stand",
                    mealSubtype: nil,
                    intakeMessage: ""
                ))
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
                let subtype: String = {
                    switch slot {
                    case .midnight:  return "snack"
                    case .morning:   return "breakfast"
                    case .noon:      return "lunch"
                    case .afternoon: return "snack"
                    case .evening:   return "dinner"
                    }
                }()
                tasks.append(WatchFaceTaskConfigForWatch(
                    id: "\(prefix)-meal",
                    emoji: mealEmoji,
                    color: "meal",
                    isDone: dailyMealDone || p.logProgress.mealLogged >= goal.logGoal.mealGoal,
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
                    isDone: dailyDrinkDone || p.logProgress.drinkLogged >= goal.logGoal.drinkGoal,
                    actionType: "water",
                    mealSubtype: nil,
                    intakeMessage: "\(slot.displayName)の水分を追加しますか？"
                ))
            }

            for activity in goal.customActivities.filter({ $0.isEnabled }) {
                tasks.append(WatchFaceTaskConfigForWatch(
                    id: "\(prefix)-custom-\(activity.id)",
                    emoji: activity.emoji,
                    color: "custom",
                    isDone: completedActivityNames.contains(activity.name) || p.completedActivityIds.contains(activity.id),
                    actionType: "custom",
                    mealSubtype: nil,
                    intakeMessage: ""
                ))
            }
        }

        // 睡眠・体重グローバルノード
        if let fixedData = UserDefaults.standard.data(forKey: "dailyFixedGoals_v1"),
           let fixed = try? JSONDecoder().decode(DailyFixedGoals.self, from: fixedData) {
            let gp = prog.globalProgress
            if fixed.sleepEnabled {
                tasks.append(WatchFaceTaskConfigForWatch(
                    id: "global-sleep",
                    emoji: "😴",
                    color: "custom",
                    isDone: gp.sleepHours >= Double(fixed.sleepHoursGoal) || gp.sleepScore >= settings.globalGoals.sleepScoreThreshold,
                    actionType: "custom",
                    mealSubtype: nil,
                    intakeMessage: ""
                ))
            }
            if fixed.weightEnabled {
                tasks.append(WatchFaceTaskConfigForWatch(
                    id: "global-weight",
                    emoji: "⚖️",
                    color: "custom",
                    isDone: gp.weightMeasured,
                    actionType: "custom",
                    mealSubtype: nil,
                    intakeMessage: ""
                ))
            }
            for cg in fixed.customGoals {
                tasks.append(WatchFaceTaskConfigForWatch(
                    id: "daily-\(cg.id.uuidString)",
                    emoji: cg.emoji,
                    color: "custom",
                    isDone: gp.completedCustomGoalIds.contains("daily_custom_\(cg.id.uuidString)"),
                    actionType: "custom",
                    mealSubtype: nil,
                    intakeMessage: ""
                ))
            }
        }

        // 曜日別カスタム目標
        let weekdayNum: Int = {
            let wd = Calendar.current.component(.weekday, from: Date())
            return wd == 1 ? 7 : wd - 1
        }()
        if let data = UserDefaults.standard.data(forKey: "weekdayGoals_v1"),
           let wdGoals = try? JSONDecoder().decode([WeekdayGoal].self, from: data),
           let wg = wdGoals.first(where: { $0.weekday == weekdayNum && $0.hasAnyGoal }) {
            let gp = prog.globalProgress
            if wg.studyEnabled {
                tasks.append(WatchFaceTaskConfigForWatch(
                    id: "wd-study",
                    emoji: "📚",
                    color: "custom",
                    isDone: gp.completedCustomGoalIds.contains("wd_study_\(weekdayNum)"),
                    actionType: "custom",
                    mealSubtype: nil,
                    intakeMessage: ""
                ))
            }
            if wg.noAlcoholEnabled {
                tasks.append(WatchFaceTaskConfigForWatch(
                    id: "wd-noalcohol",
                    emoji: "🚫",
                    color: "custom",
                    isDone: gp.completedCustomGoalIds.contains("wd_noalcohol_\(weekdayNum)"),
                    actionType: "custom",
                    mealSubtype: nil,
                    intakeMessage: ""
                ))
            }
            for cg in wg.customGoals {
                tasks.append(WatchFaceTaskConfigForWatch(
                    id: "wd-\(cg.id.uuidString)",
                    emoji: cg.emoji,
                    color: "custom",
                    isDone: gp.completedCustomGoalIds.contains("wd_\(cg.id.uuidString)"),
                    actionType: "custom",
                    mealSubtype: nil,
                    intakeMessage: ""
                ))
            }
        }

        return Array(tasks.prefix(40))
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
    /// Watch 側で HKWorkout を Health に直接書き込み済みか（iPhone 側の重複書き込み回避用）
    var savedToHealth: Bool? = nil
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
    let totalStand: Int
    let totalStandGoal: Int
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

/// Watch に送信するフィード投稿アイテム（iOS 側で構築）
struct WatchFeedItemForTransfer: Codable {
    let id: String
    let timestamp: Date
    let activityName: String
    let activityEmoji: String
    let comment: String
    let authorName: String
    let likeCount: Int
    let calories: Int?
    let isOwn: Bool
}
