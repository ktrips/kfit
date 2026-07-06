import SwiftUI

// MARK: - HRV 閾値定数（kfit 側）
// LanguageUtils.swift にも同一 HRVThreshold が定義されており、両方で統一値を使用する。
// NOTE: kmind 側は kmind/Extensions/HealthUtils.swift に同一定義あり。
//       将来的には Swift Package (KFitCore) に統合して単一実装にすること。

// MARK: - HRV ストレス指数モデル

struct MindStressInfo {
    let score: Int
    let label: String
    let englishLabel: String
    let color: Color
}

// MARK: - HRV → ストレス指数変換（0–100）

/// HRV 値からストレス指数を計算する共有関数。
/// score が -1 の場合はデータなし（HRV ≤ 0）。
func stressInfoFromHRV(_ hrv: Double) -> MindStressInfo {
    guard hrv > 0 else {
        return MindStressInfo(score: -1, label: "不明", englishLabel: "Unknown", color: Color.duoSubtitle)
    }
    let score: Int = {
        if hrv >= 100                       { return 5 }
        if hrv >= 80                        { return Int(5  + (100 - hrv) / 20 * 10) }
        if hrv >= HRVThreshold.excellent    { return Int(15 + (80  - hrv) / 20 * 20) }
        if hrv >= HRVThreshold.moderate     { return Int(35 + (HRVThreshold.excellent - hrv) / 20 * 25) }
        if hrv >= HRVThreshold.low          { return Int(60 + (HRVThreshold.moderate  - hrv) / 20 * 20) }
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

func formatMindfulMinutes(_ minutes: Double) -> String {
    if minutes < 1 { return "\(Int(minutes * 60))秒" }
    if abs(minutes.rounded() - minutes) < 0.05 { return "\(Int(minutes.rounded()))分" }
    return String(format: "%.1f分", minutes)
}
