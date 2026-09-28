import SwiftUI
import StoreKit
// kedu/kmind は FirebaseFunctions SDK をリンクしていないため canImport で分岐
// （PremiumView.swift は両ターゲットで共有コンパイルされる）
#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

// MARK: - Free vs Plus 比較データ

private struct PlanFeature: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let category: String
    let title: String
    let free: FeatureValue
    let plus: FeatureValue
    var plusNote: String? = nil  // ※注意書き

    enum FeatureValue {
        case yes, no, text(String)
        var label: String {
            switch self { case .yes: return "✓"; case .no: return "—"; case .text(let s): return s }
        }
        var color: Color {
            switch self {
            case .yes: return Color.duoGreen
            case .no: return Color(.systemGray4)
            case .text: return Color(hex: "#FF8C00")
            }
        }
        var isNo: Bool { if case .no = self { return true }; return false }
    }
}

private let planFeatures: [PlanFeature] = [
    // 全般
    PlanFeature(icon: "nosign",       iconColor: Color(hex: "#555555"),
                category: "全般", title: "広告なし",                        free: .no,              plus: .yes),
    PlanFeature(icon: "gearshape.2.fill", iconColor: Color(hex: "#555555"),
                category: "全般", title: "全機能フルアクセス",               free: .no,              plus: .yes),

    // FIT
    PlanFeature(icon: "figure.run",   iconColor: Color(hex: "#FF4B4B"),
                category: "FIT", title: "アクティビティ記録",          free: .yes,             plus: .yes),
    PlanFeature(icon: "chart.bar.fill", iconColor: Color(hex: "#FF4B4B"),
                category: "FIT", title: "詳細アクティビティ分析",       free: .no,              plus: .yes,
                plusNote: "※ AI機能はAPIキー設定が必要"),
    PlanFeature(icon: "target",       iconColor: Color(hex: "#FF4B4B"),
                category: "FIT", title: "目標自動調整提案",             free: .no,              plus: .yes,
                plusNote: "※ AI機能はAPIキー設定が必要"),

    // FOOD
    PlanFeature(icon: "fork.knife",   iconColor: Color.duoGreen,
                category: "FOOD", title: "食事ログ記録",                free: .yes,             plus: .yes),
    PlanFeature(icon: "camera.fill",  iconColor: Color.duoGreen,
                category: "FOOD", title: "フォトログ AI 栄養解析",      free: .no,              plus: .yes,
                plusNote: "※ AI機能はAPIキー設定が必要"),
    PlanFeature(icon: "doc.text.fill", iconColor: Color.duoGreen,
                category: "FOOD", title: "週次・月次 食事レポート",      free: .no,              plus: .yes),

    // MIND（タブ全体がPlus限定）
    PlanFeature(icon: "moon.fill",    iconColor: Color(hex: "#CE82FF"),
                category: "MIND", title: "睡眠・マインドフル記録",      free: .no,              plus: .yes),
    PlanFeature(icon: "sparkles",     iconColor: Color(hex: "#CE82FF"),
                category: "MIND", title: "AI コーチングコメント",       free: .no,              plus: .yes,
                plusNote: "※ AI機能はAPIキー設定が必要"),

    // BOOKS
    PlanFeature(icon: "books.vertical.fill", iconColor: Color(hex: "#FF7A00"),
                category: "BOOKS", title: "Kindle本をWebで全文読む",   free: .no,              plus: .yes),
    PlanFeature(icon: "ipad.and.iphone", iconColor: Color(hex: "#FF7A00"),
                category: "BOOKS", title: "書籍のオフライン保存",       free: .no,              plus: .yes),

    // TOMO
    PlanFeature(icon: "person.2.fill", iconColor: Color.duoBlue,
                category: "TOMO", title: "友達追加",                    free: .text("3人まで"), plus: .text("無制限")),
    PlanFeature(icon: "eye.fill",     iconColor: Color.duoBlue,
                category: "TOMO", title: "フレンドフィード閲覧",        free: .text("一部"),    plus: .text("すべて")),

    // Apple Watch
    PlanFeature(icon: "applewatch", iconColor: Color(hex: "#333333"),
                category: "Watch", title: "Apple Watchアプリ",       free: .no,              plus: .yes),
    PlanFeature(icon: "figure.run.circle.fill", iconColor: Color(hex: "#333333"),
                category: "Watch", title: "Watchモーション運動検出",   free: .no,              plus: .yes),
    PlanFeature(icon: "chart.bar.xaxis", iconColor: Color(hex: "#333333"),
                category: "Watch", title: "Watchウィジェット",         free: .no,              plus: .yes),

    // カスタマイズ
    PlanFeature(icon: "paintpalette.fill", iconColor: Color(hex: "#FF7A6B"),
                category: "カスタマイズ", title: "スパイラルテーマ",     free: .text("1種"),     plus: .text("10種以上")),
    PlanFeature(icon: "rectangle.stack.fill", iconColor: Color(hex: "#FF7A6B"),
                category: "カスタマイズ", title: "Plusウィジェット",     free: .no,              plus: .yes),
    PlanFeature(icon: "bell.badge.fill", iconColor: Color(hex: "#FF7A6B"),
                category: "カスタマイズ", title: "時間帯リマインダー",   free: .text("1スロット"), plus: .text("全スロット")),
]

