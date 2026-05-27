import UserNotifications
import UIKit

// MARK: - ユーザー設定モデル

/// 1件のリマインダー設定（UserDefaults に JSON で保存）
struct ReminderConfig: Codable {
    var enabled: Bool
    var hour: Int
    var minute: Int
}

/// 通知設定をまとめて保持（時間帯別リマインダー + ストリークアラート）
struct NotificationPrefs: Codable {
    var amReminder:        ReminderConfig
    var noonReminder:      ReminderConfig
    var afternoonReminder: ReminderConfig
    var pmReminder:        ReminderConfig
    var streakAlert:       ReminderConfig

    static let defaultPrefs = NotificationPrefs(
        amReminder:        ReminderConfig(enabled: true, hour: 6,  minute: 0),
        noonReminder:      ReminderConfig(enabled: true, hour: 10, minute: 0),
        afternoonReminder: ReminderConfig(enabled: true, hour: 14, minute: 0),
        pmReminder:        ReminderConfig(enabled: true, hour: 18, minute: 0),
        streakAlert:       ReminderConfig(enabled: true, hour: 22, minute: 0)
    )

    subscript(id: String) -> ReminderConfig {
        get {
            switch id {
            case NotificationManager.ID.amReminder:        return amReminder
            case NotificationManager.ID.noonReminder:      return noonReminder
            case NotificationManager.ID.afternoonReminder: return afternoonReminder
            case NotificationManager.ID.pmReminder:        return pmReminder
            case NotificationManager.ID.streakAlert:       return streakAlert
            default: return ReminderConfig(enabled: false, hour: 0, minute: 0)
            }
        }
        set {
            switch id {
            case NotificationManager.ID.amReminder:        amReminder        = newValue
            case NotificationManager.ID.noonReminder:      noonReminder      = newValue
            case NotificationManager.ID.afternoonReminder: afternoonReminder = newValue
            case NotificationManager.ID.pmReminder:        pmReminder        = newValue
            case NotificationManager.ID.streakAlert:       streakAlert       = newValue
            default: break
            }
        }
    }
}

// MARK: - NotificationManager

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    private init() {}

    @Published var prefs: NotificationPrefs = NotificationManager.loadPrefs()

    // MARK: - 通知 ID 定数

    enum ID {
        static let amReminder        = "fitingo.am.reminder"
        static let noonReminder      = "fitingo.noon.reminder"
        static let afternoonReminder = "fitingo.afternoon.reminder"
        static let pmReminder        = "fitingo.pm.reminder"
        static let streakAlert       = "fitingo.streak.alert"
        static var all: [String] {
            [amReminder, noonReminder, afternoonReminder, pmReminder, streakAlert]
        }
    }

    // MARK: - 通知メッセージ定数

    static let messages: [String: (title: String, body: String)] = [
        ID.amReminder:        ("🌅 朝の時間帯",           "朝のルーティンを始めよう！"),
        ID.noonReminder:      ("☀️ 昼の時間帯",           "お昼のルーティンを記録しよう！"),
        ID.afternoonReminder: ("🌤️ 午後の時間帯",         "午後のルーティンも頑張ろう！"),
        ID.pmReminder:        ("🌆 夜の時間帯",           "今日の最後のルーティンを記録しよう！"),
        ID.streakAlert:       ("🚨 ストリークが途絶えそう！", "今日はまだ記録していません。連続記録が途絶えちゃうよ！"),
    ]

    // MARK: - UserDefaults 永続化

    private static let prefsKey = "fitingo.notificationPrefs"

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
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            print("[NotificationManager] permission error: \(error)")
            return false
        }
    }

    // MARK: - 全通知をスケジュール（prefs に従う）

    func scheduleAllDaily() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ID.all)

        for id in ID.all {
            let cfg = prefs[id]
            guard cfg.enabled else { continue }
            let msg = Self.messages[id] ?? (title: id, body: "")
            add(id: id, hour: cfg.hour, minute: cfg.minute, title: msg.title, body: msg.body)
        }
        print("[NotificationManager] 通知スケジュール完了")
    }

    // MARK: - 1件だけ即時スケジュール／キャンセル（設定画面でON/OFFしたとき）

    func applyOne(id: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [id])
        let cfg = prefs[id]
        guard cfg.enabled else { return }
        let msg = Self.messages[id] ?? (title: id, body: "")
        add(id: id, hour: cfg.hour, minute: cfg.minute, title: msg.title, body: msg.body)
    }

    // MARK: - トレーニング記録後に呼ぶ（ストリークアラートをリフレッシュ）

    func handleWorkoutRecorded() {
        applyOne(id: ID.streakAlert)
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

    private func add(id: String, hour: Int, minute: Int, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        content.threadIdentifier = "fitingo.training"

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
