import Foundation
import UIKit
import ImageIO

// MARK: - ThumbnailFileStore
/// サムネイル画像をファイルシステムの Documents/thumbnails/ に保存・読み込みするユーティリティ。
///
/// UserDefaults に画像バイナリを直接保存すると起動時に全データをメモリに展開し、
/// 書き込みごとに数MB のシリアライズが走る問題を解消するために導入。
/// 各アイテムの `thumbnailData: Data?` は廃止し `thumbnailPath: String?` で置き換える。
enum ThumbnailFileStore {

    static let directory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir  = docs.appendingPathComponent("thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// `data` をファイルに書き込み、**ファイル名のみ**（相対パス）を返す。失敗時は nil。
    ///
    /// 絶対パスではなくファイル名を返すことで、シミュレーターのビルド間や
    /// アプリコンテナUUIDが変わった場合でも読み込みが壊れない。
    @discardableResult
    static func save(_ data: Data, id: String) -> String? {
        let filename = "\(id).jpg"
        let url = directory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return filename          // ファイル名のみ保存
        } catch {
            return nil
        }
    }

    /// ファイル名（相対）または旧形式の絶対パスから Data を読み込む。
    static func load(path: String) -> Data? {
        if path.hasPrefix("/") {
            // 旧形式: 絶対パス → まず直接試し、失敗ならファイル名で再試行
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) { return data }
            let filename = URL(fileURLWithPath: path).lastPathComponent
            return try? Data(contentsOf: directory.appendingPathComponent(filename))
        } else {
            // 新形式: ファイル名のみ
            return try? Data(contentsOf: directory.appendingPathComponent(path))
        }
    }

    /// ファイルを削除する。
    static func delete(id: String) {
        let url = directory.appendingPathComponent("\(id).jpg")
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - ThumbnailCache
/// サムネイル画像のデコード結果をキャッシュし、表示サイズに合わせてダウンサンプリングするユーティリティ。
///
/// 保存画像は最大1200px のフルサイズJPEG。これを `UIImage(data:)` で毎描画デコードすると
/// メインスレッドが詰まるため、（1）デコード済み `UIImage` を `NSCache` で再利用し、
/// （2）`CGImageSourceCreateThumbnailAtIndex` で表示に必要な画素数まで縮小してから保持する。
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 300
        // メモリ警告時はシステムが自動でパージするが、明示的にも空にする
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { [weak cache] _ in
            cache?.removeAllObjects()
        }
    }

    /// キャッシュ済みのデコード画像を返す。なければダウンサンプリングしてキャッシュする。
    /// - Parameters:
    ///   - key: アイテムの安定ID（同一データなら同一キー）
    ///   - data: 元画像データ
    ///   - maxPixel: 長辺の最大ピクセル数（表示サイズに合わせる）
    func image(for key: String, data: Data, maxPixel: CGFloat) -> UIImage? {
        let cacheKey = "\(key)|\(data.count)|\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached }
        guard let image = Self.downsample(data: data, maxPixel: maxPixel) else { return nil }
        cache.setObject(image, forKey: cacheKey)
        return image
    }

    /// キャッシュヒット時はディスクI/Oを一切行わない遅延ロード版。
    /// 旧 `image(for:data:maxPixel:)` はキーに data.count を含むため、キャッシュ確認の前に
    /// 必ずファイル読み込みが必要だった。サムネイルはアイテム作成時に `{id}.jpg` として
    /// 一度だけ保存され以後不変なので、id ベースのキーで安全にスキップできる。
    /// - Parameter dataProvider: キャッシュミス時のみ呼ばれるデータ読み込みクロージャ
    func image(for key: String, maxPixel: CGFloat, dataProvider: () -> Data?) -> UIImage? {
        let cacheKey = "\(key)|\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached }
        guard let data = dataProvider(),
              let image = Self.downsample(data: data, maxPixel: maxPixel) else { return nil }
        cache.setObject(image, forKey: cacheKey)
        return image
    }

    /// 画像データを指定の最大ピクセルまで縮小してデコードする。
    static func downsample(data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return UIImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel)
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cg)
    }
}