// MARK: - PlusView

// MARK: - Admin専用: テスター状況レポート（getRetentionDiagnostics Cloud Function の結果）

private struct RetentionDiagnosticRow: Identifiable {
    let id: String
    let username: String?
    let totalPoints: Int
    let streak: Int
    let firstActiveDay: String?
    let totalActiveDays: Int
    let firstSetSeconds: Int?
    let platforms: [String]
    let firstPlatform: String?
    let lastPlatform: String?
    let firstSource: String?
    let firstReferrer: String?
    let status: String

    var statusLabel: String {
        switch status {
        case "preExisting":      return "🚫 既存ユーザー除外"
        case "recorded":         return "✅ 記録済み"
        case "nonTrainingFirst": return "⚠️ 非トレーニング初回"
        default:                 return "➖ 活動記録なし"
        }
    }

    /// プラットフォーム表示（利用したことのある全プラットフォーム。iOS/Web両方使っていれば両方表示）
    /// platforms/firstSource は今回追加したフィールドのため、既存ユーザーの過去データには残っていない。
    /// 次回そのユーザーが何か活動した時点で自動的に記録される（既存データを遡って復元することはできない）。
    var platformsLabel: String {
        if !platforms.isEmpty {
            return platforms.map { $0 == "ios" ? "📱 iOS" : $0 == "web" ? "🌐 Web" : $0 }.joined(separator: "  ")
        }
        return status == "preExisting" ? "対象外" : "未記録（次回活動時に記録）"
    }

    /// 初回アクセス元の日本語ラベル（Web版 classifySource の分類に対応）
    var sourceLabel: String {
        guard let source = firstSource, !source.isEmpty else {
            return status == "preExisting" ? "対象外" : "未記録（次回活動時に記録）"
        }
        if source == "ios-app" { return "📱 iOSアプリ（TestFlightのため詳細元は取得不可）" }
        if source == "direct" { return "🔗 直リンク・ブックマーク" }
        if source == "webapp" { return "🌐 Fitingoウェブアプリ内から" }
        if source.hasPrefix("sns:") { return "📢 SNS(\(source.dropFirst(4)))" }
        if source.hasPrefix("utm:") { return "🎯 広告/キャンペーン(\(source.dropFirst(4)))" }
        if source.hasPrefix("referral:") { return "↪️ 外部サイト(\(source.dropFirst(9)))" }
        return source
    }
}

private struct RetentionDiagnosticSummary {
    let total: Int
    let preExisting: Int
    let nonTrainingFirst: Int
    let recorded: Int
    let noActivity: Int
}

