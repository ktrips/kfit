import UserNotifications
import UIKit

// MARK: - ユーザー設定モデル

/// 1件のリマインダー設定（UserDefaults に JSON で保存）
struct ReminderConfig: Codable {
    var enabled: Bool
    var hour: Int
    var minute: Int
}

/// 5本の日次リマインダー設定をまとめて保持
struct NotificationPrefs: Codable {
    var amReminder:  ReminderConfig
    var amFollowup:  ReminderConfig
    var pmReminder:  ReminderConfig
    var pmFollowup:  ReminderConfig
    var streakAlert: ReminderConfig

    static let defaultPrefs = NotificationPrefs(
        amReminder:  ReminderConfig(enabled: true, hour: 6,  minute: 0),
        amFollowup:  ReminderConfig(enabled: true, hour: 8,  minute: 0),
        pmReminder:  ReminderConfig(enabled: true, hour: 18, minute: 0),
        pmFollowup:  ReminderConfig(enabled: true, hour: 20, minute: 0),
        streakAlert: ReminderConfig(enabled: true, hour: 22, minute: 0)
    )

    // 動的アクセス用
    subscript(id: String) -> ReminderConfig {
        get {
            switch id {
            case NotificationManager.ID.amReminder:  return amReminder
            case NotificationManager.ID.amFollowup:  return amFollowup
            case NotificationManager.ID.pmReminder:  return pmReminder
            case NotificationManager.ID.pmFollowup:  return pmFollowup
            case NotificationManager.ID.streakAlert: return streakAlert
            default: return ReminderConfig(enabled: false, hour: 0, minute: 0)
            }
        }
        set {
            switch id {
            case NotificationManager.ID.amReminder:  amReminder  = newValue
            case NotificationManager.ID.amFollowup:  amFollowup  = newValue
            case NotificationManager.ID.pmReminder:  pmReminder  = newValue
            case NotificationManager.ID.pmFollowup:  pmFollowup  = newValue
            case NotificationManager.ID.streakAlert: streakAlert = newValue
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
        static let pmReminder  = "duofit.pm.reminder"
        static let pmFollowup  = "duofit.pm.followup"
        static let streakAlert = "duofit.streak.alert"
        static var all: [String] {
            [amReminder, amFollowup, pmReminder, pmFollowup, streakAlert]
        }
    }

    // MARK: - 通知メッセージ定数

    static let messages: [String: (title: String, body: String)] = [
        ID.amReminder:  ("💪 おはよう！朝トレの時間",       "今日も一緒に始めよう。ストリーク継続中！"),
        ID.amFollowup:  ("🔥 まだ間に合う！朝トレしよう",   "数分でOK。ストリークを守ろう💪"),
        ID.pmReminder:  ("🌆 夕方トレーニングの時間",       "今日の2セット目を記録しよう！"),
        ID.pmFollowup:  ("⚡ 夜トレまだ間に合う！",         "22時までに記録してストリークを守ろう🔥"),
        ID.streakAlert: ("🚨 ストリークが途絶えそう！",     "今日はまだトレーニングしていません。今すぐ記録しよう！"),
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
