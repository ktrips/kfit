import Foundation
import Vision
import NaturalLanguage
import AVFoundation
import Combine
import UIKit

// MARK: - 抽出結果

struct DuolingoExtractResult {
    var phrase: String            // 外国語フレーズ
    var languageCode: String      // 検出言語コード
    var languageName: String      // 言語表示名
    var pronunciation: String?    // ピンイン / ローマ字表記
    var translationJA: String?    // 日本語訳（Duolingo スクリーンショットから取得）
}

// MARK: - サービス

@MainActor
final class DuolingoTextExtractor: NSObject, ObservableObject {

    static let shared = DuolingoTextExtractor()
    override private init() {
        super.init()
        speechSynthesizer.delegate = self
    }

    private let speechSynthesizer = AVSpeechSynthesizer()

    // MARK: - 順次再生状態

    /// 順次再生するフレーズのキュー（phrase, langCode）
    private var sequenceQueue: [(phrase: String, langCode: String)] = []
    private var sequenceIdx: Int = 0
    private var sequenceOnFinish: (() -> Void)?

    /// 順次再生中かどうか（UI バインド用）
    @Published var isSequencePlaying: Bool = false
    /// 現在再生中のインデックス（0-based）
    @Published var sequenceCurrent: Int = 0
    /// 順次再生のフレーズ総数
    @Published var sequenceTotal: Int = 0
    /// 単発 speak() で読み上げ中かどうか（UI バインド用）
    @Published var isSpeaking: Bool = false

    // MARK: - OCR + 言語検出

    /// 画像からDuolingo外国語フレーズを抽出する
    func extract(from image: UIImage) async -> DuolingoExtractResult? {
        guard let cgImage = image.cgImage else { return nil }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }

