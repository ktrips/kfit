import UserNotifications
import UIKit

// MARK: - ユーザー設定モデル

/// 1件のリマインダー設定（UserDefaults に JSON で保存）
struct ReminderConfig: Codable {
    var enabled: Bool
    var hour: Int
    var minute: Int
}

/// 日次リマインダー設定をまとめて保持
struct NotificationPrefs: Codable {
    var amReminder:  ReminderConfig
    var amFollowup:  ReminderConfig
    var noonReminder: ReminderConfig
    var noonFollowup: ReminderConfig
    var afternoonReminder: ReminderConfig
    var afternoonFollowup: ReminderConfig
    var pmReminder:  ReminderConfig
    var pmFollowup:  ReminderConfig
    var streakAlert: ReminderConfig
    var weightMorning: ReminderConfig  // 体重測定（朝）
    var weightEvening: ReminderConfig  // 体重測定（夕）

    static let defaultPrefs = NotificationPrefs(
        amReminder:  ReminderConfig(enabled: true, hour: 6,  minute: 0),
        amFollowup:  ReminderConfig(enabled: true, hour: 9,  minute: 0),
        noonReminder: ReminderConfig(enabled: true, hour: 10, minute: 0),
        noonFollowup: ReminderConfig(enabled: true, hour: 13, minute: 0),
        afternoonReminder: ReminderConfig(enabled: true, hour: 14, minute: 0),
        afternoonFollowup: ReminderConfig(enabled: true, hour: 17, minute: 0),
        pmReminder:  ReminderConfig(enabled: true, hour: 18, minute: 0),
        pmFollowup:  ReminderConfig(enabled: true, hour: 21, minute: 0),
        streakAlert: ReminderConfig(enabled: true, hour: 22, minute: 0),
        weightMorning: ReminderConfig(enabled: true, hour: 7, minute: 0),
        weightEvening: ReminderConfig(enabled: true, hour: 21, minute: 0)
    )

    // 動的アクセス用
    subscript(id: String) -> ReminderConfig {
        get {
            switch id {
            case NotificationManager.ID.amReminder:  return amReminder
            case NotificationManager.ID.amFollowup:  return amFollowup
            case NotificationManager.ID.noonReminder: return noonReminder
            case NotificationManager.ID.noonFollowup: return noonFollowup
            case NotificationManager.ID.afternoonReminder: return afternoonReminder
            case NotificationManager.ID.afternoonFollowup: return afternoonFollowup
            case NotificationManager.ID.pmReminder:  return pmReminder
            case NotificationManager.ID.pmFollowup:  return pmFollowup
            case NotificationManager.ID.streakAlert: return streakAlert
            case NotificationManager.ID.weightMorning: return weightMorning
            case NotificationManager.ID.weightEvening: return weightEvening
            default: return ReminderConfig(enabled: false, hour: 0, minute: 0)
            }
        }
        set {
            switch id {
            case NotificationManager.ID.amReminder:  amReminder  = newValue
            case NotificationManager.ID.amFollowup:  amFollowup  = newValue
            case NotificationManager.ID.noonReminder: noonReminder = newValue
            case NotificationManager.ID.noonFollowup: noonFollowup = newValue
            case NotificationManager.ID.afternoonReminder: afternoonReminder = newValue
            case NotificationManager.ID.afternoonFollowup: afternoonFollowup = newValue
            case NotificationManager.ID.pmReminder:  pmReminder  = newValue
            case NotificationManager.ID.pmFollowup:  pmFollowup  = newValue
            case NotificationManager.ID.streakAlert: streakAlert = newValue
            case NotificationManager.ID.weightMorning: weightMorning = newValue
            case NotificationManager.ID.weightEvening: weightEvening = newValue
            default: break
            }
        }
    }
}

// MARK: - NotificationManager

