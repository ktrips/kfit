import Foundation
import StoreKit
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - PlusManager

final class PlusManager: ObservableObject {
    static let shared = PlusManager()

    // MARK: - Published（MainThread で更新）
    @Published var isPlus: Bool = false
    @Published var isAdmin: Bool = false
    @Published var secretCode: String = "kfit5526"
    @Published var availableProducts: [Product] = []
    @Published var purchaseError: String? = nil
    @Published var isLoadingPurchase: Bool = false
    @Published var codeUnlocked: Bool = false

    // MARK: - Constants
    static let adminEmail = "kenichiyoshida13@gmail.com"
    static let productIDs = ["fitingo_plus_monthly", "fitingo_plus_yearly"]

    private let plusCodeKey   = "fitingo_plus_code_unlocked"
    private let plusCodeValue = "fitingo_plus_code_value"
    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Setup（起動時に呼ぶ）

    @MainActor
    func setup() async {
        checkAdminStatus()
        await fetchSecretCode()
        checkCodeUnlock()
        await checkSubscription()
        await loadProducts()
    }

    // MARK: - Admin

    @MainActor
    func checkAdminStatus() {
        let email = Auth.auth().currentUser?.email ?? ""
        isAdmin = (email.lowercased() == Self.adminEmail.lowercased())
        if isAdmin { isPlus = true }
    }

    // MARK: - Firestore Secret Code

    @MainActor
    func fetchSecretCode() async {
        do {
            let doc = try await db.collection("appConfig").document("plus").getDocument()
            if let code = doc.data()?["secretCode"] as? String, !code.isEmpty {
                secretCode = code
            } else {
                let legacy = try await db.collection("appConfig").document("premium").getDocument()
                if let code = legacy.data()?["secretCode"] as? String, !code.isEmpty {
                    secretCode = code
                }
            }
        } catch {
            // ネットワーク不可時はデフォルト値を維持
        }
    }

    /// シークレットコード入力 → Plus解放
    @discardableResult
    @MainActor
    func unlockWithCode(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == secretCode else { return false }
        UserDefaults.standard.set(true,    forKey: plusCodeKey)
        UserDefaults.standard.set(trimmed, forKey: plusCodeValue)
        codeUnlocked = true
        isPlus       = true
        return true
    }

    @MainActor
    func checkCodeUnlock() {
        guard UserDefaults.standard.bool(forKey: plusCodeKey) else { return }
        let stored = UserDefaults.standard.string(forKey: plusCodeValue) ?? ""
        if stored == secretCode {
            codeUnlocked = true
            isPlus       = true
        } else {
            UserDefaults.standard.removeObject(forKey: plusCodeKey)
            UserDefaults.standard.removeObject(forKey: plusCodeValue)
            codeUnlocked = false
        }
    }

    @MainActor
    func revokeCodeUnlock() {
        UserDefaults.standard.removeObject(forKey: plusCodeKey)
        UserDefaults.standard.removeObject(forKey: plusCodeValue)
        codeUnlocked = false
        Task { await checkSubscription() }
    }

    /// Admin専用: シークレットコードを変更
    @MainActor
    func updateSecretCode(_ newCode: String) async -> Bool {
        // setup() 前に呼ばれた場合も確実に管理者確認
        checkAdminStatus()
        guard isAdmin else {
            print("[PlusManager] updateSecretCode failed: not admin (email=\(Auth.auth().currentUser?.email ?? "nil"))")
            return false
        }
        let trimmed = newCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            try await db.collection("appConfig").document("plus")
                .setData(["secretCode": trimmed], merge: true)
            secretCode = trimmed
            print("[PlusManager] Secret code updated to: \(trimmed)")
            return true
        } catch {
            print("[PlusManager] Firestore write failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - StoreKit 2

    @MainActor
    func loadProducts() async {
        do {
            let products = try await Product.products(for: Set(Self.productIDs))
            availableProducts = products.sorted { $0.price < $1.price }
        } catch {
            print("[Plus] Product load failed: \(error)")
        }
    }

    @MainActor
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
                    isPlus = true
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

    @MainActor
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
            isPlus = true
        } else if !codeUnlocked && !isAdmin {
            isPlus = false
        }
    }

    @MainActor
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

    var canUsePlusFeatures: Bool { isPlus }
}
