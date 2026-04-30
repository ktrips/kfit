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
        guard message["workout"] != nil || message["workout_recorded"] != nil else { return }
        Task { @MainActor in
            print("[iOSWatchBridge] Watch からワークアウト受信 → 通知キャンセル処理")
            NotificationManager.shared.handleWorkoutRecorded()

            // Watch から生のワークアウトデータが届いた場合は Firestore にも記録
            if let workoutData = message["workout"] as? Data {
                let decoder = JSONDecoder()
                if let workout = try? decoder.decode(WatchWorkoutData.self, from: workoutData) {
                    await AuthenticationManager.shared.recordWatchWorkout(workout)
                }
            }
        }
    }

    // バックグラウンド時に届いたコンテキストも処理
    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard applicationContext["pendingWorkout"] != nil else { return }
        Task { @MainActor in
            NotificationManager.shared.handleWorkoutRecorded()

            if let workoutData = applicationContext["pendingWorkout"] as? Data {
                let decoder = JSONDecoder()
                if let workout = try? decoder.decode(WatchWorkoutData.self, from: workoutData) {
                    await AuthenticationManager.shared.recordWatchWorkout(workout)
                }
            }
        }
    }
}

/// Watch 側の WorkoutData と共通のシリアライズ構造
struct WatchWorkoutData: Codable {
    let exerciseName: String
    let reps: Int
    let points: Int
    let timestamp: Date
}
