import Foundation
import UIKit
import Combine
import FirebaseAuth
import Vision

// MARK: - App 本体側: 起動時に共有コンテナを処理してフィードに投稿する

private let appGroupID       = "group.com.kfit.app"
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
    let isDuolingoSource = sourceApp.lowercased().contains("duolingo")

    let duoKeywords = ["duo", "duolingo", "🦉", "daily", "デイリー",
                       "challenge", "チャレンジ", "ストリーク", "streak",
                       "xp", "リーグ", "league", "ハート", "レッスン",
                       "例文", "文法", "grammar", "翻訳", "translation",
                       "ダメな理由", "単語", "vocabulary", "vocab",
                       "フレーズ", "phrase", "発音", "pronunciation",
                       "ピンイン", "pinyin"]
    if isDuolingoSource || duoKeywords.contains(where: { text.contains($0) }) {
        return ShareCategory(activityName: "Duolingo", activityEmoji: "🦉", isDuolingo: true)
    }

    // ── 日記 ──────────────────────────────────────────────────────────────
    let diaryKeywords = ["日記", "diary", "フォト日記", "journal", "メモ", "今日の出来事", "記録"]
    if diaryKeywords.contains(where: { text.contains($0) }) {
        return ShareCategory(activityName: "日記", activityEmoji: "📔", isDuolingo: false)
    }

    // ── 読書 ──────────────────────────────────────────────────────────────
    // "audible" 等はキーワードとして sourceApp（読書系アプリのバンドルID文字列）にも
    // マッチするため、Audible からの画像共有等の判定漏れに対する安全網となる。
    let readingKeywords = ["読書", "読んだ", "reading", "book", "本", "小説", "マンガ", "漫画",
                           "kindl", "電子書籍", "audible", "libby", "overdrive", "kobo"]
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

// MARK: - OCR による Duolingo 判定

