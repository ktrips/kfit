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

        // 目標カロリー情報を取得して送信
        Task {
            let calorieGoal = await AuthenticationManager.shared.getDailyCalorieGoal()
            payload["calorieTarget"] = calorieGoal.targetCalories
            payload["calorieConsumed"] = calorieGoal.consumedCalories
            payload["caloriePercent"] = calorieGoal.percentAchieved

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
struct WatchSetData: Codable {
    struct Exercise: Codable {
        let exerciseId: String
        let exerciseName: String
        let reps: Int
        let points: Int
    }
    let exercises: [Exercise]
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
