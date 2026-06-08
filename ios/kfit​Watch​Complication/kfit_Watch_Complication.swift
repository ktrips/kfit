import WidgetKit
import SwiftUI

// MARK: - Shared Data

private let kfitAppGroup = "group.com.kfit.app"

struct ComplicationData {
    let trainingCompleted: Int
    let trainingGoal: Int
    let mindfulnessCompleted: Int
    let mindfulnessGoal: Int
    let mealLogged: Int
    let mealGoal: Int

    static func current() -> ComplicationData {
        let ud = UserDefaults(suiteName: kfitAppGroup)
        return ComplicationData(
            trainingCompleted:    ud?.integer(forKey: "watch_totalTraining") ?? 0,
            trainingGoal:         ud?.integer(forKey: "watch_totalTrainingGoal") ?? 0,
            mindfulnessCompleted: ud?.integer(forKey: "watch_totalMindfulness") ?? 0,
            mindfulnessGoal:      ud?.integer(forKey: "watch_totalMindfulnessGoal") ?? 0,
            mealLogged:           ud?.integer(forKey: "watch_totalMeal") ?? 0,
            mealGoal:             ud?.integer(forKey: "watch_totalMealGoal") ?? 0
        )
    }

    var trainingProgress: Double {
        guard trainingGoal > 0 else { return 0 }
        return min(Double(trainingCompleted) / Double(trainingGoal), 1.0)
    }
    var trainingDone: Bool { trainingGoal > 0 && trainingCompleted >= trainingGoal }

    var mindfulnessProgress: Double {
        guard mindfulnessGoal > 0 else { return 0 }
        return min(Double(mindfulnessCompleted) / Double(mindfulnessGoal), 1.0)
    }
    var mindfulnessDone: Bool { mindfulnessGoal > 0 && mindfulnessCompleted >= mindfulnessGoal }

    var mealProgress: Double {
        guard mealGoal > 0 else { return 0 }
        return min(Double(mealLogged) / Double(mealGoal), 1.0)
    }
    var mealDone: Bool { mealGoal > 0 && mealLogged >= mealGoal }

    /// 全目標のうち達成済みの数（目標が設定されているもののみカウント）
    var goalsCompleted: Int {
        var count = 0
        if trainingGoal > 0 && trainingDone   { count += 1 }
        if mindfulnessGoal > 0 && mindfulnessDone { count += 1 }
        if mealGoal > 0 && mealDone           { count += 1 }
        return count
    }
    var goalsTotal: Int {
        var count = 0
        if trainingGoal > 0   { count += 1 }
        if mindfulnessGoal > 0 { count += 1 }
        if mealGoal > 0       { count += 1 }
        return count
    }
    var overallProgress: Double {
        guard goalsTotal > 0 else { return 0 }
        return Double(goalsCompleted) / Double(goalsTotal)
    }
    var allDone: Bool { goalsTotal > 0 && goalsCompleted == goalsTotal }

    /// 未達成項目（やるべきこと）の一覧
    var pendingItems: [(icon: String, label: String)] {
        var items: [(String, String)] = []
        if trainingGoal > 0 && !trainingDone {
            items.append(("💪", "トレーニング \(trainingCompleted)/\(trainingGoal)"))
        }
        if mindfulnessGoal > 0 && !mindfulnessDone {
            items.append(("🧘", "マインドフル \(mindfulnessCompleted)/\(mindfulnessGoal)"))
        }
        if mealGoal > 0 && !mealDone {
            let remain = mealGoal - mealLogged
            items.append(("🍽️", "食事 あと\(remain)kcal"))
        }
        return items
    }

    var motivationInlineText: String {
        let pending = pendingItems
        if pending.isEmpty { return "🎉 全て達成！" }
        if pending.count == 1 { return "\(pending[0].icon) \(pending[0].label)" }
        return pending.map { $0.icon }.joined() + " 未完了"
    }
}

// MARK: - Shared Timeline Entry

struct KfitEntry: TimelineEntry {
    let date: Date
    let data: ComplicationData
}

// MARK: - Shared Provider (base)

private func makeTimeline() -> Timeline<KfitEntry> {
    let entry = KfitEntry(date: Date(), data: .current())
    let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
    return Timeline(entries: [entry], policy: .after(next))
}

// MARK: - Shared Circular Arc Shape

private struct ProgressArc: Shape {
    var progress: Double
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2 - 2
        let start = -Double.pi / 2
        let end = start + 2 * Double.pi * min(1, max(0, progress))
        p.addArc(center: center, radius: r,
                 startAngle: .radians(start), endAngle: .radians(end),
                 clockwise: false)
        return p
    }
}

// MARK: - Shared Circular Base View

