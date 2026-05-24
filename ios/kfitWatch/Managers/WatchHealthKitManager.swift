import HealthKit
import Foundation

struct WatchMindfulnessSession: Identifiable {
    let id = UUID()
    let startDate: Date
    let durationMinutes: Double
    let sourceName: String
    let sourceBundleId: String
    let sessionTypeHint: String?

    var typeLabel: String {
        if sessionTypeHint == "Reflect" { return "Reflect" }
        if sessionTypeHint == "Breathe" { return "Breathe" }
        if durationMinutes >= 2.5 && durationMinutes <= 3.5 { return "Reflect" }
        let source = "\(sourceName) \(sourceBundleId)".lowercased()
        if source.contains("reflect") { return "Reflect" }
        if source.contains("breathe") { return "Breathe" }
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
        typeLabel == "Reflect" ? "💭" : "🧘"
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
    @Published var todayStandHours: Int = 0      // 今日のスタンド時間（時間）
    @Published var latestHRV: Double = 0.0             // 最新の心拍変動（ms）
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

    private init() {}

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
            group.addTask { await self.fetchTodayStandHours() }
            group.addTask { await self.fetchTodayDietaryCalories() }
            group.addTask { await self.fetchTodayDietaryWater() }
            group.addTask { await self.fetchTodayDietaryCaffeine() }
            group.addTask { await self.fetchTodayDietaryAlcohol() }
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
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchTodayMindfulness() }
            group.addTask { await self.fetchTodayWorkoutMinutes() }
            group.addTask { await self.fetchTodayDietaryCalories() }
            group.addTask { await self.fetchTodayDietaryWater() }
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
            print("[WatchHealthKit] ⏳ \(scope) fetch skipped; another fetch is running")
            return false
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

