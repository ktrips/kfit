import Foundation
import WatchConnectivity
import UIKit
import Combine

/// kedu iOS → keduWatch データ送信（WatchConnectivity）
/// タイムアウト対策：
///   - sendMessage はサムネイルなしの軽量ペイロードのみ
///   - transferUserInfo はキューが空の場合のみ送信
///   - replyHandler 不使用（Watch 側との往復タイムアウト回避）
///   - EduLogManager.$history を Combine で監視し、View に依存せず自動同期
@MainActor
final class WatchEduSender: NSObject {
    static let shared = WatchEduSender()

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }
    private var debounceTask: Task<Void, Never>?
    private var historyObserver: AnyCancellable?

    // MARK: - アクティベート

    func activate() {
        guard let session else { return }
        if !(session.delegate is WatchEduSender) {
            session.delegate = self
        }
        if session.activationState != .activated {
            session.activate()
        } else {
            // 蓄積した transferUserInfo キューをキャンセル（旧実装の残滓を除去）
            clearPendingUserInfoTransfers()
            sendCachedItems()
        }

        // EduLogManager の履歴変化を Combine で監視し、View に依存しない自動同期
        if historyObserver == nil {
            historyObserver = EduLogManager.shared.$history
                .debounce(for: .seconds(0.8), scheduler: RunLoop.main)
                .sink { [weak self] items in
                    guard let self, !items.isEmpty else { return }
                    self.sendEduItems(items)
                }
        }
    }

    /// 以前の実装で蓄積した transferUserInfo キューを全てキャンセル
    private func clearPendingUserInfoTransfers() {
        guard let session else { return }
        for transfer in session.outstandingUserInfoTransfers {
            transfer.cancel()
        }
    }

    // MARK: - デバウンス付き送信（500ms 以内の重複をまとめる）

    func sendEduItemsDebounced(_ items: [EduLogHistoryItem]) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            sendEduItems(items)
        }
    }

    // MARK: - 配信（applicationContext が主経路、sendMessage はリアルタイム補助）

    func sendEduItems(_ items: [EduLogHistoryItem]) {
        guard let session, session.activationState == .activated else { return }

        // フレーズあり優先、最大 20 件に制限（ペイロードサイズ抑制）
        let sorted     = items.sorted { $0.timestamp > $1.timestamp }
        let withPhrase = sorted.filter { !($0.extractedPhrase ?? "").isEmpty }
        let others     = sorted.filter {  ($0.extractedPhrase ?? "").isEmpty }
        let combined   = Array((withPhrase + others).prefix(20))
        guard !combined.isEmpty else { return }

        let slimDicts = makeSlimDicts(from: combined)

        // ── 1. applicationContext: バックグラウンド配信（主経路・常に実行）
        //    Phone 未接続でも Watch 側に届き、Watch 再起動後にも残る
        tryContext(session: session, payload: slimDicts)

        // ── 2. sendMessage: Watch がフォアグラウンドの時のリアルタイム補助
        //    replyHandler と errorHandler を両方 nil にしてタイムアウト通知を防ぐ
        //    （WCErrorCodeTransferTimedOut は errorHandler が非 nil の時に通知される）
        if session.isReachable {
            session.sendMessage(["eduItems": slimDicts],
                                replyHandler: nil,
                                errorHandler: nil)
        }

        // ── transferUserInfo は使用しない ──
        // transferUserInfo はキューに蓄積され、大量に溜まるとデバイス間通信を圧迫する。
        // applicationContext で充分（最新状態のみ保持・自動上書き）。
    }

    // MARK: - 辞書生成（サムネイルなし・軽量）

    private func makeSlimDicts(from items: [EduLogHistoryItem]) -> [[String: Any]] {
        items.map { item in
            var dict: [String: Any] = [
                "id":            item.id,
                "phrase":        item.extractedPhrase ?? "",
                "langCode":      item.extractedLanguageCode ?? "en",
                "translationJA": item.translationJA ?? "",
                "activityName":  item.activityName,
                "timestamp":     item.timestamp.timeIntervalSince1970,
            ]
            // 例文（最大3件）を配列で送信。後方互換のため先頭1件を exampleText にも設定
            if let examples = item.exampleSentences, !examples.isEmpty {
                let capped = examples.prefix(3)
                dict["exampleTexts"]       = capped.map { $0.text }
                dict["exampleTrans"]       = capped.map { $0.translationJA ?? "" }
                dict["exampleText"]        = capped.first?.text ?? ""
                dict["exampleTranslation"] = capped.first?.translationJA ?? ""
            }
            // サービス名（読書・EDU の場合）
            if let title = item.sharedTitle, !title.isEmpty {
                dict["sharedTitle"] = title
            }
            if let url = item.sharedUrl {
                dict["sharedUrl"] = url
            }
            return dict
        }
    }

    // MARK: - applicationContext 送信

    private func tryContext(session: WCSession, payload: [[String: Any]]) {
        do {
            try session.updateApplicationContext(["eduItems": payload])
        } catch {
            // 65KB 超過時は件数を半分に削って再試行
            let half = Array(payload.prefix(payload.count / 2))
            if !half.isEmpty {
                try? session.updateApplicationContext(["eduItems": half])
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchEduSender: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        guard activationState == .activated else { return }
        // 蓄積した古い transferUserInfo キューをキャンセル
        for transfer in session.outstandingUserInfoTransfers { transfer.cancel() }
        Task { @MainActor in self.sendCachedItems() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// Watch からの「フィードをください」リクエストを受信（replyHandler なし版）
    /// Watch 側が `sendMessage(..., replyHandler: nil, errorHandler: nil)` で送る場合はここに届く
    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any]) {
        guard (message["action"] as? String) == "request_edu" else { return }
        Task { @MainActor in self.sendCachedItems() }
    }

    /// Watch からの replyHandler 付きリクエスト（念のため残す）
    /// Watch 側では replyHandler なしで呼ぶが、古いビルドとの後方互換用
    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        replyHandler(["status": "ok"])  // 即座に返してタイムアウトを防ぐ
        guard (message["action"] as? String) == "request_edu" else { return }
        Task { @MainActor in self.sendCachedItems() }
    }
}

// MARK: - キャッシュ再送

extension WatchEduSender {
    /// EduLogManager のローカル履歴を Watch へ送信
    func sendCachedItems() {
        let live = EduLogManager.shared.history
        if !live.isEmpty {
            sendEduItems(live)
            return
        }
        // in-memory が空なら UserDefaults から復元
        let cacheKey = "eduLogHistory_v1"
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let history = try? JSONDecoder().decode([EduLogHistoryItem].self, from: data),
           !history.isEmpty {
            sendEduItems(history)
        }
    }
}
