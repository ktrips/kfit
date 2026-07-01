import SwiftUI
import UIKit

// MARK: - RoundedCorner / cornerRadius extension
// DashboardView.swift で定義されている Shape と View 拡張を kedu 用に提供します。

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

// MARK: - FoodView.swift が提供するビュー（TomoView が参照）

struct UserAvatarView: View {
    let name: String
    let photoURL: String
    let gradient: LinearGradient
    let size: CGFloat

    init(name: String,
         photoURL: String = "",
         gradient: LinearGradient = LinearGradient(
            colors: [Color.duoBlue, Color.duoPurple],
            startPoint: .topLeading, endPoint: .bottomTrailing),
         size: CGFloat = 36) {
        self.name     = name
        self.photoURL = photoURL
        self.gradient = gradient
        self.size     = size
    }

    var body: some View { EmptyView() }
}

struct PhotoFeedDetailSheet: View {
    let item: PhotoLogHistoryItem
    var embedded: Bool = false
    var body: some View { EmptyView() }
}

struct EduFeedDetailSheet: View {
    let item: EduLogHistoryItem
    var body: some View { EmptyView() }
}

struct EduPhotoLogSheet: View {
    var nodeEmoji: String = ""
    var nodeName: String = ""
    var onComplete: ((Bool, Bool, UIImage?, String) -> Void)? = nil
    var body: some View { EmptyView() }
}

struct PhotoLogView: View {
    var body: some View { EmptyView() }
}

struct FeedCommentsSheet: View {
    let item: EduLogHistoryItem
    var eduLogManager: EduLogManager = EduLogManager.shared
    var photoLogManager: PhotoLogManager? = nil
    var body: some View { EmptyView() }
}

struct SocialShareSheet: View {
    let item: EduLogHistoryItem
    var body: some View { EmptyView() }
}

struct CategoryGroupListSheet: View {
    let group: TomoView.FeedCategoryGroup
    var onTapItem: ((EduLogHistoryItem) -> Void)? = nil
    var onLike: ((EduLogHistoryItem) -> Void)? = nil
    var onComment: ((EduLogHistoryItem) -> Void)? = nil
    var onShare: ((EduLogHistoryItem) -> Void)? = nil
    var body: some View { EmptyView() }
}
