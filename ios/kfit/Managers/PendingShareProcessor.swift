import Foundation
import UIKit
import Combine

// MARK: - App 本体側: 起動時に共有コンテナを処理してフィードに投稿する

private let appGroupID       = "group.com.yourteam.kfit"
private let pendingSharesKey = "pendingDuolingoShares"

// MARK: - カテゴリ判定

private struct ShareCategory {
    let activityName: String
    let activityEmoji: String
    let isDuolingo: Bool
}

/// コメントと共有元アプリ名からカテゴリを判定する。
/// マッチしない場合は "その他" を返す。
private func detectCategory(comment: String, sourceApp: String) -> ShareCategory {
    let text = (comment + " " + sourceApp).lowercased()

    // ── Duolingo ─────────────────────────────────────────────────────────
    let duoKeywords = ["duo", "duolingo", "🦉", "daily", "デイリー",
                       "challenge", "チャレンジ", "ストリーク", "streak",
                       "xp", "リーグ", "league", "ハート", "レッスン"]
    if duoKeywords.contains(where: { text.contains($0) })
        || sourceApp.lowercased().contains("duolingo") {
        return ShareCategory(activityName: "Duolingo", activityEmoji: "🦉", isDuolingo: true)
    }

    // ── 日記 ──────────────────────────────────────────────────────────────
    let diaryKeywords = ["日記", "diary", "フォト日記", "journal", "メモ", "今日の出来事"]
    if diaryKeywords.contains(where: { text.contains($0) }) {
        return ShareCategory(activityName: "日記", activityEmoji: "📔", isDuolingo: false)
    }

    // ── 読書 ──────────────────────────────────────────────────────────────
    let readingKeywords = ["読書", "読んだ", "reading", "book", "本", "小説", "マンガ", "漫画",
                           "kindl", "電子書籍"]
    if readingKeywords.contains(where: { text.contains($0) }) {
        return ShareCategory(activityName: "読書", activityEmoji: "📖", isDuolingo: false)
    }

    // ── 勉強 / 語学 ────────────────────────────────────────────────────────
    let studyKeywords = ["勉強", "study", "学習", "英語", "語学", "toeic", "toefl",
                         "ielts", "eiken", "英検", "文法", "単語", "vocab",
                         "grammar", "spanish", "french", "german", "chinese",
                         "korean", "スペイン語", "フランス語", "ドイツ語", "中国語", "韓国語"]
    if studyKeywords.contains(where: { text.contains($0) }) {
        return ShareCategory(activityName: "勉強", activityEmoji: "✏️", isDuolingo: false)
    }

    // ── 瞑想 ──────────────────────────────────────────────────────────────
    let meditationKeywords = ["瞑想", "meditation", "mindfulness", "マインドフルネス",
                               "呼吸", "breath", "calm", "headspace"]
    if meditationKeywords.contains(where: { text.contains($0) }) {
        return ShareCategory(activityName: "瞑想", activityEmoji: "🧘", isDuolingo: false)
    }

    // ── ストレッチ ──────────────────────────────────────────────────────────
    let stretchKeywords = ["ストレッチ", "stretch", "ヨガ", "yoga", "柔軟"]
    if stretchKeywords.contains(where: { text.contains($0) }) {
        return ShareCategory(activityName: "ストレッチ", activityEmoji: "🤸", isDuolingo: false)
    }

    // ── 早起き / 朝活 ────────────────────────────────────────────────────────
    let morningKeywords = ["早起き", "朝活", "morning", "朝ラン", "朝散歩"]
    if morningKeywords.contains(where: { text.contains($0) }) {
        return ShareCategory(activityName: "早起き", activityEmoji: "🌅", isDuolingo: false)
    }

    // ── 筋トレ / 運動 ────────────────────────────────────────────────────────
    let workoutKeywords = ["筋トレ", "workout", "gym", "ジム", "トレーニング",
                           "training", "exercise", "運動", "ランニング", "running",
                           "walk", "散歩", "push-up", "squat", "スクワット"]
    if workoutKeywords.contains(where: { text.contains($0) }) {
        return ShareCategory(activityName: "筋トレ", activityEmoji: "💪", isDuolingo: false)
    }

    // ── コーヒー ────────────────────────────────────────────────────────────
    let coffeeKeywords = ["コーヒー", "coffee", "cafe", "カフェ", "brew", "drip"]
    if coffeeKeywords.contains(where: { text.contains($0) }) {
        return ShareCategory(activityName: "コーヒーを淹れる", activityEmoji: "☕", isDuolingo: false)
    }

    // ── マッチなし → その他 ─────────────────────────────────────────────────
    return ShareCategory(activityName: "その他", activityEmoji: "✨", isDuolingo: false)
}

// MARK: - PendingShareProcessor

@MainActor
class PendingShareProcessor {

    static let shared = PendingShareProcessor()

    /// kfitApp.onAppear や SceneDelegate から呼ぶ
    func processPendingShares(userID: String, userName: String) async {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }

        let pending = defaults.array(forKey: pendingSharesKey) as? [[String: Any]] ?? []
        guard !pending.isEmpty else { return }

        defaults.removeObject(forKey: pendingSharesKey)
        defaults.synchronize()

        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return }

        for item in pending {
            guard let filename = item["filename"] as? String else { continue }

            let fileURL = containerURL.appendingPathComponent(filename)
            guard let imageData = try? Data(contentsOf: fileURL),
                  let image = UIImage(data: imageData) else { continue }

            // コメントと元アプリ名を取得
            let savedComment = item["comment"] as? String ?? ""
            let sourceApp    = item["sourceApp"] as? String ?? ""

            // カテゴリ判定
            let cat = detectCategory(comment: savedComment, sourceApp: sourceApp)

            // 表示コメント：ユーザー入力があればそのまま、なければデフォルト文言
            let displayComment: String
            if savedComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                displayComment = "\(cat.activityEmoji) \(cat.activityName) 達成！🎉"
            } else {
                displayComment = savedComment
            }

            EduLogManager.shared.addItem(
                activityName: cat.activityName,
                activityEmoji: cat.activityEmoji,
                comment: displayComment,
                image: image,
                isPublic: true
            )

            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
