import Foundation
import Combine
import StoreKit

// MARK: - kmind 専用 PlusManager
// kfit の PremiumManager と同じ Firestore プロジェクトからシークレットコードを取得します。
// Firebase SDK 不要 — Firestore REST API で取得します。

@MainActor
final class PlusManager: ObservableObject {
    static let shared = PlusManager()

    @Published var isPlus: Bool = false
    @Published var codeUnlocked: Bool = false
    @Published var isLoadingPurchase: Bool = false
    @Published var purchaseError: String? = nil

    // kfit と同じデフォルト値（Firestore 取得失敗時のフォールバック）
    private var secretCode: String = "kfit5526"

    private let plusKey      = "kmind_is_plus"
    private let codeKey      = "kmind_plus_code_unlocked"
    private let codeValueKey = "kmind_plus_code_value"

    // Firestore REST API（kfitapp プロジェクト）
    private let firestoreURL = "https://firestore.googleapis.com/v1/projects/kfitapp/databases/(default)/documents/appConfig/plus"
    private let apiKey       = "AIzaSyBTuZi-YMZTwTqF5dhFs35MNHP-b7c9L_k"

    private init() {
        isPlus = UserDefaults.standard.bool(forKey: plusKey)
        checkCodeUnlock()
        Task {
            await fetchSecretCode()
            await checkEntitlement()
        }
    }

    // MARK: - Firestore REST でシークレットコードを取得
    func fetchSecretCode() async {
        guard var components = URLComponents(string: firestoreURL) else { return }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let fields = json["fields"] as? [String: Any],
               let codeField = fields["secretCode"] as? [String: Any],
               let code = codeField["stringValue"] as? String,
               !code.isEmpty {
                secretCode = code
                // 保存済みコードが更新後のコードと一致するか再検証
                checkCodeUnlock()
            }
        } catch {
            // ネットワークエラー時はフォールバック値を使用
        }
    }

    // MARK: - コードで Plus アンロック（kfit と同じコードが使える）
    @discardableResult
    func unlockWithCode(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == secretCode else {
            purchaseError = "コードが違います"
            return false
        }
        UserDefaults.standard.set(true,    forKey: codeKey)
        UserDefaults.standard.set(trimmed, forKey: codeValueKey)
        codeUnlocked = true
        isPlus       = true
        purchaseError = nil
        return true
    }

    func checkCodeUnlock() {
        guard UserDefaults.standard.bool(forKey: codeKey) else { return }
        let stored = UserDefaults.standard.string(forKey: codeValueKey) ?? ""
        if stored == secretCode {
            codeUnlocked = true
            isPlus       = true
        } else {
            UserDefaults.standard.removeObject(forKey: codeKey)
            UserDefaults.standard.removeObject(forKey: codeValueKey)
            codeUnlocked = false
        }
    }

    // MARK: - StoreKit 購入確認
    private func checkEntitlement() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result,
               tx.productID.hasPrefix("fitingo_plus") {
                isPlus = true
                UserDefaults.standard.set(true, forKey: plusKey)
                return
            }
        }
    }
}
