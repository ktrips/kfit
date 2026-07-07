import SwiftUI
import Combine
import AVFoundation
import WatchKit
import CoreGraphics
import ImageIO

// MARK: - TTS エンジン（watchOS 用 — AVSpeechSynthesizerDelegate で順次再生）

private final class WatchEduSpeechEngine: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = WatchEduSpeechEngine()
    let synthesizer = AVSpeechSynthesizer()

    @Published var isSequencePlaying = false
    @Published var sequenceCurrent = 0
    @Published var sequenceTotal = 0

    private var queue: [(phrase: String, langCode: String)] = []
    private var idx = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ item: WatchEduItem) {
        stopAll()
        speak(phrase: item.phrase, langCode: item.langCode)
        WKInterfaceDevice.current().play(.click)
    }

    func speakSequence(_ items: [(phrase: String, langCode: String)]) {
        stopAll()
        guard !items.isEmpty else { return }
        queue = items
        idx = 0
        isSequencePlaying = true
        sequenceTotal = items.count
        sequenceCurrent = 0
        speakNext()
    }

    func stopAll() {
        synthesizer.stopSpeaking(at: .immediate)
        isSequencePlaying = false
        queue = []
    }

    private func speak(phrase: String, langCode: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = Self.bestVoice(for: bcp47(langCode))
        utterance.rate = 0.42
        synthesizer.speak(utterance)
    }

    /// 指定言語の音声を選ぶ。完全一致 → インストール済み音声の言語プレフィックス一致 →
    /// en-US の順でフォールバックする（watchOS は音声の搭載状況が機種・設定で異なるため、
    /// AVSpeechSynthesisVoice(language:) の nil で即 en-US に落とすと外国語が英語読みになる）
    private static func bestVoice(for bcp47Code: String) -> AVSpeechSynthesisVoice? {
        if let exact = AVSpeechSynthesisVoice(language: bcp47Code) { return exact }
        let prefix = String(bcp47Code.prefix(2))
        let installed = AVSpeechSynthesisVoice.speechVoices()
        if let match = installed.first(where: { $0.language.hasPrefix(prefix) }) { return match }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    private func speakNext() {
        guard idx < queue.count else {
            isSequencePlaying = false; return
        }
        sequenceCurrent = idx
        let item = queue[idx]
        speak(phrase: item.phrase, langCode: item.langCode)
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard self.isSequencePlaying else { return }
            self.idx += 1
            self.speakNext()
        }
    }

    /// BCP-47 変換（kfit側 LanguageUtils.languageBCP47Code と同一ロジック）
    /// watchOS ターゲットは kfit の iOS ターゲットと別プロジェクトのためコピー管理。
    /// 将来的には Swift Package (KFitCore) に統合して単一実装にすること。
    private func bcp47(_ code: String) -> String {
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
        case "ja":                        return "ja-JP"
        default:                          return "en-US"
        }
    }
}

// MARK: - WatchEdulingoView（メイン）

struct WatchEdulingoView: View {
    @EnvironmentObject private var store: WatchEduStore
    @StateObject private var engine = WatchEduSpeechEngine.shared

    // 選択中の言語コード。nil = 言語選択画面を表示
    @State private var selectedLang: String? = nil
    @State private var currentIndex = 0
    @State private var speakingID: String? = nil

    // 再生可能なアイテム（フレーズが空でないもの）
    private var playableItems: [WatchEduItem] {
        store.items.filter { !$0.phrase.isEmpty }
    }

    // 現在の言語でフィルターされた再生可能アイテム
    private var filteredItems: [WatchEduItem] {
        guard let lang = selectedLang else { return playableItems }
        return playableItems.filter { $0.langCode.hasPrefix(lang) }
    }

    // ストア内の言語一覧（再生可能アイテムがある言語のみ）
    private var availableLangs: [(code: String, flag: String, label: String)] {
        var seen = Set<String>()
        var result: [(String, String, String)] = []
        for item in playableItems {
            let key = String(item.langCode.prefix(2))
            if seen.insert(key).inserted {
                result.append((key, item.langFlag, item.langLabel))
            }
        }
        return result
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if store.isLoading && store.items.isEmpty {
                    loadingView
                } else if store.items.isEmpty {
                    emptyView
                } else if selectedLang == nil {
                    languageSelectionView
                } else {
                    feedView
                }
            }

