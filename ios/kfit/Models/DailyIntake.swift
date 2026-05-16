import Foundation

// MARK: - 食事記録

enum MealType: String, Codable, CaseIterable {
    case breakfast = "breakfast"
    case lunch = "lunch"
    case dinner = "dinner"
    case snack = "snack"

    var displayName: String {
        switch self {
        case .breakfast: return "朝食"
        case .lunch: return "昼食"
        case .dinner: return "夕食"
        case .snack: return "スナック"
        }
    }

    var emoji: String {
        switch self {
        case .breakfast: return "🌅"
        case .lunch: return "🍱"
        case .dinner: return "🍽️"
        case .snack: return "🍫"
        }
    }

    var defaultCalories: Int {
        switch self {
        case .breakfast: return 400
        case .lunch: return 600
        case .dinner: return 800
        case .snack: return 100
        }
    }
}

struct MealLog: Codable, Identifiable {
    var id = UUID()
    let mealType: MealType
    let calories: Int
    let timestamp: Date
}

// MARK: - 水分記録

struct WaterLog: Codable, Identifiable {
    var id = UUID()
    let amountMl: Int  // 1杯 = 200ml
    let timestamp: Date
}

// MARK: - コーヒー記録

struct CoffeeLog: Codable, Identifiable {
    var id = UUID()
    let amountMl: Int      // 1杯 = 150ml
    let caffeineMg: Int    // 1杯 = 90mg
    let timestamp: Date
}

// MARK: - アルコール記録

enum AlcoholType: String, Codable, CaseIterable {
    case beer = "beer"
    case wine = "wine"
    case chuhai = "chuhai"
    case nonAlcoholic = "non_alcoholic"

    var displayName: String {
        switch self {
        case .beer: return "ビール"
        case .wine: return "ワイン"
        case .chuhai: return "酎ハイ"
        case .nonAlcoholic: return "ノンアルコール"
        }
    }

    var emoji: String {
        switch self {
        case .beer: return "🍺"
        case .wine: return "🍷"
        case .chuhai: return "🥃"
        case .nonAlcoholic: return "🚫"
        }
    }

    var amountMl: Int {
        switch self {
        case .beer: return 350      // ビール缶1本
        case .wine: return 120      // ワイングラス1杯
        case .chuhai: return 350    // 酎ハイ缶1本
        case .nonAlcoholic: return 0 // アルコールなし
        }
    }

    /// 純アルコール量（g単位）
    /// 計算式: 容量(ml) × アルコール度数(%) × 0.8(アルコール比重)
    var alcoholG: Double {
        switch self {
        case .beer:
            // ビール350ml × 5% × 0.8 = 14g
            return 14.0
        case .wine:
            // ワイン120ml × 12% × 0.8 = 11.52g
            return 11.5
        case .chuhai:
            // 酎ハイ350ml × 7% × 0.8 = 19.6g
            return 19.6
        case .nonAlcoholic:
            // ノンアルコール = 0g
            return 0.0
        }
    }
}

struct AlcoholLog: Codable, Identifiable {
    var id = UUID()
    let alcoholType: AlcoholType
    let amountMl: Int
    let alcoholG: Double
    let timestamp: Date
}

// MARK: - 今日の摂取記録サマリー

struct TodayIntakeSummary {
    var totalCalories: Int = 0
    var totalWaterMl: Int = 0
    var totalCaffeineMg: Int = 0
    var totalAlcoholG: Double = 0.0

    var meals: [MealLog] = []
    var waterLogs: [WaterLog] = []
    var coffeeLogs: [CoffeeLog] = []
    var alcoholLogs: [AlcoholLog] = []

    /// ログコンプリート判定: 朝昼夕 + 水 + コーヒー + アルコール（またはノンアル）
    var isLogComplete: Bool {
        let hasBreakfast = meals.contains { $0.mealType == .breakfast }
        let hasLunch = meals.contains { $0.mealType == .lunch }
        let hasDinner = meals.contains { $0.mealType == .dinner }
        let hasWater = !waterLogs.isEmpty
        let hasCoffee = !coffeeLogs.isEmpty
        let hasAlcohol = !alcoholLogs.isEmpty

        return hasBreakfast && hasLunch && hasDinner && hasWater && hasCoffee && hasAlcohol
    }
}
