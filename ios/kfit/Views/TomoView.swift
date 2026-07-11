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
    let photoURL: String
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

    /// 1カテゴリのポイント（曜日内訳内）
    struct CategoryPts: Identifiable {
        let id = UUID()
        let emoji: String
        let name: String
        let points: Int
        let color: Color
    }
    /// 1曜日の内訳
    struct DayBreakdown: Identifiable {
        let id: String          // 曜日ラベル (月, 火, ...)
        let label: String
        let total: Int
        var categories: [CategoryPts]
    }

    struct TomoEntry: Identifiable {
        let id: String
        let email: String
        let username: String
        let totalPoints: Int
        let streak: Int
        var weeklyPoints: Int
        var isMe: Bool = false
        var rank: Int = 0
        var photoURL: String = ""
        /// 曜日別ポイント内訳 (月〜日 順、ポイントが0の曜日も含む)
        var dailyBreakdown: [DayBreakdown] = []
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

    /// 今週の月曜日 0:00 を返す（週間ポイント集計の起点）
    static func thisMonday() -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 2  // Monday
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7
        return cal.date(byAdding: .day, value: -daysFromMonday, to: today) ?? today
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

        // ── 週間ポイント（曜日内訳込み）と友達ID を同時並列取得 ────────────────
        async let myWeeklyTask = weeklyPointsWithBreakdown(userId: uid)
        async let friendIdsTask: [String] = {
            (try? await withAsyncTimeout(seconds: 8) {
                let snap = try await Firestore.firestore()
                    .collection("friendships")
                    .whereField("members", arrayContains: uid)
                    .getDocuments()
                var ids: [String] = []
                for doc in snap.documents {
                    let members = doc.data()["members"] as? [String] ?? []
                    if let other = members.first(where: { $0 != uid }) { ids.append(other) }
                }
                return ids
            }) ?? []
        }()

        let (myWeeklyResult, friendIds) = await (myWeeklyTask, friendIdsTask)
        let myWeekly = myWeeklyResult.total
        let myDailyBreakdown = myWeeklyResult.daily

        // 自分のエントリーを先に追加
        var all: [TomoEntry] = []
        let myPhotoURL = Auth.auth().currentUser?.photoURL?.absoluteString
            ?? UserDefaults.standard.string(forKey: "cachedCurrentUserPhotoURL") ?? ""
        if let me = AuthenticationManager.shared.userProfile {
            var myEntry = TomoEntry(id: uid, email: me.email, username: me.username,
                                   totalPoints: me.totalPoints, streak: me.streak,
                                   weeklyPoints: myWeekly, isMe: true, photoURL: myPhotoURL)
            myEntry.dailyBreakdown = myDailyBreakdown
            all.append(myEntry)
            // 自分のプロフィールを公開（非同期・ノンブロッキング）
            let myPoints = me.totalPoints; let myStreak = me.streak
            Task {
                try? await Firestore.firestore().collection("publicProfiles").document(uid).setData([
                    "weeklyPoints": myWeekly,
                    "totalPoints": myPoints,
                    "streak": myStreak,
                    "updatedAt": Timestamp(date: Date())
                ], merge: true)
            }
        }

        // 自分だけでも先に表示（友達データ待ちの間もランキング欄に自分が見える）
        if !all.isEmpty {
            var preliminary = all
            for i in preliminary.indices { preliminary[i].rank = i + 1 }
            entries = preliminary
        }

        // ── 友達のプロフィールと投稿を全員まとめて並列フェッチ ──────────────
        struct FriendResult: Sendable {
            let profile: FriendProfile?
            let posts: [FriendPostData]
            let fid: String
        }

        let friendResults: [FriendResult] = await withTaskGroup(of: FriendResult.self) { group in
            for fid in friendIds {
                group.addTask {
                    async let profileTask = { () -> FriendProfile? in
                        try? await withAsyncTimeout(seconds: 8) { () -> FriendProfile? in
                            let pdoc = try await Firestore.firestore()
                                .collection("publicProfiles").document(fid).getDocument()
                            guard pdoc.exists, let data = pdoc.data() else { return nil }
                            return FriendProfile(
                                email: data["email"] as? String ?? "",
                                username: data["username"] as? String ?? "TOMO",
                                totalPoints: data["totalPoints"] as? Int ?? 0,
                                streak: data["streak"] as? Int ?? 0,
                                weeklyPoints: data["weeklyPoints"] as? Int ?? 0,
                                photoURL: data["photoURL"] as? String
                                    ?? data["authorPhotoURL"] as? String ?? ""
                            )
                        }
                    }()

                    async let postsTask = { () -> [FriendPostData] in
                        (try? await withAsyncTimeout(seconds: 8) {
                            let snap = try await Firestore.firestore()
                                .collection("publicProfiles").document(fid)
                                .collection("posts")
                                .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: TomoManager.oneWeekAgo()))
                                .order(by: "timestamp", descending: true)
                                .limit(to: 15)
                                .getDocuments()
                            return snap.documents.map { TomoManager.makeFriendPostData(fid: fid, doc: $0) }
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
                    weeklyPoints: p.weeklyPoints,
                    photoURL: p.photoURL
                ))
            }
            for p in result.posts { feedItems.append(makeFriendItem(from: p)) }
        }

        // 友達の写真投稿ポイント（投稿 × 10）を weeklyPoints に加算
        // ※ 自分のポイントは weeklyPointsWithBreakdown() で既に算入済みのためスキップ
        let monday = Self.thisMonday()
        var postCountMap: [String: Int] = [:]
        for item in feedItems where item.timestamp >= monday {
            postCountMap[item.authorName, default: 0] += 1
        }

        for i in all.indices {
            guard !all[i].isMe else { continue }   // 自分は二重計算を防ぐためスキップ
            let name = all[i].username
            all[i].weeklyPoints += (postCountMap[name] ?? 0) * 10
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
                        return snap.documents.map { TomoManager.makeFriendPostData(fid: fid, doc: $0) }
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

    /// Firestore ドキュメントから FriendPostData を生成する共通ヘルパー
    private nonisolated static func makeFriendPostData(fid: String, doc: QueryDocumentSnapshot) -> FriendPostData {
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
        let query = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let isEmail = query.contains("@")
        let lowerQuery = query.lowercased()

        guard !query.isEmpty else {
            addResult = .error("メールアドレスまたはユーザー名を入力してください")
            return
        }

        if isEmail, entries.contains(where: { !$0.isMe && $0.email.lowercased() == lowerQuery }) {
            addResult = .alreadyAdded; return
        }

        addResult = .searching

        // メールアドレスなら emailLower で検索、そうでなければ username で検索
        let found: TomoSearchResult?
        do {
            found = try await withAsyncTimeout(seconds: 12) {
                let db = Firestore.firestore()
                let snap: QuerySnapshot
                if isEmail {
                    snap = try await db.collection("publicProfiles")
                        .whereField("emailLower", isEqualTo: lowerQuery)
                        .limit(to: 1)
                        .getDocuments()
                } else {
                    // username は大文字小文字を区別するので、まず完全一致、次に元の文字列を試みる
                    let snapExact = try await db.collection("publicProfiles")
                        .whereField("username", isEqualTo: query)
                        .limit(to: 1)
                        .getDocuments()
                    snap = snapExact.documents.isEmpty
                        ? try await db.collection("publicProfiles")
                            .whereField("username", isEqualTo: lowerQuery)
                            .limit(to: 1)
                            .getDocuments()
                        : snapExact
                }
                guard let doc = snap.documents.first else { return nil }
                let d = doc.data()
                return TomoSearchResult(
                    id: doc.documentID,
                    username: d["username"] as? String ?? query,
                    email: d["email"] as? String ?? query,
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
            addResult = .notFound(query); return
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

    /// 今週の合計ポイントとカテゴリ別・曜日別内訳を返す
    private func weeklyPointsWithBreakdown(userId: String) async -> (total: Int, daily: [DayBreakdown]) {
        var cal = Calendar.current
        cal.firstWeekday = 2  // 月曜始まり
        let today = Date()
        let weekday = cal.component(.weekday, from: today)
        let daysSinceMonday = weekday == 1 ? 6 : weekday - 2
        guard let monday = cal.date(byAdding: .day, value: -daysSinceMonday,
                                    to: cal.startOfDay(for: today)) else { return (0, []) }

        let docs = (try? await withAsyncTimeout(seconds: 12) {
            try await Firestore.firestore()
                .collection("users").document(userId)
                .collection("completed-exercises")
                .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: monday))
                .getDocuments()
        })?.documents ?? []

        let dayLabels = ["月", "火", "水", "木", "金", "土", "日"]

        // カテゴリ別・曜日別ポイント
        var trainingPts = [Int](repeating: 0, count: 7)

        for doc in docs {
            let data = doc.data()
            let pts = data["points"] as? Int ?? 0
            guard pts > 0 else { continue }
            if let ts = (data["timestamp"] as? Timestamp)?.dateValue() {
                let wd = cal.component(.weekday, from: ts)
                let idx = wd == 1 ? 6 : wd - 2  // 月=0, …, 日=6
                if idx >= 0 && idx < 7 { trainingPts[idx] += pts }
            }
        }

        // EDU 投稿（EduLogManager ローカル履歴）: 1件 = 10pt
        var eduPts = [Int](repeating: 0, count: 7)
        for item in EduLogManager.shared.history where item.timestamp >= monday {
            let wd = cal.component(.weekday, from: item.timestamp)
            let idx = wd == 1 ? 6 : wd - 2
            if idx >= 0 && idx < 7 { eduPts[idx] += 10 }
        }

        // 食事投稿（PhotoLogManager ローカル履歴）: 1件 = 10pt
        var foodPts = [Int](repeating: 0, count: 7)
        for item in PhotoLogManager.shared.history where item.timestamp >= monday {
            let wd = cal.component(.weekday, from: item.timestamp)
            let idx = wd == 1 ? 6 : wd - 2
            if idx >= 0 && idx < 7 { foodPts[idx] += 10 }
        }

        let daily: [DayBreakdown] = dayLabels.enumerated().map { (i, label) in
            var cats: [CategoryPts] = []
            if trainingPts[i] > 0 {
                cats.append(CategoryPts(emoji: "💪", name: "トレーニング", points: trainingPts[i], color: Color.duoBlue))
            }
            if eduPts[i] > 0 {
                cats.append(CategoryPts(emoji: "📚", name: "EDU", points: eduPts[i], color: Color(hex: "#F5A623")))
            }
            if foodPts[i] > 0 {
                cats.append(CategoryPts(emoji: "🍽️", name: "食事", points: foodPts[i], color: Color(hex: "#6C5CE7")))
            }
            let total = trainingPts[i] + eduPts[i] + foodPts[i]
            return DayBreakdown(id: label, label: label, total: total, categories: cats)
        }
        let grandTotal = daily.map(\.total).reduce(0, +)
        return (grandTotal, daily)
    }

    // 後方互換：合計のみ返す（内部で新関数を呼ぶ）
    private func weeklyPoints(userId: String) async -> Int {
        await weeklyPointsWithBreakdown(userId: userId).total
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

// items と startIndex をひとまとめに渡すことで、sheet(isPresented:) の
// 状態キャプチャ競合を防ぎ、初回から正しくコンテンツが表示されるようにする
struct SwipeDetailRequest: Identifiable {
    let id = UUID()
    let items: [EduLogHistoryItem]
    let startIndex: Int
}

struct TomoView: View {
    @Binding var selectedTab: Int
    @Binding var showRecordMenu: Bool
    @StateObject private var manager = TomoManager()
    @StateObject private var eduLogManager = EduLogManager.shared
    @State private var emailInput = ""
    @State private var showShareSheet = false
    @State private var shareText = ""

    private var inviteShareItems: [Any] {
        var items: [Any] = [shareText]
        if let url = URL(string: "https://apps.apple.com/app/fitingo") { items.append(url) }
        return items
    }
    // PhotoLogManager は kfitApp から EnvironmentObject で配布済みのため
    // @StateObject による二重購読を解消（不要な View 再レンダリングを防ぐ）
    @EnvironmentObject private var photoLogManager: PhotoLogManager
    @State private var selectedEduItem: EduLogHistoryItem? = nil
    @State private var selectedFoodItem: PhotoLogHistoryItem? = nil   // FOOD投稿の詳細
    @State private var swipeDetailRequest: SwipeDetailRequest? = nil  // スワイプ詳細（item:で渡し空白バグ回避）
    @State private var commentTargetItem: EduLogHistoryItem? = nil
    @State private var shareTargetItem: EduLogHistoryItem? = nil
    @State private var categoryGroupTarget: TomoView.FeedCategoryGroup? = nil
    @State private var showOlderFeed = false
    @State private var showInviteSheet = false
    @State private var deleteConfirmItem: EduLogHistoryItem? = nil
    @State private var speakingItemID: String? = nil       // TTS 再生中のアイテム ID
    @State private var speakingExampleKey: String? = nil   // 例文 TTS 再生中のキー（"itemID-index"）
    @State private var expandedRankId: String? = nil       // ポイント内訳エクスパンド中のエントリー ID
    @ObservedObject private var ttsEngine = DuolingoTextExtractor.shared
    @ObservedObject private var linkFetcher = LinkMetadataFetcher.shared
    @State private var showFoodLog = false             // FOOD → フォトログ
    @State private var eduRecordTarget: TomoQuickRecord? = nil  // 写真記録シート対象
    @State private var selectedCategory: String? = nil  // カテゴリー絞り込み（nil=すべて）
    @State private var showFavoritesOnly: Bool = false  // お気に入りフィルター
    @State private var selectedDuolingoLanguage: String? = nil  // Duolingo言語フィルター
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
        .onAppear {
            rebuildFeedCache()
            // 共有直後に TomoView が生成された場合、OCR 等の非同期処理が
            // 少し遅れて history を更新する可能性があるため 0.5 秒後にも再構築
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                rebuildFeedCache()
            }
        }
        .onReceive(eduLogManager.$history) { _ in scheduleFeedRebuild() }
        .onReceive(photoLogManager.$history) { _ in scheduleFeedRebuild() }
        .onReceive(manager.$friendFeedItems) { _ in scheduleFeedRebuild() }
        .onReceive(manager.$isLoadingOlderPosts) { loading in
            // 古い投稿のロード完了時にフィードを再ビルド
            if !loading { scheduleFeedRebuild() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .duolingoShareProcessed)) { _ in
            // Duolingo 共有処理完了 → フィードを即時再構築（historyへのinsertは通知より前に完了済み）
            rebuildFeedCache()
        }
        .onChange(of: selectedCategory) { (_: String?, newVal: String?) in
            if newVal != "Duolingo" { selectedDuolingoLanguage = nil }
            rebuildFeedCache()
        }
        .onChange(of: showFavoritesOnly) { _, _ in rebuildFeedCache() }
        .onChange(of: selectedDuolingoLanguage) { _, _ in rebuildFeedCache() }
        .onChange(of: showOlderFeed) { _, _ in rebuildFeedCache() }
        .sheet(isPresented: $showShareSheet) {
            SystemShareSheet(items: inviteShareItems)
        }
        .sheet(item: $selectedEduItem) { item in
            EduFeedDetailSheet(item: item)
        }
        .sheet(item: $selectedFoodItem) { item in
            PhotoFeedDetailSheet(item: item)
        }
        .sheet(item: $swipeDetailRequest) { req in
            swipeDetailSheet(req)
        }
        .sheet(item: $commentTargetItem) { item in
            FeedCommentsSheet(item: item, eduLogManager: eduLogManager,
                              photoLogManager: photoLogManager)
        }
        .sheet(item: $shareTargetItem) { item in
            socialShareSheet(item)
        }
        .sheet(item: $categoryGroupTarget) { grp in
            categoryGroupSheet(grp)
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
        swipeDetailRequest = SwipeDetailRequest(items: [item], startIndex: 0)
    }

    /// スワイプ詳細シートの生成（body 内に直接書くと型推論がタイムアウトするため分離）
    private func swipeDetailSheet(_ req: SwipeDetailRequest) -> SwipeableTomoDetailSheet {
        SwipeableTomoDetailSheet(
            items: req.items,
            startIndex: req.startIndex,
            photoLogManager: photoLogManager,
            onComment: { commentTargetItem = $0 },
            onLike: { toggleLikeFeed($0) },
            onShare: { shareTargetItem = $0 }
        )
    }

    /// SNS共有シートの生成（型推論タイムアウト回避のため分離）
    private func socialShareSheet(_ item: EduLogHistoryItem) -> SocialShareSheet {
        let url: URL? = item.sharedUrl.flatMap { URL(string: $0) }
        return SocialShareSheet(item: item, shareURL: url, overrideImage: item.thumbnail)
    }

    /// カテゴリグループ一覧シートの生成（型推論タイムアウト回避のため分離）
    private func categoryGroupSheet(_ grp: FeedCategoryGroup) -> CategoryGroupListSheet {
        CategoryGroupListSheet(
            group: grp,
            onTapItem: { openDetail($0); categoryGroupTarget = nil },
            onLike: { eduLogManager.toggleLike(id: $0.id) },
            onComment: { commentTargetItem = $0; categoryGroupTarget = nil },
            onShare: { shareTargetItem = $0; categoryGroupTarget = nil }
        )
    }

    /// 同一グループ（同日×同カテゴリ）の複数アイテムをスワイプ詳細で開く
    private func openDetailInGroup(_ item: EduLogHistoryItem, siblings: [EduLogHistoryItem]) {
        guard siblings.count > 1 else {
            openDetail(item)
            return
        }
        let idx = siblings.firstIndex(where: { $0.id == item.id }) ?? 0
        swipeDetailRequest = SwipeDetailRequest(items: siblings, startIndex: idx)
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
        if showFavoritesOnly {
            items = items.filter { $0.isFavorite }
        }
        if let lang = selectedDuolingoLanguage {
            items = items.filter { $0.extractedLanguageCode == lang }
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
            var base = selectedCategory.map { cat in all.filter { categoryKey(for: $0) == cat } } ?? all
            if showFavoritesOnly { base = base.filter { $0.isFavorite } }
            if let lang = selectedDuolingoLanguage { base = base.filter { $0.extractedLanguageCode == lang } }
            let hasLocalOlder = base.count > base.filter { $0.timestamp >= oneWeekAgo }.count
            cachedHasOlderFeed = hasLocalOlder || manager.hasOlderPosts
        }
    }

    // MARK: - カテゴリー絞り込みバー

    @ViewBuilder
    private var categoryFilterBar: some View {
        if !cachedFeedCategories.isEmpty {
            VStack(spacing: 4) {
                // カテゴリーチップ行（リセットXボタンを先頭に）
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        // 絞り込み中のみXボタンを先頭表示
                        if selectedCategory != nil || showFavoritesOnly {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedCategory = nil
                                    selectedDuolingoLanguage = nil
                                    showFavoritesOnly = false
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18 * UIScale.font))
                                    .foregroundColor(Color.duoSubtitle)
                            }
                            .buttonStyle(.plain)
                        }
                        categoryChip(label: "すべて", emoji: "🗂", isSelected: selectedCategory == nil && !showFavoritesOnly) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedCategory = nil
                                selectedDuolingoLanguage = nil
                                showFavoritesOnly = false
                            }
                        }
                        ForEach(cachedFeedCategories) { cat in
                            categoryChip(label: cat.key, emoji: cat.emoji,
                                         isSelected: selectedCategory == cat.key && !showFavoritesOnly) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if showFavoritesOnly { showFavoritesOnly = false }
                                    selectedCategory = (selectedCategory == cat.key) ? nil : cat.key
                                }
                            }
                        }
                        // お気に入りチップ（常に一番右）
                        categoryChip(label: "お気に入り", emoji: "⭐️", isSelected: showFavoritesOnly) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showFavoritesOnly.toggle()
                                if showFavoritesOnly {
                                    selectedCategory = nil
                                    selectedDuolingoLanguage = nil
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }

                // Duolingo 選択時: 言語フィルターチップ行
                if selectedCategory == "Duolingo" {
                    let duoItems = allFeedItems.filter { categoryKey(for: $0) == "Duolingo" }
                    let langCodes: [String] = {
                        var seen = Set<String>()
                        return duoItems.compactMap { $0.extractedLanguageCode }
                            .filter { seen.insert($0).inserted }
                    }()
                    if !langCodes.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                Text("言語")
                                    .font(.system(size: 10 * UIScale.font, weight: .bold))
                                    .foregroundColor(Color.duoSubtitle)
                                    .padding(.leading, 12)
                                ForEach(langCodes, id: \.self) { code in
                                    let name = DuolingoTextExtractor.shared.languageDisplayNamePublic(code)
                                    categoryChip(label: name, emoji: languageFlag(code),
                                                 isSelected: selectedDuolingoLanguage == code) {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedDuolingoLanguage = (selectedDuolingoLanguage == code) ? nil : code
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
            .padding(.bottom, 4)
        }
    }

    private func categoryChip(label: String, emoji: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(emoji).font(.system(size: 12 * UIScale.font))
                Text(label)
                    .font(.system(size: 11 * UIScale.font, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .white : Color.duoDark)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(isSelected ? Color.duoBlue : Color(.systemGray6))
            .cornerRadius(14)
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
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color(hex: "#833ab4"), Color(hex: "#fd1d1d"), Color(hex: "#fcb045")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 26, height: 26)
                    Circle()
                        .fill(Color(.systemBackground))
                        .frame(width: 22, height: 22)
                    UserAvatarView(
                        name: item.authorFirstName,
                        photoURL: item.authorPhotoURL.isEmpty
                            ? (UserDefaults.standard.string(forKey: "cachedCurrentUserPhotoURL") ?? "")
                            : item.authorPhotoURL,
                        size: 19
                    )
                }

                VStack(alignment: .leading, spacing: 0) {
                    let displayName = isOwnPost(item) ? "YOU" : item.authorFirstName
                    let isYou = isOwnPost(item)
                    Text(displayName)
                        .font(.system(size: 10 * UIScale.font, weight: .black))
                        .foregroundColor(isYou ? Color.duoGreen : Color.duoDark)
                    Text(relativeTimeString(item.timestamp))
                        .font(.system(size: 8 * UIScale.font))
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
                            .font(.system(size: 10 * UIScale.font))
                        Text(categoryKey(for: item))
                            .font(.system(size: 8 * UIScale.font, weight: .semibold))
                            .foregroundColor(selectedCategory == categoryKey(for: item) ? .white : Color.duoSubtitle)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(selectedCategory == categoryKey(for: item) ? Color.duoBlue : Color(.systemGray6))
                    .cornerRadius(8)
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
                        .font(.system(size: 14 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color.duoSubtitle)
                        .padding(.leading, 2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)

            // ── リンクのみ（サムネなし）→ テキストカード / それ以外 → Instagram風写真 ──
            let isLinkOnly = item.sharedUrl != nil && item.thumbnail == nil &&
                             !item.id.hasPrefix("food_") &&
                             item.weightKg == nil
            if isLinkOnly, let rUrlStr = item.sharedUrl, let rUrl = URL(string: rUrlStr) {
                readingLinkTextCard(item: item, urlStr: rUrlStr, url: rUrl)
            } else {
            Button { openDetail(item) } label: {
                let isFood = item.id.hasPrefix("food_")
                let foodItem = isFood ? originalFoodItem(for: item) : nil
                let mealInfo = mealTimeInfo(for: item.timestamp)
                let hasThumb = (foodItem?.thumbnail ?? item.thumbnail) != nil
                // 写真なし + URLあり → リンクプレビューを正方形エリアに表示
                let showLinkMain = !hasThumb && item.sharedUrl != nil
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
                    } else if showLinkMain, let urlStr = item.sharedUrl {
                        // リンク投稿: 縦横コンパクト（高さ = 幅の52%）＋ フォールバックアイコン
                        let fetched = linkFetcher.meta(for: urlStr)
                        let host = URL(string: urlStr)?.host ?? ""
                        GeometryReader { geo in
                            Group {
                                if let img = fetched?.thumbnailImage {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: geo.size.width, height: geo.size.height)
                                        .clipped()
                                } else if fetched == nil || fetched?.isLoading == true {
                                    ZStack {
                                        Color(.secondarySystemBackground)
                                        ProgressView()
                                            .tint(Color.duoSubtitle)
                                    }
                                } else {
                                    // 取得済みだが画像なし → サービスアイコン
                                    ZStack {
                                        Color(.secondarySystemBackground)
                                        VStack(spacing: 8) {
                                            Text(feedServiceEmoji(from: host))
                                                .font(.system(size: 44 * UIScale.font))
                                            Text(feedServiceName(from: host))
                                                .font(.system(size: 11 * UIScale.font, weight: .semibold))
                                                .foregroundColor(Color.duoSubtitle)
                                        }
                                    }
                                }
                            }
                        }
                        .aspectRatio(1.0 / 0.52, contentMode: .fit)
                        .frame(maxWidth: .infinity)
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
                        // 言語バッジ + 再生ボタン
                        let isSpeakingThis = speakingItemID == item.id
                        HStack(spacing: 4) {
                            Text(languageFlag(langCode))
                                .font(.system(size: 12 * UIScale.font))
                            Text(languageLabel(langCode))
                                .font(.system(size: 9 * UIScale.font, weight: .bold))
                                .foregroundColor(.white)
                            // 再生ボタン
                            Button {
                                if isSpeakingThis {
                                    ttsEngine.stopSequence()
                                    speakingItemID = nil
                                } else {
                                    // 再生するフレーズリストを構築（メイン + 例文 + 関連表現）
                                    var phrases: [(phrase: String, langCode: String)] = []
                                    if let p = item.extractedPhrase, !p.isEmpty {
                                        phrases.append((p, langCode))
                                    }
                                    if let examples = item.exampleSentences {
                                        phrases += examples.map { ($0.text, langCode) }
                                    }
                                    if let related = item.relatedWords {
                                        phrases += related.map { ($0.text, langCode) }
                                    }
                                    guard !phrases.isEmpty else { return }
                                    speakingItemID = item.id
                                    speakingExampleKey = nil
                                    // 再生 = ハート+1 & マインドポイント +10
                                    recordMindPlay(item: item)
                                    ttsEngine.speakSequence(phrases) {
                                        DispatchQueue.main.async { speakingItemID = nil }
                                    }
                                }
                            } label: {
                                Image(systemName: isSpeakingThis ? "stop.fill" : "play.fill")
                                    .font(.system(size: 8 * UIScale.font, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(tomoLangColor(langCode))
                        .clipShape(Capsule())
                        .padding(8)
                    }
                }
                // 右上: Weight → Day◯ バッジ / リンクあり → リンクボタン
                .overlay(alignment: .topTrailing) {
                    if item.weightKg != nil {
                        Text(dayLabel(for: item.timestamp))
                            .font(.system(size: 10 * UIScale.font, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.black.opacity(0.52))
                            .clipShape(Capsule())
                            .padding(8)
                    } else if let urlStr = item.sharedUrl, let url = URL(string: urlStr) {
                        // リンクあり投稿: リンクを一覧から直接開けるボタン
                        Button {
                            UIApplication.shared.open(url)
                        } label: {
                            Image(systemName: "arrow.up.right.square.fill")
                                .font(.system(size: 16 * UIScale.font, weight: .bold))
                                .foregroundColor(.white)
                                .padding(6)
                                .background(Color.black.opacity(0.48))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
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
            if let dp = item.duolingoPhrase {
                DuolingoPhraseView(data: dp)
                    .padding(.horizontal, 12).padding(.bottom, 8)
            }

            // ── リンクカード（写真あり→thumb付き、写真なし→thumb非表示）──
            if let urlStr = item.sharedUrl, let url = URL(string: urlStr) {
                let hasPhoto = item.thumbnail != nil
                feedLinkCard(url: url, title: item.sharedTitle, urlStr: urlStr,
                             description: item.sharedDescription,
                             showThumb: hasPhoto)
                    .padding(.horizontal, 12).padding(.bottom, 8)
            }
            } // end else (非読書リンクのみ投稿)

            Spacer().frame(height: 8)
        }
        .background(Color(.systemBackground))
        .task(id: item.sharedUrl) {
            if let urlStr = item.sharedUrl {
                linkFetcher.prefetch(urlString: urlStr)
            }
        }
    }

    // MARK: - カルーセルカード（同一ユーザー×同一カテゴリー複数投稿）

    private func instaCarouselCard(_ pg: FeedPostGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── ヘッダー（ユーザー + カテゴリー + 件数） ───────────────────
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
                        name: pg.authorFirstName,
                        photoURL: pg.authorPhotoURL.isEmpty
                            ? (UserDefaults.standard.string(forKey: "cachedCurrentUserPhotoURL") ?? "")
                            : pg.authorPhotoURL,
                        size: 25
                    )
                }

                VStack(alignment: .leading, spacing: 0) {
                    let isYou = isOwnPost(pg.latestItem)
                    Text(isYou ? "YOU" : pg.authorFirstName)
                        .font(.system(size: 11 * UIScale.font, weight: .black))
                        .foregroundColor(isYou ? Color.duoGreen : Color.duoDark)
                    Text(relativeTimeString(pg.latestItem.timestamp))
                        .font(.system(size: 9 * UIScale.font))
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
                            .font(.system(size: 10 * UIScale.font))
                        Text(pg.categoryKey)
                            .font(.system(size: 9 * UIScale.font, weight: .semibold))
                            .foregroundColor(selectedCategory == pg.categoryKey ? .white : Color.duoSubtitle)
                        Text("×\(pg.items.count)")
                            .font(.system(size: 9 * UIScale.font, weight: .black))
                            .foregroundColor(selectedCategory == pg.categoryKey ? .white.opacity(0.85) : Color.duoBlue)
                    }
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(selectedCategory == pg.categoryKey ? Color.duoBlue : Color(.systemGray6))
                    .cornerRadius(8)
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
                        .font(.system(size: 14 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color.duoSubtitle)
                        .padding(.leading, 2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

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

        // リンク投稿は高さを縮小（写真・通常投稿は正方形のまま）
        let isLinkSlide = item.sharedUrl != nil && (foodItem?.thumbnail ?? item.thumbnail) == nil
        let slideHeight: CGFloat = isLinkSlide ? slideWidth * 0.52 : slideWidth

        return VStack(spacing: 0) {
        Button { openDetailInGroup(item, siblings: siblings.isEmpty ? [item] : siblings) } label: {
            ZStack {
                Group {
                    if let thumb = foodItem?.thumbnail ?? item.thumbnail {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                    } else if let urlStr = item.sharedUrl {
                        let fetched = linkFetcher.meta(for: urlStr)
                        if let ogImg = fetched?.thumbnailImage {
                            // OGイメージ表示
                            Image(uiImage: ogImg)
                                .resizable()
                                .scaledToFill()
                        } else if fetched == nil || fetched?.isLoading == true {
                            // 取得中: スピナー
                            ZStack {
                                Color(.secondarySystemBackground)
                                ProgressView()
                                    .tint(Color.duoSubtitle)
                                    .scaleEffect(1.0)
                            }
                        } else {
                            // 取得済みだが画像なし: サービスアイコン
                            let host = URL(string: urlStr)?.host ?? ""
                            ZStack {
                                Color(.secondarySystemBackground)
                                VStack(spacing: 6) {
                                    Text(feedServiceEmoji(from: host))
                                        .font(.system(size: 36 * UIScale.font))
                                    Text(feedServiceName(from: host))
                                        .font(.system(size: 10 * UIScale.font, weight: .semibold))
                                        .foregroundColor(Color.duoSubtitle)
                                }
                            }
                        }
                    } else {
                        ZStack {
                            instaGradient(for: item)
                            Text(item.activityEmoji.isEmpty ? "📝" : item.activityEmoji)
                                .font(.system(size: 72 * UIScale.font))
                                .shadow(color: .black.opacity(0.25), radius: 8)
                        }
                    }
                }
                .frame(width: slideWidth, height: slideHeight)
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
                            .background(tomoLangColor(langCode))
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
            .frame(width: slideWidth, height: slideHeight)
        }
        .buttonStyle(.plain)

        // URLがある投稿: OG画像を上に表示済みのためカードはタイトル＋サービス名のみ（thumb非表示）
        if let urlStr = item.sharedUrl, let url = URL(string: urlStr) {
            feedLinkCard(url: url, title: item.sharedTitle, urlStr: urlStr,
                         description: item.sharedDescription, showThumb: false)
                .frame(width: slideWidth)
                .padding(.top, 2)
                .task(id: urlStr) { linkFetcher.prefetch(urlString: urlStr) }
        }
        } // end VStack
    }

    // MARK: - 読書・勉強リンクのみ投稿: テキストカード（一覧用）

    private func readingLinkTextCard(item: EduLogHistoryItem, urlStr: String, url: URL) -> some View {
        let host = url.host ?? urlStr
        let svcEmoji  = feedServiceEmoji(from: host)
        let svcName   = feedServiceName(from: host)
        let svcColor  = feedServiceColor(from: host)
        let fetched   = linkFetcher.meta(for: urlStr)
        let dispTitle = (fetched?.title ?? item.sharedTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let dispDesc  = (fetched?.description ?? item.sharedDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        return VStack(alignment: .leading, spacing: 0) {
            // ── リンクコンテンツ（タップで詳細へ）──────────────
            Button { openDetail(item) } label: {
                HStack(alignment: .top, spacing: 12) {
                    // 書影 or サービスアイコン
                    if let img = fetched?.thumbnailImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(svcColor.opacity(0.14))
                            Text(svcEmoji)
                                .font(.system(size: 34 * UIScale.font))
                        }
                        .frame(width: 72, height: 72)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        if !dispTitle.isEmpty {
                            Text(dispTitle)
                                .font(.system(size: 13 * UIScale.font, weight: .bold))
                                .foregroundColor(Color.duoDark)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !dispDesc.isEmpty {
                            Text(dispDesc)
                                .font(.system(size: 11 * UIScale.font))
                                .foregroundColor(Color.duoSubtitle)
                                .lineLimit(3)
                        }
                        HStack(spacing: 4) {
                            Text(svcEmoji).font(.system(size: 10 * UIScale.font))
                            Text(svcName)
                                .font(.system(size: 10 * UIScale.font, weight: .semibold))
                                .foregroundColor(svcColor)
                        }
                    }

                    Spacer()

                    // リンクを直接開くボタン
                    Button { UIApplication.shared.open(url) } label: {
                        Image(systemName: "arrow.up.right.square.fill")
                            .font(.system(size: 20 * UIScale.font))
                            .foregroundColor(svcColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            // ── ユーザーのコメント（あれば）────────────────────
            if !item.comment.isEmpty {
                Divider().padding(.horizontal, 12)
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 10 * UIScale.font, weight: .bold))
                        .foregroundColor(svcColor.opacity(0.7))
                        .padding(.top, 2)
                    Text(item.comment)
                        .font(.system(size: 12 * UIScale.font))
                        .foregroundColor(Color.duoDark.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(svcColor.opacity(0.05))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(svcColor.opacity(0.15), lineWidth: 1))
        .padding(.horizontal, 12).padding(.vertical, 4)
    }

    // MARK: - 読書リンクカード（フィード一覧用・コンパクト版）

    private func feedLinkCard(url: URL, title: String?, urlStr: String,
                              description: String? = nil,
                              showThumb: Bool = true) -> some View {
        let host        = url.host ?? urlStr
        let serviceName = feedServiceName(from: host)
        let serviceEmoji = feedServiceEmoji(from: host)
        let color       = feedServiceColor(from: host)

        let fetched      = linkFetcher.meta(for: urlStr)
        let displayTitle = (fetched?.title ?? title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let displayDesc  = (fetched?.description ?? description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let thumbImage   = fetched?.thumbnailImage

        return Button { UIApplication.shared.open(url) } label: {
            HStack(spacing: 10) {
                // サービスアイコン or 書影（showThumb: false の場合はサービス絵文字のみ）
                if showThumb, let img = thumbImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Text(serviceEmoji)
                        .font(.system(size: 20 * UIScale.font))
                        .frame(width: 32, height: 32)
                        .background(color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 2) {
                    if !displayTitle.isEmpty {
                        Text(displayTitle)
                            .font(.system(size: 12 * UIScale.font, weight: .bold))
                            .foregroundColor(Color.duoDark)
                            .lineLimit(2)
                    }
                    if showThumb && !displayDesc.isEmpty {
                        Text(displayDesc)
                            .font(.system(size: 10 * UIScale.font))
                            .foregroundColor(Color.duoSubtitle)
                            .lineLimit(2)
                    }
                    Text(serviceName)
                        .font(.system(size: 10 * UIScale.font, weight: .semibold))
                        .foregroundColor(color)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12 * UIScale.font, weight: .bold))
                    .foregroundColor(color)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(color.opacity(0.07))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func feedServiceName(from host: String) -> String {
        let h = host.lowercased()
        if h.contains("audible") { return "Audible" }
        if h.contains("amazon") { return "Amazon Books" }
        if h.contains("kindle") { return "Kindle" }
        if h.contains("libbyapp") || h.contains("overdrive") { return "Libby 図書館" }
        if h.contains("books.google") { return "Google Play Books" }
        if h.contains("bookwalker") { return "BookWalker" }
        if h.contains("kobo") { return "楽天Kobo" }
        if h.contains("booklive") { return "BookLive" }
        return "📖 リンクを開く"
    }

    private func feedServiceEmoji(from host: String) -> String {
        let h = host.lowercased()
        if h.contains("audible") { return "🎧" }
        if h.contains("libbyapp") || h.contains("overdrive") { return "🏛️" }
        return "📖"
    }

    private func feedServiceColor(from host: String) -> Color {
        let h = host.lowercased()
        if h.contains("audible") { return Color(hex: "#F28C28") }
        if h.contains("amazon") || h.contains("kindle") { return Color(hex: "#FF9900") }
        if h.contains("libbyapp") || h.contains("overdrive") { return Color(hex: "#2E86AB") }
        if h.contains("books.google") { return Color(hex: "#4285F4") }
        if h.contains("bookwalker") { return Color(hex: "#E4001A") }
        if h.contains("kobo") { return Color(hex: "#6A0DAD") }
        return Color(hex: "#5E5CE6")
    }


    // MARK: - ヘルパー

    /// 言語コードに対応した Edulingo 準拠のバッジ背景色
    private func tomoLangColor(_ code: String) -> Color { languageBadgeColor(code) }

    /// フィード内で再生ボタンを押したときに呼ぶ。
    /// 投稿の likeCount を Firestore で +1（ハートカウント）し、マインドポイント +10 を付与する。
    private func recordMindPlay(item: EduLogHistoryItem) {
        let db = Firestore.firestore()
        guard let currentUID = Auth.auth().currentUser?.uid else { return }

        let authorUID: String
        let postDocID: String
        if item.id.hasPrefix("friend_") {
            let stripped = String(item.id.dropFirst("friend_".count))
            if let range = stripped.range(of: "_") {
                authorUID = String(stripped[stripped.startIndex..<range.lowerBound])
                postDocID = String(stripped[range.upperBound...])
            } else { authorUID = currentUID; postDocID = item.id }
        } else if item.id.hasPrefix("own_") {
            authorUID = currentUID
            postDocID = String(item.id.dropFirst("own_".count))
        } else {
            authorUID = currentUID; postDocID = item.id
        }

        db.collection("publicProfiles").document(authorUID)
            .collection("posts").document(postDocID)
            .updateData(["likeCount": FieldValue.increment(Int64(1))]) { _ in }

        let baseId = item.id.hasPrefix("own_") ? String(item.id.dropFirst(4)) : item.id
        if let idx = EduLogManager.shared.history.firstIndex(where: { $0.id == item.id || $0.id == baseId }) {
            EduLogManager.shared.history[idx].likeCount += 1
        }

        db.collection("users").document(currentUID)
            .setData(["mindPlayPoints": FieldValue.increment(Int64(10))], merge: true) { _ in }
    }

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

                // 友達アバター（自分は表示しない）＋招待ボタン
                HStack(spacing: -8) {
                    ForEach(manager.entries.filter { !$0.isMe }.prefix(4)) { entry in
                        headerAvatarCircle(entry)
                    }
                    // 招待ボタン
                    Button { showInviteSheet = true } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.25))
                                .frame(width: 28, height: 28)
                                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 11 * UIScale.font, weight: .bold))
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
        let photoURL = entry.isMe
            ? (Auth.auth().currentUser?.photoURL?.absoluteString
                ?? UserDefaults.standard.string(forKey: "cachedCurrentUserPhotoURL") ?? "")
            : entry.photoURL
        return ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color(hex: "#833ab4"), Color(hex: "#fd1d1d"), Color(hex: "#fcb045")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 30, height: 30)
            Circle()
                .fill(Color.white)
                .frame(width: 26, height: 26)
            UserAvatarView(
                name: firstName(of: entry.username),
                photoURL: photoURL,
                size: 23
            )
        }
        .overlay(Circle().stroke(Color.white, lineWidth: 1.5).frame(width: 30, height: 30))
    }

    @ViewBuilder
    private func addedFriendAvatar(_ tomo: TomoSearchResult) -> some View {
        let initial = String(tomo.username.prefix(1)).uppercased()
        ZStack {
            Circle().fill(Color.duoBlue.opacity(0.15)).frame(width: 44, height: 44)
            if let url = URL(string: tomo.photoURL), !tomo.photoURL.isEmpty {
                // CachedAsyncImage で URLCache を活用し繰り返しダウンロードを防止
                CachedAsyncImage(url: url) { image in
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
                        .frame(width: 52, alignment: .trailing)
                    Text("連続")
                        .font(.system(size: 9 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoSubtitle)
                        .frame(width: 36, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "#1CB5E0").opacity(0.08), Color(hex: "#4776E6").opacity(0.08)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )

                ForEach(manager.entries) { entry in
                    rankRow(entry)
                    if entry.id != manager.entries.last?.id {
                        Divider().padding(.leading, 54)
                    }
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.07), radius: 8, y: 2)
        }
    }

    private func rankRow(_ entry: TomoManager.TomoEntry) -> some View {
        let isExpanded = expandedRankId == entry.id

        return VStack(spacing: 0) {
            // ── メイン行 ───────────────────────────────────────────────────
            HStack(spacing: 8) {
                // アバター＋順位バッジ（コンパクト）
                ZStack(alignment: .bottomTrailing) {
                    UserAvatarView(name: firstName(of: entry.username), photoURL: entry.photoURL, size: 30)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))

                    Circle()
                        .fill(rankBadgeColor(entry.rank))
                        .frame(width: 14, height: 14)
                        .overlay(
                            Text(entry.rank <= 3 ? rankEmoji(entry.rank) : "\(entry.rank)")
                                .font(.system(size: entry.rank <= 3 ? 8 : 7, weight: .black))
                                .foregroundColor(.white)
                        )
                        .offset(x: 2, y: 2)
                }
                .frame(width: 36)

                // 名前（1行固定・はみ出しは省略）
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
                            .layoutPriority(1)  // YOU バッジは優先的に確保
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(0)  // 右側の固定幅エリアを優先し名前を縮める

                // 今週pt（タップでエクスパンド）
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        expandedRankId = isExpanded ? nil : entry.id
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text("\(entry.weeklyPoints)pt")
                            .font(.system(size: 12 * UIScale.font, weight: .black))
                            .foregroundColor(Color.duoBlue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8 * UIScale.font, weight: .bold))
                            .foregroundColor(Color.duoBlue.opacity(0.7))
                    }
                    .fixedSize()  // ポイント表示は縮まないよう固定
                }
                .buttonStyle(.plain)
                .layoutPriority(1)

                // 連続
                Text("🔥\(entry.streak)日")
                    .font(.system(size: 11 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoDark)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .fixedSize()  // 連続日数も縮まないよう固定
                    .layoutPriority(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

            // ── 曜日別・カテゴリ別内訳（エクスパンド時）─────────────────────
            if isExpanded && !entry.dailyBreakdown.isEmpty {
                // 合計行
                let breakdownTotal = entry.dailyBreakdown.map(\.total).reduce(0, +)
                VStack(spacing: 0) {
                    // ヘッダー（合計確認）
                    HStack {
                        Text("曜日別内訳")
                            .font(.system(size: 9 * UIScale.font, weight: .bold))
                            .foregroundColor(Color.duoSubtitle)
                        Spacer()
                        Text("計 \(breakdownTotal)pt")
                            .font(.system(size: 9 * UIScale.font, weight: .black, design: .rounded))
                            .foregroundColor(Color.duoBlue)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .padding(.bottom, 4)

                    Divider().padding(.horizontal, 10)

                    // 各曜日行（ポイントがある曜日のみ表示）
                    let activeDays = entry.dailyBreakdown.filter { $0.total > 0 }
                    if activeDays.isEmpty {
                        Text("今週はまだ記録なし")
                            .font(.system(size: 10 * UIScale.font))
                            .foregroundColor(Color.duoSubtitle)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(activeDays) { day in
                            HStack(spacing: 6) {
                                Text(day.label)
                                    .font(.system(size: 10 * UIScale.font, weight: .black))
                                    .foregroundColor(Color.duoSubtitle)
                                    .frame(width: 16, alignment: .center)
                                // カテゴリチップ
                                HStack(spacing: 4) {
                                    ForEach(day.categories) { cat in
                                        HStack(spacing: 2) {
                                            Text(cat.emoji)
                                                .font(.system(size: 9 * UIScale.font))
                                            Text("\(cat.points)pt")
                                                .font(.system(size: 9 * UIScale.font, weight: .bold))
                                                .foregroundColor(cat.color)
                                        }
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(cat.color.opacity(0.1))
                                        .clipShape(Capsule())
                                    }
                                }
                                Spacer(minLength: 0)
                                Text("\(day.total)pt")
                                    .font(.system(size: 10 * UIScale.font, weight: .black, design: .rounded))
                                    .foregroundColor(Color.duoDark)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 4)
                        }
                    }
                }
                .background(Color.duoBlue.opacity(0.04))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
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
    @ObservedObject private var ttsEngine = DuolingoTextExtractor.shared
    @ObservedObject private var eduLog = EduLogManager.shared
    @ObservedObject private var linkFetcher = LinkMetadataFetcher.shared
    @State private var editingItem: EduLogHistoryItem? = nil
    @State private var deleteConfirmItem: EduLogHistoryItem? = nil
    @Environment(\.dismiss) private var dismiss

    // 再生によって更新されたハートカウント（item.id → likeCount）
    @State private var playLikeCounts: [String: Int] = [:]

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
            // items が渡された時点で確実にコンテンツを表示するため、
            // items.count を id に使って TabView を強制再生成する
            TabView(selection: $selection) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    slidePage(item: item)
                        .tag(idx)
                        .task(id: item.sharedUrl) {
                            if let urlStr = item.sharedUrl {
                                linkFetcher.prefetch(urlString: urlStr)
                            }
                        }
                }
            }
            .id(items.map(\.id).joined())
            .tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .always : .never))
            .background(Color.duoBg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(items.count > 1 ? "\(selection + 1) / \(items.count)" : "")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    detailLeadingButtons
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .foregroundColor(Color.duoGreen)
                        .fontWeight(.bold)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                detailDeleteButton
            }
            .alert("投稿を削除しますか？", isPresented: Binding(
                get: { deleteConfirmItem != nil },
                set: { if !$0 { deleteConfirmItem = nil } }
            )) {
                Button("削除", role: .destructive) {
                    if let it = deleteConfirmItem {
                        EduLogManager.shared.deleteItem(id: it.id)
                        deleteConfirmItem = nil
                        dismiss()
                    }
                }
                Button("キャンセル", role: .cancel) { deleteConfirmItem = nil }
            }
            .sheet(item: $editingItem) { item in
                EduPhraseEditSheet(item: item) { updated in
                    EduLogManager.shared.updateItem(updated)
                    editingItem = nil
                }
            }
            .onAppear {
                // TabView(.page) が初期 selection を反映しないことがある SwiftUI バグの workaround
                if startIndex > 0 {
                    let target = startIndex
                    DispatchQueue.main.async { selection = target }
                }
            }
        }
    }

    /// 写真右上にオーバーレイするハート（お気に入り＋再生カウント）＋編集ボタン
    @ViewBuilder
    private func photoActionButtons(item: EduLogHistoryItem) -> some View {
        let isOwn = isOwnItem(item)
        let isFav = (liveItem(for: item)?.isFavorite ?? false)
        let likeCount = playLikeCounts[item.id] ?? item.likeCount

        VStack(spacing: 6) {
            // ── ハート（お気に入り表示＋再生カウント）──
            VStack(spacing: 2) {
                Button {
                    guard isOwn else { return }
                    let targetId = item.id.hasPrefix("own_") ? String(item.id.dropFirst(4)) : item.id
                    if EduLogManager.shared.history.contains(where: { $0.id == targetId || $0.id == item.id }) {
                        EduLogManager.shared.toggleFavorite(id: targetId)
                    } else {
                        var localCopy = item
                        localCopy.id = targetId
                        localCopy.isFavorite = true
                        EduLogManager.shared.importAndFavorite(localCopy)
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: isFav ? "heart.fill" : "heart")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(isFav ? Color(hex: "#FF4B4B") : .white)
                        if likeCount > 0 {
                            Text("\(likeCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 40, height: likeCount > 0 ? 48 : 40)
                    .background(Color.black.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

            // ── 編集（自分の投稿のみ）──
            if isOwn {
                Button {
                    editingItem = liveItem(for: item) ?? item
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
    }

    @ViewBuilder
    private var detailLeadingButtons: some View {
        EmptyView()
    }

    @ViewBuilder
    private var detailDeleteButton: some View {
        let currentItem = selection < items.count ? items[selection] : nil
        let isOwn = currentItem.map { isOwnItem($0) } ?? false

        if isOwn {
            Button {
                if let it = currentItem {
                    deleteConfirmItem = it
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(14)
                    .background(Color(hex: "#FF4B4B"))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 20)
            .padding(.bottom, 30)
        }
    }

    private func isOwnItem(_ item: EduLogHistoryItem) -> Bool {
        // kedu の fetchMyOwnPosts は自分の Firebase ポストに "own_" プレフィックスを付ける。
        // このプレフィックスは自分のコレクション(publicProfiles/{uid}/posts)から
        // 取得した場合のみ付与されるため、存在すれば必ず自分の投稿。
        if item.id.hasPrefix("own_") { return true }

        // kfit / kedu ローカル履歴に存在すれば自分の投稿
        return EduLogManager.shared.history.contains { $0.id == item.id }
    }

    /// EduLogManager.shared から最新の item を取得（favorites など更新反映）。
    /// ローカル履歴にない "own_" アイテム（kfit 経由でのみ投稿されたもの等）は
    /// item 自身を返す（Firebase 取得版がそのまま live 扱い）。
    private func liveItem(for item: EduLogHistoryItem) -> EduLogHistoryItem? {
        let baseId = item.id.hasPrefix("own_") ? String(item.id.dropFirst(4)) : item.id
        if let found = EduLogManager.shared.history.first(where: { $0.id == item.id || $0.id == baseId }) {
            return found
        }
        // ローカル履歴にない自分の投稿（"own_" プレフィックス付き）→ item 自体を返す
        if item.id.hasPrefix("own_") { return item }
        return nil
    }

    /// 再生ボタンを押したときに呼ぶ。
    /// - 投稿の likeCount を Firestore で +1（ハートカウント）
    /// - 再生した自分に EDU/マインドポイント +10 を付与
    private func recordPlay(item: EduLogHistoryItem) {
        let db = Firestore.firestore()
        guard let currentUID = Auth.auth().currentUser?.uid else { return }

        // ── 投稿ドキュメントのパスを item.id から解決 ──
        // friend_{authorUID}_{docID} → publicProfiles/{authorUID}/posts/{docID}
        // own_{docID} / ローカルUUID → publicProfiles/{currentUID}/posts/{docID}
        let authorUID: String
        let postDocID: String
        if item.id.hasPrefix("friend_") {
            let stripped = String(item.id.dropFirst("friend_".count))
            if let range = stripped.range(of: "_") {
                authorUID = String(stripped[stripped.startIndex..<range.lowerBound])
                postDocID = String(stripped[range.upperBound...])
            } else {
                authorUID = currentUID; postDocID = item.id
            }
        } else if item.id.hasPrefix("own_") {
            authorUID = currentUID
            postDocID = String(item.id.dropFirst("own_".count))
        } else if item.id.hasPrefix("food_") {
            authorUID = currentUID
            postDocID = item.id
        } else {
            authorUID = currentUID; postDocID = item.id
        }

        // Firestore: 投稿の likeCount を +1
        db.collection("publicProfiles").document(authorUID)
            .collection("posts").document(postDocID)
            .updateData(["likeCount": FieldValue.increment(Int64(1))]) { _ in }

        // ローカル楽観的更新
        let current = playLikeCounts[item.id]
            ?? (EduLogManager.shared.history.first { $0.id == item.id }?.likeCount ?? item.likeCount)
        playLikeCounts[item.id] = current + 1

        // 自分の投稿ならローカル履歴にも反映
        if !item.id.hasPrefix("friend_") {
            let baseId = item.id.hasPrefix("own_") ? String(item.id.dropFirst(4)) : item.id
            if let idx = EduLogManager.shared.history.firstIndex(where: { $0.id == baseId }) {
                EduLogManager.shared.history[idx].likeCount += 1
            }
        }

        // Firestore: EDU/マインドポイント +10
        db.collection("users").document(currentUID)
            .setData(["mindPlayPoints": FieldValue.increment(Int64(10))], merge: true) { _ in }
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
                    } else if item.sharedUrl != nil && thumb == nil && item.weightKg == nil {
                        // リンクのみ（サムネなし）: 画像エリアなし（下部の sharedLinkCard で表示）
                        EmptyView()
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
                                    Text(languageFlag(langCode))
                                        .font(.system(size: 15 * UIScale.font))
                                    Text(languageLabel(langCode))
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
                .overlay(alignment: .topTrailing) {
                    // 写真右上: ハート（お気に入り＋再生カウント）＋編集
                    let hasPhoto = !(item.sharedUrl != nil && thumb == nil && item.weightKg == nil)
                    if hasPhoto {
                        photoActionButtons(item: item)
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

                // ── リンクカード（sharedUrl があれば最上部に大きく表示）─────
                if let urlStr = item.sharedUrl, let url = URL(string: urlStr) {
                    let isLinkOnlyDetail = thumb == nil && item.weightKg == nil
                    sharedLinkCard(url: url, title: item.sharedTitle, urlStr: urlStr,
                                   description: item.sharedDescription,
                                   imageURL: item.sharedImageURL)
                        .padding(.horizontal, 16)
                        .padding(.top, isLinkOnlyDetail ? 24 : 12)
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
                if let dp = item.duolingoPhrase {
                    DuolingoPhraseView(data: dp)
                        .padding(.horizontal, 12).padding(.top, 4)
                }

                // ── アクションボタン行（いいね・コメント・シェア）──────────
                HStack(spacing: 0) {
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
    // MARK: - 読書リンクカード

    private func sharedLinkCard(url: URL, title: String?, urlStr: String,
                                description: String? = nil, imageURL: String? = nil) -> some View {
        let host        = url.host ?? urlStr
        let serviceName = readingServiceName(from: host)
        let svcColor    = readingServiceColor(from: host)
        let serviceEmoji = readingServiceEmoji(from: host)

        let fetched      = linkFetcher.meta(for: urlStr)
        let displayTitle = (fetched?.title ?? title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let displayDesc  = (fetched?.description ?? description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let thumbImage   = fetched?.thumbnailImage

        return Button {
            UIApplication.shared.open(url)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // ── 書影サムネイル（取得できた場合）─────────────────────────
                if let img = thumbImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                        .clipped()
                }

                HStack(alignment: .top, spacing: 12) {
                    // サービスアイコン（書影なし時は大きめに）
                    ZStack {
                        RoundedRectangle(cornerRadius: thumbImage == nil ? 10 : 8, style: .continuous)
                            .fill(svcColor)
                            .frame(width: thumbImage == nil ? 46 : 36,
                                   height: thumbImage == nil ? 46 : 36)
                        Text(serviceEmoji)
                            .font(.system(size: thumbImage == nil ? 22 : 18))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        // タイトル
                        if !displayTitle.isEmpty {
                            Text(displayTitle)
                                .font(.system(size: 13 * UIScale.font, weight: .bold))
                                .foregroundColor(Color.duoDark)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        // 説明文
                        if !displayDesc.isEmpty {
                            Text(displayDesc)
                                .font(.system(size: 11 * UIScale.font))
                                .foregroundColor(Color.duoSubtitle)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        // サービス名
                        Text(serviceName)
                            .font(.system(size: 10 * UIScale.font, weight: .semibold))
                            .foregroundColor(svcColor)
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right.square.fill")
                        .font(.system(size: 18 * UIScale.font))
                        .foregroundColor(svcColor)
                }
                .padding(thumbImage == nil ? 14 : 12)
            }
            .background(Color(.systemBackground))
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.07), radius: 6, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(svcColor.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func readingServiceName(from host: String) -> String {
        let h = host.lowercased()
        if h.contains("audible") { return "Audible（オーディオブック）" }
        if h.contains("amazon") && h.contains("/dp/") { return "Amazon（本）" }
        if h.contains("kindle") { return "Kindle" }
        if h.contains("libbyapp") || h.contains("overdrive") { return "Libby（図書館）" }
        if h.contains("books.google") { return "Google Play Books" }
        if h.contains("bookwalker") { return "BookWalker" }
        if h.contains("kobo") { return "楽天Kobo" }
        if h.contains("booklive") { return "BookLive" }
        if h.contains("ebookjapan") { return "ebookjapan" }
        return host
    }

    private func readingServiceEmoji(from host: String) -> String {
        let h = host.lowercased()
        if h.contains("audible") { return "🎧" }
        if h.contains("libbyapp") || h.contains("overdrive") { return "🏛️" }
        return "📖"
    }

    private func readingServiceColor(from host: String) -> Color {
        let h = host.lowercased()
        if h.contains("audible") { return Color(hex: "#F28C28") }
        if h.contains("amazon") || h.contains("kindle") { return Color(hex: "#FF9900") }
        if h.contains("libbyapp") || h.contains("overdrive") { return Color(hex: "#2E86AB") }
        if h.contains("books.google") { return Color(hex: "#4285F4") }
        if h.contains("bookwalker") { return Color(hex: "#E4001A") }
        if h.contains("kobo") { return Color(hex: "#6A0DAD") }
        return Color(hex: "#5E5CE6")
    }

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

}

// MARK: - Edu phrase edit sheet
struct EduPhraseEditSheet: View {
    @State private var item: EduLogHistoryItem
    private let onSave: (EduLogHistoryItem) -> Void
    @Environment(\.dismiss) private var dismiss

    init(item: EduLogHistoryItem, onSave: @escaping (EduLogHistoryItem) -> Void) {
        _item = State(initialValue: item)
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                Section("フレーズ（外国語）") {
                    TextEditor(text: Binding(
                        get: { item.extractedPhrase ?? "" },
                        set: { item.extractedPhrase = $0.isEmpty ? nil : $0 }
                    ))
                    .frame(minHeight: 60)
                }
                Section("発音・ピンイン") {
                    TextField("発音記号など", text: Binding(
                        get: { item.pronunciation ?? "" },
                        set: { item.pronunciation = $0.isEmpty ? nil : $0 }
                    ))
                }
                Section("日本語訳") {
                    TextEditor(text: Binding(
                        get: { item.translationJA ?? "" },
                        set: { item.translationJA = $0.isEmpty ? nil : $0 }
                    ))
                    .frame(minHeight: 50)
                }
                if item.exampleSentences?.isEmpty == false {
                    Section("例文（タップで編集）") {
                        ForEach(Array((item.exampleSentences ?? []).enumerated()), id: \.offset) { idx, _ in
                            exampleRow(idx: idx)
                        }
                    }
                }
                Section("コメント") {
                    TextEditor(text: $item.comment)
                        .frame(minHeight: 50)
                }
            }
            .navigationTitle("フレーズを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") { dismiss() }
                        .foregroundColor(.secondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { onSave(item) }
                        .fontWeight(.bold)
                        .foregroundColor(Color(hex: "#58CC02"))
                }
            }
        }
    }

    @ViewBuilder
    private func exampleRow(idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let phraseBinding = Binding<String>(
                get: { item.exampleSentences?[idx].text ?? "" },
                set: { item.exampleSentences?[idx].text = $0 }
            )
            let transBinding = Binding<String>(
                get: { item.exampleSentences?[idx].translationJA ?? "" },
                set: { item.exampleSentences?[idx].translationJA = $0 }
            )
            TextField("例文", text: phraseBinding)
                .font(.system(size: 14))
            TextField("訳", text: transBinding)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}
