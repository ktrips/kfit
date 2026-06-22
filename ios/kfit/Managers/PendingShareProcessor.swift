import Foundation
import UIKit

// MARK: - App 本体側: 起動時に共有コンテナを処理してFeedに投稿する
// FirebaseStorage は未導入のため EduLogManager.addItem() 経由でローカルフィードに保存

private let appGroupID       = "group.com.yourteam.kfit"
private let pendingSharesKey = "pendingDuolingoShares"

@MainActor
class PendingShareProcessor {

    static let shared = PendingShareProcessor()

    /// kfitApp.onAppear や SceneDelegate から呼ぶ
    func processPendingShares(userID: String, userName: String) async {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }

        let pending = defaults.array(forKey: pendingSharesKey) as? [[String: Any]] ?? []
        guard !pending.isEmpty else { return }

        defaults.removeObject(forKey: pendingSharesKey)
        defaults.synchronize()

        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return }

        for item in pending {
            guard let filename  = item["filename"]  as? String,
                  let _         = item["timestamp"] as? TimeInterval else { continue }

            let fileURL = containerURL.appendingPathComponent(filename)
            guard let imageData = try? Data(contentsOf: fileURL),
                  let image = UIImage(data: imageData) else { continue }

            // EduLogManager 経由でフィードに追加
            // activityEmoji == "🦉" により addItem 内部で自動 OCR が実行される
            EduLogManager.shared.addItem(
                activityName: "Duolingo",
                activityEmoji: "🦉",
                comment: "Duolingo 達成！🎉",
                image: image,
                isPublic: true
            )

            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
