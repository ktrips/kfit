import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - TomoManager

@MainActor
final class TomoManager: ObservableObject {

    struct TomoEntry: Identifiable {
        let id: String
        let email: String
        let username: String
        let totalPoints: Int
        let streak: Int
        var weeklyPoints: Int
        var isMe: Bool = false
        var rank: Int = 0
    }

    enum AddResult {
        case idle, searching
        case notFound(String)   // email → show share sheet
        case added(String)      // success → name
        case alreadyAdded
        case selfAdd
        case error(String)
    }

    @Published var entries: [TomoEntry] = []
    @Published var isLoading = false
    @Published var addResult: AddResult = .idle

    private let db = Firestore.firestore()

    func load() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }

        var all: [TomoEntry] = []

        // Self
        if let me = AuthenticationManager.shared.userProfile {
            let wPts = await weeklyPoints(userId: uid)
            all.append(TomoEntry(id: uid, email: me.email, username: me.username,
                                 totalPoints: me.totalPoints, streak: me.streak,
                                 weeklyPoints: wPts, isMe: true))
        }

        // Tomos
        let snap = try? await db.collection("users").document(uid)
            .collection("tomos").getDocuments()
        for doc in snap?.documents ?? [] {
            let tomoId = doc.documentID
            guard let profileDoc = try? await db.collection("users").document(tomoId).getDocument(),
                  profileDoc.exists,
                  let data = profileDoc.data() else { continue }
            let wPts = await weeklyPoints(userId: tomoId)
            all.append(TomoEntry(
                id: tomoId,
                email: data["email"] as? String ?? "",
                username: data["username"] as? String ?? "TOMO",
                totalPoints: data["totalPoints"] as? Int ?? 0,
                streak: data["streak"] as? Int ?? 0,
                weeklyPoints: wPts
            ))
        }

        all.sort { $0.weeklyPoints > $1.weeklyPoints }
        for i in all.indices { all[i].rank = i + 1 }
        entries = all
    }

    func addTomo(email rawEmail: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@") else {
            addResult = .error("有効なメールアドレスを入力してください")
            return
        }
        if entries.contains(where: { !$0.isMe && $0.email.lowercased() == email }) {
            addResult = .alreadyAdded; return
        }

        addResult = .searching
        let snap = try? await db.collection("users")
            .whereField("email", isEqualTo: email)
            .limit(to: 1)
            .getDocuments()
        guard let tomoDoc = snap?.documents.first else {
            addResult = .notFound(email); return
        }
        let tomoId = tomoDoc.documentID
        guard tomoId != uid else { addResult = .selfAdd; return }

        let now = Timestamp(date: Date())
        let myEmail = AuthenticationManager.shared.userProfile?.email ?? ""
        try? await db.collection("users").document(uid)
            .collection("tomos").document(tomoId)
            .setData(["email": email, "addedAt": now])
        try? await db.collection("users").document(tomoId)
            .collection("tomos").document(uid)
            .setData(["email": myEmail, "addedAt": now])

        let name = tomoDoc.data()["username"] as? String ?? email
        addResult = .added(name)
        await load()
    }

    func removeTomo(id: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try? await db.collection("users").document(uid)
            .collection("tomos").document(id).delete()
        entries.removeAll { $0.id == id }
        for i in entries.indices { entries[i].rank = i + 1 }
    }

    private func weeklyPoints(userId: String) async -> Int {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)  // 1=Sun, 2=Mon...
        let daysSinceMonday = weekday == 1 ? 6 : weekday - 2
        guard let monday = calendar.date(byAdding: .day, value: -daysSinceMonday,
                                         to: calendar.startOfDay(for: today)) else { return 0 }
        let snap = try? await db.collection("users").document(userId)
            .collection("completed-exercises")
            .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: monday))
            .getDocuments()
        return snap?.documents.compactMap { $0.data()["points"] as? Int }.reduce(0, +) ?? 0
    }
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - TomoView

