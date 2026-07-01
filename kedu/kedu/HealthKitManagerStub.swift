import Foundation
import Combine

// MARK: - HealthKit Data Models (kedu stub)
// kedu は HealthKit と連携しません。共有ファイルが参照する型定義のみ提供します。

struct MindfulSession: Identifiable {
    let id = UUID()
    let startDate: Date
    let durationMinutes: Double
    let sourceName: String
    let sourceBundleId: String
    let sessionTypeHint: String?
    var averageHeartRate: Double = 0
    var averageHRV: Double = 0
    var sessionTypeLabel: String { sourceName }
    var sessionEmoji: String { "🧘" }
}

struct DietarySample: Identifiable {
    let id = UUID()
    let startDate: Date
    let value: Double
}

struct HRSample: Identifiable {
    let id   = UUID()
    let date: Date
    let bpm:  Double
}

struct HRVSample: Identifiable {
    let id    = UUID()
    let date:  Date
    let value: Double
}

struct DailyHRVAverage: Identifiable {
    let id    = UUID()
    let date:  Date
    let value: Double
}

struct WorkoutSession: Identifiable {
    let id = UUID()
    let startDate: Date
    let endDate: Date
    let durationMinutes: Double
    let activityName: String
    let emoji: String
    let calories: Double
    let sourceName: String
    let sourceBundleId: String
}

struct SleepSegment: Identifiable {
    let id    = UUID()
    let start: Date
    let end:   Date
    let stage: SleepStage
    var durationHours: Double { end.timeIntervalSince(start) / 3600 }

    enum SleepStage: String {
        case inBed = "就寝", core = "コア", deep = "深い睡眠"
        case rem = "REM", awake = "覚醒", unknown = "睡眠"
        var color: String {
            switch self {
            case .deep: return "#1CB0F6"; case .rem: return "#CE82FF"
            case .core: return "#58CC02"; case .awake: return "#FF4B4B"
            case .inBed: return "#AFAFAF"; case .unknown: return "#58CC02"
            }
        }
    }
}

struct SleepVitalsAnalysis {
    let averageHeartRate: Double
    let averageRespiratoryRate: Double
    let averageOxygenSaturation: Double
    let minimumOxygenSaturation: Double
    var hasData: Bool { false }
    var alertMessages: [String] { [] }
}

struct PFCBalanceAnalysis {
    let proteinPercent: Double; let fatPercent: Double; let carbsPercent: Double
    let proteinGrams: Double;   let fatGrams: Double;   let carbsGrams: Double
    let score: Int;             let rating: String
}

struct SleepScoreAnalysis {
    let totalHours: Double; let deepHours: Double; let remHours: Double; let coreHours: Double
    let score: Int;         let rating: String
    var durationScore: Int = 0; var bedtimeScore: Int = 0; var interruptionScore: Int = 0
    var firstSleepTime: Date? = nil; var awakeHours: Double = 0; var targetHours: Double = 7.0
}

struct DailyCalorieBalance: Identifiable {
    let id = UUID(); let date: Date; let burned: Double; let consumed: Double
    var bodyMass: Double?; var bodyFatPercentage: Double?; var steps: Int = 0
    var balance: Int { Int(consumed) - Int(burned) }
    private static let dayFmt: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.dateFormat = "E"; return f }()
    var dayLabel: String { Self.dayFmt.string(from: date) }
}

struct DailyBurnSummary: Identifiable {
    let id = UUID(); let date: Date
    var activeCalories: Double = 0; var restingCalories: Double = 0
    var exerciseMinutes: Double = 0; var setCount: Int = 0; var steps: Int = 0
    var totalCalories: Double { activeCalories + restingCalories }
    private static let dayFmt: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.dateFormat = "E"; return f }()
    var dayLabel: String { Self.dayFmt.string(from: date) }
}

struct BodyMassRecord: Identifiable {
    let id = UUID(); let measuredAt: Date; let kg: Double
}

// MARK: - HealthKitManager (no-op stub)
// kedu は HealthKit と連携しないため、全プロパティは初期値、全メソッドは no-op です。

