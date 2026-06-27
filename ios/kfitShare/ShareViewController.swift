//
//  ShareViewController.swift
//  kfitShare
//

import UIKit
import Social
import UniformTypeIdentifiers

private let appGroupID       = "group.com.yourteam.kfit"
private let pendingSharesKey = "pendingDuolingoShares"

class ShareViewController: SLComposeServiceViewController {

    // MARK: - 共有元アプリ名を取得

    private var sourceAppName: String {
        // NSExtensionItem の userInfo → sourceApplication (iOS 13+)
        if let src = extensionContext?.inputItems.first as? NSExtensionItem,
           let name = src.userInfo?["sourceApplication"] as? String {
            return name
        }
        // Bundle identifier から最後のコンポーネントを表示名として使う
        return Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? ""
    }

    override func isContentValid() -> Bool { true }

    override func didSelectPost() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments else {
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            return
        }

        // ユーザーが入力したコメント（なければ空文字）
        let userComment = contentText ?? ""
        let sourceApp   = sourceAppName

        let group = DispatchGroup()

        for provider in attachments {
            let typeID: String
            if provider.hasItemConformingToTypeIdentifier(UTType.png.identifier) {
                typeID = UTType.png.identifier
            } else if provider.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier) {
                typeID = UTType.jpeg.identifier
            } else {
                continue
            }

            group.enter()
            provider.loadItem(forTypeIdentifier: typeID, options: nil) { data, _ in
                defer { group.leave() }

                var imageData: Data?
                if let url = data as? URL {
                    imageData = try? Data(contentsOf: url)
                } else if let raw = data as? Data {
                    imageData = raw
                } else if let img = data as? UIImage {
                    imageData = img.jpegData(compressionQuality: 0.85)
                }

                guard let imageData,
                      let containerURL = FileManager.default
                        .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return }

                let filename = "share_\(Date().timeIntervalSince1970).jpg"
                let fileURL  = containerURL.appendingPathComponent(filename)
                try? imageData.write(to: fileURL)

                let defaults = UserDefaults(suiteName: appGroupID)
                var pending  = defaults?.array(forKey: pendingSharesKey) as? [[String: Any]] ?? []
                pending.append([
                    "filename":   filename,
                    "timestamp":  Date().timeIntervalSince1970,
                    "comment":    userComment,    // ユーザーのコメント（キーワード含む）
                    "sourceApp":  sourceApp       // 共有元アプリ名
                ])
                defaults?.set(pending, forKey: pendingSharesKey)
                defaults?.synchronize()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    override func configurationItems() -> [Any]! { [] }
}
