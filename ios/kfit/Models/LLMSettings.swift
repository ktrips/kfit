import Foundation

/// LLM設定
struct LLMSettings: Codable {
    var provider: LLMProvider = .openAI
    var apiKey: String = ""
    var model: String = ""

    static let defaultSettings = LLMSettings()

    /// プロバイダーごとのデフォルトモデル（リーズナブルなプラン）
    var defaultModel: String {
        switch provider {
        case .openAI:
            return "gpt-4o-mini"  // 最もリーズナブル
        case .anthropic:
            return "claude-3-haiku-20240307"  // 最もリーズナブル
        case .google:
            return "gemini-1.5-flash"  // 最もリーズナブル
        }
    }

    /// 使用するモデル（設定されていない場合はデフォルト）
    var effectiveModel: String {
        return model.isEmpty ? defaultModel : model
    }
}

/// LLMプロバイダー
enum LLMProvider: String, Codable, CaseIterable {
    case openAI = "OpenAI"
    case anthropic = "Anthropic"
    case google = "Google"

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI (GPT)"
        case .anthropic: return "Anthropic (Claude)"
        case .google: return "Google (Gemini)"
        }
    }

    var endpoint: String {
        switch self {
        case .openAI:
            return "https://api.openai.com/v1/chat/completions"
        case .anthropic:
            return "https://api.anthropic.com/v1/messages"
        case .google:
            return "https://generativelanguage.googleapis.com/v1beta/models"
        }
    }
}
