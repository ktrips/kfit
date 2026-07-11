import SwiftUI
import UIKit
import Combine
import FirebaseAuth
import GoogleSignIn

// MARK: - MainMenuTab

enum MainMenuTab: Int, CaseIterable, Identifiable {
    case fit = 0
    case goal = 1
    case mind = 2
    case food = 3
    case tomo = 6      // 4=Settings, 5=More are reserved
    case goalingo = 7

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .fit:      return "ROUTIN"
        case .goal:     return "FIT"
        case .mind:     return "MIND"
        case .food:     return "FOOD"
        case .tomo:     return "TOMO"
        case .goalingo: return "GOAL"
        }
    }

    var settingsLabel: String {
        switch self {
        case .fit:      return "ROUTINタブ"
        case .goal:     return "FITタブ"
        case .mind:     return "MINDタブ"
        case .food:     return "FOODタブ"
        case .tomo:     return "TOMOタブ"
        case .goalingo: return "GOALタブ"
        }
    }

    var icon: String {
        switch self {
        case .fit:      return "house.fill"
        case .goal:     return "target"
        case .mind:     return "brain.head.profile"
        case .food:     return "fork.knife"
        case .tomo:     return "person.2.fill"
        case .goalingo: return "flag.checkered"
        }
    }
}

// MARK: - MainMenuTabPreferences

enum MainMenuTabPreferences {
    static let fitVisibleKey      = "mainTab.fit.visible"
    static let goalVisibleKey     = "mainTab.goal.visible"
    static let mindVisibleKey     = "mainTab.mind.visible"
    static let foodVisibleKey     = "mainTab.food.visible"
    static let tomoVisibleKey     = "mainTab.tomo.visible"
    static let goalingoVisibleKey = "mainTab.goalingo.visible"
    static let logVisibleKey      = "mainTab.log.visible"
    static let defaultTabKey      = "mainTab.default"
    static let orderKey           = "mainTab.order"

    static let defaultOrder = [MainMenuTab.fit, .goal, .food, .mind, .goalingo, .tomo]

    static func visibleKey(for tab: MainMenuTab) -> String {
        switch tab {
        case .fit:      return fitVisibleKey
        case .goal:     return goalVisibleKey
        case .mind:     return mindVisibleKey
        case .food:     return foodVisibleKey
        case .tomo:     return tomoVisibleKey
        case .goalingo: return goalingoVisibleKey
        }
    }

    static func orderedTabs(from storedOrder: String) -> [MainMenuTab] {
        var result = storedOrder
            .split(separator: ",")
            .compactMap { Int($0).flatMap(MainMenuTab.init(rawValue:)) }

        for tab in defaultOrder where !result.contains(tab) {
            let defaultIdx = defaultOrder.firstIndex(of: tab)!
            let predecessors = Set(defaultOrder.prefix(defaultIdx))
            if let insertAfterIdx = result.indices.last(where: { predecessors.contains(result[$0]) }) {
                result.insert(tab, at: result.index(after: insertAfterIdx))
            } else {
                result.insert(tab, at: 0)
            }
        }

        return result.filter { defaultOrder.contains($0) }
    }

    static func storedOrder(from tabs: [MainMenuTab]) -> String {
        tabs.map { String($0.rawValue) }.joined(separator: ",")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let requestStartTraining   = Notification.Name("requestStartTraining")
    static let requestStartMindfulness = Notification.Name("requestStartMindfulness")
}

// MARK: - FitingoDeepLink

enum FitingoDeepLink: String {
    case workout     = "workout"
    case mindfulness = "mindfulness"
    case food        = "food"
    case mind        = "mind"
    case goal        = "goal"
    case diet        = "diet"
    case record      = "record"
    case home        = "home"

    init?(url: URL) {
        guard url.scheme == "fitingo",
              let host = url.host,
              let link = FitingoDeepLink(rawValue: host) else { return nil }
        self = link
    }
}

// MARK: - HeaderNavigationMenu

struct HeaderNavigationMenu: View {
    @Binding var selectedTab: Int
    @Binding var showRecordMenu: Bool
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var plus: PlusManager
    @AppStorage(MainMenuTabPreferences.orderKey) private var tabOrderRaw = MainMenuTabPreferences.storedOrder(from: MainMenuTabPreferences.defaultOrder)

    @State private var showUserStatus = false
    @State private var showLogoutConfirm = false
    @State private var showPlusViewFromMenu = false

