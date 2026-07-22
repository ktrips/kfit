import SwiftUI
import UIKit

// RoundedCorner / cornerRadius(_:corners:) / UserAvatarView / FeedCommentsSheet /
// SocialShareSheet / CategoryGroupListSheet は
// Views/Components/SharedFeedViews.swift の共有定義（kfit本体と共通）を使用するため、
// ここでのスタブ提供は不要になりました。
//
// 以下は kedu 側に対応するインフラ（Plus課金・AIクォータ・HealthKit連携）が無いため、
// 引き続き空実装スタブとして提供する型です。

// MARK: - FoodView.swift が提供するビュー（TomoView が参照）

struct PhotoFeedDetailSheet: View {
    let item: PhotoLogHistoryItem
    var embedded: Bool = false
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
