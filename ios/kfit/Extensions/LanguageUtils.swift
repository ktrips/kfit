import Foundation
import SwiftUI

// MARK: - Firestore コレクションパス定数（kfit/kedu 共通スキーマ）
// ⚠️ kedu は別プロジェクトのため同名 enum を kedu 側にも保持している。
//    変更時は両方を同時に更新すること。将来的には Swift Package に統合する。

enum FirestoreCollections {
    static let users          = "users"
    static let publicProfiles = "publicProfiles"
    static let posts          = "posts"
    static let exercises      = "exercises"
    static let leaderboards   = "leaderboards"
}

// MARK: - BCP-47 言語コード変換（kfit/kedu 共通。DuolingoTextExtractor/Watch から参照）
// NOTE: keduWatch はターゲットが別プロジェクトのため同じロジックをコピーして管理している。
//       将来的に Swift Package (KFitCore) に移動して共有することを推奨。

func languageBCP47Code(_ code: String) -> String {
    switch code {
    case "zh", "zh-Hans", "cmn-Hans": return "zh-CN"
    case "zh-Hant":                   return "zh-TW"
    case "ko":                        return "ko-KR"
    case "fr":                        return "fr-FR"
    case "es":                        return "es-ES"
    case "de":                        return "de-DE"
    case "pt":                        return "pt-BR"
    case "it":                        return "it-IT"
    case "ru":                        return "ru-RU"
    case "ar":                        return "ar-SA"
    case "ja":                        return "ja-JP"
    default:                          return "en-US"
    }
}

// MARK: - HRV 閾値定数（kfit/kmind 共通。HealthKitManager から参照）
// 変更時はここ1箇所だけ修正すれば kfit / kfitWatch / kmind に反映される。
// NOTE: kmind は別プロジェクトのため同じ定数をコピーして管理している。
//       将来的に Swift Package に移動することを推奨。

enum HRVThreshold {
    static let excellent: Double = 60   // ≥60 → 良好
    static let moderate: Double  = 40   // ≥40 → 中程度
    static let low: Double       = 20   // ≥20 → 要注意
}

// MARK: - 言語コード → 国旗絵文字

func languageFlag(_ code: String) -> String {
    switch code {
    case "zh", "zh-Hans", "cmn-Hans": return "🇨🇳"
    case "zh-Hant":                   return "🇹🇼"
    case "ko":                        return "🇰🇷"
    case "fr":                        return "🇫🇷"
    case "es":                        return "🇪🇸"
    case "de":                        return "🇩🇪"
    case "pt":                        return "🇧🇷"
    case "it":                        return "🇮🇹"
    case "ru":                        return "🇷🇺"
    case "ar":                        return "🇸🇦"
    default:                          return "🇺🇸"
    }
}

// MARK: - 言語コード → 言語名（日本語）

func languageLabel(_ code: String) -> String {
    switch code {
    case "zh", "zh-Hans", "cmn-Hans": return "中国語"
    case "zh-Hant":                   return "中国語"
    case "ko":                        return "韓国語"
    case "fr":                        return "フランス語"
    case "es":                        return "スペイン語"
    case "de":                        return "ドイツ語"
    case "pt":                        return "ポルトガル語"
    case "it":                        return "イタリア語"
    case "ru":                        return "ロシア語"
    case "ar":                        return "アラビア語"
    default:                          return "英語"
    }
}

// MARK: - 言語コード → バッジ背景色（Edulingo 準拠の鮮やか系）

func languageBadgeColor(_ code: String) -> Color {
    switch String(code.prefix(2)) {
    case "zh": return Color(hex: "#E53935")   // 中国語: 赤
    case "ko": return Color(hex: "#1565C0")   // 韓国語: 濃い青
    case "fr": return Color(hex: "#1976D2")   // フランス語: 青
    case "es": return Color(hex: "#FF4081")   // スペイン語: マゼンタピンク
    case "de": return Color(hex: "#424242")   // ドイツ語: ダークグレー
    case "pt": return Color(hex: "#2E7D32")   // ポルトガル語: 緑
    case "it": return Color(hex: "#C62828")   // イタリア語: 深赤
    case "ru": return Color(hex: "#283593")   // ロシア語: 紺
    case "ar": return Color(hex: "#00695C")   // アラビア語: ティール
    case "ja": return Color(hex: "#6A1B9A")   // 日本語: 紫
    default:   return Color(hex: "#1565C0")   // 英語・その他: 青
    }
}
