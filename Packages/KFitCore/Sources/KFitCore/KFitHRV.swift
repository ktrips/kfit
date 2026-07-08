import SwiftUI

// MARK: - HRV 閾値定数（kfit / kmind 共通・単一ソース）
// ⚠️ このファイルが単一の真実のソース。
//    kfit/Extensions/LanguageUtils.swift の HRVThreshold
//    および kmind/Extensions/HealthUtils.swift の HRVThreshold は
//    KFitCore 追加後に削除すること。

/// HRV（心拍変動）の閾値定数
public enum HRVThreshold {
    public static let excellent: Double = 60   // ≥60 → 良好
    public static let moderate: Double  = 40   // ≥40 → 中程度
    public static let low: Double       = 20   // ≥20 → 要注意
}

// MARK: - HRV ストレス指数モデル

public struct MindStressInfo {
    public let score: Int
    public let label: String
    public let englishLabel: String
    public let color: Color

    public init(score: Int, label: String, englishLabel: String, color: Color) {
        self.score = score
        self.label = label
        self.englishLabel = englishLabel
        self.color = color
    }
}

// MARK: - HRV → ストレス指数変換（0–100）

/// HRV 値からストレス指数を計算する共有関数。
/// - Parameters:
///   - hrv: HRV 値（ms単位）。0 以下はデータなしとして score = -1 を返す。
/// - Returns: `MindStressInfo`
public func stressInfoFromHRV(_ hrv: Double) -> MindStressInfo {
    guard hrv > 0 else {
        return MindStressInfo(score: -1, label: "不明", englishLabel: "Unknown", color: Color.duoSubtitle)
    }
    let score: Int = {
        if hrv >= 100                        { return 5 }
        if hrv >= 80                         { return Int(5  + (100 - hrv) / 20 * 10) }
        if hrv >= HRVThreshold.excellent     { return Int(15 + (80  - hrv) / 20 * 20) }
        if hrv >= HRVThreshold.moderate      { return Int(35 + (HRVThreshold.excellent - hrv) / 20 * 25) }
        if hrv >= HRVThreshold.low           { return Int(60 + (HRVThreshold.moderate  - hrv) / 20 * 20) }
        return Int(min(95, 80 + (HRVThreshold.low - hrv) / 20 * 15))
    }()
    switch score {
    case ..<30: return MindStressInfo(score: score, label: "低い",   englishLabel: "Low",      color: Color.duoGreen)
    case ..<55: return MindStressInfo(score: score, label: "普通",   englishLabel: "Normal",   color: Color(red: 0.4, green: 0.75, blue: 0.1))
    case ..<75: return MindStressInfo(score: score, label: "やや高", englishLabel: "Elevated", color: Color.duoOrange)
    default:    return MindStressInfo(score: score, label: "高い",   englishLabel: "High",     color: Color(hex: "#FF4B4B"))
    }
}

// MARK: - マインドフルネス時間フォーマット

/// マインドフルネス時間（分）を人間が読みやすい文字列に変換
public func formatMindfulMinutes(_ minutes: Double) -> String {
    if minutes < 1 { return "\(Int(minutes * 60))秒" }
    if abs(minutes.rounded() - minutes) < 0.05 { return "\(Int(minutes.rounded()))分" }
    return String(format: "%.1f分", minutes)
}
