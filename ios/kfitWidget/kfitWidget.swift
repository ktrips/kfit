import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), stats: WidgetStats())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(), stats: loadStats())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let currentDate = Date()
        let entry = SimpleEntry(date: currentDate, stats: loadStats())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: currentDate)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadStats() -> WidgetStats {
        guard let sharedDefaults = UserDefaults(suiteName: "group.com.kfit.app") else {
            return WidgetStats()
        }

        var stats = WidgetStats()
        stats.todaySetCount = sharedDefaults.integer(forKey: "todaySetCount")
        stats.dailySetGoal = sharedDefaults.integer(forKey: "dailySetGoal")
        stats.todayReps = sharedDefaults.integer(forKey: "todayReps")
        stats.streak = sharedDefaults.integer(forKey: "streak")
        stats.todayXP = sharedDefaults.integer(forKey: "todayXP")

        // 時間帯別の情報を読み込み
        stats.currentTimeSlot = sharedDefaults.string(forKey: "currentTimeSlot") ?? "朝"
        stats.timeSlotCompleted = sharedDefaults.integer(forKey: "timeSlotCompleted")
        stats.timeSlotGoal = sharedDefaults.integer(forKey: "timeSlotGoal")

        // 到達度情報を読み込み
        stats.trainingCompleted = sharedDefaults.integer(forKey: "trainingCompleted")
        stats.trainingGoal = sharedDefaults.integer(forKey: "trainingGoal")
        stats.mindfulnessCompleted = sharedDefaults.integer(forKey: "mindfulnessCompleted")
        stats.mindfulnessGoal = sharedDefaults.integer(forKey: "mindfulnessGoal")
        stats.mealLogged = sharedDefaults.integer(forKey: "mealLogged")
        stats.mealGoal = sharedDefaults.integer(forKey: "mealGoal")
        stats.drinkLogged = sharedDefaults.integer(forKey: "drinkLogged")
        stats.drinkGoal = sharedDefaults.integer(forKey: "drinkGoal")

        // カロリー収支情報を読み込み
        stats.calorieBalance = sharedDefaults.integer(forKey: "calorieBalance")

        // 総ポイントを読み込み
        stats.totalPoints = sharedDefaults.integer(forKey: "totalPoints")

        // ワークアウトとスタンド時間を読み込み
        stats.workoutMinutes = sharedDefaults.integer(forKey: "workoutMinutes")
        stats.workoutGoal = sharedDefaults.integer(forKey: "workoutGoal")
        stats.standHours = sharedDefaults.integer(forKey: "standHours")
        stats.standGoal = sharedDefaults.integer(forKey: "standGoal")

        return stats
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let stats: WidgetStats
}

struct WidgetStats {
    var todaySetCount: Int = 0
    var dailySetGoal: Int = 2
    var todayReps: Int = 0
    var streak: Int = 0
    var todayXP: Int = 0
    var currentTimeSlot: String = "朝"
    var timeSlotCompleted: Int = 0
    var timeSlotGoal: Int = 1

    // 到達度情報
    var trainingCompleted: Int = 0
    var trainingGoal: Int = 0
    var mindfulnessCompleted: Int = 0
    var mindfulnessGoal: Int = 0
    var mealLogged: Int = 0
    var mealGoal: Int = 0
    var drinkLogged: Int = 0
    var drinkGoal: Int = 0

    // カロリー収支
    var calorieBalance: Int = 0

    // 総ポイント
    var totalPoints: Int = 0

    // ワークアウトとスタンド時間
    var workoutMinutes: Int = 0
    var workoutGoal: Int = 15
    var standHours: Int = 0
    var standGoal: Int = 12