struct PlusView: View {
    @StateObject private var plus = PlusManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var retentionRows: [RetentionDiagnosticRow] = []
    @State private var retentionSummary: RetentionDiagnosticSummary? = nil
    @State private var isLoadingRetention: Bool = false
    @State private var retentionError: String? = nil
    @State private var streakInput: String = ""
    @State private var isSavingStreak: Bool = false
    @State private var streakResult: String? = nil
    @State private var showManageSubscriptions: Bool = false
    @State private var selectedTab: PlusTab = .compare

    enum PlusTab: String, CaseIterable {
        case compare = "プランを比較"
        case upgrade = "アップグレード"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerSection
                tabBar
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        switch selectedTab {
                        case .compare: compareSection
                        case .upgrade: upgradeSection
                        }
                        if plus.isAdmin { adminSection }
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
            .background(Color.duoBg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .foregroundColor(Color.duoGreen)
                }
            }
        }
        .task { await plus.setup() }
    }

    // MARK: - ヘッダー

    private var headerSection: some View {
        Group {
            if plus.isPlus {
                HStack(spacing: 8) {
                    PlusBadge(size: 22)
                    Text("Fitingo Plus 有効中")
                        .font(.system(size: 15, weight: .black))
                        .foregroundColor(Color(hex: "#FF8C00"))
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Color(hex: "#FFD700").opacity(0.12))
            } else {
                HStack(spacing: 10) {
                    PlusBadge(size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Fitingo Plus")
                            .font(.system(size: 16, weight: .black))
                            .foregroundColor(Color(hex: "#FF8C00"))
                        Text("月額¥480〜 · 7日間無料トライアル")
                            .font(.system(size: 11))
                            .foregroundColor(Color.duoSubtitle)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(hex: "#FFD700").opacity(0.10))
            }
        }
    }

    // MARK: - タブバー

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(PlusTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
                } label: {
                    VStack(spacing: 4) {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: selectedTab == tab ? .bold : .regular))
                            .foregroundColor(selectedTab == tab ? Color(hex: "#FF8C00") : Color.duoSubtitle)
                        Rectangle()
                            .fill(selectedTab == tab ? Color(hex: "#FF8C00") : Color.clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.plain)
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - アップグレードボタン（比較画面の上下に共通利用）

    private var upgradeButtonInline: some View {
        Group {
            if !plus.isPlus {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = .upgrade }
                } label: {
                    HStack(spacing: 8) {
                        PlusBadge(size: 16)
                        Text("Plusにアップグレード")
                            .font(.system(size: 15, weight: .black))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "#FF8C00"), Color(hex: "#FFB347")],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: Color(hex: "#FF8C00").opacity(0.35), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - プラン比較タブ

    private var compareSection: some View {
        VStack(spacing: 16) {
            // 上部アップグレードボタン
            upgradeButtonInline

            // テーブルヘッダー行
            HStack(spacing: 0) {
                Text("機能")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.duoSubtitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Free")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color.duoSubtitle)
                    .frame(width: 56, alignment: .center)
                HStack(spacing: 3) {
                    PlusBadge(size: 14)
                    Text("Plus")
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(Color(hex: "#FF8C00"))
                }
                .frame(width: 72, alignment: .center)
            }
            .padding(.horizontal, 14)

            // カテゴリ別テーブル
            let categories = ["全般", "FIT", "FOOD", "MIND", "BOOKS", "TOMO", "カスタマイズ"]
            ForEach(categories, id: \.self) { cat in
                featureCategoryCard(category: cat,
                    features: planFeatures.filter { $0.category == cat })
            }

            // AI注意書き
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color.duoBlue)
                    Text("AIについて")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.duoBlue)
                }
                Text("AI機能（栄養解析・コーチング・提案）は誰でも1日1回無料。\nPlusなら3回/日、APIキー登録で無制限（自己負担）。")
                    .font(.system(size: 11))
                    .foregroundColor(Color.duoSubtitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color.duoBlue.opacity(0.06))
            .cornerRadius(10)

            Text("* 全機能はサブスクリプションまたはPlusコードで解放できます")
                .font(.system(size: 10))
                .foregroundColor(Color.duoSubtitle)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // 下部アップグレードボタン
            upgradeButtonInline
        }
    }

    private func featureCategoryCard(category: String, features: [PlanFeature]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(category)
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(features.first?.iconColor ?? Color.duoGreen)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background((features.first?.iconColor ?? Color.duoGreen).opacity(0.08))

            ForEach(Array(features.enumerated()), id: \.element.id) { idx, feat in
                if idx > 0 { Divider().padding(.leading, 44) }
                featureRow(feat)
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(14)
    }

    private func featureRow(_ feat: PlanFeature) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: feat.icon)
                    .font(.system(size: 13))
                    .foregroundColor(feat.iconColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(feat.title)
                        .font(.system(size: 13))
                        .foregroundColor(Color.duoDark)
                    if let note = feat.plusNote {
                        Text(note)
                            .font(.system(size: 9))
                            .foregroundColor(Color.duoSubtitle)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Free列
            Text(feat.free.label)
                .font(.system(size: 12, weight: feat.free.isNo ? .regular : .bold))
                .foregroundColor(feat.free.color)
                .frame(width: 56, alignment: .center)

            // Plus列
            Group {
                if case .yes = feat.plus {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "#FF8C00"))
                } else {
                    Text(feat.plus.label)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: "#FF8C00"))
                }
            }
            .frame(width: 72, alignment: .center)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: - アップグレードタブ

    private var upgradeSection: some View {
        VStack(spacing: 16) {
            if plus.isPlus {
                plusActiveCard
            } else {
                purchaseCardsSection
            }
        }
    }

    private var plusSourceLabel: String {
        let exp = plus.plusExpiresAt.map { "（\($0.formatted(date: .abbreviated, time: .omitted))まで）" } ?? ""
        switch plus.plusSource {
        case "admin": return "Adminアカウント"
        case "promo": return "プロモで有効" + exp
        default: return "サブスクリプション有効" + exp
        }
    }

    private var plusActiveCard: some View {
        VStack(spacing: 12) {
            PlusBadge(size: 50)
            Text("Fitingo Plus 有効中")
                .font(.system(size: 20, weight: .black))
                .foregroundColor(Color(hex: "#FF8C00"))
            Text(plusSourceLabel)
                .font(.system(size: 13))
                .foregroundColor(Color.duoSubtitle)
            if plus.plusSource == "appstore" {
                Button { showManageSubscriptions = true } label: {
                    Label("サブスクリプションを管理・解約", systemImage: "creditcard")
                        .font(.system(size: 12))
                }
            }
        }
        .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(hex: "#FFD700").opacity(0.12))
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20)
            .stroke(Color(hex: "#FFD700").opacity(0.4), lineWidth: 1.5))
    }

    private var purchaseCardsSection: some View {
        VStack(spacing: 10) {
            if plus.availableProducts.isEmpty {
                if plus.productLoadFailed {
                    VStack(spacing: 8) {
                        Text("プランを読み込めませんでした。通信状態を確認してください。")
                            .font(.system(size: 12)).foregroundColor(Color.duoSubtitle)
                            .multilineTextAlignment(.center)
                        Button("再読み込み") { Task { await plus.loadProducts() } }
                            .font(.system(size: 13, weight: .bold))
                    }
                    .frame(maxWidth: .infinity).padding()
                } else {
                    ProgressView().tint(Color(hex: "#FF8C00")).frame(maxWidth: .infinity).padding()
                }
            } else {
                ForEach(plus.availableProducts, id: \.id) { product in
                    purchaseCard(product)
                }
            }
            Button {
                Task { await plus.restorePurchases() }
            } label: {
                Text("購入を復元する")
                    .font(.system(size: 12))
                    .foregroundColor(Color.duoSubtitle)
                    .frame(maxWidth: .infinity)
            }
            if let err = plus.purchaseError {
                Text(err).font(.system(size: 11)).foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            if let notice = plus.purchaseNotice {
                Text(notice).font(.system(size: 11)).foregroundColor(Color(hex: "#FF8C00"))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            subscriptionDisclosure
        }
    }

    /// App Store 審査ガイドライン 3.1.2 で求められる自動更新サブスクリプションの説明と規約リンク
    private var subscriptionDisclosure: some View {
        VStack(spacing: 6) {
            Text("お支払いは購入の確定時に Apple ID に請求されます。サブスクリプションは、現在の期間が終了する24時間前までに解約しない限り自動的に更新され、更新時に同じ料金が請求されます。解約や管理は、購入後に「設定」アプリの Apple ID ＞ サブスクリプションから行えます。無料トライアルの対象期間中に購入した場合、未使用のトライアル期間は失われます。")
                .font(.system(size: 10))
                .foregroundColor(Color.duoSubtitle)
                .multilineTextAlignment(.leading)
            HStack(spacing: 16) {
                Link("利用規約（EULA）", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("プライバシーポリシー", destination: URL(string: "https://fit.ktrips.net/privacy-policy/")!)
            }
            .font(.system(size: 11, weight: .semibold))
        }
        .padding(.top, 6)
    }

    /// 初回特典（無料トライアル等）の表示文。対象外・未設定なら nil
    private func introOfferText(_ product: Product) -> String? {
        guard let offer = product.subscription?.introductoryOffer,
              plus.introEligibility[product.id] == true else { return nil }
        let p = offer.period
        let unit: String
        switch p.unit {
        case .day: unit = "日間"
        case .week: unit = "週間"
        case .month: unit = "か月"
        case .year: unit = "年"
        @unknown default: unit = ""
        }
        let length = p.unit == .week && p.value == 1 ? "7日間" : "\(p.value)\(unit)"
        switch offer.paymentMode {
        case .freeTrial: return "\(length)無料トライアル付き"
        default: return "初回 \(length) \(offer.displayPrice)"
        }
    }

    /// 年額プランの「月あたり」と月額比の割引率（実際の価格から計算）
    private func yearlySavingsText(_ yearly: Product) -> String? {
        guard let monthly = plus.availableProducts.first(where: { $0.id.contains("monthly") }) else { return nil }
        let perMonth = yearly.price / 12
        let perMonthText = perMonth.formatted(yearly.priceFormatStyle)
        let monthlyYear = monthly.price * 12
        guard monthlyYear > 0 else { return "月あたり約\(perMonthText)" }
        let saving = NSDecimalNumber(decimal: (monthlyYear - yearly.price) / monthlyYear * 100).intValue
        return saving > 0 ? "月あたり約\(perMonthText) · 約\(saving)%お得" : "月あたり約\(perMonthText)"
    }

    private func purchaseCard(_ product: Product) -> some View {
        let isYearly = product.id.contains("yearly")
        return Button {
            Task { await plus.purchase(product) }
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(isYearly ? "年額プラン" : "月額プラン")
                            .font(.system(size: 15, weight: .black))
                            .foregroundColor(Color.duoDark)
                        if isYearly {
                            Text("おすすめ")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color(hex: "#FF8C00")).cornerRadius(6)
                        }
                    }
                    Text(isYearly ? (yearlySavingsText(product) ?? "1年ごとに自動更新") : "いつでも解約可")
                        .font(.system(size: 11)).foregroundColor(Color.duoSubtitle)
                    if let intro = introOfferText(product) {
                        Text(intro)
                            .font(.system(size: 10)).foregroundColor(Color(hex: "#FF8C00"))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if plus.isLoadingPurchase {
                        ProgressView()
                    } else {
                        Text(product.displayPrice)
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: "#FF8C00"))
                        Text(isYearly ? "/年" : "/月")
                            .font(.system(size: 10)).foregroundColor(Color.duoSubtitle)
                    }
                }
            }
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(isYearly ? Color(hex: "#FFD700") : Color(.systemGray5),
                        lineWidth: isYearly ? 2 : 1))
            .shadow(color: Color.black.opacity(isYearly ? 0.08 : 0.04), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(plus.isLoadingPurchase)
    }

    // MARK: - Admin パネル

    private var adminSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("管理者パネル")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.duoSubtitle)
                .padding(.leading, 4)
            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill").foregroundColor(Color(hex: "#FFD700"))
                    Text(PlusManager.adminEmail)
                        .font(.system(size: 11)).foregroundColor(Color.duoSubtitle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Admin 状態のデバッグ表示
                HStack(spacing: 6) {
                    Image(systemName: plus.isAdmin ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(plus.isAdmin ? Color.duoGreen : .red)
                    Text(plus.isAdmin ? "Admin認証済み" : "Admin未認証（ログイン状態を確認）")
                        .font(.system(size: 10))
                        .foregroundColor(plus.isAdmin ? Color.duoSubtitle : .red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14).background(Color(.systemBackground)).cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "#FFD700").opacity(0.4), lineWidth: 1.5))

            #if canImport(FirebaseFunctions)
            PromoAdminPanel()
            streakSetterPanel
            retentionDiagnosticsPanel
            #endif
        }
    }

    #if canImport(FirebaseFunctions)
    private var streakSetterPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("連続記録を手動設定")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.duoSubtitle)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 8) {
                Text("自分（Admin）アカウントの連続記録日数を直接上書きします。")
                    .font(.system(size: 11)).foregroundColor(Color.duoSubtitle)
                HStack(spacing: 8) {
                    TextField("例: 99", text: $streakInput)
                        .keyboardType(.numberPad)
                        .padding(10).background(Color(.systemGray6)).cornerRadius(8)
                    Button {
                        setAdminStreak()
                    } label: {
                        if isSavingStreak {
                            ProgressView().tint(.white).frame(width: 40)
                        } else {
                            Text("設定")
                        }
                    }
                    .font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color(hex: "#FF8C00")).cornerRadius(8)
                    .disabled(streakInput.trimmingCharacters(in: .whitespaces).isEmpty || isSavingStreak)
                }
                if let res = streakResult {
                    Text(res)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(res.hasPrefix("✅") ? Color.duoGreen : .red)
                }
            }
            .padding(14).background(Color(.systemBackground)).cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "#FFD700").opacity(0.4), lineWidth: 1.5))
        }
    }

    private func setAdminStreak() {
        guard let streak = Int(streakInput.trimmingCharacters(in: .whitespaces)) else {
            streakResult = "❌ 数値を入力してください"
            return
        }
        isSavingStreak = true
        streakResult = nil
        Task {
            do {
                let fn = Functions.functions(region: "us-central1")
                let result = try await fn.httpsCallable("setAdminStreak").call(["streak": streak])
                let data = result.data as? [String: Any]
                let saved = data?["streak"] as? Int ?? streak
                await MainActor.run {
                    streakResult = "✅ 連続記録を\(saved)日に設定しました"
                    isSavingStreak = false
                }
            } catch {
                await MainActor.run {
                    streakResult = "❌ 失敗: \(error.localizedDescription)"
                    isSavingStreak = false
                }
            }
        }
    }
    #endif

    // kedu/kmind は FirebaseFunctions SDK 未リンクのためkfitのみ有効
    #if canImport(FirebaseFunctions)
    private var retentionDiagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("テスター状況レポート（90秒モード検証）")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.duoSubtitle)
                Spacer()
                Button {
                    fetchRetentionDiagnostics()
                } label: {
                    if isLoadingRetention {
                        ProgressView().frame(width: 16, height: 16)
                    } else {
                        Text("取得").font(.system(size: 12, weight: .bold))
                    }
                }
                .disabled(isLoadingRetention)
            }
            .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 8) {
                if let error = retentionError {
                    Text("❌ \(error)")
                        .font(.system(size: 11)).foregroundColor(.red)
                } else if let summary = retentionSummary {
                    Text("全\(summary.total)人／記録済み\(summary.recorded)／既存除外\(summary.preExisting)／非トレーニング初回\(summary.nonTrainingFirst)／活動なし\(summary.noActivity)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.duoDark)
                    Divider()
                    ForEach(retentionRows) { row in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(row.username?.isEmpty == false ? row.username! : String(row.id.prefix(8)) + "…")
                                    .font(.system(size: 14, weight: .black))
                                    .foregroundColor(Color.duoDark)
                                Spacer()
                                Text(row.statusLabel)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(Color.duoSubtitle)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.duoSubtitle.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            HStack(spacing: 8) {
                                retentionBadge(icon: "iphone", text: row.platformsLabel, color: Color.duoBlue)
                                retentionBadge(icon: "arrow.right.circle", text: row.sourceLabel, color: Color.duoPurple)
                            }
                            Text("pt=\(row.totalPoints) streak=\(row.streak) 初回活動日=\(row.firstActiveDay ?? "-") firstSetSeconds=\(row.firstSetSeconds.map { "\($0)s" } ?? "-")")
                                .font(.system(size: 10))
                                .foregroundColor(Color.duoSubtitle)
                        }
                        .padding(10)
                        .background(Color.duoBg)
                        .cornerRadius(10)
                    }
                } else {
                    Text("「取得」をタップするとFirestoreから全ユーザーの状況を集計します")
                        .font(.system(size: 11)).foregroundColor(Color.duoSubtitle)
                }
            }
            .padding(14).background(Color(.systemBackground)).cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "#FFD700").opacity(0.4), lineWidth: 1.5))
        }
    }

    private func retentionBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            Text(text).font(.system(size: 12, weight: .bold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func fetchRetentionDiagnostics() {
        isLoadingRetention = true
        retentionError = nil
        Task {
            do {
                let fn = Functions.functions(region: "us-central1")
                let result = try await fn.httpsCallable("getRetentionDiagnostics").call([String: Any]())
                guard let data = result.data as? [String: Any],
                      let rawRows = data["rows"] as? [[String: Any]] else {
                    await MainActor.run {
                        retentionError = "レスポンスの形式が不正です"
                        isLoadingRetention = false
                    }
                    return
                }
                let rows: [RetentionDiagnosticRow] = rawRows.compactMap { row in
                    guard let uid = row["uid"] as? String, let status = row["status"] as? String else { return nil }
                    return RetentionDiagnosticRow(
                        id: uid,
                        username: row["username"] as? String,
                        totalPoints: row["totalPoints"] as? Int ?? 0,
                        streak: row["streak"] as? Int ?? 0,
                        firstActiveDay: row["firstActiveDay"] as? String,
                        totalActiveDays: row["totalActiveDays"] as? Int ?? 0,
                        firstSetSeconds: row["firstSetSeconds"] as? Int,
                        platforms: row["platforms"] as? [String] ?? [],
                        firstPlatform: row["firstPlatform"] as? String,
                        lastPlatform: row["lastPlatform"] as? String,
                        firstSource: row["firstSource"] as? String,
                        firstReferrer: row["firstReferrer"] as? String,
                        status: status
                    )
                }
                var summary: RetentionDiagnosticSummary? = nil
                if let s = data["summary"] as? [String: Any] {
                    summary = RetentionDiagnosticSummary(
                        total: s["total"] as? Int ?? 0,
                        preExisting: s["preExisting"] as? Int ?? 0,
                        nonTrainingFirst: s["nonTrainingFirst"] as? Int ?? 0,
                        recorded: s["recorded"] as? Int ?? 0,
                        noActivity: s["noActivity"] as? Int ?? 0
                    )
                }
                await MainActor.run {
                    retentionRows = rows
                    retentionSummary = summary
                    isLoadingRetention = false
                }
            } catch {
                await MainActor.run {
                    retentionError = error.localizedDescription
                    isLoadingRetention = false
                }
            }
        }
    }
    #endif
}

// MARK: - 後方互換エイリアス（削除予定）
typealias PremiumView = PlusView

#Preview { PlusView() }

// MARK: - プロモ（無料の Plus ユーザー）管理パネル：管理者のみ
// 付与・解除の権限はサーバー（setPromoUser / listPromoUsers）が検証済みの
// ID トークンのメールで判定する。この画面の表示制御は見た目だけ。

#if canImport(FirebaseFunctions)
struct PromoAdminPanel: View {
    @ObservedObject private var plus = PlusManager.shared
    @State private var email: String = ""
    @State private var days: Int = 0
    @State private var note: String = ""
    @State private var isWorking = false
    @State private var result: String? = nil
    @State private var users: [PlusManager.PromoUser] = []

    private let dayOptions: [(label: String, days: Int)] = [
        ("無期限", 0), ("1か月", 30), ("3か月", 90), ("1年", 365),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("プロモ（無料の Plus ユーザー）")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.duoSubtitle)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 10) {
                Text("メールアドレスを指定して Plus を無料で付与します。相手は先に Fitingo へ一度ログインしている必要があります。")
                    .font(.system(size: 11)).foregroundColor(Color.duoSubtitle)
                TextField("メールアドレス", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(10).background(Color(.systemGray6)).cornerRadius(8)
                Picker("期間", selection: $days) {
                    ForEach(dayOptions, id: \.days) { Text($0.label).tag($0.days) }
                }
                .pickerStyle(.segmented)
                TextField("メモ（任意）", text: $note)
                    .padding(10).background(Color(.systemGray6)).cornerRadius(8)
                HStack(spacing: 8) {
                    Button { run(enabled: true, target: email) } label: {
                        Text("Plus を付与").frame(maxWidth: .infinity)
                    }
                    .font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                    .padding(.vertical, 10)
                    .background(Color(hex: "#FF8C00")).cornerRadius(8)
                    Button { run(enabled: false, target: email) } label: {
                        Text("解除").frame(maxWidth: .infinity)
                    }
                    .font(.system(size: 13, weight: .bold)).foregroundColor(.red)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6)).cornerRadius(8)
                }
                .disabled(isWorking || !email.contains("@"))
                if isWorking { ProgressView().frame(maxWidth: .infinity) }
                if let result {
                    Text(result)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(result.hasPrefix("❌") ? .red : Color.duoGreen)
                }
                Divider()
                HStack {
                    Text("付与中のユーザー（\(users.count)）")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(Color.duoSubtitle)
                    Spacer()
                    Button("更新") { Task { await load() } }.font(.system(size: 12, weight: .bold))
                }
                ForEach(users) { u in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(u.email.isEmpty ? u.id : u.email).font(.system(size: 12, weight: .semibold))
                            Text(u.expiresAt.map { "\($0.formatted(date: .abbreviated, time: .omitted))まで" } ?? "無期限")
                                .font(.system(size: 10)).foregroundColor(Color.duoSubtitle)
                            if !u.note.isEmpty {
                                Text(u.note).font(.system(size: 10)).foregroundColor(Color.duoSubtitle)
                            }
                        }
                        Spacer()
                        Button("解除") { run(enabled: false, target: u.email) }
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.red)
                            .disabled(isWorking || u.email.isEmpty)
                    }
                }
            }
            .padding(14).background(Color(.systemBackground)).cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "#FFD700").opacity(0.4), lineWidth: 1.5))
        }
        .task { await load() }
    }

    private func run(enabled: Bool, target: String) {
        let t = target.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        isWorking = true
        result = nil
        Task {
            do {
                result = "✅ " + (try await plus.setPromoUser(email: t, enabled: enabled, days: days, note: note))
                if enabled { email = ""; note = "" }
                await load()
            } catch {
                result = "❌ \(error.localizedDescription)"
            }
            isWorking = false
        }
    }

    private func load() async {
        users = (try? await plus.listPromoUsers()) ?? users
    }
}
#endif
