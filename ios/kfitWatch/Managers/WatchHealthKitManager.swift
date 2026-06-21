import HealthKit
import Foundation

struct WatchMindfulnessSession: Identifiable {
    let id = UUID()
    let startDate: Date
    let durationMinutes: Double
    let sourceName: String
    let sourceBundleId: String
    let sessionTypeHint: String?
    var averageHeartRate: Double = 0
    var averageHRV: Double = 0

    var typeLabel: String {
        if sessionTypeHint == "Reflect" { return "3分ストレッチ" }
        if sessionTypeHint == "Breathe" { return "1分瞑想" }
        if durationMinutes >= 2.5 && durationMinutes <= 3.5 { return "3分ストレッチ" }
        let source = "\(sourceName) \(sourceBundleId)".lowercased()
        if source.contains("reflect") { return "3分ストレッチ" }
        if source.contains("breathe") { return "1分瞑想" }
        return "マインドフルネス"
    }

    var sourceLabel: String {
        let source = "\(sourceName) \(sourceBundleId)".lowercased()
        if source.contains("kfit") || source.contains("fitingo") || source.contains("kfitappduo") {
            return "kfit"
        }
        if source.contains("com.apple") || source.contains("mindfulness") || source.contains("breathe") {
            return "標準アプリ"
        }
        return sourceName
    }

    var emoji: String {
        typeLabel == "3分ストレッチ" ? "🤸" : "🧘"
    }
}

struct WatchWellnessVitals: Codable, Equatable {
    var heartRate: Double
    var hrv: Double
    var measuredAt: Date
}

struct WatchMindfulnessImpact: Codable, Identifiable, Equatable {
    var id = UUID()
    var sessionType: String
    var startDate: Date
    var endDate: Date
    var before: WatchWellnessVitals
    var after: WatchWellnessVitals

    var hrvDelta: Double { after.hrv - before.hrv }
    var heartRateDelta: Double { after.heartRate - before.heartRate }
    var stressBefore: Int { Self.stressScore(hrv: before.hrv) }
    var stressAfter: Int { Self.stressScore(hrv: after.hrv) }
    var stressDelta: Int { stressAfter - stressBefore }

    static func stressScore(hrv: Double) -> Int {
        guard hrv > 0 else { return -1 }
        if hrv >= 100 { return 5 }
        if hrv >= 80  { return Int(5  + (100 - hrv) / 20 * 10) }
        if hrv >= 60  { return Int(15 + (80  - hrv) / 20 * 20) }
        if hrv >= 40  { return Int(35 + (60  - hrv) / 20 * 25) }
        if hrv >= 20  { return Int(60 + (40  - hrv) / 20 * 20) }
        return Int(min(95, 80 + (20 - hrv) / 20 * 15))
    }
}

/// Apple Watch用のHealthKitマネージャー
///
/// Watch側で直接HealthKitからデータを取得して表示する。
/// iOS版のHealthKitManagerと同様の機能を提供するが、Watch専用に最適化。
@MainActor
class WatchHealthKitManager: ObservableObject {
    static let shared = WatchHealthKitManager()

    private let healthStore = HKHealthStore()

    @Published var isAuthorized = false
    @Published var todaySteps: Int = 0
    @Published var todayCalories: Int = 0
    @Published var averageHeartRate: Int = 0
    @Published var sleepHours: Double = 0.0
    @Published var latestBodyMass: Double = 0.0
    @Published var latestBodyFatPercentage: Double = 0.0
    @Published var todayMindfulnessSessions: Int = 0
    @Published var todayMindfulnessSamples: [WatchMindfulnessSession] = []
    @Published var todayWorkoutMinutes: Int = 0  // 今日のワークアウト時間（分）
    @Published var todayHKWorkoutCount: Int = 0  // 今日のHKワークアウト件数（Apple Health優先）
    @Published var todayStandHours: Int = 0      // 今日のスタンド時間（時間）
    @Published var latestHRV: Double = 0.0             // 最新の心拍変動（ms）
    @Published var latestMindfulnessImpact: WatchMindfulnessImpact?
    @Published var mindfulnessImpactHistory: [WatchMindfulnessImpact] = []
    @Published var todayDietaryCalories: Double = 0.0  // 今日の摂取カロリー（kcal）
    @Published var todayDietaryWater: Double = 0.0     // 今日の水分摂取（ml）
    @Published var todayDietaryCaffeine: Double = 0.0  // 今日のカフェイン（mg）
    @Published var todayDietaryAlcohol: Double = 0.0   // 今日のアルコール（g）

