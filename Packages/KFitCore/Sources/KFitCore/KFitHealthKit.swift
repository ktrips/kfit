import Foundation
import HealthKit

// MARK: - 共有 HealthKit データモデル
//
// kfit / kmind / kfitWatch 全ターゲットで同一の型を使用するための
// 単一定義。各アプリが独自に定義していたモデルはこちらに統合する。
//
// ── 移行ガイド ────────────────────────────────────────────────────
// [kfit] ios/kfit/Managers/HealthKitManager.swift にある
//        HRVSample / DailyHRVAverage / SleepSegment / SleepScoreAnalysis
//        は KFitCore 統合後に削除してこちらを参照する。
//
// [kmind] kmind/kmind/Managers/HealthKitManager.swift の同名モデルも同様。
//
// [kfitWatch] WatchHealthKitManager.swift の WatchWellnessVitals / WatchMindfulnessImpact は
//             Watch 固有のため残すが、 stressScore のロジックは KFitHRV.stressInfoFromHRV で統一。
// ────────────────────────────────────────────────────────────────────

/// HRV（心拍変動）サンプル 1 件。
public struct HRVSample: Identifiable, Sendable {
    public let id = UUID()
    public let date: Date
    public let value: Double  // ms（SDNN）

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// 日別 HRV 平均値。
public struct DailyHRVAverage: Identifiable, Sendable {
    public let id = UUID()
    public let date: Date
    public let value: Double  // ms

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// 睡眠セグメント（1 ステージ分）。
public struct SleepSegment: Identifiable, Sendable {
    public let id = UUID()
    public let start: Date
    public let end: Date
    public let stage: Stage

    public init(start: Date, end: Date, stage: Stage) {
        self.start = start
        self.end = end
        self.stage = stage
    }

    public var durationHours: Double { end.timeIntervalSince(start) / 3600 }

    public enum Stage: String, Sendable {
        case inBed   = "就寝"
        case core    = "コア"
        case deep    = "深い睡眠"
        case rem     = "REM"
        case awake   = "覚醒"
        case unknown = "睡眠"

