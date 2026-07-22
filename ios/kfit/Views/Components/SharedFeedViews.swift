import SwiftUI

// kedu ターゲットとも共有されるフィード関連ビュー（TomoView.swift から使用）。
// TOMOページの詳細画面（コメント欄・SNS共有・カテゴリ一覧）を kfit/kedu で
// 同じ見た目・機能にするため、DashboardView.swift / FoodView.swift から移設。

// MARK: - Study Read Aloud Button
// 「勉強」投稿（コメント冒頭が「勉強」）の readAloudText を読み上げるボタン。
// EduPostHistorySection（一覧）・SwipeableTomoDetailSheet（詳細）で共通使用。

struct StudyReadAloudButton: View {
    let text: String
    let languageCode: String

    @ObservedObject private var tts = DuolingoTextExtractor.shared
    @State private var isPlayingLocally = false

    var body: some View {
        Button {
            if isPlayingLocally {
                tts.stopSpeaking()
                isPlayingLocally = false
            } else {
                isPlayingLocally = true
                tts.speak(phrase: text, languageCode: languageCode)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isPlayingLocally ? "stop.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(isPlayingLocally ? "停止" : "読み上げ")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(isPlayingLocally ? Color.red : Color(hex: "#CE82FF"))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onChange(of: tts.isSpeaking) { _, speaking in
            if !speaking { isPlayingLocally = false }
        }
    }
}

// MARK: - RoundedCorner Shape

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

// MARK: - User Avatar View
/// Google アイコン（URL）があれば表示、なければイニシャルをグラデーション円で表示
struct UserAvatarView: View {
    let name: String
    let photoURL: String
    let gradient: LinearGradient
    let size: CGFloat

    init(name: String, photoURL: String = "",
         gradient: LinearGradient = LinearGradient(
            colors: [Color.duoBlue, Color.duoPurple],
            startPoint: .topLeading, endPoint: .bottomTrailing),
         size: CGFloat = 36) {
        self.name     = name
        self.photoURL = photoURL
        self.gradient = gradient
        self.size     = size
    }

    private var initial: String {
        String((name.first ?? "?").uppercased())
    }

