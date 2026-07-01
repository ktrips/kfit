import SwiftUI
import PhotosUI
import FirebaseAuth

// MARK: - EdulingoView
// kedu アプリのメインビュー。Duolingo / 読書 / 勉強 / 語学 の投稿のみを表示する。
// TomoManager（TomoView.swift 内）と SwipeableTomoDetailSheet を再利用。

struct EdulingoView: View {

    @StateObject private var manager = TomoManager()
    @StateObject private var eduLogManager = EduLogManager.shared
    @EnvironmentObject private var photoLogManager: PhotoLogManager
    @EnvironmentObject private var auth: AuthenticationManager
    @EnvironmentObject private var plus: PlusManager

    // 詳細シート
    @State private var swipeDetailItems: [EduLogHistoryItem] = []
    @State private var swipeDetailStart: Int = 0
    @State private var showSwipeDetail = false

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

    // 削除確認
    @State private var deleteConfirmItem: EduLogHistoryItem? = nil

    // 友達招待
    @State private var showInviteSheet = false
    @State private var emailInput = ""

    // ハンバーガーメニュー
    @State private var showHamburgerMenu = false

    // Edulingo 専用クイックレコード（教育 4 種）
    private let eduQuickRecords: [TomoQuickRecord] = [
        TomoQuickRecord(id: "duolingo", label: "Duolingo", emoji: "🦉", color: Color(hex: "#58CC02"), isFood: false),
        TomoQuickRecord(id: "reading",  label: "読書",     emoji: "📖", color: Color(hex: "#1CB0F6"), isFood: false),
        TomoQuickRecord(id: "study",    label: "勉強",     emoji: "✏️", color: Color(hex: "#FF4B4B"), isFood: false),
        TomoQuickRecord(id: "language", label: "語学",     emoji: "🌍", color: Color(hex: "#CE82FF"), isFood: false),
    ]

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
        let myName = AuthenticationManager.shared.userProfile?.username
            ?? UserDefaults.standard.string(forKey: "cachedCurrentUserName")
            ?? ""
        return item.authorName == myName || item.authorName.isEmpty
    }

    // MARK: - フィルター済みフィードアイテム

    private var allEduItems: [EduLogHistoryItem] {
        var items = manager.friendFeedItems.filter { isEduItem($0) }

        // カテゴリフィルター
        if let cat = selectedCategory {
            items = items.filter { catKey($0) == cat }
        }

        // 言語フィルター（extractedLanguageCode）
        if let lang = selectedLanguage {
            items = items.filter { ($0.extractedLanguageCode ?? "").hasPrefix(lang) }
        }

        // ソート
        switch sortOrder {
        case .newest:   items.sort { $0.timestamp > $1.timestamp }
        case .oldest:   items.sort { $0.timestamp < $1.timestamp }
        case .category: items.sort {
            let a = catKey($0); let b = catKey($1)
            return a == b ? $0.timestamp > $1.timestamp : a < b
        }
        }
        return items
    }

    // 投稿に含まれる言語コードの一覧（Duolingo 投稿のみ）
    private var availableLanguages: [(code: String, label: String)] {
        let codes = Set(manager.friendFeedItems
            .filter { isEduItem($0) }
            .compactMap { $0.extractedLanguageCode?.prefix(2).description })
        return codes.sorted().map { code in
            let label: String
            switch code {
            case "en": label = "🇺🇸 英語"
            case "zh": label = "🇨🇳 中国語"
            case "fr": label = "🇫🇷 仏語"
            case "es": label = "🇪🇸 西語"
            case "de": label = "🇩🇪 独語"
            case "ko": label = "🇰🇷 韓国語"
            case "pt": label = "🇵🇹 葡語"
            case "it": label = "🇮🇹 伊語"
            default:   label = "🌐 \(code)"
            }
            return (code: code, label: label)
        }
    }

    private var hasOlderFeed: Bool { manager.hasOlderPosts }

    // MARK: - カテゴリーチップ一覧

    private var availableCategories: [(key: String, emoji: String)] {
        let all = allEduItems.map { (catKey($0), catEmoji($0)) }
        var seen = Set<String>()
        return all.compactMap { pair -> (key: String, emoji: String)? in
            guard !seen.contains(pair.0) else { return nil }
            seen.insert(pair.0)
            return (key: pair.0, emoji: pair.1)
        }
    }

    // MARK: - 日付グループ

    private struct FeedDay: Identifiable {
        let id: String   // 日付ラベル
        let items: [EduLogHistoryItem]
    }

    private var feedDays: [FeedDay] {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ja_JP")
        fmt.dateFormat = "yyyy年M月d日 (E)"
        var dict: [String: [EduLogHistoryItem]] = [:]
        var order: [String] = []
        for item in allEduItems {
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
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ja_JP")
        fmt.dateFormat = "M月d日"
        return fmt.string(from: date)
    }

    // MARK: - ボディ

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        quickRecordBar
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
                            .padding(.bottom, 12)

                        categoryFilterBar

                        feedSection

                        Spacer(minLength: 40)
                    }
                    .padding(.bottom, 20)
                }
                .refreshable { await manager.load(force: true) }
            }
            .navigationBarHidden(true)
            .safeAreaInset(edge: .top, spacing: 0) { edulingoHeader }
        }
        .task { await manager.load() }

        // 詳細シート
        .fullScreenCover(isPresented: $showSwipeDetail) {
            SwipeableTomoDetailSheet(
                items: swipeDetailItems,
                startIndex: swipeDetailStart,
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
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }

        // 友達招待シート
        .sheet(isPresented: $showInviteSheet) {
            NavigationStack {
                VStack(spacing: 20) {
                    Text("🦉 友達を招待").font(.title2).fontWeight(.black)
                    Text("友達のメールアドレスを入力してください")
                        .font(.subheadline).foregroundColor(Color.duoSubtitle)
                    TextField("メールアドレス", text: $emailInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    Button {
                        Task {
                            await manager.addTomo(email: emailInput)
                            emailInput = ""
                            showInviteSheet = false
                        }
                    } label: {
                        Text("招待する")
                            .font(.headline.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(hex: "#58CC02"))
                            .cornerRadius(12)
                    }
                    .disabled(emailInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    Spacer()
                }
                .padding(20)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("閉じる") { showInviteSheet = false }
                    }
                }
            }
        }

        // ハンバーガーメニューシート
        .sheet(isPresented: $showHamburgerMenu) {
            KeduMenuSheet(showInviteSheet: $showInviteSheet)
                .environmentObject(auth)
                .presentationDetents([.medium])
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
                // ユーザーアバター（タップでメニュー）
                Button { showHamburgerMenu = true } label: {
                    EduUserAvatar(
                        photoURL: Auth.auth().currentUser?.photoURL?.absoluteString ?? "",
                        name: auth.userProfile?.username ?? "",
                        size: 34
                    )
                }

                // ロゴ（中央）
                HStack(spacing: 0) {
                    Text("Edu")
                        .foregroundColor(Color(hex: "#FFD900"))
                        .font(.system(size: 16 * UIScale.font, weight: .black, design: .rounded))
                    Text("lingo")
                        .foregroundColor(.white)
                        .font(.system(size: 16 * UIScale.font, weight: .black, design: .rounded))
                }

                Spacer()

                // 記録メニュー
                Menu {
                    ForEach(eduQuickRecords) { rec in
                        Button {
                            eduRecordTarget = rec
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

                // 友達招待
                Button { showInviteSheet = true } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 16 * UIScale.font, weight: .semibold))
                        .foregroundColor(.white)
                }

                // ハンバーガーメニュー
                Button { showHamburgerMenu = true } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18 * UIScale.font, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16)
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

            Divider()
        }
        .background(Color(.systemBackground))
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
            if manager.isLoading && allEduItems.isEmpty {
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

                // 過去フィード
                if !showOlderFeed && hasOlderFeed {
                    Button {
                        Task {
                            showOlderFeed = true
                            await manager.loadOlderPosts()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if manager.isLoadingOlderPosts {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 11 * UIScale.font, weight: .semibold))
                            }
                            Text("過去の投稿を見る")
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
            ZStack {
                Circle()
                    .fill(Color(hex: "#58CC02").opacity(0.12))
                    .frame(width: 88, height: 88)
                Text("🦉")
                    .font(.system(size: 44 * UIScale.font))
            }
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

    private func postCard(_ item: EduLogHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // ヘッダー（アバター・名前・カテゴリタグ・メニュー）
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color(hex: "#58CC02"), Color(hex: "#1CB0F6")],
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
                    Text(displayName)
                        .font(.system(size: 11 * UIScale.font, weight: .black))
                        .foregroundColor(isOwnPost(item) ? Color(hex: "#58CC02") : Color.duoDark)
                    Text(relativeTimeString(item.timestamp))
                        .font(.system(size: 9 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)
                }
                Spacer()

                // カテゴリタグ
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

                // 三点メニュー
                Menu {
                    if isOwnPost(item) {
                        Button(role: .destructive) {
                            deleteConfirmItem = item
                        } label: {
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

            // 写真（あれば）
            if let img = item.thumbnail {
                GeometryReader { geo in
                    ZStack(alignment: .bottomLeading) {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.width * 0.55)
                            .clipped()
                        // コメントオーバーレイ
                        if !item.comment.isEmpty {
                            LinearGradient(
                                colors: [Color.black.opacity(0), Color.black.opacity(0.55)],
                                startPoint: .top, endPoint: .bottom
                            )
                            .frame(height: 60)

                            Text(item.comment)
                                .font(.system(size: 12 * UIScale.font, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12).padding(.bottom, 8)
                                .lineLimit(2)
                        }
                    }
                }
                .frame(height: UIScreen.main.bounds.width * 0.55)
                .contentShape(Rectangle())
                .onTapGesture { openDetail(item) }
            } else if !item.comment.isEmpty {
                // 写真なし・コメントあり
                Text(item.comment)
                    .font(.system(size: 13 * UIScale.font))
                    .foregroundColor(Color.duoDark)
                    .lineLimit(3)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .contentShape(Rectangle())
                    .onTapGesture { openDetail(item) }
            }

            // Duolingo 例文プレビュー
            if catKey(item) == "Duolingo",
               let ex = item.exampleSentences?.first {
                HStack(spacing: 6) {
                    Text("🦉")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ex.text)
                            .font(.system(size: 12 * UIScale.font, weight: .semibold))
                            .foregroundColor(Color.duoDark)
                            .lineLimit(1)
                        if let ja = ex.translationJA, !ja.isEmpty {
                            Text(ja)
                                .font(.system(size: 10 * UIScale.font))
                                .foregroundColor(Color.duoSubtitle)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }

            Spacer(minLength: 8)
        }
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .onTapGesture { openDetail(item) }
    }

    // MARK: - 詳細を開く

    private func openDetail(_ item: EduLogHistoryItem) {
        let sibling = allEduItems.filter {
            $0.authorName == item.authorName &&
            catKey($0) == catKey(item)
        }
        if sibling.count > 1, let idx = sibling.firstIndex(where: { $0.id == item.id }) {
            swipeDetailItems = sibling
            swipeDetailStart = idx
        } else {
            swipeDetailItems = [item]
            swipeDetailStart = 0
        }
        showSwipeDetail = true
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
    @Environment(\.dismiss) private var dismiss

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
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                    default:
                        Text(initial)
                            .font(.system(size: size * 0.4, weight: .black))
                            .foregroundColor(.white)
                    }
                }
            } else {
                Text(initial)
                    .font(.system(size: size * 0.4, weight: .black))
                    .foregroundColor(.white)
            }
        }
    }
}
