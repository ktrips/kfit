import SwiftUI
import Combine
import PhotosUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - EdulingoView
// kedu アプリのメインビュー。Duolingo / 読書 / 勉強 / 語学 の投稿のみを表示する。
// TomoManager（TomoView.swift 内）と SwipeableTomoDetailSheet を再利用。

struct EdulingoView: View {

    @StateObject private var manager = TomoManager()
    @StateObject private var eduLogManager = EduLogManager.shared
    @EnvironmentObject private var photoLogManager: PhotoLogManager
    @EnvironmentObject private var auth: AuthenticationManager
    @EnvironmentObject private var plus: PlusManager

    // 詳細シート（item: で items とシートを同時に渡し、最初から正しく表示する）
    struct DetailRequest: Identifiable {
        let id = UUID()
        let items: [EduLogHistoryItem]
        let startIndex: Int
    }
    @State private var detailRequest: DetailRequest? = nil

    // カテゴリ絞り込み
    @State private var selectedCategory: String? = nil

    // ソート
    enum SortOrder: String, CaseIterable, Identifiable {
        case newest = "新しい順"
        case oldest = "古い順"
        case category = "カテゴリ順"
        var id: String { rawValue }
    }
    @State private var sortOrder: SortOrder = .newest

    // 言語フィルター（Duolingo の extractedLanguageCode）
    @State private var selectedLanguage: String? = nil

    // 記録シート
    @State private var eduRecordTarget: TomoQuickRecord? = nil

    // 過去フィード
    @State private var showOlderFeed = false

    // ランキング行の展開
    @State private var expandedRankId: String? = nil

    // 削除確認
    @State private var deleteConfirmItem: EduLogHistoryItem? = nil

    // 友達招待
    @State private var showInviteSheet = false
    @State private var emailInput = ""
    @State private var showShareSheet = false
    @State private var shareText = ""

    // ハンバーガーメニュー
    @State private var showHamburgerMenu = false

    // お気に入りフィルター
    @State private var showFavoritesOnly = false

    // 自分の投稿（Firestore publicProfiles/{uid}/posts からフェッチ）
    @State private var myOwnPosts: [EduLogHistoryItem] = []
    @State private var isLoadingMyPosts = false

    // フィルター適用済みアイテムのキャッシュ
    @State private var cachedEduItems: [EduLogHistoryItem] = []
    // フィルター未適用アイテムのキャッシュ（Watch送信・ランキング等で使用）
    @State private var cachedEduItemsUnfiltered: [EduLogHistoryItem] = []

    // 言語フィルター順次再生
    @ObservedObject private var ttsEngine = DuolingoTextExtractor.shared
    @ObservedObject private var linkFetcher = LinkMetadataFetcher.shared
    // 一覧カードの単体 TTS 再生中 ID
    @State private var speakingCardId: String? = nil

    // 再生によって更新されたハートカウント（item.id → likeCount）
    @State private var playLikeCounts: [String: Int] = [:]
    // 今日の再生ポイント合計（表示用）
    @State private var todayPlayPoints: Int = 0
    // 今週の再生ポイント累計（セッション内）
    @State private var weekPlayPoints: Int = 0
    // 今週の日付別再生ポイント（"yyyy-MM-dd" → pt）。週間ランキング内訳表示用
    @State private var myPlayPointsByDay: [String: Int] = [:]
    // Firestore から取得したトータル EDU ポイント
    @State private var totalEduPoints: Int = 0
    // ポイントサマリーシートの表示
    @State private var showPointsSheet = false

    // Edulingo 専用クイックレコード（教育 4 種）
    private let eduQuickRecords: [TomoQuickRecord] = [
        TomoQuickRecord(id: "duolingo", label: "Duolingo", emoji: "🦉", color: Color(hex: "#58CC02"), isFood: false),
        TomoQuickRecord(id: "reading",  label: "読書",     emoji: "📖", color: Color(hex: "#1CB0F6"), isFood: false),
        TomoQuickRecord(id: "study",    label: "勉強",     emoji: "✏️", color: Color(hex: "#FF4B4B"), isFood: false),
        TomoQuickRecord(id: "language", label: "語学",     emoji: "🌍", color: Color(hex: "#CE82FF"), isFood: false),
    ]

