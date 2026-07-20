import SwiftUI

// MARK: - DuolingoPhrase（フラットデータモデル）
// EduLogHistoryItem / DayCarouselEntry のどちらからでも生成できる中間表現。
// TomoView・DashboardView・EdulingoView で統一的に使用する。

struct DuolingoPhrase {
    let id: String
    let phrase: String
    let languageCode: String
    let pronunciation: String?
    let translationJA: String?
    let mistakeNote: String?
    let grammarNote: String?
    let exampleSentences: [ExampleSentence]?
    let relatedWords: [ExampleSentence]?
    let extractedWords: [VocabWord]?
}

extension EduLogHistoryItem {
    var duolingoPhrase: DuolingoPhrase? {
        guard let p = extractedPhrase, !p.isEmpty else { return nil }
        return DuolingoPhrase(
            id: id,
            phrase: p,
            languageCode: extractedLanguageCode ?? "en",
            pronunciation: pronunciation,
            translationJA: translationJA,
            mistakeNote: mistakeNote,
            grammarNote: grammarNote,
            exampleSentences: exampleSentences,
            relatedWords: relatedWords,
            extractedWords: extractedWords
        )
    }
}

// NOTE: DayCarouselEntry の duolingoPhrase 拡張は DashboardView.swift 側に定義
// （DayCarouselEntry が kfit 専用のため。本ファイルは kedu ターゲットとも共有される）

// MARK: - System Share Sheet Wrapper
// TomoView（kfit / kedu 共有）から使用するためここに定義

struct SystemShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    /// 共有シートが閉じた時に呼ばれる。`completed` は実際に共有・保存などが
    /// 行われた場合に true（キャンセルのみの場合は false）。
    var onComplete: ((Bool) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, completed, _, _ in
            onComplete?(completed)
        }
        return vc
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - 複数画像を確実に共有するための ActivityItemSource
// Facebookの共有拡張（ネイティブ・アプリいずれも）は UIActivityViewController に
// 渡された複数枚の画像のうち1枚しか受け取れないため、そのままだと2枚目以降が
// 欠落する。Facebook向けには全画像を縦に結合した1枚を渡し、それ以外の共有先には
// 従来通り個別の画像を渡すことで、共有先を問わず内容が欠落しないようにする。

final class MultiImageShareItemSource: NSObject, UIActivityItemSource {
    private let image: UIImage
    private let mergedImageForFacebook: UIImage?
    private let isPrimary: Bool

    /// `images` の各要素ごとに1つずつ生成し、まとめて共有シートの activityItems に渡す。
    static func makeItems(images: [UIImage]) -> [MultiImageShareItemSource] {
        let merged = images.count > 1 ? combinedVertically(images) : nil
        return images.enumerated().map { index, image in
            MultiImageShareItemSource(image: image, mergedImageForFacebook: merged, isPrimary: index == 0)
        }
    }

    private init(image: UIImage, mergedImageForFacebook: UIImage?, isPrimary: Bool) {
        self.image = image
        self.mergedImageForFacebook = mergedImageForFacebook
        self.isPrimary = isPrimary
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        image
    }

    func activityViewController(_ activityViewController: UIActivityViewController,
                                 itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        let isFacebook = activityType?.rawValue.lowercased().contains("facebook") ?? false
        guard isFacebook else { return image }
        // Facebookには結合済みの1枚だけを、先頭のソースからのみ渡す（2枚目以降は nil で除外）。
        return isPrimary ? (mergedImageForFacebook ?? image) : nil
    }

    private static func combinedVertically(_ images: [UIImage]) -> UIImage? {
        guard let first = images.first else { return nil }
        let spacing: CGFloat = 16
        let width = images.map(\.size.width).max() ?? first.size.width
        let height = images.reduce(0) { $0 + $1.size.height } + spacing * CGFloat(images.count - 1)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = first.scale
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            var y: CGFloat = 0
            for image in images {
                let x = (width - image.size.width) / 2
                image.draw(at: CGPoint(x: x, y: y))
                y += image.size.height + spacing
            }
        }
    }
}

