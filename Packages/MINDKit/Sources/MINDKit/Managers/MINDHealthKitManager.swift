import Foundation
import HealthKit

// MARK: - MINDKit 専用 HealthKit マネージャー
// kfit の HealthKitManager とは独立して動作します。
// kmind アプリはこのクラスを直接使います。
// kfit からは既存の HealthKitManager を継続使用し、
// MIND専用メソッドのみこちらに委譲することも可能です。

@MainActor
public final class MINDHealthKitManager: ObservableObject {

    public static let shared = MINDHealthKitManager()
    private let store = HKHealthStore()

    // MARK: - Published プロパティ
    @Published public var sleepData: [SleepData] = []
    @Published public var sleepScore: SleepScore? = nil
    @Published public var todayHRV: Double? = nil
    @Published public var hrv7Days: [HRVData] = []
    @Published public var todayMindfulnessMinutes: Int = 0
    @Published public var mindfulnessSessions: [MindfulnessSession] = []
    @Published public var isAuthorized: Bool = false

    private init() {}

    // MARK: - 認証
    public func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let readTypes: Set<HKObjectType> = [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.categoryType(forIdentifier: .mindfulSession)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .respiratoryRate)!
        ]

        try await store.requestAuthorization(toShare: [], read: readTypes)
        isAuthorized = true
        await refreshAll()
    }

    // MARK: - 全データ更新
    public func refreshAll() async {
        async let sleep    = fetchSleepData()
        async let hrv      = fetchHRV()
        async let mindful  = fetchMindfulnessSessions()

        let (sleepResult, hrvResult, mindfulResult) = await (sleep, hrv, mindful)
        self.sleepData = sleepResult
        self.sleepScore = calculateSleepScore(from: sleepResult)
        self.hrv7Days = hrvResult
        self.todayHRV = hrvResult.first?.value
        self.mindfulnessSessions = mindfulResult
        self.todayMindfulnessMinutes = mindfulResult
            .filter { Calendar.current.isDateInToday($0.startDate) }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    // MARK: - 睡眠データ取得
    private func fetchSleepData() async -> [SleepData] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return []
        }
        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.date(byAdding: .day, value: -1, to: Date()),
            end: Date()
        )
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                let result = (samples as? [HKCategorySample] ?? []).compactMap { sample -> SleepData? in
                    let stage: SleepStage
                    switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
                    case .awake:                  stage = .awake
                    case .asleepREM:              stage = .rem
                    case .asleepDeep:             stage = .deep
                    case .asleepCore:             stage = .light
                    case .inBed:                  stage = .inBed
                    default:                      stage = .light
                    }
                    return SleepData(startDate: sample.startDate, endDate: sample.endDate, stage: stage)
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    // MARK: - HRV取得（直近7日）
    private func fetchHRV() async -> [HRVData] {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            return []
        }
        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.date(byAdding: .day, value: -7, to: Date()),
            end: Date()
        )
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: predicate,
                limit: 14,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                let result = (samples as? [HKQuantitySample] ?? []).map { sample in
                    HRVData(
                        date: sample.startDate,
                        value: sample.quantity.doubleValue(for: .init(from: "ms"))
                    )
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    // MARK: - マインドフルネスセッション取得
    private func fetchMindfulnessSessions() async -> [MindfulnessSession] {
        guard let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
            return []
        }
        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.startOfDay(for: Date()),
            end: Date()
        )

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: mindfulType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let result = (samples as? [HKCategorySample] ?? []).map { sample in
                    MindfulnessSession(startDate: sample.startDate, endDate: sample.endDate)
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    // MARK: - 睡眠スコア計算
    private func calculateSleepScore(from data: [SleepData]) -> SleepScore? {
        guard !data.isEmpty else { return nil }

        let totalMinutes = data
            .filter { $0.stage != .inBed && $0.stage != .awake }
            .reduce(0) { $0 + $1.durationMinutes }

        let deepMinutes = data.filter { $0.stage == .deep }.reduce(0) { $0 + $1.durationMinutes }
        let remMinutes  = data.filter { $0.stage == .rem  }.reduce(0) { $0 + $1.durationMinutes }

        // スコア計算（各要素 0-100）
        let durationScore    = min(100, Int(Double(totalMinutes) / 480.0 * 100)) // 8時間を満点
        let deepRatio        = totalMinutes > 0 ? Double(deepMinutes + remMinutes) / Double(totalMinutes) : 0
        let qualityScore     = min(100, Int(deepRatio / 0.4 * 100)) // 40%を満点
        let consistencyScore = 70 // TODO: 過去7日との比較で計算

        let total = Int(Double(durationScore) * 0.4 + Double(qualityScore) * 0.4 + Double(consistencyScore) * 0.2)

        return SleepScore(
            total: total,
            durationScore: durationScore,
            qualityScore: qualityScore,
            consistencyScore: consistencyScore
        )
    }

    // MARK: - Watch 連携用データ生成
    public func makeWatchMindData() -> WatchMindData {
        WatchMindData(
            currentHRV: todayHRV,
            sleepScore: sleepScore?.total,
            todayMindfulnessMinutes: todayMindfulnessMinutes,
            stressLevel: {
                guard let hrv = todayHRV else { return "moderate" }
                return HRVData(date: Date(), value: hrv).stressLevel.rawValue
            }()
        )
    }
}
