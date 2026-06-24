import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - 非同期タイムアウト

struct AsyncTimeoutError: Error {}

/// 指定秒数以内に終わらない非同期処理をタイムアウトさせる。
/// Firestore の getDocuments はオフライン永続キャッシュ有効時に応答が返らず
/// ハングすることがあるため、UIが固まらないよう保険として使用する。
func withAsyncTimeout<T: Sendable>(
    seconds: Double,
    _ operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw AsyncTimeoutError()
        }
        guard let result = try await group.next() else { throw AsyncTimeoutError() }
        group.cancelAll()
        return result
    }
}

// MARK: - TomoManager

/// emailLower 検索の結果（タスクグループ越えのため Sendable）
struct TomoSearchResult: Sendable {
    let id: String
    let username: String
    var email: String = ""
    var totalPoints: Int = 0
    var streak: Int = 0
    var weeklyPoints: Int = 0
    var photoURL: String = ""
}

/// 友達の公開プロフィール（タスクグループ越えのため Sendable）
struct FriendProfile: Sendable {
    let email: String
    let username: String
    let totalPoints: Int
    let streak: Int
    let weeklyPoints: Int
}

/// 友達の公開投稿（タスクグループ越えのため Sendable な素データ）
struct FriendPostData: Sendable {
    let id: String
    let timestamp: Date
    let activityName: String
    let activityEmoji: String
    let comment: String
    let authorName: String
    let authorPhotoURL: String
    let likeCount: Int
    let thumbnailData: Data?
    let weightKg: Double?
    let bodyFatPercent: Double?
    let extractedPhrase: String?
    let extractedLanguageCode: String?
    let translationJA: String?
    let pronunciation: String?
    let calories: Int?
}

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
        case notFound(String)        // email → show share sheet
        case added(TomoSearchResult) // success → 友達のプロフィール情報
        case alreadyAdded
        case selfAdd
        case error(String)
    }

    @Published var entries: [TomoEntry] = []
    @Published var isLoading = false
    @Published var addResult: AddResult = .idle
    /// 友達の公開投稿（TOMOフィードにマージ）
    @Published var friendFeedItems: [EduLogHistoryItem] = []

    private let db = Firestore.firestore()
    private static var didBackfillPublicPosts = false

    /// 2人のuidから決定的な friendship ドキュメントIDを生成
    private func friendshipId(_ a: String, _ b: String) -> String {
        [a, b].sorted().joined(separator: "_")
    }

    func load() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }

        // 自分の既存公開投稿を一度だけバックフィル（機能導入前の投稿を友達に見せるため）
        if !Self.didBackfillPublicPosts {
            Self.didBackfillPublicPosts = true
            EduLogManager.shared.syncAllPublicPosts()
            PhotoLogManager.shared.syncAllPublicPosts()
        }

        var all: [TomoEntry] = []

        // Self（自分の週間ポイントは completed-exercises から計算できる）
        let myWeekly = await weeklyPoints(userId: uid)
        if let me = AuthenticationManager.shared.userProfile {
            all.append(TomoEntry(id: uid, email: me.email, username: me.username,
                                 totalPoints: me.totalPoints, streak: me.streak,
                                 weeklyPoints: myWeekly, isMe: true))
            // 友達がランキングで参照できるよう、自分の週間ポイントを公開プロフィールへ反映
            let myPoints = me.totalPoints
            let myStreak = me.streak
            try? await withAsyncTimeout(seconds: 12) {
                try await Firestore.firestore().collection("publicProfiles").document(uid).setData([
                    "weeklyPoints": myWeekly,
                    "totalPoints": myPoints,
                    "streak": myStreak,
                    "updatedAt": Timestamp(date: Date())
                ], merge: true)
            }
        }

        // 友達（friendships の members に自分が含まれるもの）
        let friendIds: [String] = (try? await withAsyncTimeout(seconds: 12) {
            let snap = try await Firestore.firestore().collection("friendships")
                .whereField("members", arrayContains: uid)
                .getDocuments()
            var ids: [String] = []
            for doc in snap.documents {
                let members = doc.data()["members"] as? [String] ?? []
                if let other = members.first(where: { $0 != uid }) {
                    ids.append(other)
                }
            }
            return ids
        }) ?? []

        // 友達の公開プロフィール（ランキング用）
        for fid in friendIds {
            let profile = try? await withAsyncTimeout(seconds: 12) { () -> FriendProfile? in
                let pdoc = try await Firestore.firestore()
                    .collection("publicProfiles").document(fid).getDocument()
                guard pdoc.exists, let data = pdoc.data() else { return nil }
                return FriendProfile(
                    email: data["email"] as? String ?? "",
                    username: data["username"] as? String ?? "TOMO",
                    totalPoints: data["totalPoints"] as? Int ?? 0,
                    streak: data["streak"] as? Int ?? 0,
                    weeklyPoints: data["weeklyPoints"] as? Int ?? 0
                )
            }
            guard let p = profile ?? nil else { continue }
            all.append(TomoEntry(
                id: fid,
                email: p.email,
                username: p.username,
                totalPoints: p.totalPoints,
                streak: p.streak,
                weeklyPoints: p.weeklyPoints
            ))
        }

        all.sort { $0.weeklyPoints > $1.weeklyPoints }
        for i in all.indices { all[i].rank = i + 1 }
        entries = all

        await loadFriendFeed(friendIds: friendIds)
    }

    /// 友達の公開投稿を取得してフィード用アイテムに変換（タイムアウト付き）
    private func loadFriendFeed(friendIds: [String]) async {
        guard !friendIds.isEmpty else { friendFeedItems = []; return }
        var items: [EduLogHistoryItem] = []
        for fid in friendIds {
            let posts: [FriendPostData] = (try? await withAsyncTimeout(seconds: 12) {
                let snap = try await Firestore.firestore()
                    .collection("publicProfiles").document(fid)
                    .collection("posts")
                    .order(by: "timestamp", descending: true)
                    .limit(to: 50)
                    .getDocuments()
                return snap.documents.map { doc -> FriendPostData in
                    let data = doc.data()
                    return FriendPostData(
                        id: "friend_\(fid)_\(doc.documentID)",
                        timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
                        activityName: data["activityName"] as? String ?? "",
                        activityEmoji: data["activityEmoji"] as? String ?? "",
                        comment: data["comment"] as? String ?? "",
                        authorName: data["authorName"] as? String ?? "TOMO",
                        authorPhotoURL: data["authorPhotoURL"] as? String ?? "",
                        likeCount: data["likeCount"] as? Int ?? 0,
                        thumbnailData: (data["thumbnail"] as? String).flatMap { Data(base64Encoded: $0) },
                        weightKg: data["weightKg"] as? Double,
                        bodyFatPercent: data["bodyFatPercent"] as? Double,
                        extractedPhrase: data["extractedPhrase"] as? String,
                        extractedLanguageCode: data["extractedLanguageCode"] as? String,
                        translationJA: data["translationJA"] as? String,
                        pronunciation: data["pronunciation"] as? String,
                        calories: data["calories"] as? Int
                    )
                }
            }) ?? []
            for p in posts { items.append(makeFriendItem(from: p)) }
        }
        friendFeedItems = items
    }

    /// Sendable な素データからフィード用 EduLogHistoryItem を構築
    private func makeFriendItem(from p: FriendPostData) -> EduLogHistoryItem {
        var item = EduLogHistoryItem(
            activityName: p.activityName,
            activityEmoji: p.activityEmoji,
            comment: p.comment,
            authorName: p.authorName,
            authorPhotoURL: p.authorPhotoURL,
            isPublic: true
        )
        item.id = p.id
        item.timestamp = p.timestamp
        item.likeCount = p.likeCount
        item.thumbnailData = p.thumbnailData
        item.weightKg = p.weightKg
        item.bodyFatPercent = p.bodyFatPercent
        item.extractedPhrase = p.extractedPhrase
        item.extractedLanguageCode = p.extractedLanguageCode
        item.translationJA = p.translationJA
        item.pronunciation = p.pronunciation
        item.calories = p.calories
        return item
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

        // 公開プロフィールを emailLower（小文字正規化）で検索（タイムアウト付き）
        let found: TomoSearchResult?
        do {
            found = try await withAsyncTimeout(seconds: 12) {
                let snap = try await Firestore.firestore()
                    .collection("publicProfiles")
                    .whereField("emailLower", isEqualTo: email)
                    .limit(to: 1)
                    .getDocuments()
                guard let doc = snap.documents.first else { return nil }
                let d = doc.data()
                return TomoSearchResult(
                    id: doc.documentID,
                    username: d["username"] as? String ?? email,
                    email: d["email"] as? String ?? email,
                    totalPoints: d["totalPoints"] as? Int ?? 0,
                    streak: d["streak"] as? Int ?? 0,
                    weeklyPoints: d["weeklyPoints"] as? Int ?? 0,
                    photoURL: d["photoURL"] as? String ?? ""
                )
            }
        } catch is AsyncTimeoutError {
            addResult = .error("通信に時間がかかっています。ネットワークを確認して、もう一度お試しください")
            return
        } catch {
            addResult = .error("検索に失敗しました。時間をおいて再度お試しください")
            return
        }

        guard let tomo = found else {
            addResult = .notFound(email); return
        }
        guard tomo.id != uid else { addResult = .selfAdd; return }

        // 相互の友達関係を1ドキュメントで作成（双方が読み書き可能）
        let pairId = friendshipId(uid, tomo.id)
        do {
            try await withAsyncTimeout(seconds: 12) {
                try await Firestore.firestore()
                    .collection("friendships").document(pairId)
                    .setData([
                        "members": [uid, tomo.id],
                        "createdAt": Timestamp(date: Date())
                    ], merge: true)
            }
        } catch {
            addResult = .error("TOMOの追加に失敗しました。時間をおいて再度お試しください")
            return
        }

        addResult = .added(tomo)
        await load()
    }

    func removeTomo(id: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let pairId = friendshipId(uid, id)
        try? await db.collection("friendships").document(pairId).delete()
        entries.removeAll { $0.id == id }
        for i in entries.indices { entries[i].rank = i + 1 }
        friendFeedItems.removeAll { $0.id.hasPrefix("friend_\(id)_") }
    }

    private func weeklyPoints(userId: String) async -> Int {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)  // 1=Sun, 2=Mon...
        let daysSinceMonday = weekday == 1 ? 6 : weekday - 2
        guard let monday = calendar.date(byAdding: .day, value: -daysSinceMonday,
                                         to: calendar.startOfDay(for: today)) else { return 0 }
        let points: [Int] = (try? await withAsyncTimeout(seconds: 12) {
            let snap = try await Firestore.firestore()
                .collection("users").document(userId)
                .collection("completed-exercises")
                .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: monday))
                .getDocuments()
            return snap.documents.compactMap { $0.data()["points"] as? Int }
        }) ?? []
        return points.reduce(0, +)
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