    var body: some View {
        Group {
            if let url = URL(string: photoURL), !photoURL.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsView: some View {
        ZStack {
            Circle().fill(gradient)
            Text(initial)
                .font(.system(size: size * 0.42, weight: .black))
                .foregroundColor(.white)
        }
    }
}

// MARK: - 食事時間ラベルヘルパー（FoodView / TomoView 共通）

func mealTimeInfo(for date: Date) -> (label: String, color: Color) {
    let hour = Calendar.current.component(.hour, from: date)
    switch hour {
    case 5..<11:  return ("Breakfast", Color(hex: "#FF9500"))
    case 11..<14: return ("Lunch",     Color(hex: "#34C759"))
    case 14..<18: return ("Snack",     Color(hex: "#AF52DE"))
    case 18..<24: return ("Dinner",    Color(hex: "#0A84FF"))
    default:      return ("Late Night",Color(hex: "#5E5CE6"))
    }
}

// MARK: - Feed Comments Sheet

struct FeedCommentsSheet: View {
    let item: EduLogHistoryItem
    @ObservedObject var eduLogManager: EduLogManager
    var photoLogManager: PhotoLogManager? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var newCommentText = ""
    @FocusState private var inputFocused: Bool

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d HH:mm"
        return f
    }()

    private var isFoodItem: Bool { item.id.hasPrefix("food_") }
    private var foodOriginalId: String { String(item.id.dropFirst("food_".count)) }

    private var currentItem: EduLogHistoryItem {
        if isFoodItem, let pm = photoLogManager,
           let food = pm.history.first(where: { $0.id == foodOriginalId }) {
            var copy = item
            copy.isLiked = food.isLiked
            copy.likeCount = food.likeCount
            copy.feedComments = food.feedComments
            return copy
        }
        return eduLogManager.history.first { $0.id == item.id } ?? item
    }

    var body: some View {
        VStack(spacing: 0) {
            // ハンドル
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            // ナビ行
            HStack {
                Text("コメント")
                    .font(.system(size: 16 * UIScale.font, weight: .black))
                    .foregroundColor(Color.duoDark)
                Spacer()
                Button("閉じる") { dismiss() }
                    .font(.system(size: 14 * UIScale.font))
                    .foregroundColor(Color.duoBlue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // コメント一覧
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // 投稿のキャプション（コメント風に表示）
                    if !item.comment.isEmpty {
                        commentRow(
                            name: item.authorFirstName,
                            photoURL: item.authorPhotoURL,
                            text: item.comment,
                            date: item.timestamp,
                            isCaption: true,
                            commentId: nil
                        )
                        Divider().padding(.leading, 52)
                    }

                    if currentItem.feedComments.isEmpty && item.comment.isEmpty {
                        Text("まだコメントがありません\n最初のコメントを残しましょう！")
                            .font(.system(size: 13 * UIScale.font))
                            .foregroundColor(Color.duoSubtitle)
                            .multilineTextAlignment(.center)
                            .padding(32)
                    }

                    ForEach(currentItem.feedComments) { c in
                        commentRow(
                            name: c.authorFirstName,
                            photoURL: c.authorPhotoURL,
                            text: c.text,
                            date: c.timestamp,
                            isCaption: false,
                            commentId: c.id
                        )
                        if c.id != currentItem.feedComments.last?.id {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
            }

            Divider()

            // コメント入力バー
            HStack(spacing: 10) {
                // 自分のアバター
                UserAvatarView(
                    name: AuthenticationManager.shared.userProfile?.username ?? "?",
                    photoURL: UserDefaults.standard.string(forKey: "cachedCurrentUserPhotoURL") ?? "",
                    size: 32
                )

                TextField("コメントを追加...", text: $newCommentText, axis: .vertical)
                    .font(.system(size: 14 * UIScale.font))
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit { sendComment() }

                Button {
                    sendComment()
                } label: {
                    Text("投稿")
                        .font(.system(size: 14 * UIScale.font, weight: .bold))
                        .foregroundColor(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color.duoBlue.opacity(0.3) : Color.duoBlue)
                }
                .buttonStyle(.plain)
                .disabled(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
        }
        .background(Color(.systemBackground))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .onAppear { inputFocused = true }
    }

    private func commentRow(name: String, photoURL: String = "", text: String, date: Date,
                            isCaption: Bool, commentId: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            UserAvatarView(
                name: name,
                photoURL: photoURL,
                gradient: LinearGradient(
                    colors: isCaption
                        ? [Color.duoPurple, Color(hex: "#b91d73")]
                        : [Color.duoGreen, Color(hex: "#38ef7d")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                size: 36
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 13 * UIScale.font, weight: .black))
                        .foregroundColor(Color.duoDark)
                    if isCaption {
                        Text("投稿者")
                            .font(.system(size: 9 * UIScale.font, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.duoPurple)
                            .cornerRadius(4)
                    }
                    Spacer()
                    Text(FeedCommentsSheet.timeFormatter.string(from: date))
                        .font(.system(size: 10 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)
                }
                Text(text)
                    .font(.system(size: 13 * UIScale.font))
                    .foregroundColor(Color.duoDark.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contextMenu {
            if let cid = commentId {
                Button(role: .destructive) {
                    if isFoodItem, let pm = photoLogManager {
                        pm.deleteFeedComment(itemId: foodOriginalId, commentId: cid)
                    } else {
                        eduLogManager.deleteFeedComment(itemId: item.id, commentId: cid)
                    }
                } label: {
                    Label("削除", systemImage: "trash")
                }
            }
        }
    }

    private func sendComment() {
        let text = newCommentText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if isFoodItem, let pm = photoLogManager {
            pm.addFeedComment(id: foodOriginalId, text: text)
        } else {
            eduLogManager.addFeedComment(id: item.id, text: text)
        }
        newCommentText = ""
    }
}

// MARK: - Social Share Sheet

struct SocialShareSheet: View {
    let item: EduLogHistoryItem
    /// 追加で共有したいURL（リンクシェア用）
    var shareURL: URL? = nil
    /// 追加で共有したい画像（item.thumbnail より優先）
    var overrideImage: UIImage? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showSystemShare = false

    // 設定済みSNSアカウント
    @AppStorage("sns.x.handle")         private var xHandle  = ""
    @AppStorage("sns.instagram.handle") private var igHandle = ""
    @AppStorage("sns.facebook.url")     private var fbUrl    = ""
    @AppStorage("sns.line.id")          private var lineId   = ""

    private var effectiveImage: UIImage? { overrideImage ?? item.thumbnail }

    private var systemShareItems: [Any] {
        var items: [Any] = [shareText]
        if let img = effectiveImage { items.insert(img, at: 0) }
        if let url = shareURL { items.append(url) }
        return items
    }

    private var shareText: String {
        let emoji = item.activityEmoji.isEmpty ? "💪" : item.activityEmoji
        let name  = item.activityName.isEmpty ? "アクティビティ" : item.activityName
        var text  = "\(emoji) \(name) を達成！"
        if !item.comment.isEmpty { text += "\n\(item.comment)" }
        if let url = shareURL { text += "\n\(url.absoluteString)" }
        text += "\n\n#kfit #フィットネス #健康習慣"
        return text
    }

    // LINE shared text (URL encoded)
    private var lineText: String {
        var t = shareText
        if let url = shareURL { t += "\n\(url.absoluteString)" }
        return t
    }

    // シートの高さ：LINEボタンありの場合は高め
    private var sheetHeight: CGFloat {
        let hasLine = !lineId.isEmpty
        return hasLine ? 230 : 195
    }

    var body: some View {
        VStack(spacing: 0) {
            // ドラッグハンドル
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 14)

            Text("シェア")
                .font(.system(size: 16 * UIScale.font, weight: .black))
                .foregroundColor(Color.duoDark)
                .padding(.bottom, 16)

            // ── メインSNSボタン行 ────────────────────────────────
            HStack(spacing: 0) {
                Spacer()
                socialButton(
                    label: xHandle.isEmpty ? "X (Twitter)" : xHandle,
                    color: .black,
                    systemIcon: "x.square.fill"
                ) { shareToX() }
                Spacer()
                socialButton(
                    label: fbUrl.isEmpty ? "Facebook" : "Facebook",
                    color: Color(hex: "#1877F2"),
                    systemIcon: "f.square.fill"
                ) { shareToFacebook() }
                Spacer()
                socialButton(
                    label: igHandle.isEmpty ? "Instagram" : igHandle,
                    color: Color(hex: "#E1306C"),
                    systemIcon: "camera.fill"
                ) { shareToInstagram() }
                Spacer()
                socialButton(
                    label: "その他",
                    color: Color.duoSubtitle,
                    systemIcon: "square.and.arrow.up"
                ) { showSystemShare = true }
                Spacer()
            }
            .padding(.bottom, lineId.isEmpty ? 28 : 16)

            // ── LINEボタン（登録済みの場合のみ表示）────────────────
            if !lineId.isEmpty {
                Button { shareToLine() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                        Text("LINEで送る")
                            .font(.system(size: 14 * UIScale.font, weight: .bold))
                            .foregroundColor(.white)
                        Text("(\(lineId))")
                            .font(.system(size: 11 * UIScale.font))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(hex: "#06C755"))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .background(Color(.systemBackground))
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.hidden)
        .sheet(isPresented: $showSystemShare) {
            SystemShareSheet(items: systemShareItems)
        }
    }

    // MARK: - ボタンビュー

    private func socialButton(label: String, color: Color, systemIcon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(color)
                        .frame(width: 54, height: 54)
                    Image(systemName: systemIcon)
                        .font(.system(size: 24 * UIScale.font))
                        .foregroundColor(.white)
                }
                Text(label)
                    .font(.system(size: 9 * UIScale.font, weight: .semibold))
                    .foregroundColor(Color.duoSubtitle)
                    .lineLimit(1)
                    .frame(width: 60)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Share Actions

    private func shareToX() {
        var text = shareText
        // アカウントハンドルが設定されていれば末尾に追加
        if !xHandle.isEmpty, !text.contains(xHandle) {
            text += "\n\(xHandle)"
        }
        let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        // URL を別パラメータで渡す（x.com Web Intent対応）
        var urlStr = "https://x.com/intent/post?text=\(encodedText)"
        if let url = shareURL, let encodedURL = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlStr += "&url=\(encodedURL)"
        }
        let appURLStr = "twitter://post?message=\(encodedText)"
        if let appURL = URL(string: appURLStr), UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
        } else if let webURL = URL(string: urlStr) {
            UIApplication.shared.open(webURL)
        }
        dismiss()
    }

    private func shareToFacebook() {
        // Facebook はURLシェアが主流（テキスト直接投稿はAPIなしでは困難）
        if let url = shareURL,
           let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let webURL = URL(string: "https://www.facebook.com/sharer/sharer.php?u=\(encoded)") {
            UIApplication.shared.open(webURL)
        } else if let appURL = URL(string: "fb://"), UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
        } else {
            UIApplication.shared.open(URL(string: "https://www.facebook.com/")!)
        }
        dismiss()
    }

    private func shareToInstagram() {
        let image = effectiveImage
        if let image {
            guard let imageData = image.pngData() else { openInstagramApp(); dismiss(); return }
            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("kfit_share_\(UUID().uuidString).igo")
            do {
                try imageData.write(to: tmpURL)
                let controller = UIDocumentInteractionController(url: tmpURL)
                controller.uti = "com.instagram.exclusivegram"
                var caption = shareText
                if !igHandle.isEmpty, !caption.contains(igHandle) { caption += "\n\(igHandle)" }
                controller.annotation = ["InstagramCaption": caption]
                if let root = UIApplication.shared.connectedScenes
                    .compactMap({ ($0 as? UIWindowScene)?.windows.first?.rootViewController })
                    .first {
                    controller.presentOpenInMenu(from: .zero, in: root.view, animated: true)
                }
            } catch { openInstagramApp() }
        } else {
            openInstagramApp()
        }
        dismiss()
    }

    private func openInstagramApp() {
        let url = URL(string: "instagram://app")!
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            UIApplication.shared.open(URL(string: "https://www.instagram.com")!)
        }
    }

    private func shareToLine() {
        let text = lineText
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let appURL = URL(string: "line://msg/text/\(encoded)")
        let webURL = URL(string: "https://line.me/R/msg/text/?\(encoded)")
        if let app = appURL, UIApplication.shared.canOpenURL(app) {
            UIApplication.shared.open(app)
        } else if let web = webURL {
            UIApplication.shared.open(web)
        }
        dismiss()
    }
}

// MARK: - Category Group List Sheet

struct CategoryGroupListSheet: View {
    let group: TomoView.FeedCategoryGroup
    var onTapItem: (EduLogHistoryItem) -> Void
    var onLike: ((EduLogHistoryItem) -> Void)? = nil
    var onComment: ((EduLogHistoryItem) -> Void)? = nil
    var onShare: ((EduLogHistoryItem) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    private static let hhmm: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.dateFormat = "HH:mm"; return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // ハンドル
            Capsule().fill(Color(.systemGray4)).frame(width: 36, height: 4).padding(.top, 10)

            // ヘッダー
            HStack(spacing: 10) {
                Text(group.categoryEmoji.isEmpty ? "📝" : group.categoryEmoji)
                    .font(.system(size: 24 * UIScale.font))
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.categoryKey)
                        .font(.system(size: 16 * UIScale.font, weight: .black)).foregroundColor(Color.duoDark)
                    Text("\(group.items.count)件の記録")
                        .font(.system(size: 11 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                }
                Spacer()
                Button("閉じる") { dismiss() }
                    .font(.system(size: 14 * UIScale.font)).foregroundColor(Color.duoBlue)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)

            Divider()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(group.items) { item in
                        listRow(item: item)
                        if item.id != group.items.last?.id { Divider().padding(.leading, 64) }
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private func listRow(item: EduLogHistoryItem) -> some View {
        HStack(spacing: 12) {
            // アバター（左）
            UserAvatarView(
                name: item.authorFirstName,
                photoURL: item.authorPhotoURL.isEmpty
                    ? (UserDefaults.standard.string(forKey: "cachedCurrentUserPhotoURL") ?? "")
                    : item.authorPhotoURL,
                size: 36
            )

            // サムネイル（FOOD は食事タイムバッジをオーバーレイ）
            let isFood = item.id.hasPrefix("food_")
            let mealInfo = mealTimeInfo(for: item.timestamp)
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let thumb = item.smallThumbnail {
                        Image(uiImage: thumb).resizable().scaledToFill()
                    } else {
                        LinearGradient(
                            colors: [Color.duoBlue.opacity(0.6), Color.duoPurple.opacity(0.6)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        .overlay(Text(item.activityEmoji.isEmpty ? "📝" : item.activityEmoji).font(.system(size: 20 * UIScale.font)))
                    }
                }
                .frame(width: 48, height: 48)
                .clipped()

                if isFood {
                    Text(mealInfo.label)
                        .font(.system(size: 7 * UIScale.font, weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(mealInfo.color)
                        .clipShape(Capsule())
                        .padding(3)
                }
            }
            .cornerRadius(10)

            // テキスト（FOOD は食事名を色付きで強調）
            VStack(alignment: .leading, spacing: 4) {
                if isFood {
                    Text(mealInfo.label)
                        .font(.system(size: 10 * UIScale.font, weight: .black))
                        .foregroundColor(mealInfo.color)
                } else {
                    Text(item.authorFirstName)
                        .font(.system(size: 11 * UIScale.font, weight: .black)).foregroundColor(Color.duoSubtitle)
                }
                Text(item.comment.isEmpty ? item.activityName : item.comment)
                    .font(.system(size: 13 * UIScale.font, weight: .semibold)).foregroundColor(Color.duoDark).lineLimit(2)
                HStack(spacing: 10) {
                    Text(CategoryGroupListSheet.hhmm.string(from: item.timestamp))
                        .font(.system(size: 11 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                    if item.likeCount > 0 {
                        Label("\(item.likeCount)", systemImage: "heart.fill")
                            .font(.system(size: 10 * UIScale.font)).foregroundColor(Color(hex: "#ED4956"))
                    }
                    if !item.feedComments.isEmpty {
                        Label("\(item.feedComments.count)", systemImage: "bubble.right")
                            .font(.system(size: 10 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                    }
                }
            }
            Spacer()

            // アクション
            HStack(spacing: 14) {
                Button { onLike?(item) } label: {
                    Image(systemName: item.isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 18 * UIScale.font))
                        .foregroundColor(item.isLiked ? Color(hex: "#ED4956") : Color.duoDark.opacity(0.4))
                }
                Button { onTapItem(item) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color.duoDark.opacity(0.3))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { onTapItem(item) }
    }
}
