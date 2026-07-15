//
//  ShareViewController.swift
//  kfitShare
//

import UIKit
import Social
import UniformTypeIdentifiers

private let appGroupID       = "group.com.kfit.app"
private let pendingSharesKey = "pendingDuolingoShares"

// MARK: - 読書ソースアプリのバンドルID

private let readingBundleIDs: [String] = [
    "com.audible.iphone",          // Audible
    "com.amazon.audible",
    "com.amazon.Lassen",           // Kindle
    "com.amazon.kindle",
    "com.overdrive.mobile.ios.libby", // Libby（図書館）
    "com.overdrive.libby",
    "com.overdrive.app",
    "com.google.Books",            // Google Play Books
    "jp.bookwalker.gb.ios",        // BookWalker
    "jp.bookwalker.BookWalker",
    "com.yodobashi.ebook.bookplace", // 楽天kobo等
    "jp.co.rakuten.kobo",
]

// MARK: - 読書URLパターン

private let readingUrlPatterns: [String] = [
    "audible.com",
    "audible.co.jp",
    "amazon.co.jp/dp/",
    "amazon.com/dp/",
    "amazon.co.jp/gp/product",
    "amazon.com/gp/product",
    "kindle.amazon",
    "books.google.com",
    "play.google.com/store/books",
    "libbyapp.com",
    "overdrive.com",
    "bookwalker.jp",
    "kobo.com",
    "booklive.jp",
    "ebookjapan.yahoo.co.jp",
    "books.rakuten.co.jp",
]

class ShareViewController: SLComposeServiceViewController {

    // MARK: - 共有元アプリ検知

    /// 共有元が Duolingo かを複数シグナルから判定
    private var sourceIsDuolingo: Bool {
        let duolingoKeys = [
            "sourceApplication",
            "NSExtensionItemOriginatingAppBundleIdentifier",
            "UIApplicationLaunchOptionsSourceApplicationKey",
            "com.apple.share-services.source-bundle-identifier"
        ]
        for raw in extensionContext?.inputItems ?? [] {
            guard let ext = raw as? NSExtensionItem else { continue }
            for key in duolingoKeys {
                if let val = ext.userInfo?[key] as? String,
                   val.lowercased().contains("duolingo") { return true }
            }
            for (_, value) in ext.userInfo ?? [:] {
                if "\(value)".lowercased().contains("duolingo") { return true }
            }
            if let text = ext.attributedContentText?.string,
               text.lowercased().contains("duolingo") { return true }
        }
        return false
    }

    /// 共有元アプリのバンドルIDを取得
    private var sourceAppBundleID: String {
        for raw in extensionContext?.inputItems ?? [] {
            guard let ext = raw as? NSExtensionItem else { continue }
            for key in ["NSExtensionItemOriginatingAppBundleIdentifier",
                        "sourceApplication",
                        "com.apple.share-services.source-bundle-identifier"] {
                if let val = ext.userInfo?[key] as? String { return val.lowercased() }
            }
        }
        return ""
    }

    /// 共有元が読書アプリかどうかを判定
    private var sourceIsReading: Bool {
        let bundleID = sourceAppBundleID
        return readingBundleIDs.contains(where: { bundleID.contains($0.lowercased()) })
    }

