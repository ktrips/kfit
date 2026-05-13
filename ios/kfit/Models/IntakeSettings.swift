import Foundation
import UIKit

/// 摂取記録のデフォルト設定
struct IntakeSettings: Codable {
    // 食事のデフォルトカロリーと栄養素
    var breakfastCalories: Int = 400
    var breakfastProtein: Double = 17.0      // たんぱく質（g）
    var breakfastFat: Double = 15.0          // 脂質（g）
    var breakfastCarbs: Double = 65.0        // 炭水化物（g）
    var breakfastSugar: Double = 60.0        // 糖質（g）
    var breakfastFiber: Double = 5.0         // 食物繊維（g）
    var breakfastSodium: Double = 2.0        // 塩分（g）

    var lunchCalories: Int = 600
    var lunchProtein: Double = 31.0
    var lunchFat: Double = 18.0
    var lunchCarbs: Double = 85.0
    var lunchSugar: Double = 80.0
    var lunchFiber: Double = 5.0
    var lunchSodium: Double = 5.0

    var dinnerCalories: Int = 800
    var dinnerProtein: Double = 25.0
    var dinnerFat: Double = 30.0
    var dinnerCarbs: Double = 125.0
    var dinnerSugar: Double = 115.0
    var dinnerFiber: Double = 10.0
    var dinnerSodium: Double = 5.0

    // 水1杯の量（ml）
    var waterPerCup: Int = 200

    // コーヒー1杯の設定
    var coffeePerCup: Int = 150      // ml
    var caffeinePerCup: Int = 90     // mg

    // アルコールのカスタム設定
    var alcoholSettings: [CustomAlcoholSetting] = [
        CustomAlcoholSetting(type: .beer, amountMl: 350, alcoholG: 14.0, displayName: "ビール（缶350ml）"),
        CustomAlcoholSetting(type: .wine, amountMl: 120, alcoholG: 11.5, displayName: "ワイン（グラス）"),
        CustomAlcoholSetting(type: .chuhai, amountMl: 350, alcoholG: 19.6, displayName: "酎ハイ（缶350ml）"),
        CustomAlcoholSetting(type: .nonAlcoholic, amountMl: 0, alcoholG: 0.0, displayName: "ノンアルコール")
    ]

    // 1日の目標値
    var dailyCalorieGoal: Int = 1800     // kcal
    var dailyWaterGoal: Int = 1000       // ml
    var dailyCaffeineLimit: Int = 400    // mg
    var dailyAlcoholLimit: Double = 20.0 // g

    static let defaultSettings = IntakeSettings()

    /// 特定の食事タイプのカロリーを取得
    func caloriesFor(mealType: MealType) -> Int {
        switch mealType {
        case .breakfast: return breakfastCalories
        case .lunch: return lunchCalories
        case .dinner: return dinnerCalories
        }
    }

    /// 特定の食事タイプの栄養素を取得
    func nutritionFor(mealType: MealType) -> MealNutrition {
        switch mealType {
        case .breakfast:
            return MealNutrition(
                calories: breakfastCalories,
                protein: breakfastProtein,
                fat: breakfastFat,
                carbs: breakfastCarbs,
                sugar: breakfastSugar,
                fiber: breakfastFiber,
                sodium: breakfastSodium
            )
        case .lunch:
            return MealNutrition(
                calories: lunchCalories,
                protein: lunchProtein,
                fat: lunchFat,
                carbs: lunchCarbs,
                sugar: lunchSugar,
                fiber: lunchFiber,
                sodium: lunchSodium
            )
        case .dinner:
            return MealNutrition(
                calories: dinnerCalories,
                protein: dinnerProtein,
                fat: dinnerFat,
                carbs: dinnerCarbs,
                sugar: dinnerSugar,
                fiber: dinnerFiber,
                sodium: dinnerSodium
            )
        }
    }

    /// 特定のアルコールタイプの設定を取得
    func settingFor(alcoholType: AlcoholType) -> CustomAlcoholSetting? {
        return alcoholSettings.first { $0.type == alcoholType }
    }
}

/// 食事の栄養素情報
struct MealNutrition {
    let calories: Int
    let protein: Double      // たんぱく質（g）
    let fat: Double          // 脂質（g）
    let carbs: Double        // 炭水化物（g）
    let sugar: Double        // 糖質（g）
    let fiber: Double        // 食物繊維（g）
    let sodium: Double       // 塩分（g）
}

/// カスタムアルコール設定
struct CustomAlcoholSetting: Codable, Identifiable {
    var id: String { type.rawValue }
    let type: AlcoholType
    var amountMl: Int
    var alcoholG: Double
    var displayName: String
}

// MARK: - LLM Settings

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

// MARK: - Photo Log

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
