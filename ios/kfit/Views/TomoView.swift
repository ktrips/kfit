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
    @State private var deleteConfirmItem: EduLogHistoryItem? = nil
    @FocusState private var emailFocused: Bool

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        rankingSection
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
                            .padding(.bottom, 14)
                        eduFeedSection
                        Spacer(minLength: 40)
                    }
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
            FeedCommentsSheet(item: item, eduLogManager: eduLogManager,
                              photoLogManager: photoLogManager)
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
        .confirmationDialog("この投稿を削除しますか？", isPresented: Binding(
            get: { deleteConfirmItem != nil },
            set: { if !$0 { deleteConfirmItem = nil } }
        ), titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                if let item = deleteConfirmItem { deleteFeedItem(item) }
                deleteConfirmItem = nil
            }
            Button("キャンセル", role: .cancel) { deleteConfirmItem = nil }
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
        item.isLiked = food.isLiked
        item.likeCount = food.likeCount
        item.feedComments = food.feedComments
        return item
    }

    // MARK: - フィードアクションルーティング

    /// いいね：food_ プレフィックスで PhotoLogManager か EduLogManager に振り分け
    private func toggleLikeFeed(_ item: EduLogHistoryItem) {
        if item.id.hasPrefix("food_") {
            let originalId = String(item.id.dropFirst("food_".count))
            photoLogManager.toggleLike(id: originalId)
        } else {
            eduLogManager.toggleLike(id: item.id)
        }
    }

    /// 削除：自分の投稿のみ（確認ダイアログ経由）
    private func deleteFeedItem(_ item: EduLogHistoryItem) {
        if item.id.hasPrefix("food_") {
            let originalId = String(item.id.dropFirst("food_".count))
            photoLogManager.deleteHistoryItem(id: originalId)
        } else {
            eduLogManager.deleteItem(id: item.id)
        }
    }

    /// 自分の投稿かどうか
    private func isOwnPost(_ item: EduLogHistoryItem) -> Bool {
        let myName = AuthenticationManager.shared.userProfile?.username
            ?? UserDefaults.standard.string(forKey: "cachedCurrentUserName")
            ?? ""
        return item.authorName == myName || item.authorName.isEmpty
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

    // MARK: - Instagram 縦フィード

    /// 日付ごとにグループ化した投稿リスト
    private var instagramGroups: [(label: String, date: Date, items: [EduLogHistoryItem])] {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: displayFeedItems) { item in
            cal.startOfDay(for: item.timestamp)
        }
        return byDay.keys.sorted(by: >).map { date in
            let label = cal.isDateInToday(date) ? "今日" :
                        cal.isDateInYesterday(date) ? "昨日" :
                        TomoView.dateGroupFormatter.string(from: date)
            return (label: label, date: date,
                    items: (byDay[date] ?? []).sorted { $0.timestamp > $1.timestamp })
        }
    }

    private var eduFeedSection: some View {
        VStack(spacing: 0) {
            // ── 空状態 ───────────────────────────────────────────────────
            if instagramGroups.isEmpty {
                VStack(spacing: 18) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color(hex: "#833ab4").opacity(0.15), Color(hex: "#fcb045").opacity(0.15)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 88, height: 88)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 34 * UIScale.font, weight: .light))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "#833ab4"), Color(hex: "#fd1d1d"), Color(hex: "#fcb045")],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                    }
                    Text("まだ投稿がありません")
                        .font(.system(size: 16 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoDark)
                    Text("アクティビティを記録すると\nここに自動投稿されます")
                        .font(.system(size: 13 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
                .background(Color(.systemBackground))
            }

            // ── 投稿一覧 ──────────────────────────────────────────────────
            ForEach(instagramGroups, id: \.label) { group in
                // 日付ラベル
                HStack {
                    Text(group.label)
                        .font(.system(size: 11 * UIScale.font, weight: .black))
                        .foregroundColor(Color.duoSubtitle)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(UIColor.systemGroupedBackground))

                // 投稿カード
                ForEach(group.items) { item in
                    instaPostCard(item)
                    Divider()
                }
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
                        Text("過去の投稿を見る")
                            .font(.system(size: 13 * UIScale.font, weight: .bold))
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11 * UIScale.font, weight: .semibold))
                    }
                    .foregroundColor(Color.duoBlue)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 20)
                    .background(Color(.systemBackground))
                }
                .buttonStyle(.plain)
            } else if showOlderFeed {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showOlderFeed = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11 * UIScale.font, weight: .semibold))
                        Text("2週間以内のみ表示")
                            .font(.system(size: 12 * UIScale.font, weight: .bold))
                    }
                    .foregroundColor(Color.duoSubtitle)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemBackground))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Insta 投稿カード（1件）

    private func instaPostCard(_ item: EduLogHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── ポストヘッダー ────────────────────────────────────────────
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color(hex: "#833ab4"), Color(hex: "#fd1d1d"), Color(hex: "#fcb045")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 42, height: 42)
                    Circle()
                        .fill(Color(.systemBackground))
                        .frame(width: 37, height: 37)
                    UserAvatarView(
                        name: item.authorFirstName,
                        photoURL: item.authorPhotoURL.isEmpty
                            ? (UserDefaults.standard.string(forKey: "cachedCurrentUserPhotoURL") ?? "")
                            : item.authorPhotoURL,
                        size: 33
                    )
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.authorFirstName)
                        .font(.system(size: 13 * UIScale.font, weight: .black))
                        .foregroundColor(Color.duoDark)
                    Text(relativeTimeString(item.timestamp))
                        .font(.system(size: 11 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)
                }

                Spacer()

                // アクティビティタグ
                HStack(spacing: 3) {
                    Text(item.activityEmoji.isEmpty ? "📝" : item.activityEmoji)
                        .font(.system(size: 12 * UIScale.font))
                    Text(item.activityName)
                        .font(.system(size: 10 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color.duoSubtitle)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color(.systemGray6))
                .cornerRadius(10)

                // 三点メニュー（自分の投稿のみ削除を表示）
                Menu {
                    if isOwnPost(item) {
                        Button(role: .destructive) {
                            deleteConfirmItem = item
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                    }
                    Button {
                        shareTargetItem = item
                    } label: {
                        Label("シェア", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color.duoSubtitle)
                        .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // ── フルサイズ写真 or グラデーション＋絵文字 ──────────────────
            Button { selectedEduItem = item } label: {
                if let thumb = item.thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                } else {
                    ZStack {
                        instaGradient(for: item)
                        Text(item.activityEmoji.isEmpty ? "📝" : item.activityEmoji)
                            .font(.system(size: 96 * UIScale.font))
                            .shadow(color: .black.opacity(0.25), radius: 12)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260, maxHeight: 320)
                }
            }
            .buttonStyle(.plain)

            // ── アクションボタン行 ────────────────────────────────────────
            HStack(spacing: 0) {
                // いいね
                Button {
                    toggleLikeFeed(item)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 24 * UIScale.font, weight: .regular))
                            .foregroundColor(item.isLiked ? Color(hex: "#ED4956") : Color.duoDark)
                        if item.likeCount > 0 {
                            Text("\(item.likeCount)")
                                .font(.system(size: 13 * UIScale.font, weight: .bold))
                                .foregroundColor(Color.duoDark)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                // コメント
                Button {
                    commentTargetItem = item
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 22 * UIScale.font, weight: .regular))
                            .foregroundColor(Color.duoDark)
                        if !item.feedComments.isEmpty {
                            Text("\(item.feedComments.count)")
                                .font(.system(size: 13 * UIScale.font, weight: .bold))
                                .foregroundColor(Color.duoDark)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                // シェア
                Button {
                    shareTargetItem = item
                } label: {
                    Image(systemName: "paperplane")
                        .font(.system(size: 22 * UIScale.font, weight: .regular))
                        .foregroundColor(Color.duoDark)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 4)

            // ── キャプション ──────────────────────────────────────────────
            if !item.comment.isEmpty {
                (Text(item.authorFirstName + "  ").font(.system(size: 13 * UIScale.font, weight: .black))
                 + Text(item.comment).font(.system(size: 13 * UIScale.font)))
                    .foregroundColor(Color.duoDark)
                    .lineLimit(4)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            } else {
                Spacer().frame(height: 4)
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - ヘルパー

    private func relativeTimeString(_ date: Date) -> String {
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 60 { return "たった今" }
        if diff < 3600 { return "\(diff / 60)分前" }
        if diff < 86400 { return "\(diff / 3600)時間前" }
        return "\(diff / 86400)日前"
    }

    private func instaGradient(for item: EduLogHistoryItem) -> LinearGradient {
        let palettes: [[Color]] = [
            [Color(hex: "#833ab4"), Color(hex: "#fd1d1d"), Color(hex: "#fcb045")],
            [Color(hex: "#1CB5E0"), Color(hex: "#4776E6")],
            [Color(hex: "#11998e"), Color(hex: "#38ef7d")],
            [Color(hex: "#f7971e"), Color(hex: "#ffd200")],
            [Color(hex: "#f953c6"), Color(hex: "#b91d73")],
            [Color(hex: "#00b09b"), Color(hex: "#96c93d")],
        ]
        let idx = abs(item.id.hashValue) % palettes.count
        return LinearGradient(colors: palettes[idx], startPoint: .topLeading, endPoint: .bottomTrailing)
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
                // ロゴ
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

                // 参加者アバター（自分＋TOMO）をインライン表示
                HStack(spacing: -8) {
                    ForEach(manager.entries.prefix(4)) { entry in
                        headerAvatarCircle(entry)
                    }
                    // 招待ボタン
                    Button { showInviteSheet = true } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.25))
                                .frame(width: 32, height: 32)
                                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 12 * UIScale.font, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                }

                HeaderNavigationMenu(selectedTab: $selectedTab, showRecordMenu: $showRecordMenu)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 46)
    }

    private func headerAvatarCircle(_ entry: TomoManager.TomoEntry) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color(hex: "#833ab4"), Color(hex: "#fd1d1d"), Color(hex: "#fcb045")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 34, height: 34)
            Circle()
                .fill(Color.white)
                .frame(width: 30, height: 30)
            UserAvatarView(
                name: firstName(of: entry.username),
                photoURL: "",
                size: 26
            )
        }
        .overlay(Circle().stroke(Color.white, lineWidth: 1.5).frame(width: 34, height: 34))
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


    // MARK: - Ranking（コンパクトカード）

    @ViewBuilder
    private var rankingSection: some View {
        if manager.isLoading && manager.entries.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("読み込み中...").font(.caption).foregroundColor(Color.duoSubtitle)
            }
            .frame(maxWidth: .infinity)
            .padding(32)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
        } else if manager.entries.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "person.2.slash")
                    .font(.system(size: 34 * UIScale.font))
                    .foregroundColor(Color.duoSubtitle.opacity(0.5))
                Text("まだTOMOがいません")
                    .font(.system(size: 15 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoSubtitle)
                Text("右上の👥+ボタンからTOMOを招待しよう！")
                    .font(.system(size: 12 * UIScale.font))
                    .foregroundColor(Color.duoSubtitle)
                    .multilineTextAlignment(.center)
                Button { showInviteSheet = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.plus")
                        Text("TOMOを招待する")
                    }
                    .font(.system(size: 13 * UIScale.font, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(Color.duoBlue)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(32)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
        } else {
            VStack(spacing: 0) {
                // セクションタイトル
                HStack {
                    Text("🏆 今週のランキング")
                        .font(.system(size: 13 * UIScale.font, weight: .black))
                        .foregroundColor(Color.duoDark)
                    Spacer()
                    Text("今週pt")
                        .font(.system(size: 9 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoBlue)
                        .frame(width: 50, alignment: .trailing)
                    Text("連続")
                        .font(.system(size: 9 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoSubtitle)
                        .frame(width: 40, alignment: .trailing)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "#1CB5E0").opacity(0.08), Color(hex: "#4776E6").opacity(0.08)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )

                ForEach(manager.entries) { entry in
                    rankRow(entry)
                    if entry.id != manager.entries.last?.id {
                        Divider().padding(.leading, 62)
                    }
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.07), radius: 8, y: 2)
        }
    }

    private func rankRow(_ entry: TomoManager.TomoEntry) -> some View {
        HStack(spacing: 10) {
            // アバター＋順位バッジ
            ZStack(alignment: .bottomTrailing) {
                UserAvatarView(name: firstName(of: entry.username), photoURL: "", size: 38)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))

                Circle()
                    .fill(rankBadgeColor(entry.rank))
                    .frame(width: 16, height: 16)
                    .overlay(
                        Text(entry.rank <= 3 ? rankEmoji(entry.rank) : "\(entry.rank)")
                            .font(.system(size: entry.rank <= 3 ? 10 : 8, weight: .black))
                            .foregroundColor(entry.rank <= 3 ? .white : .white)
                    )
                    .offset(x: 2, y: 2)
            }
            .frame(width: 44)

            // 名前
            HStack(spacing: 5) {
                Text(firstName(of: entry.username))
                    .font(.system(size: 14 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoDark)
                    .lineLimit(1)
                if entry.isMe {
                    Text("YOU")
                        .font(.system(size: 8 * UIScale.font, weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.duoBlue)
                        .cornerRadius(5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 今週pt
            VStack(spacing: 0) {
                Text("\(entry.weeklyPoints)")
                    .font(.system(size: 14 * UIScale.font, weight: .black))
                    .foregroundColor(Color.duoBlue)
                    .minimumScaleFactor(0.6)
                Text("pt")
                    .font(.system(size: 8 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoSubtitle)
            }
            .frame(width: 50, alignment: .trailing)

            // 連続
            HStack(spacing: 2) {
                Text("🔥")
                    .font(.system(size: 11 * UIScale.font))
                Text("\(entry.streak)日")
                    .font(.system(size: 11 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoDark)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(entry.isMe
            ? LinearGradient(colors: [Color.duoBlue.opacity(0.06), Color.duoBlue.opacity(0.03)],
                             startPoint: .leading, endPoint: .trailing)
            : LinearGradient(colors: [Color.clear], startPoint: .leading, endPoint: .trailing)
        )
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

    private func rankEmoji(_ rank: Int) -> String {
        switch rank {
        case 1: return "🥇"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return "\(rank)"
        }
    }

    /// スペース区切りで最初の単語（名前部分）だけを返す
    private func firstName(of name: String) -> String {
        guard !name.isEmpty else { return name }
        return String(name.split(separator: " ").first ?? Substring(name))
    }

    private func rankBadgeColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(hex: "#FFD700")
        case 2: return Color(hex: "#90A4AE")
        case 3: return Color(hex: "#CD7F32")
        default: return Color.duoBlue.opacity(0.6)
        }
    }
}
