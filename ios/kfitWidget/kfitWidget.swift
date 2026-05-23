import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), stats: WidgetStats())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        completion(SimpleEntry(date: Date(), stats: loadStats()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let current = Date()
        let next = Calendar.current.date(byAdding: .minute, value: 10, to: current)!
        completion(Timeline(entries: [SimpleEntry(date: current, stats: loadStats())], policy: .after(next)))
    }

    private func loadStats() -> WidgetStats {
        guard let ud = UserDefaults(suiteName: "group.com.kfit.app") else { return WidgetStats() }
        var s = WidgetStats()
        s.streak               = ud.integer(forKey: "streak")
        s.totalPoints          = ud.integer(forKey: "totalPoints")
        s.calorieBalance       = ud.integer(forKey: "calorieBalance")
        s.trainingCompleted    = ud.integer(forKey: "trainingCompleted")
        s.trainingGoal         = ud.integer(forKey: "trainingGoal")
        s.mindfulnessCompleted = ud.integer(forKey: "mindfulnessCompleted")
        s.mindfulnessGoal      = ud.integer(forKey: "mindfulnessGoal")
        s.mealLogged           = ud.integer(forKey: "mealLogged")
        s.mealGoal             = ud.integer(forKey: "mealGoal")
        s.drinkLogged          = ud.integer(forKey: "drinkLogged")
        s.drinkGoal            = ud.integer(forKey: "drinkGoal")
        s.workoutMinutes       = ud.integer(forKey: "workoutMinutes")
        s.workoutGoal          = ud.integer(forKey: "workoutGoal")
        s.standHours           = ud.integer(forKey: "standHours")
        s.standGoal            = ud.integer(forKey: "standGoal")
        if let syncedProgress = ud.object(forKey: "progressPercent") as? Int {
            s.syncedProgressPercent = syncedProgress
        }
        return s
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let stats: WidgetStats
}

// MARK: - WidgetStats（iOSヘッダーと同じ計算式）

struct WidgetStats {
    var streak: Int = 0
    var totalPoints: Int = 0
    var calorieBalance: Int = 0

    var trainingCompleted: Int = 0
    var trainingGoal: Int = 0
    var mindfulnessCompleted: Int = 0
    var mindfulnessGoal: Int = 0
    var mealLogged: Int = 0
    var mealGoal: Int = 0
    var drinkLogged: Int = 0
    var drinkGoal: Int = 0
    var workoutMinutes: Int = 0
    var workoutGoal: Int = 0
    var standHours: Int = 0
    var standGoal: Int = 0
    var syncedProgressPercent: Int? = nil

    // iOSホームの「現在までの進捗」と同じ値を優先して表示
    var progressPercent: Int {
        if let syncedProgressPercent {
            return min(100, max(0, syncedProgressPercent))
        }
        var totalGoals = 0
        var completed = 0
        if trainingGoal > 0    { totalGoals += 1; if trainingCompleted >= trainingGoal       { completed += 1 } }
        if mindfulnessGoal > 0 { totalGoals += 1; if mindfulnessCompleted >= mindfulnessGoal { completed += 1 } }
        if mealGoal > 0        { totalGoals += 1; if mealLogged >= mealGoal                  { completed += 1 } }
        if drinkGoal > 0       { totalGoals += 1; if drinkLogged >= drinkGoal                { completed += 1 } }
        if workoutGoal > 0     { totalGoals += 1; if workoutMinutes >= workoutGoal            { completed += 1 } }
        if standGoal > 0       { totalGoals += 1; if standHours >= standGoal                  { completed += 1 } }
        return totalGoals > 0 ? Int(Double(completed) / Double(totalGoals) * 100) : 0
    }

    var progressColor: Color {
        switch progressPercent {
        case 100:   return Color(hex: "#58CC02")
        case 70...: return Color(hex: "#7ED321")
        case 40...: return Color(hex: "#F5A623")
        case 1...:  return Color(hex: "#FF6B6B")
        default:    return Color(hex: "#D0021B")
        }
    }
}

// MARK: - Widget Entry View

struct kfitWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:  SmallWidgetView(stats: entry.stats)
        case .systemMedium: MediumWidgetView(stats: entry.stats, date: entry.date)
        case .systemLarge:  LargeWidgetView(stats: entry.stats, date: entry.date)
        default:            SmallWidgetView(stats: entry.stats)
        }
    }
}

