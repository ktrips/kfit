import Foundation
import Combine
import WatchConnectivity
import WatchKit
import os

private let wcLogger = Logger(subsystem: "com.ktrips.kedu.watchkitapp", category: "WatchEduStore")

// MARK: - WatchEduItem

struct WatchEduItem: Identifiable, Codable {
    let id: String
    let phrase: String           // extractedPhrase
    let langCode: String         // extractedLanguageCode (例: "zh-Hans", "en", "fr")
    let translationJA: String    // 日本語訳
    let activityName: String
    let timestamp: Double        // Unix timestamp
    // 例文（TTS 用）: 複数件対応
    let exampleTexts: [String]       // 例文テキスト（最大3件）
    let exampleTrans: [String]       // 例文訳（最大3件）
    // 後方互換: 先頭例文
    var exampleText: String? { exampleTexts.first }
    var exampleTranslation: String? { exampleTrans.first }
    // リンク共有用
    let sharedTitle: String?
    let sharedUrl: String?

    var langFlag: String { languageFlag(langCode) }
    var langLabel: String { languageLabel(langCode) }

    /// フレーズ+全例文の再生キューを返す（TTS 順次再生用）
    var playQueue: [(phrase: String, langCode: String)] {
        var q: [(String, String)] = []
        if !phrase.isEmpty { q.append((phrase, langCode)) }
        for ex in exampleTexts where !ex.isEmpty { q.append((ex, langCode)) }
        return q
    }

    init?(from dict: [String: Any]) {
        guard let id   = dict["id"]       as? String,
              let lang = dict["langCode"] as? String
        else { return nil }
        self.id              = id
        self.phrase          = dict["phrase"]          as? String ?? ""
        self.langCode        = lang
        self.translationJA   = dict["translationJA"]   as? String ?? ""
        self.activityName    = dict["activityName"]    as? String ?? "Duolingo"
        self.timestamp       = dict["timestamp"]       as? Double ?? 0
        // 複数例文（新形式）
        if let texts = dict["exampleTexts"] as? [String] {
            self.exampleTexts = texts
        } else if let single = dict["exampleText"] as? String, !single.isEmpty {
            self.exampleTexts = [single]
        } else {
            self.exampleTexts = []
        }
        if let trans = dict["exampleTrans"] as? [String] {
            self.exampleTrans = trans
        } else if let single = dict["exampleTranslation"] as? String, !single.isEmpty {
            self.exampleTrans = [single]
        } else {
            self.exampleTrans = []
        }
        self.sharedTitle     = dict["sharedTitle"]     as? String
        self.sharedUrl       = dict["sharedUrl"]       as? String
    }
}

// MARK: - WatchEduStore（WatchConnectivity 受信 + キャッシュ）

@MainActor
class WatchEduStore: NSObject, ObservableObject {
    static let shared = WatchEduStore()

    @Published var items: [WatchEduItem] = []
    @Published var isLoading = true
    @Published var isSyncing = false

    private let cacheKey = "watchEduItems_v5"  // v5: exampleTexts 配列対応
    private var syncTimeoutTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var activationRetryCount = 0

    override init() {
        super.init()
        loadCache()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: - キャッシュ読み込み

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([WatchEduItem].self, from: data),
              !decoded.isEmpty else { return }
        items = decoded
        isLoading = false
    }

    // MARK: - アイテム適用（重複排除・最新優先）

    /// "own_{id}"（旧ビルドのiOSが送っていた形式）と生 id は同一投稿。
    /// 旧キャッシュとの突き合わせ時に二重表示にならないよう正規化して比較する。
    private static func normalizedId(_ id: String) -> String {
        id.hasPrefix("own_") ? String(id.dropFirst("own_".count)) : id
    }

