import Foundation
import Combine

// MARK: - 時間帯の定義

enum TimeSlot: String, Codable, CaseIterable {
    case midnight = "midnight"     // 0:00 - 6:00
    case morning = "morning"       // 6:00 - 10:00
    case noon = "noon"            // 10:00 - 14:00
    case afternoon = "afternoon"  // 14:00 - 18:00
    case evening = "evening"      // 18:00 - 24:00

    var displayName: String {
        switch self {
        case .midnight: return "夜中"
        case .morning: return "朝"
        case .noon: return "昼"
        case .afternoon: return "午後"
        case .evening: return "夜"
        }
    }

    var emoji: String {
        switch self {
        case .midnight: return "💤"
        case .morning: return "🌅"
        case .noon: return "☀️"
        case .afternoon: return "🌤️"
        case .evening: return "🌙"
        }
    }

    var timeRange: String {
        switch self {
        case .midnight: return "0:00 - 6:00"
        case .morning: return "6:00 - 10:00"
        case .noon: return "10:00 - 14:00"
        case .afternoon: return "14:00 - 18:00"
        case .evening: return "18:00 - 24:00"
        }
    }

    var startHour: Int {
        switch self {
        case .midnight: return 0
        case .morning: return 6
        case .noon: return 10
        case .afternoon: return 14
        case .evening: return 18
        }
    }

    var endHour: Int {
        switch self {
        case .midnight: return 6
        case .morning: return 10
        case .noon: return 14
        case .afternoon: return 18
        case .evening: return 24
        }
    }

    /// 指定した時刻（0〜23時）が属する時間帯を取得
    static func forHour(_ hour: Int) -> TimeSlot {
        if hour < 6 { return .midnight }
        if hour < 10 { return .morning }
        if hour < 14 { return .noon }
        if hour < 18 { return .afternoon }
        return .evening
    }

    /// 現在の時刻が属する時間帯を取得
    static func current() -> TimeSlot {
        let hour = Calendar.current.component(.hour, from: Date())
        return forHour(hour)
    }
}

// MARK: - カスタムアクティビティ

struct CustomActivity: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var emoji: String
    var isEnabled: Bool

    init(id: String = UUID().uuidString, name: String, emoji: String, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.isEnabled = isEnabled
    }

    // プリセットアクティビティ
    static let duolingo      = CustomActivity(name: "Duolingo",      emoji: "🦉")
    static let reading       = CustomActivity(name: "読書",           emoji: "📚")
    static let meditation    = CustomActivity(name: "瞑想",           emoji: "🧘")
    static let stretching    = CustomActivity(name: "ストレッチ",     emoji: "🤸")
    static let toothbrushing = CustomActivity(name: "歯磨き・フロス", emoji: "🦷")
    static let coffee        = CustomActivity(name: "コーヒーを淹れる", emoji: "☕")
    static let study         = CustomActivity(name: "勉強",           emoji: "📖")
    static let webPost       = CustomActivity(name: "今日をシェア",   emoji: "📤")

    /// このカスタム活動が「ウェブ投稿」項目かどうか（名前一致で判定。既存の読書/勉強判定と同様の方式）
    var isWebPostType: Bool { name == CustomActivity.webPost.name }
}

// MARK: - ストレッチ・ヨガ目標

struct StretchGoal: Codable, Equatable {
    var enabled: Bool = false
    var stretchMinutes: Int = 3     // 目標マインドフルネス時間（分）
}

// MARK: - 20分スタンド目標（ポモドーロ）

struct StandGoal: Codable, Equatable {
    var enabled: Bool = false       // デフォルトはオフ
    var standMinutes: Int = 20      // 1セッションの目標スタンド時間（分）
}

// MARK: - 時間帯ごとの目標

struct TimeSlotGoal: Codable, Identifiable, Equatable {
    var id: String { timeSlot.rawValue }
    let timeSlot: TimeSlot
    var trainingGoal: Int           // トレーニングセット数
    var mindfulnessGoal: Int        // マインドフルネス回数
    var logGoal: LogGoal            // ログ目標
    var stretchGoal: StretchGoal = StretchGoal() // ストレッチ・ヨガ目標
    var standGoal: StandGoal = StandGoal()       // 20分スタンド目標
    var customActivities: [CustomActivity] = [] // カスタムアクティビティ
    var reminderEnabled: Bool       // リマインダー有効
    var reminderTime: Date?         // リマインダー時刻

