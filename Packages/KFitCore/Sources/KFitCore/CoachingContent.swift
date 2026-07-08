import Foundation

// MARK: - コーチングコンテンツ DB（A5: 単一ソース）
// content_db.json から読み込む。
// ・アプリ内コーチング通知文言
// ・書籍（100メソッド）の章データ
// ・SNS 投稿テンプレート
// の単一ソースとして機能する。

// MARK: - モデル

public struct CoachingMethod: Codable, Identifiable {
    public let id: String                // "001"–"100"
    public let emoji: String
    public let title: String
    public let category: String          // "energy" | "nutrition" | "mind" | "fitingo"
    public let categoryLabel: String
    public let description: String
    public let steps: [String]
    public let tip: String
    public let coachingMessage: String   // 通知文言（60文字以内）
    public let snsPost: String           // SNS 投稿テンプレート
    public let tags: [String]

    public enum CodingKeys: String, CodingKey {
        case id, emoji, title, category
        case categoryLabel = "category_label"
        case description, steps, tip
        case coachingMessage = "coaching_message"
        case snsPost = "sns_post"
        case tags
    }
}

public struct ContentCategory: Codable {
    public let label: String
    public let emoji: String
    public let range: String
}

public struct ContentDB: Codable {
    public let version: String
    public let source: String
    public let description: String
    public let categories: [String: ContentCategory]
    public let methods: [CoachingMethod]
}

// MARK: - ローダー

public final class CoachingContentDB {
    public static let shared = CoachingContentDB()

    private var _db: ContentDB?

    private init() {}

    /// DB を読み込む（初回のみ）
    public func load() -> ContentDB? {
        if let cached = _db { return cached }
        guard let url = Bundle.module.url(forResource: "content_db", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let db = try? JSONDecoder().decode(ContentDB.self, from: data)
        else {
            return nil
        }
        _db = db
        return db
    }

    /// 全メソッドを返す
    public var allMethods: [CoachingMethod] {
        load()?.methods ?? []
    }

    /// カテゴリでフィルタ
    public func methods(for category: String) -> [CoachingMethod] {
        allMethods.filter { $0.category == category }
    }

    /// ランダムな通知文言を返す（カテゴリ指定可能）
    public func randomCoachingMessage(category: String? = nil) -> String? {
        let pool = category == nil ? allMethods : methods(for: category!)
        return pool.randomElement()?.coachingMessage
    }

    /// 今日の日付をシードにしたデイリーメソッドを返す
    public func dailyMethod(category: String? = nil) -> CoachingMethod? {
        let pool = category == nil ? allMethods : methods(for: category!)
        guard !pool.isEmpty else { return nil }
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return pool[dayOfYear % pool.count]
    }

    /// SNS 投稿テンプレートを返す（今日のメソッド）
    public func dailySNSPost(category: String? = nil) -> String? {
        dailyMethod(category: category)?.snsPost
    }

    /// 特定 ID のメソッドを返す
    public func method(id: String) -> CoachingMethod? {
        allMethods.first { $0.id == id }
    }

    /// タグでフィルタ
    public func methods(withTag tag: String) -> [CoachingMethod] {
        allMethods.filter { $0.tags.contains(tag) }
    }
}

// MARK: - 使い方（コメント）
/*
 Import KFitCore して以下のように使います:

 // 今日のコーチングメッセージ（通知文言）
 let msg = CoachingContentDB.shared.dailyMethod()?.coachingMessage

 // カテゴリ別通知
 let mindTip = CoachingContentDB.shared.randomCoachingMessage(category: "mind")

 // 今日の SNS テンプレート
 let tweet = CoachingContentDB.shared.dailySNSPost()

 // 書籍の章リスト（全メソッド）
 let chapters = CoachingContentDB.shared.allMethods
*/
