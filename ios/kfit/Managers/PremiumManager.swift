import Foundation
import Combine
import StoreKit
import FirebaseFirestore
import FirebaseAuth
#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

// MARK: - PlusManager
//
// Plus の根拠は次の 3 つだけ（サーバーの firebase/functions/plus.js と同じ判定）。
//   1. App Store の購入 — 端末の StoreKit で確認し、署名付き取引をサーバーで検証する
//   2. 管理者が付与したプロモ（無料の Plus ユーザー）— サーバーだけが users/{uid}.plusPromo を書く
//   3. 管理者本人
// users/{uid} の isPlus / plusPromo / plusAppStore はサーバー専用（firestore.rules で
// クライアントからの書き込みを禁止）。アプリはそれを読むだけで、自分では書かない。

final class PlusManager: ObservableObject {
    static let shared = PlusManager()

    // MARK: - Published（MainThread で更新）
    @Published var isPlus: Bool = false
    @Published var isAdmin: Bool = false
    /// Plus の根拠: "appstore" / "promo" / "admin"（Free なら nil）
    @Published var plusSource: String? = nil
    /// プロモ・購入の有効期限（無期限・不明なら nil）
    @Published var plusExpiresAt: Date? = nil
    @Published var availableProducts: [Product] = []
    @Published var purchaseError: String? = nil
    @Published var isLoadingPurchase: Bool = false
    /// 購入が保留中（ファミリー共有の「承認と購入のリクエスト」など）のときの案内
    @Published var purchaseNotice: String? = nil
    /// 商品情報の取得に失敗した（App Store Connect 未登録・通信不可など）
    @Published var productLoadFailed: Bool = false
    /// 商品ID → お試し期間（初回特典）の対象か
    @Published var introEligibility: [String: Bool] = [:]

    // MARK: - Constants
    static let adminEmail = "kenichiyoshida13@gmail.com"
    static let productIDs = ["fitingo_plus_monthly", "fitingo_plus_yearly"]

    private let db = Firestore.firestore()

    /// 端末の StoreKit で有効な購入があるか（オフラインでもすぐ反映するため）
    private var storeKitActive = false
    /// サーバーが判定した Plus 状態（プロモ・検証済みの購入）
    private var serverPlus = false
    private var serverSource: String? = nil
    private var serverExpiresAt: Date? = nil

    // TTL ガード: 1時間以内の再 setup() はネットワーク処理をスキップ
    private var lastSetupDate: Date? = nil
    private let setupTTL: TimeInterval = 3600

