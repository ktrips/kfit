import Foundation
import UIKit

/// フォトログエントリ
struct PhotoLogEntry: Codable, Identifiable {
    var id: String = UUID().uuidString
    var timestamp: Date = Date()
    var imageData: Data?  // 写真データ
    var comment: String = ""  // ユーザーコメント
    var mealType: MealType?  // 食事タイプ（朝食、昼食、夕食）
    var analyzedNutrition: AnalyzedNutrition?  // LLM分析結果

    var image: UIImage? {
        guard let data = imageData else { return nil }
        return UIImage(data: data)
    }
}

/// LLMが分析した栄養情報
struct AnalyzedNutrition: Codable {
    var description: String = ""  // 食品の説明
    var calories: Int = 0
    var protein: Double = 0.0
    var fat: Double = 0.0
    var carbs: Double = 0.0
    var sugar: Double = 0.0
    var fiber: Double = 0.0
    var sodium: Double = 0.0
    var water: Int = 0  // 水分量（ml）
    var caffeine: Int = 0  // カフェイン量（mg）
    var alcohol: Double = 0.0  // アルコール量（g）
    var confidence: Double = 1.0  // 推定の確度（0.0-1.0）
}
