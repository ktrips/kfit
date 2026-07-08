// KFitCore — kfit / kedu / kmind 全アプリで共有する基盤パッケージ
//
// ┌────────────────────────────────────────────────────────────┐
// │  Xcode への追加手順                                        │
// │  File → Add Package Dependencies... → Add Local...        │
// │  /Users/kenichi.yoshida/Git/kfit/Packages/KFitCore を選択  │
// │  Target に KFitCore を追加する                             │
// └────────────────────────────────────────────────────────────┘
//
// ── 提供するモジュール ────────────────────────────────────────
// KFitColors.swift    : Color.duo*, UIScale, UIImage.resized
// KFitHRV.swift       : HRVThreshold, MindStressInfo, stressInfoFromHRV
// KFitMoomin.swift    : MoominQuote, moominQuoteForStress
// KFitLanguage.swift  : languageBCP47Code, languageFlag, languageLabel,
//                       languageBadgeColor, FirestoreCollections
// KFitUI.swift        : RoundedCorner, cornerRadius(corners:)
// CoachingContent.swift: CoachingContentDB（100メソッド JSON ローダー）
// ─────────────────────────────────────────────────────────────
//
// ── 移行ガイド ────────────────────────────────────────────────
// KFitCore を Xcode プロジェクトに追加した後、以下を削除できる:
//
// [kfit]
//   ios/kfit/Extensions/Color+Duo.swift  → KFitColors.swift に統合済み
//   ios/kfit/Extensions/HealthUtils.swift → KFitHRV.swift + KFitMoomin.swift
//   ios/kfit/Extensions/LanguageUtils.swift → KFitLanguage.swift + KFitHRV.swift
//
// [kedu]
//   kedu/kedu/KeduStubViews.swift の RoundedCorner → KFitUI.swift
//   kedu 内の FirestoreCollections コピー → KFitLanguage.swift
//
// [kmind]
//   kmind/kmind/Extensions/HealthUtils.swift → KFitHRV.swift + KFitMoomin.swift
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
