import Foundation
import Combine
import HealthKit

// MARK: - Supporting Models（kfit の HealthKitManager と同等）

struct MindfulSession: Identifiable {
    let id = UUID()
    let startDate: Date
    let endDate: Date
    let durationMinutes: Double
    let sourceName: String
    let sourceBundleId: String
    let sessionTypeHint: String?
    var averageHeartRate: Double = 0
    var averageHRV: Double = 0

    var sessionTypeLabel: String {
        if sessionTypeHint == "Breathe" { return "Breathe" }
        if sessionTypeHint == "Reflect" { return "Reflect" }
        if sessionTypeHint == "Stand"   { return "Stand" }
        if durationMinutes >= 2.5 && durationMinutes <= 3.5 { return "Reflect" }
        let b = sourceBundleId.lowercased()
        let n = sourceName.lowercased()
        if b.contains("breathe") || n.contains("breathe") { return "Breathe" }
        if b.contains("reflect") || n.contains("reflect") { return "Reflect" }
        if b.contains("kfit") || n.contains("kfit") || n.contains("fitingo") || n.contains("kmind") { return "Breathe" }
        if b.contains("mindfulness") || n == "マインドフルネス" { return "マインドフルネス" }
        if b.contains("headspace") || n.contains("headspace") { return "Headspace" }
        if b.contains("calm") || n.contains("calm") { return "Calm" }
        return sourceName
    }

    var sessionEmoji: String {
        switch sessionTypeLabel {
        case "Breathe": return "🧘"
        case "Reflect": return "🤸"
        case "Stand":   return "🧍"
        default:        return "🧘"
        }
    }
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

struct SleepScoreAnalysis {
    let totalHours: Double
    let deepHours: Double
    let remHours: Double
    let coreHours: Double
    let score: Int
    let rating: String
    var durationScore: Int = 0
    var bedtimeScore: Int = 0
    var interruptionScore: Int = 0
    var firstSleepTime: Date? = nil
    var awakeHours: Double = 0
    var targetHours: Double = 7.0
}

struct SleepVitalsAnalysis {
    let averageHeartRate: Double
    let averageRespiratoryRate: Double
    let averageOxygenSaturation: Double
    let minimumOxygenSaturation: Double

    static let empty = SleepVitalsAnalysis(
        averageHeartRate: 0, averageRespiratoryRate: 0,
        averageOxygenSaturation: 0, minimumOxygenSaturation: 0
    )

    var hasData: Bool {
        averageHeartRate > 0 || averageRespiratoryRate > 0 || averageOxygenSaturation > 0
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

// MARK: - HealthKitManager

@MainActor
final class HealthKitManager: ObservableObject {

    static let shared = HealthKitManager()
    private let store = HKHealthStore()

    // MARK: - Published

    @Published var isAuthorized: Bool = false
    @Published var isLoading: Bool = false

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // Stress / HRV
    @Published var latestHRV: Double = 0
    @Published var latestHeartRate: Double = 0
    @Published var todayAvgHRV: Double = 0
    @Published var todayAvgHeartRate: Double = 0
    @Published var hrvSamples: [HRVSample] = []
    @Published var weeklyHRVAverages: [DailyHRVAverage] = []

    // Mindfulness
    @Published var todayMindfulnessSessions: Int = 0
    @Published var todayMindfulnessSamples: [MindfulSession] = []
    @Published var todayMindfulnessMinutes: Double = 0

    // Sleep
    @Published var lastNightTotalHours: Double = 0
    @Published var sleepSegments: [SleepSegment] = []
    @Published var sleepVitals: SleepVitalsAnalysis = .empty

    // Activity
    @Published var todayDaylightMinutes: Double = 0
    @Published var todayWorkoutMinutes: Int = 0
    @Published var todayStandHours: Int = 0
    @Published var todaySteps: Int = 0
    @Published var todayActiveCalories: Double = 0

    // Nutrition (PFC)
    @Published var todayProteinG: Double = 0
    @Published var todayFatG: Double = 0
    @Published var todayCarbsG: Double = 0

    private var lastFetchDate: Date? = nil
    private init() {}

    // MARK: - Authorization

    func requestAuthorization() async {
        guard isAvailable else { return }

        var readTypes: Set<HKObjectType> = [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.categoryType(forIdentifier: .mindfulSession)!,
            HKObjectType.categoryType(forIdentifier: .appleStandHour)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
            HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .dietaryProtein)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!,
            HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
            HKObjectType.workoutType(),
        ]
        if #available(iOS 17.0, *) {
            if let daylightType = HKObjectType.quantityType(forIdentifier: .timeInDaylight) {
                readTypes.insert(daylightType)
            }
        }

        let writeTypes: Set<HKSampleType> = [
            HKObjectType.categoryType(forIdentifier: .mindfulSession)!,
        ]

        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            isAuthorized = true
            await fetchMindHealth()
        } catch {
            // 権限拒否でも続行
        }
    }