        /// Duolingo カラーパレットに合わせたステージ色（hex 文字列）。
        public var hexColor: String {
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

/// 睡眠スコア分析結果。
public struct SleepScoreAnalysis: Sendable {
    public let totalHours: Double
    public let deepHours: Double
    public let remHours: Double
    public let coreHours: Double
    public let score: Int
    public let rating: String
    public var durationScore: Int = 0
    public var bedtimeScore: Int = 0
    public var interruptionScore: Int = 0
    public var firstSleepTime: Date? = nil
    public var awakeHours: Double = 0
    public var targetHours: Double = 7.0

    public init(
        totalHours: Double, deepHours: Double,
        remHours: Double, coreHours: Double,
        score: Int, rating: String, targetHours: Double = 7.0
    ) {
        self.totalHours  = totalHours
        self.deepHours   = deepHours
        self.remHours    = remHours
        self.coreHours   = coreHours
        self.score       = score
        self.rating      = rating
        self.targetHours = targetHours
    }
}

// MARK: - 睡眠スコア計算（単一実装）

/// 睡眠セグメントから睡眠スコアを計算する。
///
/// kfit / kmind 両方の `analyzeSleepScore()` はこの関数に委譲することで
/// 計算ロジックの重複を排除できる。
///
/// - Parameters:
///   - segments: `lastNightSleepSegments()` で取得したセグメント列。
///   - targetHours: 目標睡眠時間（デフォルト 7 時間）。
/// - Returns: 合計 100 点満点の `SleepScoreAnalysis`。
public func computeSleepScore(
    segments: [SleepSegment],
    targetHours: Double = 7.0
) -> SleepScoreAnalysis {
    let usable = segments.filter { $0.stage != .inBed }
    guard !usable.isEmpty else {
        return SleepScoreAnalysis(
            totalHours: 0, deepHours: 0, remHours: 0, coreHours: 0,
            score: 0, rating: "データなし", targetHours: targetHours
        )
    }

    let totalHours      = usable.filter { $0.stage != .awake }.reduce(0) { $0 + $1.durationHours }
    let deepHours       = usable.filter { $0.stage == .deep  }.reduce(0) { $0 + $1.durationHours }
    let remHours        = usable.filter { $0.stage == .rem   }.reduce(0) { $0 + $1.durationHours }
    let coreHours       = usable.filter { $0.stage == .core  }.reduce(0) { $0 + $1.durationHours }
    let awakeHours      = usable.filter { $0.stage == .awake }.reduce(0) { $0 + $1.durationHours }
    let firstSleepTime  = usable.first?.start

    // 睡眠時間スコア（最大 50 点）
    let durationScore = Int(min(totalHours / targetHours, 1.0) * 50)

    // 就寝時刻スコア（最大 30 点: 22–24 時 → 満点）
    var bedtimeScore = 30
    if let first = firstSleepTime {
        let hour = Calendar.current.component(.hour, from: first)
        if hour >= 0 && hour < 3 {
            bedtimeScore = max(0, 30 - (hour + 1) * 5)
        } else if hour >= 3 {
            bedtimeScore = max(0, 30 - (hour - 21) * 5)
        }
    } else {
        bedtimeScore = 0
    }

    // 中断スコア（最大 20 点）
    let awakeRatio        = totalHours > 0 ? awakeHours / (totalHours + awakeHours) : 0
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

    var result = SleepScoreAnalysis(
        totalHours: totalHours, deepHours: deepHours,
        remHours: remHours, coreHours: coreHours,
        score: total, rating: rating, targetHours: targetHours
    )
    result.durationScore     = durationScore
    result.bedtimeScore      = bedtimeScore
    result.interruptionScore = interruptionScore
    result.firstSleepTime    = firstSleepTime
    result.awakeHours        = awakeHours
    return result
}

// MARK: - HealthKit クエリユーティリティ

/// HKHealthStore への非同期クエリをラップした静的ユーティリティ。
///
/// 各アプリの `HealthKitManager` はこれらの関数を呼び出すことで
/// HealthKit 取得ロジックの重複実装を排除できる。
///
/// ### 使用例
/// ```swift
/// // kfit / kmind の HealthKitManager 内から：
/// let hrv = await KFitHKQuery.todayHRVSamples(store: store)
/// let steps = await KFitHKQuery.todaySteps(store: store)
/// ```
public enum KFitHKQuery {

    // MARK: HRV

    /// 今日の HRV サンプルを降順で最大 100 件取得する。
    public static func todayHRVSamples(store: HKHealthStore) async -> [HRVSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return [] }
        let start     = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort      = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type, predicate: predicate, limit: 100, sortDescriptors: [sort]
            ) { _, s, _ in
                let result = (s as? [HKQuantitySample] ?? []).map {
                    HRVSample(date: $0.startDate,
                              value: $0.quantity.doubleValue(for: HKUnit(from: "ms")))
                }
                cont.resume(returning: result)
            }
            store.execute(q)
        }
    }

    /// 過去 `days` 日間（当日含む）の日別 HRV 平均を取得する。
    public static func weeklyHRVAverages(
        store: HKHealthStore,
        days: Int = 7
    ) async -> [DailyHRVAverage] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return [] }
        let anchor = Calendar.current.startOfDay(for: Date())
        let start  = Calendar.current.date(byAdding: .day, value: -(days - 1), to: anchor)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
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

