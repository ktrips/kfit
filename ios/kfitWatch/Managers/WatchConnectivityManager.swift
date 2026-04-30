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

    // MARK: - Watch → iOS: ワークアウト送信
    func sendWorkout(_ workout: WorkoutData) {
        guard let session = session, session.isReachable else {
            // リーチ不可の場合はアプリコンテキストで送信（後で処理）
            sendWorkoutViaContext(workout)
            return
        }

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(workout)
            // "workout_recorded": true を付与し iPhone 側で通知キャンセルを識別
            session.sendMessage(["workout": data, "workout_recorded": true], replyHandler: nil) { error in
                print("WatchConnectivity sendMessage error: \(error)")
            }
        } catch {
            print("Error encoding workout: \(error)")
        }
    }

    private func sendWorkoutViaContext(_ workout: WorkoutData) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(workout)
            try session?.updateApplicationContext(["pendingWorkout": data])
        } catch {
            print("Error sending workout via context: \(error)")
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
    let exerciseName: String
    let reps: Int
    let points: Int
    let timestamp: Date
}