/// 摂取記録のデフォルト設定
struct IntakeSettings: Codable {
    // 食事のデフォルトカロリーと栄養素
    var breakfastCalories: Int = 400
    var breakfastProtein: Double = 17.0      // たんぱく質（g）
    var breakfastFat: Double = 15.0          // 脂質（g）
    var breakfastCarbs: Double = 65.0        // 炭水化物（g）
    var breakfastSugar: Double = 60.0        // 糖質（g）
    var breakfastFiber: Double = 5.0         // 食物繊維（g）
    var breakfastSodium: Double = 2.0        // 塩分（g）

    var lunchCalories: Int = 600
    var lunchProtein: Double = 31.0
    var lunchFat: Double = 18.0
    var lunchCarbs: Double = 85.0
    var lunchSugar: Double = 80.0
    var lunchFiber: Double = 5.0
    var lunchSodium: Double = 5.0

    var dinnerCalories: Int = 800
    var dinnerProtein: Double = 25.0
    var dinnerFat: Double = 30.0
    var dinnerCarbs: Double = 125.0
    var dinnerSugar: Double = 115.0
    var dinnerFiber: Double = 10.0
    var dinnerSodium: Double = 5.0

    // スナックのデフォルト栄養素
    var snackCalories: Int = 200
    var snackProtein: Double = 2.0   // たんぱく質（g）
    var snackFat: Double = 50.0      // 脂質（g）
    var snackCarbs: Double = 10.0    // 炭水化物（g）
    var snackSugar: Double = 8.0     // 糖質（g）
    var snackFiber: Double = 1.0     // 食物繊維（g）
    var snackSodium: Double = 0.2    // 食塩（g）

    // 水1杯の量（ml）
    var waterPerCup: Int = 200

    // コーヒー1杯の設定
    var coffeePerCup: Int = 150      // ml
    var caffeinePerCup: Int = 90     // mg

    // フルーツジュース1杯の設定
    var juicePerCup: Int = 200       // ml
    var juiceCaloriesPerCup: Int = 100  // kcal（フルーツジュース約200ml）
    var juiceSugarPerCup: Double = 24.0 // g（炭水化物/糖質）

    // アルコールのカスタム設定
    var alcoholSettings: [CustomAlcoholSetting] = [
        CustomAlcoholSetting(type: .beer, amountMl: 350, alcoholG: 14.0, displayName: "ビール（缶350ml）"),
        CustomAlcoholSetting(type: .wine, amountMl: 120, alcoholG: 11.5, displayName: "ワイン（グラス）"),
        CustomAlcoholSetting(type: .chuhai, amountMl: 350, alcoholG: 19.6, displayName: "酎ハイ（缶350ml）"),
        CustomAlcoholSetting(type: .nonAlcoholic, amountMl: 0, alcoholG: 0.0, displayName: "ノンアルコール")
    ]

    // 1日の目標値
    var dailyCalorieGoal: Int = 1800     // kcal
    var dailyWaterGoal: Int = 1000       // ml
    var dailyCaffeineLimit: Int = 400    // mg
    var dailyAlcoholLimit: Double = 40.0 // g（WHO基準：1日40g）

    // PFCバランスの目標比率（%）
    var targetProteinPercent: Double = 15.0  // たんぱく質 15%
    var targetFatPercent: Double = 25.0       // 脂質 25%
    var targetCarbsPercent: Double = 60.0     // 炭水化物 60%

    static let defaultSettings = IntakeSettings()

    /// 特定の食事タイプのカロリーを取得
    func caloriesFor(mealType: MealType) -> Int {
        switch mealType {
        case .breakfast: return breakfastCalories
        case .lunch: return lunchCalories
        case .dinner: return dinnerCalories
        case .snack: return snackCalories
        }
    }

