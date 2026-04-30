import UserNotifications
import UIKit

/// DuoFit の通知スケジュール管理
///
/// 毎日の通知:
///   06:00  朝のトレーニングリマインダー
///   08:00  朝のフォローアップ（06時以降に未記録なら届く）
///   18:00  夕方のトレーニングリマインダー
///   20:00  夕方のフォローアップ（18時以降に未記録なら届く）
///   22:00  ストリーク警告（その日一度も記録なし）
///
/// トレーニングを記録した時点で不要な通知をキャンセルし、
/// 同 ID で即再追加することで翌日から継続する。
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    // MARK: - 通知 ID 定数
    enum ID {
        static let amReminder  = "duofit.am.reminder"   // 06:00
        static let amFollowup  = "duofit.am.followup"   // 08:00
        static let pmReminder  = "duofit.pm.reminder"   // 18:00
        static let pmFollowup  = "duofit.pm.followup"   // 20:00
        static let streakAlert = "duofit.streak.alert"  // 22:00
        static var all: [String] {
            [amReminder, amFollowup, pmReminder, pmFollowup, streakAlert]
        }
    }

    // MARK: - 権限リクエスト
    @discardableResult
    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            return granted
        } catch {
            print("[NotificationManager] permission error: \(error)")
            return false
        }
    }

    // MARK: - 毎日の通知を全スケジュール
    /// アプリ起動時・ログイン後に呼ぶ。すでに登録済みでも安全に再スケジュール可能。
    func scheduleAllDaily() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ID.all)

        add(id: ID.amReminder, hour: 6, minute: 0,
            title: "💪 おはよう！朝トレの時間",
            body: "今日も一緒に始めよう。ストリーク継続中！")

        add(id: ID.amFollowup, hour: 8, minute: 0,
            title: "🔥 まだ間に合う！朝トレしよう",
            body: "数分でOK。ストリークを守ろう💪")

        add(id: ID.pmReminder, hour: 18, minute: 0,
            title: "🌆 夕方トレーニングの時間",
            body: "今日の2セット目を記録しよう！")

        add(id: ID.pmFollowup, hour: 20, minute: 0,
            title: "⚡ 夜トレまだ間に合う！",
            body: "22時までに記録してストリークを守ろう🔥")

        add(id: ID.streakAlert, hour: 22, minute: 0,
            title: "🚨 ストリークが途絶えそう！",
            body: "今日はまだトレーニングしていません。今すぐ記録しよう！")

        print("[NotificationManager] 5本の日次通知をスケジュールしました")
    }

    // MARK: - トレーニング記録後に呼ぶ
    /// 記録した時刻に応じて不要な通知をキャンセルし、翌日から再開させる。
    func handleWorkoutRecorded() {
        let hour = Calendar.current.component(.hour, from: Date())
        var toRefresh: [String] = []

        // ストリーク警告: トレーニング記録があった日は常にキャンセル
        toRefresh.append(ID.streakAlert)

        // 朝のフォローアップ: 8時前に記録 → 今日の 8時通知は不要
        if hour < 8 {
            toRefresh.append(ID.amFollowup)
        }

        // 夕方のフォローアップ: 20時前かつ PM 記録 → 今日の 20時通知は不要
        if hour >= 12 && hour < 20 {
            toRefresh.append(ID.pmFollowup)
        }

        // キャンセルして即再追加（repeats:true なので次回は翌日同時刻に発火）
        refreshNotifications(ids: toRefresh)
    }

    // MARK: - 通知を全削除（ログアウト時など）
    func removeAll() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ID.all)
    }

    // MARK: - デバッグ用: 現在の Pending 通知を出力
    func debugPrintPending() async {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        print("[NotificationManager] Pending: \(requests.map { $0.identifier })")
    }

    // MARK: - Private helpers

    /// キャンセルして同 ID で再スケジュール（今日をスキップし翌日から継続）
    private func refreshNotifications(ids: [String]) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ids)

        // 再スケジュール: ID に応じた hour/minute を復元
        for id in ids {
            switch id {
            case ID.amReminder:  add(id: id, hour: 6,  minute: 0,
                                     title: "💪 おはよう！朝トレの時間",
                                     body: "今日も一緒に始めよう。ストリーク継続中！")
            case ID.amFollowup:  add(id: id, hour: 8,  minute: 0,
                                     title: "🔥 まだ間に合う！朝トレしよう",
                                     body: "数分でOK。ストリークを守ろう💪")
            case ID.pmReminder:  add(id: id, hour: 18, minute: 0,
                                     title: "🌆 夕方トレーニングの時間",
                                     body: "今日の2セット目を記録しよう！")
            case ID.pmFollowup:  add(id: id, hour: 20, minute: 0,
                                     title: "⚡ 夜トレまだ間に合う！",
                                     body: "22時までに記録してストリークを守ろう🔥")
            case ID.streakAlert: add(id: id, hour: 22, minute: 0,
                                     title: "🚨 ストリークが途絶えそう！",
                                     body: "今日はまだトレーニングしていません。今すぐ記録しよう！")
            default: break
            }
        }
    }

    /// 毎日指定時刻に繰り返す通知を登録
    private func add(id: String, hour: Int, minute: Int, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        // Apple Watch 用: スレッドID でグループ化
        content.threadIdentifier = "duofit.training"
        // バッジ（オプション）
        // content.badge = 1

        var comps        = DateComponents()
        comps.hour       = hour
        comps.minute     = minute

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: comps, repeats: true
        )
        let request = UNNotificationRequest(
            identifier: id, content: content, trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("[NotificationManager] add error (\(id)): \(error)") }
        }
    }
}
