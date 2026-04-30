import Foundation

/// 習慣スタック: 既存の日課とトレーニングをセットで紐づける
/// 例: "歯磨き（7:30）が終わったらトレーニング"
struct HabitStack: Identifiable, Codable, Equatable {
    var id: UUID    = UUID()
    var emoji: String       // 🦷 🚿 ☕️ など
    var name: String        // "歯磨き", "シャワー" など
    var hour: Int           // 0–23
    var minute: Int         // 0–59
    var isEnabled: Bool = true

    var timeString: String {
        String(format: "%02d:%02d", hour, minute)
    }

    var notificationId: String {
        "duofit.habitstack.\(id.uuidString)"
    }
}

// よく使うプリセット
extension HabitStack {
    static let presets: [(emoji: String, name: String, hour: Int, minute: Int)] = [
        ("🦷", "朝の歯磨き",    7,  0),
        ("☕️", "朝のコーヒー",  7, 30),
        ("🚿", "シャワー",     7, 30),
        ("🌙", "夜の歯磨き",   21, 30),
        ("📱", "就寝前のスマホ", 22,  0),
        ("🚌", "通勤・通学",    8,  0),
        ("🏠", "帰宅後",       19,  0),
        ("🍽️", "夕食後",       19, 30),
    ]
}