    /// 特定の食事タイプの栄養素を取得
    func nutritionFor(mealType: MealType) -> MealNutrition {
        switch mealType {
        case .breakfast:
            return MealNutrition(
                calories: breakfastCalories,
                protein: breakfastProtein,
                fat: breakfastFat,
                carbs: breakfastCarbs,
                sugar: breakfastSugar,
                fiber: breakfastFiber,
                sodium: breakfastSodium
            )
        case .lunch:
            return MealNutrition(
                calories: lunchCalories,
                protein: lunchProtein,
                fat: lunchFat,
                carbs: lunchCarbs,
                sugar: lunchSugar,
                fiber: lunchFiber,
                sodium: lunchSodium
            )
        case .dinner:
            return MealNutrition(
                calories: dinnerCalories,
                protein: dinnerProtein,
                fat: dinnerFat,
                carbs: dinnerCarbs,
                sugar: dinnerSugar,
                fiber: dinnerFiber,
                sodium: dinnerSodium
            )
        case .snack:
            return MealNutrition(
                calories: snackCalories,
                protein: snackProtein,
                fat: snackFat,
                carbs: snackCarbs,
                sugar: snackSugar,
                fiber: snackFiber,
                sodium: snackSodium
            )
        }
    }

    /// 特定のアルコールタイプの設定を取得
    func settingFor(alcoholType: AlcoholType) -> CustomAlcoholSetting? {
        return alcoholSettings.first { $0.type == alcoholType }
    }
}

/// 食事の栄養素情報
struct MealNutrition {
    let calories: Int
    let protein: Double      // たんぱく質（g）
    let fat: Double          // 脂質（g）
    let carbs: Double        // 炭水化物（g）
    let sugar: Double        // 糖質（g）
    let fiber: Double        // 食物繊維（g）
    let sodium: Double       // 塩分（g）
}

/// カスタムアルコール設定
struct CustomAlcoholSetting: Codable, Identifiable {
    var id: String { type.rawValue }
    let type: AlcoholType
    var amountMl: Int
    var alcoholG: Double
    var displayName: String
}

// MARK: - LLM Settings

/// LLM設定
struct LLMSettings: Codable {
    var provider: LLMProvider = .openAI
    var apiKey: String = ""
    var model: String = ""

    static let defaultSettings = LLMSettings()

    /// プロバイダーごとのデフォルトモデル（リーズナブルなプラン）
    var defaultModel: String {
        switch provider {
        case .openAI:
            return "gpt-5.4-mini"  // 現行の低価格モデル
        case .anthropic:
            return "claude-haiku-4-5"  // 現行の低価格モデル
        case .google:
            return "gemini-3.1-flash-lite"  // 現行の低価格モデル
        }
    }

    /// 使用するモデル（設定されていない場合はデフォルト）
    var effectiveModel: String {
        return model.isEmpty ? defaultModel : model
    }
}

/// LLMプロバイダー
enum LLMProvider: String, Codable, CaseIterable {
    case openAI = "OpenAI"
    case anthropic = "Anthropic"
    case google = "Google"

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI (GPT)"
        case .anthropic: return "Anthropic (Claude)"
        case .google: return "Google (Gemini)"
        }
    }

    var endpoint: String {
        switch self {
        case .openAI:
            return "https://api.openai.com/v1/chat/completions"
        case .anthropic:
            return "https://api.anthropic.com/v1/messages"
        case .google:
            return "https://generativelanguage.googleapis.com/v1beta/models"
        }
    }
}

// MARK: - Photo Log

/// フォトログエントリ
struct PhotoLogEntry: Codable, Identifiable {
    var id: String = UUID().uuidString
    var timestamp: Date = Date()
    var imageData: Data?
    var comment: String = ""
    var mealType: MealType?
    var analyzedNutrition: AnalyzedNutrition?
    var isFavorite: Bool = false
    var isPublic: Bool = true   // TOMOのDailyフィードに公開するか

    var image: UIImage? {
        guard let data = imageData else { return nil }
        return UIImage(data: data)
    }
}

/// フォトログ履歴アイテム（画像なし・軽量）
struct PhotoLogHistoryItem: Codable, Identifiable {
    var id: String = UUID().uuidString
    var timestamp: Date = Date()
    var foodName: String = ""
    var comment: String = ""
    var analyzedNutrition: AnalyzedNutrition
    /// 旧形式（UserDefaults 直接保存）。新規保存は thumbnailPath に移行。migration 後は nil になる。
    var thumbnailData: Data?
    /// 新形式: Documents/thumbnails/{id}.jpg へのパス
    var thumbnailPath: String?
    var isFavorite: Bool = false
    var isPublic: Bool = true   // TOMOのDailyフィードに公開するか（旧データ=全て公開）
    var isLiked: Bool = false
    var likeCount: Int = 0
    var feedComments: [FeedComment] = []
    /// HealthKitへ栄養素を保存済みかのフラグ（trueならcachedPhotoLogTotalsから除外して二重計算防止）
    var savedToHealthKit: Bool = false

