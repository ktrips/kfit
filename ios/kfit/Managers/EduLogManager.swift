import Foundation
import UIKit
import Combine
import FirebaseAuth

// MARK: - EduLogManager
// AuthenticationManager.swift から分離した独立 ObservableObject。
// 分離により Views は自身が必要なマネージャーのみを購読でき、
// AuthenticationManager の @Published 更新で EduLog 非関連 View が
// 再レンダリングされる問題を解消する。

@MainActor
class EduLogManager: ObservableObject {
    static let shared = EduLogManager()

    @Published var history: [EduLogHistoryItem] = []

    private let historyKey = "eduLogHistory_v1"

    private init() { loadHistory() }

    func addItem(activityName: String, activityEmoji: String, comment: String,
                 image: UIImage?, isPublic: Bool = true,
                 extractedPhrase: String? = nil,
                 extractedLanguageCode: String? = nil,
                 translationJA: String? = nil,
                 pronunciation: String? = nil,
                 weightKg: Double? = nil,
                 bodyFatPercent: Double? = nil,
                 sharedUrl: String? = nil,
                 sharedTitle: String? = nil,
                 sharedDescription: String? = nil,
                 sharedImageURL: String? = nil,
                 autoGenerateExamples: Bool = false) {
        let authorName: String = AuthenticationManager.shared.userProfile?.username
            ?? UserDefaults.standard.string(forKey: "cachedCurrentUserName")
            ?? Auth.auth().currentUser?.displayName
            ?? ""
        let authorPhotoURL = UserDefaults.standard.string(forKey: "cachedCurrentUserPhotoURL") ?? ""
        var item = EduLogHistoryItem(
            activityName: activityName,
            activityEmoji: activityEmoji,
            comment: comment,
            authorName: authorName,
            authorPhotoURL: authorPhotoURL,
            isPublic: isPublic
        )
        if let image, let thumbData = EduLogManager.makeThumbnailHQ(from: image) {
            item.thumbnailPath = ThumbnailFileStore.save(thumbData, id: "edu_\(item.id)")
        }

        item.extractedPhrase       = extractedPhrase
        item.extractedLanguageCode = extractedLanguageCode
        item.translationJA         = translationJA
        item.pronunciation         = pronunciation
        item.weightKg              = weightKg
        item.bodyFatPercent        = bodyFatPercent
        item.sharedUrl             = sharedUrl
        item.sharedTitle           = sharedTitle
        item.sharedDescription     = sharedDescription
        item.sharedImageURL        = sharedImageURL

        history.insert(item, at: 0)
        persistHistory()
        PublicFeedPublisher.publishEduDebounced(item)

        if image != nil {
            Task { await AuthenticationManager.shared.awardPoints(10) }
        }

        let isDuolingo = activityName.localizedCaseInsensitiveContains("Duolingo")
                      || activityEmoji == "🦉"
        let needsOCR = isDuolingo && extractedPhrase == nil

        if isDuolingo {
            let itemID                  = item.id
            let capturedComment         = comment
            let capturedAutoExamples    = autoGenerateExamples
            Task { @MainActor in
                var phrase   = extractedPhrase
                var langCode = extractedLanguageCode ?? "en"
                var langName = "英語"

                if needsOCR, let image {
                    guard let result = await DuolingoTextExtractor.shared.extract(from: image) else { return }
                    let pinyin = DuolingoTextExtractor.shared.generatePronunciation(
                        phrase: result.phrase, languageCode: result.languageCode
                    )
                    phrase   = result.phrase
                    langCode = result.languageCode
                    langName = result.languageName
                    if let idx = self.history.firstIndex(where: { $0.id == itemID }) {
                        self.history[idx].extractedPhrase       = result.phrase
                        self.history[idx].extractedLanguageCode = result.languageCode
                        self.history[idx].translationJA         = result.translationJA
                        self.history[idx].pronunciation         = pinyin
                    }
                } else if let p = phrase {
                    langName = DuolingoTextExtractor.shared.languageDisplayNamePublic(langCode)
                    let _ = p
                }

                guard let finalPhrase = phrase, !finalPhrase.isEmpty else {
                    if let idx = self.history.firstIndex(where: { $0.id == itemID }) {
                        self.persistHistory()
                        PublicFeedPublisher.publishEduDebounced(self.history[idx])
                    }
                    return
                }

                let llmSettings = await AuthenticationManager.shared.getLLMSettings()

                let llmWantsGrammar = capturedComment.contains("文法")
                    || capturedComment.localizedCaseInsensitiveContains("グラマー")
                    || capturedComment.localizedCaseInsensitiveContains("grammar")
                // コメントなし or autoGenerateExamples フラグ → デフォルトで例文2つを自動生成
                let isNoComment = capturedAutoExamples
                    || capturedComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let llmWantsExamples = isNoComment
                    || capturedComment.contains("例文")
                    || capturedComment.localizedCaseInsensitiveContains("グラマー")
                    || capturedComment.localizedCaseInsensitiveContains("grammar")
                let llmWantsMistake = capturedComment.contains("ダメな理由")
                let llmWantsRelatedWords = capturedComment.contains("単語")
                    && !capturedComment.contains("例文")
                let llmWantsRelatedSentences = (capturedComment.contains("文章")
                    || capturedComment.contains("他の文章"))
                    && !capturedComment.contains("例文")

                // APIキー未設定でもサーバー経由（1日1回無料）でAI利用可能
                let needsLLM = (llmWantsGrammar || llmWantsExamples || llmWantsMistake
                             || llmWantsRelatedWords || llmWantsRelatedSentences)

                // 並列 LLM 呼び出し（async let）
                async let grammarTask: String? = needsLLM && llmWantsGrammar
                    ? DuolingoTextExtractor.shared.generateGrammarNote(
                        phrase: finalPhrase, languageName: langName, settings: llmSettings)
                    : nil
                async let examplesTask: [ExampleSentence]? = needsLLM && llmWantsExamples
                    ? DuolingoTextExtractor.shared.generateExampleSentences(
                        phrase: finalPhrase, languageName: langName,
                        languageCode: langCode, settings: llmSettings)
                    : nil
                async let mistakeTask: String? = needsLLM && llmWantsMistake
                    ? DuolingoTextExtractor.shared.generateMistakeExplanation(
                        phrase: finalPhrase, languageName: langName, settings: llmSettings)
                    : nil
                async let relatedWordsTask: [ExampleSentence]? = needsLLM && llmWantsRelatedWords
                    ? DuolingoTextExtractor.shared.generateRelatedWords(
                        phrase: finalPhrase, languageName: langName, languageCode: langCode,
                        mode: .words, settings: llmSettings)
                    : needsLLM && llmWantsRelatedSentences
                        ? DuolingoTextExtractor.shared.generateRelatedWords(
                            phrase: finalPhrase, languageName: langName, languageCode: langCode,
                            mode: .sentences, settings: llmSettings)
                        : nil

                let (grammarNote, examples, mistakeNote, relatedWords) =
                    await (grammarTask, examplesTask, mistakeTask, relatedWordsTask)

                if let idx = self.history.firstIndex(where: { $0.id == itemID }) {
                    if let g = grammarNote  { self.history[idx].grammarNote      = g }
                    if let e = examples     { self.history[idx].exampleSentences = e }
                    if let m = mistakeNote  { self.history[idx].mistakeNote      = m }
                    if let r = relatedWords { self.history[idx].relatedWords     = r }
                    self.persistHistory()
                    PublicFeedPublisher.publishEduDebounced(self.history[idx])
                }
            }
        }
    }

