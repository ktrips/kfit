import Foundation
import SwiftUI

// MARK: - ムーミン名言（kfit / kmind 共通・単一ソース）
// ⚠️ このファイルが単一の真実のソース。
//    kfit/Extensions/HealthUtils.swift の MoominQuote / moominQuoteForStress
//    kmind 側の同等実装は KFitCore 追加後に削除すること。

public struct MoominQuote: Identifiable {
    public let id = UUID()
    public let text: String
    public let speaker: String
    /// ストレスカテゴリ（JSON DB との対応付け用）
    public let stressCategory: StressCategory

    public enum StressCategory: String, CaseIterable {
        case unknown  = "unknown"   // HRVデータなし
        case low      = "low"       // ストレス低（良好）
        case normal   = "normal"    // 普通
        case elevated = "elevated"  // やや高
        case high     = "high"      // 高い
    }

    public init(text: String, speaker: String, stressCategory: StressCategory = .normal) {
        self.text = text
        self.speaker = speaker
        self.stressCategory = stressCategory
    }
}

// MARK: - 全名言データベース

public extension MoominQuote {
    static let allQuotes: [MoominQuote] = unknownQuotes + lowQuotes + normalQuotes + elevatedQuotes + highQuotes

    static let unknownQuotes: [MoominQuote] = [
        MoominQuote(text: "ね、なにが起こったって、わたしにはちゃんとあなたがわかるのよ", speaker: "ムーミンママ", stressCategory: .unknown),
        MoominQuote(text: "人の目なんか気にしないで、思うとおりに暮らしていればいいのさ", speaker: "スナフキン", stressCategory: .unknown),
        MoominQuote(text: "大切なのは、自分のしたいことを自分で知ってるってことだよ", speaker: "スナフキン", stressCategory: .unknown),
        MoominQuote(text: "ものごとって、みんなとてもあいまいなのよ。まさにそのことが、わたしを安心させるんだけれどもね", speaker: "トゥーティッキ", stressCategory: .unknown),
        MoominQuote(text: "もうだいじょうぶよ、ほら、いらっしゃい。", speaker: "ムーミンママ", stressCategory: .unknown),
        MoominQuote(text: "なにかためしてみようってときには、どうしたって危険がともなうんだ", speaker: "スナフキン", stressCategory: .unknown),
    ]

    static let lowQuotes: [MoominQuote] = [
        MoominQuote(text: "道や川ってふしぎだなあ。ずっと先までつづくのを見ていると、遠くへ行きたくてたまらなくなっちゃう。", speaker: "スニフ", stressCategory: .low),
        MoominQuote(text: "食べることもわすれるほど、しあわせになれるんだね！", speaker: "スニフ", stressCategory: .low),
        MoominQuote(text: "長い旅行に必要なのは大きなカバンじゃなく、口ずさめる一つの歌さ", speaker: "スナフキン", stressCategory: .low),
        MoominQuote(text: "自分できれいだと思うものは、なんでも僕のものさ。その気になれば、世界中でもね", speaker: "スナフキン", stressCategory: .low),
        MoominQuote(text: "生きるなんて、だれにだってできるじゃないか", speaker: "ムーミンパパ", stressCategory: .low),
        MoominQuote(text: "月の光をごらんよ。なんてあったかいんだろ。ぼく、飛べそうな気がするよ！", speaker: "ムーミントロール", stressCategory: .low),
        MoominQuote(text: "これから、なにもかもがうまくいくんだ", speaker: "ムーミントロール", stressCategory: .low),
        MoominQuote(text: "今だったら、どんなことだってできるわ。ま、なにもしないけど。でも、なんだって自分のやりたいと思ったことをするっていうのは、すてきよね！", speaker: "ミムラねえさん", stressCategory: .low),
        MoominQuote(text: "劇場は、世界でいちばん大事なものなんだ。そこへ行けばだれでも、自分にどんな生き方ができるか、見ることができる", speaker: "エンマ", stressCategory: .low),
        MoominQuote(text: "友だちが、それぞれ自分にぴったりのことを見つけられるのって、うれしいものでしょ？", speaker: "ムーミンママ", stressCategory: .low),
        MoominQuote(text: "同じところに住みついていたんじゃ、冒険家になれるもんか！", speaker: "ムーミンパパ", stressCategory: .low),
        MoominQuote(text: "世の中には、すばらしいことがいっぱいあるが、そういうものはそれにふさわしい人物でなくては開かれんのだ", speaker: "ムーミンパパ", stressCategory: .low),
    ]

