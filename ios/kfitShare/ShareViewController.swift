//
//  ShareViewController.swift
//  kfitShare
//
//  Created by Kenichi Yoshida on 2026/06/22.
//

import UIKit
import Social
import UniformTypeIdentifiers

private let appGroupID       = "group.com.yourteam.kfit"
private let pendingSharesKey = "pendingDuolingoShares"

class ShareViewController: SLComposeServiceViewController {

    override func isContentValid() -> Bool {
        return true
    }

    override func didSelectPost() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments else {
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            return
        }

        let group = DispatchGroup()

        for provider in attachments {
            // PNG / JPEG どちらも対応
            let typeID: String
            if provider.hasItemConformingToTypeIdentifier(UTType.png.identifier) {
                typeID = UTType.png.identifier
            } else if provider.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier) {
                typeID = UTType.jpeg.identifier
            } else {
                continue
            }

            group.enter()
            provider.loadItem(forTypeIdentifier: typeID, options: nil) { [weak self] data, _ in
                defer { group.leave() }
                guard let self else { return }

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

                // ファイルを共有コンテナに保存
                let filename = "duolingo_\(Date().timeIntervalSince1970).jpg"
                let fileURL  = containerURL.appendingPathComponent(filename)
                try? imageData.write(to: fileURL)

                // UserDefaults にメタデータを登録
                let defaults = UserDefaults(suiteName: appGroupID)
                var pending  = defaults?.array(forKey: pendingSharesKey) as? [[String: Any]] ?? []
                pending.append(["filename": filename, "timestamp": Date().timeIntervalSince1970])
                defaults?.set(pending, forKey: pendingSharesKey)
                defaults?.synchronize()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    override func configurationItems() -> [Any]! {
        return []
    }
}