    // MARK: - Main Fetch

    func fetchMindHealth(force: Bool = false) async {
        if !force, let last = lastFetchDate, Date().timeIntervalSince(last) < 60 { return }
        isLoading = true
        lastFetchDate = Date()

        async let hrv         = fetchHRVSamples()
        async let weeklyHRV   = fetchWeeklyHRVAverages()
        async let latestHR    = fetchLatestHeartRate()
        async let avgHR       = fetchTodayAverageHeartRate()
        async let mindful     = fetchMindfulnessSessions()
        async let sleep       = fetchSleepSegments()
        async let steps       = fetchTodaySteps()
        async let exercise    = fetchTodayExerciseMinutes()
        async let stand       = fetchTodayStandHours()
        async let daylight    = fetchTodayDaylightMinutes()
        async let calories    = fetchTodayActiveCalories()
        async let protein     = fetchTodayNutrient(.dietaryProtein)
        async let fat         = fetchTodayNutrient(.dietaryFatTotal)
        async let carbs       = fetchTodayNutrient(.dietaryCarbohydrates)

        let (
            hrvResult, weeklyHRVResult, latestHRResult, avgHRResult,
            mindfulResult, sleepResult,
            stepsResult, exerciseResult, standResult, daylightResult,
            caloriesResult, proteinResult, fatResult, carbsResult
        ) = await (
            hrv, weeklyHRV, latestHR, avgHR,
            mindful, sleep,
            steps, exercise, stand, daylight,
            calories, protein, fat, carbs
        )

        hrvSamples = hrvResult
        latestHRV = hrvResult.first?.value ?? 0
        todayAvgHRV = hrvResult.isEmpty ? 0 : hrvResult.map(\.value).reduce(0, +) / Double(hrvResult.count)
        weeklyHRVAverages = weeklyHRVResult

        latestHeartRate = latestHRResult
        todayAvgHeartRate = avgHRResult

        todayMindfulnessSamples = mindfulResult
        todayMindfulnessSessions = mindfulResult.filter { Calendar.current.isDateInToday($0.startDate) }.count
        todayMindfulnessMinutes = mindfulResult
            .filter { Calendar.current.isDateInToday($0.startDate) }
            .reduce(0) { $0 + $1.durationMinutes }

        sleepSegments = sleepResult
        let sleepHours = sleepResult.filter { $0.stage != .awake && $0.stage != .inBed }
            .reduce(0) { $0 + $1.durationHours }
        lastNightTotalHours = sleepHours

        if let firstSleep = sleepResult.filter({ $0.stage != .inBed }).first?.start,
           let lastWake  = sleepResult.last?.end {
            sleepVitals = await fetchSleepVitals(from: firstSleep, to: lastWake)
        }

        todaySteps = stepsResult
        todayWorkoutMinutes = exerciseResult
        todayStandHours = standResult
        todayDaylightMinutes = daylightResult
        todayActiveCalories = caloriesResult
        todayProteinG = proteinResult
        todayFatG = fatResult
        todayCarbsG = carbsResult

        isLoading = false
    }

