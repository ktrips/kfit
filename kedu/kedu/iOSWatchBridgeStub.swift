import Foundation

// MARK: - Watch Data Models (kedu stub)
// kedu は Watch / HealthKit と連携しません。
// AuthenticationManager など共有ファイルが参照する型定義のみ提供します。

struct WatchWorkoutData: Codable {
    let exerciseId: String
    let exerciseName: String
    let reps: Int
    let points: Int
    let timestamp: Date
}

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
    var savedToHealth: Bool? = nil
}

struct CompletedExerciseForWatch: Codable {
    let exerciseId: String
    let exerciseName: String
    let reps: Int
    let points: Int
    let timestamp: Date
}

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
}

// MARK: - iOSWatchBridge (no-op stub)
// kedu は Watch と連携しないため、全メソッドは no-op です。

@MainActor
final class iOSWatchBridge {
    static let shared = iOSWatchBridge()
    private init() {}

    static var isWatchAutoLaunchEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "watchAutoLaunchEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "watchAutoLaunchEnabled") }
    }

    func activate() {}
    func sendPlusStatusToWatch(isPlus: Bool) {}
    func sendStartWorkoutSignal() {}
    func notifyWatchAfterDirectRecord() {}
}
