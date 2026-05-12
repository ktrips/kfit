import Foundation

/// 摂取記録のデフォルト設定
struct IntakeSettings: Codable {
    // 食事のデフォルトカロリー
    var breakfastCalories: Int = 400
    var lunchCalories: Int = 600
    var dinnerCalories: Int = 800

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

    /// 特定のアルコールタイプの設定を取得
    func settingFor(alcoholType: AlcoholType) -> CustomAlcoholSetting? {
        return alcoholSettings.first { $0.type == alcoholType }
    }
}

/// カスタムアルコール設定
struct CustomAlcoholSetting: Codable, Identifiable {
    var id: String { type.rawValue }
    let type: AlcoholType
    var amountMl: Int
    var alcoholG: Double
    var displayName: String
}