    static func makeThumbnailHQ(from image: UIImage, maxDimension: CGFloat = 1200) -> Data? {
        let enhanced = image.enhancedForUpload()
        let size = enhanced.size
        let maxSide = max(size.width, size.height)
        let target: UIImage
        if maxSide > maxDimension {
            let scale = maxDimension / maxSide
            let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
            target = renderer.image { _ in enhanced.draw(in: CGRect(origin: .zero, size: newSize)) }
        } else {
            target = enhanced
        }
        return target.jpegData(compressionQuality: 0.88)
    }

    private static let syncTimestampKey = "eduLastSyncTimestamp"
    func syncAllPublicPosts() {
        let lastSync = UserDefaults.standard.double(forKey: Self.syncTimestampKey)
        let lastSyncDate = lastSync > 0 ? Date(timeIntervalSince1970: lastSync) : Date.distantPast
        var synced = false
        for item in history where item.isPublic && item.timestamp > lastSyncDate {
            PublicFeedPublisher.publishEduDebounced(item)
            synced = true
        }
        if synced {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.syncTimestampKey)
        }
    }

    func deleteItem(id: String) {
        history.removeAll { $0.id == id }
        persistHistory()
        PublicFeedPublisher.deleteEdu(id: id)
        ThumbnailFileStore.delete(id: "edu_\(id)")
    }

    func setPublic(id: String, isPublic: Bool) {
        guard let idx = history.firstIndex(where: { $0.id == id }) else { return }
        history[idx].isPublic = isPublic
        persistHistory()
        if isPublic {
            PublicFeedPublisher.publishEduDebounced(history[idx])
        } else {
            PublicFeedPublisher.deleteEdu(id: id)
        }
    }

    func toggleLike(id: String) {
        guard let idx = history.firstIndex(where: { $0.id == id }) else { return }
        history[idx].isLiked.toggle()
        history[idx].likeCount = max(0, history[idx].likeCount + (history[idx].isLiked ? 1 : -1))
        persistHistory()
        PublicFeedPublisher.publishEduDebounced(history[idx])
    }

    func toggleFavorite(id: String) {
        let baseId = id.hasPrefix("own_") ? String(id.dropFirst(4)) : id
        guard let idx = history.firstIndex(where: { $0.id == id || $0.id == baseId }) else { return }
        history[idx].isFavorite.toggle()
        persistHistory()
    }

    func importAndFavorite(_ item: EduLogHistoryItem) {
        if let idx = history.firstIndex(where: { $0.id == item.id }) {
            history[idx].isFavorite.toggle()
            persistHistory()
            return
        }
        var copy = item
        copy.isFavorite = true
        history.insert(copy, at: 0)
        persistHistory()
    }

    func updateItem(_ updated: EduLogHistoryItem) {
        let baseId = updated.id.hasPrefix("own_") ? String(updated.id.dropFirst(4)) : updated.id
        if let idx = history.firstIndex(where: { $0.id == updated.id || $0.id == baseId }) {
            history[idx] = updated
            persistHistory()
            if updated.isPublic {
                PublicFeedPublisher.publishEduDebounced(history[idx])
            }
        } else if updated.id.hasPrefix("own_") {
            var localCopy = updated
            localCopy.id = baseId
            history.insert(localCopy, at: 0)
            persistHistory()
            if localCopy.isPublic {
                PublicFeedPublisher.publishEduDebounced(localCopy)
            }
        }
    }

    func addFeedComment(id: String, text: String) {
        guard let idx = history.firstIndex(where: { $0.id == id }) else { return }
        let authorName     = AuthenticationManager.shared.userProfile?.username ?? ""
        let authorPhotoURL = UserDefaults.standard.string(forKey: "cachedCurrentUserPhotoURL") ?? ""
        let c = FeedComment(text: text, authorName: authorName, authorPhotoURL: authorPhotoURL)
        history[idx].feedComments.append(c)
        persistHistory()
    }

    func deleteFeedComment(itemId: String, commentId: String) {
        guard let idx = history.firstIndex(where: { $0.id == itemId }) else { return }
        history[idx].feedComments.removeAll { $0.id == commentId }
        persistHistory()
    }

    private func loadHistory() {
        guard let raw = UserDefaults.standard.data(forKey: historyKey),
              let items = try? JSONDecoder().decode([EduLogHistoryItem].self, from: raw) else { return }
        var needsMigration = false
        history = items.map { item in
            guard let thumbData = item.thumbnailData, item.thumbnailPath == nil else { return item }
            var copy = item
            if let path = ThumbnailFileStore.save(thumbData, id: "edu_\(item.id)") {
                copy.thumbnailPath = path
                copy.thumbnailData = nil
                needsMigration = true
            }
            return copy
        }
        if needsMigration { persistHistory() }
    }

    private var _lastPersistedSignature: String = ""
    private func persistHistory() {
        let snapshot = history
        // id + timestamp + isFavorite + likeCount でシグネチャを作成（変更なし検出）
        let sig = snapshot.map { "\($0.id):\($0.timestamp.timeIntervalSince1970):\($0.isFavorite):\($0.likeCount)" }.joined(separator: ",")
        guard sig != _lastPersistedSignature else { return }
        _lastPersistedSignature = sig
        Task.detached(priority: .utility) {
            let stripped = snapshot.map { item -> EduLogHistoryItem in
                guard item.thumbnailPath != nil else { return item }
                var copy = item
                copy.thumbnailData = nil
                return copy
            }
            if let data = try? JSONEncoder().encode(stripped) {
                UserDefaults.standard.set(data, forKey: self.historyKey)
            }
        }
    }
}
