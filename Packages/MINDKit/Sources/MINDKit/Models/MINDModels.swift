import Foundation
import HealthKit

// MARK: - 睡眠データ
public struct SleepData: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let startDate: Date
    public let endDate: Date
    public let stage: SleepStage
    public var durationMinutes: Int {
        Int(endDate.timeIntervalSince(startDate) / 60)
    }

    public init(id: UUID = UUID(), startDate: Date, endDate: Date, stage: SleepStage) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.stage = stage
    }
}

public enum SleepStage: String, Sendable {
    case awake      = "awake"
    case light      = "light"
    case deep       = "deep"
    case rem        = "rem"
    case inBed      = "inBed"

    public var label: String {
        switch self {
        case .awake:  return "覚醒"
        case .light:  return "浅い眠り"
        case .deep:   return "深い眠り"
        case .rem:    return "REM"
        case .inBed:  return "就寝中"
        }
    }

    public var color: String {
        switch self {
        case .awake:  return "FF6B6B"
        case .light:  return "74B9FF"
        case .deep:   return "0984E3"
        case .rem:    return "A29BFE"
        case .inBed:  return "DFE6E9"
        }
    }
}

// MARK: - 睡眠スコア
public struct SleepScore: Sendable {
    public let total: Int          // 0-100
    public let durationScore: Int  // 睡眠時間
    public let qualityScore: Int   // 深睡眠・REM の割合
    public let consistencyScore: Int // 就寝・起床時刻の一貫性

    public var label: String {
        switch total {
        case 85...100: return "優秀"
        case 70...84:  return "良好"
        case 50...69:  return "普通"
        default:       return "要改善"
        }
    }

    public init(total: Int, durationScore: Int, qualityScore: Int, consistencyScore: Int) {
        self.total = total
        self.durationScore = durationScore
        self.qualityScore = qualityScore
        self.consistencyScore = consistencyScore
    }
}

// MARK: - HRV（心拍変動）
public struct HRVData: Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let value: Double // ms (SDNN)

    public var stressLevel: StressLevel {
        switch value {
        case 60...: return .low
        case 40..<60: return .moderate
        default: return .high
        }
    }

    public init(id: UUID = UUID(), date: Date, value: Double) {
        self.id = id
        self.date = date
        self.value = value
    }
}

public enum StressLevel: String, Sendable {
    case low      = "low"
    case moderate = "moderate"
    case high     = "high"

    public var label: String {
        switch self {
        case .low:      return "低ストレス"
        case .moderate: return "中程度"
        case .high:     return "高ストレス"
        }
    }
}

// MARK: - マインドフルネスセッション
public struct MindfulnessSession: Identifiable, Sendable {
    public let id: UUID
    public let startDate: Date
    public let endDate: Date
    public let durationMinutes: Int

    public init(id: UUID = UUID(), startDate: Date, endDate: Date) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.durationMinutes = Int(endDate.timeIntervalSince(startDate) / 60)
    }
}

// MARK: - Watch 連携用データ転送モデル
public struct WatchMindData: Codable, Sendable {
    public var currentHRV: Double?
    public var sleepScore: Int?
    public var todayMindfulnessMinutes: Int
    public var stressLevel: String
    public var lastUpdated: Date

    public init(
        currentHRV: Double? = nil,
        sleepScore: Int? = nil,
        todayMindfulnessMinutes: Int = 0,
        stressLevel: String = "moderate",
        lastUpdated: Date = Date()
    ) {
        self.currentHRV = currentHRV
        self.sleepScore = sleepScore
        self.todayMindfulnessMinutes = todayMindfulnessMinutes
        self.stressLevel = stressLevel
        self.lastUpdated = lastUpdated
    }
}