    // 日付フォーマッター（毎回生成を避けるため static）
    private static let feedDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月d日 (E)"
        return f
    }()
    private static let relativeShortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日"
        return f
    }()
    private static let rankDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d(E)"
        return f
    }()
    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - 再生記録（ハート+1 & 10ポイント付与）

    /// 投稿の再生ボタンを押したときに呼ぶ。
    /// - 投稿の likeCount を Firestore で +1（ハートカウントとして扱う）
    /// - 再生を行ったユーザーに 10 ポイントを付与
    private func recordPlay(item: EduLogHistoryItem) {
        let db = Firestore.firestore()
        guard let currentUID = Auth.auth().currentUser?.uid else { return }

        // ── 投稿ドキュメントのパスを item.id から解決 ──────────────────────
        // friend_{authorUID}_{docID}  → publicProfiles/{authorUID}/posts/{docID}
        // own_{docID}                → publicProfiles/{currentUID}/posts/{docID}
        // {localUUID}（ローカル自分投稿）→ publicProfiles/{currentUID}/posts/{localUUID}
        let authorUID: String
        let postDocID: String
        if item.id.hasPrefix("friend_") {
            // "friend_<uid>_<docId>" → split で uid と docId を取り出す
            let stripped = String(item.id.dropFirst("friend_".count))
            // uid は 28文字の Firebase UID（英数字）
            if let underscoreRange = stripped.range(of: "_") {
                authorUID = String(stripped[stripped.startIndex..<underscoreRange.lowerBound])
                postDocID = String(stripped[underscoreRange.upperBound...])
            } else {
                authorUID = currentUID
                postDocID = item.id
            }
        } else if item.id.hasPrefix("own_") {
            authorUID = currentUID
            postDocID = String(item.id.dropFirst("own_".count))
        } else {
            authorUID = currentUID
            postDocID = item.id
        }

        // ── Firestore: 投稿の likeCount を +1 ────────────────────────────
        let postRef = db
            .collection("publicProfiles").document(authorUID)
            .collection("posts").document(postDocID)
        postRef.updateData(["likeCount": FieldValue.increment(Int64(1))]) { err in
            if let err { print("[recordPlay] likeCount update failed: \(err)") }
        }

        // ── ローカル状態を即時反映（UXのため楽観的更新） ─────────────────
        let currentCount = playLikeCounts[item.id]
            ?? (EduLogManager.shared.history.first { $0.id == item.id }?.likeCount ?? item.likeCount)
        playLikeCounts[item.id] = currentCount + 1

        // 自分の投稿ならローカル履歴にも反映
        if !item.id.hasPrefix("friend_") {
            let baseId = item.id.hasPrefix("own_") ? String(item.id.dropFirst(4)) : item.id
            if let idx = EduLogManager.shared.history.firstIndex(where: { $0.id == baseId }) {
                EduLogManager.shared.history[idx].likeCount += 1
            }
        }

        // ── Firestore: 再生ポイント +10（今日 & トータル & 今週）──────────
        let userRef = db.collection("users").document(currentUID)
        userRef.setData(["eduPlayPoints": FieldValue.increment(Int64(10))], merge: true) { err in
            if let err { print("[recordPlay] points update failed: \(err)") }
        }
        // 今週の再生ポイント（Firestore: users/{uid}/weeklyEduStats/{YYYY-WW}）
        let weekKey = currentWeekKey()
        let dayKey = Self.dayKeyFormatter.string(from: Date())
        db.collection("users").document(currentUID)
            .collection("weeklyEduStats").document(weekKey)
            .setData([
                "playPoints": FieldValue.increment(Int64(10)),
                "playPointsByDay.\(dayKey)": FieldValue.increment(Int64(10))
            ], merge: true) { _ in }

        todayPlayPoints += 10
        weekPlayPoints += 10
        totalEduPoints += 10
        myPlayPointsByDay[dayKey, default: 0] += 10
    }

    /// 現在の週を "YYYY-WW" 形式で返す（月曜始まり）
    private func currentWeekKey() -> String {
        var cal = Calendar(identifier: .iso8601)
        cal.locale = Locale(identifier: "ja_JP")
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        let y = comps.yearForWeekOfYear ?? 2025
        let w = comps.weekOfYear ?? 1
        return String(format: "%04d-%02d", y, w)
    }

    // MARK: - 教育コンテンツ判定

    private func isEduItem(_ item: EduLogHistoryItem) -> Bool {
        let name = item.activityName.trimmingCharacters(in: .whitespaces)
        if name == "体重ログ" || name == "食事ログ" { return false }
        if name == "日記" || name == "フォト日記" { return false }
        if name.localizedCaseInsensitiveContains("Duolingo") { return true }
        if name == "読書" || name == "勉強" || name == "語学" { return true }
        if name.contains("語学") { return true }
        return false
    }

    private func categoryInfo(for item: EduLogHistoryItem) -> (label: String, emoji: String) {
        let name = item.activityName.trimmingCharacters(in: .whitespaces)
        if name.localizedCaseInsensitiveContains("Duolingo") { return ("Duolingo", "🦉") }
        if name == "読書"                                    { return ("読書", "📖") }
        if name == "勉強"                                    { return ("勉強", "✏️") }
        if name == "語学" || name.contains("語学")           { return ("語学", "🌍") }
        return ("その他", "📝")
    }

    private func catKey(_ item: EduLogHistoryItem) -> String { categoryInfo(for: item).label }
    private func catEmoji(_ item: EduLogHistoryItem) -> String { categoryInfo(for: item).emoji }

    private func isOwnPost(_ item: EduLogHistoryItem) -> Bool {
        if item.id.hasPrefix("friend_") { return false }
        if item.id.hasPrefix("own_") { return true }
        let myName = AuthenticationManager.shared.userProfile?.username
            ?? UserDefaults.standard.string(forKey: "cachedCurrentUserName")
            ?? ""
        return item.authorName == myName || item.authorName.isEmpty
    }

    // MARK: - フィルター済みフィードアイテム

    /// フィルターなしの全 Edu アイテム（Watch 同期用）
    // allEduItemsUnfiltered は rebuildEduCache() 内で cachedEduItemsUnfiltered として計算される

    /// キャッシュを再計算する（onAppear / onChange で呼ぶ）
    private func rebuildEduCache() {
        let friendsEdu = manager.friendFeedItems.filter { isEduItem($0) }
        let existingIds = Set(friendsEdu.map { $0.id })
        // 自分の投稿はローカル履歴を正とし、Firestore取得版で補完する（EDUアイテムのみ）
        let localOwn = EduLogManager.shared.history.filter { isEduItem($0) }
        let localIds = Set(localOwn.map { $0.id })
        // myOwnPosts の id は "own_<firestoreDocID>" 形式
        // firestoreDocID = ローカル item.id なので、"own_" を除去して重複チェック
        let remoteOnly = myOwnPosts.filter { remote in
            let firestoreId = remote.id.hasPrefix("own_") ? String(remote.id.dropFirst(4)) : remote.id
            return !localIds.contains(firestoreId)
                && !localIds.contains(remote.id)
                && !existingIds.contains(remote.id)
        }
        let ownEdu = (localOwn + remoteOnly).filter { !existingIds.contains($0.id) }
        var allItems = ownEdu + friendsEdu

        // フィルター未適用版をキャッシュ（Watch送信・ランキング等で使用、再計算不要）
        cachedEduItemsUnfiltered = allItems.sorted { $0.timestamp > $1.timestamp }

        // フィルター適用
        if showFavoritesOnly {
            let favIds = Set(EduLogManager.shared.history.filter { $0.isFavorite }.map { $0.id })
            allItems = allItems.filter { favIds.contains($0.id) }
        }
        if let cat = selectedCategory {
            allItems = allItems.filter { catKey($0) == cat }
        }
        if let lang = selectedLanguage {
            allItems = allItems.filter { ($0.extractedLanguageCode ?? "").hasPrefix(lang) }
        }
        switch sortOrder {
        case .newest:   allItems.sort { $0.timestamp > $1.timestamp }
        case .oldest:   allItems.sort { $0.timestamp < $1.timestamp }
        case .category: allItems.sort {
            let a = catKey($0); let b = catKey($1)
            return a == b ? $0.timestamp > $1.timestamp : a < b
        }
        }
        cachedEduItems = allItems
    }

    /// フィルター適用済みアイテム（画面表示用）
    private var allEduItems: [EduLogHistoryItem] { cachedEduItems }

    // 投稿に含まれる言語コードの一覧（投稿数が多い順）
    private var availableLanguages: [(code: String, label: String)] {
        // 言語コード（先頭2文字）ごとの投稿数をカウント
        var counts: [String: Int] = [:]
        for item in cachedEduItems {
            guard let raw = item.extractedLanguageCode, !raw.isEmpty else { continue }
            let key = String(raw.prefix(2))
            counts[key, default: 0] += 1
        }
        // 投稿数の多い順にソート
        return counts.keys.sorted { counts[$0, default: 0] > counts[$1, default: 0] }.map { code in
            let label: String
            switch code {
            case "en": label = "🇺🇸 英語"
            case "zh": label = "🇨🇳 中国語"
            case "fr": label = "🇫🇷 フランス語"
            case "es": label = "🇪🇸 スペイン語"
            case "de": label = "🇩🇪 ドイツ語"
            case "ko": label = "🇰🇷 韓国語"
            case "pt": label = "🇧🇷 ポルトガル語"
            case "it": label = "🇮🇹 イタリア語"
            case "ja": label = "🇯🇵 日本語"
            case "ru": label = "🇷🇺 ロシア語"
            case "ar": label = "🇸🇦 アラビア語"
            case "hi": label = "🇮🇳 ヒンディー語"
            case "nl": label = "🇳🇱 オランダ語"
            case "sv": label = "🇸🇪 スウェーデン語"
            case "tr": label = "🇹🇷 トルコ語"
            case "pl": label = "🇵🇱 ポーランド語"
            case "vi": label = "🇻🇳 ベトナム語"
            case "th": label = "🇹🇭 タイ語"
            case "id": label = "🇮🇩 インドネシア語"
            default:   label = "🌐 \(code)"
            }
            return (code: code, label: label)
        }
    }

    private var oneWeekAgo: Date { Date().addingTimeInterval(-7 * 24 * 3600) }

    /// 1週間より古い投稿がキャッシュまたは友達の未ロード分に存在するか
    private var hasOlderFeed: Bool {
        cachedEduItems.contains { $0.timestamp < oneWeekAgo } || manager.hasOlderPosts
    }

    // MARK: - 自分の投稿フェッチ（Firestore publicProfiles/{uid}/posts）

    @MainActor
    private func fetchMyOwnPosts() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoadingMyPosts = true
        defer { isLoadingMyPosts = false }

        let db = Firestore.firestore()
        guard let snap = try? await db
            .collection(FirestoreCollections.publicProfiles).document(uid)
            .collection(FirestoreCollections.posts)
            .order(by: "timestamp", descending: true)
            .limit(to: 100)
            .getDocuments() else { return }

        let fetched: [EduLogHistoryItem] = snap.documents.compactMap { doc in
            let data = doc.data()
            let activityName  = data["activityName"]  as? String ?? ""
            let activityEmoji = data["activityEmoji"] as? String ?? ""

            // 教育コンテンツのみ
            let nameL = activityName.trimmingCharacters(in: .whitespaces)
            let isEdu = nameL.localizedCaseInsensitiveContains("Duolingo")
                     || nameL == "読書" || nameL == "勉強" || nameL == "語学"
                     || nameL.contains("語学")
            guard isEdu else { return nil }

            var item = EduLogHistoryItem(
                activityName: activityName,
                activityEmoji: activityEmoji,
                comment: data["comment"] as? String ?? "",
                authorName: data["authorName"] as? String ?? "",
                authorPhotoURL: data["authorPhotoURL"] as? String ?? "",
                isPublic: true
            )
            // data["id"] = ローカルのitem.id(UUID)。documentIDが自動生成IDの旧形式と互換性を持つ
            let baseId = (data["id"] as? String) ?? doc.documentID
            item.id = "own_\(baseId)"
            item.timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()
            item.likeCount = data["likeCount"] as? Int ?? 0
            item.thumbnailData = (data["thumbnail"] as? String).flatMap { Data(base64Encoded: $0) }
            item.extractedPhrase = data["extractedPhrase"] as? String
            item.extractedLanguageCode = data["extractedLanguageCode"] as? String
            item.translationJA = data["translationJA"] as? String
            item.pronunciation = data["pronunciation"] as? String
            item.grammarNote = data["grammarNote"] as? String
            item.mistakeNote = data["mistakeNote"] as? String
            item.exampleSentences = {
                guard let raw = data["exampleSentences"] as? [[String: Any]],
                      let d = try? JSONSerialization.data(withJSONObject: raw),
                      let decoded = try? JSONDecoder().decode([ExampleSentence].self, from: d)
                else { return nil }
                return decoded
            }()
            item.sharedUrl         = data["sharedUrl"]         as? String
            item.sharedTitle       = data["sharedTitle"]       as? String
            item.sharedDescription = data["sharedDescription"] as? String
            item.sharedImageURL    = data["sharedImageURL"]    as? String
            return item
        }
        myOwnPosts = fetched
    }

    // MARK: - カテゴリーチップ一覧

    private var availableCategories: [(key: String, emoji: String)] {
        let all = cachedEduItems.map { (catKey($0), catEmoji($0)) }
        var seen = Set<String>()
        return all.compactMap { pair -> (key: String, emoji: String)? in
            guard !seen.contains(pair.0) else { return nil }
            seen.insert(pair.0)
            return (key: pair.0, emoji: pair.1)
        }
    }

    // MARK: - 日付グループ

    private struct FeedDay: Identifiable {
        let id: String
        let items: [EduLogHistoryItem]
    }

    private var feedDays: [FeedDay] {
        let fmt = Self.feedDayFormatter
        // showOlderFeed = false のときは過去1週間のみ表示
        let source = showOlderFeed
            ? cachedEduItems
            : cachedEduItems.filter { $0.timestamp >= oneWeekAgo }
        var dict: [String: [EduLogHistoryItem]] = [:]
        var order: [String] = []
        for item in source {
            let key = fmt.string(from: item.timestamp)
            if dict[key] == nil { order.append(key) }
            dict[key, default: []].append(item)
        }
        return order.map { FeedDay(id: $0, items: dict[$0]!) }
    }

    // MARK: - 時刻表示

    private func relativeTimeString(_ date: Date) -> String {
        let diff = -date.timeIntervalSinceNow
        if diff < 60 { return "たった今" }
        if diff < 3600 { return "\(Int(diff / 60))分前" }
        if diff < 86400 { return "\(Int(diff / 3600))時間前" }
        if diff < 86400 * 7 { return "\(Int(diff / 86400))日前" }
        return Self.relativeShortFormatter.string(from: date)
    }

    // MARK: - 週次ランキング計算

    /// 今週月曜 00:00 を返す
    private func thisMonday() -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let daysSinceMon = weekday == 1 ? 6 : weekday - 2
        return cal.date(byAdding: .day, value: -daysSinceMon, to: today) ?? today
    }

    /// 1日1投稿以上を連続した日数（今日から遡る）
    private func calcStreak(posts: [EduLogHistoryItem]) -> Int {
        let cal = Calendar.current
        var streak = 0
        var checkDay = cal.startOfDay(for: Date())
        while true {
            let nextDay = cal.date(byAdding: .day, value: 1, to: checkDay)!
            let hasPost = posts.contains { $0.timestamp >= checkDay && $0.timestamp < nextDay }
            if hasPost {
                streak += 1
                checkDay = cal.date(byAdding: .day, value: -1, to: checkDay)!
            } else {
                break
            }
        }
        return streak
    }

    /// 今週月曜 00:00 以降に絞った Edu ランキングエントリー（投稿 × 10pt + 連続日数）
    private var weeklyEduRanking: [EduRankEntry] {
        let monday = thisMonday()
        let myUID = Auth.auth().currentUser?.uid ?? ""
        let myName = AuthenticationManager.shared.userProfile?.username
            ?? UserDefaults.standard.string(forKey: "cachedCurrentUserName") ?? ""
        let myPhotoURL = Auth.auth().currentUser?.photoURL?.absoluteString
            ?? UserDefaults.standard.string(forKey: "cachedCurrentUserPhotoURL") ?? ""

        let myEduPosts = myOwnPosts.filter { isEduItem($0) }
        let myCount  = myEduPosts.filter { $0.timestamp >= monday }.count
        let myStreak = calcStreak(posts: myEduPosts)

        var entries: [EduRankEntry] = []
        entries.append(EduRankEntry(uid: myUID, username: myName, photoURL: myPhotoURL,
                                    weeklyPostCount: myCount, weeklyPlayPoints: weekPlayPoints,
                                    isMe: true, streak: myStreak))

        for friendEntry in manager.entries.filter({ !$0.isMe }) {
            let fid = friendEntry.id
            let friendPosts = manager.friendFeedItems.filter {
                $0.id.hasPrefix("friend_\(fid)_") && isEduItem($0)
            }
            let count  = friendPosts.filter { $0.timestamp >= monday }.count
            let streak = calcStreak(posts: friendPosts)
            entries.append(EduRankEntry(uid: fid, username: friendEntry.username,
                                        photoURL: friendEntry.photoURL,
                                        weeklyPostCount: count, weeklyPlayPoints: 0,
                                        isMe: false, streak: streak))
        }

        entries.sort { $0.weeklyTotalPt > $1.weeklyTotalPt }
        for i in entries.indices { entries[i].rank = i + 1 }
        return entries
    }

    /// 自分の連続投稿日数（ヘッダー表示用）
    private var myCurrentStreak: Int {
        calcStreak(posts: myOwnPosts.filter { isEduItem($0) })
    }

    /// 今日の投稿によるポイント（投稿数 × 10pt）
    private var todayPostPoints: Int {
        let start = Calendar.current.startOfDay(for: Date())
        let count = myOwnPosts.filter { isEduItem($0) && $0.timestamp >= start }.count
        return count * 10
    }

    // MARK: - ボディ

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        eduRankingSection
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 8)

                        categoryFilterBar

                        feedSection

                        Spacer(minLength: 40)
                    }
                    .padding(.bottom, 20)
                }
                .refreshable {
                    async let a: () = manager.load(force: true)
                    async let b: () = fetchMyOwnPosts()
                    _ = await (a, b)
                }
            }
            .navigationBarHidden(true)
            .safeAreaInset(edge: .top, spacing: 0) { edulingoHeader }
        }
        .task {
            WatchEduSender.shared.activate()
            async let a: () = manager.load()
            async let b: () = fetchMyOwnPosts()
            _ = await (a, b)
            rebuildEduCache()
            WatchEduSender.shared.sendEduItemsDebounced(cachedEduItemsUnfiltered)
            // トータル・今週 EDU ポイントを Firestore から取得
            if let uid = Auth.auth().currentUser?.uid {
                let db = Firestore.firestore()

                // ユーザードキュメントから累計再生ポイントを取得
                let userSnap = try? await db.collection("users").document(uid).getDocument()
                if let data = userSnap?.data() {
                    // Firestore の increment は Int64 で返るため NSNumber 経由でキャスト
                    let playPt = (data["eduPlayPoints"] as? NSNumber)?.intValue ?? 0
                    let postPt = myOwnPosts.filter { isEduItem($0) }.count * 10
                    totalEduPoints = playPt + postPt
                }

                // 今週の再生ポイントを Firestore から取得
                let weekKey  = currentWeekKey()
                let weekSnap = try? await db.collection("users").document(uid)
                    .collection("weeklyEduStats").document(weekKey).getDocument()
                if let wData = weekSnap?.data() {
                    let fetchedWeekPt = (wData["playPoints"] as? NSNumber)?.intValue ?? 0
                    if fetchedWeekPt > weekPlayPoints {
                        weekPlayPoints = fetchedWeekPt
                    }
                    if let byDay = wData["playPointsByDay"] as? [String: Any] {
                        var merged = myPlayPointsByDay
                        for (key, value) in byDay {
                            let pt = (value as? NSNumber)?.intValue ?? 0
                            merged[key] = max(merged[key] ?? 0, pt)
                        }
                        myPlayPointsByDay = merged
                    }
                }
            }
            // 既存のローカル履歴を全件 Firebase に同期（バックフィル）
            EduLogManager.shared.syncAllPublicPosts()
            // 90秒ごとに友達フィードを再取得して最新投稿を反映
            for await _ in Timer.publish(every: 90, on: .main, in: .common).autoconnect().values {
                await fetchMyOwnPosts()
                await manager.load(force: true)
            }
        }
        .sheet(isPresented: $showPointsSheet) {
            EduPointsSummarySheet(
                todayPoints: todayPostPoints + todayPlayPoints,
                weekPoints: (weeklyEduRanking.first(where: { $0.isMe })?.weeklyTotalPt ?? 0),
                totalPoints: totalEduPoints
            )
        }
        .onReceive(manager.$friendFeedItems) { _ in
            rebuildEduCache()
            WatchEduSender.shared.sendEduItemsDebounced(cachedEduItemsUnfiltered)
        }
        .onChange(of: myOwnPosts.count) { _ in
            rebuildEduCache()
            WatchEduSender.shared.sendEduItemsDebounced(cachedEduItemsUnfiltered)
        }
        .onChange(of: selectedCategory) { _ in rebuildEduCache() }
        .onChange(of: selectedLanguage) { _ in
            rebuildEduCache()
            ttsEngine.stopSequence()   // 言語変更時は再生停止
        }
        .onChange(of: sortOrder) { _ in rebuildEduCache() }
        .onChange(of: showFavoritesOnly) { _ in rebuildEduCache() }
        .onReceive(EduLogManager.shared.$history) { _ in
            rebuildEduCache()
            // ローカル履歴変更（新規投稿・OCR完了）を Watch に即時反映
            WatchEduSender.shared.sendEduItemsDebounced(cachedEduItemsUnfiltered)
        }

        // 詳細シート（item: で items を同時に渡すことで初回から正しく表示）
        .fullScreenCover(item: $detailRequest) { req in
            SwipeableTomoDetailSheet(
                items: req.items,
                startIndex: req.startIndex,
                photoLogManager: photoLogManager
            )
        }

        // 記録シート
        .sheet(item: $eduRecordTarget) { rec in
            EdulingoRecordSheet(
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

                        // Edu 系の投稿は kfit スパイラルの「語学・勉強」ノードを完了にする
                        let weekdayNum: Int = {
                            let wd = Calendar.current.component(.weekday, from: Date())
                            return wd == 1 ? 7 : wd - 1
                        }()
                        Task {
                            await TimeSlotManager.shared.completeCustomGoalIfNeeded(id: "wd_study_\(weekdayNum)")
                        }
                        // kfit DashboardView にスパイラル再計算を通知
                        NotificationCenter.default.post(name: .duolingoShareProcessed, object: nil)

                        // 投稿後、少し待ってから自分の投稿一覧を再取得（Firebase 反映確認）
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5秒
                            await fetchMyOwnPosts()
                        }
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }

        // 友達招待シート
        .sheet(isPresented: $showInviteSheet, onDismiss: { manager.addResult = .idle }) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("メールアドレスまたはユーザー名を入力してください")
                            .font(.subheadline).foregroundColor(Color.duoSubtitle)

                        TextField("メールアドレス / ユーザー名", text: $emailInput)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)

                        Button {
                            Task { await manager.addTomo(email: emailInput) }
                        } label: {
                            HStack {
                                if case .searching = manager.addResult {
                                    ProgressView().tint(.white).scaleEffect(0.85)
                                } else {
                                    Text("検索して追加")
                                }
                            }
                            .font(.headline.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(hex: "#58CC02"))
                            .cornerRadius(12)
                        }
                        .disabled(
                            emailInput.trimmingCharacters(in: .whitespaces).isEmpty ||
                            { if case .searching = manager.addResult { return true }; return false }()
                        )

                        // 結果表示
                        eduAddResultView
                    }
                    .padding(20)
                }
                .navigationTitle("🦉 友達を追加")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("閉じる") {
                            showInviteSheet = false
                            emailInput = ""
                        }
                    }
                }
            }
        }
        // シェアシート（未登録ユーザー招待用）
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [shareText])
        }

        // ハンバーガーメニューシート
        .sheet(isPresented: $showHamburgerMenu) {
            KeduMenuSheet(
                showInviteSheet: $showInviteSheet,
                todayPoints: todayPostPoints + todayPlayPoints,
                weekPoints: weeklyEduRanking.first(where: { $0.isMe })?.weeklyTotalPt ?? 0,
                totalPoints: totalEduPoints
            )
            .environmentObject(auth)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }

        // 削除確認
        .confirmationDialog("この投稿を削除しますか？",
                            isPresented: Binding(
                                get: { deleteConfirmItem != nil },
                                set: { if !$0 { deleteConfirmItem = nil } }
                            ), titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                if let item = deleteConfirmItem {
                    EduLogManager.shared.deleteItem(id: item.id)
                }
                deleteConfirmItem = nil
            }
            Button("キャンセル", role: .cancel) { deleteConfirmItem = nil }
        }
    }

    // MARK: - ヘッダー

    private var edulingoHeader: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#58CC02"), Color(hex: "#1CB0F6")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea(edges: .top)

            HStack(spacing: 10) {
                // 左：アプリアイコン＋ロゴ＋＋ボタン
                HStack(spacing: 5) {
                    Image("kedu_icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)

                    HStack(spacing: 0) {
                        Text("Edu")
                            .foregroundColor(Color(hex: "#FFD900"))
                            .font(.system(size: 16 * UIScale.font, weight: .black, design: .rounded))
                        Text("lingo")
                            .foregroundColor(.white)
                            .font(.system(size: 16 * UIScale.font, weight: .black, design: .rounded))
                    }

                    // 記録メニュー（＋）
                    Menu {
                        ForEach(eduQuickRecords) { rec in
                            Button { eduRecordTarget = rec } label: {
                                Text("\(rec.emoji)  \(rec.label)")
                            }
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.25))
                                .frame(width: 26, height: 26)
                                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                            Image(systemName: "plus")
                                .font(.system(size: 11 * UIScale.font, weight: .black))
                                .foregroundColor(.white)
                        }
                    }
                }

                Spacer()

                // 連続投稿日数バッジ
                let streak = myCurrentStreak
                if streak > 0 {
                    HStack(spacing: 3) {
                        Text("🔥")
                            .font(.system(size: 13 * UIScale.font))
                        Text("\(streak)日")
                            .font(.system(size: 12 * UIScale.font, weight: .black))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.orange.opacity(0.35))
                    .clipShape(Capsule())
                }

                // 友達招待ボタン
                Button { showInviteSheet = true } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 16 * UIScale.font, weight: .semibold))
                        .foregroundColor(.white)
                }

                // 右端：ユーザーアイコン（タップでハンバーガーメニュー＋ポイント）
                Button { showHamburgerMenu = true } label: {
                    ZStack(alignment: .topTrailing) {
                        EduUserAvatar(
                            photoURL: Auth.auth().currentUser?.photoURL?.absoluteString ?? "",
                            name: auth.userProfile?.username ?? "",
                            size: 30
                        )
                        .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1.5))
                        Image(systemName: "star.fill")
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(Color(hex: "#FFD700"))
                            .frame(width: 14, height: 14)
                            .background(Color.white)
                            .clipShape(Circle())
                            .offset(x: 3, y: -3)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .frame(height: 48)
        }
        .frame(height: 48)
    }

    // MARK: - クイックレコードバー

    private var quickRecordBar: some View {
        HStack(spacing: 10) {
            ForEach(eduQuickRecords) { rec in
                Button { eduRecordTarget = rec } label: {
                    VStack(spacing: 3) {
                        ZStack {
                            Circle()
                                .fill(rec.color.opacity(0.15))
                                .frame(width: 48, height: 48)
                                .overlay(Circle().stroke(rec.color.opacity(0.3), lineWidth: 1.5))
                            Text(rec.emoji)
                                .font(.system(size: 22 * UIScale.font))
                        }
                        Text(rec.label)
                            .font(.system(size: 9 * UIScale.font, weight: .semibold))
                            .foregroundColor(Color.duoSubtitle)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - ランキングセクション

    private var eduRankingSection: some View {
        let entries = weeklyEduRanking
        return VStack(spacing: 0) {
            // セクションヘッダー
            HStack {
                Text("🏆 今週のEDUランキング")
                    .font(.system(size: 13 * UIScale.font, weight: .black))
                    .foregroundColor(Color.duoDark)
                Spacer()
                Text("週間 EDU pt")
                    .font(.system(size: 9 * UIScale.font, weight: .bold))
                    .foregroundColor(Color(hex: "#58CC02"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [Color(hex: "#58CC02").opacity(0.08), Color(hex: "#1CB0F6").opacity(0.08)],
                    startPoint: .leading, endPoint: .trailing
                )
            )

            if entries.isEmpty {
                VStack(spacing: 10) {
                    Text("📚").font(.system(size: 32 * UIScale.font))
                    Text("今週の投稿はまだありません")
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                }
                .frame(maxWidth: .infinity).padding(24)
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                    VStack(spacing: 0) {
                        // ── メイン行 ──
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                expandedRankId = (expandedRankId == entry.id) ? nil : entry.id
                            }
                        } label: {
                            HStack(spacing: 8) {
                                // アバター＋順位バッジ
                                ZStack(alignment: .bottomTrailing) {
                                    EduUserAvatar(photoURL: entry.photoURL,
                                                  name: String(entry.username.prefix(1)),
                                                  size: 30)
                                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                                    Circle()
                                        .fill(eduRankBadgeColor(entry.rank))
                                        .frame(width: 14, height: 14)
                                        .overlay(
                                            Text(entry.rank <= 3 ? eduRankEmoji(entry.rank) : "\(entry.rank)")
                                                .font(.system(size: entry.rank <= 3 ? 8 : 7, weight: .black))
                                                .foregroundColor(.white)
                                        )
                                        .offset(x: 2, y: 2)
                                }
                                .frame(width: 36)

                                // 名前 + YOU バッジ + 🔥連続
                                HStack(spacing: 4) {
                                    Text(String(entry.username.split(separator: " ").first ?? Substring(entry.username)))
                                        .font(.system(size: 13 * UIScale.font, weight: .bold))
                                        .foregroundColor(Color.duoDark)
                                        .lineLimit(1)
                                    if entry.isMe {
                                        Text("YOU")
                                            .font(.system(size: 7 * UIScale.font, weight: .black))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 4).padding(.vertical, 2)
                                            .background(Color(hex: "#58CC02"))
                                            .cornerRadius(4)
                                    }
                                    if entry.streak > 0 {
                                        HStack(spacing: 2) {
                                            Text("🔥")
                                                .font(.system(size: 10 * UIScale.font))
                                            Text("\(entry.streak)日")
                                                .font(.system(size: 10 * UIScale.font, weight: .bold))
                                                .foregroundColor(.orange)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                // EDU pt + 展開矢印
                                HStack(spacing: 4) {
                                    Text("\(entry.weeklyTotalPt)pt")
                                        .font(.system(size: 12 * UIScale.font, weight: .black))
                                        .foregroundColor(Color(hex: "#58CC02"))
                                        .minimumScaleFactor(0.7)
                                    Image(systemName: expandedRankId == entry.id ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(Color.duoSubtitle)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(entry.isMe
                            ? LinearGradient(
                                colors: [Color(hex: "#58CC02").opacity(0.06), Color(hex: "#58CC02").opacity(0.02)],
                                startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [Color.clear], startPoint: .leading, endPoint: .trailing)
                        )

                        // ── 展開詳細（日別内訳）──
                        if expandedRankId == entry.id {
                            eduRankDetail(for: entry)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        if idx < entries.count - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.07), radius: 8, y: 2)
    }

    /// 指定ユーザーの今週のカテゴリ別・日付別EDU pt内訳
    private func eduRankDetail(for entry: EduRankEntry) -> some View {
        let cal = Calendar.current
        let monday = thisMonday()
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let daysSinceMon = weekday == 1 ? 6 : weekday - 2

        // entry.id が UID なので、id プレフィックスで確実にマッチ（名前一致より正確）
        let userPosts: [EduLogHistoryItem]
        if entry.isMe {
            userPosts = myOwnPosts.filter { isEduItem($0) && $0.timestamp >= monday }
        } else {
            let fid = entry.id
            userPosts = manager.friendFeedItems.filter {
                $0.id.hasPrefix("friend_\(fid)_") && isEduItem($0) && $0.timestamp >= monday
            }
        }

        let catEmojis: [String: String] = [
            "Duolingo": "🦉", "読書": "📖", "勉強": "✏️", "語学": "🌍", "その他": "📝"
        ]

        // 月〜今日まで（新しい順）
        let days: [Date] = (0...daysSinceMon).compactMap {
            cal.date(byAdding: .day, value: $0, to: monday)
        }.reversed()

        // body 評価毎の DateFormatter 生成を避けるため static を参照
        let dayFmt = Self.rankDayFormatter

        let ptWidth: CGFloat = 52

        return VStack(spacing: 0) {
            Divider().padding(.leading, 12)

            // ヘッダー
            HStack {
                Text("日付")
                    .font(.system(size: 9 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoSubtitle)
                Spacer()
                Text("カテゴリ")
                    .font(.system(size: 9 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoSubtitle)
                Text("EDU pt")
                    .font(.system(size: 9 * UIScale.font, weight: .bold))
                    .foregroundColor(Color(hex: "#58CC02"))
                    .frame(width: ptWidth, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .background(Color(hex: "#58CC02").opacity(0.06))

            if userPosts.isEmpty {
                Text("今週の投稿なし")
                    .font(.system(size: 11 * UIScale.font))
                    .foregroundColor(Color.duoSubtitle)
                    .padding(.vertical, 10)
            } else {
                ForEach(days, id: \.self) { day in
                    let dayPosts = userPosts.filter { cal.isDate($0.timestamp, inSameDayAs: day) }
                    let count = dayPosts.count
                    let isToday = cal.isDateInToday(day)
                    // 再生ポイントは現状「自分」のみ日別データを保持（フレンドは日別内訳未取得のため 0）
                    let playPt = entry.isMe ? (myPlayPointsByDay[Self.dayKeyFormatter.string(from: day)] ?? 0) : 0

                    // その日に投稿されたカテゴリ絵文字（重複除去・順序保持）
                    let seenCats = dayPosts.reduce(into: [String]()) { acc, p in
                        let k = catKey(p)
                        if !acc.contains(k) { acc.append(k) }
                    }
                    let catLine = seenCats.compactMap { catEmojis[$0] }.joined(separator: " ")

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(dayFmt.string(from: day))
                                .font(.system(size: 11 * UIScale.font,
                                              weight: isToday ? .bold : .regular))
                                .foregroundColor(isToday ? Color(hex: "#58CC02") : Color.duoDark)
                                .frame(width: 64, alignment: .leading)
                            Spacer()
                            Text(count > 0 ? catLine : "—")
                                .font(.system(size: 12 * UIScale.font))
                                .foregroundColor(count > 0 ? Color.duoDark : Color.duoSubtitle)
                            Text(count > 0 ? "+\(count * 10)pt" : "—")
                                .font(.system(size: 11 * UIScale.font, weight: .bold))
                                .foregroundColor(count > 0 ? Color(hex: "#58CC02") : Color.duoSubtitle)
                                .frame(width: ptWidth, alignment: .trailing)
                        }
                        if playPt > 0 {
                            HStack(spacing: 3) {
                                Spacer()
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 8))
                                Text("+\(playPt)pt 再生")
                                    .font(.system(size: 9 * UIScale.font, weight: .semibold))
                            }
                            .foregroundColor(Color(hex: "#1CB0F6"))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 5)
                    .background(isToday ? Color(hex: "#58CC02").opacity(0.04) : Color.clear)
                }
            }

            // 合計行
            VStack(alignment: .trailing, spacing: 2) {
                HStack {
                    Text("今週合計")
                        .font(.system(size: 11 * UIScale.font, weight: .black))
                        .foregroundColor(Color.duoDark)
                    Spacer()
                    Text("\(userPosts.count)件")
                        .font(.system(size: 11 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoDark)
                    Text("+\(userPosts.count * 10)pt")
                        .font(.system(size: 12 * UIScale.font, weight: .black))
                        .foregroundColor(Color(hex: "#58CC02"))
                        .frame(width: ptWidth, alignment: .trailing)
                }
                if entry.weeklyPlayPoints > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 9))
                        Text("+\(entry.weeklyPlayPoints)pt 再生")
                            .font(.system(size: 10 * UIScale.font, weight: .bold))
                    }
                    .foregroundColor(Color(hex: "#1CB0F6"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(Color(hex: "#58CC02").opacity(0.08))
        }
    }

    // MARK: - 友達追加 結果ビュー

    @ViewBuilder
    private var eduAddResultView: some View {
        switch manager.addResult {
        case .idle:
            EmptyView()

        case .searching:
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.85)
                Text("検索中...").font(.subheadline).foregroundColor(Color.duoSubtitle)
            }

        case .notFound(let email):
            VStack(alignment: .leading, spacing: 10) {
                Label("このメールアドレスのユーザーはまだ登録していません", systemImage: "person.fill.questionmark")
                    .font(.subheadline).foregroundColor(Color.duoSubtitle)
                Button {
                    shareText = "【Edulingo 招待】\n\n一緒に語学・読書を楽しみませんか？\nEdulingoアプリをダウンロードして友達になりましょう！"
                    showShareSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text("招待を送る")
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color(hex: "#58CC02"))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                Text("招待されたメール: \(email)")
                    .font(.caption).foregroundColor(Color.duoSubtitle)
            }
            .padding(14)
            .background(Color.orange.opacity(0.08))
            .cornerRadius(12)

        case .added(let tomo):
            VStack(alignment: .leading, spacing: 10) {
                Label("友達に追加しました！", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.bold()).foregroundColor(Color(hex: "#58CC02"))
                HStack(spacing: 12) {
                    EduUserAvatar(photoURL: tomo.photoURL, name: String(tomo.username.prefix(1)), size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tomo.username)
                            .font(.system(size: 15, weight: .black))
                            .foregroundColor(Color.duoDark)
                            .lineLimit(1)
                        HStack(spacing: 10) {
                            Label("\(tomo.weeklyPoints)pt", systemImage: "bolt.fill")
                                .font(.caption.bold()).foregroundColor(Color(hex: "#1CB5E0"))
                            Label("\(tomo.streak)日", systemImage: "flame.fill")
                                .font(.caption.bold()).foregroundColor(.orange)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Color(hex: "#58CC02").opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#58CC02").opacity(0.3), lineWidth: 1))
                .cornerRadius(12)

                Text("フィードとランキングに反映されました")
                    .font(.caption).foregroundColor(Color.duoSubtitle)

                Button {
                    showInviteSheet = false
                    emailInput = ""
                } label: {
                    Text("閉じる")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(hex: "#1CB5E0"))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Color(hex: "#58CC02").opacity(0.06))
            .cornerRadius(12)

        case .alreadyAdded:
            Label("すでに友達です", systemImage: "info.circle.fill")
                .font(.subheadline).foregroundColor(.orange)

        case .selfAdd:
            Label("自分自身は追加できません", systemImage: "xmark.circle.fill")
                .font(.subheadline).foregroundColor(.red)

        case .error(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .font(.subheadline).foregroundColor(.red)
        }
    }

    private func eduRankEmoji(_ rank: Int) -> String {
        switch rank {
        case 1: return "🥇"; case 2: return "🥈"; case 3: return "🥉"
        default: return "\(rank)"
        }
    }

    private func eduRankBadgeColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(hex: "#FFD700")
        case 2: return Color(hex: "#90A4AE")
        case 3: return Color(hex: "#CD7F32")
        default: return Color(hex: "#58CC02").opacity(0.7)
        }
    }

    /// 言語コードに対応したバッジ背景色（LanguageUtils.swift の共通関数を使用）
    private func eduLangBadgeColor(_ code: String) -> Color { languageBadgeColor(code) }

    // MARK: - カテゴリーフィルターバー

    private var categoryFilterBar: some View {
        VStack(spacing: 0) {
            // カテゴリ行
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryChip(label: "すべて", emoji: "🗂", isSelected: selectedCategory == nil) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCategory = nil
                            selectedLanguage = nil
                        }
                    }
                    ForEach(availableCategories, id: \.key) { cat in
                        categoryChip(label: cat.key, emoji: cat.emoji,
                                     isSelected: selectedCategory == cat.key) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if selectedCategory == cat.key {
                                    selectedCategory = nil
                                } else {
                                    selectedCategory = cat.key
                                    selectedLanguage = nil
                                }
                            }
                        }
                    }

                    // ── お気に入りチップ（カテゴリ行の末尾）────────────────────
                    let hasFav = EduLogManager.shared.history.contains { $0.isFavorite }
                    if hasFav || showFavoritesOnly {
                        categoryChip(
                            label: "お気に入り",
                            emoji: showFavoritesOnly ? "❤️" : "🤍",
                            isSelected: showFavoritesOnly
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showFavoritesOnly.toggle()
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }

            Divider()

            // ソート + 言語フィルター行
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // ソート Picker
                    Menu {
                        ForEach(SortOrder.allCases) { order in
                            Button {
                                withAnimation { sortOrder = order }
                            } label: {
                                HStack {
                                    Text(order.rawValue)
                                    if sortOrder == order {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 10 * UIScale.font, weight: .semibold))
                            Text(sortOrder.rawValue)
                                .font(.system(size: 11 * UIScale.font, weight: .semibold))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color(hex: "#1CB0F6").opacity(0.15))
                        .foregroundColor(Color(hex: "#1CB0F6"))
                        .cornerRadius(12)
                    }

                    // 言語フィルター（投稿に含まれる場合のみ表示）
                    if !availableLanguages.isEmpty {
                        Divider().frame(height: 20)
                        ForEach(availableLanguages, id: \.code) { lang in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedLanguage = (selectedLanguage == lang.code) ? nil : lang.code
                                }
                            } label: {
                                Text(lang.label)
                                    .font(.system(size: 11 * UIScale.font, weight: .semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(selectedLanguage == lang.code
                                        ? Color(hex: "#CE82FF")
                                        : Color(.systemGray6))
                                    .foregroundColor(selectedLanguage == lang.code
                                        ? .white : Color.duoDark)
                                    .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
            }

            // ── 言語選択中の順次再生バー ──────────────────────────────
            if let lang = selectedLanguage {
                languagePlayBar(for: lang)
            }

            Divider()
        }
        .background(Color(.systemBackground))
    }

    /// 言語選択時にフィルター済みフレーズを順次再生するバー
    private func languagePlayBar(for langCode: String) -> some View {
        let phrases = cachedEduItems
            .filter { ($0.extractedLanguageCode ?? "").hasPrefix(langCode) }
            .compactMap { $0.extractedPhrase?.isEmpty == false ? $0.extractedPhrase : nil }

        let isPlaying = ttsEngine.isSequencePlaying
        let cur = ttsEngine.sequenceCurrent + 1
        let tot = ttsEngine.sequenceTotal

        return HStack(spacing: 10) {
            // 言語フラグ
            Text(languageFlag(langCode))
                .font(.system(size: 16))

            // 再生状態テキスト
            if isPlaying {
                Text("\(cur) / \(tot)フレーズ再生中")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#CE82FF"))
            } else {
                Text("\(phrases.count)フレーズ")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.duoSubtitle)
            }

            Spacer()

            // 再生 / 停止ボタン
            Button {
                if isPlaying {
                    ttsEngine.stopSequence()
                } else {
                    let queue = phrases.map { (phrase: $0, langCode: langCode) }
                    ttsEngine.speakSequence(queue)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 12))
                    Text(isPlaying ? "停止" : "全て再生")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isPlaying ? Color.red : Color(hex: "#CE82FF"))
                .cornerRadius(14)
            }
            .buttonStyle(.plain)
            .disabled(phrases.isEmpty && !isPlaying)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(hex: "#CE82FF").opacity(0.07))
    }

    private func categoryChip(label: String, emoji: String, isSelected: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(emoji).font(.system(size: 11 * UIScale.font))
                Text(label).font(.system(size: 11 * UIScale.font, weight: .semibold))
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(isSelected ? Color(hex: "#58CC02") : Color(.systemGray6))
            .foregroundColor(isSelected ? .white : Color.duoDark)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - フィードセクション

    private var feedSection: some View {
        LazyVStack(spacing: 0) {
            if (manager.isLoading || isLoadingMyPosts) && allEduItems.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("読み込み中...").font(.caption).foregroundColor(Color.duoSubtitle)
                }
                .frame(maxWidth: .infinity).padding(40)
                .background(Color(.systemBackground))
            } else if allEduItems.isEmpty {
                emptyState
            } else {
                ForEach(feedDays) { day in
                    // 日付ラベル
                    HStack {
                        Text(day.id)
                            .font(.system(size: 11 * UIScale.font, weight: .black))
                            .foregroundColor(Color.duoSubtitle)
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color(UIColor.systemGroupedBackground))

                    ForEach(day.items) { item in
                        postCard(item)
                        Divider()
                    }
                }

                // 1週間より古い投稿の「さらに表示」ボタン
                if !showOlderFeed && hasOlderFeed {
                    Button {
                        Task {
                            showOlderFeed = true
                            // 友達の古い投稿がまだロードされていなければ取得
                            if manager.hasOlderPosts {
                                await manager.loadOlderPosts()
                            }
                            rebuildEduCache()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if manager.isLoadingOlderPosts {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 11 * UIScale.font, weight: .semibold))
                            }
                            Text("さらに表示（1週間以前）")
                                .font(.system(size: 12 * UIScale.font, weight: .bold))
                        }
                        .foregroundColor(Color.duoBlue)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemBackground))
                    }
                    .buttonStyle(.plain)
                    .disabled(manager.isLoadingOlderPosts)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image("kedu_icon")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            Text("まだ投稿がありません")
                .font(.system(size: 16 * UIScale.font, weight: .bold))
                .foregroundColor(Color.duoDark)
            Text("Duolingo・読書・勉強・語学を記録すると\nここに自動投稿されます")
                .font(.system(size: 13 * UIScale.font))
                .foregroundColor(Color.duoSubtitle)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 48)
        .background(Color(.systemBackground))
    }

    // MARK: - 投稿カード

    /// ローカル履歴で isFavorite かどうかを確認（"own_" プレフィックス対応）
    private func isFavoriteItem(_ item: EduLogHistoryItem) -> Bool {
        if item.isFavorite { return true }
        let baseId = item.id.hasPrefix("own_") ? String(item.id.dropFirst(4)) : item.id
        return EduLogManager.shared.history.first(where: { $0.id == baseId || $0.id == item.id })?.isFavorite == true
    }

    private func postCard(_ item: EduLogHistoryItem) -> some View {
        let isDuo      = catKey(item) == "Duolingo"
        let langCode   = item.extractedLanguageCode ?? ""
        let phrase     = item.extractedPhrase ?? ""
        let isSpeaking = speakingCardId == item.id
        let isFav      = isFavoriteItem(item)

        return VStack(alignment: .leading, spacing: 0) {
            // ── ヘッダー（アバター・名前・言語バッジ・再生ボタン・カテゴリ・メニュー）──────────
            HStack(spacing: 6) {
                // 左アバター（タップでメニュー＆ポイントサマリー）
                Button { showHamburgerMenu = true } label: {
                    EduUserAvatar(
                        photoURL: item.authorPhotoURL.isEmpty
                            ? (UserDefaults.standard.string(forKey: "cachedCurrentUserPhotoURL") ?? "")
                            : item.authorPhotoURL,
                        name: item.authorFirstName,
                        size: 24
                    )
                }
                .buttonStyle(.plain)

                Text(isOwnPost(item) ? "YOU" : item.authorFirstName)
                    .font(.system(size: 11 * UIScale.font, weight: .black))
                    .foregroundColor(isOwnPost(item) ? Color(hex: "#58CC02") : Color.duoDark)
                    .lineLimit(1)

                // 言語バッジ + 再生ボタン（Duolingo 投稿のみ・名前の右）
                if isDuo && !langCode.isEmpty {
                    HStack(spacing: 4) {
                        HStack(spacing: 3) {
                            Text(languageFlag(langCode))
                                .font(.system(size: 11 * UIScale.font))
                            Text(languageLabel(langCode))
                                .font(.system(size: 9 * UIScale.font, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(eduLangBadgeColor(langCode))
                        .clipShape(Capsule())

                        if !phrase.isEmpty {
                            Button {
                                if isSpeaking {
                                    DuolingoTextExtractor.shared.stopSpeaking()
                                    speakingCardId = nil
                                } else {
                                    ttsEngine.stopSequence()
                                    speakingCardId = item.id
                                    var queue: [(phrase: String, langCode: String)] = [(phrase, langCode)]
                                    if let exs = item.exampleSentences {
                                        queue += exs.map { ($0.text, langCode) }
                                    }
                                    ttsEngine.speakSequence(queue) {
                                        DispatchQueue.main.async { speakingCardId = nil }
                                    }
                                    // 再生 = ハート +1 & 自分に 10pt
                                    recordPlay(item: item)
                                }
                            } label: {
                                Image(systemName: isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(isSpeaking ? .red : Color(hex: "#1CB0F6"))
                                    .frame(width: 26, height: 22)
                                    .background((isSpeaking ? Color.red : Color(hex: "#1CB0F6")).opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)

                            // ハートカウント（再生回数）
                            let likeCount = playLikeCounts[item.id] ?? item.likeCount
                            if likeCount > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "heart.fill")
                                        .font(.system(size: 9))
                                        .foregroundColor(Color(hex: "#FF4B4B"))
                                    Text("\(likeCount)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(Color(hex: "#FF4B4B"))
                                }
                            }
                        }
                    }
                }

                Spacer()
                Button {
                    let cat = catKey(item)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedCategory = (selectedCategory == cat) ? nil : cat
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(catEmoji(item)).font(.system(size: 11 * UIScale.font))
                        Text(catKey(item))
                            .font(.system(size: 9 * UIScale.font, weight: .semibold))
                            .foregroundColor(selectedCategory == catKey(item) ? .white : Color.duoSubtitle)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(selectedCategory == catKey(item) ? Color(hex: "#58CC02") : Color(.systemGray6))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                Menu {
                    if isOwnPost(item) {
                        Button(role: .destructive) { deleteConfirmItem = item } label: {
                            Label("削除", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color.duoSubtitle)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // ── メインコンテンツ ─────────────────────────────────
            let isReading = (catKey(item) == "読書" || catKey(item) == "勉強")
            let hasLink   = item.sharedUrl != nil

            if isReading && hasLink {
                // 読書・勉強：フルワイドのブックカード表示
                readingBookCard(item: item)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .contentShape(Rectangle())
                    .onTapGesture { openDetail(item) }
            } else {
                HStack(alignment: .top, spacing: 10) {

                    // 左：小さいサムネイル（写真があれば）
                    if let img = item.thumbnail {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(width: 76, height: 76)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .onTapGesture { openDetail(item) }
                    }

                    // 右：フレーズ + 訳 + 例文
                    VStack(alignment: .leading, spacing: 4) {

                        // フレーズ（外国語）
                        if isDuo && !phrase.isEmpty {
                            Text(phrase)
                                .font(.system(size: 14 * UIScale.font, weight: .bold))
                                .foregroundColor(Color.duoDark)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        // 日本語訳
                        if let tja = item.translationJA, !tja.isEmpty {
                            Text(tja)
                                .font(.system(size: 11 * UIScale.font))
                                .foregroundColor(Color.duoSubtitle)
                                .lineLimit(2)
                        }

                        // 例文（最大2件）
                        if isDuo, let exs = item.exampleSentences, !exs.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(Array(exs.prefix(2).enumerated()), id: \.offset) { _, ex in
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(ex.text)
                                            .font(.system(size: 11 * UIScale.font, weight: .semibold))
                                            .foregroundColor(Color.duoDark)
                                            .lineLimit(2)
                                        if let ja = ex.translationJA, !ja.isEmpty {
                                            Text(ja)
                                                .font(.system(size: 10 * UIScale.font))
                                                .foregroundColor(Color.duoSubtitle)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                            .padding(7)
                            .background(Color(hex: "#58CC02").opacity(0.06))
                            .cornerRadius(8)
                        }

                        // コメント（Duolingo 以外 or フレーズがない場合）
                        if !item.comment.isEmpty && !(isDuo && !phrase.isEmpty) {
                            Text(item.comment)
                                .font(.system(size: 12 * UIScale.font))
                                .foregroundColor(Color.duoDark)
                                .lineLimit(3)
                        }

                        // 共有リンク（その他カテゴリでリンクがある場合）
                        if let urlStr = item.sharedUrl, let url = URL(string: urlStr) {
                            let host = url.host ?? urlStr
                            let fetched = linkFetcher.meta(for: urlStr)
                            Button { UIApplication.shared.open(url) } label: {
                                HStack(spacing: 8) {
                                    if let img = fetched?.thumbnailImage {
                                        Image(uiImage: img)
                                            .resizable().scaledToFill()
                                            .frame(width: 36, height: 36)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    } else {
                                        Image(systemName: "link")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.white)
                                            .frame(width: 36, height: 36)
                                            .background(Color(hex: "#1CB0F6"))
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        let titleStr = (fetched?.title ?? item.sharedTitle ?? "").trimmingCharacters(in: .whitespaces)
                                        if !titleStr.isEmpty {
                                            Text(titleStr)
                                                .font(.system(size: 11 * UIScale.font, weight: .bold))
                                                .foregroundColor(Color.duoDark)
                                                .lineLimit(1)
                                        }
                                        Text(host)
                                            .font(.system(size: 9 * UIScale.font))
                                            .foregroundColor(Color(hex: "#1CB0F6"))
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 10))
                                        .foregroundColor(Color.duoSubtitle)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(Color(hex: "#1CB0F6").opacity(0.07))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .contentShape(Rectangle())
                .onTapGesture { openDetail(item) }
            }
        }
        .background(Color(.systemBackground))
        .task(id: item.sharedUrl) {
            if let urlStr = item.sharedUrl {
                linkFetcher.prefetch(urlString: urlStr)
            }
        }
    }

    // MARK: - 読書・勉強投稿用ブックカード（一覧）

    @ViewBuilder
    private func readingBookCard(item: EduLogHistoryItem) -> some View {
        let urlStr  = item.sharedUrl ?? ""
        let url     = URL(string: urlStr)
        let fetched = linkFetcher.meta(for: urlStr)
        let title   = (fetched?.title ?? item.sharedTitle ?? "").trimmingCharacters(in: .whitespaces)
        let desc    = (fetched?.description ?? item.sharedDescription ?? "").trimmingCharacters(in: .whitespaces)
        let host    = url?.host ?? urlStr
        let coverImg: UIImage? = fetched?.thumbnailImage

        Button {
            if let u = url { UIApplication.shared.open(u) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    // 表紙画像 or アイコン
                    if let img = coverImg {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(width: 64, height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    } else {
                        ZStack {
                            LinearGradient(
                                colors: [Color(hex: "#1CB0F6"), Color(hex: "#0A7AC7")],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                            Image(systemName: catKey(item) == "読書" ? "book.closed.fill" : "pencil.and.list.clipboard")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .frame(width: 64, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: Color(hex: "#1CB0F6").opacity(0.3), radius: 4, y: 2)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        // タイトル
                        if !title.isEmpty {
                            Text(title)
                                .font(.system(size: 13 * UIScale.font, weight: .bold))
                                .foregroundColor(Color.duoDark)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        // 説明
                        if !desc.isEmpty {
                            Text(desc)
                                .font(.system(size: 11 * UIScale.font))
                                .foregroundColor(Color.duoSubtitle)
                                .lineLimit(3)
                        }
                        // コメント
                        if !item.comment.isEmpty {
                            Text(item.comment)
                                .font(.system(size: 11 * UIScale.font))
                                .foregroundColor(Color.duoDark.opacity(0.75))
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        // ホスト
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.system(size: 9))
                            Text(host)
                                .font(.system(size: 9 * UIScale.font, weight: .medium))
                        }
                        .foregroundColor(Color(hex: "#1CB0F6"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 13 * UIScale.font))
                        .foregroundColor(Color(hex: "#1CB0F6").opacity(0.5))
                }
                .padding(12)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "#1CB0F6").opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color(hex: "#1CB0F6").opacity(0.18), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 詳細を開く

    private func openDetail(_ item: EduLogHistoryItem) {
        let sibling = allEduItems.filter {
            $0.authorName == item.authorName &&
            catKey($0) == catKey(item)
        }
        let items: [EduLogHistoryItem]
        let startIndex: Int
        if sibling.count > 1, let idx = sibling.firstIndex(where: { $0.id == item.id }) {
            items = sibling
            startIndex = idx
        } else {
            items = [item]
            startIndex = 0
        }
        // items と表示を同時にセット → 初回から空白にならない
        detailRequest = DetailRequest(items: items, startIndex: startIndex)
    }
}

// MARK: - EdulingoRecordSheet
// DashboardView.swift の EduPhotoLogSheet をベースにした kedu 専用バージョン

struct EdulingoRecordSheet: View {
    let nodeEmoji: String
    let nodeName: String
    let onComplete: (Bool, Bool, UIImage?, String) -> Void

    @State private var selectedImage: UIImage? = nil
    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var comment: String = ""
    @State private var saveToFeed: Bool = true
    @State private var isPublic: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(nodeEmoji).font(.system(size: 44 * UIScale.font))
                Text(nodeName).font(.title3).fontWeight(.black).foregroundColor(Color.duoDark)
            }
            .padding(.top, 20).padding(.bottom, 14)

            Divider()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    // 写真選択
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        if let image = selectedImage {
                            Image(uiImage: image)
                                .resizable().scaledToFill()
                                .frame(maxWidth: .infinity).frame(height: 160)
                                .cornerRadius(12).clipped()
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6))
                                .frame(maxWidth: .infinity).frame(height: 90)
                                .overlay {
                                    VStack(spacing: 6) {
                                        Image(systemName: "camera.fill")
                                            .font(.title2).foregroundColor(Color.duoBlue)
                                        Text("写真を選択（任意）")
                                            .font(.caption).foregroundColor(Color.duoBlue)
                                    }
                                }
                        }
                    }
                    .onChange(of: pickerItem) { _, item in
                        Task {
                            if let data = try? await item?.loadTransferable(type: Data.self),
                               let img = UIImage(data: data) {
                                selectedImage = img
                            }
                        }
                    }

                    // コメント入力
                    TextField("タイトル・メモ（本のタイトル・学んだこと等）", text: $comment)
                        .font(.body)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .submitLabel(.done)
                        .onSubmit {
                            UIApplication.shared.sendAction(
                                #selector(UIResponder.resignFirstResponder),
                                to: nil, from: nil, for: nil
                            )
                        }

                    // フィードに追加
                    Toggle(isOn: Binding(
                        get: { saveToFeed },
                        set: { v in saveToFeed = v; isPublic = v }
                    )) {
                        HStack(spacing: 6) {
                            Image(systemName: saveToFeed ? "rectangle.stack.fill" : "rectangle.stack")
                                .foregroundColor(saveToFeed ? Color(hex: "#58CC02") : Color.duoSubtitle)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("フィードに追加")
                                    .font(.subheadline).fontWeight(.semibold)
                                Text(saveToFeed ? "Edulingoフィードに公開" : "フィードには追加しない")
                                    .font(.caption).foregroundColor(Color.duoSubtitle)
                            }
                        }
                    }
                    .tint(Color(hex: "#58CC02"))

                    // 記録ボタン
                    Button {
                        onComplete(saveToFeed, isPublic, selectedImage, comment)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill").font(.title3)
                            Text("記録する").font(.headline).fontWeight(.black)
                            Spacer()
                        }
                        .foregroundColor(Color(hex: "#58CC02"))
                        .padding(.horizontal, 20).padding(.vertical, 14)
                        .background(Color(hex: "#58CC02").opacity(0.1))
                        .cornerRadius(14)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
            }
        }
    }
}

// MARK: - KeduMenuSheet（ハンバーガーメニュー）

struct KeduMenuSheet: View {
    @EnvironmentObject private var auth: AuthenticationManager
    @Binding var showInviteSheet: Bool
    var todayPoints: Int = 0
    var weekPoints: Int = 0
    var totalPoints: Int = 0
    @Environment(\.dismiss) private var dismiss
    @AppStorage("keduColorScheme") private var colorSchemePref: String = "auto"

    private struct AppearanceOption: Identifiable {
        let id: String
        let label: String
        let icon: String
    }
    private let appearanceOptions: [AppearanceOption] = [
        .init(id: "auto",  label: "自動",   icon: "circle.lefthalf.filled"),
        .init(id: "light", label: "ライト", icon: "sun.max"),
        .init(id: "dark",  label: "ダーク", icon: "moon.fill"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // アカウント情報
                    HStack(spacing: 12) {
                        EduUserAvatar(
                            photoURL: Auth.auth().currentUser?.photoURL?.absoluteString ?? "",
                            name: auth.userProfile?.username ?? "",
                            size: 48
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(auth.userProfile?.username ?? "ユーザー")
                                .font(.headline)
                            Text(Auth.auth().currentUser?.email ?? "")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // ── EDU ポイントサマリー ──────────────────────────────────────
                Section(header: Label("EDU ポイント", systemImage: "star.fill").foregroundColor(Color(hex: "#FFD700"))) {
                    HStack {
                        pointCell(icon: "sun.max.fill",            color: Color(hex: "#FF9500"), label: "今日",  pt: todayPoints)
                        Divider()
                        pointCell(icon: "calendar.badge.clock",    color: Color(hex: "#1CB0F6"), label: "今週",  pt: weekPoints)
                        Divider()
                        pointCell(icon: "star.fill",               color: Color(hex: "#FFD700"), label: "累計",  pt: totalPoints)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }

                Section("Edulingo") {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showInviteSheet = true
                        }
                    } label: {
                        Label("友達を招待", systemImage: "person.badge.plus")
                    }
                    .tint(.primary)
                }

                // 表示モード選択
                Section("表示モード") {
                    HStack(spacing: 0) {
                        ForEach(appearanceOptions) { option in
                            let isSelected = colorSchemePref == option.id
                            Button {
                                colorSchemePref = option.id
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: option.icon)
                                        .font(.system(size: 18, weight: .medium))
                                    Text(option.label)
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(isSelected ? .white : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(isSelected ? Color.accentColor : Color(.systemGray5))
                            }
                            .buttonStyle(.plain)
                            if option.id != "dark" {
                                Divider()
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section {
                    Button(role: .destructive) {
                        auth.signOut()
                        dismiss()
                    } label: {
                        Label("ログアウト", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("メニュー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func pointCell(icon: String, color: Color, label: String, pt: Int) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(color)
            Text("\(pt)")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
            Text("pt")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - ShareSheet

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - EduPointsSummarySheet

struct EduPointsSummarySheet: View {
    let todayPoints: Int
    let weekPoints: Int
    let totalPoints: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // ヘッダー
                VStack(spacing: 4) {
                    Text("🏆").font(.system(size: 44))
                    Text("EDU ポイント")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "#58CC02"))
                    Text("投稿×10pt ＋ 再生×10pt で獲得")
                        .font(.system(size: 12))
                        .foregroundColor(Color.gray)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "#58CC02").opacity(0.08), Color(hex: "#1CB0F6").opacity(0.05)],
                        startPoint: .top, endPoint: .bottom
                    )
                )

                // ポイント3段表示
                VStack(spacing: 12) {
                    pointRow(icon: "sun.max.fill",    color: Color(hex: "#FF9500"), label: "今日",   pt: todayPoints)
                    Divider().padding(.horizontal, 16)
                    pointRow(icon: "calendar.badge.clock", color: Color(hex: "#1CB0F6"), label: "今週", pt: weekPoints)
                    Divider().padding(.horizontal, 16)
                    pointRow(icon: "star.fill",       color: Color(hex: "#FFD700"), label: "累計",   pt: totalPoints)
                }
                .padding(.vertical, 20)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .padding(16)

                Spacer()

                // ヒント
                Text("💡 再生するたびに EDU ポイントが増え\n週間ランキングにも加算されます")
                    .font(.system(size: 12))
                    .foregroundColor(Color.gray)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                        .fontWeight(.bold)
                        .foregroundColor(Color(hex: "#58CC02"))
                }
            }
        }
    }

    private func pointRow(icon: String, color: Color, label: String, pt: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(color)
                .frame(width: 36)
            Text(label)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Color(.label))
            Spacer()
            Text("\(pt) pt")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundColor(color)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - EduRankEntry

struct EduRankEntry: Identifiable {
    let id: String          // uid（Firebase UID）
    let username: String
    let photoURL: String
    let weeklyPostCount: Int
    var weeklyPlayPoints: Int = 0   // 今週の再生ポイント
    let isMe: Bool
    var rank: Int = 0
    var streak: Int = 0     // 連続投稿日数（1日1投稿以上）

    /// 合計週間 EDU pt（投稿 × 10pt ＋ 再生ポイント）
    var weeklyTotalPt: Int { weeklyPostCount * 10 + weeklyPlayPoints }

    init(uid: String, username: String, photoURL: String,
         weeklyPostCount: Int, weeklyPlayPoints: Int = 0, isMe: Bool, streak: Int = 0) {
        self.id = uid
        self.username = username
        self.photoURL = photoURL
        self.weeklyPostCount = weeklyPostCount
        self.weeklyPlayPoints = weeklyPlayPoints
        self.isMe = isMe
        self.streak = streak
    }
}

// MARK: - EduUserAvatar

struct EduUserAvatar: View {
    let photoURL: String
    let name: String
    let size: CGFloat

    private var initial: String {
        String(name.prefix(1)).uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color(hex: "#FFD900"), Color(hex: "#FF9600")],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))

            if !photoURL.isEmpty, let url = URL(string: photoURL) {
                // CachedAsyncImage で URLCache を活用し繰り返しダウンロードを防止
                CachedAsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                } placeholder: {
                    Text(initial)
                        .font(.system(size: size * 0.4, weight: .black))
                        .foregroundColor(.white)
                }
            } else {
                Text(initial)
                    .font(.system(size: size * 0.4, weight: .black))
                    .foregroundColor(.white)
            }
        }
    }
}