    private func applyItems(_ raw: [[String: Any]]) {
        var parsed: [WatchEduItem] = []
        var seenKeys = Set<String>()
        for dict in raw {
            guard let item = WatchEduItem(from: dict) else { continue }
            guard seenKeys.insert(Self.normalizedId(item.id)).inserted else { continue }
            parsed.append(item)
        }
        guard !parsed.isEmpty else { return }

        var merged = parsed
        let existing = items.filter { !seenKeys.contains(Self.normalizedId($0.id)) }
        merged += existing

        // 純粋にタイムスタンプ降順（直近の投稿を常に先頭に表示）
        merged.sort { $0.timestamp > $1.timestamp }
        merged = Array(merged.prefix(50))

        items = merged
        isLoading = false
        isSyncing = false
        syncTimeoutTask?.cancel()
        retryTask?.cancel()

        if let data = try? JSONEncoder().encode(merged) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    // MARK: - Watch → iOS: フィードリクエスト

    /// 同期を要求する。
    /// 1. まず applicationContext を即反映（Phone の起動状態に依存しない・オフラインでも表示可能）
    /// 2. その上で iPhone が届く範囲なら request_edu を送って最新データを取りに行く
    ///    （旧実装はコンテキストがあると即 return していたため、kfit 側で投稿した直後など
    ///      コンテキストが古い場合に手動同期しても新データが来なかった）
    /// replyHandler は使わない（往復タイムアウト WCErrorCodeTransferTimedOut 回避）。
    /// - Parameter playHaptic: 手動操作時のみ true（ライフサイクル起点の自動同期では鳴らさない）
    func requestSync(playHaptic: Bool = true) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        isSyncing = true
        if playHaptic { WKInterfaceDevice.current().play(.click) }

        // applicationContext を即反映（Phone の起動状態に依存しない）
        let ctx = session.receivedApplicationContext
        wcLogger.info("requestSync: isReachable=\(session.isReachable) receivedContextKeys=\(ctx.keys.sorted())")
        if let raw = ctx["eduItems"] as? [[String: Any]], !raw.isEmpty {
            applyItems(raw)
        }

        // iPhone が届く範囲なら常に最新データをリクエストする
        // （iOS 側は request_edu 受信で Firestore からも補完して context を更新する）
        if session.isReachable {
            session.sendMessage(["action": "request_edu"], replyHandler: nil, errorHandler: { error in
                wcLogger.error("requestSync: sendMessage error=\(error.localizedDescription)")
            })
        }

        isSyncing = false

        // データが空なら自動再試行をスケジュール
        if items.isEmpty { scheduleRetryIfNeeded() }
    }

    // MARK: - 自動再試行

    func scheduleRetryIfNeeded() {
        guard items.isEmpty else { return }
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            // 5秒後に1回目の再試行
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.items.isEmpty else { return }
                self.requestSync()
            }
            // さらに 15秒後に2回目の再試行
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.items.isEmpty else { return }
                self.requestSync()
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchEduStore: WCSessionDelegate {

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        wcLogger.info("activationDidCompleteWith: state=\(activationState.rawValue) error=\(error?.localizedDescription ?? "nil") isReachable=\(session.isReachable)")
        Task { @MainActor in
            self.isLoading = false
            guard activationState == .activated else {
                self.scheduleRetryIfNeeded()
                return
            }

            // applicationContext が既にあれば即反映（Phone 未起動・未接続でも動作）
            let ctx = session.receivedApplicationContext
            if let raw = ctx["eduItems"] as? [[String: Any]], !raw.isEmpty {
                self.applyItems(raw)
                return
            }

            // コンテキストが空で Phone が起動中なら軽量リクエスト
            // replyHandler/errorHandler を nil にしてタイムアウトを完全に防ぐ
            if session.isReachable {
                session.sendMessage(["action": "request_edu"],
                                    replyHandler: nil,
                                    errorHandler: nil)
            }

            // データが届かない場合の自動再試行
            self.scheduleRetryIfNeeded()
        }
    }

    // sendMessage（replyHandler なし）で受信
    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any]) {
        if let raw = message["eduItems"] as? [[String: Any]] {
            Task { @MainActor in self.applyItems(raw) }
        }
        // action: request_edu を iPhone 側が受け取るケースは iOS の delegate が処理
    }

    // sendMessage（replyHandler 付き）で受信
    // ※ iOS 側から来ることはほぼないが、念のため対応
    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        if let raw = message["eduItems"] as? [[String: Any]] {
            Task { @MainActor in self.applyItems(raw) }
            replyHandler(["status": "ok"])
        } else {
            replyHandler([:])
        }
    }

    // updateApplicationContext で受信
    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let raw = applicationContext["eduItems"] as? [[String: Any]] else { return }
        Task { @MainActor in self.applyItems(raw) }
    }

    // transferUserInfo で受信（キュー保証配信）
    nonisolated func session(_ session: WCSession,
                             didReceiveUserInfo userInfo: [String: Any]) {
        guard let raw = userInfo["eduItems"] as? [[String: Any]] else { return }
        Task { @MainActor in self.applyItems(raw) }
    }
}