    // 進捗率の計算（0.0 - 1.0）
    var progressRate: Double {
        var totalGoals = 0
        var completed = 0

        if trainingGoal > 0 {
            totalGoals += 1
            if trainingCompleted >= trainingGoal { completed += 1 }
        }
        if mindfulnessGoal > 0 {
            totalGoals += 1
            if mindfulnessCompleted >= mindfulnessGoal { completed += 1 }
        }
        if mealGoal > 0 {
            totalGoals += 1
            if mealLogged >= mealGoal { completed += 1 }
        }
        if drinkGoal > 0 {
            totalGoals += 1
            if drinkLogged >= drinkGoal { completed += 1 }
        }
        if workoutGoal > 0 {
            totalGoals += 1
            if workoutMinutes >= workoutGoal { completed += 1 }
        }
        if standGoal > 0 {
            totalGoals += 1
            if standHours >= standGoal { completed += 1 }
        }

        return totalGoals > 0 ? Double(completed) / Double(totalGoals) : 0.0
    }

    // 進捗％の計算
    var progressPercent: Int {
        return Int(progressRate * 100)
    }

    // 進捗に基づく背景色
    var backgroundColor: Color {
        if progressRate >= 1.0 {
            return Color(hex: "#58CC02")  // 完璧: 緑
        } else if progressRate >= 0.75 {
            return Color(hex: "#7ED321")  // 良好: 明るい緑
        } else if progressRate >= 0.5 {
            return Color(hex: "#F5A623")  // 普通: オレンジ
        } else if progressRate >= 0.25 {
            return Color(hex: "#FF6B6B")  // 悪い: 薄い赤
        } else {
            return Color(hex: "#D0021B")  // 非常に悪い: 真っ赤
        }
    }
}

struct kfitWidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(stats: entry.stats)
        case .systemMedium:
            MediumWidgetView(stats: entry.stats)
        case .systemLarge:
            LargeWidgetView(stats: entry.stats)
        default:
            SmallWidgetView(stats: entry.stats)
        }
    }
}