            // 同期ボタン（右上）
            if selectedLang == nil || (store.isLoading || store.isSyncing) {
                syncButton
            }
        }
        .onAppear {
            // キャッシュあり・なし問わず最新データを要求（applicationContext から即反映）
            store.requestSync()
            if store.items.isEmpty {
                store.scheduleRetryIfNeeded()
            }
        }
        .onChange(of: selectedLang) { _ in
            engine.stopAll()
            currentIndex = 0
            speakingID = nil
        }
    }

    // MARK: - 同期ボタン

    private var syncButton: some View {
        Button { store.requestSync() } label: {
            ZStack {
                Circle().fill(Color.black.opacity(0.55)).frame(width: 28, height: 28)
                if store.isSyncing {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .green)).scaleEffect(0.55)
                } else {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .bold)).foregroundStyle(.green)
                }
            }
        }
        .buttonStyle(.plain).disabled(store.isSyncing)
        .padding(.top, 4).padding(.trailing, 4)
    }

    // MARK: - ローディング

    private var loadingView: some View {
        VStack(spacing: 6) {
            Text("🦉").font(.system(size: 32))
            Text("Edulingo").font(.headline.bold())
            ProgressView().tint(.green)
            Text("iPhoneのkeduを\n開いてください").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    // MARK: - 空状態

    private var emptyView: some View {
        VStack(spacing: 8) {
            Text("🦉").font(.system(size: 32))
            Text("投稿がありません").font(.caption.bold())
            Text("keduでDuolingo投稿を\n追加してください").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button {
                store.requestSync()
            } label: {
                HStack(spacing: 4) {
                    if store.isSyncing {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(0.6)
                    } else {
                        Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .bold))
                    }
                    Text(store.isSyncing ? "同期中..." : "同期する").font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Color.green.opacity(0.85))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain).disabled(store.isSyncing)
        }
        .padding(8)
    }

    // MARK: - 言語選択画面（バブル）

    private var languageSelectionView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                Text("🌍").font(.system(size: 28))
                Text("言語を選択").font(.system(size: 14, weight: .bold)).foregroundStyle(.primary)

                // 言語バブル（タグ）
                let langs = availableLangs
                if langs.isEmpty {
                    Text("データなし").font(.caption2).foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(langs, id: \.code) { lang in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedLang = lang.code
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(lang.flag).font(.system(size: 16))
                                    Text(lang.label).font(.system(size: 12, weight: .bold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(langColor(lang.code))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 4)
                }

                // 同期ボタン（画面内）
                Button { store.requestSync() } label: {
                    HStack(spacing: 4) {
                        if store.isSyncing {
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(0.6)
                        } else {
                            Image(systemName: "arrow.clockwise").font(.system(size: 11))
                        }
                        Text(store.isSyncing ? "同期中" : "更新").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Color.gray.opacity(0.4))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain).disabled(store.isSyncing)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - フィード（言語選択後）

    private var feedView: some View {
        let items = filteredItems
        return VStack(spacing: 0) {
            // 言語ヘッダー（戻るボタン付き）
            HStack(spacing: 6) {
                Button {
                    engine.stopAll()
                    selectedLang = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)

                if let lang = availableLangs.first(where: { $0.code == selectedLang }) {
                    Text(lang.flag).font(.system(size: 14))
                    Text(lang.label).font(.system(size: 12, weight: .bold)).foregroundStyle(.primary)
                }
                Spacer()

                // 全再生ボタン（フレーズ+例文を全アイテム分）
                Button {
                    if engine.isSequencePlaying {
                        engine.stopAll()
                        speakingID = nil
                    } else {
                        // 全アイテムのフレーズ+例文を結合して再生
                        let queue = items.flatMap { $0.playQueue }
                        guard !queue.isEmpty else { return }
                        speakingID = nil
                        engine.speakSequence(queue)
                    }
                } label: {
                    ZStack {
                        Circle().fill(engine.isSequencePlaying ? Color.red : Color.green)
                            .frame(width: 26, height: 26)
                        Image(systemName: engine.isSequencePlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .disabled(items.isEmpty)
            }
            .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 2)

            // 再生進捗バー
            if engine.isSequencePlaying && engine.sequenceTotal > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 9)).foregroundStyle(.green)
                    Text("\(engine.sequenceCurrent + 1) / \(engine.sequenceTotal)")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.green)
                    Spacer()
                }
                .padding(.horizontal, 10).padding(.bottom, 2)
            }

            // カード群
            if items.isEmpty {
                VStack(spacing: 8) {
                    Text("😅").font(.system(size: 24))
                    Text("フレーズなし").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        WatchEduCard(
                            item: item,
                            isSpeaking: speakingID == item.id || (engine.isSequencePlaying && engine.sequenceCurrent == idx)
                        ) {
                            // フレーズ + 例文を順番に再生
                            let queue = item.playQueue
                            guard !queue.isEmpty else { return }
                            engine.stopAll()
                            speakingID = item.id
                            WKInterfaceDevice.current().play(.click)
                            if queue.count == 1 {
                                engine.speak(item)
                            } else {
                                engine.speakSequence(queue)
                            }
                            // 推定再生時間後に再生中インジケータを消去
                            let totalChars = queue.map { $0.phrase.count }.reduce(0, +)
                            let estimatedSec = Double(totalChars) * 0.12 + Double(queue.count) * 1.5
                            DispatchQueue.main.asyncAfter(deadline: .now() + estimatedSec) {
                                if speakingID == item.id && !engine.isSequencePlaying {
                                    speakingID = nil
                                }
                            }
                        }
                        .tag(idx)
                    }
                }
                .tabViewStyle(.page)
                .indexViewStyle(.page(backgroundDisplayMode: .automatic))
                // 全再生中はカードを進める（アイテム単位で進む）
                .onChange(of: engine.sequenceCurrent) { cur in
                    if engine.isSequencePlaying && cur < items.count {
                        withAnimation { currentIndex = cur }
                    }
                }
                // 全再生終了時にインジケータをリセット
                .onChange(of: engine.isSequencePlaying) { playing in
                    if !playing { speakingID = nil }
                }
            }
        }
    }

    private func langColor(_ code: String) -> Color {
        switch code {
        case "zh": return Color(red: 0.85, green: 0.1, blue: 0.1)
        case "ko": return Color(red: 0.0,  green: 0.2, blue: 0.7)
        case "fr": return Color(red: 0.0,  green: 0.3, blue: 0.7)
        case "es": return Color(red: 0.8,  green: 0.4, blue: 0.0)
        case "de": return Color(red: 0.1,  green: 0.1, blue: 0.1)
        case "pt": return Color(red: 0.0,  green: 0.5, blue: 0.2)
        case "it": return Color(red: 0.6,  green: 0.0, blue: 0.0)
        case "ru": return Color(red: 0.1,  green: 0.1, blue: 0.6)
        default:   return Color(red: 0.1,  green: 0.55, blue: 0.1)
        }
    }
}

