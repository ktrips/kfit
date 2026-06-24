import Foundation
import StoreKit
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - PremiumManager

@MainActor
final class PremiumManager: ObservableObject {
    static let shared = PremiumManager()

    // MARK: - Published
    @Published var isPremium: Bool = false
    @Published var isAdmin: Bool = false
    @Published var secretCode: String = "kfit5526"
    @Published var availableProducts: [Product] = []
    @Published var purchaseError: String? = nil
    @Published var isLoadingPurchase: Bool = false
    @Published var codeUnlocked: Bool = false  // コードによるアンロック

    // MARK: - Constants
    static let adminEmail = "kenichiyoshida13@gmail.com"
    static let productIDs = ["fitingo_premium_monthly", "fitingo_premium_yearly"]

    private let premiumCodeKey   = "fitingo_premium_code_unlocked"
    private let premiumCodeValue = "fitingo_premium_code_value"
    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Setup（起動時に呼ぶ）

    func setup() async {
        checkAdminStatus()
        await fetchSecretCode()
        checkCodeUnlock()
        await checkSubscription()
        await loadProducts()
    }

    // MARK: - Admin

    func checkAdminStatus() {
        let email = Auth.auth().currentUser?.email ?? ""
        isAdmin = (email.lowercased() == Self.adminEmail.lowercased())
        if isAdmin { isPremium = true }
    }

    // MARK: - Firestore Secret Code

    func fetchSecretCode() async {
        do {
            let doc = try await db.collection("appConfig").document("premium").getDocument()
            if let code = doc.data()?["secretCode"] as? String, !code.isEmpty {
                secretCode = code
            }
        } catch {
            // ネットワーク不可時はデフォルト値を維持
        }
    }

    /// シークレットコード入力 → Premium解放
    @discardableResult
    func unlockWithCode(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == secretCode else { return false }
        UserDefaults.standard.set(true,    forKey: premiumCodeKey)
        UserDefaults.standard.set(trimmed, forKey: premiumCodeValue)
        codeUnlocked = true
        isPremium    = true
        return true
    }

    func checkCodeUnlock() {
        guard UserDefaults.standard.bool(forKey: premiumCodeKey) else { return }
        let stored = UserDefaults.standard.string(forKey: premiumCodeValue) ?? ""
        if stored == secretCode {
            codeUnlocked = true
            isPremium    = true
        } else {
            // コードが変更された → 再入力が必要
            UserDefaults.standard.removeObject(forKey: premiumCodeKey)
            UserDefaults.standard.removeObject(forKey: premiumCodeValue)
            codeUnlocked = false
        }
    }

    func revokeCodeUnlock() {
        UserDefaults.standard.removeObject(forKey: premiumCodeKey)
        UserDefaults.standard.removeObject(forKey: premiumCodeValue)
        codeUnlocked = false
        // サブスクリプションがなければPremium解除
        Task { await checkSubscription() }
    }

    /// Admin専用: シークレットコードを変更
    func updateSecretCode(_ newCode: String) async -> Bool {
        guard isAdmin else { return false }
        let trimmed = newCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            try await db.collection("appConfig").document("premium")
                .setData(["secretCode": trimmed], merge: true)
            secretCode = trimmed
            return true
        } catch {
            return false
        }
    }

    // MARK: - StoreKit 2

    func loadProducts() async {
        do {
            let products = try await Product.products(for: Set(Self.productIDs))
            availableProducts = products.sorted { $0.price < $1.price }
        } catch {
            print("[Premium] Product load failed: \(error)")
        }
    }

    func purchase(_ product: Product) async {
        isLoadingPurchase = true
        purchaseError = nil
        defer { isLoadingPurchase = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let tx) = verification {
                    await tx.finish()
                    isPremium = true
                }
            case .userCancelled:
                break
            case .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func checkSubscription() async {
        var hasActive = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result,
               tx.productType == .autoRenewable,
               !tx.isUpgraded {
                hasActive = true
            }
        }
        if hasActive {
            isPremium = true
        } else if !codeUnlocked && !isAdmin {
            isPremium = false
        }
    }

    func restorePurchases() async {
        isLoadingPurchase = true
        defer { isLoadingPurchase = false }
        do {
            try await AppStore.sync()
            await checkSubscription()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    /// Premium機能を使えるかチェック（UIでのガード用）
    var canUsePremiumFeatures: Bool { isPremium }
}