    /// 共有アイテムの attributedContentText から説明文を取得
    private var itemDescription: String {
        for raw in extensionContext?.inputItems ?? [] {
            guard let ext = raw as? NSExtensionItem else { continue }
            if let text = ext.attributedContentText?.string,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        return ""
    }

    override func isContentValid() -> Bool { true }

    override func didSelectPost() {
        let userTyped   = (contentText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let autoDesc    = itemDescription
        let userComment = userTyped.isEmpty ? autoDesc : userTyped

        let isDuolingoSrc  = sourceIsDuolingo
        let isReadingSrc   = sourceIsReading
        let commentLower   = userComment.lowercased()

        let duoKeywords = ["duo", "duolingo", "🦉", "xp", "streak", "ストリーク",
                           "例文", "文法", "grammar", "翻訳", "単語", "vocab",
                           "フレーズ", "phrase", "発音", "pronunciation", "ピンイン",
                           "daily", "デイリー", "challenge", "ハート", "レッスン",
                           "lesson", "league", "リーグ"]
        let commentHasDuo = duoKeywords.contains { commentLower.contains($0) }
        let isDuolingo    = isDuolingoSrc || commentHasDuo

        let readingCommentKeywords = ["読書", "読んだ", "読んでいる", "本", "書評", "感想",
                                      "おすすめ", "reading", "book", "novel", "kindle",
                                      "audible", "ebook", "図書", "文庫", "マンガ", "漫画"]
        let commentHasReading = readingCommentKeywords.contains { commentLower.contains($0) }

        // 共有アイテムから添付ファイルを全部収集
        var allProviders: [NSItemProvider] = []
        for raw in extensionContext?.inputItems ?? [] {
            if let ext = raw as? NSExtensionItem {
                allProviders += ext.attachments ?? []
            }
        }

        let group = DispatchGroup()

        // ── URL 共有を先にチェック ─────────────────────────────────────────
        var foundURL: URL? = nil
        var foundTitle: String? = nil

        for provider in allProviders {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) ||
               provider.hasItemConformingToTypeIdentifier("public.url") {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    if let url = item as? URL { foundURL = url }
                    else if let str = item as? String, let url = URL(string: str) { foundURL = url }
                }
                break
            }
        }

        // タイトルは itemDescription か attributedContentText から取得
        for raw in extensionContext?.inputItems ?? [] {
            if let ext = raw as? NSExtensionItem,
               let title = ext.attributedContentText?.string,
               !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                foundTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }

            let urlStr = foundURL?.absoluteString ?? ""
            let urlLower = urlStr.lowercased()

            // URL が読書系かどうかを判定
            let urlIsReading = readingUrlPatterns.contains { urlLower.contains($0) }
            let isReadingShare = isReadingSrc || urlIsReading || commentHasReading

            // URL-only 共有（画像なし）の場合の処理
            if let url = foundURL, !urlStr.isEmpty {
                // URL 共有を保存
                let category: String
                if isDuolingo {
                    category = "duolingo"
                } else if isReadingShare {
                    category = "reading"
                } else {
                    category = "other"
                }

                self.saveURL(
                    url,
                    title: foundTitle ?? userComment,
                    comment: userComment,
                    category: category,
                    sourceApp: self.sourceAppBundleID
                )

                // 画像も同時共有されている場合は引き続き画像も保存
                var savedImage = false
                let imgGroup = DispatchGroup()
                let providers = allProviders

                for provider in providers {
                    if provider.canLoadObject(ofClass: UIImage.self) {
                        imgGroup.enter()
                        provider.loadObject(ofClass: UIImage.self) { obj, _ in
                            defer { imgGroup.leave() }
                            guard let img = obj as? UIImage else { return }
                            if !savedImage {
                                savedImage = true
                                self.saveImage(img, comment: userComment,
                                               isDuolingo: isDuolingo, isDuolingoSrc: isDuolingoSrc,
                                               isReadingShare: isReadingShare,
                                               sharedUrl: urlStr)
                            }
                        }
                    }
                }
                imgGroup.notify(queue: .main) {
                    self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                }
                return
            }

            // ── 画像のみ共有 ───────────────────────────────────────────────
            let imgGroup2 = DispatchGroup()
            var savedCount2 = 0
            let providers2 = allProviders

            for provider in providers2 {
                if provider.canLoadObject(ofClass: UIImage.self) {
                    imgGroup2.enter()
                    provider.loadObject(ofClass: UIImage.self) { obj, _ in
                        defer { imgGroup2.leave() }
                        guard let img = obj as? UIImage else { return }
                        self.saveImage(img, comment: userComment,
                                       isDuolingo: isDuolingo, isDuolingoSrc: isDuolingoSrc,
                                       isReadingShare: isReadingShare,
                                       sharedUrl: nil)
                        savedCount2 += 1
                    }
                    continue
                }

                // フォールバック: Data として読み込む
                let imageTypes = [UTType.png.identifier, UTType.jpeg.identifier,
                                  UTType.heic.identifier, "public.image",
                                  "com.apple.uikit.image"]
                guard let typeID = imageTypes.first(where: {
                    provider.hasItemConformingToTypeIdentifier($0)
                }) else { continue }

                imgGroup2.enter()
                provider.loadItem(forTypeIdentifier: typeID, options: nil) { item, _ in
                    defer { imgGroup2.leave() }
                    var imageData: Data?
                    if let url  = item as? URL   { imageData = try? Data(contentsOf: url) }
                    else if let d = item as? Data  { imageData = d }
                    else if let img = item as? UIImage { imageData = img.jpegData(compressionQuality: 0.85) }
                    guard let data = imageData, let img = UIImage(data: data) else { return }
                    self.saveImage(img, comment: userComment,
                                   isDuolingo: isDuolingo, isDuolingoSrc: isDuolingoSrc,
                                   isReadingShare: isReadingShare,
                                   sharedUrl: nil)
                    savedCount2 += 1
                }
            }

            imgGroup2.notify(queue: .main) {
                self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }
        }
    }

    // MARK: - URL を App Group に保存

    private func saveURL(_ url: URL, title: String, comment: String,
                         category: String, sourceApp: String) {
        let defaults = UserDefaults(suiteName: appGroupID)
        var pending  = defaults?.array(forKey: pendingSharesKey) as? [[String: Any]] ?? []
        pending.append([
            "urlString":   url.absoluteString,
            "sharedTitle": title,
            "timestamp":   Date().timeIntervalSince1970,
            "comment":     comment,
            "category":    category,
            "sourceApp":   sourceApp,
            "isDuolingo":  category == "duolingo",
        ])
        defaults?.set(pending, forKey: pendingSharesKey)
        defaults?.synchronize()
    }

    // MARK: - 画像を App Group に保存

    private func saveImage(_ img: UIImage, comment: String,
                           isDuolingo: Bool, isDuolingoSrc: Bool,
                           isReadingShare: Bool = false,
                           sharedUrl: String?) {
        guard let data = img.jpegData(compressionQuality: 0.85),
              let containerURL = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return }

        let filename = "share_\(Date().timeIntervalSince1970)_\(Int.random(in: 1000...9999)).jpg"
        let fileURL  = containerURL.appendingPathComponent(filename)
        try? data.write(to: fileURL)

        let defaults = UserDefaults(suiteName: appGroupID)
        var pending  = defaults?.array(forKey: pendingSharesKey) as? [[String: Any]] ?? []
        var entry: [String: Any] = [
            "filename":  filename,
            "timestamp": Date().timeIntervalSince1970,
            "comment":   comment,
            "sourceApp": isDuolingoSrc ? "com.duolingo.DuolingoMobile" : sourceAppBundleID,
            "isDuolingo": isDuolingo
        ]
        if let url = sharedUrl { entry["urlString"] = url }
        if isDuolingo {
            entry["category"] = "duolingo"
        } else if isReadingShare {
            entry["category"] = "reading"
        }
        pending.append(entry)
        defaults?.set(pending, forKey: pendingSharesKey)
        defaults?.synchronize()
    }

    override func configurationItems() -> [Any]! { [] }
}