    private var allPrimaryTabs: [MainMenuTab] {
        MainMenuTabPreferences.orderedTabs(from: tabOrderRaw)
    }
    private let bookURL = URL(string: "https://fit.ktrips.net/books")!

    private var displayName: String {
        authManager.userProfile?.username
            ?? Auth.auth().currentUser?.displayName
            ?? Auth.auth().currentUser?.email?.components(separatedBy: "@").first
            ?? "ユーザー"
    }
    private var googlePhotoURL: URL? { Auth.auth().currentUser?.photoURL }

    var body: some View {
        Menu {
            Section {
                Button {
                    showUserStatus = true
                } label: {
                    Label(
                        "\(displayName)  \(plus.isPlus ? "✦ Plus" : "Free")",
                        systemImage: plus.isPlus ? "star.circle.fill" : "person.circle"
                    )
                }
                if !plus.isPlus {
                    Button {
                        showPlusViewFromMenu = true
                    } label: {
                        Label("Plus にアップグレード", systemImage: "plus.circle.fill")
                    }
                }
                Button(role: .destructive) {
                    showLogoutConfirm = true
                } label: {
                    Label("ログアウト", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } header: {
                Text(Auth.auth().currentUser?.email ?? "")
            }

            Section {
                ForEach(allPrimaryTabs) { tab in
                    Button { selectedTab = tab.rawValue } label: {
                        Label(tab.label, systemImage: tab.icon)
                    }
                }
                Button { showRecordMenu = true } label: {
                    Label("LOG", systemImage: "plus.circle.fill")
                }
                Button { selectedTab = 4 } label: {
                    Label("SETUP", systemImage: "gearshape.fill")
                }
                Link(destination: bookURL) {
                    Label("BOOKS", systemImage: "book.fill")
                }
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                if let url = googlePhotoURL {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                                .frame(width: 28, height: 28)
                                .clipShape(Circle())
                        } else {
                            initialsCircleLabel
                        }
                    }
                } else {
                    initialsCircleLabel
                }
                if plus.isPlus {
                    PlusBadge(size: 11).offset(x: 4, y: 4)
                }
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showUserStatus) {
            UserStatusSheet(
                onShowPlus: { showPlusViewFromMenu = true },
                onSetup: { selectedTab = 4 }
            )
            .environmentObject(authManager)
            .environmentObject(plus)
        }
        .sheet(isPresented: $showPlusViewFromMenu) {
            PlusView()
        }
        .confirmationDialog("ログアウトしますか？",
                            isPresented: $showLogoutConfirm,
                            titleVisibility: .visible) {
            Button("ログアウト", role: .destructive) {
                GIDSignIn.sharedInstance.signOut()
                try? Auth.auth().signOut()
            }
            Button("キャンセル", role: .cancel) {}
        }
    }

    private var initialsCircleLabel: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 28, height: 28)
            if let initial = displayName.first {
                Text(String(initial).uppercased())
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            } else {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .black))
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - UserStatusSheet

struct UserStatusSheet: View {
    var onShowPlus: () -> Void = {}
    var onSetup: () -> Void = {}
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var plus: PlusManager
    @Environment(\.dismiss) private var dismiss

    @State private var adminNewCode: String = ""
    @State private var adminCodeResult: String? = nil
    @State private var isUpdatingCode: Bool = false