        let query = HKStatisticsQuery(
            quantityType: stepType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, result, error in
            Task { @MainActor in
                if let error {
                    print("[WatchHealthKit] Steps query error: \(error)")
                    return
                }
                let steps = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                self?.todaySteps = Int(steps)
                print("[WatchHealthKit] 📊 Steps: \(Int(steps))")
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Calories

    func fetchTodayCalories() async {
        guard let calorieType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }

        let (start, end) = todayBounds()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let query = HKStatisticsQuery(
            quantityType: calorieType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, result, error in
            Task { @MainActor in
                if let error {
                    print("[WatchHealthKit] Calories query error: \(error)")
                    return
                }
                let calories = result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                self?.todayCalories = Int(calories)
                print("[WatchHealthKit] 🔥 Calories: \(Int(calories)) kcal")
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Heart Rate

    func fetchAverageHeartRate() async {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }

        let (start, end) = todayBounds()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let query = HKStatisticsQuery(
            quantityType: heartRateType,
            quantitySamplePredicate: predicate,
            options: .discreteAverage
        ) { [weak self] _, result, error in
            Task { @MainActor in
                if let error {
                    print("[WatchHealthKit] Heart rate query error: \(error)")
                    return
                }
                let bpm = result?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) ?? 0
                self?.averageHeartRate = Int(bpm)
                print("[WatchHealthKit] ❤️ Heart rate: \(Int(bpm)) bpm")
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Sleep

    func fetchSleepHours() async {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return }

        let (start, end) = todayBounds()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: sleepType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            Task { @MainActor in
                if let error {
                    print("[WatchHealthKit] Sleep query error: \(error)")
                    return
                }
                guard let samples = samples as? [HKCategorySample] else { return }

                let totalSeconds = samples
                    .filter { $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                              $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                              $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }

                let hours = totalSeconds / 3600.0
                self?.sleepHours = hours
                print("[WatchHealthKit] 😴 Sleep: \(String(format: "%.1f", hours)) hours")
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Body Mass

    func fetchLatestBodyMass() async {
        guard let bodyMassType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return }
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: bodyMassType,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            Task { @MainActor in
                if let error {
                    print("[WatchHealthKit] Body mass query error: \(error)")
                    return
                }
                guard let sample = samples?.first as? HKQuantitySample else { return }
                let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                self?.latestBodyMass = kg
                print("[WatchHealthKit] ⚖️ Body mass: \(String(format: "%.1f", kg)) kg")
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Body Fat Percentage

    func fetchLatestBodyFatPercentage() async {
        guard let bodyFatType = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) else { return }
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: bodyFatType,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            Task { @MainActor in
                if let error {
                    print("[WatchHealthKit] Body fat query error: \(error)")
                    return
                }
                guard let sample = samples?.first as? HKQuantitySample else { return }
                let pct = sample.quantity.doubleValue(for: .percent()) * 100
                self?.latestBodyFatPercentage = pct
                print("[WatchHealthKit] 📊 Body fat: \(String(format: "%.1f", pct))%")
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Mindfulness

    func fetchTodayMindfulness() async {
        guard let mindfulType = HKCategoryType.categoryType(forIdentifier: .mindfulSession) else { return }

        let (start, end) = todayBounds()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: mindfulType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            Task { @MainActor in
                if let error {
                    print("[WatchHealthKit] Mindfulness query error: \(error)")
                    return
                }
                let mindfulSamples = ((samples as? [HKCategorySample]) ?? []).map { sample in
                    WatchMindfulnessSession(
                        startDate: sample.startDate,
                        durationMinutes: sample.endDate.timeIntervalSince(sample.startDate) / 60.0,
                        sourceName: sample.sourceRevision.source.name,
                        sourceBundleId: sample.sourceRevision.source.bundleIdentifier,
                        sessionTypeHint: sample.metadata?["kfitSessionType"] as? String
                    )
                }
                let count = mindfulSamples.count
                self?.todayMindfulnessSessions = count
                self?.todayMindfulnessSamples = mindfulSamples
                print("[WatchHealthKit] 🧘 Mindfulness sessions: \(count)")
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Workout Minutes

    func fetchTodayWorkoutMinutes() async {
        guard let exerciseType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) else { return }
        let (start, end) = todayBounds()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let query = HKStatisticsQuery(
            quantityType: exerciseType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, result, error in
            Task { @MainActor in
                if let error { print("[WatchHealthKit] WorkoutMinutes error: \(error)"); return }
                let minutes = result?.sumQuantity()?.doubleValue(for: .minute()) ?? 0
                self?.todayWorkoutMinutes = Int(minutes)
                print("[WatchHealthKit] 🏃 WorkoutMinutes: \(Int(minutes))")
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Stand Hours

    func fetchTodayStandHours() async {
        guard let standType = HKCategoryType.categoryType(forIdentifier: .appleStandHour) else { return }
        let (start, end) = todayBounds()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let query = HKSampleQuery(
            sampleType: standType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { [weak self] _, samples, error in
            Task { @MainActor in
                if let error { print("[WatchHealthKit] StandHours error: \(error)"); return }
                let stood = (samples as? [HKCategorySample])?.filter {
                    $0.value == HKCategoryValueAppleStandHour.stood.rawValue
                }.count ?? 0
                self?.todayStandHours = stood
                print("[WatchHealthKit] 🕐 StandHours: \(stood)")
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Heart Rate Variability

    func fetchLatestHRV() async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return }
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: type,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            Task { @MainActor in
                if let error { print("[WatchHealthKit] HRV error: \(error)"); return }
                guard let sample = samples?.first as? HKQuantitySample else { return }
                let ms = sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                self?.latestHRV = ms
                print("[WatchHealthKit] 💓 HRV: \(String(format: "%.1f", ms)) ms")
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Dietary Calories

    func fetchTodayDietaryCalories() async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else { return }
        let (start, end) = todayBounds()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let query = HKStatisticsQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, result, error in
            Task { @MainActor in
                if let error { print("[WatchHealthKit] DietaryCalories error: \(error)"); return }
                let kcal = result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                self?.todayDietaryCalories = kcal
                print("[WatchHealthKit] 🍽️ DietaryCalories: \(Int(kcal)) kcal")
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Dietary Water

    func fetchTodayDietaryWater() async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else { return }
        let (start, end) = todayBounds()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let query = HKStatisticsQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, result, error in
            Task { @MainActor in
                if let error { print("[WatchHealthKit] DietaryWater error: \(error)"); return }
                let ml = result?.sumQuantity()?.doubleValue(for: .literUnit(with: .milli)) ?? 0
                self?.todayDietaryWater = ml
                print("[WatchHealthKit] 💧 DietaryWater: \(Int(ml)) ml")
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Dietary Caffeine

    func fetchTodayDietaryCaffeine() async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryCaffeine) else { return }
        let (start, end) = todayBounds()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let query = HKStatisticsQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, result, error in
            Task { @MainActor in
                if let error { print("[WatchHealthKit] DietaryCaffeine error: \(error)"); return }
                let mg = result?.sumQuantity()?.doubleValue(for: .gramUnit(with: .milli)) ?? 0
                self?.todayDietaryCaffeine = mg
                print("[WatchHealthKit] ☕ DietaryCaffeine: \(Int(mg)) mg")
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Dietary Alcohol (dietaryEnergyConsumed with alcohol metadata)

    func fetchTodayDietaryAlcohol() async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else { return }
        let (start, end) = todayBounds()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let query = HKSampleQuery(
            sampleType: type,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            Task { @MainActor in
                if let error { print("[WatchHealthKit] DietaryAlcohol error: \(error)"); return }
                var totalAlcoholG = 0.0
                for sample in (samples as? [HKQuantitySample]) ?? [] {
                    if let intakeType = sample.metadata?["intake_type"] as? String,
                       intakeType == "alcohol",
                       let alcoholGrams = sample.metadata?["alcohol_grams"] as? Double {
                        totalAlcoholG += alcoholGrams
                    }
                }
                self?.todayDietaryAlcohol = totalAlcoholG
                print("[WatchHealthKit] 🍺 DietaryAlcohol: \(String(format: "%.1f", totalAlcoholG)) g")
            }
        }
        healthStore.execute(query)
    }

    func saveMindfulnessSession(durationMinutes: Int, sessionType: String = "Breathe") async {
        guard let mindfulType = HKCategoryType.categoryType(forIdentifier: .mindfulSession) else {
            print("[WatchHealthKit] ⚠️ Mindfulness type not available")
            return
        }

        let now = Date()
        let startDate = now.addingTimeInterval(-Double(durationMinutes * 60))
        let normalizedSessionType = sessionType == "Reflect" ? "Reflect" : "Breathe"

        let sample = HKCategorySample(
            type: mindfulType,
            value: HKCategoryValue.notApplicable.rawValue,
            start: startDate,
            end: now,
            metadata: [
                HKMetadataKeyWasUserEntered: true,
                "kfitSessionType": normalizedSessionType
            ]
        )

        do {
            try await healthStore.save(sample)
            print("[WatchHealthKit] ✅ Mindfulness session saved: \(durationMinutes) min, type=\(normalizedSessionType)")
            // iOS側に通知してTimeSlotManagerとWatchの表示を即座に同期
            WatchConnectivityManager.shared.sendMindfulnessCompleted()
        } catch {
            print("[WatchHealthKit] ⚠️ Failed to save mindfulness: \(error)")
        }
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
