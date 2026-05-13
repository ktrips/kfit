import Foundation

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