    init(timeSlot: TimeSlot, trainingGoal: Int = 1, mindfulnessGoal: Int = 1, logGoal: LogGoal = LogGoal()) {
        self.timeSlot = timeSlot
        self.trainingGoal = trainingGoal
        self.mindfulnessGoal = mindfulnessGoal
        self.logGoal = logGoal
        self.reminderEnabled = false
        self.reminderTime = nil
    }
}

// MARK: - ログ目標

struct LogGoal: Codable, Equatable {
    var mealGoal: Int = 400          // 0=不要, N=目標kcal
    var drinkGoal: Int = 400         // 0=不要, N=目標ml
    var mindInputRequired: Bool = false

    var mealRequired: Bool { mealGoal > 0 }
    var drinkRequired: Bool { drinkGoal > 0 }

    var totalRequired: Int {
        (mealGoal > 0 ? 1 : 0) + (drinkGoal > 0 ? 1 : 0) + (mindInputRequired ? 1 : 0)
    }
}

// MARK: - 時間帯ごとの実績

struct TimeSlotProgress: Codable, Identifiable, Equatable {
    var id: String { timeSlot.rawValue }
    let timeSlot: TimeSlot
    var trainingCompleted: Int = 0       // 完了したトレーニングセット数
    var mindfulnessCompleted: Int = 0    // 完了したマインドフルネス回数
    var logProgress: LogProgress = LogProgress()
    var stretchSetsCompleted: Int = 0    // 完了したストレッチ・ヨガセット数
    var standCompleted: Int = 0          // 完了した20分スタンドセッション数
    var completedActivityIds: Set<String> = [] // 完了したカスタムアクティビティのID
    var lastUpdated: Date = Date()

    /// 目標達成率（0.0 - 1.0）
    func completionRate(goal: TimeSlotGoal) -> Double {
        var totalGoals = 0
        var completed = 0

        // トレーニング
        if goal.trainingGoal > 0 {
            totalGoals += 1
            if trainingCompleted >= goal.trainingGoal {
                completed += 1
            }
        }

        // マインドフルネス（分）: 瞑想1セッション=1分, ストレッチ1セット=3分
        if goal.mindfulnessGoal > 0 {
            totalGoals += 1
            let totalMindfulMinutes = mindfulnessCompleted * 1 + stretchSetsCompleted * 3
            if totalMindfulMinutes >= goal.mindfulnessGoal { completed += 1 }
        }

        // ログ（食事・水分は1日全体の目標で管理するため除外）
        if goal.logGoal.mealGoal > 0 {
            totalGoals += 1
            if logProgress.mealLogged >= goal.logGoal.mealGoal { completed += 1 }
        }
        if goal.logGoal.drinkGoal > 0 {
            totalGoals += 1
            if logProgress.drinkLogged >= goal.logGoal.drinkGoal { completed += 1 }
        }

        // 20分スタンド（夜中以外）
        if goal.standGoal.enabled && goal.timeSlot != .midnight {
            totalGoals += 1
            if standCompleted >= 1 { completed += 1 }
        }

        // カスタムアクティビティ
        let enabledActivities = goal.customActivities.filter { $0.isEnabled }
        for activity in enabledActivities {
            totalGoals += 1
            if completedActivityIds.contains(activity.id) {
                completed += 1
            }
        }

        return totalGoals > 0 ? Double(completed) / Double(totalGoals) : 0.0
    }

    /// 完全達成したか
    func isFullyCompleted(goal: TimeSlotGoal) -> Bool {
        return completionRate(goal: goal) >= 1.0
    }
}

// MARK: - ログ進捗

struct LogProgress: Codable, Equatable {
    var mealLogged: Int = 0  // この時間帯の累積摂取kcal
    var drinkLogged: Int = 0  // この時間帯の累積ml
    var mindInputLogged: Int = 0  // 記録されたマインド入力の回数

    var completedCount: Int {
        var count = 0
        if mealLogged > 0 { count += 1 }
        if drinkLogged > 0 { count += 1 }
        if mindInputLogged > 0 { count += 1 }
        return count
    }
}

// MARK: - カスタム日次目標（任意に追加できる1日単位の目標）

