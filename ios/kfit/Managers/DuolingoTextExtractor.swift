import Foundation
import Vision
import NaturalLanguage
import AVFoundation
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
final class DuolingoTextExtractor {

    static let shared = DuolingoTextExtractor()
    private init() {}

    private let speechSynthesizer = AVSpeechSynthesizer()

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
    }

    var isSpeaking: Bool { speechSynthesizer.isSpeaking }

    // MARK: - BCP-47 変換

    private func bcp47Code(from code: String) -> String {
        switch code {
        case "zh", "zh-Hans", "cmn-Hans": return "zh-CN"
        case "zh-Hant":                   return "zh-TW"
        case "ko":                        return "ko-KR"
        case "fr":                        return "fr-FR"
        case "es":                        return "es-ES"
        case "de":                        return "de-DE"
        case "pt":                        return "pt-BR"
        case "it":                        return "it-IT"
        case "ru":                        return "ru-RU"
        case "ar":                        return "ar-SA"
        default:                          return "en-US"
        }
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
