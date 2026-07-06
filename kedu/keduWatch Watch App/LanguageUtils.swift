import Foundation

// MARK: - 言語コード → 国旗絵文字 / 言語名
// kfit/ios/kfit/Extensions/LanguageUtils.swift と同一定義。
// 将来的には Swift Package に移して全ターゲットから参照する。

func languageFlag(_ code: String) -> String {
    switch code {
    case "zh", "zh-Hans", "cmn-Hans": return "🇨🇳"
    case "zh-Hant":                   return "🇹🇼"
    case "ko":                        return "🇰🇷"
    case "fr":                        return "🇫🇷"
    case "es":                        return "🇪🇸"
    case "de":                        return "🇩🇪"
    case "pt":                        return "🇵🇹"
    case "it":                        return "🇮🇹"
    case "ru":                        return "🇷🇺"
    case "ar":                        return "🇸🇦"
    default:                          return "🇺🇸"
    }
}

func languageLabel(_ code: String) -> String {
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
    default:                          return "英語"
    }
}