struct kfitWidget: Widget {
    let kind = "kfitWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                kfitWidgetEntryView(entry: entry)
                    .containerBackground(entry.stats.progressColor, for: .widget)
            } else {
                kfitWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("Fitingo")
        .description("今日の進捗を表示")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Small Widget（2×2 グリッド）

struct SmallWidgetView: View {
    let stats: WidgetStats

    var body: some View {
        ZStack(alignment: .topLeading) {
            stats.progressColor.ignoresSafeArea()
            VStack(spacing: 6) {
                HStack(spacing: 0) {
                    headerCell(icon: "🔥", value: "\(stats.streak)", sub: "日連続")
                    Divider().background(Color.white.opacity(0.4)).frame(height: 44)
                    headerCell(icon: "📊", value: "\(stats.progressPercent)%", sub: "達成度")
                }
                Divider().background(Color.white.opacity(0.4)).padding(.horizontal, 12)
                HStack(spacing: 0) {
                    let balSign = stats.calorieBalance >= 0 ? "+" : ""
                    headerCell(
                        icon: stats.calorieBalance >= 0 ? "📈" : "📉",
                        value: "\(balSign)\(stats.calorieBalance)",
                        sub: "kcal"
                    )
                    Divider().background(Color.white.opacity(0.4)).frame(height: 44)
                    headerCell(icon: "⭐", value: "\(stats.totalPoints)", sub: "XP")
                }
            }
            .padding(8)
            // Fitingo アイコン（左上）
            Image("fitingo_button_mascot")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .clipShape(Circle())
                .padding(5)
        }
        .containerBackground(stats.progressColor, for: .widget)
    }

    private func headerCell(icon: String, value: String, sub: String) -> some View {
        VStack(spacing: 2) {
            Text(icon).font(.system(size: 16))
            Text(value)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(sub)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Medium Widget（iOSヘッダーと同じ横4列）

struct MediumWidgetView: View {
    let stats: WidgetStats
    let date: Date

    var body: some View {
        ZStack(alignment: .topLeading) {
            stats.progressColor.ignoresSafeArea()
            HStack(spacing: 0) {
                mediumCell(icon: "🔥", value: "\(stats.streak)", sub: "日連続")
                divider
                mediumCell(icon: "📊", value: "\(stats.progressPercent)%", sub: "達成度",
                           badge: stats.progressPercent == 100 ? "✓" : nil)
                divider
                let balSign = stats.calorieBalance >= 0 ? "+" : ""
                mediumCell(
                    icon: stats.calorieBalance >= 0 ? "📈" : "📉",
                    value: "\(balSign)\(stats.calorieBalance)",
                    sub: "kcal"
                )
                divider
                mediumCell(icon: "⭐", value: "\(stats.totalPoints)", sub: "XP")
            }
            .padding(.horizontal, 12)
            .padding(.top, 38)
            .padding(.bottom, 10)
            // Fitingo アイコン + ラベル + 日付時刻（1行）
            HStack(spacing: 5) {
                Image("fitingo_button_mascot")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 26, height: 26)
                    .clipShape(Circle())
                Text("Fitingo")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Text(date, formatter: Self.headerFormatter)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
        }
        .containerBackground(stats.progressColor, for: .widget)
    }

    private static let headerFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d (EEE)  H:mm"; return f
    }()

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.35))
            .frame(width: 1, height: 60)
    }

    private func mediumCell(icon: String, value: String, sub: String, badge: String? = nil) -> some View {
        VStack(spacing: 4) {
            Text(icon).font(.system(size: 26))
            HStack(spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1).minimumScaleFactor(0.5)
                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            Text(sub)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Large Widget（4ヘッダー + 詳細目標リスト）

struct LargeWidgetView: View {
    let stats: WidgetStats
    let date: Date

    var body: some View {
        ZStack {
            stats.progressColor.ignoresSafeArea()
            VStack(spacing: 12) {
                // Fitingo アイコン + アプリ名 + 日付時刻（1行）
                HStack(spacing: 8) {
                    Image("fitingo_button_mascot")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                    Text("Fitingo")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Text(date, formatter: Self.headerFormatter)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                }

                // iOSヘッダーと同じ4項目
                HStack(spacing: 0) {
                    largeHeaderCell(icon: "🔥", value: "\(stats.streak)", sub: "日連続")
                    largeHeaderCell(icon: "📊", value: "\(stats.progressPercent)%", sub: "達成度")
                    let balSign = stats.calorieBalance >= 0 ? "+" : ""
                    largeHeaderCell(
                        icon: stats.calorieBalance >= 0 ? "📈" : "📉",
                        value: "\(balSign)\(stats.calorieBalance)",
                        sub: "kcal"
                    )
                    largeHeaderCell(icon: "⭐", value: "\(stats.totalPoints)", sub: "XP")
                }
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.15))
                .cornerRadius(12)

                Divider().background(Color.white.opacity(0.3))

                // 目標別進捗リスト
                VStack(spacing: 8) {
                    if stats.trainingGoal > 0 {
                        largeGoalRow(icon: "💪", label: "トレーニング",
                                     done: stats.trainingCompleted, goal: stats.trainingGoal)
                    }
                    if stats.mindfulnessGoal > 0 {
                        largeGoalRow(icon: "🧘", label: "マインドフル",
                                     done: stats.mindfulnessCompleted, goal: stats.mindfulnessGoal)
                    }
                    if stats.mealGoal > 0 {
                        largeGoalRow(icon: "🍽️", label: "食事",
                                     done: stats.mealLogged, goal: stats.mealGoal)
                    }
                    if stats.drinkGoal > 0 {
                        largeGoalRow(icon: "💧", label: "水分",
                                     done: stats.drinkLogged, goal: stats.drinkGoal)
                    }
                    if stats.workoutGoal > 0 {
                        largeGoalRow(icon: "🏃", label: "ワークアウト",
                                     done: stats.workoutMinutes, goal: stats.workoutGoal, unit: "分")
                    }
                    if stats.standGoal > 0 {
                        largeGoalRow(icon: "🧍", label: "スタンド",
                                     done: stats.standHours, goal: stats.standGoal, unit: "h")
                    }
                }
                .padding(.horizontal, 4)

                Spacer()
            }
            .padding(14)
        }
        .containerBackground(stats.progressColor, for: .widget)
    }

    private static let headerFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d (EEE)  H:mm"; return f
    }()

    private func largeHeaderCell(icon: String, value: String, sub: String) -> some View {
        VStack(spacing: 3) {
            Text(icon).font(.system(size: 22))
            Text(value)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(sub)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
    }

    private func largeGoalRow(icon: String, label: String, done: Int, goal: Int, unit: String = "") -> some View {
        let achieved = done >= goal
        return HStack(spacing: 8) {
            Text(icon).font(.system(size: 18))
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Text("\(done)/\(goal)\(unit.isEmpty ? "" : " \(unit)")")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundColor(.white)
            if achieved {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(achieved ? 0.25 : 0.12))
        .cornerRadius(10)
    }
}

// MARK: - Color Extension

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

// MARK: - Preview

#Preview(as: .systemSmall) {
    kfitWidget()
} timeline: {
    SimpleEntry(date: .now, stats: {
        var s = WidgetStats(); s.streak = 7; s.totalPoints = 1240
        s.calorieBalance = 350; s.trainingCompleted = 2; s.trainingGoal = 3
        return s
    }())
}

#Preview(as: .systemMedium) {
    kfitWidget()
} timeline: {
    SimpleEntry(date: .now, stats: {
        var s = WidgetStats(); s.streak = 7; s.totalPoints = 1240
        s.calorieBalance = -120; s.trainingCompleted = 3; s.trainingGoal = 3
        s.workoutMinutes = 20; s.workoutGoal = 30
        return s
    }())
}
