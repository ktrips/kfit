import HealthKit
import Foundation

// MARK: - Data Models

struct MindfulSession: Identifiable {
    let id = UUID()
    let startDate: Date
    let durationMinutes: Double
    let sourceName: String
}

struct HRSample: Identifiable {
    let id   = UUID()
    let date: Date
    let bpm:  Double
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
    @Published var latestHeartRate:  Double     = 0
    @Published var restingHeartRate: Double     = 0
    @Published var latestHRV:        Double     = 0  // 心拍変動（ms）
    @Published var hrSamples:        [HRSample] = []

    // 睡眠
    @Published var lastNightTotalHours: Double         = 0
    @Published var lastNightDeepHours:  Double         = 0
    @Published var sleepSegments:       [SleepSegment] = []

    // 体重・体脂肪
    @Published var latestBodyMass: Double = 0              // kg
    @Published var latestBodyFatPercentage: Double = 0     // %
    @Published var todayBodyMassMeasurements: Int = 0      // 今日の測定回数
    @Published var weeklyBodyMassChange: Double? = nil     // 1週間の体重変動（kg）nil=データ不足
    @Published var weeklyBodyFatChange: Double? = nil      // 1週間の体脂肪変動（%）nil=データ不足

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
    private var previousMindfulnessSessions: Int = 0     // 前回のセッション数（差分検出用）

    // ワークアウト
    @Published var todayWorkoutMinutes: Int = 0         // 今日のワークアウト時間（分）

    // スタンド時間
    @Published var todayStandHours: Int = 0             // 今日のスタンド時間（時間）