    // 新フィールド追加後も旧データを正常に読み込めるよう実装
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                 = try c.decodeIfPresent(String.self,             forKey: .id)                 ?? UUID().uuidString
        timestamp          = try c.decodeIfPresent(Date.self,               forKey: .timestamp)          ?? Date()
        foodName           = try c.decodeIfPresent(String.self,             forKey: .foodName)           ?? ""
        comment            = try c.decodeIfPresent(String.self,             forKey: .comment)            ?? ""
        analyzedNutrition  = try c.decode(AnalyzedNutrition.self,          forKey: .analyzedNutrition)
        thumbnailData      = try c.decodeIfPresent(Data.self,               forKey: .thumbnailData)
        thumbnailPath      = try c.decodeIfPresent(String.self,             forKey: .thumbnailPath)
        isFavorite         = try c.decodeIfPresent(Bool.self,               forKey: .isFavorite)         ?? false
        isPublic           = try c.decodeIfPresent(Bool.self,               forKey: .isPublic)           ?? true
        isLiked            = try c.decodeIfPresent(Bool.self,               forKey: .isLiked)            ?? false
        likeCount          = try c.decodeIfPresent(Int.self,                forKey: .likeCount)          ?? 0
        feedComments       = try c.decodeIfPresent([FeedComment].self,      forKey: .feedComments)       ?? []
        savedToHealthKit   = try c.decodeIfPresent(Bool.self,               forKey: .savedToHealthKit)   ?? false
    }

    init(foodName: String = "", comment: String = "",
         analyzedNutrition: AnalyzedNutrition,
         isFavorite: Bool = false, isPublic: Bool = true) {
        self.foodName          = foodName
        self.comment           = comment
        self.analyzedNutrition = analyzedNutrition
        self.isFavorite        = isFavorite
        self.isPublic          = isPublic
    }

    /// フィード等の大きめ表示用（キャッシュヒット時はディスクI/Oなし）
    var thumbnail: UIImage? {
        ThumbnailCache.shared.image(for: "photo_\(id)", maxPixel: 1024) { loadThumbnailData() }
    }

    /// 一覧の小サムネイル用（長辺240pxまで縮小・キャッシュ）
    var smallThumbnail: UIImage? {
        ThumbnailCache.shared.image(for: "photo_sm_\(id)", maxPixel: 240) { loadThumbnailData() }
    }

    /// ファイルキャッシュ優先、旧データは thumbnailData フォールバック
    private func loadThumbnailData() -> Data? {
        if let path = thumbnailPath, let data = ThumbnailFileStore.load(path: path) { return data }
        return thumbnailData
    }

    var displayName: String {
        if !foodName.isEmpty { return foodName }
        if !comment.isEmpty { return comment }
        return "食品 \(calories)kcal"
    }

    var calories: Int { analyzedNutrition.calories }
}

/// LLMが分析した栄養情報
struct AnalyzedNutrition: Codable {
    var description: String = ""  // 食品の説明
    var calories: Int = 0
    var protein: Double = 0.0
    var fat: Double = 0.0
    var carbs: Double = 0.0
    var sugar: Double = 0.0
    var fiber: Double = 0.0
    var sodium: Double = 0.0
    var water: Int = 0  // 水分量（ml）
    var caffeine: Int = 0  // カフェイン量（mg）
    var alcohol: Double = 0.0  // アルコール量（g）
    var confidence: Double = 1.0  // 推定の確度（0.0-1.0）
}

/// EDUログ履歴アイテム（勉強・読書・Duolingo等）
struct FeedComment: Codable, Identifiable {
    var id: String = UUID().uuidString
    var text: String
    var authorName: String
    var authorPhotoURL: String = ""
    var timestamp: Date = Date()

    var authorFirstName: String {
        String(authorName.split(separator: " ").first ?? Substring(authorName))
    }
}

