import HealthKit
import Foundation

// MARK: - Data Models

struct MindfulSession: Identifiable {
    let id = UUID()
    let startDate: Date
    let durationMinutes: Double
    let sourceName: String
    let sourceBundleId: String
    let sessionTypeHint: String?
    var averageHeartRate: Double = 0
    var averageHRV: Double = 0

    /// ソースから判定した種別ラベル
    var sessionTypeLabel: String {
        if sessionTypeHint == "Breathe" { return "Breathe" }
        if sessionTypeHint == "Reflect" { return "Reflect" }
        if sessionTypeHint == "Stand" { return "Stand" }
        if durationMinutes >= 2.5 && durationMinutes <= 3.5 { return "Reflect" }
        let b = sourceBundleId.lowercased()
        let n = sourceName.lowercased()
        if b.contains("breathe") || n.contains("breathe") { return "Breathe" }
        if b.contains("reflect") || n.contains("reflect") { return "Reflect" }
        if b.contains("kfit") || n.contains("kfit") || n.contains("fitingo") || n.contains("duofit") { return "Breathe" }
        if b.contains("mindfulness") || b.contains("nanomindfulness") || n == "マインドフルネス" { return "マインドフルネス" }
        if b.contains("headspace") || n.contains("headspace") { return "Headspace" }
        if b.contains("calm") || n.contains("calm") { return "Calm" }
        return sourceName
    }

    var sessionEmoji: String {
        switch sessionTypeLabel {
        case "Breathe":         return "🧘"
        case "Reflect":         return "🤸"
        case "Stand":           return "🧍"
        case "マインドフルネス": return "🧘"
        case "Headspace":       return "🟠"
        case "Calm":            return "🌊"
        default:                return "🧘"
        }
    }
}

struct DietarySample: Identifiable {
    let id = UUID()
    let startDate: Date
    let value: Double  // ml (water) or kcal (meal)
}

struct HRSample: Identifiable {
    let id   = UUID()
    let date: Date
    let bpm:  Double
}

struct HRVSample: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

struct DailyHRVAverage: Identifiable {
    let id = UUID()
    let date: Date
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
        case inBed   = "就寝"
        case core    = "コア"
        case deep    = "深い睡眠"
        case rem     = "REM"
        case awake   = "覚醒"
        case unknown = "睡眠"

        var color: String {
            switch self {
            case .deep:    return "#1CB0F6"
            case .rem:     return "#CE82FF"
            case .core:    return "#58CC02"
            case .awake:   return "#FF4B4B"
            case .inBed:   return "#AFAFAF"
            case .unknown: return "#58CC02"
            }
        }
    }
}

/// PFCバランスの分析結果
struct PFCBalanceAnalysis {
    let proteinPercent: Double  // たんぱく質の割合（%）
    let fatPercent: Double       // 脂質の割合（%）
    let carbsPercent: Double     // 炭水化物の割合（%）
    let proteinGrams: Double     // たんぱく質の摂取量（g）
    let fatGrams: Double         // 脂質の摂取量（g）
    let carbsGrams: Double       // 炭水化物の摂取量（g）
    let score: Int               // バランススコア（0-100点）
    let rating: String           // 評価（理想的、良好、まずまず、要改善、バランス悪い）
}

/// 睡眠スコアの分析結果
struct SleepScoreAnalysis {
    let totalHours: Double       // 総睡眠時間（時間）
    let deepHours: Double        // 深い睡眠時間（時間）
    let remHours: Double         // REM睡眠時間（時間）
    let coreHours: Double        // コア睡眠時間（時間）
    let score: Int               // 睡眠スコア（0-100点）
    let rating: String           // 評価（最高、良好、普通、要改善、不十分）

    // スコア内訳（各コンポーネントの得点）
    var durationScore: Int = 0   // 睡眠時間スコア（最大50点）
    var bedtimeScore: Int = 0    // 就寝時刻スコア（最大30点）
    var interruptionScore: Int = 0 // 睡眠中断スコア（最大20点）

    // 内訳の元データ
    var firstSleepTime: Date? = nil  // 最初に眠った時刻
    var awakeHours: Double = 0       // 覚醒時間（時間）
    var targetHours: Double = 7.0    // 目標睡眠時間（時間）
}

struct SleepVitalsAnalysis {
    let averageHeartRate: Double
    let averageRespiratoryRate: Double
    let averageOxygenSaturation: Double
    let minimumOxygenSaturation: Double

    var hasData: Bool {
        averageHeartRate > 0 || averageRespiratoryRate > 0 || averageOxygenSaturation > 0 || minimumOxygenSaturation > 0
    }

    var alertMessages: [String] {
        var messages: [String] = []
        if averageHeartRate > 0 && (averageHeartRate < 40 || averageHeartRate > 100) {
            messages.append("睡眠中の心拍数が通常範囲から外れています")
        }
        if averageRespiratoryRate > 0 && (averageRespiratoryRate < 10 || averageRespiratoryRate > 24) {
            messages.append("睡眠中の呼吸数が通常範囲から外れています")
        }
        if minimumOxygenSaturation > 0 && minimumOxygenSaturation < 90 {
            messages.append("睡眠中の酸素レベルが90%未満まで低下しています")
        } else if averageOxygenSaturation > 0 && averageOxygenSaturation < 94 {
            messages.append("睡眠中の平均酸素レベルが低めです")
        }
        return messages
    }
}

// MARK: - 週間カロリー記録（日別）
struct DailyCalorieBalance: Identifiable {
    let id = UUID()
    let date: Date
    let burned: Double    // 消費カロリー（active + resting）
    let consumed: Double  // 摂取カロリー（dietaryEnergy）
    var bodyMass: Double?           // kg（その日の最新計測値、なければnil）
    var bodyFatPercentage: Double?  // %（その日の最新計測値、なければnil）
    var steps: Int = 0              // 歩数
    var balance: Int { Int(consumed) - Int(burned) }
    // LOW(M-8): DateFormatter を static let にキャッシュ
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "E"
        return f
    }()
    var dayLabel: String { Self.dayFmt.string(from: date) }
}

// MARK: - 週間消費カロリー記録（安静時・活動別）
struct DailyBurnSummary: Identifiable {
    let id = UUID()
    let date: Date
    var activeCalories: Double = 0
    var restingCalories: Double = 0
    var exerciseMinutes: Double = 0
    var setCount: Int = 0
    var steps: Int = 0
    var totalCalories: Double { activeCalories + restingCalories }
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "E"
        return f
    }()
    var dayLabel: String { Self.dayFmt.string(from: date) }
}

// MARK: - 体重記録（日別）
struct BodyMassRecord: Identifiable {
    let id = UUID()
    let measuredAt: Date   // 計測日時
    let kg: Double
}

// MARK: - HealthKitManager

