import HealthKit
import Foundation

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
    @Published var latestBodyMass: Double = 0.0  // 体重 (kg)
    @Published var latestBodyFatPercentage: Double = 0.0  // 体脂肪率 (%)
    @Published var todayMindfulnessSessions: Int = 0  // 今日のマインドフルネスセッション数

    private init() {}

    // MARK: - Authorization

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("[WatchHealthKit] HealthKit not available on this device")
            return
        }

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!,
            HKObjectType.categoryType(forIdentifier: .mindfulSession)!,
        ]

        let typesToWrite: Set<HKSampleType> = [
            HKObjectType.categoryType(forIdentifier: .mindfulSession)!,
        ]

        do {
            try await healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead)
            isAuthorized = true
            print("[WatchHealthKit] ✅ Authorization granted")
            await fetchAllTodayData()
        } catch {
            print("[WatchHealthKit] ⚠️ Authorization error: \(error)")
            isAuthorized = false
        }
    }

    // MARK: - Fetch All Data

    func fetchAllTodayData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchTodaySteps() }
            group.addTask { await self.fetchTodayCalories() }
            group.addTask { await self.fetchAverageHeartRate() }
            group.addTask { await self.fetchSleepHours() }
            group.addTask { await self.fetchLatestBodyMass() }
            group.addTask { await self.fetchLatestBodyFatPercentage() }
            group.addTask { await self.fetchTodayMindfulness() }
        }
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
                let count = samples?.count ?? 0
                self?.todayMindfulnessSessions = count
                print("[WatchHealthKit] 🧘 Mindfulness sessions: \(count)")
            }
        }
        healthStore.execute(query)
    }

    func saveMindfulnessSession(durationMinutes: Int) async {
        guard let mindfulType = HKCategoryType.categoryType(forIdentifier: .mindfulSession) else {
            print("[WatchHealthKit] ⚠️ Mindfulness type not available")
            return
        }

        let now = Date()
        let startDate = now.addingTimeInterval(-Double(durationMinutes * 60))

        let sample = HKCategorySample(
            type: mindfulType,
            value: HKCategoryValue.notApplicable.rawValue,
            start: startDate,
            end: now
        )

        do {
            try await healthStore.save(sample)
            print("[WatchHealthKit] ✅ Mindfulness session saved: \(durationMinutes) min")
        } catch {
            print("[WatchHealthKit] ⚠️ Failed to save mindfulness: \(error)")
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
