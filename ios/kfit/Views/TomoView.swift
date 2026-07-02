import SwiftUI
import Combine
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
    let grammarNote: String?
    let mistakeNote: String?
    let exampleSentences: [ExampleSentence]?
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
    /// 「過去の投稿を見る」追加ロード中フラグ
    @Published var isLoadingOlderPosts = false
    /// 1週間より古い投稿が存在する可能性（友達がいれば true）
    @Published var hasOlderPosts = false

    private let db = Firestore.firestore()
    private static var didBackfillPublicPosts = false
    /// 初回ロード完了フラグ — .task からの重複ロードを防止
    private var isLoaded = false
    /// 古い投稿ロード済みフラグ — 重複ロードを防止
    private var isOlderLoaded = false
    /// 直近1週間の開始日を返す
    private static func oneWeekAgo() -> Date {
        Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    }

    /// 2人のuidから決定的な friendship ドキュメントIDを生成
    private func friendshipId(_ a: String, _ b: String) -> String {
        [a, b].sorted().joined(separator: "_")
    }

    func load(force: Bool = false) async {
        guard !isLoaded || force else { return }   // 初回以外はスキップ
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false; isLoaded = true }

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

        // 友達のプロフィールと投稿を並列フェッチ
        struct FriendResult: Sendable {
            let profile: FriendProfile?
            let posts: [FriendPostData]
            let fid: String
        }

        let friendResults: [FriendResult] = await withTaskGroup(of: FriendResult.self) { group in
            for fid in friendIds {
                group.addTask {
                    async let profileTask = { () -> FriendProfile? in
                        try? await withAsyncTimeout(seconds: 12) { () -> FriendProfile? in
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
                    }()

                    async let postsTask = { () -> [FriendPostData] in
                        (try? await withAsyncTimeout(seconds: 12) {
                            // 直近1週間の投稿のみ取得（古い投稿は「過去の投稿を見る」ボタンで遅延ロード）
                            let snap = try await Firestore.firestore()
                                .collection("publicProfiles").document(fid)
                                .collection("posts")
                                .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: TomoManager.oneWeekAgo()))
                                .order(by: "timestamp", descending: true)
                                .limit(to: 15)
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
                                    calories: data["calories"] as? Int,
                                    grammarNote: data["grammarNote"] as? String,
                                    mistakeNote: data["mistakeNote"] as? String,
                                    exampleSentences: {
                                        guard let raw = data["exampleSentences"] as? [[String: Any]],
                                              let d = try? JSONSerialization.data(withJSONObject: raw),
                                              let decoded = try? JSONDecoder().decode([ExampleSentence].self, from: d)
                                        else { return nil }
                                        return decoded
                                    }()
                                )
                            }
                        }) ?? []
                    }()

                    let (profile, posts) = await (profileTask, postsTask)
                    return FriendResult(profile: profile, posts: posts, fid: fid)
                }
            }
            var results: [FriendResult] = []
            for await result in group { results.append(result) }
            return results
        }

        // ランキングエントリーとフィードアイテムをまとめて構築
        var feedItems: [EduLogHistoryItem] = []
        for result in friendResults {
            if let p = result.profile {
                all.append(TomoEntry(
                    id: result.fid,
                    email: p.email,
                    username: p.username,
                    totalPoints: p.totalPoints,
                    streak: p.streak,
                    weeklyPoints: p.weeklyPoints
                ))
            }
            for p in result.posts { feedItems.append(makeFriendItem(from: p)) }
        }

        all.sort { $0.weeklyPoints > $1.weeklyPoints }
        for i in all.indices { all[i].rank = i + 1 }
        entries = all
        friendFeedItems = feedItems
        // 友達がいれば1週間より古い投稿が存在する可能性がある
        hasOlderPosts = !friendIds.isEmpty
    }

    /// 友達の古い投稿（1週間より前）を遅延ロードする。「過去の投稿を見る」ボタン押下時に呼ぶ。
    func loadOlderPosts() async {
        guard !isOlderLoaded else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoadingOlderPosts = true
        defer { isLoadingOlderPosts = false; isOlderLoaded = true }

        let friendIds: [String] = (try? await withAsyncTimeout(seconds: 12) {
            let snap = try await Firestore.firestore().collection("friendships")
                .whereField("members", arrayContains: uid)
                .getDocuments()
            var ids: [String] = []
            for doc in snap.documents {
                let members = doc.data()["members"] as? [String] ?? []
                if let other = members.first(where: { $0 != uid }) { ids.append(other) }
            }
            return ids
        }) ?? []

        guard !friendIds.isEmpty else { return }

        let cutoff = TomoManager.oneWeekAgo()
        let existingIds = Set(friendFeedItems.map { $0.id })

        struct OlderPostResult: Sendable {
            let posts: [FriendPostData]
        }

        let results: [OlderPostResult] = await withTaskGroup(of: OlderPostResult.self) { group in
            for fid in friendIds {
                group.addTask {
                    let posts: [FriendPostData] = (try? await withAsyncTimeout(seconds: 12) {
                        // 1週間以前のデータを30件まで取得
                        let snap = try await Firestore.firestore()
                            .collection("publicProfiles").document(fid)
                            .collection("posts")
                            .whereField("timestamp", isLessThan: Timestamp(date: cutoff))
                            .order(by: "timestamp", descending: true)
                            .limit(to: 30)
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
                                calories: data["calories"] as? Int,
                                grammarNote: data["grammarNote"] as? String,
                                mistakeNote: data["mistakeNote"] as? String,
                                exampleSentences: {
                                    guard let raw = data["exampleSentences"] as? [[String: Any]],
                                          let d = try? JSONSerialization.data(withJSONObject: raw),
                                          let decoded = try? JSONDecoder().decode([ExampleSentence].self, from: d)
                                    else { return nil }
                                    return decoded
                                }()
                            )
                        }
                    }) ?? []
                    return OlderPostResult(posts: posts)
                }
            }
            var results: [OlderPostResult] = []
            for await r in group { results.append(r) }
            return results
        }

        // 既存に含まれていない投稿だけ追加
        var newItems: [EduLogHistoryItem] = []
        for result in results {
            for p in result.posts where !existingIds.contains(p.id) {
                newItems.append(makeFriendItem(from: p))
            }
        }
        if !newItems.isEmpty {
            friendFeedItems.append(contentsOf: newItems)
        }
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
        item.grammarNote = p.grammarNote
        item.mistakeNote = p.mistakeNote
        item.exampleSentences = p.exampleSentences
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
    // PhotoLogManager は kfitApp から EnvironmentObject で配布済みのため
    // @StateObject による二重購読を解消（不要な View 再レンダリングを防ぐ）
    @EnvironmentObject private var photoLogManager: PhotoLogManager
    @State private var selectedEduItem: EduLogHistoryItem? = nil
    @State private var selectedFoodItem: PhotoLogHistoryItem? = nil   // FOOD投稿の詳細
    @State private var swipeDetailItems: [EduLogHistoryItem] = []     // スワイプ詳細グループ
    @State private var swipeDetailStart: Int = 0
    @State private var showSwipeDetail = false
    @State private var commentTargetItem: EduLogHistoryItem? = nil
    @State private var shareTargetItem: EduLogHistoryItem? = nil
    @State private var categoryGroupTarget: TomoView.FeedCategoryGroup? = nil
    @State private var showOlderFeed = false
    @State private var showInviteSheet = false
    @State private var deleteConfirmItem: EduLogHistoryItem? = nil
    @State private var speakingItemID: String? = nil       // TTS 再生中のアイテム ID
    @State private var speakingExampleKey: String? = nil   // 例文 TTS 再生中のキー（"itemID-index"）
    @State private var showFoodLog = false             // FOOD → フォトログ
    @State private var eduRecordTarget: TomoQuickRecord? = nil  // 写真記録シート対象
    @State private var selectedCategory: String? = nil  // カテゴリー絞り込み（nil=すべて）
    @FocusState private var emailFocused: Bool

    // フィード集計のキャッシュ（body 毎の merge+sort+grouping 再計算を回避）
    @State private var cachedFeedGroups: [FeedDayGroup] = []
    @State private var cachedFeedCategories: [FeedCategoryChip] = []
    @State private var cachedHasOlderFeed: Bool = false
    // rebuildFeedCache() の多重発火をデバウンス（50ms）
    @State private var feedRebuildWork: DispatchWorkItem? = nil

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
                .refreshable { await manager.load(force: true) }
            }
            .navigationBarHidden(true)
            .safeAreaInset(edge: .top, spacing: 0) { tomoHeader }
        }
        .task { await manager.load() }   // isLoaded で重複ロードを自動防止
        .onAppear { rebuildFeedCache() }
        .onReceive(eduLogManager.$history) { _ in scheduleFeedRebuild() }
        .onReceive(photoLogManager.$history) { _ in scheduleFeedRebuild() }
        .onReceive(manager.$friendFeedItems) { _ in scheduleFeedRebuild() }
        .onReceive(manager.$isLoadingOlderPosts) { loading in
            // 古い投稿のロード完了時にフィードを再ビルド
            if !loading { scheduleFeedRebuild() }
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
        .sheet(isPresented: $showSwipeDetail) {
            SwipeableTomoDetailSheet(
                items: swipeDetailItems,
                startIndex: swipeDetailStart,
                photoLogManager: photoLogManager,
                onComment: { commentTargetItem = $0 },
                onLike: { toggleLikeFeed($0) },
                onShare: { shareTargetItem = $0 }
            )
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

    private var oneWeekAgo: Date {
        Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
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
        item.thumbnailPath = food.thumbnailPath   // 新形式（ファイルパス）
        item.thumbnailData = food.thumbnailData   // 旧データ互換
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

    /// 投稿タップ時のルーティング：全種別を SwipeableTomoDetailSheet で統一表示
    private func openDetail(_ item: EduLogHistoryItem) {
        swipeDetailItems = [item]
        swipeDetailStart = 0
        showSwipeDetail = true
    }

    /// 同一グループ（同日×同カテゴリ）の複数アイテムをスワイプ詳細で開く
    private func openDetailInGroup(_ item: EduLogHistoryItem, siblings: [EduLogHistoryItem]) {
        guard siblings.count > 1 else {
            openDetail(item)
            return
        }
        let idx = siblings.firstIndex(where: { $0.id == item.id }) ?? 0
        swipeDetailItems = siblings
        swipeDetailStart = idx
        showSwipeDetail = true
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

    /// 同一ユーザー × 同一カテゴリーの投稿をまとめた単位（カルーセル表示の1カード分）
    struct FeedPostGroup: Identifiable {
        let id: String           // authorName_categoryKey
        let authorName: String
        let authorFirstName: String
        let authorPhotoURL: String
        let categoryKey: String
        let categoryEmoji: String
        let items: [EduLogHistoryItem]  // 時刻降順
        var isSingle: Bool { items.count == 1 }
        var latestItem: EduLogHistoryItem { items[0] }
    }

    // 日付グループ（キャッシュ用）
    struct FeedDayGroup: Identifiable {
        var id: String { label }
        let label: String
        let postGroups: [FeedPostGroup]  // 1日内を「ユーザー×カテゴリー」でまとめたグループ列
    }

    /// 連続する履歴更新をまとめて1回だけ rebuildFeedCache() を実行する（50msデバウンス）
    private func scheduleFeedRebuild() {
        feedRebuildWork?.cancel()
        let work = DispatchWorkItem { rebuildFeedCache() }
        feedRebuildWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
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

        // 表示対象（直近1週間 or 全件 ＋ カテゴリー絞り込み）
        var items = showOlderFeed ? all : all.filter { $0.timestamp >= oneWeekAgo }
        if let cat = selectedCategory {
            items = items.filter { categoryKey(for: $0) == cat }
        }

        // 日付グループ化 → ユーザー×カテゴリーグループ化
        let cal = Calendar.current
        let byDay = Dictionary(grouping: items) { cal.startOfDay(for: $0.timestamp) }
        cachedFeedGroups = byDay.keys.sorted(by: >).map { date in
            let label = cal.isDateInToday(date) ? "今日" :
                        cal.isDateInYesterday(date) ? "昨日" :
                        TomoView.dateGroupFormatter.string(from: date)
            let dayItems = (byDay[date] ?? []).sorted { $0.timestamp > $1.timestamp }

            // 同一ユーザー×同一カテゴリーをまとめ、最新投稿の時刻順に並べる
            let groupKey: (EduLogHistoryItem) -> String = { item in
                "\(item.authorName)__\(self.categoryKey(for: item))"
            }
            var keyOrder: [String] = []
            var grouped: [String: [EduLogHistoryItem]] = [:]
            for item in dayItems {
                let k = groupKey(item)
                if grouped[k] == nil { keyOrder.append(k) }
                grouped[k, default: []].append(item)
            }
            let postGroups: [FeedPostGroup] = keyOrder.compactMap { k in
                guard let grpItems = grouped[k], let first = grpItems.first else { return nil }
                let info = self.categoryInfo(for: first)
                return FeedPostGroup(
                    id: k,
                    authorName: first.authorName,
                    authorFirstName: first.authorFirstName,
                    authorPhotoURL: first.authorPhotoURL,
                    categoryKey: info.label,
                    categoryEmoji: info.emoji,
                    items: grpItems
                )
            }
            return FeedDayGroup(label: label, postGroups: postGroups)
        }

        // 過去フィードの有無（ローカルに古い投稿がある、またはFirestoreに未ロードの古い投稿がある）
        if showOlderFeed {
            cachedHasOlderFeed = false
        } else {
            let base = selectedCategory.map { cat in all.filter { categoryKey(for: $0) == cat } } ?? all
            let hasLocalOlder = base.count > base.filter { $0.timestamp >= oneWeekAgo }.count
            cachedHasOlderFeed = hasLocalOlder || manager.hasOlderPosts
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

                // 投稿カード（ユーザー×カテゴリー単位でカルーセルまとめ）
                ForEach(group.postGroups) { pg in
                    if pg.isSingle {
                        instaPostCard(pg.latestItem)
                    } else {
                        instaCarouselCard(pg)
                    }
                    Divider()
                }
            }

            // ── 過去フィード展開ボタン ────────────────────────────────────
            if !showOlderFeed && cachedHasOlderFeed {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showOlderFeed = true
                    }
                    // 友達の古い投稿が未ロードの場合は Firestore から取得
                    Task { await manager.loadOlderPosts() }
                } label: {
                    HStack(spacing: 8) {
                        if manager.isLoadingOlderPosts {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(Color.duoBlue)
                        } else {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 14 * UIScale.font, weight: .semibold))
                        }
                        Text(manager.isLoadingOlderPosts ? "読み込み中…" : "過去の投稿を見る")
                            .font(.system(size: 13 * UIScale.font, weight: .bold))
                        Spacer()
                        if !manager.isLoadingOlderPosts {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11 * UIScale.font, weight: .semibold))
                        }
                    }
                    .foregroundColor(Color.duoBlue)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 20)
                    .background(Color(.systemBackground))
                }
                .buttonStyle(.plain)
                .disabled(manager.isLoadingOlderPosts)
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
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color(hex: "#833ab4"), Color(hex: "#fd1d1d"), Color(hex: "#fcb045")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 32, height: 32)
                    Circle()
                        .fill(Color(.systemBackground))
                        .frame(width: 28, height: 28)
                    UserAvatarView(
                        name: item.authorFirstName,
                        photoURL: item.authorPhotoURL.isEmpty
                            ? (UserDefaults.standard.string(forKey: "cachedCurrentUserPhotoURL") ?? "")
                            : item.authorPhotoURL,
                        size: 25
                    )
                }

                VStack(alignment: .leading, spacing: 1) {
                    let displayName = isOwnPost(item) ? "YOU" : item.authorFirstName
                    let isYou = isOwnPost(item)
                    // 説明は写真上に表示するため、ヘッダーには名前のみ
                    Text(displayName)
                        .font(.system(size: 11 * UIScale.font, weight: .black))
                        .foregroundColor(isYou ? Color.duoGreen : Color.duoDark)
                    Text(relativeTimeString(item.timestamp))
                        .font(.system(size: 9 * UIScale.font))
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
                            .font(.system(size: 11 * UIScale.font))
                        Text(categoryKey(for: item))
                            .font(.system(size: 9 * UIScale.font, weight: .semibold))
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
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

            // ── Instagram風 正方形写真 or グラデーション＋絵文字 ──────────────
            Button { openDetail(item) } label: {
                let isFood = item.id.hasPrefix("food_")
                let foodItem = isFood ? originalFoodItem(for: item) : nil
                let mealInfo = mealTimeInfo(for: item.timestamp)
                Group {
                    if let thumb = foodItem?.thumbnail ?? item.thumbnail {
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
                // 左上: FOOD投稿に食事タイムバッジ / Duolingo投稿に言語バッジ
                .overlay(alignment: .topLeading) {
                    if isFood {
                        Text(mealInfo.label)
                            .font(.system(size: 11 * UIScale.font, weight: .black))
                            .foregroundColor(.white)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(mealInfo.color)
                            .clipShape(Capsule())
                            .padding(8)
                    } else if (item.activityEmoji == "🦉"
                               || item.activityName.localizedCaseInsensitiveContains("Duolingo")),
                              let langCode = item.extractedLanguageCode, !langCode.isEmpty {
                        HStack(spacing: 3) {
                            Text(languageFlag(langCode))
                                .font(.system(size: 12 * UIScale.font))
                            Text(languageLabel(langCode))
                                .font(.system(size: 9 * UIScale.font, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.black.opacity(0.58))
                        .clipShape(Capsule())
                        .padding(8)
                    }
                }
                // 右上: Weight 投稿のみ Day◯ バッジ
                .overlay(alignment: .topTrailing) {
                    if item.weightKg != nil {
                        Text(dayLabel(for: item.timestamp))
                            .font(.system(size: 10 * UIScale.font, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.black.opacity(0.52))
                            .clipShape(Capsule())
                            .padding(8)
                    }
                }
                // 下部: FOOD → 栄養情報、非FOOD → コメント（あれば）
                .overlay(alignment: .bottom) {
                    if let food = foodItem {
                        // FOOD: 食品名 + 栄養情報
                        VStack(alignment: .leading, spacing: 2) {
                            Text(food.displayName)
                                .font(.system(size: 11 * UIScale.font, weight: .black))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .shadow(color: .black.opacity(0.6), radius: 2)
                            HStack(spacing: 6) {
                                Text("🔥 \(food.calories)kcal")
                                    .font(.system(size: 10 * UIScale.font, weight: .bold))
                                    .foregroundColor(.white)
                                Text("P \(Int(food.analyzedNutrition.protein))g")
                                    .font(.system(size: 10 * UIScale.font, weight: .bold))
                                    .foregroundColor(Color(hex: "#FF9F43"))
                                Text("F \(Int(food.analyzedNutrition.fat))g")
                                    .font(.system(size: 10 * UIScale.font, weight: .bold))
                                    .foregroundColor(Color(hex: "#A29BFE"))
                                Text("C \(Int(food.analyzedNutrition.carbs))g")
                                    .font(.system(size: 10 * UIScale.font, weight: .bold))
                                    .foregroundColor(Color(hex: "#74B9FF"))
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            LinearGradient(
                                colors: [.clear, Color.black.opacity(0.7)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    } else if !item.comment.isEmpty {
                        // 非FOOD: コメント・説明テキスト
                        Text(item.comment)
                            .font(.system(size: 12 * UIScale.font, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .shadow(color: .black.opacity(0.6), radius: 2)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                LinearGradient(
                                    colors: [.clear, Color.black.opacity(0.65)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                    }
                }
            }
            .buttonStyle(.plain)

            // ── Duolingo フレーズパネル ───────────────────────────────────
            if let phrase = item.extractedPhrase, !phrase.isEmpty {
                duolingoPhrasePanel(item: item, phrase: phrase)
            }

            Spacer().frame(height: 8)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - カルーセルカード（同一ユーザー×同一カテゴリー複数投稿）

    private func instaCarouselCard(_ pg: FeedPostGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── ヘッダー（ユーザー + カテゴリー + 件数） ───────────────────
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
                        name: pg.authorFirstName,
                        photoURL: pg.authorPhotoURL.isEmpty
                            ? (UserDefaults.standard.string(forKey: "cachedCurrentUserPhotoURL") ?? "")
                            : pg.authorPhotoURL,
                        size: 33
                    )
                }

                VStack(alignment: .leading, spacing: 1) {
                    let isYou = isOwnPost(pg.latestItem)
                    Text(isYou ? "YOU" : pg.authorFirstName)
                        .font(.system(size: 13 * UIScale.font, weight: .black))
                        .foregroundColor(isYou ? Color.duoGreen : Color.duoDark)
                    Text(relativeTimeString(pg.latestItem.timestamp))
                        .font(.system(size: 11 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)
                }

                Spacer()

                // カテゴリータグ（件数バッジ付き）
                Button {
                    let cat = pg.categoryKey
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedCategory = (selectedCategory == cat) ? nil : cat
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(pg.categoryEmoji)
                            .font(.system(size: 12 * UIScale.font))
                        Text(pg.categoryKey)
                            .font(.system(size: 10 * UIScale.font, weight: .semibold))
                            .foregroundColor(selectedCategory == pg.categoryKey ? .white : Color.duoSubtitle)
                        Text("×\(pg.items.count)")
                            .font(.system(size: 10 * UIScale.font, weight: .black))
                            .foregroundColor(selectedCategory == pg.categoryKey ? .white.opacity(0.85) : Color.duoBlue)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(selectedCategory == pg.categoryKey ? Color.duoBlue : Color(.systemGray6))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

                // 三点メニュー
                Menu {
                    if pg.items.contains(where: { isOwnPost($0) }) {
                        Button(role: .destructive) {
                            deleteConfirmItem = pg.latestItem
                        } label: { Label("最新の投稿を削除", systemImage: "trash") }
                    }
                    Button {
                        shareTargetItem = pg.latestItem
                    } label: { Label("シェア", systemImage: "square.and.arrow.up") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color.duoSubtitle)
                        .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // ── 横スクロールカルーセル ────────────────────────────────────
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(Array(pg.items.enumerated()), id: \.element.id) { idx, item in
                        carouselSlide(item: item, index: idx, total: pg.items.count, siblings: pg.items)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Spacer().frame(height: 8)
        }
        .background(Color(.systemBackground))
    }

    /// カルーセル内の1スライド（タップで詳細表示）
    private func carouselSlide(item: EduLogHistoryItem, index: Int, total: Int, siblings: [EduLogHistoryItem] = []) -> some View {
        let screenWidth = UIScreen.main.bounds.width
        let slideWidth: CGFloat = total == 1 ? screenWidth : screenWidth * 0.72
        let isFood = item.id.hasPrefix("food_")
        let foodItem = isFood ? originalFoodItem(for: item) : nil
        let mealInfo = mealTimeInfo(for: item.timestamp)

        return Button { openDetailInGroup(item, siblings: siblings.isEmpty ? [item] : siblings) } label: {
            ZStack {
                Group {
                    if let thumb = foodItem?.thumbnail ?? item.thumbnail {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            instaGradient(for: item)
                            Text(item.activityEmoji.isEmpty ? "📝" : item.activityEmoji)
                                .font(.system(size: 72 * UIScale.font))
                                .shadow(color: .black.opacity(0.25), radius: 8)
                        }
                    }
                }
                .frame(width: slideWidth, height: slideWidth)
                .clipped()
                .contentShape(Rectangle())

                // 上部オーバーレイ（左: meal/言語バッジ, 右: Weight Day◯ + 番号バッジ）
                VStack {
                    HStack(alignment: .top) {
                        // 左: FOOD → meal バッジ / Duolingo → 言語バッジ
                        if isFood {
                            Text(mealInfo.label)
                                .font(.system(size: 10 * UIScale.font, weight: .black))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(mealInfo.color)
                                .clipShape(Capsule())
                        } else if (item.activityEmoji == "🦉"
                                   || item.activityName.localizedCaseInsensitiveContains("Duolingo")),
                                  let langCode = item.extractedLanguageCode, !langCode.isEmpty {
                            HStack(spacing: 3) {
                                Text(languageFlag(langCode))
                                    .font(.system(size: 11 * UIScale.font))
                                Text(languageLabel(langCode))
                                    .font(.system(size: 9 * UIScale.font, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.black.opacity(0.58))
                            .clipShape(Capsule())
                        }
                        Spacer()
                        // 右: Weight 投稿のみ Day◯ バッジ + 番号バッジ（複数枚時）
                        VStack(alignment: .trailing, spacing: 4) {
                            if item.weightKg != nil {
                                Text(dayLabel(for: item.timestamp))
                                    .font(.system(size: 10 * UIScale.font, weight: .black, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.black.opacity(0.52))
                                    .clipShape(Capsule())
                            }
                            if total > 1 {
                                Text("\(index + 1)/\(total)")
                                    .font(.system(size: 10 * UIScale.font, weight: .black))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Color.black.opacity(0.55))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(8)
                    Spacer()
                }

                // 下部: FOOD の名称 + 栄養情報オーバーレイ
                if let food = foodItem {
                    VStack {
                        Spacer()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(food.displayName)
                                .font(.system(size: 11 * UIScale.font, weight: .black))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .shadow(color: .black.opacity(0.6), radius: 2)
                            HStack(spacing: 5) {
                                Text("🔥 \(food.calories)kcal")
                                    .font(.system(size: 10 * UIScale.font, weight: .bold))
                                    .foregroundColor(.white)
                                Text("P \(Int(food.analyzedNutrition.protein))g")
                                    .font(.system(size: 10 * UIScale.font, weight: .bold))
                                    .foregroundColor(Color(hex: "#FF9F43"))
                                Text("F \(Int(food.analyzedNutrition.fat))g")
                                    .font(.system(size: 10 * UIScale.font, weight: .bold))
                                    .foregroundColor(Color(hex: "#A29BFE"))
                                Text("C \(Int(food.analyzedNutrition.carbs))g")
                                    .font(.system(size: 10 * UIScale.font, weight: .bold))
                                    .foregroundColor(Color(hex: "#74B9FF"))
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            LinearGradient(
                                colors: [.clear, Color.black.opacity(0.7)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    }
                }
            }
            .frame(width: slideWidth, height: slideWidth)
        }
        .buttonStyle(.plain)
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

            // ── 間違えた理由解説 ──────────────────────────────────────────
            if let note = item.mistakeNote, !note.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("ダメな理由", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color(hex: "#FF3B30"))
                    Text(note)
                        .font(.system(size: 13 * UIScale.font))
                        .foregroundColor(Color.duoDark)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color(hex: "#FF3B30").opacity(0.07))
                .cornerRadius(8)
                .padding(.top, 4)
            }

            // ── 文法解説 ──────────────────────────────────────────────────
            if let note = item.grammarNote, !note.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("文法メモ", systemImage: "text.book.closed")
                        .font(.system(size: 11 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color(hex: "#FF9500"))
                    Text(note)
                        .font(.system(size: 13 * UIScale.font))
                        .foregroundColor(Color.duoDark)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color(hex: "#FF9500").opacity(0.08))
                .cornerRadius(8)
                .padding(.top, 4)
            }

            // ── 例文 2 件 ─────────────────────────────────────────────────
            if let examples = item.exampleSentences, !examples.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("例文", systemImage: "quote.bubble")
                        .font(.system(size: 11 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color(hex: "#58CC02"))
                    ForEach(Array(examples.enumerated()), id: \.offset) { idx, ex in
                        let exKey       = "\(item.id)-ex\(idx)"
                        let isExSpeaking = speakingExampleKey == exKey
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .top, spacing: 6) {
                                Text("\(idx + 1).")
                                    .font(.system(size: 13 * UIScale.font, weight: .bold))
                                    .foregroundColor(Color(hex: "#58CC02"))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(ex.text)
                                        .font(.system(size: 14 * UIScale.font, weight: .semibold))
                                        .foregroundColor(Color.duoDark)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if let tr = ex.translationJA, !tr.isEmpty {
                                        Text(tr)
                                            .font(.system(size: 12 * UIScale.font))
                                            .foregroundColor(Color.duoSubtitle)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                Spacer()
                                // 例文 TTS ボタン
                                Button {
                                    if isExSpeaking {
                                        DuolingoTextExtractor.shared.stopSpeaking()
                                        speakingExampleKey = nil
                                    } else {
                                        speakingExampleKey = exKey
                                        speakingItemID = nil
                                        DuolingoTextExtractor.shared.speak(
                                            phrase: ex.text, languageCode: langCode)
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                                            if speakingExampleKey == exKey {
                                                speakingExampleKey = nil
                                            }
                                        }
                                    }
                                } label: {
                                    Image(systemName: isExSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(isExSpeaking ? .red : Color(hex: "#58CC02"))
                                        .frame(width: 28, height: 28)
                                        .background((isExSpeaking ? Color.red : Color(hex: "#58CC02")).opacity(0.12))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(10)
                .background(Color(hex: "#58CC02").opacity(0.07))
                .cornerRadius(8)
                .padding(.top, 4)
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

    private func mealTimeInfo(for date: Date) -> (label: String, color: Color) {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<11:  return ("Breakfast", Color(hex: "#FF9500"))
        case 11..<14: return ("Lunch",     Color(hex: "#34C759"))
        case 14..<18: return ("Snack",     Color(hex: "#AF52DE"))
        case 18..<24: return ("Dinner",    Color(hex: "#0A84FF"))
        default:      return ("Late Night",Color(hex: "#5E5CE6"))
        }
    }

    /// スタート日（joinDate）から投稿日までの日数を "Day N" 文字列で返す
    private func dayLabel(for date: Date) -> String {
        let joinDate = AuthenticationManager.shared.userProfile?.joinDate ?? date
        let cal = Calendar.current
        let start = cal.startOfDay(for: joinDate)
        let post  = cal.startOfDay(for: date)
        let days  = cal.dateComponents([.day], from: start, to: post).day ?? 0
        return "Day \(days + 1)"
    }
}

// MARK: - スワイプ詳細シート（同一グループ複数投稿を左右スワイプで閲覧）

struct SwipeableTomoDetailSheet: View {
    let items: [EduLogHistoryItem]
    let startIndex: Int
    let photoLogManager: PhotoLogManager
    var onComment: ((EduLogHistoryItem) -> Void)? = nil
    var onLike: ((EduLogHistoryItem) -> Void)? = nil
    var onShare: ((EduLogHistoryItem) -> Void)? = nil

    @State private var selection: Int
    @State private var speakingItemID: String? = nil
    @State private var speakingExampleKey: String? = nil
    @Environment(\.dismiss) private var dismiss

    private static let hhmm: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.dateFormat = "M月d日 HH:mm"; return f
    }()
    private static let fullFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月d日 (E) HH:mm"; return f
    }()

    init(items: [EduLogHistoryItem], startIndex: Int, photoLogManager: PhotoLogManager,
         onComment: ((EduLogHistoryItem) -> Void)? = nil,
         onLike: ((EduLogHistoryItem) -> Void)? = nil,
         onShare: ((EduLogHistoryItem) -> Void)? = nil) {
        self.items = items
        self.startIndex = startIndex
        self.photoLogManager = photoLogManager
        self.onComment = onComment
        self.onLike = onLike
        self.onShare = onShare
        _selection = State(initialValue: startIndex)
    }

    var body: some View {
        NavigationView {
            TabView(selection: $selection) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    slidePage(item: item)
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .always : .never))
            .background(Color.duoBg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(items.count > 1 ? "\(selection + 1) / \(items.count)" : "")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .foregroundColor(Color.duoGreen)
                        .fontWeight(.bold)
                }
            }
            .onAppear {
                // TabView(.page) が初期 selection を反映しないことがある SwiftUI バグの workaround
                let target = startIndex
                DispatchQueue.main.async { selection = target }
            }
        }
    }

    @ViewBuilder
    private func slidePage(item: EduLogHistoryItem) -> some View {
        let isFood = item.id.hasPrefix("food_")
        let food: PhotoLogHistoryItem? = isFood
            ? photoLogManager.history.first(where: { $0.id == String(item.id.dropFirst("food_".count)) })
            : nil
        let hour = Calendar.current.component(.hour, from: item.timestamp)
        let mealColor: Color = {
            switch hour {
            case 5..<11:  return Color(hex: "#FF9500")
            case 11..<14: return Color(hex: "#34C759")
            case 14..<18: return Color(hex: "#AF52DE")
            case 18..<24: return Color(hex: "#0A84FF")
            default:      return Color(hex: "#5E5CE6")
            }
        }()
        let mealLabel: String = {
            switch hour {
            case 5..<11:  return "Breakfast"
            case 11..<14: return "Lunch"
            case 14..<18: return "Snack"
            case 18..<24: return "Dinner"
            default:      return "Late Night"
            }
        }()

        let isFit = item.weightKg != nil
        let joinDate = AuthenticationManager.shared.userProfile?.joinDate ?? item.timestamp
        let fitDays  = Calendar.current.dateComponents([.day],
                           from: Calendar.current.startOfDay(for: joinDate),
                           to:   Calendar.current.startOfDay(for: item.timestamp)).day ?? 0

        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // ── 写真セクション（FIT / FOOD / その他で表示を統一） ───────
                let thumb = food?.thumbnail ?? item.thumbnail

                Group {
                    if isFit {
                        // ── FIT: WeightFeedDetailSheet と同じ表示 ──────────
                        if let thumb = thumb {
                            Image(uiImage: thumb)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .overlay(alignment: .bottom) {
                                    HStack {
                                        Text(SwipeableTomoDetailSheet.fullFmt.string(from: item.timestamp))
                                            .font(.system(size: 12 * UIScale.font, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(Color.black.opacity(0.50))
                                            .clipShape(Capsule())
                                        Spacer()
                                        Text("Day \(fitDays + 1)")
                                            .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(Color.black.opacity(0.50))
                                            .clipShape(Capsule())
                                    }
                                    .padding(10)
                                }
                        } else {
                            ZStack {
                                LinearGradient(colors: [Color(hex: "#1CB0F6"), Color(hex: "#0080C0")],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                                Text("⚖️").font(.system(size: 80 * UIScale.font))
                            }
                            .frame(maxWidth: .infinity).frame(height: 280)
                        }
                    } else if isFood {
                        // ── FOOD: PhotoFeedDetailSheet と同じ表示 ──────────
                        ZStack(alignment: .bottom) {
                            Group {
                                if let thumb = thumb {
                                    Image(uiImage: thumb)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    LinearGradient(
                                        colors: [Color(hex: "#FF6B6B"), Color(hex: "#FF8E53")],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    )
                                    .overlay(Text("🍽️").font(.system(size: 72 * UIScale.font)))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: UIScreen.main.bounds.width * 0.85)
                            .clipped()

                            // 下部: 料理名 ＋ 時間
                            VStack(alignment: .leading, spacing: 4) {
                                if let food = food {
                                    Text(food.displayName)
                                        .font(.system(size: 15 * UIScale.font, weight: .black))
                                        .foregroundColor(.white)
                                        .lineLimit(2)
                                }
                                Text(SwipeableTomoDetailSheet.hhmm.string(from: item.timestamp))
                                    .font(.system(size: 11 * UIScale.font, weight: .bold))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                LinearGradient(colors: [.clear, Color.black.opacity(0.60)],
                                               startPoint: .top, endPoint: .bottom)
                            )
                        }
                        // 左上: 食事タイムバッジ
                        .overlay(alignment: .topLeading) {
                            Text(mealLabel)
                                .font(.system(size: 12 * UIScale.font, weight: .black))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(mealColor)
                                .clipShape(Capsule())
                                .shadow(color: .black.opacity(0.2), radius: 4)
                                .padding(12)
                        }
                    } else {
                        // ── その他（Duolingo等）: 既存グラデーション表示 ────
                        ZStack(alignment: .bottom) {
                            Group {
                                if let thumb = thumb {
                                    Image(uiImage: thumb)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: .infinity)
                                } else {
                                    ZStack {
                                        LinearGradient(
                                            colors: [Color(hex: "#833ab4"), Color(hex: "#fd1d1d"), Color(hex: "#fcb045")],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        )
                                        Text(item.activityEmoji.isEmpty ? "📝" : item.activityEmoji)
                                            .font(.system(size: 80 * UIScale.font))
                                    }
                                    .frame(maxWidth: .infinity).frame(height: 300)
                                }
                            }
                            .clipped()

                            VStack(alignment: .leading, spacing: 4) {
                                if !item.activityName.isEmpty {
                                    Text(item.activityEmoji + " " + item.activityName)
                                        .font(.system(size: 15 * UIScale.font, weight: .black))
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.6), radius: 2)
                                }
                                Text(SwipeableTomoDetailSheet.hhmm.string(from: item.timestamp))
                                    .font(.system(size: 11 * UIScale.font, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                LinearGradient(colors: [.clear, Color.black.opacity(0.72)],
                                               startPoint: .top, endPoint: .bottom)
                            )
                        }
                        // 左上: Duolingo言語バッジ（言語が検知されていれば）
                        .overlay(alignment: .topLeading) {
                            if (item.activityEmoji == "🦉"
                                || item.activityName.localizedCaseInsensitiveContains("Duolingo")),
                               let langCode = item.extractedLanguageCode, !langCode.isEmpty {
                                HStack(spacing: 4) {
                                    Text(duoLangFlag(langCode))
                                        .font(.system(size: 15 * UIScale.font))
                                    Text(duoLangLabel(langCode))
                                        .font(.system(size: 11 * UIScale.font, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.black.opacity(0.55))
                                .clipShape(Capsule())
                                .shadow(color: .black.opacity(0.3), radius: 4)
                                .padding(12)
                            }
                        }
                    }
                }

                // ── FIT: 体重・体脂肪メトリクス（WeightFeedDetailSheet と同じ）
                if isFit {
                    HStack(spacing: 12) {
                        tomoMetric(emoji: "⚖️", label: "体重",
                                   value: item.weightKg != nil ? String(format: "%.1f", item.weightKg!) : "—",
                                   unit: "kg", color: Color(hex: "#1CB0F6"))
                        tomoMetric(emoji: "📉", label: "体脂肪率",
                                   value: item.bodyFatPercent != nil ? String(format: "%.1f", item.bodyFatPercent!) : "—",
                                   unit: "%", color: Color(hex: "#CE82FF"))
                    }
                    .padding(.horizontal, 16).padding(.top, 12)
                }

                // ── コメント ────────────────────────────────────────────────
                let caption = food?.comment ?? (item.comment.isEmpty ? nil : item.comment)
                if let caption, !caption.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "quote.opening")
                            .font(.system(size: 12 * UIScale.font, weight: .bold))
                            .foregroundColor(Color.duoGreen.opacity(0.7))
                            .padding(.top, 2)
                        Text(caption)
                            .font(.system(size: 14 * UIScale.font))
                            .foregroundColor(Color.duoDark.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .padding(.horizontal, 16).padding(.top, 12)
                }

                // ── FOOD 栄養詳細（FOOD投稿のみ）──────────────────────────
                if isFood, let food = food {
                    foodNutritionSection(food: food)
                        .padding(.top, 4)
                } else if isFood {
                    // 友達のFOOD投稿（calories のみ）
                    if let cal = item.calories, cal > 0 {
                        HStack(spacing: 6) {
                            Text("🔥")
                            Text("\(cal) kcal")
                                .font(.system(size: 22 * UIScale.font, weight: .black, design: .rounded))
                                .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.0))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    }
                }

                // ── Duolingo フレーズパネル（Duolingo投稿のみ）─────────────
                if let phrase = item.extractedPhrase, !phrase.isEmpty {
                    duolingoPhrasePanel(item: item, phrase: phrase)
                        .padding(.top, 4)
                }

                // ── アクションボタン行（いいね・コメント・シェア）──────────
                HStack(spacing: 0) {
                    // いいね
                    Button {
                        onLike?(item)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: item.isLiked ? "heart.fill" : "heart")
                                .font(.system(size: 20 * UIScale.font, weight: .regular))
                                .foregroundColor(item.isLiked ? Color(hex: "#ED4956") : Color.duoDark)
                            if item.likeCount > 0 {
                                Text("\(item.likeCount)")
                                    .font(.system(size: 13 * UIScale.font, weight: .bold))
                                    .foregroundColor(item.isLiked ? Color(hex: "#ED4956") : Color.duoDark)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)

                    // コメント
                    Button {
                        onComment?(item)
                        dismiss()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "bubble.right")
                                .font(.system(size: 19 * UIScale.font, weight: .regular))
                                .foregroundColor(Color.duoDark)
                            if !item.feedComments.isEmpty {
                                Text("\(item.feedComments.count)")
                                    .font(.system(size: 13 * UIScale.font, weight: .bold))
                                    .foregroundColor(Color.duoDark)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)

                    // シェア
                    Button {
                        onShare?(item)
                        dismiss()
                    } label: {
                        Image(systemName: "paperplane")
                            .font(.system(size: 19 * UIScale.font, weight: .regular))
                            .foregroundColor(Color.duoDark)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 8)

                // ── 投稿コメント一覧 ──────────────────────────────────────
                if !item.feedComments.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Divider().padding(.horizontal, 16)
                        ForEach(item.feedComments) { fc in
                            HStack(alignment: .top, spacing: 10) {
                                ZStack {
                                    Circle().fill(Color.duoGreen.opacity(0.15))
                                        .frame(width: 28, height: 28)
                                    Text(String((fc.authorName.first ?? "?").uppercased()))
                                        .font(.system(size: 12 * UIScale.font, weight: .black))
                                        .foregroundColor(Color.duoGreen)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fc.authorName)
                                        .font(.system(size: 12 * UIScale.font, weight: .black))
                                        .foregroundColor(Color.duoDark)
                                    Text(fc.text)
                                        .font(.system(size: 13 * UIScale.font))
                                        .foregroundColor(Color.duoDark.opacity(0.85))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            if fc.id != item.feedComments.last?.id {
                                Divider().padding(.leading, 54)
                            }
                        }
                        // コメントを書くボタン
                        Button {
                            onComment?(item)
                            dismiss()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.bubble")
                                    .font(.system(size: 14 * UIScale.font, weight: .semibold))
                                Text("コメントを書く")
                                    .font(.system(size: 13 * UIScale.font, weight: .bold))
                            }
                            .foregroundColor(Color.duoBlue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }

                Spacer().frame(height: 20)
            }
        }
        .background(Color.duoBg.ignoresSafeArea())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - FIT メトリクスタイル（WeightFeedDetailSheet と同一デザイン）
    private func tomoMetric(emoji: String, label: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(emoji).font(.system(size: 22 * UIScale.font))
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24 * UIScale.font, weight: .black, design: .rounded))
                    .foregroundColor(color)
                Text(unit)
                    .font(.system(size: 11 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoSubtitle)
            }
            Text(label)
                .font(.system(size: 11 * UIScale.font, weight: .semibold))
                .foregroundColor(Color.duoSubtitle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(color.opacity(0.08))
        .cornerRadius(14)
    }

    // MARK: - FOOD 栄養詳細パネル
    @ViewBuilder
    private func foodNutritionSection(food: PhotoLogHistoryItem) -> some View {
        let n = food.analyzedNutrition
        let totalMacro = n.protein * 4 + n.fat * 9 + n.carbs * 4
        let pPct = totalMacro > 0 ? n.protein * 4 / totalMacro * 100 : 0
        let fPct = totalMacro > 0 ? n.fat * 9 / totalMacro * 100 : 0
        let cPct = totalMacro > 0 ? n.carbs * 4 / totalMacro * 100 : 0

        VStack(alignment: .leading, spacing: 10) {
            // カロリーバナー
            HStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text("\(food.calories)")
                        .font(.system(size: 32 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.0))
                    Text("kcal")
                        .font(.system(size: 11 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoSubtitle)
                }
                Divider().frame(height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    pfcBar(label: "P", percent: pPct, color: Color.duoOrange)
                    pfcBar(label: "F", percent: fPct, color: Color.duoPurple)
                    pfcBar(label: "C", percent: cPct, color: Color.duoBlue)
                }
                Spacer()
                if n.confidence < 1.0 {
                    Text(String(format: "確度\n%.0f%%", n.confidence * 100))
                        .font(.system(size: 10 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoSubtitle)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(12)
            .background(Color(.systemBackground))
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)

            // 説明文
            if !n.description.isEmpty {
                Text(n.description)
                    .font(.system(size: 13 * UIScale.font, weight: .semibold))
                    .foregroundColor(Color.duoDark.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
            }

            // 栄養グリッド
            VStack(alignment: .leading, spacing: 8) {
                Text("栄養素")
                    .font(.system(size: 12 * UIScale.font, weight: .black))
                    .foregroundColor(Color.duoDark)
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 8
                ) {
                    nutritionTile(icon: "💪", label: "たんぱく質", value: String(format: "%.1fg", n.protein), color: Color.duoOrange)
                    nutritionTile(icon: "🛢️", label: "脂質",     value: String(format: "%.1fg", n.fat),     color: Color.duoPurple)
                    nutritionTile(icon: "🍚", label: "炭水化物", value: String(format: "%.1fg", n.carbs),   color: Color.duoBlue)
                    if n.sugar > 0 {
                        nutritionTile(icon: "🍬", label: "糖質",   value: String(format: "%.1fg", n.sugar),  color: Color(hex: "#FDCB6E"))
                    }
                    if n.fiber > 0 {
                        nutritionTile(icon: "🌾", label: "食物繊維", value: String(format: "%.1fg", n.fiber), color: Color(hex: "#00B894"))
                    }
                    if n.sodium > 0 {
                        nutritionTile(icon: "🧂", label: "塩分",   value: String(format: "%.1fg", n.sodium), color: Color(hex: "#B2BEC3"))
                    }
                    if n.water > 0 {
                        nutritionTile(icon: "💧", label: "水分",   value: "\(n.water)ml",                    color: Color(hex: "#1CB0F6"))
                    }
                    if n.caffeine > 0 {
                        nutritionTile(icon: "☕", label: "カフェイン", value: "\(n.caffeine)mg",               color: Color(hex: "#8B5E3C"))
                    }
                    if n.alcohol > 0 {
                        nutritionTile(icon: "🍷", label: "アルコール", value: String(format: "%.1fg", n.alcohol), color: Color.duoPurple)
                    }
                }
            }
            .padding(12)
            .background(Color(.systemBackground))
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private func pfcBar(label: String, percent: Double, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10 * UIScale.font, weight: .black))
                .foregroundColor(color)
                .frame(width: 12)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.15)).frame(height: 8)
                    Capsule().fill(color)
                        .frame(width: max(4, geo.size.width * CGFloat(min(percent / 100, 1))), height: 8)
                }
            }
            .frame(height: 8)
            Text(String(format: "%.0f%%", percent))
                .font(.system(size: 9 * UIScale.font, weight: .bold))
                .foregroundColor(color)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private func nutritionTile(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(icon).font(.system(size: 20 * UIScale.font))
            Text(value)
                .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 8 * UIScale.font, weight: .bold))
                .foregroundColor(Color.duoSubtitle)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.10))
        .cornerRadius(12)
    }

    // MARK: - Duolingo フレーズパネル
    @ViewBuilder
    private func duolingoPhrasePanel(item: EduLogHistoryItem, phrase: String) -> some View {
        let isSpeaking   = speakingItemID == item.id
        let langCode     = item.extractedLanguageCode ?? "en"
        let langLabel    = duoLangLabel(langCode)

        VStack(alignment: .leading, spacing: 6) {
            // 言語バッジ + 再生ボタン
            HStack(spacing: 6) {
                Text(duoLangFlag(langCode)).font(.system(size: 16))
                Text(langLabel)
                    .font(.system(size: 11 * UIScale.font, weight: .semibold))
                    .foregroundColor(Color.duoSubtitle)
                Spacer()
                Button {
                    if isSpeaking {
                        DuolingoTextExtractor.shared.stopSpeaking()
                        speakingItemID = nil
                    } else {
                        speakingItemID = item.id
                        DuolingoTextExtractor.shared.speak(phrase: phrase, languageCode: langCode)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                            if speakingItemID == item.id { speakingItemID = nil }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 14))
                        Text(isSpeaking ? "停止" : "再生")
                            .font(.system(size: 12 * UIScale.font, weight: .semibold))
                    }
                    .foregroundColor(isSpeaking ? .red : Color(hex: "#1CB0F6"))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background((isSpeaking ? Color.red : Color(hex: "#1CB0F6")).opacity(0.12))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }

            // フレーズ本文（大）
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

            // ダメな理由
            if let note = item.mistakeNote, !note.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("ダメな理由", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color(hex: "#FF3B30"))
                    Text(note)
                        .font(.system(size: 13 * UIScale.font))
                        .foregroundColor(Color.duoDark)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color(hex: "#FF3B30").opacity(0.07))
                .cornerRadius(8)
                .padding(.top, 2)
            }

            // 文法メモ
            if let note = item.grammarNote, !note.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("文法メモ", systemImage: "text.book.closed")
                        .font(.system(size: 11 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color(hex: "#FF9500"))
                    Text(note)
                        .font(.system(size: 13 * UIScale.font))
                        .foregroundColor(Color.duoDark)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color(hex: "#FF9500").opacity(0.08))
                .cornerRadius(8)
                .padding(.top, 2)
            }

            // 例文
            if let examples = item.exampleSentences, !examples.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("例文", systemImage: "quote.bubble")
                        .font(.system(size: 11 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color(hex: "#58CC02"))
                    ForEach(Array(examples.enumerated()), id: \.offset) { idx, ex in
                        let exKey        = "\(item.id)-ex\(idx)"
                        let isExSpeaking = speakingExampleKey == exKey
                        HStack(alignment: .top, spacing: 6) {
                            Text("\(idx + 1).")
                                .font(.system(size: 13 * UIScale.font, weight: .bold))
                                .foregroundColor(Color(hex: "#58CC02"))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(ex.text)
                                    .font(.system(size: 14 * UIScale.font, weight: .semibold))
                                    .foregroundColor(Color.duoDark)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let tr = ex.translationJA, !tr.isEmpty {
                                    Text(tr)
                                        .font(.system(size: 12 * UIScale.font))
                                        .foregroundColor(Color.duoSubtitle)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer()
                            Button {
                                if isExSpeaking {
                                    DuolingoTextExtractor.shared.stopSpeaking()
                                    speakingExampleKey = nil
                                } else {
                                    speakingExampleKey = exKey
                                    speakingItemID     = nil
                                    DuolingoTextExtractor.shared.speak(
                                        phrase: ex.text, languageCode: langCode)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                                        if speakingExampleKey == exKey { speakingExampleKey = nil }
                                    }
                                }
                            } label: {
                                Image(systemName: isExSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(isExSpeaking ? .red : Color(hex: "#58CC02"))
                                    .frame(width: 28, height: 28)
                                    .background((isExSpeaking ? Color.red : Color(hex: "#58CC02")).opacity(0.12))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(10)
                .background(Color(hex: "#58CC02").opacity(0.07))
                .cornerRadius(8)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.systemGray6).opacity(0.6))
    }

    // MARK: - Language helpers
    private func duoLangFlag(_ code: String) -> String {
        switch code {
        case "zh", "zh-Hans", "cmn-Hans": return "🇨🇳"
        case "zh-Hant":                   return "🇹🇼"
        case "ko":                        return "🇰🇷"
        case "fr":                        return "🇫🇷"
        case "es":                        return "🇪🇸"
        case "de":                        return "🇩🇪"
        case "it":                        return "🇮🇹"
        case "pt":                        return "🇵🇹"
        case "ru":                        return "🇷🇺"
        case "ar":                        return "🇸🇦"
        default:                          return "🇬🇧"
        }
    }

    private func duoLangLabel(_ code: String) -> String {
        switch code {
        case "zh", "zh-Hans", "cmn-Hans": return "中国語（簡体字）"
        case "zh-Hant":                   return "中国語（繁体字）"
        case "ko":                        return "韓国語"
        case "fr":                        return "フランス語"
        case "es":                        return "スペイン語"
        case "de":                        return "ドイツ語"
        case "it":                        return "イタリア語"
        case "pt":                        return "ポルトガル語"
        case "ru":                        return "ロシア語"
        case "ar":                        return "アラビア語"
        default:                          return "英語"
        }
    }
}
