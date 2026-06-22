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

    // アプリヘッダーと同じ値を使用（常にsyncedProgressPercentを優先、未同期時は0）
    var progressPercent: Int {
        return min(100, max(0, syncedProgressPercent ?? 0))
    }

    var progressColor: Color {
        switch progressPercent {
        case 100:   return Color(hex: "#4CAF50")
        case 70...: return Color(hex: "#A5D63B")
        case 40...: return Color(hex: "#FFD700")
        case 1...:  return Color(hex: "#FF9500")
        default:    return Color(hex: "#9E9E9E")
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

// MARK: - Deep Link URL Helpers

private extension URL {
    static let fitingoHome        = URL(string: "fitingo://home")!
    static let fitingoWorkout     = URL(string: "fitingo://workout")!
    static let fitingoMindfulness = URL(string: "fitingo://mindfulness")!
    static let fitingoFood        = URL(string: "fitingo://food")!
    static let fitingoMind        = URL(string: "fitingo://mind")!
    static let fitingoGoal        = URL(string: "fitingo://goal")!
}

// MARK: - Small Widget（2×2 グリッド）
// タップ → トレーニング開始

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
        .widgetURL(.fitingoWorkout)  // Small: タップ → トレーニング
        .containerBackground(stats.progressColor, for: .widget)
    }

    private func headerCell(icon: String, value: String, sub: String) -> some View {
        VStack(spacing: 2) {
            Text(icon).font(.system(size: 16))
            Text(value)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
                .widgetAccentable()
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
                // 🔥 ストリーク → ホーム
                Link(destination: .fitingoHome) {
                    mediumCell(icon: "🔥", value: "\(stats.streak)", sub: "日連続")
                }
                divider
                // 📊 達成度 → ホーム
                Link(destination: .fitingoHome) {
                    mediumCell(icon: "📊", value: "\(stats.progressPercent)%", sub: "達成度",
                               badge: stats.progressPercent == 100 ? "✓" : nil)
                }
                divider
                // 📈/📉 カロリー収支 → FOOD
                Link(destination: .fitingoFood) {
                    let balSign = stats.calorieBalance >= 0 ? "+" : ""
                    mediumCell(
                        icon: stats.calorieBalance >= 0 ? "📈" : "📉",
                        value: "\(balSign)\(stats.calorieBalance)",
                        sub: "kcal"
                    )
                }
                divider
                // ⭐ XP → ホーム
                Link(destination: .fitingoHome) {
                    mediumCell(icon: "⭐", value: "\(stats.totalPoints)", sub: "XP")
                }
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
                    .widgetAccentable()
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
                // Fitingo アイコン + アプリ名 + 日付時刻（1行）→ ホームへ
                Link(destination: .fitingoHome) {
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
                }

                // iOSヘッダーと同じ4項目（各セルをタップで関連画面へ）
                HStack(spacing: 0) {
                    Link(destination: .fitingoHome) {
                        largeHeaderCell(icon: "🔥", value: "\(stats.streak)", sub: "日連続")
                    }
                    Link(destination: .fitingoHome) {
                        largeHeaderCell(icon: "📊", value: "\(stats.progressPercent)%", sub: "達成度")
                    }
                    Link(destination: .fitingoFood) {
                        let balSign = stats.calorieBalance >= 0 ? "+" : ""
                        largeHeaderCell(
                            icon: stats.calorieBalance >= 0 ? "📈" : "📉",
                            value: "\(balSign)\(stats.calorieBalance)",
                            sub: "kcal"
                        )
                    }
                    Link(destination: .fitingoHome) {
                        largeHeaderCell(icon: "⭐", value: "\(stats.totalPoints)", sub: "XP")
                    }
                }
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.15))
                .cornerRadius(12)

                Divider().background(Color.white.opacity(0.3))

                // 目標別進捗リスト（タップで各アクション画面へ）
                VStack(spacing: 8) {
                    if stats.trainingGoal > 0 {
                        Link(destination: .fitingoWorkout) {
                            largeGoalRow(icon: "💪", label: "トレーニング",
                                         done: stats.trainingCompleted, goal: stats.trainingGoal)
                        }
                    }
                    if stats.mindfulnessGoal > 0 {
                        Link(destination: .fitingoMindfulness) {
                            largeGoalRow(icon: "🧘", label: "マインドフル",
                                         done: stats.mindfulnessCompleted, goal: stats.mindfulnessGoal)
                        }
                    }
                    if stats.mealGoal > 0 {
                        Link(destination: .fitingoFood) {
                            largeGoalRow(icon: "🍽️", label: "食事",
                                         done: stats.mealLogged, goal: stats.mealGoal)
                        }
                    }
                    if stats.drinkGoal > 0 {
                        Link(destination: .fitingoFood) {
                            largeGoalRow(icon: "💧", label: "水分",
                                         done: stats.drinkLogged, goal: stats.drinkGoal)
                        }
                    }
                    if stats.workoutGoal > 0 {
                        Link(destination: .fitingoWorkout) {
                            largeGoalRow(icon: "🏃", label: "ワークアウト",
                                         done: stats.workoutMinutes, goal: stats.workoutGoal, unit: "分")
                        }
                    }
                    if stats.standGoal > 0 {
                        Link(destination: .fitingoMind) {
                            largeGoalRow(icon: "🧍", label: "スタンド",
                                         done: stats.standHours, goal: stats.standGoal, unit: "h")
                        }
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
            Text(icon).font(.system(size: 40))
            Text(value)
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1).minimumScaleFactor(0.42)
            Text(sub)
                .font(.system(size: 14, weight: .bold))
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

// MARK: - Circular Progress Arc

private struct CircularProgressArc: Shape {
    var progress: Double
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let start = -CGFloat.pi / 2
        let end = start + CGFloat(2 * Double.pi * min(1, max(0, progress)))
        p.addArc(center: center, radius: radius, startAngle: .radians(Double(start)),
                 endAngle: .radians(Double(end)), clockwise: false)
        return p
    }
}

// MARK: - Focus Widget Cell（Training / Mindfulness / Meal 共通ベース）

private struct FocusWidgetCell: View {
    let icon: String
    let label: String
    let numerator: String
    let denominator: String
    let unit: String
    let progress: Double
    let achieved: Bool
    let accentColor: Color

    var body: some View {
        ZStack {
            // ─ 背景グラデーション ─
            LinearGradient(
                colors: achieved
                    ? [Color(hex: "#58CC02"), Color(hex: "#45A300")]
                    : [accentColor, accentColor.opacity(0.75)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // ラベル行（上）
                HStack(spacing: 4) {
                    Text(icon).font(.system(size: 13))
                    Text(label)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                    if achieved {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)

                Spacer()

                // 円弧プログレス + 数値
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.22), lineWidth: 6)
                        .frame(width: 76, height: 76)
                    CircularProgressArc(progress: progress)
                        .stroke(Color.white,
                                style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 76, height: 76)
                    VStack(spacing: 0) {
                        Text(numerator)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .widgetAccentable()
                        HStack(spacing: 2) {
                            Text("/\(denominator)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.75))
                            if !unit.isEmpty {
                                Text(unit)
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                }

                Spacer()

                // Fitingo ロゴ（下左）
                HStack {
                    Image("fitingo_button_mascot")
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                        .clipShape(Circle())
                        .opacity(0.8)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Training Widget

struct TrainingWidgetView: View {
    let stats: WidgetStats
    private var progress: Double {
        guard stats.trainingGoal > 0 else { return 0 }
        return min(1, Double(stats.trainingCompleted) / Double(stats.trainingGoal))
    }
    private var achieved: Bool { stats.trainingGoal > 0 && stats.trainingCompleted >= stats.trainingGoal }

    var body: some View {
        FocusWidgetCell(
            icon: "💪", label: "トレーニング",
            numerator: "\(stats.trainingCompleted)",
            denominator: stats.trainingGoal > 0 ? "\(stats.trainingGoal)" : "-",
            unit: "セット",
            progress: progress, achieved: achieved,
            accentColor: Color(hex: "#1CB0F6")
        )
        .widgetURL(.fitingoWorkout)
        .containerBackground(achieved ? Color(hex: "#58CC02") : Color(hex: "#1CB0F6"), for: .widget)
    }
}

struct TrainingWidget: Widget {
    let kind = "TrainingWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            TrainingWidgetView(stats: entry.stats)
        }
        .configurationDisplayName("💪 トレーニング")
        .description("今日のセット数を表示")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Mindfulness Widget

struct MindfulnessWidgetView: View {
    let stats: WidgetStats
    private var progress: Double {
        guard stats.mindfulnessGoal > 0 else { return 0 }
        return min(1, Double(stats.mindfulnessCompleted) / Double(stats.mindfulnessGoal))
    }
    private var achieved: Bool { stats.mindfulnessGoal > 0 && stats.mindfulnessCompleted >= stats.mindfulnessGoal }

    var body: some View {
        FocusWidgetCell(
            icon: "🧘", label: "マインドフル",
            numerator: "\(stats.mindfulnessCompleted)",
            denominator: stats.mindfulnessGoal > 0 ? "\(stats.mindfulnessGoal)" : "-",
            unit: "分",
            progress: progress, achieved: achieved,
            accentColor: Color(hex: "#9B59B6")
        )
        .widgetURL(.fitingoMindfulness)
        .containerBackground(achieved ? Color(hex: "#58CC02") : Color(hex: "#9B59B6"), for: .widget)
    }
}

struct MindfulnessWidget: Widget {
    let kind = "MindfulnessWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            MindfulnessWidgetView(stats: entry.stats)
        }
        .configurationDisplayName("🧘 マインドフルネス")
        .description("今日のマインドフルネス達成度を表示")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Meal Widget

struct MealWidgetView: View {
    let stats: WidgetStats
    private var progress: Double {
        guard stats.mealGoal > 0 else { return 0 }
        return min(1, Double(stats.mealLogged) / Double(stats.mealGoal))
    }
    private var achieved: Bool { stats.mealGoal > 0 && stats.mealLogged >= stats.mealGoal }

    var body: some View {
        FocusWidgetCell(
            icon: "🍽️", label: "食事記録",
            numerator: "\(stats.mealLogged)",
            denominator: stats.mealGoal > 0 ? "\(stats.mealGoal)" : "-",
            unit: "kcal",
            progress: progress, achieved: achieved,
            accentColor: Color(hex: "#FF9600")
        )
        .widgetURL(.fitingoFood)
        .containerBackground(achieved ? Color(hex: "#58CC02") : Color(hex: "#FF9600"), for: .widget)
    }
}

struct MealWidget: Widget {
    let kind = "MealWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            MealWidgetView(stats: entry.stats)
        }
        .configurationDisplayName("🍽️ 食事記録")
        .description("今日の摂取カロリーを表示")
        .supportedFamilies([.systemSmall])
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