    // アクティビティリング
    @Published var activityMoveCalories: Double = 0.0
    @Published var activityMoveGoal: Double = 350.0
    @Published var activityExerciseMinutes: Int = 0
    @Published var activityExerciseGoal: Int = 30
    @Published var activityStandHours: Int = 0
    @Published var activityStandGoal: Int = 12

    private var isFetchingAll = false
    private var lastFetchAllAt: Date? = nil
    private var lastScopedFetchAt: [String: Date] = [:]
    private let fetchAllTTL: TimeInterval = 30
    private let mindfulnessImpactKey = "watch.mindfulnessImpact.latest"
    private let mindfulnessImpactHistoryKey = "watch.mindfulnessImpact.history"

    private init() {
        latestMindfulnessImpact = loadLatestMindfulnessImpact()
        mindfulnessImpactHistory = loadMindfulnessImpactHistory()
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("[WatchHealthKit] HealthKit not available on this device")
            return
        }

        var typesToRead = Set<HKObjectType>()
        [
            HKQuantityTypeIdentifier.stepCount,
            .activeEnergyBurned,
            .heartRate,
            .bodyMass,
            .bodyFatPercentage,
            .appleExerciseTime,
            .dietaryEnergyConsumed,
            .dietaryWater,
            .dietaryCaffeine,
            .heartRateVariabilitySDNN
        ].compactMap { HKObjectType.quantityType(forIdentifier: $0) }
            .forEach { typesToRead.insert($0) }
        [
            HKCategoryTypeIdentifier.sleepAnalysis,
            .mindfulSession,
            .appleStandHour
        ].compactMap { HKObjectType.categoryType(forIdentifier: $0) }
            .forEach { typesToRead.insert($0) }
        typesToRead.insert(HKObjectType.activitySummaryType())

        var typesToWrite = Set<HKSampleType>()
        if let mindful = HKObjectType.categoryType(forIdentifier: .mindfulSession) {
            typesToWrite.insert(mindful)
        }

