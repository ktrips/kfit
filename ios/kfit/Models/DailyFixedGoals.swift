import Foundation

// MARK: - 毎日の設定モデル（SettingsView.swift から抽出）
// kfit・kmind 両方から参照されます

struct DailyCustomGoal: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var emoji: String
    init(name: String, emoji: String) { self.id = UUID(); self.name = name; self.emoji = emoji }
}

struct DailyFixedGoals: Codable, Equatable {
    var foodEnabled: Bool = false    // 🍽️ 食事2000kcal以上（Apple Health自動）
    var weightEnabled: Bool = false  // ⚖️ 体重計測（Apple Health自動）
    var sleepEnabled: Bool = false   // 😴 睡眠計測（Apple Health自動）
    var sleepHoursGoal: Int = 7      // 😴 目標睡眠時間（時間）
    var customGoals: [DailyCustomGoal] = []  // 📱 カスタム項目（スクショで完了）
}