    static let normalQuotes: [MoominQuote] = [
        MoominQuote(text: "大切なのは、自分のしたいことを自分で知ってるってことだよ", speaker: "スナフキン", stressCategory: .normal),
        MoominQuote(text: "「そのうち」なんて当てにならないな。いまがその時さ", speaker: "スナフキン", stressCategory: .normal),
        MoominQuote(text: "いつも希望を胸に生きるって、いいことよね", speaker: "リトルミイ", stressCategory: .normal),
        MoominQuote(text: "さあ、明日もまた、長い一日になるでしょうよ。しかも、はじめからおわりまで自分のものよ。とてもすてきなことじゃない！", speaker: "ムーミンママ", stressCategory: .normal),
        MoominQuote(text: "たまには変化も必要ですよ。わたしたちはおたがいに、あまりにも、あたりまえのことをあたりまえと思いすぎるのじゃない？", speaker: "ムーミンママ", stressCategory: .normal),
        MoominQuote(text: "しないではいられないということと、しなければならないということは、ちがうわよね。", speaker: "フィリフヨンカ", stressCategory: .normal),
        MoominQuote(text: "なんにでも、時期というものがあってね。今は、はたらくときなのさ", speaker: "ヘムレン", stressCategory: .normal),
        MoominQuote(text: "人と違った考えを持つことは一向にかまわないさ。でも、その考えを無理やり他の人に押し付けてはいけないなあ", speaker: "スナフキン", stressCategory: .normal),
        MoominQuote(text: "心の繋がった仲間こそ、ルビーにも勝る美しいルビーさ。", speaker: "スナフキン", stressCategory: .normal),
        MoominQuote(text: "今夜は歌のことだけを考えよう。明日は明日の風が吹くさ", speaker: "スナフキン", stressCategory: .normal),
        MoominQuote(text: "ぜったいにたしかなもの―そういうものがあるんだよ。たとえば、海の潮流とか、季節のうつり変わりとか、朝になったら日がのぼるとかさ", speaker: "ムーミンパパ", stressCategory: .normal),
        MoominQuote(text: "ときには思いついたことをやってみよ、ですわ", speaker: "フィリフヨンカ", stressCategory: .normal),
    ]

    static let elevatedQuotes: [MoominQuote] = [
        MoominQuote(text: "あんまりおおげさに考えすぎないようにしろよ。なんでも、大きくしすぎちゃ、だめだぜ", speaker: "スナフキン", stressCategory: .elevated),
        MoominQuote(text: "ちょっと眠るよ。ちょいちょい、寝ている間に、問題が自然にとけることがあるからな。頭はほったらかしておくと、よく働くものなんだ", speaker: "ムーミンパパ", stressCategory: .elevated),
        MoominQuote(text: "眠っているときは、休んでいるときだ。春、また元気を取り戻すために", speaker: "スナフキン", stressCategory: .elevated),
        MoominQuote(text: "ゆううつになんか、ならないで。ぼくたちが帰ったら、ママはごちそうを作って待ってるんだ", speaker: "ムーミントロール", stressCategory: .elevated),
        MoominQuote(text: "もう泣くのはやめて、サンドイッチを食べなよ。", speaker: "ムーミントロール", stressCategory: .elevated),
        MoominQuote(text: "ものごとって、みんなとてもあいまいなのよ。まさにそのことが、わたしを安心させるんだけれどもね", speaker: "トゥーティッキ", stressCategory: .elevated),
        MoominQuote(text: "あんまりだれかを崇拝すると、本物の自由はえられないんだぜ。そういうものなのさ", speaker: "スナフキン", stressCategory: .elevated),
        MoominQuote(text: "生きるって、すばらしいことだなあ。どんなものでも、なんの理由もなしにあべこべになったりするんだねえ", speaker: "ムーミントロール", stressCategory: .elevated),
        MoominQuote(text: "なんだっておもしろいのよ—多かれ、少なかれ", speaker: "リトルミイ", stressCategory: .elevated),
        MoominQuote(text: "だけど、こんなに泣いてもいい理由があるときには、泣けるだけ泣いておくの", speaker: "ミーサ", stressCategory: .elevated),
        MoominQuote(text: "明日という日があるじゃないの", speaker: "ムーミンママ", stressCategory: .elevated),
    ]

