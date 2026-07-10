import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - AI カテゴリ

enum AICategory: String {
    case food   = "food"
    case edu    = "edu"
    case diet   = "diet"
    case general = "general"

    var displayName: String {
        switch self {
        case .food:    return "食事AI"
        case .edu:     return "語学AI"
        case .diet:    return "ダイエットAI"
        case .general: return "AI"
        }
    }
}

// MARK: - クォータ超過エラー

enum AIQuotaError: LocalizedError {
    /// 90秒モード中（全カテゴリ合計 1/日 超過）
    case ninetyModeExceeded
    /// フリーユーザーの日次カテゴリ上限
    case freeExceeded(category: AICategory)
    /// Plusユーザーの日次カテゴリ上限
    case plusExceeded(category: AICategory)

    var errorDescription: String? {
        switch self {
        case .ninetyModeExceeded:
            return "今日のAI枠は使いました。明日また試してね！\nAPIキーを登録すると何度でも使えます"
        case .freeExceeded(let cat):
            return "\(cat.displayName)の無料枠（1回/日）を使いました。\nPlusなら3回/日、APIキー登録で無制限になります"
        case .plusExceeded(let cat):
            return "\(cat.displayName)の今日の上限（3回/日）に達しました。\nAPIキーを登録すると無制限に使えます"
        }
    }

    /// Plusへのアップセルが適切か
    var shouldOfferPlus: Bool {
        if case .freeExceeded = self { return true }
        return false
    }

    /// APIキー登録を促すか
    var shouldOfferAPIKey: Bool { true }
}

// MARK: - AIQuotaManager

/// AI 利用クォータをサーバー（Firestore）に記録・チェックするマネージャ。
/// カスタム API キーも Firestore に保存し、aiProxy 経由で使用させる。
final class AIQuotaManager: ObservableObject {
    static let shared = AIQuotaManager()
    private let db = Firestore.firestore()

    // MARK: - 日次クォータ上限

    private let ninetyDailyLimit = 1   // 90秒モード中: 全カテゴリ合計
    private let freeDailyLimit   = 1   // フリー: カテゴリごと
    private let plusDailyLimit   = 3   // Plus: カテゴリごと

    // MARK: - カスタム API キー（@Published で設定画面と同期）

    @Published private(set) var customAPIKey: String = ""
    @Published private(set) var isLoadingKey: Bool = false
    @Published private(set) var isSavingKey:  Bool = false

    private init() { Task { await loadCustomAPIKey() } }

    // MARK: - クォータチェック（サーバー問い合わせ）

    /// AI 呼び出し前に使用量をチェックする。
    /// 超過時は AIQuotaError を throw、通過時は nil を返す。
    /// カスタムキーが設定されている場合は常に通過する。
    func checkQuota(category: AICategory, isNinetyMode: Bool, isPlus: Bool) async throws {
        guard customAPIKey.isEmpty else { return } // カスタムキーがあれば無制限

        guard let uid = Auth.auth().currentUser?.uid else { return }

        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let usageDoc = db.collection("users").document(uid)
            .collection("ai-usage").document("daily-\(today)")

        let snap = try await usageDoc.getDocument()
        let data = snap.data() ?? [:]

        if isNinetyMode {
            // 全カテゴリ合計
            let total = data.values.compactMap { $0 as? Int }.reduce(0, +)
            if total >= ninetyDailyLimit { throw AIQuotaError.ninetyModeExceeded }
        } else {
            let count = (data[category.rawValue] as? Int) ?? 0
            let limit = isPlus ? plusDailyLimit : freeDailyLimit
            if count >= limit {
                throw isPlus
                    ? AIQuotaError.plusExceeded(category: category)
                    : AIQuotaError.freeExceeded(category: category)
            }
        }
    }

    // MARK: - カスタム API キー 読み書き

    func loadCustomAPIKey() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoadingKey = true
        defer { isLoadingKey = false }
        let snap = try? await db.collection("users").document(uid)
            .collection("settings").document("ai").getDocument()
        let key = (snap?.data() ?? [:])["openaiApiKey"] as? String ?? ""
        await MainActor.run { self.customAPIKey = key }
    }

    func saveCustomAPIKey(_ key: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        await MainActor.run { isSavingKey = true }
        defer { Task { await MainActor.run { self.isSavingKey = false } } }
        try await db.collection("users").document(uid)
            .collection("settings").document("ai")
            .setData(["openaiApiKey": key.trimmingCharacters(in: .whitespaces)], merge: true)
        await MainActor.run { self.customAPIKey = key.trimmingCharacters(in: .whitespaces) }
    }

    func clearCustomAPIKey() async throws {
        try await saveCustomAPIKey("")
    }

    // MARK: - hasCustomKey ヘルパー

    var hasCustomKey: Bool { !customAPIKey.isEmpty }
}