/// Apple HealthKit から健康データを読み取る専用マネージャ
///
/// 取得データ:
///   - 歩数（今日）
///   - 消費カロリー（今日）
///   - 心拍数（最新値 + 今日のサンプル履歴）
///   - 安静時心拍数（最新値）
///   - 睡眠（昨夜の総時間 + ステージ別）
///
/// 使い方:
///   1. HealthKitManager.shared を @StateObject で取得
///   2. requestAuthorization() を非同期で呼ぶ
///   3. 許可後 fetchAll() でデータ更新
///
/// NOTE: Xcode プロジェクト設定が必要
///   - Target → Signing & Capabilities → "＋ HealthKit" を追加
///   - Info.plist に NSHealthShareUsageDescription を追加
@MainActor
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    // LOW(M-8): DateFormatter を static let にキャッシュ（毎呼び出しで生成しない）
    static let yyyyMMddFmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private let store = HKHealthStore()

    // MARK: - 公開状態

    @Published var isAvailable = HKHealthStore.isHealthDataAvailable()
    @Published var isAuthorized = false
    @Published var isLoading    = false

    // 今日のアクティビティ
    @Published var todaySteps:    Int    = 0
    @Published var todayCalories: Double = 0  // アクティブカロリー（後方互換性のため残す）
    @Published var todayActiveCalories: Double = 0   // アクティブカロリー
    @Published var todayRestingCalories: Double = 0  // 安静時カロリー（基礎代謝）
    @Published var todayTotalCalories: Double = 0    // 総消費カロリー（安静時＋アクティブ）

    // 心拍数
    @Published var latestHeartRate:   Double     = 0
    @Published var restingHeartRate:  Double     = 0
    @Published var latestHRV:         Double     = 0  // 心拍変動（ms）
    @Published var todayAvgHeartRate: Double     = 0  // 今日の平均心拍数
    @Published var todayAvgHRV:       Double     = 0  // 今日の平均HRV
    @Published var hrSamples:         [HRSample] = []
    @Published var hrvSamples:        [HRVSample] = []
    @Published var weeklyHRVAverages: [DailyHRVAverage] = []

    // 睡眠
    @Published var lastNightTotalHours: Double         = 0
    @Published var lastNightDeepHours:  Double         = 0
    @Published var sleepSegments:       [SleepSegment] = []
    @Published var sleepVitals = SleepVitalsAnalysis(
        averageHeartRate: 0,
        averageRespiratoryRate: 0,
        averageOxygenSaturation: 0,
        minimumOxygenSaturation: 0
    )

    // 体重・体脂肪
    @Published var latestBodyMass: Double = 0              // kg
    @Published var latestBodyFatPercentage: Double = 0     // %
    @Published var todayBodyMassMeasurements: Int = 0      // 今日の測定回数
    @Published var todayBodyMassRecord: BodyMassRecord? = nil  // 今日の体重計測（時刻付き）
    @Published var weeklyBodyMassChange: Double? = nil     // 1週間の体重変動（kg）nil=データ不足
    @Published var weeklyBodyFatChange: Double? = nil      // 1週間の体脂肪変動（%）nil=データ不足
    @Published var bodyMassHistory: [BodyMassRecord] = []  // 日別体重履歴
    @Published var weeklyCalorieData: [DailyCalorieBalance] = []  // 今週の日別カロリー収支
    @Published var weeklyBurnData: [DailyBurnSummary] = []       // 今週の日別消費カロリー内訳
    @Published var weeklyDietarySamples: [DietarySample] = []    // 今週の食事カロリーサンプル（タイムスタンプ付き）

    // 摂取データ（Apple Healthから読み取り）
    @Published var todayIntakeCalories: Double = 0      // kcal
    @Published var todayIntakeWater: Double = 0         // ml
    @Published var todayIntakeCaffeine: Double = 0      // mg
    @Published var todayIntakeAlcohol: Double = 0       // g（純アルコール）

    // PFC（たんぱく質・脂質・炭水化物）
    @Published var todayIntakeProtein: Double = 0       // g
    @Published var todayIntakeFat: Double = 0           // g
    @Published var todayIntakeCarbs: Double = 0         // g

    // マインドフルネス
    @Published var todayMindfulnessMinutes: Double = 0  // 今日のマインドフルネス時間（分）
    @Published var todayMindfulnessSessions: Int = 0    // 今日のマインドフルネスセッション数
    @Published var todayMindfulnessSamples: [MindfulSession] = []  // 個別セッション

    // 摂取サンプル（時刻付き）
    @Published var todayWaterSamples: [DietarySample] = []  // 水分サンプル（ml）
    @Published var todayMealSamples:  [DietarySample] = []  // 食事カロリーサンプル（kcal）
    @Published var todayToothbrushingSamples: [Date] = []   // 歯磨きイベント（終了時刻）
    private var previousMindfulnessSessions: Int = 0     // 前回のセッション数（差分検出用）
    private var lastFetchAllAt: Date? = nil
    private var lastScopedFetchAt: [String: Date] = [:]
    private let fetchAllTTL: TimeInterval = 20
    private var mindfulnessCacheResult: (minutes: Double, sessions: Int, samples: [MindfulSession])?
    private var mindfulnessCachedAt: Date?
    private let mindfulnessCacheTTL: TimeInterval = 30

    // ワークアウト
    @Published var todayWorkoutMinutes: Int = 0         // 今日のワークアウト時間（分）
    @Published var todayWorkoutCount: Int = 0           // 今日のワークアウト件数

    // スタンド時間
    @Published var todayStandHours: Int = 0             // 今日のスタンド時間（時間）

    // 日光下時間（iOS 17+）
    @Published var todayDaylightMinutes: Double = 0     // 今日の日光下時間（分）

    // アクティビティリング（Apple Watch / HealthKit）
    @Published var activityMoveCalories: Double = 0    // ムーブリング（アクティブカロリー）
    @Published var activityMoveGoal: Double = 600      // ムーブ目標（kcal）
    @Published var activityExerciseMinutes: Int = 0    // エクササイズリング（分）
    @Published var activityExerciseGoal: Int = 30      // エクササイズ目標（分）
    @Published var activityStandHours: Int = 0         // スタンドリング（時間）
    @Published var activityStandGoal: Int = 12         // スタンド目標（時間）

    // 日光露出時間（todayDaylightMinutes の別名）
    var todaySunlightExposure: Double { todayDaylightMinutes }

    // HRV平均（現状は最新値のみ取得のため latestHRV と同値）
    var todayAverageHRV: Double { latestHRV }

    // HRV ステータス文字列
    var hrvStatus: String {
        if latestHRV >= 60 { return "良好" }
        if latestHRV >= 40 { return "中程度" }
        if latestHRV > 0   { return "要注意" }
        return "—"
    }

    // MARK: - 権限セット

    private var readTypes: Set<HKObjectType> {
        var set = Set<HKObjectType>()
        let quantityIds: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .restingHeartRate,
            .heartRateVariabilitySDNN,  // 心拍変動
            .respiratoryRate,       // 呼吸数
            .oxygenSaturation,      // 血中酸素ウェルネス
            .stepCount,
            .activeEnergyBurned,
            .basalEnergyBurned,     // 安静時カロリー（基礎代謝）
            .appleExerciseTime,     // アクティブ運動時間
            .bodyMass,              // 体重
            .bodyFatPercentage,     // 体脂肪率
            .dietaryEnergyConsumed, // 摂取カロリー
            .dietaryWater,          // 水分
            .dietaryCaffeine,       // カフェイン
        ]
        for id in quantityIds {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { set.insert(t) }
        }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            set.insert(sleep)
        }
        if let mindfulness = HKCategoryType.categoryType(forIdentifier: .mindfulSession) {
            set.insert(mindfulness)
        }
        if let standHour = HKCategoryType.categoryType(forIdentifier: .appleStandHour) {
            set.insert(standHour)
        }
        // 日光下時間（iOS 17+）
        if #available(iOS 17.0, *) {
            if let daylightType = HKQuantityType.quantityType(forIdentifier: .timeInDaylight) {
                set.insert(daylightType)
            }
        }
        // ワークアウトタイプを追加
        set.insert(HKWorkoutType.workoutType())
        // アクティビティサマリー（アクティビティリング）
        set.insert(HKObjectType.activitySummaryType())
        return set
    }

    private var writeTypes: Set<HKSampleType> {
        var set = Set<HKSampleType>()
        let writeIds: [HKQuantityTypeIdentifier] = [
            .activeEnergyBurned,
            .dietaryEnergyConsumed,
            .dietaryWater,
            .dietaryCaffeine,
            .dietaryProtein,        // たんぱく質
            .dietaryFatTotal,       // 脂質
            .dietaryCarbohydrates,  // 炭水化物
            .dietarySugar,          // 糖質
            .dietaryFiber,          // 食物繊維
            .dietarySodium,         // ナトリウム（塩分）
            .numberOfAlcoholicBeverages, // 飲酒量（標準ドリンク数）
        ]
        for id in writeIds {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { set.insert(t) }
        }
        if let mindfulness = HKCategoryType.categoryType(forIdentifier: .mindfulSession) {
            set.insert(mindfulness)
        }
        if let toothbrushing = HKCategoryType.categoryType(forIdentifier: .toothbrushingEvent) {
            set.insert(toothbrushing)
        }
        set.insert(HKWorkoutType.workoutType())
        return set
    }

    // MARK: - 権限リクエスト

    func requestAuthorization() async {
        guard isAvailable else {
            print("[HealthKit] HealthKit not available on this device")
            return
        }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            isAuthorized = true
            print("[HealthKit] ✅ Authorization granted")
            await fetchAll()
        } catch {
            print("[HealthKit] ❌ 権限エラー: \(error.localizedDescription)")
        }
    }

    // MARK: - ワークアウト書き込み

    static let caloriesPerRep: [String: Double] = [
        "pushup": 0.32, "squat": 0.32, "situp": 0.15,
        "lunge": 0.40,  "burpee": 1.00, "plank": 0.08,
    ]

    func saveExercise(exerciseId: String, reps: Int, startDate: Date, endDate: Date) async {
        guard isAvailable else {
            print("[HealthKit] ⚠️ HealthKit not available")
            return
        }
        guard isAuthorized else {
            print("[HealthKit] ⚠️ Not authorized - skipping save")
            return
        }
        let kcal = (Self.caloriesPerRep[exerciseId.lowercased()] ?? 0.25) * Double(reps)
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
        let energySample = HKQuantitySample(
            type: energyType,
            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
            start: startDate, end: endDate
        )
        let workout = HKWorkout(
            activityType: workoutActivity(for: exerciseId),
            start: startDate, end: endDate,
            duration: max(endDate.timeIntervalSince(startDate), 1),
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
            totalDistance: nil, metadata: nil
        )
        do {
            try await store.save(energySample)
            try await store.save(workout)
            print("[HealthKit] ✅ Saved: \(exerciseId) \(reps)rep (\(String(format: "%.1f", kcal))kcal)")
        } catch {
            print("[HealthKit] ❌ 書き込みエラー: \(error.localizedDescription)")
        }
    }

    func saveCompletedSet(exercises: [(id: String, name: String, reps: Int)], startDate: Date, setId: String? = nil) async {
        guard isAvailable else {
            print("[HealthKit] ⚠️ HealthKit not available")
            return
        }
        guard isAuthorized else {
            print("[HealthKit] ⚠️ Not authorized - skipping set save")
            return
        }
        let endDate = Date()
        let totalKcal = exercises.reduce(0.0) {
            $0 + (Self.caloriesPerRep[$1.id.lowercased()] ?? 0.25) * Double($1.reps)
        }
        let totalReps = exercises.reduce(0) { $0 + $1.reps }
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
        let energySample = HKQuantitySample(
            type: energyType,
            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: totalKcal),
            start: startDate, end: endDate
        )
        var workoutMetadata: [String: Any]? = nil
        if let setId { workoutMetadata = ["kfitSetId": setId] }
        let workout = HKWorkout(
            activityType: .functionalStrengthTraining,
            start: startDate, end: endDate,
            duration: max(endDate.timeIntervalSince(startDate), 1),
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: totalKcal),
            totalDistance: nil, metadata: workoutMetadata
        )
        do {
            try await store.save(energySample)
            try await store.save(workout)
            print("[HealthKit] ✅ Set saved: \(totalReps)rep (\(String(format: "%.1f", totalKcal))kcal)")
        } catch {
            print("[HealthKit] ❌ セット書き込みエラー: \(error.localizedDescription)")
        }
    }

    private func workoutActivity(for exerciseId: String) -> HKWorkoutActivityType {
        switch exerciseId.lowercased() {
        case "pushup", "situp", "lunge", "burpee": return .traditionalStrengthTraining
        case "squat":  return .functionalStrengthTraining
        case "plank":  return .coreTraining
        default:       return .functionalStrengthTraining
        }
    }

    /// 既に許可済みかチェック（起動時に呼ぶ）
    func refreshAuthorizationStatus() {
        guard isAvailable else { return }
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        let status = store.authorizationStatus(for: hrType)
        // .notDetermined は未リクエスト、.sharingAuthorized は読み書き可
        // HealthKit は読み取り権限の状態をプライバシー保護のため非公開にするため
        // .notDetermined でもデータが取れる場合がある → fetchAll を試みる
        if status != .sharingDenied {
            isAuthorized = true
        }
    }

    // MARK: - 全データ取得

    func fetchAll(force: Bool = false) async {
        guard isAvailable else {
            print("[HealthKit] HealthKit not available - skipping fetch")
            return
        }
        guard isAuthorized else {
            print("[HealthKit] Not authorized - skipping fetch")
            return
        }
        if isLoading {
            print("[HealthKit] ⏳ fetchAll already running - skip duplicate")
            return
        }
        if !force, let lastFetchAllAt, Date().timeIntervalSince(lastFetchAllAt) < fetchAllTTL {
            print("[HealthKit] ✅ fetchAll skipped by TTL")
            return
        }

        print("[HealthKit] 🔄 Fetching all health data...")
        isLoading = true
        defer {
            lastFetchAllAt = Date()
            isLoading = false
        }

        async let steps    = fetchTodaySteps()
        async let activeCalories = fetchTodayActiveCalories()
        async let restingCalories = fetchTodayRestingCalories()
        async let latHR    = fetchLatestHeartRate()
        async let restHR   = fetchRestingHeartRate()
        async let hrv      = fetchLatestHRV()
        async let avgHR    = fetchTodayAverageHeartRate()
        async let avgHRV   = fetchTodayAverageHRV()
        async let hrList   = fetchTodayHRSamples()
        async let hrvList  = fetchTodayHRVSamples()
        async let sleep    = fetchLastNightSleep()
        async let bodyMass = fetchLatestBodyMass()
        async let bodyFat  = fetchLatestBodyFatPercentage()
        async let bodyMassCount = fetchTodayBodyMassMeasurements()
        async let todayBM  = fetchTodayBodyMassRecord()
        async let bodyMassChange = fetchWeeklyBodyMassChange()
        async let bodyFatChange  = fetchWeeklyBodyFatChange()
        async let intakeCal = fetchTodayIntakeCalories()
        async let intakeWater = fetchTodayIntakeWater()
        async let intakeCaffeine = fetchTodayIntakeCaffeine()
        async let intakeAlcohol = fetchTodayIntakeAlcohol()
        async let intakeProtein = fetchTodayIntakeProtein()
        async let intakeFat = fetchTodayIntakeFat()
        async let intakeCarbs = fetchTodayIntakeCarbs()
        async let mindfulness = fetchTodayMindfulness()
        async let daylight = fetchTodayDaylight()
        async let exerciseMinutes = fetchTodayExerciseMinutes()
        async let workoutCount = fetchTodayWorkoutCount()
        async let activityRings = fetchTodayActivitySummary()
        async let waterSamples = fetchTodayWaterSamplesRaw()
        async let mealSamples  = fetchTodayMealSamplesRaw()
        async let toothbrushing = fetchTodayToothbrushingRaw()

        todaySteps          = await steps
        todayActiveCalories = await activeCalories
        todayRestingCalories = await restingCalories
        todayTotalCalories  = todayActiveCalories + todayRestingCalories
        todayCalories       = todayActiveCalories  // 後方互換性
        latestHeartRate     = await latHR
        restingHeartRate    = await restHR
        latestHRV           = await hrv
        todayAvgHeartRate   = await avgHR
        todayAvgHRV         = await avgHRV
        hrSamples           = await hrList
        hrvSamples          = await hrvList
        let sleepResult     = await sleep
        lastNightTotalHours = sleepResult.total
        lastNightDeepHours  = sleepResult.deep
        sleepSegments       = sleepResult.segments
        sleepVitals         = await fetchSleepVitals(segments: sleepResult.segments)
        latestBodyMass          = await bodyMass
        latestBodyFatPercentage = await bodyFat
        todayBodyMassMeasurements = await bodyMassCount
        todayBodyMassRecord     = await todayBM
        weeklyBodyMassChange    = await bodyMassChange
        weeklyBodyFatChange     = await bodyFatChange
        todayIntakeCalories = await intakeCal
        todayIntakeWater    = await intakeWater
        todayIntakeCaffeine = await intakeCaffeine
        todayIntakeAlcohol  = await intakeAlcohol
        todayIntakeProtein  = await intakeProtein
        todayIntakeFat      = await intakeFat
        todayIntakeCarbs    = await intakeCarbs
        let mindfulnessResult = await mindfulness
        todayMindfulnessMinutes = mindfulnessResult.minutes
        todayMindfulnessSamples = mindfulnessResult.samples
        let newSessions = mindfulnessResult.sessions

        // セッション数が増えていたら時間帯の進捗を更新
        if newSessions > previousMindfulnessSessions && previousMindfulnessSessions > 0 {
            let hour = Calendar.current.component(.hour, from: Date())
            let timeSlot = TimeSlot.forHour(hour)

            let diff = newSessions - previousMindfulnessSessions
            for _ in 0..<diff {
                await TimeSlotManager.shared.recordMindfulnessCompleted(at: timeSlot)
            }
            print("[HealthKit] 🧘 Mindfulness sessions increased by \(diff), updated time slot: \(timeSlot.displayName)")
        }

        todayMindfulnessSessions = newSessions
        previousMindfulnessSessions = newSessions
        todayDaylightMinutes  = await daylight
        todayWorkoutMinutes   = await exerciseMinutes
        todayWorkoutCount     = await workoutCount
        let rings = await activityRings
        activityMoveCalories    = rings.moveCalories
        activityMoveGoal        = rings.moveGoal
        activityExerciseMinutes = rings.exerciseMinutes
        activityExerciseGoal    = rings.exerciseGoal
        activityStandHours      = rings.standHours
        activityStandGoal       = rings.standGoal
        todayWaterSamples       = await waterSamples
        todayMealSamples        = await mealSamples
        todayToothbrushingSamples = await toothbrushing
        weeklyCalorieData       = await fetchWeeklyCalories()

        print("[HealthKit] ✅ Fetched: steps=\(todaySteps), active=\(Int(todayActiveCalories))kcal, resting=\(Int(todayRestingCalories))kcal, total=\(Int(todayTotalCalories))kcal, hr=\(Int(latestHeartRate)), hrv=\(String(format: "%.1f", latestHRV))ms, sleep=\(String(format: "%.1f", lastNightTotalHours))h, daylight=\(Int(todayDaylightMinutes))min, weight=\(String(format: "%.1f", latestBodyMass))kg, bodyFat=\(String(format: "%.1f", latestBodyFatPercentage))%, intake=\(Int(todayIntakeCalories))kcal, P:\(String(format: "%.1f", todayIntakeProtein))g, F:\(String(format: "%.1f", todayIntakeFat))g, C:\(String(format: "%.1f", todayIntakeCarbs))g, water=\(Int(todayIntakeWater))ml, caffeine=\(Int(todayIntakeCaffeine))mg, alcohol=\(String(format: "%.1f", todayIntakeAlcohol))g, mindfulness=\(String(format: "%.1f", todayMindfulnessMinutes))min (\(todayMindfulnessSessions) sessions)")
    }

    func fetchDashboardHealth(force: Bool = false) async {
        guard beginScopedFetch("dashboard", force: force) else { return }
        defer { finishScopedFetch("dashboard") }

        async let steps = fetchTodaySteps()
        async let activeCalories = fetchTodayActiveCalories()
        async let restingCalories = fetchTodayRestingCalories()
        async let latHR = fetchLatestHeartRate()
        async let avgHR = fetchTodayAverageHeartRate()
        async let mindfulness = fetchTodayMindfulness()
        async let exerciseMinutes = fetchTodayExerciseMinutes()
        async let workoutCount = fetchTodayWorkoutCount()
        async let activityRings = fetchTodayActivitySummary()
        async let waterSamples = fetchTodayWaterSamplesRaw()
        async let mealSamples = fetchTodayMealSamplesRaw()
        async let toothbrushing = fetchTodayToothbrushingRaw()

        todaySteps = await steps
        todayActiveCalories = await activeCalories
        todayRestingCalories = await restingCalories
        todayTotalCalories = todayActiveCalories + todayRestingCalories
        todayCalories = todayActiveCalories
        latestHeartRate = await latHR
        todayAvgHeartRate = await avgHR
        applyMindfulnessResult(await mindfulness)
        todayWorkoutMinutes = await exerciseMinutes
        todayWorkoutCount = await workoutCount
        let rings = await activityRings
        activityMoveCalories = rings.moveCalories
        activityMoveGoal = rings.moveGoal
        activityExerciseMinutes = rings.exerciseMinutes
        activityExerciseGoal = rings.exerciseGoal
        activityStandHours = rings.standHours
        activityStandGoal = rings.standGoal
        todayWaterSamples = await waterSamples
        todayMealSamples = await mealSamples
        todayToothbrushingSamples = await toothbrushing
    }

    func fetchMindHealth(force: Bool = false) async {
        guard beginScopedFetch("mind", force: force) else { return }
        defer { finishScopedFetch("mind") }

        async let latHR = fetchLatestHeartRate()
        async let restHR = fetchRestingHeartRate()
        async let hrv = fetchLatestHRV()
        async let avgHR = fetchTodayAverageHeartRate()
        async let avgHRV = fetchTodayAverageHRV()
        async let hrList = fetchTodayHRSamples()
        async let hrvList = fetchTodayHRVSamples()
        async let weeklyHRV = fetchWeeklyHRVAverages()
        async let sleep = fetchLastNightSleep()
        async let mindfulness = fetchTodayMindfulness()
        async let daylight = fetchTodayDaylight()
        async let exerciseMinutes = fetchTodayExerciseMinutes()

        latestHeartRate = await latHR
        restingHeartRate = await restHR
        latestHRV = await hrv
        todayAvgHeartRate = await avgHR
        todayAvgHRV = await avgHRV
        hrSamples = await hrList
        hrvSamples = await hrvList
        weeklyHRVAverages = await weeklyHRV
        let sleepResult = await sleep
        lastNightTotalHours = sleepResult.total
        lastNightDeepHours = sleepResult.deep
        sleepSegments = sleepResult.segments
        sleepVitals = await fetchSleepVitals(segments: sleepResult.segments)
        applyMindfulnessResult(await mindfulness)
        todayDaylightMinutes = await daylight
        todayWorkoutMinutes = await exerciseMinutes
    }

    func fetchGoalHealth(force: Bool = false) async {
        guard beginScopedFetch("goal", force: force) else { return }
        defer { finishScopedFetch("goal") }

        async let activeCalories = fetchTodayActiveCalories()
        async let restingCalories = fetchTodayRestingCalories()
        async let bodyMass = fetchLatestBodyMass()
        async let bodyFat = fetchLatestBodyFatPercentage()
        async let bodyMassCount = fetchTodayBodyMassMeasurements()
        async let todayBM = fetchTodayBodyMassRecord()
        async let bodyMassChange = fetchWeeklyBodyMassChange()
        async let bodyFatChange = fetchWeeklyBodyFatChange()
        async let intakeCal = fetchTodayIntakeCalories()
        async let intakeWater = fetchTodayIntakeWater()
        async let activityRings = fetchTodayActivitySummary()
        async let weeklyCalories = fetchWeeklyCalories()

        todayActiveCalories = await activeCalories
        todayRestingCalories = await restingCalories
        todayTotalCalories = todayActiveCalories + todayRestingCalories
        todayCalories = todayActiveCalories
        latestBodyMass = await bodyMass
        latestBodyFatPercentage = await bodyFat
        todayBodyMassMeasurements = await bodyMassCount
        todayBodyMassRecord = await todayBM
        weeklyBodyMassChange = await bodyMassChange
        weeklyBodyFatChange = await bodyFatChange
        todayIntakeCalories = await intakeCal
        todayIntakeWater = await intakeWater
        let rings = await activityRings
        activityMoveCalories = rings.moveCalories
        activityMoveGoal = rings.moveGoal
        activityExerciseMinutes = rings.exerciseMinutes
        activityExerciseGoal = rings.exerciseGoal
        activityStandHours = rings.standHours
        activityStandGoal = rings.standGoal
        weeklyCalorieData = await weeklyCalories
    }

    func fetchIntakeHealth(force: Bool = false) async {
        guard beginScopedFetch("intake", force: force) else { return }
        defer { finishScopedFetch("intake") }

        async let intakeCal = fetchTodayIntakeCalories()
        async let intakeWater = fetchTodayIntakeWater()
        async let intakeCaffeine = fetchTodayIntakeCaffeine()
        async let intakeAlcohol = fetchTodayIntakeAlcohol()
        async let intakeProtein = fetchTodayIntakeProtein()
        async let intakeFat = fetchTodayIntakeFat()
        async let intakeCarbs = fetchTodayIntakeCarbs()
        async let waterSamples = fetchTodayWaterSamplesRaw()
        async let mealSamples = fetchTodayMealSamplesRaw()

        todayIntakeCalories = await intakeCal
        todayIntakeWater = await intakeWater
        todayIntakeCaffeine = await intakeCaffeine
        todayIntakeAlcohol = await intakeAlcohol
        todayIntakeProtein = await intakeProtein
        todayIntakeFat = await intakeFat
        todayIntakeCarbs = await intakeCarbs
        todayWaterSamples = await waterSamples
        todayMealSamples = await mealSamples
    }

    func fetchWatchSnapshotHealth(force: Bool = false) async {
        guard beginScopedFetch("watch", force: force, ttl: 10) else { return }
        defer { finishScopedFetch("watch") }

        async let steps = fetchTodaySteps()
        async let activeCalories = fetchTodayActiveCalories()
        async let restingCalories = fetchTodayRestingCalories()
        async let latHR = fetchLatestHeartRate()
        async let sleep = fetchLastNightSleep()
        async let bodyMass = fetchLatestBodyMass()
        async let bodyFat = fetchLatestBodyFatPercentage()
        async let mindfulness = fetchTodayMindfulness()
        async let exerciseMinutes = fetchTodayExerciseMinutes()
        async let workoutCount = fetchTodayWorkoutCount()

        todaySteps = await steps
        todayActiveCalories = await activeCalories
        todayRestingCalories = await restingCalories
        todayTotalCalories = todayActiveCalories + todayRestingCalories
        todayCalories = todayActiveCalories
        latestHeartRate = await latHR
        let sleepResult = await sleep
        lastNightTotalHours = sleepResult.total
        lastNightDeepHours = sleepResult.deep
        sleepSegments = sleepResult.segments
        latestBodyMass = await bodyMass
        latestBodyFatPercentage = await bodyFat
        applyMindfulnessResult(await mindfulness)
        todayWorkoutMinutes = await exerciseMinutes
        todayWorkoutCount = await workoutCount
    }

    private func beginScopedFetch(_ scope: String, force: Bool, ttl: TimeInterval? = nil) -> Bool {
        guard isAvailable else {
            print("[HealthKit] HealthKit not available - skipping \(scope) fetch")
            return false
        }
        guard isAuthorized else {
            print("[HealthKit] Not authorized - skipping \(scope) fetch")
            return false
        }
        if isLoading {
            if force {
                // 強制更新時は実行中フラグをリセットして続行
                print("[HealthKit] ⚡ \(scope) force-fetch: resetting isLoading")
                isLoading = false
            } else {
                print("[HealthKit] ⏳ \(scope) fetch skipped; another fetch is running")
                return false
            }
        }
        let scopeTTL = ttl ?? fetchAllTTL
        if !force, let last = lastScopedFetchAt[scope], Date().timeIntervalSince(last) < scopeTTL {
            print("[HealthKit] ✅ \(scope) fetch skipped by TTL")
            return false
        }
        isLoading = true
        return true
    }

    private func finishScopedFetch(_ scope: String) {
        lastScopedFetchAt[scope] = Date()
        isLoading = false
    }

    private func applyMindfulnessResult(_ mindfulnessResult: (minutes: Double, sessions: Int, samples: [MindfulSession])) {
        todayMindfulnessMinutes = mindfulnessResult.minutes
        todayMindfulnessSamples = mindfulnessResult.samples
        let newSessions = mindfulnessResult.sessions

        if newSessions > previousMindfulnessSessions && previousMindfulnessSessions > 0 {
            let timeSlot = TimeSlot.current()
            let diff = newSessions - previousMindfulnessSessions
            Task {
                for _ in 0..<diff {
                    await TimeSlotManager.shared.recordMindfulnessCompleted(at: timeSlot)
                }
            }
            print("[HealthKit] 🧘 Mindfulness sessions increased by \(diff), updated time slot: \(timeSlot.displayName)")
        }

        todayMindfulnessSessions = newSessions
        previousMindfulnessSessions = newSessions
    }

    // MARK: - 歩数

    private func fetchTodaySteps() async -> Int {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let start = Calendar.current.startOfDay(for: Date())
        let pred  = HKQuery.predicateForSamples(withStart: start, end: Date())
        return Int(await fetchCumulativeSum(type: type, predicate: pred, unit: .count()))
    }

    // MARK: - 消費カロリー

    /// アクティブカロリー（活動による消費カロリー）
    private func fetchTodayActiveCalories() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return 0 }
        let start = Calendar.current.startOfDay(for: Date())
        let pred  = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await fetchCumulativeSum(type: type, predicate: pred, unit: .kilocalorie())
    }

    /// 安静時カロリー（基礎代謝）
    private func fetchTodayRestingCalories() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned) else { return 0 }
        let start = Calendar.current.startOfDay(for: Date())
        let pred  = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await fetchCumulativeSum(type: type, predicate: pred, unit: .kilocalorie())
    }

    // MARK: - 心拍数（最新）

    private func fetchLatestHeartRate() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return 0 }
        let unit = HKUnit.count().unitDivided(by: .minute())
        return await fetchLatestSampleValue(type: type, unit: unit)
    }

    // MARK: - 安静時心拍数（最新）

    private func fetchRestingHeartRate() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return 0 }
        let unit = HKUnit.count().unitDivided(by: .minute())
        return await fetchLatestSampleValue(type: type, unit: unit)
    }

    // MARK: - 心拍変動（最新）

    private func fetchLatestHRV() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return 0 }
        return await fetchLatestSampleValue(type: type, unit: .secondUnit(with: .milli))
    }

    // MARK: - 今日の平均心拍数・平均HRV

    private func fetchTodayAverageHeartRate() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return 0 }
        let unit  = HKUnit.count().unitDivided(by: .minute())
        let start = Calendar.current.startOfDay(for: Date())
        let pred  = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .discreteAverage) { _, result, _ in
                cont.resume(returning: result?.averageQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(q)
        }
    }

    private func fetchTodayAverageHRV() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return 0 }
        let unit  = HKUnit.secondUnit(with: .milli)
        let start = Calendar.current.startOfDay(for: Date())
        let pred  = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .discreteAverage) { _, result, _ in
                cont.resume(returning: result?.averageQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(q)
        }
    }

    // MARK: - 今日の心拍数サンプル一覧

    private func fetchTodayHRSamples() async -> [HRSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let start = Calendar.current.startOfDay(for: Date())
        let pred  = HKQuery.predicateForSamples(withStart: start, end: Date())
        let unit  = HKUnit.count().unitDivided(by: .minute())

        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type, predicate: pred,
                limit: 48,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, _ in
                let list = (samples as? [HKQuantitySample] ?? []).map {
                    HRSample(date: $0.startDate, bpm: $0.quantity.doubleValue(for: unit))
                }
                cont.resume(returning: list)
            }
            store.execute(q)
        }
    }

    private func fetchTodayHRVSamples() async -> [HRVSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return [] }
        let start = Calendar.current.startOfDay(for: Date())
        let pred  = HKQuery.predicateForSamples(withStart: start, end: Date())
        let unit  = HKUnit.secondUnit(with: .milli)

        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type,
                predicate: pred,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                let list = (samples as? [HKQuantitySample] ?? []).map {
                    HRVSample(date: $0.startDate, value: $0.quantity.doubleValue(for: unit))
                }
                cont.resume(returning: list)
            }
            store.execute(q)
        }
    }

    private func fetchWeeklyHRVAverages() async -> [DailyHRVAverage] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return [] }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let unit = HKUnit.secondUnit(with: .milli)
        let hkStore = store

        // 7日分を並列クエリで一括取得
        let results = await withTaskGroup(of: DailyHRVAverage?.self) { group in
            for offset in stride(from: 6, through: 0, by: -1) {
                guard let dayStart = calendar.date(byAdding: .day, value: -offset, to: today),
                      let dayEnd   = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }
                group.addTask {
                    let predicate = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd)
                    let value = await withCheckedContinuation { (cont: CheckedContinuation<Double, Never>) in
                        let query = HKStatisticsQuery(
                            quantityType: type,
                            quantitySamplePredicate: predicate,
                            options: .discreteAverage
                        ) { _, result, _ in
                            cont.resume(returning: result?.averageQuantity()?.doubleValue(for: unit) ?? 0)
                        }
                        hkStore.execute(query)
                    }
                    return DailyHRVAverage(date: dayStart, value: value)
                }
            }
            var collected: [DailyHRVAverage] = []
            for await item in group {
                if let item { collected.append(item) }
            }
            return collected
        }
        return results.sorted { $0.date < $1.date }
    }

    // MARK: - 昨夜の睡眠

    private func fetchLastNightSleep() async -> (total: Double, deep: Double, segments: [SleepSegment]) {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            return (0, 0, [])
        }

        // 前日 15:00 〜 今日 14:00（幅広い睡眠パターンをカバー）
        let cal   = Calendar.current
        let now   = Date()
        let today = cal.startOfDay(for: now)
        let start = cal.date(byAdding: .hour, value: -9, to: today) ?? today
        let end   = cal.date(byAdding: .hour, value: 14, to: today) ?? now
        let pred  = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type, predicate: pred,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                // 無効サンプル（開始 >= 終了）を除外
                let hkSamples = (samples as? [HKCategorySample] ?? [])
                    .filter { $0.startDate < $0.endDate }

                // ── ソース選択 ────────────────────────────────────────
                // staged data (Core=4, Deep=5, REM=6) を持つソースをグループ化し
                // 最も多くの実睡眠時間を記録したソースを 1 つ選ぶ
                let asleepValues: Set<Int> = [0, 3, 4, 5, 6]
                let bySource = Dictionary(grouping: hkSamples) {
                    $0.sourceRevision.source.bundleIdentifier
                }
                let stagedBySource = bySource.filter { _, ss in
                    ss.contains { [4, 5, 6].contains($0.value) }
                }

                let baseSamples: [HKCategorySample]
                if !stagedBySource.isEmpty {
                    // staged ソースの中で実睡眠時間が最長のものを採用
                    let best = stagedBySource.max { a, b in
                        let dur: ([HKCategorySample]) -> TimeInterval = { ss in
                            ss.filter { asleepValues.contains($0.value) }
                              .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                        }
                        return dur(a.value) < dur(b.value)
                    }!
                    baseSamples = best.value.filter { $0.value != 1 }  // InBed 除外
                } else {
                    // staged data なし：全ソース合算（InBed 除外）
                    baseSamples = hkSamples.filter { $0.value != 1 }
                }

                // ── 重複区間のマージ ──────────────────────────────────
                // 同一ソース内でも稀に重複が発生するためマージ処理を行う
                let sorted = baseSamples.sorted { $0.startDate < $1.startDate }
                var mergedAsleep: [(start: Date, end: Date, value: Int)] = []
                var awakeSegs:    [SleepSegment] = []

                for s in sorted {
                    if s.value == 2 {
                        awakeSegs.append(SleepSegment(start: s.startDate, end: s.endDate, stage: .awake))
                        continue
                    }
                    guard asleepValues.contains(s.value) else { continue }
                    // deprecated asleep(0) → unspecified(3) に正規化
                    let val = s.value == 0 ? 3 : s.value
                    if let last = mergedAsleep.last, s.startDate < last.end {
                        // 重複：終了時刻を延ばし、より具体的なステージを優先
                        mergedAsleep[mergedAsleep.count - 1] = (
                            last.start, max(last.end, s.endDate), max(last.value, val)
                        )
                    } else {
                        mergedAsleep.append((s.startDate, s.endDate, val))
                    }
                }

                // ── 集計 ──────────────────────────────────────────────
                var total: TimeInterval = 0
                var deep:  TimeInterval = 0
                var segs:  [SleepSegment] = []

                for m in mergedAsleep {
                    let dur   = m.end.timeIntervalSince(m.start)
                    let stage = Self.sleepStage(from: m.value)
                    segs.append(SleepSegment(start: m.start, end: m.end, stage: stage))
                    total += dur
                    if stage == .deep { deep += dur }
                }

                segs.append(contentsOf: awakeSegs)
                segs.sort { $0.start < $1.start }

                cont.resume(returning: (total / 3600, deep / 3600, segs))
            }
            self.store.execute(q)
        }
    }

    private nonisolated static func sleepStage(from value: Int) -> SleepSegment.SleepStage {
        // HKCategoryValueSleepAnalysis raw values:
        //   0: asleep (deprecated, iOS <16 の全睡眠)
        //   1: inBed
        //   2: awake   (iOS 16+)
        //   3: asleepUnspecified (iOS 16+)  ← Apple が未分類とする場合
        //   4: asleepCore (iOS 16+)
        //   5: asleepDeep (iOS 16+)
        //   6: asleepREM  (iOS 16+)
        switch value {
        case 1:      return .inBed
        case 2:      return .awake
        case 3:      return .unknown
        case 4:      return .core
        case 5:      return .deep
        case 6:      return .rem
        default:     return .unknown  // value == 0 も含む
        }
    }

    // MARK: - アクティビティリング

    private struct ActivityRingsResult {
        var moveCalories: Double = 0
        var moveGoal: Double = 600
        var exerciseMinutes: Int = 0
        var exerciseGoal: Int = 30
        var standHours: Int = 0
        var standGoal: Int = 12
    }

    private func fetchTodayActivitySummary() async -> ActivityRingsResult {
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        var components = cal.dateComponents([.era, .year, .month, .day], from: Date())
        components.calendar = cal
        let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: components, end: components)

        return await withCheckedContinuation { cont in
            let q = HKActivitySummaryQuery(predicate: predicate) { _, summaries, _ in
                guard let summary = summaries?.first else {
                    cont.resume(returning: ActivityRingsResult())
                    return
                }
                var result = ActivityRingsResult()
                result.moveCalories    = summary.activeEnergyBurned.doubleValue(for: .kilocalorie())
                let goalKcal           = summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
                result.moveGoal        = goalKcal > 0 ? goalKcal : 600
                result.exerciseMinutes = Int(summary.appleExerciseTime.doubleValue(for: .minute()))
                let goalMin            = Int(summary.appleExerciseTimeGoal.doubleValue(for: .minute()))
                result.exerciseGoal    = goalMin > 0 ? goalMin : 30
                result.standHours      = Int(summary.appleStandHours.doubleValue(for: .count()))
                let goalHrs            = Int(summary.appleStandHoursGoal.doubleValue(for: .count()))
                result.standGoal       = goalHrs > 0 ? goalHrs : 12
                cont.resume(returning: result)
            }
            store.execute(q)
        }
    }

    // MARK: - Generic HealthKit helpers

    private func fetchCumulativeSum(
        type: HKQuantityType,
        predicate: NSPredicate,
        unit: HKUnit
    ) async -> Double {
        await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, _ in
                cont.resume(returning: result?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(q)
        }
    }

    private func fetchLatestSampleValue(type: HKQuantityType, unit: HKUnit) async -> Double {
        await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type, predicate: nil, limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, _ in
                let val = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit) ?? 0
                cont.resume(returning: val)
            }
            store.execute(q)
        }
    }

    private func fetchDiscreteAverage(type: HKQuantityType, predicate: NSPredicate, unit: HKUnit) async -> Double {
        await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, result, _ in
                continuation.resume(returning: result?.averageQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(query)
        }
    }

    private func fetchMinimumSampleValue(type: HKQuantityType, predicate: NSPredicate, unit: HKUnit) async -> Double {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let values = (samples as? [HKQuantitySample])?.map { $0.quantity.doubleValue(for: unit) } ?? []
                continuation.resume(returning: values.min() ?? 0)
            }
            store.execute(query)
        }
    }

    private func fetchDiscreteAverage(type: HKQuantityType?, predicate: NSPredicate, unit: HKUnit) async -> Double {
        guard let type else { return 0 }
        return await fetchDiscreteAverage(type: type, predicate: predicate, unit: unit)
    }

    private func fetchMinimumSampleValue(type: HKQuantityType?, predicate: NSPredicate, unit: HKUnit) async -> Double {
        guard let type else { return 0 }
        return await fetchMinimumSampleValue(type: type, predicate: predicate, unit: unit)
    }

    private func fetchSleepVitals(segments: [SleepSegment]) async -> SleepVitalsAnalysis {
        let asleepSegments = segments.filter { segment in
            switch segment.stage {
            case .deep, .rem, .core, .unknown:
                return true
            case .awake, .inBed:
                return false
            }
        }
        guard let start = asleepSegments.map(\.start).min(),
              let end = asleepSegments.map(\.end).max(),
              start < end else {
            return SleepVitalsAnalysis(
                averageHeartRate: 0,
                averageRespiratoryRate: 0,
                averageOxygenSaturation: 0,
                minimumOxygenSaturation: 0
            )
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let heartType = HKQuantityType.quantityType(forIdentifier: .heartRate)
        let respiratoryType = HKQuantityType.quantityType(forIdentifier: .respiratoryRate)
        let oxygenType = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)

        async let heart = fetchDiscreteAverage(
            type: heartType,
            predicate: predicate,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
        async let respiratory = fetchDiscreteAverage(
            type: respiratoryType,
            predicate: predicate,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
        async let oxygenAverage = fetchDiscreteAverage(type: oxygenType, predicate: predicate, unit: .percent()) * 100
        async let oxygenMinimum = fetchMinimumSampleValue(type: oxygenType, predicate: predicate, unit: .percent()) * 100

        return await SleepVitalsAnalysis(
            averageHeartRate: heart,
            averageRespiratoryRate: respiratory,
            averageOxygenSaturation: oxygenAverage,
            minimumOxygenSaturation: oxygenMinimum
        )
    }

    // MARK: - 体重・体脂肪の取得

    private func fetchLatestBodyMass() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return 0 }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: 0)
                    return
                }
                let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                Task { @MainActor in self.latestBodyMass = kg }
                continuation.resume(returning: kg)
            }
            store.execute(query)
        }
    }

    private func fetchLatestBodyFatPercentage() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) else { return 0 }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: 0)
                    return
                }
                let pct = sample.quantity.doubleValue(for: .percent()) * 100
                Task { @MainActor in self.latestBodyFatPercentage = pct }
                continuation.resume(returning: pct)
            }
            store.execute(query)
        }
    }

    func fetchTodayBodyMassMeasurements() async -> Int {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return 0 }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: samples?.count ?? 0)
            }
            store.execute(query)
        }
    }

    /// 今日計測された最新の体重レコードを取得（時刻付き）
    func fetchTodayBodyMassRecord() async -> BodyMassRecord? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return nil }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? Date()
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: pred, limit: 1, sortDescriptors: [sort]) { [weak self] _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    Task { @MainActor in self?.todayBodyMassRecord = nil }
                    continuation.resume(returning: nil)
                    return
                }
                let record = BodyMassRecord(measuredAt: sample.endDate,
                                            kg: sample.quantity.doubleValue(for: .gramUnit(with: .kilo)))
                Task { @MainActor in self?.todayBodyMassRecord = record }
                continuation.resume(returning: record)
            }
            store.execute(query)
        }
    }

    // MARK: - 日別体重履歴（履歴画面用）

    /// 過去 days 日間の体重サンプルを取得し、日ごとに最新1件を bodyMassHistory に格納する
    func fetchBodyMassHistory(days: Int = 14) async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: cal.date(byAdding: .day, value: -days, to: Date()) ?? Date())
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { [weak self] _, samples, _ in
                guard let self, let samples = samples as? [HKQuantitySample] else {
                    cont.resume(); return
                }
                let fmt = HealthKitManager.yyyyMMddFmt
                var map: [String: BodyMassRecord] = [:]
                for s in samples {
                    let key = fmt.string(from: s.endDate)
                    // ascending order → last write wins = latest sample per day
                    map[key] = BodyMassRecord(
                        measuredAt: s.endDate,
                        kg: s.quantity.doubleValue(for: .gramUnit(with: .kilo))
                    )
                }
                Task { @MainActor in
                    self.bodyMassHistory = map.values.sorted { $0.measuredAt > $1.measuredAt }
                }
                cont.resume()
            }
            store.execute(q)
        }
    }

    /// "yyyy-MM-dd" キーで体重記録を検索する
    func bodyMassRecord(for dateKey: String) -> BodyMassRecord? {
        let fmt = HealthKitManager.yyyyMMddFmt
        return bodyMassHistory.first { fmt.string(from: $0.measuredAt) == dateKey }
    }

    // MARK: - 日別体脂肪率履歴

    struct BodyFatRecord: Identifiable {
        let id = UUID()
        let measuredAt: Date
        let percent: Double
    }

    @Published var bodyFatHistory: [BodyFatRecord] = []

    /// 過去 days 日間の体脂肪率サンプルを取得し、日ごとに最新1件を bodyFatHistory に格納する
    func fetchBodyFatHistory(days: Int = 30) async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: cal.date(byAdding: .day, value: -days, to: Date()) ?? Date())
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { [weak self] _, samples, _ in
                guard let self, let samples = samples as? [HKQuantitySample] else {
                    cont.resume(); return
                }
                let fmt = HealthKitManager.yyyyMMddFmt
                var map: [String: BodyFatRecord] = [:]
                for s in samples {
                    let key = fmt.string(from: s.endDate)
                    map[key] = BodyFatRecord(
                        measuredAt: s.endDate,
                        percent: s.quantity.doubleValue(for: .percent()) * 100
                    )
                }
                Task { @MainActor in
                    self.bodyFatHistory = map.values.sorted { $0.measuredAt < $1.measuredAt }
                }
                cont.resume()
            }
            store.execute(q)
        }
    }

    // MARK: - 1週間の体重・体脂肪変動

    /// 過去7日間の最古の体重と現在値の差分を返す（データ不足はnil）
    private func fetchWeeklyBodyMassChange() async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return nil }
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                guard let samples = samples as? [HKQuantitySample], samples.count >= 2 else {
                    continuation.resume(returning: nil)
                    return
                }
                let oldest  = samples.first!.quantity.doubleValue(for: .gramUnit(with: .kilo))
                let current = samples.last!.quantity.doubleValue(for: .gramUnit(with: .kilo))
                continuation.resume(returning: current - oldest)
            }
            store.execute(query)
        }
    }

    /// 過去7日間の最古の体脂肪と現在値の差分を返す（データ不足はnil）
    private func fetchWeeklyBodyFatChange() async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) else { return nil }
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                guard let samples = samples as? [HKQuantitySample], samples.count >= 2 else {
                    continuation.resume(returning: nil)
                    return
                }
                let oldest  = samples.first!.quantity.doubleValue(for: .percent()) * 100
                let current = samples.last!.quantity.doubleValue(for: .percent()) * 100
                continuation.resume(returning: current - oldest)
            }
            store.execute(query)
        }
    }

    // MARK: - 週間カロリー収支

    /// 指定日時範囲内の最新サンプル値を取得（なければnil）
    private func fetchLatestSampleInRange(type: HKQuantityType, predicate: NSPredicate, unit: HKUnit) async -> Double? {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    /// 今週（月〜日）の日別カロリー収支・体重・体脂肪を取得
    private func fetchWeeklyCalories() async -> [DailyCalorieBalance] {
        guard let activeType  = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
              let restingType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned),
              let intakeType  = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed),
              let massType    = HKQuantityType.quantityType(forIdentifier: .bodyMass),
              let fatType     = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage),
              let stepType    = HKQuantityType.quantityType(forIdentifier: .stepCount)
        else { return [] }

        var cal = Calendar.current
        cal.firstWeekday = 2  // 月曜始まり
        let today = Date()
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today

        var results: [DailyCalorieBalance] = []
        for i in 0..<7 {
            guard let dayStart = cal.date(byAdding: .day, value: i, to: weekStart) else { continue }
            guard dayStart <= today else {
                results.append(DailyCalorieBalance(date: dayStart, burned: 0, consumed: 0))
                continue
            }
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let pred = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd)

            let active  = await fetchCumulativeSum(type: activeType,  predicate: pred, unit: .kilocalorie())
            let resting = await fetchCumulativeSum(type: restingType, predicate: pred, unit: .kilocalorie())
            let intake  = await fetchCumulativeSum(type: intakeType,  predicate: pred, unit: .kilocalorie())
            let mass    = await fetchLatestSampleInRange(type: massType, predicate: pred, unit: .gramUnit(with: .kilo))
            let fat     = await fetchLatestSampleInRange(type: fatType,  predicate: pred, unit: .percent())
            let stepSum = await fetchCumulativeSum(type: stepType, predicate: pred, unit: .count())

            var entry = DailyCalorieBalance(date: dayStart, burned: active + resting, consumed: intake)
            entry.bodyMass = mass
            entry.bodyFatPercentage = fat.map { $0 * 100 }
            entry.steps = Int(stepSum)
            results.append(entry)
        }
        return results
    }

    /// 今週（月〜日）の日別消費カロリー内訳（安静時・活動・運動時間）を取得
    func fetchWeeklyBurnData() async {
        guard let activeType   = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
              let restingType  = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned),
              let exerciseType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime),
              let stepType     = HKQuantityType.quantityType(forIdentifier: .stepCount)
        else { return }

        var cal = Calendar.current
        cal.firstWeekday = 2
        let today = Date()
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today

        var results: [DailyBurnSummary] = []
        for i in 0..<7 {
            guard let dayStart = cal.date(byAdding: .day, value: i, to: weekStart) else { continue }
            guard dayStart <= today else {
                results.append(DailyBurnSummary(date: dayStart))
                continue
            }
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let pred = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd)

            let active   = await fetchCumulativeSum(type: activeType,   predicate: pred, unit: .kilocalorie())
            let resting  = await fetchCumulativeSum(type: restingType,  predicate: pred, unit: .kilocalorie())
            let exercise = await fetchCumulativeSum(type: exerciseType, predicate: pred, unit: .minute())
            let stepSum  = await fetchCumulativeSum(type: stepType,     predicate: pred, unit: .count())

            results.append(DailyBurnSummary(
                date: dayStart,
                activeCalories: active,
                restingCalories: resting,
                exerciseMinutes: exercise,
                steps: Int(stepSum)
            ))
        }
        weeklyBurnData = results
    }

    /// 今週（月〜日）の食事カロリーサンプルを取得（摂取タイミング別スタック用）
    func fetchWeeklyDietarySamples() async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else { return }
        var cal = Calendar.current; cal.firstWeekday = 2
        let today = Date()
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today
        let weekEnd   = cal.date(byAdding: .day, value: 7, to: weekStart) ?? today
        let predicate = HKQuery.predicateForSamples(withStart: weekStart, end: weekEnd, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let samples: [DietarySample] = await withCheckedContinuation { continuation in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, raw, _ in
                let result = (raw as? [HKQuantitySample])?.compactMap { s -> DietarySample? in
                    let kcal = s.quantity.doubleValue(for: .kilocalorie())
                    guard kcal > 0 else { return nil }
                    return DietarySample(startDate: s.startDate, value: kcal)
                } ?? []
                continuation.resume(returning: result)
            }
            self.store.execute(q)
        }
        await MainActor.run { weeklyDietarySamples = samples }
    }

    // MARK: - 摂取記録の書き込み

    /// 食事カロリーを Apple Health に記録
    @discardableResult
    func saveDietaryEnergy(calories: Double, timestamp: Date, metadata: [String: Any]? = nil) async -> Bool {
        guard isAvailable, isAuthorized else {
            print("[HealthKit] ⚠️ Not authorized - skipping dietary energy save")
            return false
        }
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else { return false }
        let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: calories)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: timestamp, end: timestamp, metadata: metadata)
        do {
            try await store.save(sample)
            print("[HealthKit] ✅ Saved dietary energy: \(calories)kcal")
            return true
        } catch {
            print("[HealthKit] ❌ 食事記録エラー: \(error.localizedDescription)")
            return false
        }
    }

    /// 水分摂取を Apple Health に記録
    func saveWaterIntake(amountMl: Double, timestamp: Date) async {
        guard isAvailable, isAuthorized else {
            print("[HealthKit] ⚠️ Not authorized - skipping water save")
            return
        }
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else { return }
        let quantity = HKQuantity(unit: .literUnit(with: .milli), doubleValue: amountMl)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: timestamp, end: timestamp)
        do {
            try await store.save(sample)
            print("[HealthKit] ✅ Saved water: \(amountMl)ml")
        } catch {
            print("[HealthKit] ❌ 水分記録エラー: \(error.localizedDescription)")
        }
    }

    /// カフェイン摂取を Apple Health に記録
    func saveCaffeineIntake(caffeineMg: Double, timestamp: Date) async {
        guard isAvailable, isAuthorized else {
            print("[HealthKit] ⚠️ Not authorized - skipping caffeine save")
            return
        }
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryCaffeine) else { return }
        let quantity = HKQuantity(unit: .gramUnit(with: .milli), doubleValue: caffeineMg)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: timestamp, end: timestamp)
        do {
            try await store.save(sample)
            print("[HealthKit] ✅ Saved caffeine: \(caffeineMg)mg")
        } catch {
            print("[HealthKit] ❌ カフェイン記録エラー: \(error.localizedDescription)")
        }
    }

    /// アルコール摂取を Apple Health に記録
    /// - dietaryEnergyConsumed にカロリーとしてメタデータ付きで保存
    /// - numberOfAlcoholicBeverages に標準ドリンク数（alcoholG / 12g）で保存
    /// - dietaryWater に液量（amountMl）として保存
    func saveAlcoholIntake(amountMl: Double, alcoholG: Double, timestamp: Date) async {
        guard isAvailable, isAuthorized else {
            print("[HealthKit] ⚠️ Not authorized - skipping alcohol save")
            return
        }

        var samples: [HKSample] = []

        // 1. カロリー（dietaryEnergyConsumed）
        if let type = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed), alcoholG > 0 {
            let estimatedCalories = alcoholG * 7.0
            let metadata: [String: Any] = ["intake_type": "alcohol", "amount_ml": amountMl, "alcohol_grams": alcoholG]
            samples.append(HKQuantitySample(type: type,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: estimatedCalories),
                start: timestamp, end: timestamp, metadata: metadata))
        }

        // 2. 飲酒量（numberOfAlcoholicBeverages）: 1標準ドリンク = 12g純アルコール
        if let type = HKQuantityType.quantityType(forIdentifier: .numberOfAlcoholicBeverages), alcoholG > 0 {
            let drinks = alcoholG / 12.0
            samples.append(HKQuantitySample(type: type,
                quantity: HKQuantity(unit: .count(), doubleValue: drinks),
                start: timestamp, end: timestamp))
        }

        // 3. 液量（dietaryWater）
        if let type = HKQuantityType.quantityType(forIdentifier: .dietaryWater), amountMl > 0 {
            samples.append(HKQuantitySample(type: type,
                quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: amountMl),
                start: timestamp, end: timestamp))
        }

        guard !samples.isEmpty else { return }
        do {
            try await store.save(samples)
            print("[HealthKit] ✅ Saved alcohol: \(amountMl)ml, \(alcoholG)g → \(String(format: "%.2f", alcoholG / 12.0))drinks")
        } catch {
            print("[HealthKit] ❌ アルコール記録エラー: \(error.localizedDescription)")
        }
    }

    /// 歯磨きを Apple Health に記録（toothbrushingEvent: 1分）
    func saveToothbrushing(durationSeconds: Double = 60, timestamp: Date = Date()) async {
        guard isAvailable, isAuthorized else {
            print("[HealthKit] ⚠️ Not authorized - skipping toothbrushing save")
            return
        }
        guard let type = HKCategoryType.categoryType(forIdentifier: .toothbrushingEvent) else { return }
        let start = timestamp.addingTimeInterval(-durationSeconds)
        let sample = HKCategorySample(type: type, value: HKCategoryValue.notApplicable.rawValue,
                                      start: start, end: timestamp)
        do {
            try await store.save(sample)
            print("[HealthKit] ✅ Saved toothbrushing: \(Int(durationSeconds))s")
            todayToothbrushingSamples = await fetchTodayToothbrushingRaw()
            await TimeSlotManager.shared.syncToothbrushingFromHealthKit()
        } catch {
            print("[HealthKit] ❌ 歯磨き記録エラー: \(error.localizedDescription)")
        }
    }

    // MARK: - 摂取データ読み取り

    /// 今日の摂取カロリーを取得
    private func fetchTodayIntakeCalories() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else { return 0 }
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        return await fetchDietaryEnergyCalories(predicate: predicate)
    }

    func fetchDietaryEnergyCalories(start: Date, end: Date) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await fetchDietaryEnergyCalories(predicate: predicate, type: type)
    }

    private func fetchDietaryEnergyCalories(predicate: NSPredicate, type: HKQuantityType? = nil) async -> Double {
        guard let type = type ?? HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else { return 0 }
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let sum = result?.sumQuantity() {
                    let kcal = sum.doubleValue(for: .kilocalorie())
                    continuation.resume(returning: kcal)
                } else {
                    continuation.resume(returning: 0)
                }
            }
            store.execute(query)
        }
    }

    /// 今日の水分摂取量を取得（ml）
    private func fetchTodayIntakeWater() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else { return 0 }
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let sum = result?.sumQuantity() {
                    let ml = sum.doubleValue(for: .literUnit(with: .milli))
                    continuation.resume(returning: ml)
                } else {
                    continuation.resume(returning: 0)
                }
            }
            store.execute(query)
        }
    }

    /// 今日の水分サンプル（時刻付き）を取得
    private func fetchTodayWaterSamplesRaw() async -> [DietarySample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else { return [] }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { continuation in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                let result = (samples as? [HKQuantitySample])?.map {
                    DietarySample(startDate: $0.startDate, value: $0.quantity.doubleValue(for: .literUnit(with: .milli)))
                } ?? []
                continuation.resume(returning: result)
            }
            self.store.execute(q)
        }
    }

    /// 今日の食事カロリーサンプル（時刻付き）を取得
    private func fetchTodayMealSamplesRaw() async -> [DietarySample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else { return [] }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { continuation in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                let result = (samples as? [HKQuantitySample])?.map {
                    DietarySample(startDate: $0.startDate, value: $0.quantity.doubleValue(for: .kilocalorie()))
                } ?? []
                continuation.resume(returning: result)
            }
            self.store.execute(q)
        }
    }

    /// 今日の歯磨きイベントを取得（終了時刻の配列）
    private func fetchTodayToothbrushingRaw() async -> [Date] {
        guard let type = HKCategoryType.categoryType(forIdentifier: .toothbrushingEvent) else { return [] }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { continuation in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                let dates = (samples as? [HKCategorySample])?.map { $0.endDate } ?? []
                continuation.resume(returning: dates)
            }
            self.store.execute(q)
        }
    }

    /// 今日のカフェイン摂取量を取得（mg）
    private func fetchTodayIntakeCaffeine() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryCaffeine) else { return 0 }
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let sum = result?.sumQuantity() {
                    let mg = sum.doubleValue(for: .gramUnit(with: .milli))
                    continuation.resume(returning: mg)
                } else {
                    continuation.resume(returning: 0)
                }
            }
            store.execute(query)
        }
    }

    /// 今日のアルコール摂取量を取得（純アルコールg）
    /// メタデータからalcohol_mgを読み取る
    private func fetchTodayIntakeAlcohol() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else { return 0 }
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                guard let samples = samples as? [HKQuantitySample] else {
                    continuation.resume(returning: 0)
                    return
                }

                var totalAlcoholGrams: Double = 0
                for sample in samples {
                    if let metadata = sample.metadata,
                       let intakeType = metadata["intake_type"] as? String,
                       intakeType == "alcohol",
                       let alcoholGrams = metadata["alcohol_grams"] as? Double {
                        totalAlcoholGrams += alcoholGrams
                    }
                }
                continuation.resume(returning: totalAlcoholGrams)
            }
            store.execute(query)
        }
    }

    /// 今日のたんぱく質摂取量を取得（g）
    private func fetchTodayIntakeProtein() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryProtein) else { return 0 }
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let sum = result?.sumQuantity() {
                    let g = sum.doubleValue(for: .gram())
                    continuation.resume(returning: g)
                } else {
                    continuation.resume(returning: 0)
                }
            }
            store.execute(query)
        }
    }

    /// 今日の脂質摂取量を取得（g）
    private func fetchTodayIntakeFat() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal) else { return 0 }
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let sum = result?.sumQuantity() {
                    let g = sum.doubleValue(for: .gram())
                    continuation.resume(returning: g)
                } else {
                    continuation.resume(returning: 0)
                }
            }
            store.execute(query)
        }
    }

    /// 今日の炭水化物摂取量を取得（g）
    private func fetchTodayIntakeCarbs() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates) else { return 0 }
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let sum = result?.sumQuantity() {
                    let g = sum.doubleValue(for: .gram())
                    continuation.resume(returning: g)
                } else {
                    continuation.resume(returning: 0)
                }
            }
            store.execute(query)
        }
    }

    // MARK: - マインドフルネス

    /// 今日のマインドフルネスセッションを取得（30秒キャッシュ付き）
    func fetchTodayMindfulness() async -> (minutes: Double, sessions: Int, samples: [MindfulSession]) {
        if let cached = mindfulnessCacheResult,
           let cachedAt = mindfulnessCachedAt,
           Date().timeIntervalSince(cachedAt) < mindfulnessCacheTTL {
            return cached
        }

        guard let type = HKCategoryType.categoryType(forIdentifier: .mindfulSession) else {
            return (0, 0, [])
        }

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let rawSamples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        var totalMinutes: Double = 0
        var mindfulSamples: [MindfulSession] = []
        for sample in rawSamples {
            let duration = sample.endDate.timeIntervalSince(sample.startDate) / 60.0
            totalMinutes += duration
            let sessionPred = HKQuery.predicateForSamples(withStart: sample.startDate, end: sample.endDate, options: .strictStartDate)
            let hr = await fetchDiscreteAverage(
                type: HKQuantityType.quantityType(forIdentifier: .heartRate),
                predicate: sessionPred,
                unit: HKUnit.count().unitDivided(by: .minute())
            )
            let hrv = await fetchDiscreteAverage(
                type: HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
                predicate: sessionPred,
                unit: .secondUnit(with: .milli)
            )
            mindfulSamples.append(MindfulSession(
                startDate: sample.startDate,
                durationMinutes: duration,
                sourceName: sample.sourceRevision.source.name,
                sourceBundleId: sample.sourceRevision.source.bundleIdentifier,
                sessionTypeHint: sample.metadata?["kfitSessionType"] as? String,
                averageHeartRate: hr,
                averageHRV: hrv
            ))
        }

        let oneMinuteCount = mindfulSamples.filter { $0.durationMinutes <= 1.5 }.count
        let result = (totalMinutes, oneMinuteCount, mindfulSamples)
        mindfulnessCacheResult = result
        mindfulnessCachedAt = now
        return result
    }

    /// マインドフルネスデータを手動で更新
    func refreshMindfulness() async {
        let result = await fetchTodayMindfulness()
        todayMindfulnessMinutes = result.minutes
        todayMindfulnessSessions = result.sessions
        todayMindfulnessSamples = result.samples
        print("[HealthKit] 🧘 Refreshed mindfulness: \(result.sessions) sessions, \(String(format: "%.1f", result.minutes)) min")
    }

    /// アプリ内セッションをHealthKitのマインドフルネスとして保存
    func saveMindfulnessSession(
        startDate: Date,
        endDate: Date,
        durationSeconds: TimeInterval = 60,
        sessionType: String = "Breathe"
    ) async -> Bool {
        guard isAvailable else {
            print("[HealthKit] ⚠️ HealthKit not available for mindfulness save")
            return false
        }
        guard let type = HKCategoryType.categoryType(forIdentifier: .mindfulSession) else {
            print("[HealthKit] ⚠️ Mindful session type unavailable")
            return false
        }

        if !isAuthorized {
            await requestAuthorization()
        }

        let normalizedDuration = max(60, durationSeconds)
        let normalizedEndDate = startDate.addingTimeInterval(normalizedDuration)
        let normalizedSessionType = ["Reflect", "Stand"].contains(sessionType) ? sessionType : "Breathe"
        let sample = HKCategorySample(
            type: type,
            value: HKCategoryValue.notApplicable.rawValue,
            start: startDate,
            end: normalizedEndDate,
            metadata: [
                HKMetadataKeyWasUserEntered: true,
                "kfitSessionType": normalizedSessionType
            ]
        )

        let success = await withCheckedContinuation { continuation in
            store.save(sample) { success, error in
                if let error {
                    print("[HealthKit] ❌ Mindfulness save failed: \(error.localizedDescription)")
                } else {
                    print("[HealthKit] ✅ Mindfulness saved: \(success)")
                }
                continuation.resume(returning: success)
            }
        }
        // 新しいセッションを保存したのでキャッシュを無効化（Sendableクロージャの外で実施）
        if success { mindfulnessCacheResult = nil }
        return success
    }

    // MARK: - ワークアウト

    /// 今日のワークアウト時間を取得（分単位）
    func fetchTodayWorkout() async -> Int {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                guard let workouts = samples as? [HKWorkout] else {
                    continuation.resume(returning: 0)
                    return
                }

                var totalMinutes: Double = 0
                for workout in workouts {
                    let duration = workout.duration // 秒単位
                    totalMinutes += duration / 60.0
                }

                continuation.resume(returning: Int(totalMinutes))
            }
            store.execute(query)
        }
    }

    func fetchTodayWorkoutSessions() async -> [WorkoutSession] {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let workouts = samples as? [HKWorkout] else {
                    continuation.resume(returning: [])
                    return
                }

                let sessions = workouts.map { workout in
                    let meta = self.workoutDisplayMeta(for: workout.workoutActivityType)
                    return WorkoutSession(
                        startDate: workout.startDate,
                        endDate: workout.endDate,
                        durationMinutes: workout.duration / 60.0,
                        activityName: meta.name,
                        emoji: meta.emoji,
                        calories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0,
                        sourceName: workout.sourceRevision.source.name,
                        sourceBundleId: workout.sourceRevision.source.bundleIdentifier
                    )
                }
                continuation.resume(returning: sessions)
            }
            store.execute(query)
        }
    }

    private func workoutDisplayMeta(for type: HKWorkoutActivityType) -> (name: String, emoji: String) {
        switch type {
        case .walking: return ("散歩", "🚶")
        case .running: return ("ラン", "🏃")
        case .cycling: return ("自転車", "🚴")
        case .swimming: return ("泳ぎ", "🏊")
        case .functionalStrengthTraining, .traditionalStrengthTraining: return ("筋トレ", "💪")
        case .yoga: return ("ヨガ", "🧘")
        case .hiking: return ("ハイキング", "🥾")
        case .dance: return ("ダンス", "💃")
        case .cooldown: return ("クールダウン", "🧊")
        default: return ("ワークアウト", "🏃")
        }
    }

    // MARK: - スタンド時間

    /// 今日のスタンド時間を取得（時間単位）
    func fetchTodayStand() async -> Int {
        guard let type = HKCategoryType.categoryType(forIdentifier: .appleStandHour) else {
            return 0
        }

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: 0)
                    return
                }

                // スタンドした時間の数をカウント（1サンプル = 1時間）
                let standHours = samples.filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue }.count

                continuation.resume(returning: standHours)
            }
            store.execute(query)
        }
    }

    // MARK: - 日光下時間（iOS 17+）

    private func fetchTodayDaylight() async -> Double {
        guard #available(iOS 17.0, *) else { return 0 }
        guard let type = HKQuantityType.quantityType(forIdentifier: .timeInDaylight) else { return 0 }
        let start = Calendar.current.startOfDay(for: Date())
        let pred  = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await fetchCumulativeSum(type: type, predicate: pred, unit: .minute())
    }

    private func fetchTodayExerciseMinutes() async -> Int {
        guard let type = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) else { return 0 }
        let start = Calendar.current.startOfDay(for: Date())
        let pred  = HKQuery.predicateForSamples(withStart: start, end: Date())
        let value = await fetchCumulativeSum(type: type, predicate: pred, unit: .minute())
        return Int(value)
    }

    private func fetchTodayWorkoutCount() async -> Int {
        let start = Calendar.current.startOfDay(for: Date())
        let pred  = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: pred,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: samples?.count ?? 0)
            }
            store.execute(query)
        }
    }

    // MARK: - 睡眠スコア分析

    /// 睡眠データを分析してスコア化（0-100点）
    /// 計算式: 睡眠時間 50% + 就寝時刻 30% + 睡眠中断 20%
    /// - Parameter targetHours: 目標睡眠時間（デフォルト7時間）
    /// - Returns: 睡眠スコアの分析結果
    func analyzeSleepScore(targetHours: Double = 7.0) -> SleepScoreAnalysis {
        let totalHours = lastNightTotalHours

        // ステージ別時間と覚醒時間・就寝開始時刻を集計
        var deepHours:  Double = 0
        var remHours:   Double = 0
        var coreHours:  Double = 0
        var awakeHours: Double = 0
        var firstSleepStart: Date? = nil

        for segment in sleepSegments.sorted(by: { $0.start < $1.start }) {
            switch segment.stage {
            case .deep:
                deepHours += segment.durationHours
                if firstSleepStart == nil { firstSleepStart = segment.start }
            case .rem:
                remHours += segment.durationHours
                if firstSleepStart == nil { firstSleepStart = segment.start }
            case .core, .unknown:
                coreHours += segment.durationHours
                if firstSleepStart == nil { firstSleepStart = segment.start }
            case .awake:
                awakeHours += segment.durationHours
            case .inBed:
                break
            }
        }

        guard totalHours > 0 else {
            return SleepScoreAnalysis(
                totalHours: 0, deepHours: 0, remHours: 0, coreHours: 0,
                score: 0, rating: "未記録"
            )
        }

        // 1. 睡眠時間スコア（最大50点）: 目標時間に対する実績の比率
        let durationScore = min(totalHours / targetHours, 1.0) * 50.0

        // 2. 就寝時刻スコア（最大30点）: 24:00 以前なら満点、以降は10分遅れるごとに-1点
        var bedtimeScore: Double = 0
        if let sleepStart = firstSleepStart {
            let cal = Calendar.current
            let hour   = Double(cal.component(.hour,   from: sleepStart))
            let minute = Double(cal.component(.minute, from: sleepStart))
            let timeInHours = hour + minute / 60.0
            // 深夜0〜6時は 24〜30 として扱い、就寝時刻の連続性を保つ
            let normalized = timeInHours < 6 ? timeInHours + 24.0 : timeInHours
            let minutesLate = max(0.0, (normalized - 24.0) * 60.0)
            bedtimeScore = max(0.0, 30.0 - minutesLate / 10.0)
        }

        // 3. 睡眠中断スコア（最大20点）: 覚醒割合が0% → 20点、20%以上 → 0点
        let totalPeriod = totalHours + awakeHours
        let awakeRatio  = totalPeriod > 0 ? awakeHours / totalPeriod : 0.0
        let interruptionScore = max(0.0, (1.0 - awakeRatio / 0.20) * 20.0)

        let finalScore = Int(min(100.0, durationScore + bedtimeScore + interruptionScore))

        let rating: String
        switch finalScore {
        case 90...100: rating = "最高"
        case 80..<90:  rating = "良好"
        case 70..<80:  rating = "普通"
        case 50..<70:  rating = "要改善"
        default:       rating = "不十分"
        }

        var result = SleepScoreAnalysis(
            totalHours: totalHours,
            deepHours: deepHours,
            remHours: remHours,
            coreHours: coreHours,
            score: finalScore,
            rating: rating
        )
        result.durationScore     = Int(durationScore)
        result.bedtimeScore      = Int(bedtimeScore)
        result.interruptionScore = Int(interruptionScore)
        result.firstSleepTime    = firstSleepStart
        result.awakeHours        = awakeHours
        result.targetHours       = targetHours
        return result
    }

    // MARK: - PFCバランス分析

    /// PFCバランスを分析して点数化（0-100点）
    /// - Parameter settings: 目標設定（デフォルトは15% / 25% / 60%）
    /// - Returns: PFCバランスの分析結果
    func analyzePFCBalance(settings: IntakeSettings = .defaultSettings) -> PFCBalanceAnalysis {
        // 各栄養素のカロリー換算
        // たんぱく質: 1g = 4kcal
        // 脂質: 1g = 9kcal
        // 炭水化物: 1g = 4kcal
        let proteinKcal = todayIntakeProtein * 4.0
        let fatKcal = todayIntakeFat * 9.0
        let carbsKcal = todayIntakeCarbs * 4.0
        let totalKcal = proteinKcal + fatKcal + carbsKcal

        guard totalKcal > 0 else {
            return PFCBalanceAnalysis(
                proteinPercent: 0, fatPercent: 0, carbsPercent: 0,
                proteinGrams: 0, fatGrams: 0, carbsGrams: 0,
                score: 0, rating: "未記録"
            )
        }

        // 実際の比率（%）
        let actualProteinPercent = (proteinKcal / totalKcal) * 100
        let actualFatPercent = (fatKcal / totalKcal) * 100
        let actualCarbsPercent = (carbsKcal / totalKcal) * 100

        // 目標との差分（絶対値）
        let proteinDiff = abs(actualProteinPercent - settings.targetProteinPercent)
        let fatDiff = abs(actualFatPercent - settings.targetFatPercent)
        let carbsDiff = abs(actualCarbsPercent - settings.targetCarbsPercent)

        // 平均偏差
        let avgDiff = (proteinDiff + fatDiff + carbsDiff) / 3.0

        // スコア計算（偏差が大きいほど減点）
        // 偏差0% → 100点
        // 偏差5% → 90点
        // 偏差10% → 75点
        // 偏差15% → 60点
        // 偏差20% → 40点
        // 偏差30%以上 → 0点
        let score: Int
        if avgDiff <= 5 {
            score = max(0, 100 - Int(avgDiff * 2))
        } else if avgDiff <= 15 {
            score = max(0, 90 - Int((avgDiff - 5) * 3))
        } else if avgDiff <= 25 {
            score = max(0, 60 - Int((avgDiff - 15) * 2))
        } else {
            score = 0
        }

        // 評価
        let rating: String
        switch score {
        case 90...100: rating = "理想的"
        case 80..<90:  rating = "良好"
        case 70..<80:  rating = "まずまず"
        case 50..<70:  rating = "要改善"
        default:       rating = "バランス悪い"
        }

        return PFCBalanceAnalysis(
            proteinPercent: actualProteinPercent,
            fatPercent: actualFatPercent,
            carbsPercent: actualCarbsPercent,
            proteinGrams: todayIntakeProtein,
            fatGrams: todayIntakeFat,
            carbsGrams: todayIntakeCarbs,
            score: score,
            rating: rating
        )
    }

    // MARK: - 栄養素の保存

    /// 食事の栄養素をHealthKitに保存
    func saveMealNutrition(_ nutrition: MealNutrition, date: Date = Date()) async {
        guard isAuthorized else {
            print("[HealthKit] ⚠️ Not authorized to save nutrition data")
            return
        }

        var samples: [HKQuantitySample] = []

        // カロリー
        if let calorieType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) {
            let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: Double(nutrition.calories))
            let sample = HKQuantitySample(type: calorieType, quantity: quantity, start: date, end: date)
            samples.append(sample)
        }

        // たんぱく質
        if let proteinType = HKQuantityType.quantityType(forIdentifier: .dietaryProtein) {
            let quantity = HKQuantity(unit: .gram(), doubleValue: nutrition.protein)
            let sample = HKQuantitySample(type: proteinType, quantity: quantity, start: date, end: date)
            samples.append(sample)
        }

        // 脂質
        if let fatType = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal) {
            let quantity = HKQuantity(unit: .gram(), doubleValue: nutrition.fat)
            let sample = HKQuantitySample(type: fatType, quantity: quantity, start: date, end: date)
            samples.append(sample)
        }

        // 炭水化物
        if let carbsType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates) {
            let quantity = HKQuantity(unit: .gram(), doubleValue: nutrition.carbs)
            let sample = HKQuantitySample(type: carbsType, quantity: quantity, start: date, end: date)
            samples.append(sample)
        }

        // 糖質
        if let sugarType = HKQuantityType.quantityType(forIdentifier: .dietarySugar) {
            let quantity = HKQuantity(unit: .gram(), doubleValue: nutrition.sugar)
            let sample = HKQuantitySample(type: sugarType, quantity: quantity, start: date, end: date)
            samples.append(sample)
        }

        // 食物繊維
        if let fiberType = HKQuantityType.quantityType(forIdentifier: .dietaryFiber) {
            let quantity = HKQuantity(unit: .gram(), doubleValue: nutrition.fiber)
            let sample = HKQuantitySample(type: fiberType, quantity: quantity, start: date, end: date)
            samples.append(sample)
        }

        // ナトリウム（塩分）- 塩分（g）をナトリウム（mg）に変換
        // 塩分1g = ナトリウム約393mg
        if let sodiumType = HKQuantityType.quantityType(forIdentifier: .dietarySodium) {
            let sodiumMg = nutrition.sodium * 393.0  // 塩分をナトリウムに変換
            let quantity = HKQuantity(unit: .gramUnit(with: .milli), doubleValue: sodiumMg)
            let sample = HKQuantitySample(type: sodiumType, quantity: quantity, start: date, end: date)
            samples.append(sample)
        }

        // HealthKitに保存
        do {
            try await store.save(samples)
            print("[HealthKit] ✅ Saved meal nutrition: \(nutrition.calories)kcal, protein:\(nutrition.protein)g, fat:\(nutrition.fat)g, carbs:\(nutrition.carbs)g")
        } catch {
            print("[HealthKit] ❌ Failed to save nutrition: \(error)")
        }
    }
}