        do {
            try await healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead)
            isAuthorized = true
            print("[WatchHealthKit] ✅ Authorization granted")
            await fetchDashboardData(force: true)
        } catch {
            print("[WatchHealthKit] ⚠️ Authorization error: \(error)")
            isAuthorized = false
        }
    }

    // MARK: - Fetch All Data

    func fetchAllTodayData(force: Bool = false) async {
        if isFetchingAll {
            print("[WatchHealthKit] ⏳ fetchAllTodayData already running - skip")
            return
        }
        if !force, let lastFetchAllAt, Date().timeIntervalSince(lastFetchAllAt) < fetchAllTTL {
            print("[WatchHealthKit] ✅ fetchAllTodayData skipped by TTL")
            return
        }
        isFetchingAll = true
        defer {
            lastFetchAllAt = Date()
            isFetchingAll = false
        }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchTodaySteps() }
            group.addTask { await self.fetchTodayCalories() }
            group.addTask { await self.fetchAverageHeartRate() }
            group.addTask { await self.fetchSleepHours() }
            group.addTask { await self.fetchLatestBodyMass() }
            group.addTask { await self.fetchLatestBodyFatPercentage() }
            group.addTask { await self.fetchTodayMindfulness() }
            group.addTask { await self.fetchTodayWorkoutMinutes() }
            group.addTask { await self.fetchTodayHKWorkouts() }
            group.addTask { await self.fetchTodayStandHours() }
            // W3: 食事/水分/カフェイン/アルコールは iOS Firestore が正源のため HK 直取得を除外
            // スパイラル完了判定は WatchConnectivityManager の値を使用。
            // 摂取入力タブ表示用は fetchIntakeData スコープで個別に取得。
            group.addTask { await self.fetchLatestHRV() }
            group.addTask { await self.fetchActivitySummary() }
        }
    }

    func fetchDashboardData(force: Bool = false) async {
        guard beginScopedFetch("dashboard", force: force, ttl: 20) else { return }
        defer { finishScopedFetch("dashboard") }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchTodaySteps() }
            group.addTask { await self.fetchTodayCalories() }
            group.addTask { await self.fetchAverageHeartRate() }
            group.addTask { await self.fetchTodayWorkoutMinutes() }
            group.addTask { await self.fetchTodayHKWorkouts() }
            group.addTask { await self.fetchTodayMindfulness() }
            group.addTask { await self.fetchActivitySummary() }
        }
    }

    func fetchIntakeData(force: Bool = false) async {
        guard beginScopedFetch("intake", force: force, ttl: 15) else { return }
        defer { finishScopedFetch("intake") }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchTodayDietaryCalories() }
            group.addTask { await self.fetchTodayDietaryWater() }
            group.addTask { await self.fetchTodayDietaryCaffeine() }
            group.addTask { await self.fetchTodayDietaryAlcohol() }
        }
    }

    func fetchWellnessData(force: Bool = false) async {
        guard beginScopedFetch("wellness", force: force, ttl: 20) else { return }
        defer { finishScopedFetch("wellness") }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchAverageHeartRate() }
            group.addTask { await self.fetchLatestHRV() }
            group.addTask { await self.fetchSleepHours() }
            group.addTask { await self.fetchTodayMindfulness() }
            group.addTask { await self.fetchTodayWorkoutMinutes() }
            group.addTask { await self.fetchTodayHKWorkouts() }
        }
    }

    func fetchHealthData(force: Bool = false) async {
        guard beginScopedFetch("health", force: force, ttl: 25) else { return }
        defer { finishScopedFetch("health") }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchTodaySteps() }
            group.addTask { await self.fetchTodayCalories() }
            group.addTask { await self.fetchAverageHeartRate() }
            group.addTask { await self.fetchSleepHours() }
            group.addTask { await self.fetchLatestBodyMass() }
            group.addTask { await self.fetchLatestBodyFatPercentage() }
            group.addTask { await self.fetchTodayWorkoutMinutes() }
            group.addTask { await self.fetchTodayStandHours() }
            group.addTask { await self.fetchActivitySummary() }
        }
    }

    func fetchWatchFaceData(force: Bool = false) async {
        guard beginScopedFetch("watchFace", force: force, ttl: 15) else { return }
        defer { finishScopedFetch("watchFace") }
        // W3: スパイラル完了判定は connectivity 値を使うため、HK 直取得は MF/Workout のみ
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchTodayMindfulness() }
            group.addTask { await self.fetchTodayWorkoutMinutes() }
            group.addTask { await self.fetchTodayHKWorkouts() }
        }
    }

    func fetchData(scope: String, force: Bool = false) async {
        switch scope {
        case "intake":
            await fetchIntakeData(force: force)
        case "wellness":
            await fetchWellnessData(force: force)
        case "health":
            await fetchHealthData(force: force)
        case "watchFace":
            await fetchWatchFaceData(force: force)
        default:
            await fetchDashboardData(force: force)
        }
    }

    private func beginScopedFetch(_ scope: String, force: Bool, ttl: TimeInterval) -> Bool {
        if isFetchingAll {
            if force {
                // 強制更新時は実行中フラグをリセットして続行
                print("[WatchHealthKit] ⚡ \(scope) force-fetch: resetting isFetchingAll")
                isFetchingAll = false
            } else {
                print("[WatchHealthKit] ⏳ \(scope) fetch skipped; another fetch is running")
                return false
            }
        }
        if !force, let last = lastScopedFetchAt[scope], Date().timeIntervalSince(last) < ttl {
            print("[WatchHealthKit] ✅ \(scope) fetch skipped by TTL")
            return false
        }
        isFetchingAll = true
        return true
    }

    private func finishScopedFetch(_ scope: String) {
        lastScopedFetchAt[scope] = Date()
        isFetchingAll = false
    }

    // MARK: - Steps

    func fetchTodaySteps() async {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }
        let (start, end) = todayBounds()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let value: Double = await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                cont.resume(returning: result?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
            }
            healthStore.execute(query)
        }
        await MainActor.run { self.todaySteps = Int(value) }
        print("[WatchHealthKit] 📊 Steps: \(Int(value))")
    }

    // MARK: - Calories

    func fetchTodayCalories() async {
        guard let calorieType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
        let (start, end) = todayBounds()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let value: Double = await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(quantityType: calorieType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                cont.resume(returning: result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)
            }
            healthStore.execute(query)
        }
        await MainActor.run { self.todayCalories = Int(value) }
        print("[WatchHealthKit] 🔥 Calories: \(Int(value)) kcal")
    }

    // MARK: - Heart Rate

    func fetchAverageHeartRate() async {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        let (start, end) = todayBounds()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let value: Double = await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(quantityType: heartRateType, quantitySamplePredicate: predicate, options: .discreteAverage) { _, result, _ in
                cont.resume(returning: result?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) ?? 0)
            }
            healthStore.execute(query)
        }
        await MainActor.run { self.averageHeartRate = Int(value) }
        print("[WatchHealthKit] ❤️ Heart rate: \(Int(value)) bpm")
    }

    // MARK: - Sleep

    func fetchSleepHours() async {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        let (start, end) = todayBounds()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let hours: Double = await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, _ in
                let totalSeconds = (samples as? [HKCategorySample] ?? [])
                    .filter { $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                              $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                              $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                cont.resume(returning: totalSeconds / 3600.0)
            }
            healthStore.execute(query)
        }
        await MainActor.run { self.sleepHours = hours }
        print("[WatchHealthKit] 😴 Sleep: \(String(format: "%.1f", hours)) hours")
    }

    // MARK: - Body Mass

    func fetchLatestBodyMass() async {
        guard let bodyMassType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return }
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let value: Double = await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: bodyMassType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, _ in
                let kg = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: .gramUnit(with: .kilo)) ?? 0
                cont.resume(returning: kg)
            }
            healthStore.execute(query)
        }
        if value > 0 {
            await MainActor.run { self.latestBodyMass = value }
            print("[WatchHealthKit] ⚖️ Body mass: \(String(format: "%.1f", value)) kg")
        }
    }

    // MARK: - Body Fat Percentage

    func fetchLatestBodyFatPercentage() async {
        guard let bodyFatType = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) else { return }
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let value: Double = await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: bodyFatType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, _ in
                let pct = ((samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: .percent()) ?? 0) * 100
                cont.resume(returning: pct)
            }
            healthStore.execute(query)
        }
        if value > 0 {
            await MainActor.run { self.latestBodyFatPercentage = value }
            print("[WatchHealthKit] 📊 Body fat: \(String(format: "%.1f", value))%")
        }
    }

    // MARK: - Mindfulness

    func fetchTodayMindfulness() async {
        guard let mindfulType = HKCategoryType.categoryType(forIdentifier: .mindfulSession) else { return }

        let (start, end) = todayBounds()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let rawSamples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: mindfulType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(query)
        }

        // W4: N+1 直列クエリを withTaskGroup で並列化
        let enriched: [WatchMindfulnessSession] = await withTaskGroup(of: WatchMindfulnessSession.self) { group in
            for sample in rawSamples {
                group.addTask {
                    let sessionPred = HKQuery.predicateForSamples(withStart: sample.startDate, end: sample.endDate, options: .strictStartDate)
                    async let hr = self.averageInWindow(identifier: .heartRate, predicate: sessionPred, unit: HKUnit.count().unitDivided(by: .minute()))
                    async let hrv = self.averageInWindow(identifier: .heartRateVariabilitySDNN, predicate: sessionPred, unit: .secondUnit(with: .milli))
                    let (heartRate, heartRateV) = await (hr, hrv)
                    return WatchMindfulnessSession(
                        startDate: sample.startDate,
                        durationMinutes: sample.endDate.timeIntervalSince(sample.startDate) / 60.0,
                        sourceName: sample.sourceRevision.source.name,
                        sourceBundleId: sample.sourceRevision.source.bundleIdentifier,
                        sessionTypeHint: sample.metadata?["kfitSessionType"] as? String,
                        averageHeartRate: heartRate,
                        averageHRV: heartRateV
                    )
                }
            }
            var results: [WatchMindfulnessSession] = []
            for await session in group { results.append(session) }
            return results.sorted { $0.startDate > $1.startDate }
        }

        let count = enriched.count
        await MainActor.run {
            self.todayMindfulnessSessions = count
            self.todayMindfulnessSamples = enriched
        }
        print("[WatchHealthKit] 🧘 Mindfulness sessions: \(count)")
    }

    private func averageInWindow(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate, unit: HKUnit) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, result, _ in
                cont.resume(returning: result?.averageQuantity()?.doubleValue(for: unit) ?? 0)
            }
            healthStore.execute(q)
        }
    }

    // MARK: - Workout Minutes

    func fetchTodayWorkoutMinutes() async {
        guard let exerciseType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) else { return }
        let (start, end) = todayBounds()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let value: Double = await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(quantityType: exerciseType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                cont.resume(returning: result?.sumQuantity()?.doubleValue(for: .minute()) ?? 0)
            }
            healthStore.execute(query)
        }
        await MainActor.run { self.todayWorkoutMinutes = Int(value) }
        print("[WatchHealthKit] 🏃 WorkoutMinutes: \(Int(value))")
    }

    /// Apple Healthに記録された今日のHKWorkout件数を取得（トレーニング完了判定の正源として利用）
    func fetchTodayHKWorkouts() async {
        let workoutType = HKObjectType.workoutType()
        let (start, end) = todayBounds()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let count: Int = await withCheckedContinuation { cont in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                cont.resume(returning: (samples ?? []).count)
            }
            healthStore.execute(query)
        }
        await MainActor.run { self.todayHKWorkoutCount = count }
        print("[WatchHealthKit] 💪 HKWorkoutCount: \(count)")
    }

    // MARK: - Stand Hours

    func fetchTodayStandHours() async {
        guard let standType = HKCategoryType.categoryType(forIdentifier: .appleStandHour) else { return }
        let (start, end) = todayBounds()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let value: Int = await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: standType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let stood = (samples as? [HKCategorySample])?.filter {
                    $0.value == HKCategoryValueAppleStandHour.stood.rawValue
                }.count ?? 0
                cont.resume(returning: stood)
            }
            healthStore.execute(query)
        }
        await MainActor.run { self.todayStandHours = value }
        print("[WatchHealthKit] 🕐 StandHours: \(value)")
    }

    // MARK: - Heart Rate Variability

    func fetchLatestHRV() async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return }
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let value: Double = await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, _ in
                let ms = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli)) ?? 0
                cont.resume(returning: ms)
            }
            healthStore.execute(query)
        }
        if value > 0 {
            await MainActor.run { self.latestHRV = value }
            print("[WatchHealthKit] 💓 HRV: \(String(format: "%.1f", value)) ms")
        }
    }

    func measureCurrentWellnessVitals() async -> WatchWellnessVitals {
        async let heartRate = latestQuantityValue(identifier: .heartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let hrv = latestQuantityValue(identifier: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        let measuredAt = Date()
        let result = WatchWellnessVitals(heartRate: await heartRate, hrv: await hrv, measuredAt: measuredAt)
        averageHeartRate = Int(result.heartRate)
        latestHRV = result.hrv
        return result
    }

    private func latestQuantityValue(identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    print("[WatchHealthKit] latest \(identifier.rawValue) error: \(error)")
                    cont.resume(returning: 0)
                    return
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    cont.resume(returning: 0)
                    return
                }
                cont.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Dietary Calories

    func fetchTodayDietaryCalories() async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else { return }
        let (start, end) = todayBounds()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let value: Double = await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                cont.resume(returning: result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)
            }
            healthStore.execute(query)
        }
        await MainActor.run { self.todayDietaryCalories = value }
        print("[WatchHealthKit] 🍽️ DietaryCalories: \(Int(value)) kcal")
    }

    // MARK: - Dietary Water

    func fetchTodayDietaryWater() async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else { return }
        let (start, end) = todayBounds()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let value: Double = await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                cont.resume(returning: result?.sumQuantity()?.doubleValue(for: .literUnit(with: .milli)) ?? 0)
            }
            healthStore.execute(query)
        }
        await MainActor.run { self.todayDietaryWater = value }
        print("[WatchHealthKit] 💧 DietaryWater: \(Int(value)) ml")
    }

    // MARK: - Dietary Caffeine

    func fetchTodayDietaryCaffeine() async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryCaffeine) else { return }
        let (start, end) = todayBounds()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let value: Double = await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                cont.resume(returning: result?.sumQuantity()?.doubleValue(for: .gramUnit(with: .milli)) ?? 0)
            }
            healthStore.execute(query)
        }
        await MainActor.run { self.todayDietaryCaffeine = value }
        print("[WatchHealthKit] ☕ DietaryCaffeine: \(Int(value)) mg")
    }

    // MARK: - Dietary Alcohol (dietaryEnergyConsumed with alcohol metadata)

    func fetchTodayDietaryAlcohol() async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else { return }
        let (start, end) = todayBounds()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let value: Double = await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, _ in
                var totalAlcoholG = 0.0
                for sample in (samples as? [HKQuantitySample]) ?? [] {
                    if let intakeType = sample.metadata?["intake_type"] as? String,
                       intakeType == "alcohol",
                       let alcoholGrams = sample.metadata?["alcohol_grams"] as? Double {
                        totalAlcoholG += alcoholGrams
                    }
                }
                cont.resume(returning: totalAlcoholG)
            }
            healthStore.execute(query)
        }
        await MainActor.run { self.todayDietaryAlcohol = value }
        print("[WatchHealthKit] 🍺 DietaryAlcohol: \(String(format: "%.1f", value)) g")
    }

    func saveMindfulnessSession(durationMinutes: Int, sessionType: String = "Breathe", impact: WatchMindfulnessImpact? = nil) async {
        guard let mindfulType = HKCategoryType.categoryType(forIdentifier: .mindfulSession) else {
            print("[WatchHealthKit] ⚠️ Mindfulness type not available")
            return
        }

        let now = Date()
        let startDate = now.addingTimeInterval(-Double(durationMinutes * 60))
        let normalizedSessionType = sessionType == "Reflect" ? "Reflect" : "Breathe"

        var metadata: [String: Any] = [
            HKMetadataKeyWasUserEntered: true,
            "kfitSessionType": normalizedSessionType
        ]
        if let impact {
            metadata["kfitBeforeHeartRate"] = impact.before.heartRate
            metadata["kfitAfterHeartRate"] = impact.after.heartRate
            metadata["kfitBeforeHRV"] = impact.before.hrv
            metadata["kfitAfterHRV"] = impact.after.hrv
            metadata["kfitHRVDelta"] = impact.hrvDelta
            metadata["kfitStressBefore"] = impact.stressBefore
            metadata["kfitStressAfter"] = impact.stressAfter
            metadata["kfitStressDelta"] = impact.stressDelta
        }

        let sample = HKCategorySample(
            type: mindfulType,
            value: HKCategoryValue.notApplicable.rawValue,
            start: startDate,
            end: now,
            metadata: metadata
        )

        do {
            try await healthStore.save(sample)
            if let impact {
                saveLatestMindfulnessImpact(impact)
            }
            print("[WatchHealthKit] ✅ Mindfulness session saved: \(durationMinutes) min, type=\(normalizedSessionType)")
            // iOS側に通知してTimeSlotManagerとWatchの表示を即座に同期
            WatchConnectivityManager.shared.sendMindfulnessCompleted()
        } catch {
            print("[WatchHealthKit] ⚠️ Failed to save mindfulness: \(error)")
        }
    }

    private func saveLatestMindfulnessImpact(_ impact: WatchMindfulnessImpact) {
        latestMindfulnessImpact = impact
        if let data = try? JSONEncoder().encode(impact) {
            UserDefaults.standard.set(data, forKey: mindfulnessImpactKey)
        }
        mindfulnessImpactHistory.insert(impact, at: 0)
        if mindfulnessImpactHistory.count > 30 {
            mindfulnessImpactHistory = Array(mindfulnessImpactHistory.prefix(30))
        }
        if let data = try? JSONEncoder().encode(mindfulnessImpactHistory) {
            UserDefaults.standard.set(data, forKey: mindfulnessImpactHistoryKey)
        }
    }

    private func loadLatestMindfulnessImpact() -> WatchMindfulnessImpact? {
        guard let data = UserDefaults.standard.data(forKey: mindfulnessImpactKey) else { return nil }
        return try? JSONDecoder().decode(WatchMindfulnessImpact.self, from: data)
    }

    private func loadMindfulnessImpactHistory() -> [WatchMindfulnessImpact] {
        guard let data = UserDefaults.standard.data(forKey: mindfulnessImpactHistoryKey) else { return [] }
        return (try? JSONDecoder().decode([WatchMindfulnessImpact].self, from: data)) ?? []
    }

    // MARK: - Activity Summary

    func fetchActivitySummary() async {
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        var components = cal.dateComponents([.era, .year, .month, .day], from: Date())
        components.calendar = cal
        let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: components, end: components)

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let q = HKActivitySummaryQuery(predicate: predicate) { [weak self] _, summaries, _ in
                Task { @MainActor in
                    guard let self, let summary = summaries?.first else {
                        cont.resume()
                        return
                    }
                    self.activityMoveCalories    = summary.activeEnergyBurned.doubleValue(for: .kilocalorie())
                    let goalKcal                 = summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
                    self.activityMoveGoal        = goalKcal > 0 ? goalKcal : 350
                    self.activityExerciseMinutes = Int(summary.appleExerciseTime.doubleValue(for: .minute()))
                    let goalMin                  = Int(summary.appleExerciseTimeGoal.doubleValue(for: .minute()))
                    self.activityExerciseGoal    = goalMin > 0 ? goalMin : 30
                    self.activityStandHours      = Int(summary.appleStandHours.doubleValue(for: .count()))
                    let goalHrs                  = Int(summary.appleStandHoursGoal.doubleValue(for: .count()))
                    self.activityStandGoal       = goalHrs > 0 ? goalHrs : 12
                    print("[WatchHealthKit] 🏃 Activity rings — Move: \(Int(self.activityMoveCalories))/\(Int(self.activityMoveGoal)) Exercise: \(self.activityExerciseMinutes)/\(self.activityExerciseGoal) Stand: \(self.activityStandHours)/\(self.activityStandGoal)")
                    cont.resume()
                }
            }
            healthStore.execute(q)
        }
    }

    // MARK: - Helpers

    private func todayBounds() -> (Date, Date) {
        let now = Date()
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return (start, end)
    }
}
