import WatchConnectivity
import Foundation

@MainActor
class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()

    @Published var lastWorkout: WorkoutData?

    // Watch側でリアルタイム表示するデータ
    @Published var streak: Int = 0
    @Published var todayXP: Int = 0
    @Published var todayReps: Int = 0
    @Published var recentWorkouts: [String] = []
    @Published var todayExercises: [CompletedExerciseWatch] = []

    // 目標カロリー
    @Published var calorieTarget: Int = 500
    @Published var calorieConsumed: Int = 0
    @Published var caloriePercent: Int = 0

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