/// 例文1件（外国語テキスト + 日本語訳）
struct ExampleSentence: Codable {
    var text: String           // 外国語の例文
    var translationJA: String? // 日本語訳
}

/// 単語リスト画像から抽出した1単語（テキスト + 読み方、個別にTTS再生可能）
struct VocabWord: Codable, Identifiable {
    var id: String = UUID().uuidString
    var text: String           // 外国語の単語
    var languageCode: String   // 検出言語コード
    var reading: String?       // 発音記号 / ピンイン / カタカナ読み
}

struct EduLogHistoryItem: Codable, Identifiable {
    var id: String = UUID().uuidString
    var timestamp: Date = Date()
    var activityName: String = ""
    var activityEmoji: String = ""
    var comment: String = ""
    var authorName: String = ""
    var authorPhotoURL: String = ""
    /// 旧形式（UserDefaults 直接保存）。新規保存は thumbnailPath に移行。migration 後は nil になる。
    var thumbnailData: Data?
    /// 新形式: Documents/thumbnails/{id}.jpg へのパス
    var thumbnailPath: String?
    var likeCount: Int = 0
    var isLiked: Bool = false
    var feedComments: [FeedComment] = []
    var isPublic: Bool = true

    // Duolingo 外国語フレーズ情報（OCR・翻訳・TTS 用）
    var extractedPhrase: String?         // OCR で抽出した外国語テキスト
    var extractedLanguageCode: String?   // 検出言語コード (zh-Hans, en, fr, es …)
    var translationJA: String?           // 日本語訳
    var pronunciation: String?           // 発音記号 / ピンイン等
    var grammarNote: String?             // 文法解説（コメントに「文法」と入れた場合に LLM 生成）
    var exampleSentences: [ExampleSentence]? // 例文 2 件（コメントに「例文」と入れた場合に LLM 生成）
    var mistakeNote: String?             // 間違えた理由解説（コメントに「ダメな理由」と入れた場合に LLM 生成）
    var relatedWords: [ExampleSentence]? // 関連単語/文章（コメントに「単語」「文章」と入れた場合に LLM 生成）
    var extractedWords: [VocabWord]?     // 画像内の各単語（コメントに「単語」と入れた場合にOCR抽出、読み方付き）

    // 「勉強」読み上げ用：コメントが「勉強」で始まる投稿の写真OCRテキスト＋コメントを
    // 結合した読み上げ対象テキストと、その検出言語（Duolingoフレーズ用フィールドとは独立）
    var readAloudText: String?
    var readAloudLanguageCode: String?

    // 体重ログ用：記録時点の Apple Health 計測値
    var weightKg: Double?              // 体重（kg）
    var bodyFatPercent: Double?        // 体脂肪率（%）

    // FOOD投稿用：共有フィードでカロリーを表示するための値（食事ログのみ）
    var calories: Int?

    // お気に入りフラグ
    var isFavorite: Bool = false

    // 読書・リンク共有用フィールド
    var sharedUrl: String?         // 共有されたURL (Audible/Kindle/図書館など)
    var sharedTitle: String?       // リンクのタイトル（OG取得 or 共有時の名称）
    var sharedDescription: String? // OG description / 本の概要など
    var sharedImageURL: String?    // OG image URL（書影等）

