import Foundation

// MARK: - 時間帯の定義

enum TimeSlot: String, Codable, CaseIterable {
    case morning = "morning"       // 6:00 - 10:00
    case noon = "noon"            // 10:00 - 14:00
    case afternoon = "afternoon"  // 14:00 - 18:00
    case evening = "evening"      // 18:00 - 24:00

    var displayName: String {
        switch self {
        case .morning: return "朝"
        case .noon: return "昼"
        case .afternoon: return "午後"
        case .evening: return "夜"
        }
    }

    var emoji: String {
        switch self {
        case .morning: return "🌅"
        case .noon: return "☀️"
        case .afternoon: return "🌤️"
        case .evening: return "🌙"
        }
    }

    var timeRange: String {
        switch self {
        case .morning: return "6:00 - 10:00"
        case .noon: return "10:00 - 14:00"
        case .afternoon: return "14:00 - 18:00"
        case .evening: return "18:00 - 24:00"
        }
    }

    var startHour: Int {
        switch self {
        case .morning: return 6
        case .noon: return 10
        case .afternoon: return 14
        case .evening: return 18
        }
    }

    var endHour: Int {
        switch self {
        case .morning: return 10
        case .noon: return 14
        case .afternoon: return 18
        case .evening: return 24
        }
    }

    /// 現在の時刻が属する時間帯を取得
    static func current() -> TimeSlot {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 6 && hour < 10 { return .morning }
        if hour >= 10 && hour < 14 { return .noon }
        if hour >= 14 && hour < 18 { return .afternoon }
        return .evening
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
    static let duolingo = CustomActivity(name: "Duolingo", emoji: "🦉")
    static let reading = CustomActivity(name: "読書", emoji: "📚")
    static let meditation = CustomActivity(name: "瞑想", emoji: "🧘")
    static let stretching = CustomActivity(name: "ストレッチ", emoji: "🤸")
}

// MARK: - 時間帯ごとの目標

struct TimeSlotGoal: Codable, Identifiable {
    var id: String { timeSlot.rawValue }
    let timeSlot: TimeSlot
    var trainingGoal: Int           // トレーニングセット数
    var mindfulnessGoal: Int        // マインドフルネス回数
    var logGoal: LogGoal            // ログ目標
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

struct LogGoal: Codable {
    var mealRequired: Bool = true       // 食事記録必須
    var drinkRequired: Bool = true      // 飲み物記録必須
    var mindInputRequired: Bool = false // マインド入力必須

    var totalRequired: Int {
        var count = 0
        if mealRequired { count += 1 }
        if drinkRequired { count += 1 }
        if mindInputRequired { count += 1 }
        return count
    }
}

// MARK: - 時間帯ごとの実績

struct TimeSlotProgress: Codable, Identifiable {
    var id: String { timeSlot.rawValue }
    let timeSlot: TimeSlot
    var trainingCompleted: Int = 0       // 完了したトレーニングセット数
    var mindfulnessCompleted: Int = 0    // 完了したマインドフルネス回数
    var logProgress: LogProgress = LogProgress()
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

        // マインドフルネス
        if goal.mindfulnessGoal > 0 {
            totalGoals += 1
            if mindfulnessCompleted >= goal.mindfulnessGoal {
                completed += 1
            }
        }

        // ログ
        let logGoals = goal.logGoal.totalRequired
        if logGoals > 0 {
            totalGoals += 1
            if logProgress.completedCount >= logGoals {
                completed += 1
            }
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

struct LogProgress: Codable {
    var mealLogged: Int = 0  // 記録された食事の回数
    var drinkLogged: Int = 0  // 記録されたドリンクの回数
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
        CustomDailyGoal(name: "読書", emoji: "📚"),
        CustomDailyGoal(name: "Duolingo", emoji: "🦉"),
        CustomDailyGoal(name: "瞑想", emoji: "🧘"),
        CustomDailyGoal(name: "ストレッチ", emoji: "🤸"),
        CustomDailyGoal(name: "早起き", emoji: "🌅"),
        CustomDailyGoal(name: "禁酒", emoji: "🚫"),
    ]
}

// MARK: - 1日全体の目標（時間帯に関係なし）

struct DailyGlobalGoals: Codable {
    var workoutEnabled: Bool = false           // ワークアウト目標を使用するか
    var workoutMinutes: Int = 15               // 目標ワークアウト時間（分）
    var standEnabled: Bool = false             // スタンド時間目標を使用するか
    var standHours: Int = 12                   // 目標スタンド時間（時間）
    var sleepEnabled: Bool = false             // 睡眠計測目標を使用するか
    var sleepScoreThreshold: Int = 80          // 睡眠スコアの目標（80点以上で達成）
    var pfcEnabled: Bool = false               // PFCバランス目標を使用するか
    var pfcScoreThreshold: Int = 80            // PFCバランススコアの目標（80点以上で達成）
    var weightEnabled: Bool = false            // 体重計測目標を使用するか
    var customGoals: [CustomDailyGoal] = []    // ユーザー定義のカスタム目標
}

// MARK: - 1日全体の実績

struct DailyGlobalProgress: Codable {
    var workoutMinutes: Int = 0                // 完了したワークアウト時間（分）
    var standHours: Int = 0                    // 完了したスタンド時間（時間）
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