struct kfitWidget: Widget {
    let kind: String = "kfitWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                kfitWidgetEntryView(entry: entry)
                    .containerBackground(Color(hex: "#58CC02"), for: .widget)
            } else {
                kfitWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("DuoFit")
        .description("今日のトレーニング進捗を表示")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Small Widget
struct SmallWidgetView: View {
    let stats: WidgetStats

    var body: some View {
        ZStack {
            // Duolingo緑で統一
            Color(hex: "#58CC02")
                .ignoresSafeArea()

            VStack(spacing: 8) {
                // 連続記録
                HStack(spacing: 3) {
                    Text("🔥")
                        .font(.system(size: 14))
                    Text("\(stats.streak)")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                }

                Divider()
                    .background(Color.white.opacity(0.3))
                    .padding(.horizontal, 8)

                // 進捗％
                HStack(spacing: 3) {
                    Text("📊")
                        .font(.system(size: 14))
                    Text("\(stats.progressPercent)%")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    if stats.progressPercent == 100 {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    }
                }

                Divider()
                    .background(Color.white.opacity(0.3))
                    .padding(.horizontal, 8)

                // カロリー収支
                HStack(spacing: 2) {
                    Text(stats.calorieBalance >= 0 ? "📈" : "📉")
                        .font(.system(size: 14))
                    if stats.calorieBalance >= 0 {
                        Text("+")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    Text("\(abs(stats.calorieBalance))")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .padding(10)
        }
        .containerBackground(Color(hex: "#58CC02"), for: .widget)
    }
}

// MARK: - Medium Widget
struct MediumWidgetView: View {
    let stats: WidgetStats

    var body: some View {
        ZStack {
            // Duolingo緑で統一
            Color(hex: "#58CC02")
                .ignoresSafeArea()

            HStack(spacing: 20) {
                // 左側: 連続記録
                VStack(spacing: 6) {
                    Text("🔥")
                        .font(.system(size: 36))
                    Text("\(stats.streak)")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("日連続")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .background(Color.white.opacity(0.3))
                    .frame(height: 80)

                // 中央: 進捗％
                VStack(spacing: 6) {
                    Text("📊")
                        .font(.system(size: 36))
                    Text("\(stats.progressPercent)%")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    if stats.progressPercent == 100 {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    } else {
                        Text("進捗")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .background(Color.white.opacity(0.3))
                    .frame(height: 80)

                // 右側: カロリー収支
                VStack(spacing: 6) {
                    Text(stats.calorieBalance >= 0 ? "📈" : "📉")
                        .font(.system(size: 36))
                    HStack(spacing: 2) {
                        if stats.calorieBalance >= 0 {
                            Text("+")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        Text("\(abs(stats.calorieBalance))")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                    }
                    Text("kcal")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .containerBackground(Color(hex: "#58CC02"), for: .widget)
    }
}

// MARK: - Large Widget
struct LargeWidgetView: View {
    let stats: WidgetStats

    var body: some View {
        ZStack {
            // Duolingo緑で統一
            Color(hex: "#58CC02")
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // ヘッダー
                HStack {
                    Text("💪")
                        .font(.system(size: 36))
                    Text("DuoFit")
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(.white)
                    Spacer()
                }

                // 連続記録（大きく表示）
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Text("🔥")
                            .font(.system(size: 44))
                        Text("\(stats.streak)")
                            .font(.system(size: 52, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("日連続")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.bottom, 6)
                    }
                }
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.15))
                .cornerRadius(14)

                Divider()
                    .background(Color.white.opacity(0.3))

                // 到達度表示（詳細）
                VStack(spacing: 10) {
                    if stats.trainingGoal > 0 {
                        largeProgressRow(icon: "💪", label: "トレーニング", completed: stats.trainingCompleted, goal: stats.trainingGoal)
                    }
                    if stats.mindfulnessGoal > 0 {
                        largeProgressRow(icon: "🧘", label: "マインドフルネス", completed: stats.mindfulnessCompleted, goal: stats.mindfulnessGoal)
                    }
                    if stats.mealGoal > 0 {
                        largeProgressRow(icon: "🍽️", label: "食事記録", completed: stats.mealLogged, goal: stats.mealGoal)
                    }
                    if stats.drinkGoal > 0 {
                        largeProgressRow(icon: "💧", label: "ドリンク記録", completed: stats.drinkLogged, goal: stats.drinkGoal)
                    }
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.15))
                .cornerRadius(14)

                Spacer()
            }
            .padding()
        }
        .containerBackground(Color(hex: "#58CC02"), for: .widget)
    }

    private func largeProgressRow(icon: String, label: String, completed: Int, goal: Int) -> some View {
        HStack(spacing: 8) {
            Text(icon)
                .font(.system(size: 24))
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Text("\(completed)/\(goal)")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(.white)
            if completed >= goal {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - Helper Views
struct StatItem: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(icon)
                .font(.title3)
            Text(value)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.9))
        }
    }
}

struct LargeStatRow: View {
    let icon: String
    let label: String
    var current: Int? = nil
    var goal: Int? = nil
    var value: String? = nil

    var body: some View {
        HStack {
            Text(icon)
                .font(.title2)
            Text(label)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            Spacer()
            if let current = current, let goal = goal {
                Text("\(current)/\(goal)")
                    .font(.title3)
                    .fontWeight(.black)
                    .foregroundColor(.white)
            } else if let value = value {
                Text(value)
                    .font(.title3)
                    .fontWeight(.black)
                    .foregroundColor(.white)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.2))
        .cornerRadius(12)
    }
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted))
        var hexNumber: UInt64 = 0
        scanner.scanHexInt64(&hexNumber)
        let r = Double((hexNumber & 0xff0000) >> 16) / 255
        let g = Double((hexNumber & 0x00ff00) >> 8) / 255
        let b = Double(hexNumber & 0x0000ff) / 255
        self.init(red: r, green: g, blue: b)
    }
}

#Preview(as: .systemSmall) {
    kfitWidget()
} timeline: {
    SimpleEntry(date: .now, stats: WidgetStats(todaySetCount: 1, dailySetGoal: 2, todayReps: 25, streak: 5, todayXP: 150))
}