    /// 最新の HRV 値を取得する（ms）。
    public static func latestHRV(store: HKHealthStore) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return 0 }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, s, _ in
                let ms = (s as? [HKQuantitySample])?.first?
                    .quantity.doubleValue(for: HKUnit.secondUnit(with: .milli)) ?? 0
                cont.resume(returning: ms)
            }
            store.execute(q)
        }
    }

    // MARK: 心拍数

    /// 最新の心拍数を取得する（bpm）。
    public static func latestHeartRate(store: HKHealthStore) async -> Double {
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

    /// 今日の平均心拍数を取得する（bpm）。
    public static func todayAverageHeartRate(store: HKHealthStore) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return 0 }
        let start     = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort      = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type, predicate: predicate, limit: 200, sortDescriptors: [sort]
            ) { _, s, _ in
                let samples = s as? [HKQuantitySample] ?? []
                guard !samples.isEmpty else { cont.resume(returning: 0); return }
                let avg = samples.map {
                    $0.quantity.doubleValue(for: HKUnit(from: "count/min"))
                }.reduce(0, +) / Double(samples.count)
                cont.resume(returning: avg)
            }
            store.execute(q)
        }
    }

    // MARK: アクティビティ

    /// 今日の歩数合計を取得する。
    public static func todaySteps(store: HKHealthStore) async -> Int {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let start     = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(
                quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum
            ) { _, stats, _ in
                cont.resume(returning: Int(stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0))
            }
            store.execute(q)
        }
    }

    /// 今日のアクティブカロリーを取得する（kcal）。
    public static func todayActiveCalories(store: HKHealthStore) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return 0 }
        let start     = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(
                quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum
            ) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)
            }
            store.execute(q)
        }
    }

    /// 今日のエクササイズ時間を取得する（分）。
    public static func todayExerciseMinutes(store: HKHealthStore) async -> Int {
        guard let type = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) else { return 0 }
        let start     = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(
                quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum
            ) { _, stats, _ in
                cont.resume(returning: Int(stats?.sumQuantity()?.doubleValue(for: .minute()) ?? 0))
            }
            store.execute(q)
        }
    }

    /// 今日のスタンド回数を取得する（1 時間単位）。
    public static func todayStandHours(store: HKHealthStore) async -> Int {
        guard let type = HKObjectType.categoryType(forIdentifier: .appleStandHour) else { return 0 }
        let start     = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type, predicate: predicate, limit: 24, sortDescriptors: nil
            ) { _, s, _ in
                let stood = (s as? [HKCategorySample] ?? [])
                    .filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue }.count
                cont.resume(returning: stood)
            }
            store.execute(q)
        }
    }

    /// 今日の日光浴時間を取得する（分）。iOS 17 / watchOS 10 以降のみ有効。
    public static func todayDaylightMinutes(store: HKHealthStore) async -> Double {
        guard #available(iOS 17.0, watchOS 10.0, *),
              let type = HKQuantityType.quantityType(forIdentifier: .timeInDaylight) else { return 0 }
        let start     = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(
                quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum
            ) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: .minute()) ?? 0)
            }
            store.execute(q)
        }
    }

    // MARK: 睡眠

    /// 昨夜の睡眠セグメントを取得する（過去 20 時間）。
    ///
    /// 返り値は `computeSleepScore(segments:targetHours:)` に直接渡せる。
    public static func lastNightSleepSegments(store: HKHealthStore) async -> [SleepSegment] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let start     = Calendar.current.date(byAdding: .hour, value: -20, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort      = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type, predicate: predicate, limit: 200, sortDescriptors: [sort]
            ) { _, s, _ in
                let result = (s as? [HKCategorySample] ?? []).compactMap { sample -> SleepSegment? in
                    let stage: SleepSegment.Stage
                    switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
                    case .inBed:             stage = .inBed
                    case .asleepCore:        stage = .core
                    case .asleepDeep:        stage = .deep
                    case .asleepREM:         stage = .rem
                    case .awake:             stage = .awake
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

    // MARK: 汎用ヘルパー

    /// 指定期間内の平均値を取得する（心拍数・呼吸数・SpO2 などに汎用）。
    public static func averageDuring(
        type: HKQuantityType,
        unit: HKUnit,
        start: Date,
        end: Date,
        store: HKHealthStore
    ) async -> Double {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort      = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type, predicate: predicate, limit: 500, sortDescriptors: [sort]
            ) { _, s, _ in
                let samples = s as? [HKQuantitySample] ?? []
                guard !samples.isEmpty else { cont.resume(returning: 0); return }
                let avg = samples.map { $0.quantity.doubleValue(for: unit) }
                    .reduce(0, +) / Double(samples.count)
                cont.resume(returning: avg)
            }
            store.execute(q)
        }
    }

    /// 指定期間内の最小値を取得する（SpO2 の最低値算出などに汎用）。
    public static func minimumDuring(
        type: HKQuantityType,
        unit: HKUnit,
        start: Date,
        end: Date,
        store: HKHealthStore
    ) async -> Double {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type, predicate: predicate, limit: 500, sortDescriptors: nil
            ) { _, s, _ in
                let values = (s as? [HKQuantitySample] ?? []).map { $0.quantity.doubleValue(for: unit) }
                cont.resume(returning: values.min() ?? 0)
            }
            store.execute(q)
        }
    }
}