struct TomoView: View {
    @Binding var selectedTab: Int
    @Binding var showRecordMenu: Bool
    @StateObject private var manager = TomoManager()
    @StateObject private var eduLogManager = EduLogManager.shared
    @State private var emailInput = ""
    @State private var showShareSheet = false
    @State private var shareText = ""
    @StateObject private var photoLogManager = PhotoLogManager.shared
    @State private var selectedEduItem: EduLogHistoryItem? = nil
    @State private var commentTargetItem: EduLogHistoryItem? = nil
    @State private var shareTargetItem: EduLogHistoryItem? = nil
    @State private var categoryGroupTarget: TomoView.FeedCategoryGroup? = nil
    @State private var showOlderFeed = false
    @State private var showInviteSheet = false
    @FocusState private var emailFocused: Bool

    var body: some View {
        NavigationView {
            ZStack {
                Color.duoBg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        rankingSection
                        eduFeedSection
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }
                .refreshable { await manager.load() }
            }
            .navigationBarHidden(true)
            .safeAreaInset(edge: .top, spacing: 0) { tomoHeader }
        }
        .task { await manager.load() }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [shareText])
        }
        .sheet(item: $selectedEduItem) { item in
            EduFeedDetailSheet(item: item)
        }
        .sheet(item: $commentTargetItem) { item in
            FeedCommentsSheet(item: item, eduLogManager: eduLogManager)
        }
        .sheet(item: $shareTargetItem) { item in
            SocialShareSheet(item: item)
        }
        .sheet(item: $categoryGroupTarget) { grp in
            CategoryGroupListSheet(
                group: grp,
                onTapItem: { selectedEduItem = $0; categoryGroupTarget = nil },
                onLike: { eduLogManager.toggleLike(id: $0.id) },
                onComment: { commentTargetItem = $0; categoryGroupTarget = nil },
                onShare: { shareTargetItem = $0; categoryGroupTarget = nil }
            )
        }
        .sheet(isPresented: $showInviteSheet) {
            inviteSheet
        }
    }

    // MARK: - Invite Sheet

    private var inviteSheet: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.duoBlue.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 20 * UIScale.font, weight: .bold))
                            .foregroundColor(Color.duoBlue)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TOMOを招待")
                            .font(.system(size: 17 * UIScale.font, weight: .black))
                            .foregroundColor(Color.duoDark)
                        Text("一緒にトレーニングしよう！")
                            .font(.system(size: 12 * UIScale.font))
                            .foregroundColor(Color.duoSubtitle)
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    TextField("Googleアカウントのメールアドレス", text: $emailInput)
                        .font(.system(size: 14 * UIScale.font))
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .focused($emailFocused)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)

                    Button {
                        emailFocused = false
                        Task { await manager.addTomo(email: emailInput) }
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 34 * UIScale.font))
                            .foregroundColor(emailInput.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Color.duoBlue.opacity(0.3) : Color.duoBlue)
                    }
                    .buttonStyle(.plain)
                    .disabled(emailInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                addResultView
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .onDisappear {
            emailInput = ""
            manager.addResult = .idle
        }
    }

    // MARK: - Dailyフィード

    private static let dateGroupFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日（E）"
        return f
    }()

    private var twoWeeksAgo: Date {
        Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
    }

    /// PhotoLogHistoryItem → EduLogHistoryItem（表示用）変換
    private func makeFoodFeedItem(_ food: PhotoLogHistoryItem) -> EduLogHistoryItem {
        var item = EduLogHistoryItem(
            activityName: "食事ログ",
            activityEmoji: "🍽️",
            comment: food.foodName.isEmpty ? food.comment : food.foodName,
            authorName: UserDefaults.standard.string(forKey: "cachedCurrentUserName") ?? "Kenichi Yoshida",
            authorPhotoURL: UserDefaults.standard.string(forKey: "cachedCurrentUserPhotoURL") ?? ""
        )
        item.id = "food_\(food.id)"
        item.timestamp = food.timestamp
        item.thumbnailData = food.thumbnailData
        return item
    }

    /// アクティビティ＋食事ログを統合したフィード全件（公開のもののみ）
    private var allFeedItems: [EduLogHistoryItem] {
        let activity = eduLogManager.history.filter { $0.isPublic }
        let food     = photoLogManager.history.filter { $0.isPublic }.map { makeFoodFeedItem($0) }
        return (activity + food).sorted { $0.timestamp > $1.timestamp }
    }

    /// 2週間以上前のデータが存在するか
    private var hasOlderItems: Bool {
        allFeedItems.contains { $0.timestamp < twoWeeksAgo }
    }

    /// 表示するフィード（直近2週間 or 全件）
    private var displayFeedItems: [EduLogHistoryItem] {
        showOlderFeed ? allFeedItems : allFeedItems.filter { $0.timestamp >= twoWeeksAgo }
    }

    // カテゴリグループ：ユーザー×カテゴリ単位で集約
    struct FeedCategoryGroup: Identifiable {
        var id: String { categoryKey }
        let categoryKey: String
        let categoryEmoji: String
        let items: [EduLogHistoryItem]
        var isSingle: Bool { items.count == 1 }
    }

    // ユーザーグループ：日付×ユーザー単位で集約
    struct FeedUserGroup: Identifiable {
        var id: String { authorName }
        let authorName: String
        let authorFirstName: String
        let authorPhotoURL: String
        let categoryGroups: [FeedCategoryGroup]
        var totalItems: Int { categoryGroups.reduce(0) { $0 + $1.items.count } }
    }

    // 日付セクション
    struct FeedDateSection: Identifiable {
        var id: String { dateLabel }
        let dateLabel: String
        let userGroups: [FeedUserGroup]
        var totalItems: Int { userGroups.reduce(0) { $0 + $1.totalItems } }
    }

    private var groupedItems: [FeedDateSection] {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: displayFeedItems) { item in
            cal.startOfDay(for: item.timestamp)
        }
        return byDay.keys.sorted(by: >).map { date in
            let label = cal.isDateInToday(date) ? "今日" :
                        cal.isDateInYesterday(date) ? "昨日" :
                        TomoView.dateGroupFormatter.string(from: date)
            let dayItems = byDay[date]!.sorted { $0.timestamp > $1.timestamp }

            // ① 日付内をユーザー別にグループ
            var seenUsers: [String] = []
            var byUser: [String: [EduLogHistoryItem]] = [:]
            for item in dayItems {
                let key = item.resolvedAuthorName
                if byUser[key] == nil { seenUsers.append(key); byUser[key] = [] }
                byUser[key]!.append(item)
            }

            let userGroups = seenUsers.map { userKey -> FeedUserGroup in
                let userItems = byUser[userKey]!
                let firstItem = userItems.first!

                // ② 各投稿を時系列のまま1件ずつカードに（カテゴリ集約なし）
                let catGroups = userItems.map { item in
                    FeedCategoryGroup(
                        categoryKey: item.id,
                        categoryEmoji: item.activityEmoji,
                        items: [item]
                    )
                }

                return FeedUserGroup(
                    authorName: userKey,
                    authorFirstName: firstItem.authorFirstName,
                    authorPhotoURL: firstItem.authorPhotoURL,
                    categoryGroups: catGroups
                )
            }
            return FeedDateSection(dateLabel: label, userGroups: userGroups)
        }
    }

    private var eduFeedSection: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── セクションヘッダー ──────────────────────────────────────────
            HStack(spacing: 8) {
                LinearGradient(
                    colors: [Color(hex: "#833ab4"), Color(hex: "#fd1d1d"), Color(hex: "#fcb045")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .frame(width: 24, height: 24)
                .mask(
                    Image(systemName: "camera.fill")
                        .font(.system(size: 13 * UIScale.font, weight: .bold))
                )

                Text("Daily")
                    .font(.system(size: 16 * UIScale.font, weight: .black))
                    .foregroundColor(Color.duoDark)
                + Text(" フィード")
                    .font(.system(size: 13 * UIScale.font, weight: .semibold))
                    .foregroundColor(Color.duoSubtitle)

                Spacer()

                if !eduLogManager.history.isEmpty {
                    Text("\(min(eduLogManager.history.count, 30))件")
                        .font(.system(size: 11 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoSubtitle.opacity(0.7))
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)

            // ── 投稿なし空状態 ────────────────────────────────────────────
            if groupedItems.isEmpty {
                VStack(spacing: 14) {
                    LinearGradient(
                        colors: [Color(hex: "#833ab4"), Color(hex: "#fd1d1d"), Color(hex: "#fcb045")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .frame(width: 56, height: 56)
                    .mask(
                        Image(systemName: "camera.fill")
                            .font(.system(size: 30 * UIScale.font))
                    )
                    Text("まだDailyフィードがありません")
                        .font(.system(size: 14 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoDark)
                    Text("スパイラルのアクティビティを記録すると\nここに写真と一緒に投稿されます")
                        .font(.system(size: 12 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            }

            // ── 日付グループ ───────────────────────────────────────────────
            ForEach(groupedItems) { section in
                VStack(alignment: .leading, spacing: 0) {
                    // 日付ラベル
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [Color(hex: "#833ab4"), Color(hex: "#fd1d1d")],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: 3, height: 14)
                            .cornerRadius(2)
                        Text(section.dateLabel)
                            .font(.system(size: 12 * UIScale.font, weight: .black))
                            .foregroundColor(Color.duoDark.opacity(0.75))
                        Text("・\(section.totalItems)件")
                            .font(.system(size: 10 * UIScale.font))
                            .foregroundColor(Color.duoSubtitle)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                    .padding(.bottom, 10)

                    // ── ユーザー別行 ───────────────────────────────────────
                    ForEach(section.userGroups) { userGroup in
                        VStack(alignment: .leading, spacing: 8) {
                            // ユーザーヘッダー：アバター＋名前＋件数
                            HStack(spacing: 8) {
                                UserAvatarView(
                                    name: userGroup.authorFirstName,
                                    photoURL: userGroup.authorPhotoURL.isEmpty
                                        ? (UserDefaults.standard.string(forKey: "cachedCurrentUserPhotoURL") ?? "")
                                        : userGroup.authorPhotoURL,
                                    size: 34
                                )
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(userGroup.authorFirstName)
                                        .font(.system(size: 13 * UIScale.font, weight: .black))
                                        .foregroundColor(Color.duoDark)
                                    Text("\(userGroup.totalItems)件の記録")
                                        .font(.system(size: 10 * UIScale.font))
                                        .foregroundColor(Color.duoSubtitle)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 4)

                            // カテゴリを横一列に並べる（件数に関わらず統一）
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 10) {
                                    ForEach(userGroup.categoryGroups) { catGroup in
                                        CategoryMiniCard(group: catGroup) { tappedItem in
                                            if catGroup.isSingle {
                                                selectedEduItem = tappedItem
                                            } else {
                                                categoryGroupTarget = catGroup
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 4)
                                .padding(.bottom, 4)
                            }
                        }
                        .padding(.bottom, 12)

                        // ユーザー間の区切り線
                        if userGroup.id != section.userGroups.last?.id {
                            Divider()
                                .padding(.horizontal, 4)
                                .padding(.bottom, 12)
                        }
                    }
                }
                .padding(.bottom, 4)
            }

            // ── 過去フィード展開ボタン ────────────────────────────────────
            if !showOlderFeed && hasOlderItems {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showOlderFeed = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 14 * UIScale.font, weight: .semibold))
                        Text("過去のフィードを表示")
                            .font(.system(size: 13 * UIScale.font, weight: .bold))
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11 * UIScale.font, weight: .semibold))
                    }
                    .foregroundColor(Color.duoBlue)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .background(Color.duoBlue.opacity(0.07))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            } else if showOlderFeed {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showOlderFeed = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11 * UIScale.font, weight: .semibold))
                        Text("2週間以内のみ表示")
                            .font(.system(size: 12 * UIScale.font, weight: .bold))
                    }
                    .foregroundColor(Color.duoSubtitle)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .clipped()
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    // MARK: - Header

    private var tomoHeader: some View {
        ZStack {
            LinearGradient(
                colors: [Color.duoBlue, Color(red: 0.06, green: 0.56, blue: 0.85)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea(edges: .top)
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image("mascot")
                        .resizable().scaledToFill()
                        .frame(width: 18, height: 18)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 0.4))
                    HStack(spacing: 0) {
                        Text("Tomo")
                            .foregroundColor(Color(red: 1.0, green: 0.29, blue: 0.10))
                        Text("lingo")
                            .foregroundColor(.white)
                    }
                    .font(.system(size: 14 * UIScale.font, weight: .black, design: .rounded))
                }
                Spacer()
                let tomoCount = manager.entries.filter { !$0.isMe }.count
                Button { showInviteSheet = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 11 * UIScale.font, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                        Text("\(tomoCount)")
                            .font(.system(size: 12 * UIScale.font, weight: .black))
                            .foregroundColor(.white)
                        Image(systemName: "plus")
                            .font(.system(size: 9 * UIScale.font, weight: .black))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

                HeaderNavigationMenu(selectedTab: $selectedTab, showRecordMenu: $showRecordMenu)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 46)
    }

    @ViewBuilder
    private var addResultView: some View {
        switch manager.addResult {
        case .idle:
            EmptyView()
        case .searching:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.75)
                Text("検索中...").font(.caption).foregroundColor(Color.duoSubtitle)
            }
        case .notFound(let email):
            VStack(alignment: .leading, spacing: 8) {
                Text("このメールアドレスのユーザーはまだFitingoに登録していません。招待を送りましょう！")
                    .font(.caption)
                    .foregroundColor(Color.duoSubtitle)
                Button {
                    shareText = "【Fitingo招待】\n\n\(email) さん、一緒にトレーニングしましょう！\n\nFitingoアプリをダウンロードしてTOMOになろう！\nhttps://apps.apple.com/app/fitingo"
                    showShareSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 11 * UIScale.font, weight: .bold))
                        Text("招待を送る")
                            .font(.system(size: 12 * UIScale.font, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color.duoBlue)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        case .added(let name):
            Label("\(name) をTOMOに追加しました！", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundColor(Color.duoGreen)
        case .alreadyAdded:
            Label("すでにTOMOです", systemImage: "info.circle.fill")
                .font(.caption).foregroundColor(Color.duoOrange)
        case .selfAdd:
            Label("自分自身は追加できません", systemImage: "xmark.circle.fill")
                .font(.caption).foregroundColor(Color.duoRed)
        case .error(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .font(.caption).foregroundColor(Color.duoRed)
        }
    }

    // MARK: - Ranking

    @ViewBuilder
    private var rankingSection: some View {
        if manager.isLoading && manager.entries.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("読み込み中...").font(.caption).foregroundColor(Color.duoSubtitle)
            }
            .frame(maxWidth: .infinity)
            .padding(32)
            .background(Color.white)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
        } else if manager.entries.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "person.2.slash")
                    .font(.system(size: 30 * UIScale.font))
                    .foregroundColor(Color.duoSubtitle)
                Text("まだTOMOがいません")
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(Color.duoSubtitle)
                Text("右上の👥+ボタンからTOMOを招待しよう！")
                    .font(.caption).foregroundColor(Color.duoSubtitle)
                    .multilineTextAlignment(.center)
                Button { showInviteSheet = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.plus")
                        Text("TOMOを招待する")
                    }
                    .font(.system(size: 13 * UIScale.font, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.duoBlue)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(32)
            .background(Color.white)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                rankingHeader
                ForEach(manager.entries) { entry in
                    rankRow(entry)
                    if entry.id != manager.entries.last?.id {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(Color.white)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
        }
    }

    private var rankingHeader: some View {
        HStack(spacing: 0) {
            Text("順位")
                .font(.system(size: 9 * UIScale.font, weight: .black))
                .foregroundColor(Color.duoSubtitle)
                .frame(width: 38, alignment: .center)
            Text("名前")
                .font(.system(size: 9 * UIScale.font, weight: .black))
                .foregroundColor(Color.duoSubtitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
            Text("今週pt")
                .font(.system(size: 9 * UIScale.font, weight: .black))
                .foregroundColor(Color.duoBlue)
                .frame(width: 50, alignment: .trailing)
            Text("累計")
                .font(.system(size: 9 * UIScale.font, weight: .semibold))
                .foregroundColor(Color.duoSubtitle)
                .frame(width: 44, alignment: .trailing)
            Text("連続")
                .font(.system(size: 9 * UIScale.font, weight: .semibold))
                .foregroundColor(Color.duoSubtitle)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.duoBg)
    }

    private func rankRow(_ entry: TomoManager.TomoEntry) -> some View {
        HStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(rankBadgeColor(entry.rank))
                    .frame(width: 26, height: 26)
                Text("\(entry.rank)")
                    .font(.system(size: 10 * UIScale.font, weight: .black))
                    .foregroundColor(.white)
            }
            .frame(width: 38)

            HStack(spacing: 4) {
                Text(firstName(of: entry.username))
                    .font(.system(size: 13 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoDark)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if entry.isMe {
                    Text("YOU")
                        .font(.system(size: 7 * UIScale.font, weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(Color.duoBlue)
                        .cornerRadius(4)
                }
            }
            .padding(.leading, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()

            VStack(spacing: 0) {
                Text("\(entry.weeklyPoints)")
                    .font(.system(size: 13 * UIScale.font, weight: .black))
                    .foregroundColor(Color.duoBlue)
                    .minimumScaleFactor(0.7)
                Text("pt")
                    .font(.system(size: 7 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoSubtitle)
            }
            .frame(width: 50, alignment: .trailing)

            VStack(spacing: 0) {
                Text("\(entry.totalPoints)")
                    .font(.system(size: 10 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoDark)
                    .minimumScaleFactor(0.7)
                Text("pt")
                    .font(.system(size: 7 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoSubtitle)
            }
            .frame(width: 44, alignment: .trailing)

            VStack(spacing: 0) {
                HStack(spacing: 1) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 7 * UIScale.font))
                        .foregroundColor(Color(hex: "#FF9600"))
                    Text("\(entry.streak)")
                        .font(.system(size: 10 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoDark)
                        .minimumScaleFactor(0.7)
                }
                Text("日")
                    .font(.system(size: 7 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoSubtitle)
            }
            .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(entry.isMe ? Color.duoBlue.opacity(0.05) : Color.clear)
        .contextMenu {
            if !entry.isMe {
                Button(role: .destructive) {
                    Task { await manager.removeTomo(id: entry.id) }
                } label: {
                    Label("TOMOから削除", systemImage: "person.badge.minus")
                }
            }
        }
    }

    /// スペース区切りで最初の単語（名前部分）だけを返す
    private func firstName(of name: String) -> String {
        guard !name.isEmpty else { return name }
        return String(name.split(separator: " ").first ?? Substring(name))
    }

    private func rankBadgeColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color.duoYellow
        case 2: return Color(hex: "#90A4AE")
        case 3: return Color.duoOrange
        default: return Color.duoBlue.opacity(0.55)
        }
    }
}