private struct CircularBase: View {
    let progress: Double
    let done: Bool
    let icon: String
    let numerator: Int
    let denominator: Int
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 3)
            ProgressArc(progress: progress)
                .stroke(done ? .green : color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            VStack(spacing: 0) {
                Text(icon).font(.system(size: 11))
                if denominator > 0 {
                    Text("\(numerator)/\(denominator)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                } else {
                    Text("\(numerator)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
            }
        }
    }
}

// ===========================================================================
// MARK: - 1. Training Complication
// ===========================================================================

struct TrainingProvider: TimelineProvider {
    func placeholder(in context: Context) -> KfitEntry {
        KfitEntry(date: Date(), data: ComplicationData(
            trainingCompleted: 2, trainingGoal: 5,
            mindfulnessCompleted: 0, mindfulnessGoal: 0,
            mealLogged: 0, mealGoal: 0))
    }
    func getSnapshot(in context: Context, completion: @escaping (KfitEntry) -> Void) {
        completion(KfitEntry(date: Date(), data: .current()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<KfitEntry>) -> Void) {
        completion(makeTimeline())
    }
}

struct TrainingEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: KfitEntry

    var body: some View {
        let d = entry.data
        switch family {
        case .accessoryCircular:
            CircularBase(progress: d.trainingProgress, done: d.trainingDone,
                         icon: "💪", numerator: d.trainingCompleted,
                         denominator: d.trainingGoal, color: .blue)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("💪").font(.system(size: 13))
                    Text("トレーニング").font(.headline)
                    Spacer()
                    if d.trainingDone { Text("✅").font(.system(size: 12)) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(d.trainingCompleted)")
                        .font(.title3).bold()
                    if d.trainingGoal > 0 {
                        Text("/ \(d.trainingGoal) セット")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("セット完了")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if d.trainingGoal > 0 {
                    ProgressView(value: d.trainingProgress)
                        .tint(d.trainingDone ? .green : .blue)
                }
            }
        case .accessoryInline:
            if d.trainingGoal > 0 {
                Text("💪 \(d.trainingCompleted)/\(d.trainingGoal) セット")
            } else {
                Text("💪 \(d.trainingCompleted) セット")
            }
        default:
            CircularBase(progress: d.trainingProgress, done: d.trainingDone,
                         icon: "💪", numerator: d.trainingCompleted,
                         denominator: d.trainingGoal, color: .blue)
        }
    }
}

struct kfit_Watch_Complication: Widget {
    let kind = "kfitTrainingComplication"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrainingProvider()) { entry in
            TrainingEntryView(entry: entry)
        }
        .configurationDisplayName("トレーニング")
        .description("今日の完了セット数/目標を表示")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// ===========================================================================
// MARK: - 2. Mindfulness Complication
// ===========================================================================

struct MindfulnessProvider: TimelineProvider {
    func placeholder(in context: Context) -> KfitEntry {
        KfitEntry(date: Date(), data: ComplicationData(
            trainingCompleted: 0, trainingGoal: 0,
            mindfulnessCompleted: 1, mindfulnessGoal: 3,
            mealLogged: 0, mealGoal: 0))
    }
    func getSnapshot(in context: Context, completion: @escaping (KfitEntry) -> Void) {
        completion(KfitEntry(date: Date(), data: .current()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<KfitEntry>) -> Void) {
        completion(makeTimeline())
    }
}

struct MindfulnessEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: KfitEntry

    var body: some View {
        let d = entry.data
        switch family {
        case .accessoryCircular:
            CircularBase(progress: d.mindfulnessProgress, done: d.mindfulnessDone,
                         icon: "🧘", numerator: d.mindfulnessCompleted,
                         denominator: d.mindfulnessGoal,
                         color: Color(red: 0.61, green: 0.35, blue: 0.71))
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("🧘").font(.system(size: 13))
                    Text("マインドフルネス").font(.headline)
                    Spacer()
                    if d.mindfulnessDone { Text("✅").font(.system(size: 12)) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(d.mindfulnessCompleted)")
                        .font(.title3).bold()
                    if d.mindfulnessGoal > 0 {
                        Text("/ \(d.mindfulnessGoal) 分")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("分")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if d.mindfulnessGoal > 0 {
                    ProgressView(value: d.mindfulnessProgress)
                        .tint(d.mindfulnessDone ? .green : Color(red: 0.61, green: 0.35, blue: 0.71))
                }
            }
        case .accessoryInline:
            if d.mindfulnessGoal > 0 {
                Text("🧘 \(d.mindfulnessCompleted)/\(d.mindfulnessGoal) 分")
            } else {
                Text("🧘 \(d.mindfulnessCompleted) 分")
            }
        default:
            CircularBase(progress: d.mindfulnessProgress, done: d.mindfulnessDone,
                         icon: "🧘", numerator: d.mindfulnessCompleted,
                         denominator: d.mindfulnessGoal,
                         color: Color(red: 0.61, green: 0.35, blue: 0.71))
        }
    }
}

struct MindfulnessComplication: Widget {
    let kind = "kfitMindfulnessComplication"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MindfulnessProvider()) { entry in
            MindfulnessEntryView(entry: entry)
        }
        .configurationDisplayName("マインドフルネス")
        .description("今日のマインドフルネス達成回数/目標を表示")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// ===========================================================================
// MARK: - 3. Meal Complication
// ===========================================================================

struct MealProvider: TimelineProvider {
    func placeholder(in context: Context) -> KfitEntry {
        KfitEntry(date: Date(), data: ComplicationData(
            trainingCompleted: 0, trainingGoal: 0,
            mindfulnessCompleted: 0, mindfulnessGoal: 0,
            mealLogged: 400, mealGoal: 1800))
    }
    func getSnapshot(in context: Context, completion: @escaping (KfitEntry) -> Void) {
        completion(KfitEntry(date: Date(), data: .current()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<KfitEntry>) -> Void) {
        completion(makeTimeline())
    }
}

struct MealEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: KfitEntry

    var body: some View {
        let d = entry.data
        let orange = Color(red: 1.0, green: 0.59, blue: 0.0)
        switch family {
        case .accessoryCircular:
            CircularBase(progress: d.mealProgress, done: d.mealDone,
                         icon: "🍽️", numerator: d.mealLogged,
                         denominator: d.mealGoal, color: orange)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("🍽️").font(.system(size: 13))
                    Text("食事記録").font(.headline)
                    Spacer()
                    if d.mealDone { Text("✅").font(.system(size: 12)) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(d.mealLogged)")
                        .font(.title3).bold()
                    if d.mealGoal > 0 {
                        Text("/ \(d.mealGoal) kcal")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("kcal")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if d.mealGoal > 0 {
                    ProgressView(value: d.mealProgress)
                        .tint(d.mealDone ? .green : orange)
                }
            }
        case .accessoryInline:
            if d.mealGoal > 0 {
                Text("🍽️ \(d.mealLogged)/\(d.mealGoal)kcal")
            } else {
                Text("🍽️ \(d.mealLogged)kcal")
            }
        default:
            CircularBase(progress: d.mealProgress, done: d.mealDone,
                         icon: "🍽️", numerator: d.mealLogged,
                         denominator: d.mealGoal, color: orange)
        }
    }
}

struct MealComplication: Widget {
    let kind = "kfitMealComplication"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MealProvider()) { entry in
            MealEntryView(entry: entry)
        }
        .configurationDisplayName("食事記録")
        .description("今日の摂取カロリー/目標を表示")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// ===========================================================================
// MARK: - 4. Motivation Complication（やるべきことメッセージ）
// ===========================================================================

struct MotivationProvider: TimelineProvider {
    func placeholder(in context: Context) -> KfitEntry {
        KfitEntry(date: Date(), data: ComplicationData(
            trainingCompleted: 1, trainingGoal: 3,
            mindfulnessCompleted: 0, mindfulnessGoal: 2,
            mealLogged: 400, mealGoal: 1800))
    }
    func getSnapshot(in context: Context, completion: @escaping (KfitEntry) -> Void) {
        completion(KfitEntry(date: Date(), data: .current()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<KfitEntry>) -> Void) {
        completion(makeTimeline())
    }
}

struct MotivationEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: KfitEntry

    var body: some View {
        let d = entry.data
        switch family {
        case .accessoryCircular:
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 3)
                ProgressArc(progress: d.overallProgress)
                    .stroke(d.allDone ? .green : .yellow,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                VStack(spacing: 0) {
                    Text(d.allDone ? "🎉" : "⚡")
                        .font(.system(size: 11))
                    Text(d.goalsTotal > 0
                         ? "\(d.goalsCompleted)/\(d.goalsTotal)"
                         : "-")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 4) {
                if d.allDone {
                    HStack(spacing: 4) {
                        Text("🎉").font(.system(size: 13))
                        Text("今日の目標達成！").font(.headline)
                    }
                    Text("全てクリアしました").font(.caption).foregroundStyle(.secondary)
                } else if d.pendingItems.isEmpty {
                    Text("⚡ 目標を設定してください")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 4) {
                        Text("⚡").font(.system(size: 12))
                        Text("残りのタスク").font(.headline)
                    }
                    ForEach(Array(d.pendingItems.prefix(3).enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 3) {
                            Text(item.icon).font(.system(size: 10))
                            Text(item.label).font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        case .accessoryInline:
            Text(d.motivationInlineText)
        default:
            Text(d.motivationInlineText)
        }
    }
}

struct MotivationComplication: Widget {
    let kind = "kfitMotivationComplication"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MotivationProvider()) { entry in
            MotivationEntryView(entry: entry)
        }
        .configurationDisplayName("今日のタスク")
        .description("未完了の目標とやるべきことを表示")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Preview

#Preview(as: .accessoryCircular) {
    kfit_Watch_Complication()
} timeline: {
    KfitEntry(date: .now, data: ComplicationData(
        trainingCompleted: 3, trainingGoal: 5,
        mindfulnessCompleted: 1, mindfulnessGoal: 2,
        mealLogged: 800, mealGoal: 1800))
}