    private var displayName: String {
        authManager.userProfile?.username
            ?? Auth.auth().currentUser?.displayName
            ?? Auth.auth().currentUser?.email?.components(separatedBy: "@").first
            ?? "ユーザー"
    }
    private var email: String { Auth.auth().currentUser?.email ?? "" }
    private var avatarLetter: String { String((displayName.first ?? "U")).uppercased() }
    private var googlePhotoURL: URL? { Auth.auth().currentUser?.photoURL }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    VStack(spacing: 10) {
                        ZStack(alignment: .bottomTrailing) {
                            avatarImage
                            if plus.isPlus {
                                PlusBadge(size: 22).offset(x: 4, y: 4)
                            }
                        }
                        Text(displayName)
                            .font(.system(size: 18, weight: .black))
                            .foregroundColor(Color.duoDark)
                        Text(email)
                            .font(.system(size: 12))
                            .foregroundColor(Color.duoSubtitle)

                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onSetup() }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 11))
                                Text("セットアップを開く")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(Color.duoSubtitle)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Color(.systemGray6))
                            .cornerRadius(20)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)

                    planStatusCard

                    if plus.isAdmin { adminPanel }

                    if !plus.isPlus { miniComparisonSection }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
            .background(Color.duoBg.ignoresSafeArea())
            .navigationTitle("プロフィール")
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

    @ViewBuilder
    private var avatarImage: some View {
        if let url = googlePhotoURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(
                            plus.isPlus ? Color(hex: "#FFD700") : Color.duoGreen,
                            lineWidth: 3
                        ))
                default:
                    initialsCircle
                }
            }
        } else {
            initialsCircle
        }
    }

    private var initialsCircle: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color.duoGreen, Color(hex: "#26A800")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 80, height: 80)
            Text(avatarLetter)
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundColor(.white)
        }
    }

    private var planStatusCard: some View {
        HStack(spacing: 14) {
            if plus.isPlus {
                PlusBadge(size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fitingo Plus")
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(Color(hex: "#FF8C00"))
                    Text(plus.isAdmin ? "Admin アカウント"
                         : plus.codeUnlocked ? "Plusコードで解放済み"
                         : "サブスクリプション有効")
                        .font(.system(size: 12)).foregroundColor(Color.duoSubtitle)
                    Text("すべての機能が使えます ✓")
                        .font(.system(size: 11, weight: .bold)).foregroundColor(Color.duoGreen)
                }
            } else {
                ZStack {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 44, height: 44)
                    Image(systemName: "person.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Color.duoSubtitle)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Free プラン")
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(Color.duoDark)
                    Text("基本機能が無料で使えます")
                        .font(.system(size: 12)).foregroundColor(Color.duoSubtitle)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(
            plus.isPlus
            ? Color(hex: "#FFD700").opacity(0.12)
            : Color(.systemBackground)
        )
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(plus.isPlus ? Color(hex: "#FFD700").opacity(0.5) : Color(.systemGray5),
                    lineWidth: 1.5))
    }

    private var adminPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "crown.fill").foregroundColor(Color(hex: "#FFD700"))
                Text("管理者パネル")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.duoSubtitle)
            }
            .padding(.leading, 4)

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("現在のPlusコード")
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

                if let res = adminCodeResult {
                    Text(res)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(res.hasPrefix("✅") ? Color.duoGreen : .red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14).background(Color(.systemBackground)).cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "#FFD700").opacity(0.5), lineWidth: 1.5))
        }
    }

    private var miniComparisonSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Plus にすると使えること")
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(Color.duoDark)
                Spacer()
            }

            let benefits: [(String, String)] = [
                ("🚫", "広告なし"),
                ("📊", "AI による詳細アクティビティ分析"),
                ("📸", "フォトログ AI 栄養解析"),
                ("✨", "AI スリープ・マインドコーチング"),
                ("📚", "Kindle本をWebで全文読む"),
                ("👥", "友達追加 無制限"),
                ("📱", "Plus ウィジェット"),
                ("🎨", "スパイラルテーマ 10種以上"),
                ("🔔", "全時間帯リマインダー"),
            ]
            VStack(spacing: 0) {
                ForEach(Array(benefits.enumerated()), id: \.offset) { idx, item in
                    if idx > 0 { Divider().padding(.leading, 36) }
                    HStack(spacing: 10) {
                        Text(item.0).font(.system(size: 16)).frame(width: 26)
                        Text(item.1)
                            .font(.system(size: 13))
                            .foregroundColor(Color.duoDark)
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "#FF8C00"))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(14)

            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 11)).foregroundColor(Color.duoBlue)
                Text("APIキー不要で1日1回無料・Plusは3回/日・APIキー登録で無制限")
                    .font(.system(size: 10)).foregroundColor(Color.duoSubtitle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onShowPlus() }
            } label: {
                HStack(spacing: 8) {
                    PlusBadge(size: 20)
                    Text("Plus にアップグレード")
                        .font(.system(size: 14, weight: .black))
                    Text("月額¥480〜")
                        .font(.system(size: 11)).opacity(0.85)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(LinearGradient(
                    colors: [Color(hex: "#FF8C00"), Color(hex: "#FFD700")],
                    startPoint: .leading, endPoint: .trailing
                ))
                .cornerRadius(14)
                .shadow(color: Color(hex: "#FF8C00").opacity(0.35), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - LinkMeta / LinkMetadataFetcher
// URLのOGメタデータ（og:title, og:description, og:image）を非同期取得・キャッシュ。
// SharedAppComponents に置くことで kfit/kedu 両プロジェクトから参照可能。

struct LinkMeta: Equatable {
    var title: String?
    var description: String?
    var imageURL: String?
    var thumbnailImage: UIImage?
    var isLoading: Bool = false
    var hasContent: Bool { !(title ?? "").isEmpty || !(description ?? "").isEmpty }
}

// ObservableObject + @Published の組み合わせを明示的に実装。
// @MainActor をクラスレベルに付けると Swift バージョンによって
// ObservableObject 合成が失敗するため、スレッド管理は内部で行う。
final class LinkMetadataFetcher: ObservableObject {

    static let shared = LinkMetadataFetcher()

    // MARK: - 正規表現キャッシュ（静的。毎回コンパイルすると CPU 負荷大）
    // NSRegularExpression のコンパイルは高コスト。static で初回のみ行い以降は再利用。
    private static var regexCache: [String: NSRegularExpression] = [:]
    private static let regexCacheLock = NSLock()

    private static func cachedRegex(pattern: String, options: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators]) -> NSRegularExpression? {
        regexCacheLock.lock()
        defer { regexCacheLock.unlock() }
        if let cached = regexCache[pattern] { return cached }
        guard let r = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        regexCache[pattern] = r
        return r
    }

    // メインスレッドから読み書きする前提
    var cache: [String: LinkMeta] = [:] {
        willSet { objectWillChange.send() }
    }
    private var inFlight: Set<String> = []

    func prefetch(urlString: String) {
        guard !inFlight.contains(urlString), cache[urlString] == nil else { return }
        inFlight.insert(urlString)
        cache[urlString] = LinkMeta(isLoading: true)
        Task { @MainActor in await self.doFetch(urlString: urlString) }
    }

    func meta(for urlString: String) -> LinkMeta? { cache[urlString] }

    @MainActor
    private func doFetch(urlString: String) async {
        defer {
            inFlight.remove(urlString)
        }
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? String(data: data, encoding: .shiftJIS)
                ?? ""
            var meta = LinkMeta(isLoading: false)
            (meta.title, meta.description, meta.imageURL) = parseOG(from: html)
            if let imgUrl = meta.imageURL, let iurl = URL(string: imgUrl),
               let (imgData, _) = try? await URLSession.shared.data(from: iurl),
               let img = UIImage(data: imgData) {
                meta.thumbnailImage = resized(img, maxPixel: 180)
            }
            cache[urlString] = meta
        } catch {
            cache[urlString] = LinkMeta(isLoading: false)
        }
    }

    private func parseOG(from html: String) -> (title: String?, description: String?, imageURL: String?) {
        func extract(property: String) -> String? {
            let patterns = [
                "property=[\"']og:\(property)[\"'][^>]*content=[\"']([^\"'<>]+)[\"']",
                "content=[\"']([^\"'<>]+)[\"'][^>]*property=[\"']og:\(property)[\"']",
                "name=[\"']twitter:\(property)[\"'][^>]*content=[\"']([^\"'<>]+)[\"']",
                "content=[\"']([^\"'<>]+)[\"'][^>]*name=[\"']twitter:\(property)[\"']",
                "name=[\"']\(property)[\"'][^>]*content=[\"']([^\"'<>]+)[\"']",
                "content=[\"']([^\"'<>]+)[\"'][^>]*name=[\"']\(property)[\"']"
            ]
            for pattern in patterns {
                // cachedRegex を使用し、毎回のコンパイルを回避（パフォーマンス改善）
                guard let regex = LinkMetadataFetcher.cachedRegex(pattern: pattern) else { continue }
                let ns = html as NSString
                if let m = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
                   m.numberOfRanges > 1 {
                    let r = m.range(at: 1)
                    if r.location != NSNotFound {
                        return htmlDecode(ns.substring(with: r)).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
            return nil
        }
        let titleFallback: String? = {
            // title タグ用正規表現もキャッシュ
            guard let r = LinkMetadataFetcher.cachedRegex(
                pattern: "<title[^>]*>([^<]+)</title>",
                options: .caseInsensitive
            ) else { return nil }
            let ns = html as NSString
            if let m = r.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
               m.numberOfRanges > 1 {
                let rng = m.range(at: 1)
                if rng.location != NSNotFound {
                    return htmlDecode(ns.substring(with: rng)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return nil
        }()
        return (extract(property: "title") ?? titleFallback,
                extract(property: "description"),
                extract(property: "image"))
    }

    private func htmlDecode(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
         .replacingOccurrences(of: "&quot;", with: "\"")
         .replacingOccurrences(of: "&#39;", with: "'")
         .replacingOccurrences(of: "&apos;", with: "'")
         .replacingOccurrences(of: "&lt;", with: "<")
         .replacingOccurrences(of: "&gt;", with: ">")
         .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private func resized(_ img: UIImage, maxPixel: CGFloat) -> UIImage {
        let long = max(img.size.width, img.size.height)
        guard long > maxPixel else { return img }
        let scale = maxPixel / long
        let newSize = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in img.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

extension LinkMetadataFetcher {
    /// PendingShareProcessor から呼ぶ static ヘルパー（キャッシュなし・バックグラウンド）
    static func fetchOGMeta(urlString: String) async -> (title: String?, description: String?, imageURL: String?) {
        guard let url = URL(string: urlString) else { return (nil, nil, nil) }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return (nil, nil, nil) }
        let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        return LinkMetadataFetcher.shared.parseOG(from: html)
    }
}

// MARK: - CachedAsyncImage（URLCache を活用した画像キャッシュ付き AsyncImage 代替）
// AsyncImage はデフォルトで URLCache を使わず、LazyVStack でのスクロール時に
// 同一 URL を繰り返しダウンロードする。CachedAsyncImage は URLCache.shared を
// 経由するセッションを使い、ディスク/メモリキャッシュを活用する。

// Generic 型は static stored property を持てないため、URLSession をトップレベル定数で管理する。
private let _cachedImageSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.urlCache = URLCache.shared          // ディスク 512MB / メモリ 64MB
    config.requestCachePolicy = .returnCacheDataElseLoad
    return URLSession(configuration: config)
}()

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage? = nil
    @State private var isLoading = false

    var body: some View {
        Group {
            if let img = image {
                content(Image(uiImage: img))
            } else {
                placeholder()
                    .onAppear { load() }
            }
        }
    }

    private func load() {
        guard !isLoading, let url else { return }
        isLoading = true
        Task {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
            guard let (data, _) = try? await _cachedImageSession.data(for: request),
                  let loaded = UIImage(data: data) else {
                await MainActor.run { isLoading = false }
                return
            }
            await MainActor.run {
                image = loaded
                isLoading = false
            }
        }
    }
}

// MARK: - AIRequiresPlusSheet

/// 10日以降のフリーユーザーに表示するPlus誘導シート。
/// AI利用を試みた際に自動的にプレゼントする。
struct AIRequiresPlusSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showPlus = false

    private let activeDays = UserDefaults.standard.integer(forKey: "retention.activeDayCount")

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                // アイコン + メッセージ
                VStack(spacing: 14) {
                    Text("🎉")
                        .font(.system(size: 56))
                    Text("\(activeDays)日連続達成！")
                        .font(.title2).fontWeight(.black)
                        .foregroundColor(Color.duoDark)
                    Text("ここまで続けたあなたはすごい！\nAIをもっと使うには\nFitingo Plusがおすすめです。")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color.duoSubtitle)
                }

                // 比較カード
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Free").font(.caption).fontWeight(.bold)
                                .foregroundColor(Color.duoSubtitle)
                            Text("AI機能なし\n（10日以降）")
                                .font(.subheadline)
                                .foregroundColor(Color.duoSubtitle)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(14)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 4) {
                                Text("Plus").font(.caption).fontWeight(.bold)
                                    .foregroundColor(Color.duoGreen)
                                Image(systemName: "star.fill")
                                    .font(.caption2).foregroundColor(Color.duoGreen)
                            }
                            Text("食事AI・語学AI\n毎日3回ずつ")
                                .font(.subheadline).fontWeight(.semibold)
                                .foregroundColor(Color.duoDark)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.duoGreen.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.duoGreen, lineWidth: 1.5)
                        )
                        .cornerRadius(14)
                    }

                    Text("または自分のOpenAI APIキーを登録すると無制限に使えます")
                        .font(.caption)
                        .foregroundColor(Color.duoSubtitle)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 4)

                // CTAボタン
                Button {
                    showPlus = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill")
                        Text("Fitingo Plus を見る")
                            .fontWeight(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.duoGreen)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                }
                .buttonStyle(.plain)

                Button("あとで") { dismiss() }
                    .font(.subheadline)
                    .foregroundColor(Color.duoSubtitle)
            }
            .padding(24)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color.duoSubtitle)
                    }
                }
            }
            .sheet(isPresented: $showPlus) {
                PlusView()
            }
        }
    }
}