/// DuoFit の通知スケジュール管理
///
/// 毎日の通知は NotificationPrefs (UserDefaults) から時刻・有効状態を読み込む。
/// ユーザーが設定画面でカスタマイズした内容がそのまま反映される。
@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    private init() {}

    /// SettingsView から @StateObject として参照できるよう @Published で公開
    @Published var prefs: NotificationPrefs = NotificationManager.loadPrefs()

    // MARK: - 通知 ID 定数

    enum ID {
        static let amReminder  = "duofit.am.reminder"
        static let amFollowup  = "duofit.am.followup"
        static let noonReminder = "duofit.noon.reminder"
        static let noonFollowup = "duofit.noon.followup"
        static let afternoonReminder = "duofit.afternoon.reminder"
        static let afternoonFollowup = "duofit.afternoon.followup"
        static let pmReminder  = "duofit.pm.reminder"
        static let pmFollowup  = "duofit.pm.followup"
        static let streakAlert = "duofit.streak.alert"
        static let weightMorning = "duofit.weight.morning"
        static let weightEvening = "duofit.weight.evening"
        static var all: [String] {
            [amReminder, amFollowup, noonReminder, noonFollowup, afternoonReminder, afternoonFollowup, pmReminder, pmFollowup, streakAlert, weightMorning, weightEvening]
        }
        static var workoutReminders: [String] {
            [amReminder, amFollowup, noonReminder, noonFollowup, afternoonReminder, afternoonFollowup, pmReminder, pmFollowup, streakAlert]
        }
    }

    // MARK: - 通知カテゴリ定数
    enum Category {
        static let workoutReminder = "WORKOUT_REMINDER"
        static let weightReminder = "WEIGHT_REMINDER"
    }

    // MARK: - 通知アクション定数
    enum Action {
        static let startWorkout = "START_WORKOUT"
        static let recordWeight = "RECORD_WEIGHT"
    }

    // MARK: - 通知メッセージ定数

    static let messages: [String: (title: String, body: String)] = [
        ID.amReminder:  ("💪 おはよう！朝トレの時間",       "今日も一緒に始めよう。ストリーク継続中！"),
        ID.amFollowup:  ("🔥 朝トレまだ間に合う！",         "朝のトレーニングを完了してストリークを守ろう💪"),
        ID.noonReminder: ("☀️ 昼のトレーニング時間",        "お昼の時間帯も記録しよう！"),
        ID.noonFollowup: ("💡 昼トレを完了しよう",          "昼のトレーニングで目標達成！"),
        ID.afternoonReminder: ("🌤️ 午後のトレーニング時間", "午後の時間帯も頑張ろう！"),
        ID.afternoonFollowup: ("⚡ 午後トレまだ間に合う！",  "午後のトレーニングを完了しよう💪"),
        ID.pmReminder:  ("🌆 夜のトレーニング時間",         "今日の最後の時間帯を記録しよう！"),
        ID.pmFollowup:  ("🌙 夜トレまだ間に合う！",         "夜のトレーニングでストリークを守ろう🔥"),
        ID.streakAlert: ("🚨 ストリークが途絶えそう！",     "今日はまだトレーニングしていません。連続記録が途絶えちゃうよ！"),
        ID.weightMorning: ("⚖️ 朝の体重測定",             "起床後の体重を記録しよう！習慣化が大切💪"),
        ID.weightEvening: ("⚖️ 夜の体重測定",             "就寝前の体重を記録しよう！1日2回で変化を追跡📊"),
    ]

    // MARK: - UserDefaults 永続化

    private static let prefsKey = "duofit.notificationPrefs"

    static func loadPrefs() -> NotificationPrefs {
        guard let data = UserDefaults.standard.data(forKey: prefsKey),
              let decoded = try? JSONDecoder().decode(NotificationPrefs.self, from: data)
        else { return .defaultPrefs }
        return decoded
    }

    func savePrefs() {
        guard let data = try? JSONEncoder().encode(prefs) else { return }
        UserDefaults.standard.set(data, forKey: Self.prefsKey)
    }

    // MARK: - 権限リクエスト

    @discardableResult
    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])

            // 通知カテゴリとアクションを設定
            setupNotificationCategories()

            return granted
        } catch {
            print("[NotificationManager] permission error: \(error)")
            return false
        }
    }

    // MARK: - 通知カテゴリ設定

    private func setupNotificationCategories() {
        // ワークアウトリマインダー用アクション
        let startWorkoutAction = UNNotificationAction(
            identifier: Action.startWorkout,
            title: "今すぐ始める",
            options: [.foreground]
        )

        let workoutCategory = UNNotificationCategory(
            identifier: Category.workoutReminder,
            actions: [startWorkoutAction],
            intentIdentifiers: [],
            options: []
        )

        // 体重測定リマインダー用アクション
        let recordWeightAction = UNNotificationAction(
            identifier: Action.recordWeight,
            title: "記録する",
            options: [.foreground]
        )

        let weightCategory = UNNotificationCategory(
            identifier: Category.weightReminder,
            actions: [recordWeightAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([workoutCategory, weightCategory])
        print("[NotificationManager] 通知カテゴリを設定しました")
    }

    // MARK: - 全通知をスケジュール（prefs に従う）

    func scheduleAllDaily() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ID.all)

        for id in ID.all {
            let cfg = prefs[id]
            guard cfg.enabled else { continue }
            let msg = Self.messages[id] ?? (title: id, body: "")
            add(id: id, hour: cfg.hour, minute: cfg.minute,
                title: msg.title, body: msg.body)
        }
        print("[NotificationManager] 通知をスケジュール（prefs に基づく）")
    }

    // MARK: - トレーニング記録後に呼ぶ

    func handleWorkoutRecorded() {
        let hour = Calendar.current.component(.hour, from: Date())
        var toRefresh: [String] = [ID.streakAlert]
        if hour < 8  { toRefresh.append(ID.amFollowup) }
        if hour >= 12 && hour < 20 { toRefresh.append(ID.pmFollowup) }
        refreshNotifications(ids: toRefresh)
    }

    // MARK: - 体重測定記録後に呼ぶ

    func handleWeightRecorded() {
        Task {
            let count = await HealthKitManager.shared.fetchTodayBodyMassMeasurements()
            let hour = Calendar.current.component(.hour, from: Date())
            var toRefresh: [String] = []

            // 朝の測定が完了したら朝のリマインダーをキャンセル
            if hour < 12 && count >= 1 {
                toRefresh.append(ID.weightMorning)
            }
            // 2回目の測定が完了したら夜のリマインダーもキャンセル
            if count >= 2 {
                toRefresh.append(ID.weightEvening)
            }

            if !toRefresh.isEmpty {
                refreshNotifications(ids: toRefresh)
            }
        }
    }

    // MARK: - 全削除（ログアウト時など）

    func removeAll() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ID.all)
    }

    // MARK: - デバッグ

    func debugPrintPending() async {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        print("[NotificationManager] Pending: \(requests.map { $0.identifier })")
    }

    // MARK: - Private helpers

    private func refreshNotifications(ids: [String]) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ids)
        for id in ids {
            let cfg = prefs[id]
            guard cfg.enabled else { continue }
            let msg = Self.messages[id] ?? (title: id, body: "")
            add(id: id, hour: cfg.hour, minute: cfg.minute,
                title: msg.title, body: msg.body)
        }
    }

    private func add(id: String, hour: Int, minute: Int, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        content.threadIdentifier = "duofit.training"

        // カテゴリを設定（ワークアウトリマインダーか体重測定か）
        if ID.workoutReminders.contains(id) {
            content.categoryIdentifier = Category.workoutReminder
            content.userInfo = ["action": "startWorkout"]
        } else if id == ID.weightMorning || id == ID.weightEvening {
            content.categoryIdentifier = Category.weightReminder
            content.userInfo = ["action": "recordWeight"]
        }

        var comps    = DateComponents()
        comps.hour   = hour
        comps.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("[NotificationManager] add error (\(id)): \(error)") }
        }
    }
}