    // 日光下時間（iOS 17+）
    @Published var todayDaylightMinutes: Double = 0     // 今日の日光下時間（分）

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
        ]
        for id in writeIds {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { set.insert(t) }
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

    func saveCompletedSet(exercises: [(id: String, name: String, reps: Int)], startDate: Date) async {
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
        let workout = HKWorkout(
            activityType: .functionalStrengthTraining,
            start: startDate, end: endDate,
            duration: max(endDate.timeIntervalSince(startDate), 1),
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: totalKcal),
            totalDistance: nil, metadata: nil
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

    func fetchAll() async {
        guard isAvailable else {
            print("[HealthKit] HealthKit not available - skipping fetch")
            return
        }
        guard isAuthorized else {
            print("[HealthKit] Not authorized - skipping fetch")
            return
        }

        print("[HealthKit] 🔄 Fetching all health data...")
        isLoading = true
        defer { isLoading = false }

        async let steps    = fetchTodaySteps()
        async let activeCalories = fetchTodayActiveCalories()
        async let restingCalories = fetchTodayRestingCalories()
        async let latHR    = fetchLatestHeartRate()
        async let restHR   = fetchRestingHeartRate()
        async let hrv      = fetchLatestHRV()
        async let hrList   = fetchTodayHRSamples()
        async let sleep    = fetchLastNightSleep()
        async let bodyMass = fetchLatestBodyMass()
        async let bodyFat  = fetchLatestBodyFatPercentage()
        async let bodyMassCount = fetchTodayBodyMassMeasurements()
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

        todaySteps          = await steps
        todayActiveCalories = await activeCalories
        todayRestingCalories = await restingCalories
        todayTotalCalories  = todayActiveCalories + todayRestingCalories
        todayCalories       = todayActiveCalories  // 後方互換性
        latestHeartRate     = await latHR
        restingHeartRate    = await restHR
        latestHRV           = await hrv
        hrSamples           = await hrList
        let sleepResult     = await sleep
        lastNightTotalHours = sleepResult.total
        lastNightDeepHours  = sleepResult.deep
        sleepSegments       = sleepResult.segments
        latestBodyMass          = await bodyMass
        latestBodyFatPercentage = await bodyFat
        todayBodyMassMeasurements = await bodyMassCount
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
            let now = Date()
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: now)
            let timeSlot: TimeSlot
            if hour >= 6 && hour < 10 { timeSlot = .morning }
            else if hour >= 10 && hour < 14 { timeSlot = .noon }
            else if hour >= 14 && hour < 18 { timeSlot = .afternoon }
            else { timeSlot = .evening }

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

        print("[HealthKit] ✅ Fetched: steps=\(todaySteps), active=\(Int(todayActiveCalories))kcal, resting=\(Int(todayRestingCalories))kcal, total=\(Int(todayTotalCalories))kcal, hr=\(Int(latestHeartRate)), hrv=\(String(format: "%.1f", latestHRV))ms, sleep=\(String(format: "%.1f", lastNightTotalHours))h, daylight=\(Int(todayDaylightMinutes))min, weight=\(String(format: "%.1f", latestBodyMass))kg, bodyFat=\(String(format: "%.1f", latestBodyFatPercentage))%, intake=\(Int(todayIntakeCalories))kcal, P:\(String(format: "%.1f", todayIntakeProtein))g, F:\(String(format: "%.1f", todayIntakeFat))g, C:\(String(format: "%.1f", todayIntakeCarbs))g, water=\(Int(todayIntakeWater))ml, caffeine=\(Int(todayIntakeCaffeine))mg, alcohol=\(String(format: "%.1f", todayIntakeAlcohol))g, mindfulness=\(String(format: "%.1f", todayMindfulnessMinutes))min (\(todayMindfulnessSessions) sessions)")
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

    /// 後方互換性のため
    private func fetchTodayCalories() async -> Double {
        return await fetchTodayActiveCalories()
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

    // MARK: - 昨夜の睡眠

    private func fetchLastNightSleep() async -> (total: Double, deep: Double, segments: [SleepSegment]) {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            return (0, 0, [])
        }

        // 前日 15:00 〜 今日 12:00 の範囲で取得
        let cal   = Calendar.current
        let now   = Date()
        let today = cal.startOfDay(for: now)
        let start = cal.date(byAdding: .hour, value: -9, to: today) ?? today  // 前日15:00
        let end   = cal.date(byAdding: .hour, value: 12, to: today) ?? now    // 当日12:00
        let pred  = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type, predicate: pred,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                let hkSamples = samples as? [HKCategorySample] ?? []

                // Core/Deep/REM のステージデータを持つソース（Watch等）を特定
                let stagedSourceIds = Set(hkSamples
                    .filter { [4, 5, 6].contains($0.value) }
                    .map { $0.sourceRevision.source.bundleIdentifier }
                )

                // ステージデータがあるソースのみ使用し InBed(1) を除外して重複カウントを防ぐ
                // ステージデータがない場合は全データを使用
                let filtered: [HKCategorySample]
                if !stagedSourceIds.isEmpty {
                    filtered = hkSamples.filter {
                        stagedSourceIds.contains($0.sourceRevision.source.bundleIdentifier)
                        && $0.value != 1  // InBed を除外
                    }
                } else {
                    filtered = hkSamples
                }

                var total: TimeInterval = 0
                var deep:  TimeInterval = 0
                var segs:  [SleepSegment] = []

                for s in filtered {
                    let dur   = s.endDate.timeIntervalSince(s.startDate)
                    let stage = Self.sleepStage(from: s.value)
                    segs.append(SleepSegment(start: s.startDate, end: s.endDate, stage: stage))
                    switch stage {
                    case .core, .deep, .rem, .unknown:
                        total += dur
                        if stage == .deep { deep += dur }
                    case .inBed, .awake:
                        break
                    }
                }

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

    // MARK: - 摂取記録の書き込み

    /// 食事カロリーを Apple Health に記録
    func saveDietaryEnergy(calories: Double, timestamp: Date) async {
        guard isAvailable, isAuthorized else {
            print("[HealthKit] ⚠️ Not authorized - skipping dietary energy save")
            return
        }
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else { return }
        let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: calories)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: timestamp, end: timestamp)
        do {
            try await store.save(sample)
            print("[HealthKit] ✅ Saved dietary energy: \(calories)kcal")
        } catch {
            print("[HealthKit] ❌ 食事記録エラー: \(error.localizedDescription)")
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
    /// NOTE: HealthKit にはアルコール専用の型がないため、dietaryEnergyConsumed にメタデータとして保存
    func saveAlcoholIntake(amountMl: Double, alcoholG: Double, timestamp: Date) async {
        guard isAvailable, isAuthorized else {
            print("[HealthKit] ⚠️ Not authorized - skipping alcohol save")
            return
        }
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else { return }
        // 純アルコール量(g)からカロリーを計算（アルコール1g = 約7kcal）
        let estimatedCalories = alcoholG * 7.0
        let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: estimatedCalories)
        let metadata: [String: Any] = [
            "intake_type": "alcohol",
            "amount_ml": amountMl,
            "alcohol_grams": alcoholG
        ]
        let sample = HKQuantitySample(type: type, quantity: quantity, start: timestamp, end: timestamp, metadata: metadata)
        do {
            try await store.save(sample)
            print("[HealthKit] ✅ Saved alcohol: \(amountMl)ml (\(alcoholG)g純アルコール, \(Int(estimatedCalories))kcal)")
        } catch {
            print("[HealthKit] ❌ アルコール記録エラー: \(error.localizedDescription)")
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

    /// 今日のマインドフルネスセッションを取得
    func fetchTodayMindfulness() async -> (minutes: Double, sessions: Int, samples: [MindfulSession]) {
        guard let type = HKCategoryType.categoryType(forIdentifier: .mindfulSession) else {
            return (0, 0, [])
        }

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: (0, 0, []))
                    return
                }

                var totalMinutes: Double = 0
                var mindfulSamples: [MindfulSession] = []
                for sample in samples {
                    let duration = sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                    totalMinutes += duration
                    mindfulSamples.append(MindfulSession(
                        startDate: sample.startDate,
                        durationMinutes: duration,
                        sourceName: sample.sourceRevision.source.name
                    ))
                }

                continuation.resume(returning: (totalMinutes, samples.count, mindfulSamples))
            }
            store.execute(query)
        }
    }

    /// マインドフルネスデータを手動で更新
    func refreshMindfulness() async {
        let result = await fetchTodayMindfulness()
        todayMindfulnessMinutes = result.minutes
        todayMindfulnessSessions = result.sessions
        todayMindfulnessSamples = result.samples
        print("[HealthKit] 🧘 Refreshed mindfulness: \(result.sessions) sessions, \(String(format: "%.1f", result.minutes)) min")
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

    // MARK: - 睡眠スコア分析

    /// 睡眠データを分析してスコア化（0-100点）
    /// - Parameter targetHours: 目標睡眠時間（デフォルト7時間）
    /// - Returns: 睡眠スコアの分析結果
    func analyzeSleepScore(targetHours: Double = 7.0) -> SleepScoreAnalysis {
        let totalHours = lastNightTotalHours
        let deepHours = lastNightDeepHours

        // 各ステージの時間を計算
        var remHours: Double = 0
        var coreHours: Double = 0
        for segment in sleepSegments {
            switch segment.stage {
            case .rem:
                remHours += segment.durationHours
            case .core:
                coreHours += segment.durationHours
            default:
                break
            }
        }

        guard totalHours > 0 else {
            return SleepScoreAnalysis(
                totalHours: 0, deepHours: 0, remHours: 0, coreHours: 0,
                score: 0, rating: "未記録"
            )
        }

        // スコア計算（100点満点）
        var score = 0.0

        // 1. 睡眠時間スコア（最大40点）
        // 目標時間±30分以内: 40点
        // 6-8時間: 30-40点
        // 5-6時間 or 8-9時間: 20-30点
        // 5時間未満 or 9時間以上: 0-20点
        let hoursDiff = abs(totalHours - targetHours)
        if hoursDiff <= 0.5 {
            score += 40
        } else if totalHours >= 6 && totalHours <= 8 {
            score += 40 - (hoursDiff * 10)
        } else if totalHours >= 5 && totalHours <= 9 {
            score += 30 - (abs(totalHours - 7) * 5)
        } else {
            score += max(0, 20 - (abs(totalHours - 7) * 5))
        }

        // 2. 深い睡眠スコア（最大30点）
        // 目安: 総睡眠の15-20%が理想
        let deepPercent = (deepHours / totalHours) * 100
        if deepPercent >= 15 && deepPercent <= 25 {
            score += 30
        } else if deepPercent >= 10 && deepPercent < 15 {
            score += 20 + ((deepPercent - 10) * 2)
        } else if deepPercent > 25 && deepPercent <= 30 {
            score += 25
        } else {
            score += max(0, 10)
        }

        // 3. REM睡眠スコア（最大20点）
        // 目安: 総睡眠の20-25%が理想
        let remPercent = (remHours / totalHours) * 100
        if remPercent >= 18 && remPercent <= 28 {
            score += 20
        } else if remPercent >= 12 && remPercent < 18 {
            score += 10 + ((remPercent - 12) * 1.5)
        } else if remPercent > 28 && remPercent <= 35 {
            score += 15
        } else {
            score += max(0, 5)
        }

        // 4. 睡眠効率スコア（最大10点）
        // 深い睡眠 + REM睡眠の合計が多いほど良い
        let qualitySleepPercent = ((deepHours + remHours) / totalHours) * 100
        if qualitySleepPercent >= 40 {
            score += 10
        } else if qualitySleepPercent >= 30 {
            score += 5 + ((qualitySleepPercent - 30) * 0.5)
        } else {
            score += max(0, qualitySleepPercent * 0.2)
        }

        let finalScore = Int(min(100, max(0, score)))

        // 評価
        let rating: String
        switch finalScore {
        case 90...100: rating = "最高"
        case 80..<90:  rating = "良好"
        case 70..<80:  rating = "普通"
        case 50..<70:  rating = "要改善"
        default:       rating = "不十分"
        }

        return SleepScoreAnalysis(
            totalHours: totalHours,
            deepHours: deepHours,
            remHours: remHours,
            coreHours: coreHours,
            score: finalScore,
            rating: rating
        )
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
