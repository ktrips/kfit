import Foundation
import Combine

// MARK: - kmind 専用 TimeSlotManager（スタブ）
// kfit の TimeSlotManager（Firebase 依存）とは独立した軽量実装です。
// kmind では時間帯別目標機能は使用しないため、最小限の実装に留めます。

@MainActor
final class TimeSlotManager: ObservableObject {
    static let shared = TimeSlotManager()
    private init() {}
}
