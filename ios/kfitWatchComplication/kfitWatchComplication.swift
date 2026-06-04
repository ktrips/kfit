import WidgetKit
import SwiftUI

// MARK: - Entry

struct TrainingEntry: TimelineEntry {
    let date: Date
    let completed: Int
    let goal: Int

    var progress: Double {
        guard goal > 0 else { return 0 }
        return min(Double(completed) / Double(goal), 1.0)
    }

    static func current() -> TrainingEntry {
        let ud = UserDefaults(suiteName: "group.com.kfit.app")
        let completed = ud?.integer(forKey: "watch_totalTraining") ?? 0
        let goal = ud?.integer(forKey: "watch_totalTrainingGoal") ?? 0
        return TrainingEntry(date: Date(), completed: completed, goal: goal)
    }
}

// MARK: - Provider

struct TrainingComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> TrainingEntry {
        TrainingEntry(date: Date(), completed: 2, goal: 5)
    }

    func getSnapshot(in context: Context, completion: @escaping (TrainingEntry) -> Void) {
        completion(.current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrainingEntry>) -> Void) {
        let entry = TrainingEntry.current()
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Views

struct TrainingComplicationCircularView: View {
    let entry: TrainingEntry

    var body: some View {
        ZStack {
            if entry.goal > 0 {
                ProgressView(value: entry.progress)
                    .progressViewStyle(.circular)
                    .tint(.green)
            }
            VStack(spacing: 0) {
                Text("💪")
                    .font(.system(size: 11))
                Text(entry.goal > 0 ? "\(entry.completed)/\(entry.goal)" : "\(entry.completed)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
    }
}

struct TrainingComplicationRectangularView: View {
    let entry: TrainingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("💪")
                Text("トレーニング")
                    .font(.headline)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(entry.completed)")
                    .font(.title3).bold()
                if entry.goal > 0 {
                    Text("/ \(entry.goal) セット")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("セット完了")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if entry.goal > 0 {
                ProgressView(value: entry.progress)
                    .tint(.green)
            }
        }
    }
}

struct TrainingComplicationView: View {
    @Environment(\.widgetFamily) var family
    let entry: TrainingEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            TrainingComplicationCircularView(entry: entry)
        case .accessoryRectangular:
            TrainingComplicationRectangularView(entry: entry)
        case .accessoryInline:
            Text("💪 \(entry.completed)/\(entry.goal)")
        default:
            TrainingComplicationCircularView(entry: entry)
        }
    }
}

// MARK: - Widget

struct kfitTrainingComplication: Widget {
    let kind = "kfitTrainingComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrainingComplicationProvider()) { entry in
            TrainingComplicationView(entry: entry)
        }
        .configurationDisplayName("トレーニング")
        .description("今日のトレーニング完了セット数/目標を表示します")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Bundle

@main
struct kfitWatchComplicationBundle: WidgetBundle {
    var body: some Widget {
        kfitTrainingComplication()
    }
}
