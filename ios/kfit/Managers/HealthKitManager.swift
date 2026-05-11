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

    // 体重・体脂肪
    @Published var latestBodyMass: Double = 0           // kg
    @Published var latestBodyFatPercentage: Double = 0  // %
    @Published var todayBodyMassMeasurements: Int = 0   // 今日の測定回数

    // 摂取データ（Apple Healthから読み取り）
    @Published var todayIntakeCalories: Double = 0      // kcal
    @Published var todayIntakeWater: Double = 0         // ml
    @Published var todayIntakeCaffeine: Double = 0      // mg
    @Published var todayIntakeAlcohol: Double = 0       // g（純アルコール）

    // MARK: - 権限セット

    private var readTypes: Set<HKObjectType> {
        var set = Set<HKObjectType>()
        let quantityIds: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .restingHeartRate,
            .stepCount,
            .activeEnergyBurned,
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
        return set
    }

    private var writeTypes: Set<HKSampleType> {
        var set = Set<HKSampleType>()
        let writeIds: [HKQuantityTypeIdentifier] = [
            .activeEnergyBurned,
            .dietaryEnergyConsumed,
            .dietaryWater,
            .dietaryCaffeine,
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
        async let calories = fetchTodayCalories()
        async let latHR    = fetchLatestHeartRate()
        async let restHR   = fetchRestingHeartRate()
        async let hrList   = fetchTodayHRSamples()
        async let sleep    = fetchLastNightSleep()
        async let bodyMass = fetchLatestBodyMass()
        async let bodyFat  = fetchLatestBodyFatPercentage()
        async let bodyMassCount = fetchTodayBodyMassMeasurements()
        async let intakeCal = fetchTodayIntakeCalories()
        async let intakeWater = fetchTodayIntakeWater()
        async let intakeCaffeine = fetchTodayIntakeCaffeine()
        async let intakeAlcohol = fetchTodayIntakeAlcohol()

        todaySteps          = await steps
        todayCalories       = await calories
        latestHeartRate     = await latHR
        restingHeartRate    = await restHR
        hrSamples           = await hrList
        let sleepResult     = await sleep
        lastNightTotalHours = sleepResult.total
        lastNightDeepHours  = sleepResult.deep
        sleepSegments       = sleepResult.segments
        latestBodyMass      = await bodyMass
        latestBodyFatPercentage = await bodyFat
        todayBodyMassMeasurements = await bodyMassCount
        todayIntakeCalories = await intakeCal
        todayIntakeWater    = await intakeWater
        todayIntakeCaffeine = await intakeCaffeine
        todayIntakeAlcohol  = await intakeAlcohol

        print("[HealthKit] ✅ Fetched: steps=\(todaySteps), cal=\(Int(todayCalories)), hr=\(Int(latestHeartRate)), sleep=\(String(format: "%.1f", lastNightTotalHours))h, weight=\(String(format: "%.1f", latestBodyMass))kg, bodyFat=\(String(format: "%.1f", latestBodyFatPercentage))%, intake=\(Int(todayIntakeCalories))kcal, water=\(Int(todayIntakeWater))ml, caffeine=\(Int(todayIntakeCaffeine))mg, alcohol=\(String(format: "%.1f", todayIntakeAlcohol))g")
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
    func saveAlcoholIntake(amountMl: Double, alcoholMg: Double, timestamp: Date) async {
        guard isAvailable, isAuthorized else {
            print("[HealthKit] ⚠️ Not authorized - skipping alcohol save")
            return
        }
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else { return }
        // 純アルコール量(g)からカロリーを計算（アルコール1g = 約7kcal）
        let alcoholGrams = alcoholMg / 1000.0
        let estimatedCalories = alcoholGrams * 7.0
        let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: estimatedCalories)
        let metadata: [String: Any] = [
            "intake_type": "alcohol",
            "amount_ml": amountMl,
            "alcohol_mg": alcoholMg,
            "alcohol_grams": alcoholGrams
        ]
        let sample = HKQuantitySample(type: type, quantity: quantity, start: timestamp, end: timestamp, metadata: metadata)
        do {
            try await store.save(sample)
            print("[HealthKit] ✅ Saved alcohol: \(amountMl)ml (\(alcoholGrams)g純アルコール, \(Int(estimatedCalories))kcal)")
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
}