struct CustomDailyGoal: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var emoji: String
    var isEnabled: Bool = true

    // プリセット例
    static let presets: [CustomDailyGoal] = [
        CustomDailyGoal(name: "読書",           emoji: "📚"),
        CustomDailyGoal(name: "Duolingo",       emoji: "🦉"),
        CustomDailyGoal(name: "瞑想",           emoji: "🧘"),
        CustomDailyGoal(name: "ストレッチ",     emoji: "🤸"),
        CustomDailyGoal(name: "早起き",         emoji: "🌅"),
        CustomDailyGoal(name: "禁酒",           emoji: "🚫"),
        CustomDailyGoal(name: "歯磨き・フロス", emoji: "🦷"),
        CustomDailyGoal(name: "コーヒーを淹れる", emoji: "☕"),
        CustomDailyGoal(name: "勉強",           emoji: "📖"),
    ]
}

// MARK: - 1日全体の目標（時間帯に関係なし）

struct DailyGlobalGoals: Codable {
    var activityEnabled: Bool = false          // アクティビティリング目標を使用するか
    var workoutEnabled: Bool = false           // (後方互換、非使用)
    var workoutMinutes: Int = 15               // (後方互換、非使用)
    var standEnabled: Bool = false             // (後方互換、非使用)
    var standHours: Int = 12                   // (後方互換、非使用)
    var sleepEnabled: Bool = false             // 睡眠計測目標を使用するか
    var sleepHoursGoal: Int = 6              // 睡眠時間の目標（時間）
    var sleepScoreThreshold: Int = 80          // 睡眠スコアの目標（80点以上で達成）
    var pfcEnabled: Bool = false               // PFCバランス目標を使用するか
    var pfcScoreThreshold: Int = 80            // PFCバランススコアの目標（80点以上で達成）
    var mindfulnessEnabled: Bool = true        // マインドフルネス計測を使用するか
    var weightEnabled: Bool = false            // 体重計測目標を使用するか
    var mealEnabled: Bool = true               // 食事カロリー目標を使用するか
    var dailyMealKcal: Int = 2000             // 1日の食事カロリー目標（4時間帯に均等配分）
    var drinkEnabled: Bool = true              // 水分目標を使用するか
    var dailyDrinkMl: Int = 1000             // 1日の水分目標ml（4時間帯に均等配分）
    var customGoals: [CustomDailyGoal] = []    // ユーザー定義のカスタム目標
}

// MARK: - 1日全体の実績

struct DailyGlobalProgress: Codable {
    var workoutMinutes: Int = 0                // 完了したワークアウト時間（分）
    var standHours: Int = 0                    // 完了したスタンド時間（時間）
    var sleepHours: Double = 0.0               // 睡眠時間（時間）
    var sleepScore: Int = 0                    // 睡眠スコア（0-100点）
    var pfcScore: Int = 0                      // PFCバランススコア（0-100点）
    var weightMeasured: Bool = false           // 今日体重を計測したか
    var completedCustomGoalIds: [String] = []  // 達成済みカスタム目標IDリスト
    var lastUpdated: Date = Date()
}

// MARK: - 1日の時間帯別目標設定

struct DailyTimeSlotSettings: Codable {
    var goals: [TimeSlotGoal]
    var date: Date
    var globalGoals: DailyGlobalGoals = DailyGlobalGoals()  // 1日全体の目標

    init(date: Date = Date()) {
        self.date = date
        self.goals = TimeSlot.allCases.map { TimeSlotGoal(timeSlot: $0) }
    }

    func goalFor(_ timeSlot: TimeSlot) -> TimeSlotGoal? {
        return goals.first { $0.timeSlot == timeSlot }
    }

    mutating func updateGoal(_ goal: TimeSlotGoal) {
        if let index = goals.firstIndex(where: { $0.timeSlot == goal.timeSlot }) {
            goals[index] = goal
        }
    }
}

// MARK: - 1日の時間帯別実績

struct DailyTimeSlotProgress: Codable {
    var progress: [TimeSlotProgress]
    var date: Date
    var globalProgress: DailyGlobalProgress = DailyGlobalProgress()  // 1日全体の実績

    init(date: Date = Date()) {
        self.date = date
        self.progress = TimeSlot.allCases.map { TimeSlotProgress(timeSlot: $0) }
    }

    func progressFor(_ timeSlot: TimeSlot) -> TimeSlotProgress? {
        return progress.first { $0.timeSlot == timeSlot }
    }

    mutating func updateProgress(_ prog: TimeSlotProgress) {
        if let index = progress.firstIndex(where: { $0.timeSlot == prog.timeSlot }) {
            progress[index] = prog
        }
    }
}