    // 新フィールド追加後も古いデータを読み込めるようカスタムデコーダーを実装
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                    = try c.decodeIfPresent(String.self,         forKey: .id)                    ?? UUID().uuidString
        timestamp             = try c.decodeIfPresent(Date.self,           forKey: .timestamp)             ?? Date()
        activityName          = try c.decodeIfPresent(String.self,         forKey: .activityName)          ?? ""
        activityEmoji         = try c.decodeIfPresent(String.self,         forKey: .activityEmoji)         ?? ""
        comment               = try c.decodeIfPresent(String.self,         forKey: .comment)               ?? ""
        authorName            = try c.decodeIfPresent(String.self,         forKey: .authorName)            ?? ""
        authorPhotoURL        = try c.decodeIfPresent(String.self,         forKey: .authorPhotoURL)        ?? ""
        thumbnailData         = try c.decodeIfPresent(Data.self,           forKey: .thumbnailData)
        thumbnailPath         = try c.decodeIfPresent(String.self,         forKey: .thumbnailPath)
        likeCount             = try c.decodeIfPresent(Int.self,            forKey: .likeCount)             ?? 0
        isLiked               = try c.decodeIfPresent(Bool.self,           forKey: .isLiked)               ?? false
        feedComments          = try c.decodeIfPresent([FeedComment].self,  forKey: .feedComments)          ?? []
        isPublic              = try c.decodeIfPresent(Bool.self,           forKey: .isPublic)              ?? true
        extractedPhrase       = try c.decodeIfPresent(String.self,              forKey: .extractedPhrase)
        extractedLanguageCode = try c.decodeIfPresent(String.self,              forKey: .extractedLanguageCode)
        translationJA         = try c.decodeIfPresent(String.self,              forKey: .translationJA)
        pronunciation         = try c.decodeIfPresent(String.self,              forKey: .pronunciation)
        grammarNote           = try c.decodeIfPresent(String.self,              forKey: .grammarNote)
        exampleSentences      = try c.decodeIfPresent([ExampleSentence].self,   forKey: .exampleSentences)
        mistakeNote           = try c.decodeIfPresent(String.self,              forKey: .mistakeNote)
        relatedWords          = try c.decodeIfPresent([ExampleSentence].self,   forKey: .relatedWords)
        extractedWords        = try c.decodeIfPresent([VocabWord].self,         forKey: .extractedWords)
        weightKg              = try c.decodeIfPresent(Double.self,              forKey: .weightKg)
        bodyFatPercent        = try c.decodeIfPresent(Double.self,              forKey: .bodyFatPercent)
        calories              = try c.decodeIfPresent(Int.self,                 forKey: .calories)
        isFavorite            = try c.decodeIfPresent(Bool.self,               forKey: .isFavorite)        ?? false
        sharedUrl             = try c.decodeIfPresent(String.self,             forKey: .sharedUrl)
        sharedTitle           = try c.decodeIfPresent(String.self,             forKey: .sharedTitle)
        sharedDescription     = try c.decodeIfPresent(String.self,             forKey: .sharedDescription)
        sharedImageURL        = try c.decodeIfPresent(String.self,             forKey: .sharedImageURL)
        readAloudText         = try c.decodeIfPresent(String.self,             forKey: .readAloudText)
        readAloudLanguageCode = try c.decodeIfPresent(String.self,             forKey: .readAloudLanguageCode)
    }

    // 明示的な通常のinitも定義（コード内で直接生成するため）
    init(activityName: String = "", activityEmoji: String = "",
         comment: String = "", authorName: String = "", authorPhotoURL: String = "",
         isPublic: Bool = true) {
        self.activityName   = activityName
        self.activityEmoji  = activityEmoji
        self.comment        = comment
        self.authorName     = authorName
        self.authorPhotoURL = authorPhotoURL
        self.isPublic       = isPublic
    }

    /// フィード等の大きめ表示用（キャッシュヒット時はディスクI/Oなし）
    var thumbnail: UIImage? {
        ThumbnailCache.shared.image(for: "edu_\(id)", maxPixel: 1024) { loadThumbnailData() }
    }

    /// 一覧の小サムネイル用（長辺240pxまで縮小・キャッシュ）
    var smallThumbnail: UIImage? {
        ThumbnailCache.shared.image(for: "edu_sm_\(id)", maxPixel: 240) { loadThumbnailData() }
    }

    /// ファイルキャッシュ優先、旧データは thumbnailData フォールバック
    private func loadThumbnailData() -> Data? {
        if let path = thumbnailPath, let data = ThumbnailFileStore.load(path: path) { return data }
        return thumbnailData
    }

    /// authorNameが空（旧データ）の場合はUserDefaultsキャッシュのユーザー名でフォールバック
    var resolvedAuthorName: String {
        if !authorName.isEmpty { return authorName }
        return UserDefaults.standard.string(forKey: "cachedCurrentUserName") ?? "Kenichi Yoshida"
    }

    /// Googleの表示名から最初のスペース前の名前部分を返す
    var authorFirstName: String {
        let name = resolvedAuthorName
        return String(name.split(separator: " ").first ?? Substring(name))
    }
}
