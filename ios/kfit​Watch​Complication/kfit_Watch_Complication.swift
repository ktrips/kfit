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

// MARK: - Shared Provider

private func makeTimeline() -> Timeline<KfitEntry> {
    let entry = KfitEntry(date: Date(), data: .current())
    let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
    return Timeline(entries: [entry], policy: .after(next))
}

// MARK: - Circular Progress Arc

private struct ProgressArc: Shape {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - 2
        let start: Double = -.pi / 2
        let end = start + 2 * .pi * min(1, max(0, progress))
        p.addArc(center: center, radius: radius,
                 startAngle: .radians(start), endAngle: .radians(end),
                 clockwise: false)
        return p
    }
}

// MARK: - Circular Complication View

private struct CircularComplicationView: View {
    let progress: Double
    let done: Bool
    let icon: String
    let numerator: Int
    let denominator: Int
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.25), lineWidth: 4)
            if progress > 0 {
                ProgressArc(progress: progress)
                    .stroke(done ? Color.green : color,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
            VStack(spacing: 1) {
                Text(icon)
                    .font(.system(size: 13))
                    .widgetAccentable()
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
        .containerBackground(.clear, for: .widget)
    }
}

// MARK: - Rectangular Complication View

private struct RectangularComplicationView: View {
    let icon: String
    let title: String
    let numerator: Int
    let denominator: Int
    let unit: String
    let done: Bool
    let progress: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(icon).font(.system(size: 13))
                Text(title)
                    .font(.headline)
                    .widgetAccentable()
                Spacer()
                if done { Text("✅").font(.system(size: 12)) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(numerator)")
                    .font(.title3).bold()
                    .widgetAccentable()
                if denominator > 0 {
                    Text("/ \(denominator) \(unit)")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(unit)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if denominator > 0 {
                ProgressView(value: progress)
                    .tint(done ? .green : color)
            }
        }
        .containerBackground(.clear, for: .widget)
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
            CircularComplicationView(
                progress: d.trainingProgress, done: d.trainingDone,
                icon: "💪", numerator: d.trainingCompleted,
                denominator: d.trainingGoal, color: .blue)
        case .accessoryRectangular:
            RectangularComplicationView(
                icon: "💪", title: "トレーニング",
                numerator: d.trainingCompleted,
                denominator: d.trainingGoal,
                unit: "セット",
                done: d.trainingDone,
                progress: d.trainingProgress,
                color: .blue)
        case .accessoryInline:
            if d.trainingGoal > 0 {
                Text("💪 \(d.trainingCompleted)/\(d.trainingGoal) セット")
            } else {
                Text("💪 \(d.trainingCompleted) セット")
            }
        default:
            CircularComplicationView(
                progress: d.trainingProgress, done: d.trainingDone,
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

private let mindfulColor = Color(red: 0.61, green: 0.35, blue: 0.71)

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
            CircularComplicationView(
                progress: d.mindfulnessProgress, done: d.mindfulnessDone,
                icon: "🧘", numerator: d.mindfulnessCompleted,
                denominator: d.mindfulnessGoal, color: mindfulColor)
        case .accessoryRectangular:
            RectangularComplicationView(
                icon: "🧘", title: "マインドフルネス",
                numerator: d.mindfulnessCompleted,
                denominator: d.mindfulnessGoal,
                unit: "分",
                done: d.mindfulnessDone,
                progress: d.mindfulnessProgress,
                color: mindfulColor)
        case .accessoryInline:
            if d.mindfulnessGoal > 0 {
                Text("🧘 \(d.mindfulnessCompleted)/\(d.mindfulnessGoal) 分")
            } else {
                Text("🧘 \(d.mindfulnessCompleted) 分")
            }
        default:
            CircularComplicationView(
                progress: d.mindfulnessProgress, done: d.mindfulnessDone,
                icon: "🧘", numerator: d.mindfulnessCompleted,
                denominator: d.mindfulnessGoal, color: mindfulColor)
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
        .description("今日のマインドフルネス達成分数/目標を表示")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// ===========================================================================
// MARK: - 3. Meal Complication
// ===========================================================================

private let mealOrange = Color(red: 1.0, green: 0.59, blue: 0.0)

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
        switch family {
        case .accessoryCircular:
            CircularComplicationView(
                progress: d.mealProgress, done: d.mealDone,
                icon: "🍽️", numerator: d.mealLogged,
                denominator: d.mealGoal, color: mealOrange)
        case .accessoryRectangular:
            RectangularComplicationView(
                icon: "🍽️", title: "食事記録",
                numerator: d.mealLogged,
                denominator: d.mealGoal,
                unit: "kcal",
                done: d.mealDone,
                progress: d.mealProgress,
                color: mealOrange)
        case .accessoryInline:
            if d.mealGoal > 0 {
                Text("🍽️ \(d.mealLogged)/\(d.mealGoal)kcal")
            } else {
                Text("🍽️ \(d.mealLogged)kcal")
            }
        default:
            CircularComplicationView(
                progress: d.mealProgress, done: d.mealDone,
                icon: "🍽️", numerator: d.mealLogged,
                denominator: d.mealGoal, color: mealOrange)
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
// MARK: - 4. Motivation Complication（全体進捗）
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
                    .stroke(Color.yellow.opacity(0.25), lineWidth: 4)
                if d.overallProgress > 0 {
                    ProgressArc(progress: d.overallProgress)
                        .stroke(d.allDone ? Color.green : Color.yellow,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round))
                }
                VStack(spacing: 1) {
                    Text(d.allDone ? "🎉" : "⚡")
                        .font(.system(size: 13))
                        .widgetAccentable()
                    Text(d.goalsTotal > 0
                         ? "\(d.goalsCompleted)/\(d.goalsTotal)"
                         : "-")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                }
            }
            .containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                if d.allDone {
                    HStack(spacing: 4) {
                        Text("🎉").font(.system(size: 13))
                        Text("今日の目標達成！")
                            .font(.headline)
                            .widgetAccentable()
                    }
                    Text("全てクリアしました").font(.caption).foregroundStyle(.secondary)
                } else if d.pendingItems.isEmpty {
                    Text("⚡ 目標を設定してください")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 4) {
                        Text("⚡").font(.system(size: 12))
                        Text("残りのタスク")
                            .font(.headline)
                            .widgetAccentable()
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
            .containerBackground(.clear, for: .widget)
        case .accessoryInline:
            Text(d.motivationInlineText)
        default:
            Text(d.motivationInlineText)
                .containerBackground(.clear, for: .widget)
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
        mindfulnessCompleted: 25, mindfulnessGoal: 40,
        mealLogged: 800, mealGoal: 1800))
}

#Preview(as: .accessoryRectangular) {
    kfit_Watch_Complication()
} timeline: {
    KfitEntry(date: .now, data: ComplicationData(
        trainingCompleted: 3, trainingGoal: 5,
        mindfulnessCompleted: 25, mindfulnessGoal: 40,
        mealLogged: 800, mealGoal: 1800))
}