// MARK: - FlowLayout（バブルを折り返して配置）

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 160
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxW && x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}

// MARK: - WatchEduCard（1枚）

struct WatchEduCard: View {
    let item: WatchEduItem
    let isSpeaking: Bool
    let onTap: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 6) {

                // ── ヘッダー: アクティビティ絵文字＋言語バッジ＋再生ボタン ──
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(
                            colors: isSpeaking
                                ? [Color(red: 0.1, green: 0.5, blue: 0.8), Color(red: 0.0, green: 0.35, blue: 0.65)]
                                : [Color(red: 0.09, green: 0.56, blue: 0.03), Color(red: 0.35, green: 0.80, blue: 0.01)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(maxWidth: .infinity).frame(height: 58)

                    HStack(spacing: 0) {
                        // 左: アクティビティ絵文字 + 言語バッジ
                        HStack(spacing: 6) {
                            Text(activityEmoji(item.activityName))
                                .font(.system(size: 20))
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 3) {
                                    Text(item.langFlag).font(.system(size: 11))
                                    Text(item.langLabel)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                if !item.exampleTexts.isEmpty {
                                    Text("フレーズ+例文\(item.exampleTexts.count)件")
                                        .font(.system(size: 7, weight: .medium))
                                        .foregroundStyle(Color.white.opacity(0.75))
                                }
                            }
                        }
                        .padding(.leading, 10)

                        Spacer()

                        // 右: 再生/停止ボタン
                        Button(action: onTap) {
                            ZStack {
                                Circle()
                                    .fill(isSpeaking ? Color.red.opacity(0.9) : Color.white.opacity(0.25))
                                    .frame(width: 34, height: 34)
                                if isSpeaking {
                                    Image(systemName: "stop.fill")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                } else {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                        .offset(x: 1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 10)
                    }
                }

                // ── フレーズ（外国語）─────────────────────────
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        if isSpeaking {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.green)
                        }
                        Text(item.phrase)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // 日本語訳
                    if !item.translationJA.isEmpty {
                        Text(item.translationJA)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { onTap() }

                // ── 例文（あれば表示）──────────────────────────
                ForEach(Array(zip(item.exampleTexts.indices, item.exampleTexts)), id: \.0) { i, ex in
                    let trans = i < item.exampleTrans.count ? item.exampleTrans[i] : ""
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 3) {
                            Text("例文\(item.exampleTexts.count > 1 ? "\(i+1)" : "")")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(Color.gray)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color.gray.opacity(0.2))
                                .clipShape(Capsule())
                        }
                        Text(ex)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(3)
                        if !trans.isEmpty {
                            Text(trans)
                                .font(.system(size: 9))
                                .foregroundStyle(Color.gray)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(2)
                        }
                    }
                    .padding(.horizontal, 6).padding(.vertical, 5)
                    .background(Color.gray.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                // ── アクティビティ名 ───────────────────────────
                Text(item.activityName)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Helper

private func activityEmoji(_ name: String) -> String {
    let n = name.lowercased()
    if n.contains("duolingo")  { return "🦉" }
    if n.contains("読書") || n.contains("book") || n.contains("audible") || n.contains("kindle") { return "📖" }
    if n.contains("勉強") || n.contains("study") { return "📝" }
    if n.contains("英語") || n.contains("english") { return "🇬🇧" }
    if n.contains("スペイン") || n.contains("spanish") { return "🇪🇸" }
    if n.contains("フランス") || n.contains("french")  { return "🇫🇷" }
    if n.contains("中国") || n.contains("chinese")  { return "🇨🇳" }
    if n.contains("韓国") || n.contains("korean")   { return "🇰🇷" }
    return "📚"
}