// MARK: - クイック記録カテゴリ

struct TomoQuickRecord: Identifiable {
    let id: String
    let label: String
    let emoji: String
    let color: Color
    let isFood: Bool   // true → フォトログ(PhotoLogView)、false → EduPhotoLogSheet
}

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
    @State private var selectedFoodItem: PhotoLogHistoryItem? = nil   // FOOD投稿の詳細
    @State private var commentTargetItem: EduLogHistoryItem? = nil
    @State private var shareTargetItem: EduLogHistoryItem? = nil
    @State private var categoryGroupTarget: TomoView.FeedCategoryGroup? = nil
    @State private var showOlderFeed = false
    @State private var showInviteSheet = false
    @State private var deleteConfirmItem: EduLogHistoryItem? = nil
    @State private var speakingItemID: String? = nil   // TTS 再生中のアイテム ID
    @State private var showFoodLog = false             // FOOD → フォトログ
    @State private var eduRecordTarget: TomoQuickRecord? = nil  // 写真記録シート対象
    @State private var selectedCategory: String? = nil  // カテゴリー絞り込み（nil=すべて）
    @FocusState private var emailFocused: Bool

    // フィード集計のキャッシュ（body 毎の merge+sort+grouping 再計算を回避）
    @State private var cachedFeedGroups: [FeedDayGroup] = []
    @State private var cachedFeedCategories: [FeedCategoryChip] = []
    @State private var cachedHasOlderFeed: Bool = false

    // クイック記録カテゴリ（ランキング上部・ヘッダー＋から起動）
    private let quickRecords: [TomoQuickRecord] = [
        TomoQuickRecord(id: "food",     label: "FOOD",     emoji: "🍽️", color: Color(hex: "#FF9600"), isFood: true),
        TomoQuickRecord(id: "duolingo", label: "Duolingo", emoji: "🦉", color: Color(hex: "#58CC02"), isFood: false),
        TomoQuickRecord(id: "diary",    label: "日記",     emoji: "📔", color: Color(hex: "#CE82FF"), isFood: false),
        TomoQuickRecord(id: "reading",  label: "読書",     emoji: "📖", color: Color(hex: "#1CB0F6"), isFood: false),
        TomoQuickRecord(id: "study",    label: "勉強",     emoji: "✏️", color: Color(hex: "#FF4B4B"), isFood: false),
        TomoQuickRecord(id: "other",    label: "その他",   emoji: "✨", color: Color(hex: "#FFC800"), isFood: false),
    ]

    private func handleQuickRecord(_ rec: TomoQuickRecord) {
        if rec.isFood {
            showFoodLog = true
        } else {
            eduRecordTarget = rec
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        quickRecordBar
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
                        rankingSection
                            .padding(.horizontal, 14)
                            .padding(.top, 12)
                            .padding(.bottom, 14)
                        categoryFilterBar
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
        .onAppear { rebuildFeedCache() }
        .onReceive(eduLogManager.$history) { _ in
            DispatchQueue.main.async { rebuildFeedCache() }
        }
        .onReceive(photoLogManager.$history) { _ in
            DispatchQueue.main.async { rebuildFeedCache() }
        }
        .onReceive(manager.$friendFeedItems) { _ in
            DispatchQueue.main.async { rebuildFeedCache() }
        }
        .onChange(of: selectedCategory) { _, _ in rebuildFeedCache() }
        .onChange(of: showOlderFeed) { _, _ in rebuildFeedCache() }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [shareText])
        }
        .sheet(item: $selectedEduItem) { item in
            EduFeedDetailSheet(item: item)
        }
        .sheet(item: $selectedFoodItem) { item in
            PhotoFeedDetailSheet(item: item)
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
                onTapItem: { openDetail($0); categoryGroupTarget = nil },
                onLike: { eduLogManager.toggleLike(id: $0.id) },
                onComment: { commentTargetItem = $0; categoryGroupTarget = nil },
                onShare: { shareTargetItem = $0; categoryGroupTarget = nil }
            )
        }
        .sheet(isPresented: $showInviteSheet) {
            inviteSheet
        }
        .fullScreenCover(isPresented: $showFoodLog) {
            PhotoLogView()
        }
        .sheet(item: $eduRecordTarget) { rec in
            EduPhotoLogSheet(
                nodeEmoji: rec.emoji,
                nodeName: rec.label,
                onComplete: { saveToFeed, isPublic, image, comment in
                    eduRecordTarget = nil
                    if saveToFeed {
                        EduLogManager.shared.addItem(
                            activityName: rec.label,
                            activityEmoji: rec.emoji,
                            comment: comment,
                            image: image,
                            isPublic: isPublic
                        )
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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

    /// FOOD投稿（food_ プレフィックス）の元データを取得
    private func originalFoodItem(for item: EduLogHistoryItem) -> PhotoLogHistoryItem? {
        guard item.id.hasPrefix("food_") else { return nil }
        let originalId = String(item.id.dropFirst("food_".count))
        return photoLogManager.history.first { $0.id == originalId }
    }

    /// FOOD投稿のカロリー（FOOD以外は nil）。友達の投稿はアイテム自身の calories を使用
    private func foodCalories(for item: EduLogHistoryItem) -> Int? {
        if let local = originalFoodItem(for: item)?.calories { return local }
        return item.calories
    }

    /// 投稿タップ時のルーティング：FOODはFOOD詳細、それ以外はEduFeed詳細
    private func openDetail(_ item: EduLogHistoryItem) {
        if let food = originalFoodItem(for: item) {
            selectedFoodItem = food
        } else {
            selectedEduItem = item
        }
    }

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
        if item.id.hasPrefix("friend_") { return false }
        let myName = AuthenticationManager.shared.userProfile?.username
            ?? UserDefaults.standard.string(forKey: "cachedCurrentUserName")
            ?? ""
        return item.authorName == myName || item.authorName.isEmpty
    }

    /// アクティビティ＋食事ログ＋友達の公開投稿を統合したフィード全件（公開のもののみ）
    private var allFeedItems: [EduLogHistoryItem] {
        let activity = eduLogManager.history.filter { $0.isPublic }
        let food     = photoLogManager.history.filter { $0.isPublic }.map { makeFoodFeedItem($0) }
        let friends  = manager.friendFeedItems
        return (activity + food + friends).sorted { $0.timestamp > $1.timestamp }
    }

    /// activityName をグループ化したカテゴリー表記（FIT / FOOD / EDU / DIARY / OTHERS）と代表絵文字
    private func categoryInfo(for item: EduLogHistoryItem) -> (label: String, emoji: String) {
        let name = item.activityName.trimmingCharacters(in: .whitespaces)
        switch name {
        case "体重ログ":
            return ("FIT", "💪")
        case "食事ログ":
            return ("FOOD", "🍽")
        case "読書", "勉強":
            return ("EDU", "📚")
        case "日記", "フォト日記":
            return ("DIARY", "📔")
        default:
            if name.localizedCaseInsensitiveContains("Duolingo") {
                return ("Duolingo", "🦉")
            }
            return ("OTHERS", "📝")
        }
    }

    /// アイテムのカテゴリーキー（FIT / FOOD / EDU / DIARY / OTHERS）
    private func categoryKey(for item: EduLogHistoryItem) -> String {
        categoryInfo(for: item).label
    }

    /// アイテムのカテゴリー代表絵文字
    private func categoryEmoji(for item: EduLogHistoryItem) -> String {
        categoryInfo(for: item).emoji
    }

    // フィードの集計（カテゴリー一覧・表示対象・過去有無・日付グループ）は
    // rebuildFeedCache() に集約し、結果を cachedFeed* に保持する。

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

    // MARK: - Instagram 縦フィード

    // カテゴリーチップ（キャッシュ用）
    struct FeedCategoryChip: Identifiable {
        var id: String { key }
        let key: String
        let emoji: String
    }

    // 日付グループ（キャッシュ用）
    struct FeedDayGroup: Identifiable {
        var id: String { label }
        let label: String
        let items: [EduLogHistoryItem]
    }

    /// フィード集計を 1 回だけ実行してキャッシュに格納する。
    /// `allFeedItems`（2履歴の filter+merge+sort）は body 評価ごとに複数回呼ばれていたため、
    /// 履歴・絞り込み・表示範囲が変化したときだけ再計算する。
    private func rebuildFeedCache() {
        let all = allFeedItems

        // カテゴリーチップ
        var seen = Set<String>()
        var cats: [FeedCategoryChip] = []
        for item in all {
            let info = categoryInfo(for: item)
            if seen.insert(info.label).inserted {
                cats.append(FeedCategoryChip(key: info.label, emoji: info.emoji))
            }
        }
        cachedFeedCategories = cats

        // 表示対象（直近2週間 or 全件 ＋ カテゴリー絞り込み）
        var items = showOlderFeed ? all : all.filter { $0.timestamp >= twoWeeksAgo }
        if let cat = selectedCategory {
            items = items.filter { categoryKey(for: $0) == cat }
        }

        // 日付グループ化
        let cal = Calendar.current
        let byDay = Dictionary(grouping: items) { cal.startOfDay(for: $0.timestamp) }
        cachedFeedGroups = byDay.keys.sorted(by: >).map { date in
            let label = cal.isDateInToday(date) ? "今日" :
                        cal.isDateInYesterday(date) ? "昨日" :
                        TomoView.dateGroupFormatter.string(from: date)
            return FeedDayGroup(label: label,
                                items: (byDay[date] ?? []).sorted { $0.timestamp > $1.timestamp })
        }

        // 過去フィードの有無
        if showOlderFeed {
            cachedHasOlderFeed = false
        } else {
            let base = selectedCategory.map { cat in all.filter { categoryKey(for: $0) == cat } } ?? all
            cachedHasOlderFeed = base.count > base.filter { $0.timestamp >= twoWeeksAgo }.count
        }
    }

    // MARK: - カテゴリー絞り込みバー

    @ViewBuilder
    private var categoryFilterBar: some View {
        if !cachedFeedCategories.isEmpty {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 12 * UIScale.font, weight: .black))
                        .foregroundColor(Color.duoBlue)
                    Text("カテゴリーで絞り込み")
                        .font(.system(size: 13 * UIScale.font, weight: .black))
                        .foregroundColor(Color.duoDark)
                    Spacer()
                    if selectedCategory != nil {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { selectedCategory = nil }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 10 * UIScale.font, weight: .bold))
                                Text("リセット")
                                    .font(.system(size: 11 * UIScale.font, weight: .bold))
                            }
                            .foregroundColor(Color.duoSubtitle)
                        }
                        .buttonStyle(.plain)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        categoryChip(label: "すべて", emoji: "🗂", isSelected: selectedCategory == nil) {
                            withAnimation(.easeInOut(duration: 0.2)) { selectedCategory = nil }
                        }
                        ForEach(cachedFeedCategories) { cat in
                            categoryChip(label: cat.key, emoji: cat.emoji,
                                         isSelected: selectedCategory == cat.key) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedCategory = (selectedCategory == cat.key) ? nil : cat.key
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
    }

    private func categoryChip(label: String, emoji: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(emoji).font(.system(size: 14 * UIScale.font))
                Text(label)
                    .font(.system(size: 12 * UIScale.font, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .white : Color.duoDark)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.duoBlue : Color(.systemGray6))
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }

    private var eduFeedSection: some View {
        LazyVStack(spacing: 0) {
            // ── 空状態 ───────────────────────────────────────────────────
            if cachedFeedGroups.isEmpty {
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
            ForEach(cachedFeedGroups) { group in
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
            if !showOlderFeed && cachedHasOlderFeed {
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
                    if item.comment.isEmpty {
                        Text(item.authorFirstName)
                            .font(.system(size: 13 * UIScale.font, weight: .black))
                            .foregroundColor(Color.duoDark)
                    } else {
                        (Text(item.authorFirstName + "  ")
                            .font(.system(size: 13 * UIScale.font, weight: .black))
                         + Text(item.comment)
                            .font(.system(size: 13 * UIScale.font)))
                            .foregroundColor(Color.duoDark)
                            .lineLimit(1)
                    }
                    Text(relativeTimeString(item.timestamp))
                        .font(.system(size: 11 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)
                }

                Spacer()

                // アクティビティタグ（タップで同カテゴリーに絞り込み）
                Button {
                    let cat = categoryKey(for: item)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedCategory = (selectedCategory == cat) ? nil : cat
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(categoryEmoji(for: item))
                            .font(.system(size: 12 * UIScale.font))
                        Text(categoryKey(for: item))
                            .font(.system(size: 10 * UIScale.font, weight: .semibold))
                            .foregroundColor(selectedCategory == categoryKey(for: item) ? .white : Color.duoSubtitle)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(selectedCategory == categoryKey(for: item) ? Color.duoBlue : Color(.systemGray6))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

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

            // ── Instagram風 正方形写真 or グラデーション＋絵文字 ──────────────
            Button { openDetail(item) } label: {
                Group {
                    if let thumb = item.thumbnail {
                        // メイン被写体を中心に据えた正方形クロップ（中央寄せ・フィル）
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                Image(uiImage: thumb)
                                    .resizable()
                                    .scaledToFill()
                            )
                            .clipped()
                            .contentShape(Rectangle())
                    } else {
                        ZStack {
                            instaGradient(for: item)
                            Text(item.activityEmoji.isEmpty ? "📝" : item.activityEmoji)
                                .font(.system(size: 96 * UIScale.font))
                                .shadow(color: .black.opacity(0.25), radius: 12)
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                    }
                }
                // FOOD投稿はカロリーバッジを表示
                .overlay(alignment: .bottomLeading) {
                    if let kcal = foodCalories(for: item) {
                        HStack(spacing: 3) {
                            Text("🔥").font(.system(size: 11 * UIScale.font))
                            Text("\(kcal) kcal")
                                .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                        .padding(10)
                    }
                }
            }
            .buttonStyle(.plain)

            // ── Duolingo フレーズパネル ───────────────────────────────────
            if let phrase = item.extractedPhrase, !phrase.isEmpty {
                duolingoPhrasePanel(item: item, phrase: phrase)
            }

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

            Spacer().frame(height: 4)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Duolingo フレーズパネル

    @ViewBuilder
    private func duolingoPhrasePanel(item: EduLogHistoryItem, phrase: String) -> some View {
        let isSpeaking = speakingItemID == item.id
        let langCode   = item.extractedLanguageCode ?? "en"
        let langLabel  = languageLabel(langCode)

        VStack(alignment: .leading, spacing: 6) {
            // 言語バッジ
            HStack(spacing: 6) {
                Text(languageFlag(langCode))
                    .font(.system(size: 16))
                Text(langLabel)
                    .font(.system(size: 11 * UIScale.font, weight: .semibold))
                    .foregroundColor(Color.duoSubtitle)
                Spacer()
                // 再生ボタン
                Button {
                    if isSpeaking {
                        DuolingoTextExtractor.shared.stopSpeaking()
                        speakingItemID = nil
                    } else {
                        speakingItemID = item.id
                        DuolingoTextExtractor.shared.speak(phrase: phrase, languageCode: langCode)
                        // 読み上げ終了を 10 秒後にリセット（完了コールバック非対応のため）
                        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                            if speakingItemID == item.id {
                                speakingItemID = nil
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 14))
                        Text(isSpeaking ? "停止" : "再生")
                            .font(.system(size: 12 * UIScale.font, weight: .semibold))
                    }
                    .foregroundColor(isSpeaking ? Color.red : Color(hex: "#1CB0F6"))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background((isSpeaking ? Color.red : Color(hex: "#1CB0F6")).opacity(0.12))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }

            // 外国語フレーズ（大）
            Text(phrase)
                .font(.system(size: 18 * UIScale.font, weight: .bold))
                .foregroundColor(Color.duoDark)
                .fixedSize(horizontal: false, vertical: true)

            // 発音記号
            if let pron = item.pronunciation, !pron.isEmpty {
                Text(pron)
                    .font(.system(size: 13 * UIScale.font))
                    .foregroundColor(Color(hex: "#1CB0F6"))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 日本語訳
            if let tja = item.translationJA, !tja.isEmpty {
                Text(tja)
                    .font(.system(size: 13 * UIScale.font))
                    .foregroundColor(Color.duoSubtitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.systemGray6).opacity(0.6))
    }

    private func languageFlag(_ code: String) -> String {
        switch code {
        case "zh", "zh-Hans", "cmn-Hans": return "🇨🇳"
        case "zh-Hant":                   return "🇹🇼"
        case "ko":                        return "🇰🇷"
        case "fr":                        return "🇫🇷"
        case "es":                        return "🇪🇸"
        case "de":                        return "🇩🇪"
        case "pt":                        return "🇧🇷"
        case "it":                        return "🇮🇹"
        case "ru":                        return "🇷🇺"
        case "ar":                        return "🇸🇦"
        default:                          return "🇺🇸"
        }
    }

    private func languageLabel(_ code: String) -> String {
        switch code {
        case "zh", "zh-Hans", "cmn-Hans": return "中国語"
        case "zh-Hant":                   return "中国語（繁体）"
        case "ko":                        return "韓国語"
        case "fr":                        return "フランス語"
        case "es":                        return "スペイン語"
        case "de":                        return "ドイツ語"
        case "pt":                        return "ポルトガル語"
        case "it":                        return "イタリア語"
        case "ru":                        return "ロシア語"
        case "ar":                        return "アラビア語"
        default:                          return "英語"
        }
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

                // 記録メニュー（プラスアイコン・左側）
                Menu {
                    ForEach(quickRecords) { rec in
                        Button {
                            handleQuickRecord(rec)
                        } label: {
                            Text("\(rec.emoji)  \(rec.label)")
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.25))
                            .frame(width: 32, height: 32)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        Image(systemName: "plus")
                            .font(.system(size: 14 * UIScale.font, weight: .black))
                            .foregroundColor(.white)
                    }
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
    private func addedFriendAvatar(_ tomo: TomoSearchResult) -> some View {
        let initial = String(tomo.username.prefix(1)).uppercased()
        ZStack {
            Circle().fill(Color.duoBlue.opacity(0.15)).frame(width: 44, height: 44)
            if let url = URL(string: tomo.photoURL), !tomo.photoURL.isEmpty {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Text(initial).font(.system(size: 18 * UIScale.font, weight: .black)).foregroundColor(Color.duoBlue)
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            } else {
                Text(initial).font(.system(size: 18 * UIScale.font, weight: .black)).foregroundColor(Color.duoBlue)
            }
        }
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
        case .added(let tomo):
            VStack(alignment: .leading, spacing: 10) {
                Label("TOMOに追加しました！", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoGreen)
                HStack(spacing: 12) {
                    addedFriendAvatar(tomo)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tomo.username)
                            .font(.system(size: 15 * UIScale.font, weight: .black))
                            .foregroundColor(Color.duoDark)
                            .lineLimit(1)
                        HStack(spacing: 12) {
                            Label("\(tomo.weeklyPoints) pt", systemImage: "bolt.fill")
                                .font(.system(size: 11 * UIScale.font, weight: .bold))
                                .foregroundColor(Color.duoBlue)
                            Label("\(tomo.streak) 日", systemImage: "flame.fill")
                                .font(.system(size: 11 * UIScale.font, weight: .bold))
                                .foregroundColor(Color.duoOrange)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Color.duoGreen.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.duoGreen.opacity(0.30), lineWidth: 1)
                )
                .cornerRadius(12)
                Text("ランキングとフィードに反映されました")
                    .font(.system(size: 11 * UIScale.font))
                    .foregroundColor(Color.duoSubtitle)
            }
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


    // MARK: - クイック記録バー（ランキング上部）

    private var quickRecordBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 12 * UIScale.font, weight: .black))
                    .foregroundColor(Color.duoBlue)
                Text("写真で記録")
                    .font(.system(size: 13 * UIScale.font, weight: .black))
                    .foregroundColor(Color.duoDark)
                Spacer()
            }

            HStack(spacing: 0) {
                ForEach(quickRecords) { rec in
                    Button {
                        handleQuickRecord(rec)
                    } label: {
                        VStack(spacing: 5) {
                            ZStack {
                                Circle()
                                    .fill(rec.color.opacity(0.14))
                                    .frame(width: 46, height: 46)
                                Text(rec.emoji)
                                    .font(.system(size: 24 * UIScale.font))
                            }
                            Text(rec.label)
                                .font(.system(size: 9.5 * UIScale.font, weight: .bold))
                                .foregroundColor(Color.duoDark)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
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