    func refreshMindfulness() async {
        let result = await fetchMindfulnessSessions()
        todayMindfulnessSamples = result
        todayMindfulnessSessions = result.filter { Calendar.current.isDateInToday($0.startDate) }.count
        todayMindfulnessMinutes = result
            .filter { Calendar.current.isDateInToday($0.startDate) }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    // MARK: - Save Mindfulness

    func saveMindfulnessSession(
        startDate: Date,
        endDate: Date,
        durationSeconds: Int,
        sessionType: String
    ) async -> Bool {
        guard isAvailable,
              let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
            return false
        }
        var metadata: [String: Any] = [:]
        metadata["sessionType"] = sessionType
        let sample = HKCategorySample(
            type: mindfulType,
            value: HKCategoryValue.notApplicable.rawValue,
            start: startDate,
            end: endDate,
            metadata: metadata
        )
        do {
            try await store.save(sample)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Sleep Score Analysis

    func analyzeSleepScore(targetHours: Double = 7.0) -> SleepScoreAnalysis {
        let usableSegments = sleepSegments.filter { $0.stage != .inBed }
        guard !usableSegments.isEmpty else {
            return SleepScoreAnalysis(totalHours: 0, deepHours: 0, remHours: 0, coreHours: 0,
                                      score: 0, rating: "データなし", targetHours: targetHours)
        }

        let totalHours      = usableSegments.filter { $0.stage != .awake }.reduce(0) { $0 + $1.durationHours }
        let deepHours       = usableSegments.filter { $0.stage == .deep  }.reduce(0) { $0 + $1.durationHours }
        let remHours        = usableSegments.filter { $0.stage == .rem   }.reduce(0) { $0 + $1.durationHours }
        let coreHours       = usableSegments.filter { $0.stage == .core  }.reduce(0) { $0 + $1.durationHours }
        let awakeHours      = usableSegments.filter { $0.stage == .awake }.reduce(0) { $0 + $1.durationHours }
        let firstSleepTime  = usableSegments.first?.start

        // 睡眠時間スコア（最大 50 点）
        let durationRatio = min(totalHours / targetHours, 1.0)
        let durationScore = Int(durationRatio * 50)

        // 就寝時刻スコア（最大 30 点: 22-24時 → 満点）
        var bedtimeScore = 30
        if let firstSleep = firstSleepTime {
            let hour = Calendar.current.component(.hour, from: firstSleep)
            if hour >= 0 && hour < 3 {
                bedtimeScore = max(0, 30 - (hour + 1) * 5)
            } else if hour >= 3 {
                bedtimeScore = max(0, 30 - (hour - 21) * 5)
            }
        } else {
            bedtimeScore = 0
        }

        // 中断スコア（最大 20 点）
        let awakeRatio = totalHours > 0 ? awakeHours / (totalHours + awakeHours) : 0
        let interruptionScore = max(0, Int((1 - min(awakeRatio * 5, 1)) * 20))

        let total = durationScore + bedtimeScore + interruptionScore
        let rating: String = {
            switch total {
            case 90...: return "最高"
            case 80...: return "良好"
            case 60...: return "普通"
            case 40...: return "要改善"
            default:    return "不十分"
            }
        }()

        var analysis = SleepScoreAnalysis(
            totalHours: totalHours, deepHours: deepHours,
            remHours: remHours, coreHours: coreHours,
            score: total, rating: rating, targetHours: targetHours
        )
        analysis.durationScore     = durationScore
        analysis.bedtimeScore      = bedtimeScore
        analysis.interruptionScore = interruptionScore
        analysis.firstSleepTime    = firstSleepTime
        analysis.awakeHours        = awakeHours
        return analysis
    }

    // MARK: - Private Fetches

    private func fetchHRVSamples() async -> [HRVSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return [] }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: 100, sortDescriptors: [sort]) { _, s, _ in
                let result = (s as? [HKQuantitySample] ?? []).map {
                    HRVSample(date: $0.startDate, value: $0.quantity.doubleValue(for: HKUnit(from: "ms")))
                }
                cont.resume(returning: result)
            }
            store.execute(q)
        }
    }

    private func fetchWeeklyHRVAverages() async -> [DailyHRVAverage] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date()))!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())

        return await withCheckedContinuation { cont in
            let anchorDate = Calendar.current.startOfDay(for: Date())
            let interval = DateComponents(day: 1)
            let q = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage,
                anchorDate: anchorDate,
                intervalComponents: interval
            )
            q.initialResultsHandler = { _, results, _ in
                guard let stats = results else { cont.resume(returning: []); return }
                var averages: [DailyHRVAverage] = []
                stats.enumerateStatistics(from: start, to: Date()) { stat, _ in
                    let value = stat.averageQuantity()?.doubleValue(for: HKUnit(from: "ms")) ?? 0
                    averages.append(DailyHRVAverage(date: stat.startDate, value: value))
                }
                cont.resume(returning: averages)
            }
            store.execute(q)
        }
    }

    private func fetchLatestHeartRate() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return 0 }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, s, _ in
                let bpm = (s as? [HKQuantitySample])?.first?
                    .quantity.doubleValue(for: HKUnit(from: "count/min")) ?? 0
                cont.resume(returning: bpm)
            }
            store.execute(q)
        }
    }

    private func fetchTodayAverageHeartRate() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return 0 }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: 200, sortDescriptors: [sort]) { _, s, _ in
                let samples = (s as? [HKQuantitySample] ?? [])
                guard !samples.isEmpty else { cont.resume(returning: 0); return }
                let avg = samples.map { $0.quantity.doubleValue(for: HKUnit(from: "count/min")) }.reduce(0, +) / Double(samples.count)
                cont.resume(returning: avg)
            }
            store.execute(q)
        }
    }

    private func fetchMindfulnessSessions() async -> [MindfulSession] {
        guard let type = HKObjectType.categoryType(forIdentifier: .mindfulSession) else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: 200, sortDescriptors: [sort]) { _, s, _ in
                let result = (s as? [HKCategorySample] ?? []).map { sample -> MindfulSession in
                    let hint = sample.metadata?["sessionType"] as? String
                    let dur = sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                    return MindfulSession(
                        startDate: sample.startDate,
                        endDate: sample.endDate,
                        durationMinutes: dur,
                        sourceName: sample.sourceRevision.source.name,
                        sourceBundleId: sample.sourceRevision.source.bundleIdentifier,
                        sessionTypeHint: hint
                    )
                }
                cont.resume(returning: result)
            }
            store.execute(q)
        }
    }

    private func fetchSleepSegments() async -> [SleepSegment] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let start = Calendar.current.date(byAdding: .hour, value: -20, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: 200, sortDescriptors: [sort]) { _, s, _ in
                let result = (s as? [HKCategorySample] ?? []).compactMap { sample -> SleepSegment? in
                    let stage: SleepSegment.SleepStage
                    switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
                    case .inBed:      stage = .inBed
                    case .asleepCore: stage = .core
                    case .asleepDeep: stage = .deep
                    case .asleepREM:  stage = .rem
                    case .awake:      stage = .awake
                    case .asleepUnspecified: stage = .unknown
                    default: return nil
                    }
                    return SleepSegment(start: sample.startDate, end: sample.endDate, stage: stage)
                }
                cont.resume(returning: result)
            }
            store.execute(q)
        }
    }

    private func fetchSleepVitals(from start: Date, to end: Date) async -> SleepVitalsAnalysis {
        async let hr   = fetchAverageDuring(type: HKQuantityType.quantityType(forIdentifier: .heartRate)!,
                                            unit: HKUnit(from: "count/min"), start: start, end: end)
        async let resp = fetchAverageDuring(type: HKQuantityType.quantityType(forIdentifier: .respiratoryRate)!,
                                            unit: HKUnit(from: "count/min"), start: start, end: end)
        async let spo2 = fetchAverageDuring(type: HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!,
                                            unit: HKUnit.percent(), start: start, end: end)
        async let minSpo2 = fetchMinDuring(type: HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!,
                                           unit: HKUnit.percent(), start: start, end: end)
        let (hrVal, respVal, spo2Val, minSpo2Val) = await (hr, resp, spo2, minSpo2)
        return SleepVitalsAnalysis(
            averageHeartRate: hrVal,
            averageRespiratoryRate: respVal,
            averageOxygenSaturation: spo2Val > 0 ? spo2Val * 100 : 0,
            minimumOxygenSaturation: minSpo2Val > 0 ? minSpo2Val * 100 : 0
        )
    }

    private func fetchAverageDuring(type: HKQuantityType, unit: HKUnit, start: Date, end: Date) async -> Double {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: 500, sortDescriptors: [sort]) { _, s, _ in
                let samples = s as? [HKQuantitySample] ?? []
                guard !samples.isEmpty else { cont.resume(returning: 0); return }
                let avg = samples.map { $0.quantity.doubleValue(for: unit) }.reduce(0, +) / Double(samples.count)
                cont.resume(returning: avg)
            }
            store.execute(q)
        }
    }

    private func fetchMinDuring(type: HKQuantityType, unit: HKUnit, start: Date, end: Date) async -> Double {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: 500, sortDescriptors: [sort]) { _, s, _ in
                let values = (s as? [HKQuantitySample] ?? []).map { $0.quantity.doubleValue(for: unit) }
                cont.resume(returning: values.min() ?? 0)
            }
            store.execute(q)
        }
    }

    private func fetchTodaySteps() async -> Int {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                let steps = Int(stats?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0)
                cont.resume(returning: steps)
            }
            store.execute(q)
        }
    }

    private func fetchTodayExerciseMinutes() async -> Int {
        guard let type = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) else { return 0 }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                let minutes = Int(stats?.sumQuantity()?.doubleValue(for: HKUnit.minute()) ?? 0)
                cont.resume(returning: minutes)
            }
            store.execute(q)
        }
    }

    private func fetchTodayStandHours() async -> Int {
        guard let type = HKObjectType.categoryType(forIdentifier: .appleStandHour) else { return 0 }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: 24, sortDescriptors: nil) { _, s, _ in
                let stood = (s as? [HKCategorySample] ?? [])
                    .filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue }.count
                cont.resume(returning: stood)
            }
            store.execute(q)
        }
    }

    private func fetchTodayDaylightMinutes() async -> Double {
        guard #available(iOS 17.0, *),
              let type = HKQuantityType.quantityType(forIdentifier: .timeInDaylight) else { return 0 }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                let minutes = stats?.sumQuantity()?.doubleValue(for: HKUnit.minute()) ?? 0
                cont.resume(returning: minutes)
            }
            store.execute(q)
        }
    }

    private func fetchTodayActiveCalories() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return 0 }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                let kcal = stats?.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie()) ?? 0
                cont.resume(returning: kcal)
            }
            store.execute(q)
        }
    }

    private func fetchTodayNutrient(_ identifier: HKQuantityTypeIdentifier) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                let grams = stats?.sumQuantity()?.doubleValue(for: HKUnit.gram()) ?? 0
                cont.resume(returning: grams)
            }
            store.execute(q)
        }
    }
}
