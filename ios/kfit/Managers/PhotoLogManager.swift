import Foundation
import UIKit

@MainActor
class PhotoLogManager: ObservableObject {
    static let shared = PhotoLogManager()

    @Published var logs: [PhotoLogEntry] = []
    @Published var isAnalyzing = false

    private init() {}

    /// 写真を分析して栄養情報を取得
    func analyzePhoto(_ image: UIImage, comment: String, settings: LLMSettings) async throws -> AnalyzedNutrition {
        isAnalyzing = true
        defer { isAnalyzing = false }

        guard !settings.apiKey.isEmpty else {
            throw PhotoLogError.noAPIKey
        }

        // 画像をBase64エンコード
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw PhotoLogError.invalidImage
        }
        let base64Image = imageData.base64EncodedString()

        // プロンプト作成
        let prompt = createAnalysisPrompt(comment: comment)

        // プロバイダーに応じてAPIを呼び出し
        switch settings.provider {
        case .openAI:
            return try await analyzeWithOpenAI(base64Image: base64Image, prompt: prompt, settings: settings)
        case .anthropic:
            return try await analyzeWithAnthropic(base64Image: base64Image, prompt: prompt, settings: settings)
        case .google:
            return try await analyzeWithGoogle(base64Image: base64Image, prompt: prompt, settings: settings)
        }
    }

    /// フォトログを保存
    func savePhotoLog(_ entry: PhotoLogEntry) {
        logs.insert(entry, at: 0)
        // TODO: Firestoreに保存
    }

    // MARK: - Private Methods

    private func createAnalysisPrompt(comment: String) -> String {
        var prompt = """
        この画像に写っている食べ物や飲み物を分析して、以下の情報をJSON形式で返してください。

        {
          "description": "食品の簡潔な説明",
          "calories": カロリー（kcal、整数）,
          "protein": たんぱく質（g、小数）,
          "fat": 脂質（g、小数）,
          "carbs": 炭水化物（g、小数）,
          "sugar": 糖質（g、小数）,
          "fiber": 食物繊維（g、小数）,
          "sodium": 塩分（g、小数）,
          "water": 水分量（ml、整数）,
          "caffeine": カフェイン（mg、整数）,
          "alcohol": アルコール（g、小数）,
          "confidence": 推定の確度（0.0-1.0）
        }
        """

        if !comment.isEmpty {
            prompt += "\n\nユーザーコメント: \(comment)"
            prompt += "\nコメントから食事タイプ（朝食、昼食、夕食）や飲み物の種類（コーヒー、ワインなど）を推測してください。"
        }

        return prompt
    }

    // MARK: - OpenAI API

    private func analyzeWithOpenAI(base64Image: String, prompt: String, settings: LLMSettings) async throws -> AnalyzedNutrition {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": settings.effectiveModel,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]]
                    ]
                ]
            ],
            "max_tokens": 500,
            "response_format": ["type": "json_object"]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PhotoLogError.apiError("OpenAI API error")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw PhotoLogError.invalidResponse
        }

        return try parseNutritionJSON(content)
    }

    // MARK: - Anthropic API

    private func analyzeWithAnthropic(base64Image: String, prompt: String, settings: LLMSettings) async throws -> AnalyzedNutrition {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(settings.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let payload: [String: Any] = [
            "model": settings.effectiveModel,
            "max_tokens": 500,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": base64Image]],
                        ["type": "text", "text": prompt]
                    ]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PhotoLogError.apiError("Anthropic API error")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw PhotoLogError.invalidResponse
        }

        return try parseNutritionJSON(text)
    }

    // MARK: - Google Gemini API

    private func analyzeWithGoogle(base64Image: String, prompt: String, settings: LLMSettings) async throws -> AnalyzedNutrition {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(settings.effectiveModel):generateContent?key=\(settings.apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt],
                        ["inline_data": ["mime_type": "image/jpeg", "data": base64Image]]
                    ]
                ]
            ],
            "generationConfig": [
                "response_mime_type": "application/json"
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PhotoLogError.apiError("Google API error")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let candidates = json?["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw PhotoLogError.invalidResponse
        }

        return try parseNutritionJSON(text)
    }

    // MARK: - JSON Parsing

    private func parseNutritionJSON(_ jsonString: String) throws -> AnalyzedNutrition {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PhotoLogError.invalidResponse
        }

        var nutrition = AnalyzedNutrition()
        nutrition.description = json["description"] as? String ?? ""
        nutrition.calories = json["calories"] as? Int ?? 0
        nutrition.protein = json["protein"] as? Double ?? 0.0
        nutrition.fat = json["fat"] as? Double ?? 0.0
        nutrition.carbs = json["carbs"] as? Double ?? 0.0
        nutrition.sugar = json["sugar"] as? Double ?? 0.0
        nutrition.fiber = json["fiber"] as? Double ?? 0.0
        nutrition.sodium = json["sodium"] as? Double ?? 0.0
        nutrition.water = json["water"] as? Int ?? 0
        nutrition.caffeine = json["caffeine"] as? Int ?? 0
        nutrition.alcohol = json["alcohol"] as? Double ?? 0.0
        nutrition.confidence = json["confidence"] as? Double ?? 0.8

        return nutrition
    }
}

enum PhotoLogError: LocalizedError {
    case noAPIKey
    case invalidImage
    case apiError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "APIキーが設定されていません"
        case .invalidImage:
            return "画像の処理に失敗しました"
        case .apiError(let message):
            return "API呼び出しエラー: \(message)"
        case .invalidResponse:
            return "無効なレスポンス"
        }
    }
}
