import HealthKit
import Foundation

// MARK: - Data Models

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
    @Published var todayCalories: Double = 0

    // 心拍数
    @Published var latestHeartRate:  Double     = 0
    @Published var restingHeartRate: Double     = 0
    @Published var hrSamples:        [HRSample] = []

    // 睡眠
    @Published var lastNightTotalHours: Double         = 0
    @Published var lastNightDeepHours:  Double         = 0
    @Published var sleepSegments:       [SleepSegment] = []

    // MARK: - 権限セット

    private var readTypes: Set<HKObjectType> {
        var set = Set<HKObjectType>()
        let quantityIds: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .restingHeartRate,
            .stepCount,
            .activeEnergyBurned,
        ]
        for id in quantityIds {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { set.insert(t) }
        }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            set.insert(sleep)
        }
        return set
    }

    private var writeTypes: Set<HKSampleType> {
        var set = Set<HKSampleType>()
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            set.insert(energy)
        }
        set.insert(HKWorkoutType.workoutType())
        return set
    }

    // MARK: - 権限リクエスト

    func requestAuthorization() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            isAuthorized = true
            await fetchAll()
        } catch {
            print("[HealthKit] 権限エラー: \(error)")
        }
    }

    // MARK: - ワークアウト書き込み

    private static let caloriesPerRep: [String: Double] = [
        "pushup": 0.32, "squat": 0.32, "situp": 0.15,
        "lunge": 0.40,  "burpee": 1.00, "plank": 0.08,
    ]

    func saveExercise(exerciseId: String, reps: Int, startDate: Date, endDate: Date) async {
        guard isAvailable else { return }
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
        } catch {
            print("[HealthKit] ❌ 書き込みエラー: \(error)")
        }
    }

    func saveCompletedSet(exercises: [(id: String, name: String, reps: Int)], startDate: Date) async {
        guard isAvailable else { return }
        let endDate = Date()
        let totalKcal = exercises.reduce(0.0) {
            $0 + (Self.caloriesPerRep[$1.id.lowercased()] ?? 0.25) * Double($1.reps)
        }
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
        } catch {
            print("[HealthKit] ❌ セット書き込みエラー: \(error)")
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
        guard isAvailable else { return }
        isLoading = true
        defer { isLoading = false }

        async let steps    = fetchTodaySteps()
        async let calories = fetchTodayCalories()
        async let latHR    = fetchLatestHeartRate()
        async let restHR   = fetchRestingHeartRate()
        async let hrList   = fetchTodayHRSamples()
        async let sleep    = fetchLastNightSleep()

        todaySteps          = await steps
        todayCalories       = await calories
        latestHeartRate     = await latHR
        restingHeartRate    = await restHR
        hrSamples           = await hrList
        let sleepResult     = await sleep
        lastNightTotalHours = sleepResult.total
        lastNightDeepHours  = sleepResult.deep
        sleepSegments       = sleepResult.segments
    }

    // MARK: - 歩数

    private func fetchTodaySteps() async -> Int {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let start = Calendar.current.startOfDay(for: Date())
        let pred  = HKQuery.predicateForSamples(withStart: start, end: Date())
        return Int(await fetchCumulativeSum(type: type, predicate: pred, unit: .count()))
    }

    // MARK: - 消費カロリー

    private func fetchTodayCalories() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return 0 }
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
        let start = cal.date(byAdding: .hour, value: -21, to: today) ?? today
        let end   = cal.date(byAdding: .hour, value: 12,  to: today) ?? now
        let pred  = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type, predicate: pred,
                limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, _ in
                let hkSamples = samples as? [HKCategorySample] ?? []

                var total: TimeInterval = 0
                var deep:  TimeInterval = 0
                var segs:  [SleepSegment] = []

                for s in hkSamples {
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

                // 時系列順にソート
                let sortedSegs = segs.sorted { $0.start < $1.start }
                cont.resume(returning: (total / 3600, deep / 3600, sortedSegs))
            }
            self.store.execute(q)
        }
    }

    private static func sleepStage(from value: Int) -> SleepSegment.SleepStage {
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
}
