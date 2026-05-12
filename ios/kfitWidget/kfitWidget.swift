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
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 10, to: currentDate)!
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
            // 全面緑の背景
            Color(hex: "#58CC02")
                .ignoresSafeArea()

            VStack(spacing: 10) {
                // 連続記録
                HStack(spacing: 4) {
                    Text("🔥")
                        .font(.system(size: 20))
                    Text("\(stats.streak)")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("日連続")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                }

                Divider()
                    .background(Color.white.opacity(0.3))

                // 今日のセット状況（直近の時間帯）
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Text(stats.currentTimeSlot)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                        Text("のセット")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    HStack(spacing: 4) {
                        Text("\(stats.timeSlotCompleted)")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("/")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                        Text("\(stats.timeSlotGoal)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Medium Widget
struct MediumWidgetView: View {
    let stats: WidgetStats

    var body: some View {
        ZStack {
            // 全面緑の背景
            Color(hex: "#58CC02")
                .ignoresSafeArea()

            HStack(spacing: 20) {
                // 左側: 連続記録
                VStack(spacing: 6) {
                    Text("🔥")
                        .font(.system(size: 40))
                    Text("\(stats.streak)")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("日連続")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .background(Color.white.opacity(0.3))
                    .frame(height: 80)

                // 右側: 今日のセット状況（直近の時間帯）
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Text("📊")
                            .font(.system(size: 20))
                        Text("\(stats.currentTimeSlot)のセット")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                    }

                    HStack(alignment: .bottom, spacing: 6) {
                        Text("\(stats.timeSlotCompleted)")
                            .font(.system(size: 48, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("/")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.bottom, 4)
                        Text("\(stats.timeSlotGoal)")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                    }

                    Text("完了")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
    }
}

// MARK: - Large Widget
struct LargeWidgetView: View {
    let stats: WidgetStats

    var body: some View {
        ZStack {
            // 全面緑の背景
            Color(hex: "#58CC02")
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // ヘッダー
                HStack {
                    Text("💪")
                        .font(.system(size: 40))
                    Text("DuoFit")
                        .font(.system(size: 24, weight: .black))
                        .foregroundColor(.white)
                    Spacer()
                }

                // 連続記録（大きく表示）
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Text("🔥")
                            .font(.system(size: 50))
                        Text("\(stats.streak)")
                            .font(.system(size: 60, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("日連続")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.bottom, 8)
                    }
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.15))
                .cornerRadius(16)

                Divider()
                    .background(Color.white.opacity(0.3))

                // 今日のセット状況（直近の時間帯）
                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Text("📊")
                            .font(.system(size: 24))
                        Text("\(stats.currentTimeSlot)のセット状況")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }

                    HStack(alignment: .bottom, spacing: 8) {
                        Text("\(stats.timeSlotCompleted)")
                            .font(.system(size: 72, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("/")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.bottom, 10)
                        Text("\(stats.timeSlotGoal)")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                    }

                    Text("完了")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.15))
                .cornerRadius(16)

                Spacer()
            }
            .padding()
        }
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
