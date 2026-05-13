import WatchConnectivity
import Foundation

@MainActor
class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()

    @Published var lastWorkout: WorkoutData?

    // Watch側でリアルタイム表示するデータ（統一指標）
    @Published var streak: Int = 0
    @Published var todayXP: Int = 0
    @Published var todayReps: Int = 0
    @Published var recentWorkouts: [String] = []
    @Published var todayExercises: [CompletedExerciseWatch] = []

    // 統一指標用（時間帯別の進捗）
    @Published var totalTraining: Int = 0
    @Published var totalTrainingGoal: Int = 0
    @Published var totalMindfulness: Int = 0
    @Published var totalMindfulnessGoal: Int = 0
    @Published var totalMealLogged: Int = 0
    @Published var totalMealGoal: Int = 0
    @Published var totalDrinkLogged: Int = 0
    @Published var totalDrinkGoal: Int = 0

    // 後方互換性のため残す
    @Published var todaySetCount: Int = 0
    @Published var dailySetGoal: Int = 2

    // モーション感度設定
    @Published var motionSensitivity: [String: (threshold: Double, minInterval: Double)] = [:]

    // 目標カロリー
    @Published var calorieTarget: Int = 500
    @Published var calorieConsumed: Int = 0
    @Published var caloriePercent: Int = 0

    // 摂取データ
    @Published var intakeCalories: Int = 0
    @Published var intakeCaloriesGoal: Int = 1800
    @Published var intakeWater: Int = 0
    @Published var intakeWaterGoal: Int = 1000
    @Published var intakeCaffeine: Int = 0
    @Published var intakeCaffeineLimit: Int = 400
    @Published var intakeAlcohol: Double = 0.0
    @Published var intakeAlcoholLimit: Double = 20.0

    // 摂取記録のデフォルト設定
    @Published var breakfastCalories: Int = 400
    @Published var lunchCalories: Int = 600
    @Published var dinnerCalories: Int = 800
    @Published var waterPerCup: Int = 200
    @Published var coffeePerCup: Int = 150
    @Published var caffeinePerCup: Int = 90
    @Published var beerAlcoholG: Double = 14.0
    @Published var wineAlcoholG: Double = 11.5
    @Published var chuhaiAlcoholG: Double = 19.6

    // ログ入力状態
    @Published var todayMealLogged: Bool = false

    /// iOS アプリ起動シグナルを受信したら true になる → WatchDashboardView が自動遷移
    @Published var shouldAutoStartWorkout: Bool = false

    /// データロード中かどうか
    @Published var isLoading: Bool = false

    /// データロード済みフラグ（初回データ取得成功）
    @Published var hasLoadedData: Bool = false

    private var session: WCSession?

    override init() {
        super.init()
        setupWatchConnectivity()
    }

    private func setupWatchConnectivity() {
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    // MARK: - Watch → iOS: 種目ごとの送信（通知キャンセル用）
    func sendWorkout(_ workout: WorkoutData) {
        guard let session = session, session.isReachable else {
            sendWorkoutViaContext(workout)
            return
        }
        guard let data = try? JSONEncoder().encode(workout) else { return }
        session.sendMessage(
            ["workout": data, "workout_recorded": true],
            replyHandler: nil
        ) { error in print("WatchConnectivity sendMessage error: \(error)") }
    }

    private func sendWorkoutViaContext(_ workout: WorkoutData) {
        guard let data = try? JSONEncoder().encode(workout) else { return }
        try? session?.updateApplicationContext(["pendingWorkout": data])
    }

    // MARK: - Watch → iOS: セット完了（全種目まとめて送信）
    func sendCompletedSet(_ set: WatchSetData) {
        guard let data = try? JSONEncoder().encode(set) else { return }
        if let session = session, session.isReachable {
            session.sendMessage(["completed_set": data], replyHandler: nil) { error in
                print("WatchConnectivity sendCompletedSet error: \(error)")
            }
        } else {
            try? session?.updateApplicationContext(["pendingCompletedSet": data])
        }
    }

    // MARK: - Watch → iOS: 摂取記録
    func sendIntakeRecord(type: String, subtype: String? = nil) {
        guard let session = session else { return }
        var message: [String: Any] = ["action": "record_intake", "type": type]
        if let subtype = subtype {
            message["subtype"] = subtype
        }
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                print("WatchConnectivity sendIntakeRecord error: \(error)")
            }
        } else {
            try? session.updateApplicationContext(message)
        }
    }

    // MARK: - iOS → Watch: stats リクエスト
    func requestStatsFromiOS() {
        guard let session = session else {
            // セッションがない場合はデフォルト値で表示開始
            isLoading = false
            hasLoadedData = true
            return
        }

        isLoading = true

        guard session.isReachable else {
            // iOSアプリが起動していない場合は5秒でタイムアウト
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                if self?.isLoading == true {
                    self?.isLoading = false
                    self?.hasLoadedData = true
                }
            }
            return
        }

        session.sendMessage(["action": "request_stats"], replyHandler: nil) { [weak self] error in
            Task { @MainActor in
                self?.isLoading = false
                self?.hasLoadedData = true
            }
        }

        // タイムアウト保険（10秒）
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            if self?.isLoading == true {
                self?.isLoading = false
                self?.hasLoadedData = true
            }
        }
    }

    // MARK: - 今日の記録に追加（Watch側UI更新）
    func addRecentWorkout(_ text: String) {
        recentWorkouts.insert(text, at: 0)
        if recentWorkouts.count > 5 {
            recentWorkouts.removeLast()
        }
    }

    // MARK: - iOS → Watch: プロフィール更新受信
    private func handleProfileUpdate(_ message: [String: Any]) {
        if let streak = message["streak"] as? Int { self.streak = streak }
        if let xp    = message["todayXP"] as? Int { self.todayXP = xp }
        if let reps  = message["todayReps"] as? Int { self.todayReps = reps }

        // 統一指標用データ受信（時間帯別の進捗）
        if let val = message["totalTraining"] as? Int { self.totalTraining = val }
        if let val = message["totalTrainingGoal"] as? Int { self.totalTrainingGoal = val }
        if let val = message["totalMindfulness"] as? Int { self.totalMindfulness = val }
        if let val = message["totalMindfulnessGoal"] as? Int { self.totalMindfulnessGoal = val }
        if let val = message["totalMealLogged"] as? Int { self.totalMealLogged = val }
        if let val = message["totalMealGoal"] as? Int { self.totalMealGoal = val }
        if let val = message["totalDrinkLogged"] as? Int { self.totalDrinkLogged = val }
        if let val = message["totalDrinkGoal"] as? Int { self.totalDrinkGoal = val }

        // 後方互換性のため残す
        if let setCount = message["todaySetCount"] as? Int { self.todaySetCount = setCount }
        if let setGoal = message["dailySetGoal"] as? Int { self.dailySetGoal = setGoal }

        // モーション感度設定を受信
        if let sensitivityData = message["motionSensitivity"] as? Data {
            if let sensitivityArray = try? JSONSerialization.jsonObject(with: sensitivityData) as? [[String: Any]] {
                var newSensitivity: [String: (threshold: Double, minInterval: Double)] = [:]
                for item in sensitivityArray {
                    if let exerciseId = item["exerciseId"] as? String,
                       let threshold = item["threshold"] as? Double,
                       let minInterval = item["minInterval"] as? Double {
                        newSensitivity[exerciseId] = (threshold, minInterval)
                    }
                }
                self.motionSensitivity = newSensitivity
                print("🔵 WatchConnectivity: Received motion sensitivity for \(newSensitivity.keys.joined(separator: ", "))")
            }
        }

        // 目標カロリー受信
        if let target = message["calorieTarget"] as? Int { self.calorieTarget = target }
        if let consumed = message["calorieConsumed"] as? Int { self.calorieConsumed = consumed }
        if let percent = message["caloriePercent"] as? Int { self.caloriePercent = percent }

        // 今日の運動記録を受信
        if let exercisesData = message["todayExercises"] as? Data {
            do {
                let exercises = try JSONDecoder().decode([CompletedExerciseWatch].self, from: exercisesData)
                self.todayExercises = exercises

                // recentWorkouts も更新（下位互換性のため）
                self.recentWorkouts = exercises.map { ex in
                    "\(exerciseEmoji(ex.exerciseId)) \(ex.exerciseName): \(ex.reps)回"
                }
            } catch {
                print("⚠️ todayExercises decode error: \(error)")
            }
        }

        // 摂取データを受信
        if let val = message["intakeCalories"] as? Int {
            self.intakeCalories = val
            print("📊 Watch: Received intakeCalories = \(val)")
        }
        if let val = message["intakeCaloriesGoal"] as? Int { self.intakeCaloriesGoal = val }
        if let val = message["intakeWater"] as? Int {
            self.intakeWater = val
            print("💧 Watch: Received intakeWater = \(val)")
        }
        if let val = message["intakeWaterGoal"] as? Int { self.intakeWaterGoal = val }
        if let val = message["intakeCaffeine"] as? Int {
            self.intakeCaffeine = val
            print("☕ Watch: Received intakeCaffeine = \(val)")
        }
        if let val = message["intakeCaffeineLimit"] as? Int { self.intakeCaffeineLimit = val }
        if let val = message["intakeAlcohol"] as? Double {
            self.intakeAlcohol = val
            print("🍺 Watch: Received intakeAlcohol = \(val)")
        }
        if let val = message["intakeAlcoholLimit"] as? Double { self.intakeAlcoholLimit = val }
        if let val = message["todayMealLogged"] as? Bool { self.todayMealLogged = val }

        // 摂取記録のデフォルト設定を受信
        if let val = message["breakfastCalories"] as? Int { self.breakfastCalories = val }
        if let val = message["lunchCalories"] as? Int { self.lunchCalories = val }
        if let val = message["dinnerCalories"] as? Int { self.dinnerCalories = val }
        if let val = message["waterPerCup"] as? Int { self.waterPerCup = val }
        if let val = message["coffeePerCup"] as? Int { self.coffeePerCup = val }
        if let val = message["caffeinePerCup"] as? Int { self.caffeinePerCup = val }
        if let val = message["beerAlcoholG"] as? Double { self.beerAlcoholG = val }
        if let val = message["wineAlcoholG"] as? Double { self.wineAlcoholG = val }
        if let val = message["chuhaiAlcoholG"] as? Double { self.chuhaiAlcoholG = val }

        // データ受信完了
        isLoading = false
        hasLoadedData = true
    }

    private func exerciseEmoji(_ id: String) -> String {
        let map: [String: String] = [
            "pushup": "💪", "push-up": "💪",
            "squat": "🏋️", "situp": "🔥", "sit-up": "🔥",
            "lunge": "🦵", "burpee": "⚡", "plank": "🧘"
        ]
        for (key, emoji) in map {
            if id.lowercased().contains(key) { return emoji }
        }
        return "🏃"
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error = error {
            print("WCSession activation error: \(error)")
        }
    }

    // Watch からメッセージ受信（iOS側）/ iOS からメッセージ受信（Watch側）
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            // iOS アプリ起動シグナル → ワークアウト自動開始
            if (message["action"] as? String) == "start_workout" {
                self.shouldAutoStartWorkout = true
                return
            }

            if let workoutData = message["workout"] as? Data {
                do {
                    let decoder = JSONDecoder()
                    let workout = try decoder.decode(WorkoutData.self, from: workoutData)
                    self.lastWorkout = workout
                } catch {
                    print("Error decoding workout: \(error)")
                }
            }

            // プロフィール更新（Watch側）
            if message["streak"] != nil {
                self.handleProfileUpdate(message)
            }
        }
    }

    // アプリコンテキスト受信（バックグラウンド時のデータ同期）
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            // iOS アプリ起動シグナル（バックグラウンド経由）→ 次回 Watch 起動時に自動開始
            if (applicationContext["action"] as? String) == "start_workout" {
                self.shouldAutoStartWorkout = true
                return
            }

            if let workoutData = applicationContext["pendingWorkout"] as? Data {
                do {
                    let decoder = JSONDecoder()
                    let workout = try decoder.decode(WorkoutData.self, from: workoutData)
                    self.lastWorkout = workout
                } catch {
                    print("Error decoding pending workout: \(error)")
                }
            }

            if applicationContext["streak"] != nil {
                self.handleProfileUpdate(applicationContext)
            }

            // プロフィール更新（通常のstatsデータ）
            if applicationContext["intakeCalories"] != nil {
                print("📥 Watch: Received application context with intake data")
                self.handleProfileUpdate(applicationContext)
            }
        }
    }

    // Watch起動時に最新のApplicationContextを確認
    func checkLatestApplicationContext() {
        guard let session = session else { return }
        let context = session.receivedApplicationContext
        if !context.isEmpty {
            print("📥 Watch: Loading latest application context")
            Task { @MainActor in
                self.handleProfileUpdate(context)
            }
        }
    }
}

struct WorkoutData: Codable {
    let exerciseId: String
    let exerciseName: String
    let reps: Int
    let points: Int
    let timestamp: Date
}

// MARK: - セット完了データ（全種目をまとめて送る）
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

// MARK: - Watch用の完了記録
struct CompletedExerciseWatch: Codable, Identifiable, Hashable {
    var id: String { "\(exerciseId)-\(timestamp.timeIntervalSince1970)" }
    let exerciseId: String
    let exerciseName: String
    let reps: Int
    let points: Int
    let timestamp: Date
}
