// KFitCore — kfit / kedu / kmind 全アプリで共有する基盤パッケージ
//
// ┌────────────────────────────────────────────────────────────┐
// │  Xcode への追加手順                                        │
// │  File → Add Package Dependencies... → Add Local...        │
// │  /Users/kenichi.yoshida/Git/kfit/Packages/KFitCore を選択  │
// │  ターゲット（kfit / kmind / kfitWatch）に KFitCore を追加  │
// └────────────────────────────────────────────────────────────┘
//
// ── 提供するモジュール ────────────────────────────────────────
// KFitColors.swift     : Color.duo*, UIScale, UIImage.resized
// KFitHRV.swift        : HRVThreshold, MindStressInfo, stressInfoFromHRV
// KFitMoomin.swift     : MoominQuote, moominQuoteForStress(seed:)
// KFitLanguage.swift   : languageBCP47Code, languageFlag, languageLabel,
//                        languageBadgeColor, FirestoreCollections
// KFitUI.swift         : RoundedCorner, cornerRadius(corners:)
// KFitHealthKit.swift  : HRVSample, DailyHRVAverage, SleepSegment,
//                        SleepScoreAnalysis, computeSleepScore,
//                        KFitHKQuery（共通 HealthKit フェッチ）
// CoachingContent.swift: CoachingContentDB（100メソッド JSON ローダー）
// ─────────────────────────────────────────────────────────────
//
// ── 移行ガイド ────────────────────────────────────────────────
// KFitCore を各 Xcode ターゲットに追加した後、以下を削除できる:
//
// [kfit]
//   ios/kfit/Extensions/Color+Duo.swift     → KFitColors.swift
//   ios/kfit/Extensions/HealthUtils.swift   → KFitHRV.swift + KFitMoomin.swift
//   ios/kfit/Extensions/LanguageUtils.swift → KFitLanguage.swift + KFitHRV.swift
//   HealthKitManager の fetch 関数群        → KFitHKQuery に委譲
//   HealthKitManager のモデル定義           → KFitHealthKit.swift の型を使用
//
// [kedu]
//   kedu/kedu/KeduStubViews.swift の RoundedCorner → KFitUI.swift
//   kedu 内の FirestoreCollections コピー          → KFitLanguage.swift
//
// [kmind]
//   kmind/kmind/Extensions/HealthUtils.swift → KFitHRV.swift + KFitMoomin.swift
//   HealthKitManager の fetch 関数群          → KFitHKQuery に委譲
//
// [kfitWatch]
//   WatchHealthKitManager の WatchHRVThreshold → KFitCore.HRVThreshold
//   WatchMindfulnessImpact.stressScore         → stressInfoFromHRV(hrv).score
// ─────────────────────────────────────────────────────────────

public enum KFitCore {
    public static let version = "1.0.0"

    /// KFitCore が提供するすべてのカテゴリ
    public enum Module: String, CaseIterable {
        case colors      = "KFitColors"
        case hrv         = "KFitHRV"
        case moomin      = "KFitMoomin"
        case language    = "KFitLanguage"
        case ui          = "KFitUI"
        case coaching    = "CoachingContent"
    }
}