    /// 更新・返金・別端末での購入・承認待ちの承認などを受け取るリスナー。
    /// Apple はアプリ起動直後から Transaction.updates を監視することを求めている
    /// （監視しないと、自動更新や「承認と購入のリクエスト」の結果を取りこぼす）。
    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let tx) = result {
                    await tx.finish()
                }
                await self.checkSubscription()
            }
        }
    }

    // MARK: - Setup（起動時に呼ぶ）

    @MainActor
    func setup() async {
        checkAdminStatus()

        // ネットワーク処理は TTL 内ならスキップ
        if let last = lastSetupDate, Date().timeIntervalSince(last) < setupTTL {
            return
        }
        lastSetupDate = Date()
        await checkSubscription()
        await loadProducts()
    }

    @MainActor
    private func recompute() {
        isPlus = isAdmin || storeKitActive || serverPlus
        if isAdmin {
            plusSource = "admin"
            plusExpiresAt = nil
        } else if serverPlus {
            plusSource = serverSource
            plusExpiresAt = serverExpiresAt
        } else {
            plusSource = storeKitActive ? "appstore" : nil
            plusExpiresAt = nil
        }
    }

    // MARK: - Admin

    @MainActor
    func checkAdminStatus() {
        let email = Auth.auth().currentUser?.email ?? ""
        isAdmin = (email.lowercased() == Self.adminEmail.lowercased())
        recompute()
    }

    // MARK: - サーバーの Plus 状態

    /// users/{uid} のサーバー専用項目（plusPromo / plusAppStore）から Plus を判定する。
    /// 判定は firebase/functions/plus.js の plusStatusFromData と同じ（期限も見る）。
    @MainActor
    func refreshServerStatus() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            serverPlus = false; serverSource = nil; serverExpiresAt = nil
            recompute()
            return
        }
        guard let snap = try? await db.collection("users").document(uid).getDocument(),
              let data = snap.data() else { return }
        let now = Date()
        var plus = false, source: String? = nil, exp: Date? = nil
        if let promo = data["plusPromo"] as? [String: Any], promo["enabled"] as? Bool == true {
            let promoExp = (promo["expiresAt"] as? Timestamp)?.dateValue()
            if promoExp == nil || promoExp! > now { plus = true; source = "promo"; exp = promoExp }
        }
        if !plus, let store = data["plusAppStore"] as? [String: Any], store["revoked"] as? Bool != true,
           let storeExp = (store["expiresAt"] as? Timestamp)?.dateValue(), storeExp > now {
            plus = true; source = "appstore"; exp = storeExp
        }
        serverPlus = plus; serverSource = source; serverExpiresAt = exp
        recompute()
    }

    /// 署名付き取引をサーバーで検証し、サーバー側の Plus（AI の回数上限など）に反映する
    @MainActor
    private func verifyWithServer(_ signedTransactions: [String]) async {
        #if canImport(FirebaseFunctions)
        guard Auth.auth().currentUser != nil, !signedTransactions.isEmpty else { return }
        do {
            let fn = Functions.functions(region: "us-central1")
            _ = try await fn.httpsCallable("verifySubscription")
                .call(["signedTransactions": signedTransactions])
        } catch {
            dlog("[Plus] verifySubscription failed: \(error.localizedDescription)")
        }
        #endif
    }

    // MARK: - StoreKit 2

    @MainActor
    func loadProducts() async {
        do {
            let products = try await Product.products(for: Set(Self.productIDs))
            availableProducts = products.sorted { $0.price < $1.price }
            productLoadFailed = products.isEmpty
            var eligibility: [String: Bool] = [:]
            for p in products {
                if let sub = p.subscription, sub.introductoryOffer != nil {
                    eligibility[p.id] = await sub.isEligibleForIntroOffer
                }
            }
            introEligibility = eligibility
        } catch {
            productLoadFailed = true
            dlog("[Plus] Product load failed: \(error)")
        }
    }

    @MainActor
    func purchase(_ product: Product) async {
        isLoadingPurchase = true
        purchaseError = nil
        purchaseNotice = nil
        defer { isLoadingPurchase = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let tx):
                    await tx.finish()
                    storeKitActive = true
                    recompute()
                    await verifyWithServer([verification.jwsRepresentation])
                    await refreshServerStatus()
                case .unverified(_, let error):
                    // 署名を検証できない取引は有効にしない
                    purchaseError = "購入を確認できませんでした（\(error.localizedDescription)）"
                }
            case .userCancelled:
                break
            case .pending:
                // 承認後は Transaction.updates 経由で有効になる
                purchaseNotice = "購入の承認待ちです。承認されると自動で Plus が有効になります。"
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    /// 端末の購入状態を確認し、有効な購入はサーバーでも検証してから、サーバーの判定を読み直す
    @MainActor
    func checkSubscription() async {
        var active = false
        var signed: [String] = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result,
               tx.productType == .autoRenewable,
               Self.productIDs.contains(tx.productID),
               tx.revocationDate == nil,
               !tx.isUpgraded {
                active = true
                signed.append(result.jwsRepresentation)
            }
        }
        storeKitActive = active
        recompute()
        await verifyWithServer(signed)
        await refreshServerStatus()
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

    // MARK: - プロモ（無料の Plus ユーザー）管理：管理者のみ

    #if canImport(FirebaseFunctions)
    struct PromoUser: Identifiable {
        let id: String
        let email: String
        let expiresAt: Date?
        let note: String
    }

    /// 指定メールのユーザーにプロモを付与（enabled=false で解除）。days=0 は無期限。
    /// 権限はサーバー（setPromoUser）が検証済み ID トークンのメールで判定する。
    func setPromoUser(email: String, enabled: Bool, days: Int, note: String = "") async throws -> String {
        let fn = Functions.functions(region: "us-central1")
        let result = try await fn.httpsCallable("setPromoUser").call([
            "email": email, "enabled": enabled, "days": days, "note": note,
        ])
        let data = result.data as? [String: Any] ?? [:]
        let target = data["email"] as? String ?? email
        return enabled ? "\(target) を Plus（プロモ）にしました" : "\(target) のプロモを解除しました"
    }

    func listPromoUsers() async throws -> [PromoUser] {
        let fn = Functions.functions(region: "us-central1")
        let result = try await fn.httpsCallable("listPromoUsers").call([String: Any]())
        let rows = (result.data as? [String: Any])?["users"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let uid = row["uid"] as? String else { return nil }
            let exp = (row["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
            return PromoUser(id: uid, email: row["email"] as? String ?? "", expiresAt: exp,
                             note: row["note"] as? String ?? "")
        }
    }
    #endif

    // MARK: - Helpers

    var canUsePlusFeatures: Bool { isPlus }
}
