import SwiftUI

// MARK: - Firestore コレクションパス定数（kfit / kedu 共通・単一ソース）
// ⚠️ このファイルが単一の真実のソース。
//    kfit/Extensions/LanguageUtils.swift の FirestoreCollections
//    kedu 側の同等 enum は KFitCore 追加後に削除すること。

public enum FirestoreCollections {
    public static let users          = "users"
    public static let publicProfiles = "publicProfiles"
    public static let posts          = "posts"
    public static let exercises      = "exercises"
    public static let leaderboards   = "leaderboards"
}

// MARK: - BCP-47 言語コード変換

/// 言語コード文字列を BCP-47 形式に変換する
public func languageBCP47Code(_ code: String) -> String {
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

// MARK: - 言語コード → 国旗絵文字

public func languageFlag(_ code: String) -> String {
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

public func languageLabel(_ code: String) -> String {
    switch code {
    case "zh", "zh-Hans", "cmn-Hans": return "中国語"
    case "zh-Hant":                   return "中国語（繁体）"
    case "ko":                        return "韓国語"
    case "fr":                        return "フランス語"
    case "es":                        return "スペイン語"
    case "de":                        return "ドイツ語"
    case "pt":                        return "ポルトガル語"
    case "it":                        return "イタリア語"
    case "ru":                        return "ロシア語"
    case "ar":                        return "アラビア語"
    case "ja":                        return "日本語"
    default:                          return "英語"
    }
}

// MARK: - 言語コード → バッジ背景色

public func languageBadgeColor(_ code: String) -> Color {
    switch String(code.prefix(2)) {
    case "zh": return Color(hex: "#E53935")
    case "ko": return Color(hex: "#1565C0")
    case "fr": return Color(hex: "#1976D2")
    case "es": return Color(hex: "#FF4081")
    case "de": return Color(hex: "#424242")
    case "pt": return Color(hex: "#2E7D32")
    case "it": return Color(hex: "#C62828")
    case "ru": return Color(hex: "#283593")
    case "ar": return Color(hex: "#00695C")
    case "ja": return Color(hex: "#6A1B9A")
    default:   return Color(hex: "#1565C0")
    }
}