@MainActor
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    // availability
    @Published var isAvailable = false
    @Published var isAuthorized = false
    @Published var isLoading = false

    // steps / calories
    @Published var todaySteps: Int = 0
    @Published var todayCalories: Double = 0
    @Published var todayActiveCalories: Double = 0
    @Published var todayRestingCalories: Double = 0
    @Published var todayTotalCalories: Double = 0

    // heart rate / HRV
    @Published var latestHeartRate: Double = 0
    @Published var restingHeartRate: Double = 0
    @Published var latestHRV: Double = 0
    @Published var todayAvgHeartRate: Double = 0
    @Published var todayAvgHRV: Double = 0
    @Published var hrSamples: [HRSample] = []
    @Published var hrvSamples: [HRVSample] = []
    @Published var weeklyHRVAverages: [DailyHRVAverage] = []

    // sleep
    @Published var lastNightTotalHours: Double = 0
    @Published var lastNightDeepHours: Double = 0
    @Published var sleepSegments: [SleepSegment] = []
    @Published var sleepVitals = SleepVitalsAnalysis(
        averageHeartRate: 0, averageRespiratoryRate: 0,
        averageOxygenSaturation: 0, minimumOxygenSaturation: 0)

    // body mass
    @Published var latestBodyMass: Double = 0
    @Published var latestBodyFatPercentage: Double = 0
    @Published var todayBodyMassMeasurements: Int = 0
    @Published var todayBodyMassRecord: BodyMassRecord? = nil
    @Published var weeklyBodyMassChange: Double? = nil
    @Published var weeklyBodyFatChange: Double? = nil
    @Published var bodyMassHistory: [BodyMassRecord] = []
    @Published var weeklyCalorieData: [DailyCalorieBalance] = []
    @Published var weeklyBurnData: [DailyBurnSummary] = []
    @Published var weeklyDietarySamples: [DietarySample] = []

    // intake
    @Published var todayIntakeCalories: Double = 0
    @Published var todayIntakeWater: Double = 0
    @Published var todayIntakeCaffeine: Double = 0
    @Published var todayIntakeAlcohol: Double = 0
    @Published var todayIntakeProtein: Double = 0
    @Published var todayIntakeFat: Double = 0
    @Published var todayIntakeCarbs: Double = 0

    // mindfulness
    @Published var todayMindfulnessMinutes: Double = 0
    @Published var todayMindfulnessSessions: Int = 0
    @Published var todayMindfulnessSamples: [MindfulSession] = []

    // samples
    @Published var todayWaterSamples: [DietarySample] = []
    @Published var todayMealSamples: [DietarySample] = []
    @Published var todayToothbrushingSamples: [Date] = []

    // workout / stand / daylight
    @Published var todayWorkoutMinutes: Int = 0
    @Published var todayWorkoutCount: Int = 0
    @Published var todayStandHours: Int = 0
    @Published var todayDaylightMinutes: Double = 0
    @Published var todayMindfulnessMinutesInt: Int = 0

    // activity rings
    @Published var activityMoveCalories: Double = 0
    @Published var activityMoveGoal: Double = 600
    @Published var activityExerciseMinutes: Int = 0
    @Published var activityExerciseGoal: Int = 30
    @Published var activityStandHours: Int = 0
    @Published var activityStandGoal: Int = 12

    // body fat history
    @Published var bodyFatHistory: [BodyFatRecord] = []

    // alias kept for backward compat
    @Published var weeklyCalories: [DailyCalorieBalance] = []
    @Published var weeklyBurn: [DailyBurnSummary] = []
    @Published var mindfulSessions: [MindfulSession] = []
    @Published var workoutSessions: [WorkoutSession] = []

    struct BodyFatRecord: Identifiable {
        let id = UUID(); let measuredAt: Date; let percent: Double
    }

    static let caloriesPerRep: [String: Double] = [
        "push_up": 0.35, "squat": 0.32, "sit_up": 0.25,
        "pushup": 0.35, "squat_jump": 0.40,
    ]

    private init() {}

    // MARK: - no-op methods

    func requestAuthorization() async {}
    func refreshAuthorizationStatus() {}
    func fetchAll(force: Bool = false) async {}
    func fetchDashboardHealth(force: Bool = false) async {}
    func fetchMindHealth(force: Bool = false) async {}
    func fetchGoalHealth(force: Bool = false) async {}
    func fetchIntakeHealth(force: Bool = false) async {}
    func fetchWatchSnapshotHealth(force: Bool = false) async {}
    func fetchTodayWorkout() async -> Int { 0 }
    func fetchTodayWorkoutSessions() async -> [WorkoutSession] { [] }
    func fetchTodayStand() async -> Int { 0 }
    func fetchTodayBodyMassMeasurements() async -> Int { 0 }
    func fetchTodayBodyMassRecord() async -> BodyMassRecord? { nil }
    func fetchBodyMassHistory(days: Int = 14) async {}
    func bodyMassRecord(for dateKey: String) -> BodyMassRecord? { nil }
    func fetchBodyFatHistory(days: Int = 30) async {}
    func fetchWeeklyBurnData() async {}
    func fetchWeeklyDietarySamples() async {}
    func fetchTodayMindfulness() async -> (minutes: Double, sessions: Int, samples: [MindfulSession]) { (0, 0, []) }
    func refreshMindfulness() async {}
    func fetchDietaryEnergyCalories(start: Date, end: Date) async -> Double { 0 }
    func saveDietaryEnergy(calories: Double, timestamp: Date, metadata: [String: Any]? = nil) async -> Bool { false }
    func saveExercise(exerciseId: String, reps: Int, startDate: Date, endDate: Date) async {}
    func saveCompletedSet(exercises: [(id: String, name: String, reps: Int)],
                          startDate: Date, setId: String? = nil) async {}
    func saveWaterIntake(amountMl: Double, timestamp: Date) async {}
    func saveCaffeineIntake(caffeineMg: Double, timestamp: Date) async {}
    func saveAlcoholIntake(amountMl: Double, alcoholG: Double, timestamp: Date) async {}
    func saveToothbrushing(durationSeconds: Double = 60, timestamp: Date = Date()) async {}
    func saveMindfulnessSession(startDate: Date, endDate: Date,
                                durationSeconds: Int,
                                sessionType: String) async -> Bool { false }
    func saveMealNutrition(_ nutrition: MealNutrition, date: Date = Date()) async {}
    func analyzeSleepScore(targetHours: Double = 7.0) -> SleepScoreAnalysis {
        SleepScoreAnalysis(totalHours: 0, deepHours: 0, remHours: 0, coreHours: 0, score: 0, rating: "-")
    }
    func analyzePFCBalance(settings: IntakeSettings = .defaultSettings) -> PFCBalanceAnalysis {
        PFCBalanceAnalysis(proteinPercent: 0, fatPercent: 0, carbsPercent: 0,
                           proteinGrams: 0, fatGrams: 0, carbsGrams: 0, score: 0, rating: "-")
    }
}
