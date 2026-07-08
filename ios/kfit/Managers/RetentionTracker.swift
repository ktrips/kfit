import Foundation
import FirebaseAuth
import FirebaseFirestore

/// 継続コホート計測（7/30/90 日継続率の元データ収集）
///
/// 「その日に何かしらの活動を記録したか」を users/{uid}/retention/summary に
/// 1 日 1 回だけ書き込む。指標の定義（3 日猶予の連続判定など）はサーバー側
/// （Cloud Function: computeRetentionStats）に置き、クライアントは事実
/// （活動した日付）だけを送る。定義変更にアプリ更新が不要になる。
///
/// 書き込みスキーマ:
///   users/{uid}/retention/summary {
///     firstActiveDay: "yyyy-MM-dd",   // 初回活動日（コホートキー）
///     lastActiveDay:  "yyyy-MM-dd",
///     totalActiveDays: Int,           // 累計活動日数
///     days: { "yyyy-MM-dd": true },   // 活動日マップ（1年で約365キー）
///     maxStreak: Int,                 // 既存ストリークの最高値（参考値）
///     updatedAt: Timestamp
///   }
@MainActor
final class RetentionTracker {
    static let shared = RetentionTracker()
    private init() {}

    private let lastMarkedKey = "retention.lastMarkedDay"
    private let activeDayCountKey = "retention.activeDayCount"
    private let firstSetSecondsKey = "retention.firstSetSecondsSent"
    private var observer: NSObjectProtocol?

    /// この端末で記録した活動日数（90秒モードの卒業判定などに使用）
    var localActiveDayCount: Int {
        UserDefaults.standard.integer(forKey: activeDayCountKey)
    }

    /// 初回起動から最初の1セット完了までの秒数を一度だけ記録する（90秒モードの検証指標）
    func recordFirstSetLatency(installedAt: Date) {
        guard !UserDefaults.standard.bool(forKey: firstSetSecondsKey) else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        UserDefaults.standard.set(true, forKey: firstSetSecondsKey)
        let seconds = Int(Date().timeIntervalSince(installedAt))
        let ref = Firestore.firestore()
            .collection("users").document(uid)
            .collection("retention").document("summary")
        Task {
            try? await ref.setData(["firstSetSeconds": seconds], merge: true)
            dlog("[RetentionTracker] 📏 firstSetSeconds = \(seconds)s")
        }
    }

    /// TimeSlotManager の進捗保存（運動・食事・水分・マインドフルネス等の
    /// あらゆる記録経路の合流点）を監視して活動日をマークする。
    /// TimeSlotManager は kedu と共有ソースのため直接呼ばず、通知経由で疎結合にする。
    func startObserving() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .timeSlotProgressDidSave, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in RetentionTracker.shared.markActiveToday() }
        }
    }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// 今日を「活動あり」としてマークする。1 日 1 回だけ Firestore に書く。
    /// 運動・食事・水分・マインドフルネス等、どの記録経路から呼んでもよい。
    func markActiveToday() {
        let today = Self.dayFmt.string(from: Date())
        guard UserDefaults.standard.string(forKey: lastMarkedKey) != today else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        UserDefaults.standard.set(today, forKey: lastMarkedKey)
        UserDefaults.standard.set(localActiveDayCount + 1, forKey: activeDayCountKey)

        let streak = AuthenticationManager.shared.userProfile?.streak ?? 0
        let ref = Firestore.firestore()
            .collection("users").document(uid)
            .collection("retention").document("summary")

        Task {
            // firstActiveDay は初回のみ設定（既存があれば維持）
            let snap = try? await ref.getDocument()
            let firstActiveDay = (snap?.data()?["firstActiveDay"] as? String) ?? today
            let prevMaxStreak = (snap?.data()?["maxStreak"] as? Int) ?? 0

            let data: [String: Any] = [
                "firstActiveDay": firstActiveDay,
                "lastActiveDay": today,
                "totalActiveDays": FieldValue.increment(Int64(1)),
                "days.\(today)": true,
                "maxStreak": max(prevMaxStreak, streak),
                "updatedAt": FieldValue.serverTimestamp()
            ]
            do {
                try await ref.setData(["firstActiveDay": firstActiveDay], merge: true)
                try await ref.updateData(data)
                dlog("[RetentionTracker] ✅ marked active: \(today)")
            } catch {
                // 失敗時は次回の記録で再試行できるようフラグとカウントを戻す
                UserDefaults.standard.removeObject(forKey: lastMarkedKey)
                UserDefaults.standard.set(max(0, self.localActiveDayCount - 1), forKey: self.activeDayCountKey)
                dlog("[RetentionTracker] ❌ mark failed: \(error)")
            }
        }
    }
}