/// Vision OCR で画像からDuolingo固有テキストを検知する（フォールバック用）
private func detectsDuolingoByOCR(_ image: UIImage) async -> Bool {
    guard let cgImage = image.cgImage else { return false }
    return await withCheckedContinuation { continuation in
        let request = VNRecognizeTextRequest { req, _ in
            let observations = req.results as? [VNRecognizedTextObservation] ?? []
            let allText = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")
                .lowercased()

            // Duolingo 固有テキストパターン
            let duoPatterns = [
                "duolingo",
                "duo",
                "🦉",
                // UI 固有テキスト
                "daily goal", "ストリーク", "streak",
                "xp", "league", "リーグ",
                "hearts", "ハート",
                // 言語学習テキスト
                "lesson complete", "レッスン完了",
                "you earned", "獲得",
                // 言語ペア表記
                "spanish", "french", "german", "japanese", "chinese", "korean",
                "スペイン語", "フランス語", "ドイツ語", "中国語", "韓国語",
                // 典型的な Duolingo スクリーンショット文言
                "keep it up", "nice work", "great work",
                // 問題文の典型パターン
                "tap what you hear", "type what you hear",
                "select the correct translation"
            ]
            let isDuolingo = duoPatterns.contains { allText.contains($0) }
            continuation.resume(returning: isDuolingo)
        }
        // Fast モードで十分（キーワード検知のみ）
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        // 多言語認識
        request.recognitionLanguages = ["ja-JP", "en-US", "es-ES", "zh-Hant", "zh-Hans", "ko-KR"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }
}

// MARK: - PendingShareProcessor

@MainActor
class PendingShareProcessor {

    static let shared = PendingShareProcessor()

    /// kfitApp.onAppear や scenePhase.active から呼ぶ（ログイン済みであれば可）
    func processPendingShares() async {
        guard Auth.auth().currentUser != nil else { return }
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }

        let pending = defaults.array(forKey: pendingSharesKey) as? [[String: Any]] ?? []
        guard !pending.isEmpty else { return }

        defaults.removeObject(forKey: pendingSharesKey)
        defaults.synchronize()

        let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)

        for item in pending {
            let savedComment = item["comment"] as? String ?? ""
            let sourceApp    = item["sourceApp"] as? String ?? ""
            let urlString    = item["urlString"] as? String
            let sharedTitle  = item["sharedTitle"] as? String
            let sharedText   = item["sharedText"] as? String

            // ── プレーンテキスト共有（単語・フレーズ）：画像・URLなし ─────────────
            // 発音記号・意味・例文（発話）は EduLogManager.addItem 内でLLM生成される
            if let text = sharedText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                let langCode = DuolingoTextExtractor.shared.detectLanguagePublic(text) ?? "en"
                let cat = ShareCategory(activityName: "Duolingo", activityEmoji: "🦉", isDuolingo: true)

                EduLogManager.shared.addItem(
                    activityName:          cat.activityName,
                    activityEmoji:         cat.activityEmoji,
                    comment:               "🦉 \(text) を追加",
                    image:                 nil,
                    isPublic:              true,
                    extractedPhrase:       text,
                    extractedLanguageCode: langCode,
                    autoGenerateExamples:  true
                )
                postNotificationsIfNeeded(cat: cat)
                continue
            }

            // ── URL-only 共有（画像なし）───────────────────────────────────
            if let urlStr = urlString, item["filename"] == nil {
                let cat = detectCategoryForURL(urlStr: urlStr, comment: savedComment,
                                               sourceApp: sourceApp,
                                               forcedCategory: item["category"] as? String)
                let displayComment = savedComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "\(cat.activityEmoji) \(cat.activityName) をシェア📚"
                    : savedComment

                // OGメタデータを取得して本のタイトル・概要を保存
                let ogMeta = await LinkMetadataFetcher.fetchOGMeta(urlString: urlStr)
                let finalTitle = ogMeta.title ?? sharedTitle ?? displayComment
                let finalDesc  = ogMeta.description
                let finalImgURL = ogMeta.imageURL

                EduLogManager.shared.addItem(
                    activityName:      cat.activityName,
                    activityEmoji:     cat.activityEmoji,
                    comment:           displayComment,
                    image:             nil,
                    isPublic:          true,
                    sharedUrl:         urlStr,
                    sharedTitle:       finalTitle,
                    sharedDescription: finalDesc,
                    sharedImageURL:    finalImgURL
                )
                postNotificationsIfNeeded(cat: cat)
                continue
            }

            // ── 画像共有（URL が付属している場合もある）─────────────────────
            guard let filename = item["filename"] as? String,
                  let fileURL  = containerURL?.appendingPathComponent(filename),
                  let imageData = try? Data(contentsOf: fileURL),
                  let image     = UIImage(data: imageData) else { continue }

            // ── カテゴリ判定（3段階フォールバック）────────────────────────────
            // Duolingoアプリからの共有（isDuolingo または sourceApp が Duolingo）でも、
            // コメントに「日記」「写真」「今日」等が含まれる場合は日記として扱う
            // （ストリーク画面・イベントバナー等、レッスン以外のスクショの誤分類対策）
            let sourceSignalsDuolingo = item["isDuolingo"] as? Bool == true
                || sourceApp.lowercased().contains("duolingo")
            let diaryOverrideKeywords = ["日記", "写真", "今日"]
            let hasDiaryOverride = sourceSignalsDuolingo
                && diaryOverrideKeywords.contains { savedComment.contains($0) }

            var cat: ShareCategory
            if hasDiaryOverride {
                cat = ShareCategory(activityName: "日記", activityEmoji: "📔", isDuolingo: false)
            } else if item["isDuolingo"] as? Bool == true {
                cat = ShareCategory(activityName: "Duolingo", activityEmoji: "🦉", isDuolingo: true)
            } else if let forced = item["category"] as? String {
                cat = detectCategoryForURL(urlStr: urlString ?? "", comment: savedComment,
                                           sourceApp: sourceApp, forcedCategory: forced)
            } else {
                cat = detectCategory(comment: savedComment, sourceApp: sourceApp)
                if !cat.isDuolingo {
                    let ocrDetected = await detectsDuolingoByOCR(image)
                    if ocrDetected {
                        cat = ShareCategory(activityName: "Duolingo", activityEmoji: "🦉", isDuolingo: true)
                    }
                }
            }

            let originalCommentEmpty = savedComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let displayComment: String
            if originalCommentEmpty {
                displayComment = "\(cat.activityEmoji) \(cat.activityName) 達成！🎉"
            } else {
                displayComment = savedComment
            }
            // Duolingo + コメントなし → 例文を自動生成
            let shouldAutoExamples = cat.isDuolingo && originalCommentEmpty

            // 画像付き共有でも URL があれば OG メタデータを取得
            var imgShareTitle = sharedTitle
            var imgShareDesc: String? = nil
            var imgShareImgURL: String? = nil
            if let urlStr = urlString {
                let ogMeta = await LinkMetadataFetcher.fetchOGMeta(urlString: urlStr)
                imgShareTitle = ogMeta.title ?? sharedTitle
                imgShareDesc  = ogMeta.description
                imgShareImgURL = ogMeta.imageURL
            }

            EduLogManager.shared.addItem(
                activityName:        cat.activityName,
                activityEmoji:       cat.activityEmoji,
                comment:             displayComment,
                image:               image,
                isPublic:            true,
                sharedUrl:           urlString,
                sharedTitle:         imgShareTitle,
                sharedDescription:   imgShareDesc,
                sharedImageURL:      imgShareImgURL,
                autoGenerateExamples: shouldAutoExamples
            )
            postNotificationsIfNeeded(cat: cat)
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    // MARK: - カテゴリ判定（URL・forcedCategory 対応版）

    private func detectCategoryForURL(urlStr: String, comment: String,
                                      sourceApp: String, forcedCategory: String?) -> ShareCategory {
        if forcedCategory == "reading" {
            return ShareCategory(activityName: "読書", activityEmoji: "📖", isDuolingo: false)
        }
        if forcedCategory == "duolingo" {
            return ShareCategory(activityName: "Duolingo", activityEmoji: "🦉", isDuolingo: true)
        }
        // URL パターンで読書判定
        let readingUrlPatterns = ["audible.com", "audible.co.jp", "amazon.co.jp/dp/",
                                  "amazon.com/dp/", "kindle.amazon", "books.google.com",
                                  "libbyapp.com", "overdrive.com", "bookwalker.jp",
                                  "kobo.com", "booklive.jp", "ebookjapan"]
        let urlLower = urlStr.lowercased()
        if readingUrlPatterns.contains(where: { urlLower.contains($0) }) {
            return ShareCategory(activityName: "読書", activityEmoji: "📖", isDuolingo: false)
        }
        return detectCategory(comment: comment, sourceApp: sourceApp)
    }

    // MARK: - 通知送出

    private func postNotificationsIfNeeded(cat: ShareCategory) {
        if cat.isDuolingo {
            let weekdayNum: Int = {
                let wd = Calendar.current.component(.weekday, from: Date())
                return wd == 1 ? 7 : wd - 1
            }()
            Task { await TimeSlotManager.shared.completeCustomGoalIfNeeded(id: "wd_study_\(weekdayNum)") }
        }
        NotificationCenter.default.post(name: .duolingoShareProcessed, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(name: .duolingoShareProcessed, object: nil)
        }
    }
}

extension Notification.Name {
    static let duolingoShareProcessed = Notification.Name("com.kfit.duolingoShareProcessed")
}