    static let highQuotes: [MoominQuote] = [
        MoominQuote(text: "どんなことでも、自分で見つけださなきゃいけないものよ。そうして自分ひとりで、それを乗りこえるんだわ", speaker: "トゥーティッキ", stressCategory: .high),
        MoominQuote(text: "ほら、元気をなくしてはだめだよ。もう一回！", speaker: "ヘムレン", stressCategory: .high),
        MoominQuote(text: "本当の勇気とは自分の弱い心に打ち勝つことだよ。包み隠さず本当のことを正々堂々と言える者こそ本当の勇気のある強い者なんだ", speaker: "スナフキン", stressCategory: .high),
        MoominQuote(text: "一度決めたら最後までやりぬく、それが俺の人生さ", speaker: "スナフキン", stressCategory: .high),
        MoominQuote(text: "あのさ、たたかうってことをおぼえないかぎり、あんたには自分の顔を持てるわけないわ", speaker: "リトルミイ", stressCategory: .high),
        MoominQuote(text: "飢えを知っていればこそ、ぼくは二度とそうなりたくないと努力するだけだよ", speaker: "スナフキン", stressCategory: .high),
        MoominQuote(text: "明日という日があるじゃないの", speaker: "ムーミンママ", stressCategory: .high),
        MoominQuote(text: "なにかちがうこと、なにかあたらしいことをしなくちゃな。なにかすごく大きなことをやるんだ", speaker: "ムーミンパパ", stressCategory: .high),
        MoominQuote(text: "いつでも日曜日だったら、すばらしいじゃないか。そういう気持ちこそ、われわれが見失っていたものなんだ", speaker: "ムーミンパパ", stressCategory: .high),
        MoominQuote(text: "おだやかな人生なんてあるわけがない", speaker: "スナフキン", stressCategory: .high),
        MoominQuote(text: "さあ、さっと思い立ったときに決心しなくては。決心がにぶらないうちに、すばやく実行しなくては", speaker: "フィリフヨンカ", stressCategory: .high),
    ]
}

// MARK: - ストレスレベルに合った名言を返す

/// ストレスレベルに合ったムーミン名言を返す。
/// - Parameters:
///   - stress: HRV から計算したストレス指数
///   - seed: ≥0 で固定インデックス指定。-1（デフォルト）で日付ベースのシード
public func moominQuoteForStress(_ stress: MindStressInfo, seed: Int = -1) -> MoominQuote {
    let candidates: [MoominQuote]
    switch stress.score {
    case ..<0:  candidates = MoominQuote.unknownQuotes
    case ..<30: candidates = MoominQuote.lowQuotes
    case ..<55: candidates = MoominQuote.normalQuotes
    case ..<75: candidates = MoominQuote.elevatedQuotes
    default:    candidates = MoominQuote.highQuotes
    }
    let effectiveSeed: Int = seed >= 0
        ? seed
        : (Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1)
    return candidates[effectiveSeed % candidates.count]
}
