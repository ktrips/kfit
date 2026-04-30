import Foundation
import UserNotifications

/// 習慣スタックの CRUD と通知スケジュール管理
///
/// 習慣（HabitStack）を UserDefaults に永続化し、
/// 各習慣に紐づく毎日の通知を UNUserNotificationCenter でスケジュールする。
@MainActor
final class HabitStackManager: ObservableObject {
    static let shared = HabitStackManager()

    @Published var habits: [HabitStack] = [] {
        didSet { save() }
    }

    private let key = "duofit.habitStacks"

    private init() {
        load()
    }

    // MARK: - CRUD

    func add(_ habit: HabitStack) {
        habits.append(habit)
        if habit.isEnabled { scheduleNotification(for: habit) }
    }

    func update(_ habit: HabitStack) {
        guard let idx = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        // 既存通知をキャンセルしてから再スケジュール
        cancelNotification(for: habits[idx])
        habits[idx] = habit
        if habit.isEnabled { scheduleNotification(for: habit) }
    }

    func remove(id: UUID) {
        if let habit = habits.first(where: { $0.id == id }) {
            cancelNotification(for: habit)
        }
        habits.removeAll { $0.id == id }
    }

    func toggle(id: UUID) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        habits[idx].isEnabled.toggle()
        if habits[idx].isEnabled {
            scheduleNotification(for: habits[idx])
        } else {
            cancelNotification(for: habits[idx])
        }
    }

    // MARK: - アプリ起動時: 全有効習慣を再スケジュール

    func rescheduleAll() {
        for habit in habits where habit.isEnabled {
            scheduleNotification(for: habit)
        }
    }

    // MARK: - 通知スケジュール

    private func scheduleNotification(for habit: HabitStack) {
        let content        = UNMutableNotificationContent()
        content.title      = "\(habit.emoji) \(habit.name)の時間！"
        content.body       = "終わったらすぐトレーニングを始めよう 💪"
        content.sound      = .default
        content.threadIdentifier = "duofit.habitstack"
        // ユーザーがタップしたらアプリを開いてトレーニング画面へ（将来拡張用）
        content.userInfo   = ["habitId": habit.id.uuidString, "action": "startWorkout"]

        var comps   = DateComponents()
        comps.hour  = habit.hour
        comps.minute = habit.minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(
            identifier: habit.notificationId,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[HabitStackManager] schedule error (\(habit.name)): \(error)")
            }
        }
    }

    private func cancelNotification(for habit: HabitStack) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [habit.notificationId])
    }

    // MARK: - UserDefaults 永続化

    private func save() {
        guard let data = try? JSONEncoder().encode(habits) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([HabitStack].self, from: data)
        else { return }
        habits = decoded
    }
}
