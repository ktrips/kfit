import SwiftUI
import StoreKit

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

struct PlusView: View {
    @StateObject private var plus = PlusManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var codeInput: String = ""
    @State private var codeResult: CodeResult? = nil
    @State private var showCodeField: Bool = false
    @State private var adminNewCode: String = ""
    @State private var adminCodeResult: String? = nil
    @State private var isUpdatingCode: Bool = false
    @FocusState private var codeFocused: Bool
    @State private var selectedTab: PlusTab = .compare

    enum CodeResult { case success, failure }
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
                codeSection
            }
        }
    }

    private var plusActiveCard: some View {
        VStack(spacing: 12) {
            PlusBadge(size: 50)
            Text("Fitingo Plus 有効中")
                .font(.system(size: 20, weight: .black))
                .foregroundColor(Color(hex: "#FF8C00"))
            Text(plus.isAdmin ? "Adminアカウント"
                 : plus.codeUnlocked ? "Plusコードで解放済み"
                 : "サブスクリプション有効")
                .font(.system(size: 13))
                .foregroundColor(Color.duoSubtitle)
            if plus.codeUnlocked && !plus.isAdmin {
                Button(role: .destructive) { plus.revokeCodeUnlock() } label: {
                    Label("コード解放を取り消す", systemImage: "lock.rotation")
                        .font(.system(size: 12))
                }
            }
        }
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
                ProgressView().tint(Color(hex: "#FF8C00")).frame(maxWidth: .infinity).padding()
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
        }
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
                    Text(isYearly ? "月あたり約¥317 · 約34%お得" : "いつでもキャンセル可")
                        .font(.system(size: 11)).foregroundColor(Color.duoSubtitle)
                    Text("7日間無料トライアル付き")
                        .font(.system(size: 10)).foregroundColor(Color(hex: "#FF8C00"))
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

    private var codeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plusコード")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.duoSubtitle)
                .padding(.leading, 4)
            if !showCodeField {
                Button { showCodeField = true; codeFocused = true } label: {
                    HStack {
                        Image(systemName: "key.fill").foregroundColor(Color(hex: "#FF8C00"))
                        Text("コードを持っている")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(hex: "#FF8C00"))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11)).foregroundColor(Color.duoSubtitle)
                    }
                    .padding(14)
                    .background(Color(.systemBackground))
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 10) {
                    SecureField("Plusコードを入力", text: $codeInput)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($codeFocused)
                        .padding(12).background(Color(.systemGray6)).cornerRadius(10)
                    if let result = codeResult {
                        Label(result == .success ? "Plusを解放しました！" : "コードが違います",
                              systemImage: result == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(result == .success ? Color.duoGreen : .red)
                    }
                    HStack {
                        Button("キャンセル") {
                            showCodeField = false; codeInput = ""; codeResult = nil
                        }
                        .font(.system(size: 13)).foregroundColor(Color.duoSubtitle)
                        Spacer()
                        Button("解放する") {
                            let ok = plus.unlockWithCode(codeInput)
                            codeResult = ok ? .success : .failure
                            if ok {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                    showCodeField = false
                                }
                            }
                        }
                        .font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(codeInput.isEmpty ? Color(.systemGray4) : Color(hex: "#FF8C00"))
                        .cornerRadius(8).disabled(codeInput.isEmpty)
                    }
                }
                .padding(14).background(Color(.systemBackground)).cornerRadius(14)
            }
        }
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("現在のコード")
                        .font(.system(size: 10, weight: .semibold)).foregroundColor(Color.duoSubtitle)
                    Text(plus.secretCode)
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                        .foregroundColor(Color(hex: "#FF8C00"))
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: "#FF8C00").opacity(0.08)).cornerRadius(8)
                }
                HStack(spacing: 8) {
                    TextField("新しいコード", text: $adminNewCode)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(10).background(Color(.systemGray6)).cornerRadius(8)
                    Button {
                        guard !adminNewCode.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        isUpdatingCode = true
                        adminCodeResult = nil
                        Task {
                            let ok = await plus.updateSecretCode(adminNewCode)
                            adminCodeResult = ok ? "✅ 変更完了" : "❌ 失敗（Xcodeコンソールを確認）"
                            if ok { adminNewCode = "" }
                            isUpdatingCode = false
                        }
                    } label: {
                        if isUpdatingCode {
                            ProgressView().tint(.white).frame(width: 40)
                        } else {
                            Text("変更")
                        }
                    }
                    .font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color(hex: "#FF8C00")).cornerRadius(8)
                    .disabled(adminNewCode.trimmingCharacters(in: .whitespaces).isEmpty || isUpdatingCode)
                }
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
                if let res = adminCodeResult {
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
}

// MARK: - 後方互換エイリアス（削除予定）
typealias PremiumView = PlusView

#Preview { PlusView() }