// MARK: - DuolingoPhraseView
// Duolingo フレーズパネルの統一実装。
// TomoView・SwipeableTomoDetailSheet・DayCarouselSheet の三箇所で共有。
// 自前で TTS ステートを管理するため、呼び出し元でのステート管理は不要。

struct DuolingoPhraseView: View {
    let data: DuolingoPhrase

    @ObservedObject private var tts = DuolingoTextExtractor.shared
    @State private var isMySeqPlaying = false
    @State private var speakingExKey: String? = nil

    private var langCode: String { data.languageCode }
    private var langColor: Color { languageBadgeColor(langCode) }

    private var allPhrases: [(phrase: String, langCode: String)] {
        var q: [(String, String)] = [(data.phrase, langCode)]
        if let ex = data.exampleSentences  { q += ex.map { ($0.text, langCode) } }
        if let rel = data.relatedWords     { q += rel.map { ($0.text, langCode) } }
        if let words = data.extractedWords { q += words.map { ($0.text, $0.languageCode) } }
        return q
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow
            phraseText
            pronunciationText
            translationText
            mistakeNoteCard
            grammarNoteCard
            examplesCard
            relatedCard
            wordsCard
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.systemGray6).opacity(0.55))
        .cornerRadius(12)
        .onChange(of: tts.isSequencePlaying) { playing in
            if !playing { isMySeqPlaying = false }
        }
    }

    // MARK: - Sub-components

    private var headerRow: some View {
        HStack(spacing: 6) {
            // 言語バッジ
            HStack(spacing: 4) {
                Text(languageFlag(langCode)).font(.system(size: 14))
                Text(languageLabel(langCode))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(langColor)
            .clipShape(Capsule())

            Spacer()

            // 全再生ボタン
            Button {
                if isMySeqPlaying {
                    tts.stopSequence()
                    isMySeqPlaying = false
                } else {
                    isMySeqPlaying = true
                    speakingExKey = nil
                    tts.speakSequence(allPhrases) {
                        DispatchQueue.main.async { isMySeqPlaying = false }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: isMySeqPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(isMySeqPlaying
                         ? "\(tts.sequenceCurrent + 1)/\(tts.sequenceTotal)"
                         : "全再生")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(isMySeqPlaying ? Color.red : Color(hex: "#CE82FF"))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var phraseText: some View {
        Text(data.phrase)
            .font(.system(size: 18 * UIScale.font, weight: .bold))
            .foregroundColor(Color.duoDark)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var pronunciationText: some View {
        if let pron = data.pronunciation, !pron.isEmpty {
            Text(pron)
                .font(.system(size: 13 * UIScale.font))
                .foregroundColor(Color(hex: "#1CB0F6"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var translationText: some View {
        if let tja = data.translationJA, !tja.isEmpty {
            Text(tja)
                .font(.system(size: 13 * UIScale.font))
                .foregroundColor(Color.duoSubtitle)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var mistakeNoteCard: some View {
        if let note = data.mistakeNote, !note.isEmpty {
            noteBlock(
                label: "ダメな理由", icon: "exclamationmark.triangle",
                text: note, accent: Color(hex: "#FF3B30")
            )
        }
    }

    @ViewBuilder
    private var grammarNoteCard: some View {
        if let note = data.grammarNote, !note.isEmpty {
            noteBlock(
                label: "文法メモ", icon: "text.book.closed",
                text: note, accent: Color(hex: "#FF9500")
            )
        }
    }

    @ViewBuilder
    private var examplesCard: some View {
        if let examples = data.exampleSentences, !examples.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("例文", systemImage: "quote.bubble")
                    .font(.system(size: 11 * UIScale.font, weight: .semibold))
                    .foregroundColor(Color(hex: "#58CC02"))
                ForEach(Array(examples.enumerated()), id: \.offset) { idx, ex in
                    exampleRow(ex, index: idx, prefix: "\(idx + 1).",
                               color: Color(hex: "#58CC02"), key: "\(data.id)-ex\(idx)")
                }
            }
            .padding(10)
            .background(Color(hex: "#58CC02").opacity(0.07))
            .cornerRadius(8)
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var relatedCard: some View {
        if let related = data.relatedWords, !related.isEmpty {
            let relColor = Color(hex: "#1CB0F6")
            VStack(alignment: .leading, spacing: 6) {
                Label("関連表現", systemImage: "text.bubble")
                    .font(.system(size: 11 * UIScale.font, weight: .semibold))
                    .foregroundColor(relColor)
                ForEach(Array(related.enumerated()), id: \.offset) { idx, rel in
                    exampleRow(rel, index: idx, prefix: "·",
                               color: relColor, key: "\(data.id)-rel\(idx)")
                }
            }
            .padding(10)
            .background(relColor.opacity(0.07))
            .cornerRadius(8)
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var wordsCard: some View {
        if let words = data.extractedWords, !words.isEmpty {
            let wordColor = Color(hex: "#CE82FF")
            VStack(alignment: .leading, spacing: 6) {
                Label("単語リスト", systemImage: "textformat.abc")
                    .font(.system(size: 11 * UIScale.font, weight: .semibold))
                    .foregroundColor(wordColor)
                ForEach(Array(words.enumerated()), id: \.offset) { idx, word in
                    wordRow(word, color: wordColor, key: "\(data.id)-word\(idx)")
                }
            }
            .padding(10)
            .background(wordColor.opacity(0.07))
            .cornerRadius(8)
            .padding(.top, 2)
        }
    }

    // MARK: - Helper builders

    private func noteBlock(label: String, icon: String, text: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon)
                .font(.system(size: 11 * UIScale.font, weight: .semibold))
                .foregroundColor(accent)
            Text(text)
                .font(.system(size: 13 * UIScale.font))
                .foregroundColor(Color.duoDark)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(accent.opacity(0.07))
        .cornerRadius(8)
        .padding(.top, 2)
    }

    private func exampleRow(_ ex: ExampleSentence, index: Int, prefix: String,
                            color: Color, key: String) -> some View {
        let isSpeaking = speakingExKey == key
        return HStack(alignment: .top, spacing: 6) {
            Text(prefix)
                .font(.system(size: 13 * UIScale.font, weight: .bold))
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(ex.text)
                    .font(.system(size: 14 * UIScale.font, weight: .semibold))
                    .foregroundColor(Color.duoDark)
                    .fixedSize(horizontal: false, vertical: true)
                if let tr = ex.translationJA, !tr.isEmpty {
                    Text(tr)
                        .font(.system(size: 12 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Button {
                if isSpeaking {
                    tts.stopSpeaking()
                    speakingExKey = nil
                } else {
                    speakingExKey = key
                    isMySeqPlaying = false
                    tts.speak(phrase: ex.text, languageCode: langCode)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                        if speakingExKey == key { speakingExKey = nil }
                    }
                }
            } label: {
                Image(systemName: isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 13))
                    .foregroundColor(isSpeaking ? .red : color)
                    .frame(width: 28, height: 28)
                    .background((isSpeaking ? Color.red : color).opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private func wordRow(_ word: VocabWord, color: Color, key: String) -> some View {
        let isSpeaking = speakingExKey == key
        return HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(word.text)
                    .font(.system(size: 14 * UIScale.font, weight: .semibold))
                    .foregroundColor(Color.duoDark)
                    .fixedSize(horizontal: false, vertical: true)
                if let reading = word.reading, !reading.isEmpty {
                    Text(reading)
                        .font(.system(size: 12 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Button {
                if isSpeaking {
                    tts.stopSpeaking()
                    speakingExKey = nil
                } else {
                    speakingExKey = key
                    isMySeqPlaying = false
                    tts.speak(phrase: word.text, languageCode: word.languageCode)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                        if speakingExKey == key { speakingExKey = nil }
                    }
                }
            } label: {
                Image(systemName: isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 13))
                    .foregroundColor(isSpeaking ? .red : color)
                    .frame(width: 28, height: 28)
                    .background((isSpeaking ? Color.red : color).opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - routinGoShareCaption
// スパイラル・今日の投稿を共有する際の共通メッセージ。DashboardView で共有。

private let routinGoShareDateFmt: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ja_JP")
    f.dateFormat = "M/d(E)"
    return f
}()

func routinGoShareCaption() -> String {
    "今日 \(routinGoShareDateFmt.string(from: Date()))のルーティン。Fit.ktrips.netで継続中！"
}

// MARK: - dayLabel
// 参加日（joinDate）からの経過日数を "Day N" 形式で返す。
// GoalView・GoalingoView・TomoView・WeightFeedCard で共有。

@MainActor
func dayLabel(for date: Date) -> String {
    let joinDate = AuthenticationManager.shared.userProfile?.joinDate ?? date
    let cal = Calendar.current
    let days = cal.dateComponents([.day],
                                  from: cal.startOfDay(for: joinDate),
                                  to: cal.startOfDay(for: date)).day ?? 0
    return "Day \(days + 1)"
}

// MARK: - WeightFatReadout
// 体重・体脂肪率を絵文字付きで横並び表示する読み取り行（写真オーバーレイ用）。
// WeightFeedCard・DashboardView（今日の投稿）で共有。

struct WeightFatReadout: View {
    let weightKg: Double?
    let bodyFatPercent: Double?

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                Text("⚖️").font(.system(size: 10 * UIScale.font))
                Text(weightKg != nil ? String(format: "%.1f", weightKg!) : "—")
                    .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("kg")
                    .font(.system(size: 8 * UIScale.font, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
            }
            if let fat = bodyFatPercent {
                HStack(spacing: 2) {
                    Text("📉").font(.system(size: 10 * UIScale.font))
                    Text(String(format: "%.1f", fat))
                        .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("%")
                        .font(.system(size: 8 * UIScale.font, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
        }
    }
}

// MARK: - WeightFeedCard
// 体重ログの写真上に日付・Day番号・体重・体脂肪率を重ねるカード。
// GoalView・GoalingoView の FIT フィード一覧で共有。

struct WeightFeedCard: View {
    let item: EduLogHistoryItem

    private static let mdFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d (E)"; return f
    }()

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let thumb = item.thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(colors: [Color(hex: "#1CB0F6"), Color(hex: "#58CC02")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(Text("⚖️").font(.system(size: 44 * UIScale.font)))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150)
            .clipped()

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(WeightFeedCard.mdFmt.string(from: item.timestamp))
                        .font(.system(size: 10 * UIScale.font, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                    Text(dayLabel(for: item.timestamp))
                        .font(.system(size: 9 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Capsule())
                }
                .shadow(color: .black.opacity(0.5), radius: 2)
                WeightFatReadout(weightKg: item.weightKg, bodyFatPercent: item.bodyFatPercent)
                    .shadow(color: .black.opacity(0.5), radius: 2)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [.clear, Color.black.opacity(0.65)],
                               startPoint: .top, endPoint: .bottom)
            )
        }
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.14), radius: 6, x: 0, y: 3)
    }
}

// MARK: - MacroChip
// PFC 栄養素チップ。FoodView・DashboardView で共有。

struct MacroChip: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(color.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(color.opacity(0.08))
        .cornerRadius(12)
    }
}

// MARK: - LinkPreviewCard
// 外部リンクのプレビューカード。DashboardView・TomoView で共有。

struct LinkPreviewCard: View {
    let title: String?
    let url: URL

    var body: some View {
        Button { UIApplication.shared.open(url) } label: {
            HStack(spacing: 12) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(Color(hex: "#1CB0F6"))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title ?? url.host ?? url.absoluteString)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color.duoDark)
                        .lineLimit(2)
                    Text(url.absoluteString)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#1CB0F6").opacity(0.7))
            }
            .padding(12)
            .background(Color(hex: "#1CB0F6").opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "#1CB0F6").opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