                // 認識したすべての行を取得
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }

                // 日本語・英語・ロゴ行を除いて外国語フレーズを特定
                let result = self.parseDuolingoLines(lines)
                continuation.resume(returning: result)
            }

            // 多言語認識を有効化
            request.recognitionLanguages = [
                "zh-Hans", "zh-Hant",
                "en-US", "fr-FR", "es-ES", "de-DE",
                "ko-KR", "pt-BR", "it-IT", "ja-JP"
            ]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    // MARK: - 行解析

    private func parseDuolingoLines(_ lines: [String]) -> DuolingoExtractResult? {
        // Duolingo のスクリーンショット構造:
        //   - 「duolingo」「Duolingo」ロゴ文字
        //   - 外国語フレーズ（主な学習対象）
        //   - 日本語訳（ひらがな/カタカナ/漢字 が多い行）
        //   - その他 UI テキスト

        let skipWords: Set<String> = ["duolingo", "Duolingo", "この文を訳してください",
                                      "コンボ", "ライフ", "ハート"]

        var foreignPhrase: String?
        var japaneseTranslation: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !skipWords.contains(trimmed),
                  !trimmed.hasPrefix("x") else { continue }

            let lang = detectLanguage(trimmed)

            if lang == "ja" {
                if japaneseTranslation == nil && trimmed.count > 3 {
                    japaneseTranslation = trimmed
                }
            } else if lang != nil && lang != "en" {
                // 外国語（日本語・英語以外）を優先フレーズとして採用
                if foreignPhrase == nil && trimmed.count > 2 {
                    foreignPhrase = trimmed
                }
            } else if lang == "en" && foreignPhrase == nil {
                // 英語フレーズ（英語学習の場合）
                if trimmed.count > 4 && !trimmed.allSatisfy({ $0.isUppercase || $0 == " " }) {
                    foreignPhrase = trimmed
                }
            }
        }

        guard let phrase = foreignPhrase else { return nil }

        let detectedLang = detectLanguage(phrase) ?? "en"
        let langName = languageDisplayName(detectedLang)

        return DuolingoExtractResult(
            phrase: phrase,
            languageCode: detectedLang,
            languageName: langName,
            pronunciation: nil,   // ピンインは別途生成
            translationJA: japaneseTranslation
        )
    }

    // MARK: - 言語検出

    private func detectLanguage(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    /// 外部から言語表示名を取得するための public ラッパー
    func languageDisplayNamePublic(_ code: String) -> String {
        languageDisplayName(code)
    }

    private func languageDisplayName(_ code: String) -> String {
        switch code {
        case "zh", "zh-Hans", "cmn-Hans":  return "中国語"
        case "zh-Hant":                    return "中国語（繁体）"
        case "ko":                         return "韓国語"
        case "fr":                         return "フランス語"
        case "es":                         return "スペイン語"
        case "de":                         return "ドイツ語"
        case "pt":                         return "ポルトガル語"
        case "it":                         return "イタリア語"
        case "en":                         return "英語"
        case "ru":                         return "ロシア語"
        case "ar":                         return "アラビア語"
        default:                           return code
        }
    }

    // MARK: - TTS 再生

    /// フレーズを検出言語で音声再生する
    func speak(phrase: String, languageCode: String) {
        isSpeaking = true
        speechSynthesizer.stopSpeaking(at: .immediate)

        // サイレントモード・他セッションに関わらず確実に再生する
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try? session.setActive(true)

        // BCP-47 言語コードを AVSpeechSynthesizer 向けに変換
        let bcp47 = bcp47Code(from: languageCode)

        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = AVSpeechSynthesisVoice(language: bcp47)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.42          // やや遅め（学習用）
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        speechSynthesizer.speak(utterance)
    }

    func stopSpeaking() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    // MARK: - 順次再生

    /// 複数フレーズを順番に読み上げる。
    /// - Parameters:
    ///   - items: (phrase, langCode) のペア配列（空ならすぐ onFinish）
    ///   - onFinish: 全フレーズ再生完了時のコールバック
    func speakSequence(
        _ items: [(phrase: String, langCode: String)],
        onFinish: (() -> Void)? = nil
    ) {
        guard !items.isEmpty else { onFinish?(); return }
        stopSpeaking()
        sequenceQueue = items
        sequenceIdx = 0
        sequenceOnFinish = onFinish
        isSequencePlaying = true
        sequenceTotal = items.count
        sequenceCurrent = 0
        speakNextInQueue()
    }

    /// 順次再生を停止する
    func stopSequence() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        isSequencePlaying = false
        sequenceQueue = []
        sequenceOnFinish = nil
    }

    private func speakNextInQueue() {
        guard sequenceIdx < sequenceQueue.count else {
            isSequencePlaying = false
            sequenceOnFinish?()
            sequenceOnFinish = nil
            return
        }
        sequenceCurrent = sequenceIdx
        let item = sequenceQueue[sequenceIdx]
        speak(phrase: item.phrase, languageCode: item.langCode)
    }

    // MARK: - BCP-47 変換

    private func bcp47Code(from code: String) -> String {
        // LanguageUtils.swift の共通関数に委譲（重複定義を排除）
        languageBCP47Code(code)
    }

    // MARK: - LLM テキスト生成（文法解説 / 例文）

    /// コメントに「文法」が含まれていた場合に呼ぶ。
    /// 短い文法解説を日本語で返す。
    func generateGrammarNote(phrase: String, languageName: String,
                              settings: LLMSettings) async -> String? {
        let prompt = """
あなたは語学学習アシスタントです。
次の\(languageName)フレーズの文法を、日本語で3〜5文以内で簡潔に解説してください。
専門用語は使わず、学習者にわかりやすい表現で。

フレーズ:「\(phrase)」
"""
        return await callLLMText(prompt: prompt, settings: settings)
    }

    /// コメントに「ダメな理由」が含まれていた場合に呼ぶ。
    /// Duolingo の問題でよくある間違いの理由を日本語で解説する。
    func generateMistakeExplanation(phrase: String, languageName: String,
                                    settings: LLMSettings) async -> String? {
        let prompt = """
あなたは語学学習アシスタントです。
Duolingo で次の\(languageName)フレーズを学習している日本語話者が、よく間違えやすい理由を3〜5文で解説してください。
どのような勘違い・混乱が起きやすいか、日本語との違いや注意点を中心に、具体的にわかりやすく説明してください。

フレーズ:「\(phrase)」
"""
        return await callLLMText(prompt: prompt, settings: settings)
    }

    /// コメントに「例文」が含まれていた場合に呼ぶ。
    /// 同じ文法パターンを使った類似例文を 2 件返す。
    func generateExampleSentences(phrase: String, languageName: String,
                                   languageCode: String,
                                   settings: LLMSettings) async -> [ExampleSentence]? {
        let prompt = """
あなたは語学学習アシスタントです。
次の\(languageName)フレーズと似た文法・表現パターンを使った例文を2つ作成してください。
回答は必ず以下のJSON配列形式のみで返してください（説明文は不要）:
[
  {"text": "<\(languageName)の例文1>", "translationJA": "<日本語訳1>"},
  {"text": "<\(languageName)の例文2>", "translationJA": "<日本語訳2>"}
]

フレーズ:「\(phrase)」
"""
        guard let raw = await callLLMText(prompt: prompt, settings: settings) else { return nil }
        // JSONをパース
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonStr = extractJSON(from: cleaned)
        guard let data = jsonStr.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([ExampleSentence].self, from: data)
        else { return nil }
        return decoded.isEmpty ? nil : decoded
    }

    /// コメントに「単語」「他の単語」「文章」「他の文章」が含まれていた場合に呼ぶ。
    /// 関連単語（単語モード）または関連文章（文章モード）を 3〜4 件返す。
    func generateRelatedWords(phrase: String, languageName: String,
                              languageCode: String, mode: RelatedWordsMode,
                              settings: LLMSettings) async -> [ExampleSentence]? {
        let instruction: String
        switch mode {
        case .words:
            instruction = """
あなたは語学学習アシスタントです。
次の\(languageName)の語句に関連する単語・語彙を3〜4つ挙げてください。
同じ意味フィールド・トピックに属する語彙を選び、それぞれに日本語訳を付けてください。
回答は必ず以下のJSON配列形式のみで返してください（説明文は不要）:
[
  {"text": "<\(languageName)の単語1>", "translationJA": "<日本語訳1>"},
  {"text": "<\(languageName)の単語2>", "translationJA": "<日本語訳2>"},
  {"text": "<\(languageName)の単語3>", "translationJA": "<日本語訳3>"}
]

語句:「\(phrase)」
"""
        case .sentences:
            instruction = """
あなたは語学学習アシスタントです。
次の\(languageName)フレーズと同じテーマ・場面で使える関連文章を3つ作成してください。
それぞれに日本語訳を付けてください。
回答は必ず以下のJSON配列形式のみで返してください（説明文は不要）:
[
  {"text": "<\(languageName)の文章1>", "translationJA": "<日本語訳1>"},
  {"text": "<\(languageName)の文章2>", "translationJA": "<日本語訳2>"},
  {"text": "<\(languageName)の文章3>", "translationJA": "<日本語訳3>"}
]

フレーズ:「\(phrase)」
"""
        }
        guard let raw = await callLLMText(prompt: instruction, settings: settings) else { return nil }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonStr = extractJSON(from: cleaned)
        guard let data = jsonStr.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([ExampleSentence].self, from: data)
        else { return nil }
        return decoded.isEmpty ? nil : decoded
    }

    enum RelatedWordsMode { case words, sentences }

    // MARK: - LLM テキスト呼び出し共通

    private func callLLMText(prompt: String, settings: LLMSettings) async -> String? {
        // ユーザー API キー未設定時はサーバー代理（aiProxy）経由 — 設定ゼロで動くデフォルト経路
        guard !settings.apiKey.isEmpty else {
            let activeDayCount = RetentionTracker.shared.localActiveDayCount
            let isNinety = activeDayCount < 5

            // 10日以降のフリーユーザーはサーバーで拒否されるが、
            // クライアント側でも事前に activeDays を送信してエラーを受け取る
            return try? await AIProxyClient.call(
                prompt: prompt,
                category: "edu",
                isNinetyMode: isNinety,
                activeDays: activeDayCount
            )
        }
        do {
            switch settings.provider {
            case .openAI:
                return try await textOpenAI(prompt: prompt, settings: settings)
            case .anthropic:
                return try await textAnthropic(prompt: prompt, settings: settings)
            case .google:
                return try await textGoogle(prompt: prompt, settings: settings)
            }
        } catch {
            return nil
        }
    }

    private func textOpenAI(prompt: String, settings: LLMSettings) async throws -> String? {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "model": settings.effectiveModel,
            "max_completion_tokens": 512,
            "messages": [["role": "user", "content": prompt]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let content = msg["content"] as? String else { return nil }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func textAnthropic(prompt: String, settings: LLMSettings) async throws -> String? {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(settings.apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "model": settings.effectiveModel,
            "max_tokens": 512,
            "messages": [["role": "user", "content": prompt]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func textGoogle(prompt: String, settings: LLMSettings) async throws -> String? {
        let model = settings.effectiveModel
        let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(settings.apiKey)"
        let url = URL(string: urlStr)!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": ["maxOutputTokens": 512]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// レスポンスから最初の JSON 配列部分を抽出する
    private func extractJSON(from text: String) -> String {
        if let start = text.firstIndex(of: "["),
           let end = text.lastIndex(of: "]") {
            return String(text[start...end])
        }
        return text
    }

    // MARK: - 発音記号（ルビ）生成

    /// 中国語の場合にピンインを生成する（CFStringTransform を使用）
    func generatePronunciation(phrase: String, languageCode: String) -> String? {
        let lang = languageCode.lowercased()
        guard lang.hasPrefix("zh") || lang == "cmn-hans" else { return nil }

        // CFStringTransform で漢字 → ピンイン変換
        let mutable = NSMutableString(string: phrase)
        let success = CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        guard success else { return nil }
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
        let pinyin = (mutable as String).trimmingCharacters(in: .whitespaces)
        return pinyin.isEmpty ? nil : pinyin
    }
}

// MARK: - AVSpeechSynthesizerDelegate（順次再生のフレーズ進行）

extension DuolingoTextExtractor: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            if self.isSequencePlaying {
                self.sequenceIdx += 1
                // フレーズ間に 0.5 秒の間を空ける
                try? await Task.sleep(nanoseconds: 500_000_000)
                self.speakNextInQueue()
            } else {
                self.isSpeaking = false
            }
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }
}
