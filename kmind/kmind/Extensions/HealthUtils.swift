import SwiftUI

// MARK: - HRV 閾値定数（kmind ローカルコピー）
//
// ⚠️ KFitCore.HRVThreshold（Packages/KFitCore/Sources/KFitCore/KFitHRV.swift）と
//    同一の値を維持すること。値を変更する場合は KFitCore 側も同時に更新する。
//
// TODO: kmind ターゲットに KFitCore を追加したら、この定義を削除して
//       import KFitCore に置き換える。

enum HRVThreshold {
    static let excellent: Double = 60   // ≥60 → 良好
    static let moderate: Double  = 40   // ≥40 → 中程度
    static let low: Double       = 20   // ≥20 → 要注意
}

// MARK: - HRV ストレス指数モデル
//
// KFitCore.MindStressInfo と同一定義。
// KFitCore 統合後はこの定義を削除し import KFitCore を使用する。

struct MindStressInfo {
    let score: Int
    let label: String
    let englishLabel: String
    let color: Color
}

// MARK: - HRV → ストレス指数変換（0–100）
//
// KFitCore.stressInfoFromHRV と同一アルゴリズム。
// KFitCore 統合後はこの関数を削除し KFitCore の public 版を使用する。

/// HRV 値からストレス指数を計算する共有関数。
/// score が -1 の場合はデータなし（HRV ≤ 0）。
func stressInfoFromHRV(_ hrv: Double) -> MindStressInfo {
    guard hrv > 0 else {
        return MindStressInfo(score: -1, label: "不明", englishLabel: "Unknown", color: Color.duoSubtitle)
    }
    let score: Int = {
        if hrv >= 100                       { return 5 }
        if hrv >= 80                        { return Int(5  + (100 - hrv) / 20 * 10) }
        if hrv >= HRVThreshold.excellent    { return Int(15 + (80  - hrv) / 20 * 20) }
        if hrv >= HRVThreshold.moderate     { return Int(35 + (HRVThreshold.excellent - hrv) / 20 * 25) }
        if hrv >= HRVThreshold.low          { return Int(60 + (HRVThreshold.moderate  - hrv) / 20 * 20) }
        return Int(min(95, 80 + (HRVThreshold.low - hrv) / 20 * 15))
    }()
    switch score {
    case ..<30: return MindStressInfo(score: score, label: "低い",   englishLabel: "Low",      color: Color.duoGreen)
    case ..<55: return MindStressInfo(score: score, label: "普通",   englishLabel: "Normal",   color: Color(red: 0.4, green: 0.75, blue: 0.1))
    case ..<75: return MindStressInfo(score: score, label: "やや高", englishLabel: "Elevated", color: Color.duoOrange)
    default:    return MindStressInfo(score: score, label: "高い",   englishLabel: "High",     color: Color(hex: "#FF4B4B"))
    }
}

// MARK: - ムーミン名言DB（ストレスレベル対応）

struct MoominQuote {
    let text: String
    let speaker: String
}

/// ストレスレベルに応じたムーミン名言を返す。
/// - Parameters:
///   - stress: `stressInfoFromHRV` が返した `MindStressInfo`。
///   - seed: 0 以上を指定するとその値で名言を選択（頻繁なローテーション用）。
///           -1（デフォルト）は当日の日付をシードにする（毎日変わる）。
func moominQuoteForStress(_ stress: MindStressInfo, seed: Int = -1) -> MoominQuote {
    let quotes: [MoominQuote]
    switch stress.score {
    case ..<0:
        quotes = [
            MoominQuote(text: "ね、なにが起こったって、わたしにはちゃんとあなたがわかるのよ", speaker: "ムーミンママ"),
            MoominQuote(text: "人の目なんか気にしないで、思うとおりに暮らしていればいいのさ", speaker: "スナフキン"),
            MoominQuote(text: "大切なのは、自分のしたいことを自分で知ってるってことだよ", speaker: "スナフキン"),
            MoominQuote(text: "ものごとって、みんなとてもあいまいなのよ。まさにそのことが、わたしを安心させるんだけれどもね", speaker: "トゥーティッキ"),
            MoominQuote(text: "もうだいじょうぶよ、ほら、いらっしゃい。", speaker: "ムーミンママ"),
            MoominQuote(text: "なにかためしてみようってときには、どうしたって危険がともなうんだ", speaker: "スナフキン"),
        ]
    case ..<30:
        quotes = [
            MoominQuote(text: "道や川ってふしぎだなあ。ずっと先までつづくのを見ていると、遠くへ行きたくてたまらなくなっちゃう。どこまで行くのかなって、ついていきたくなるんだ……", speaker: "スニフ"),
            MoominQuote(text: "食べることもわすれるほど、しあわせになれるんだね！", speaker: "スニフ"),
            MoominQuote(text: "長い旅行に必要なのは大きなカバンじゃなく、口ずさめる一つの歌さ", speaker: "スナフキン"),
            MoominQuote(text: "自分できれいだと思うものは、なんでも僕のものさ。その気になれば、世界中でもね", speaker: "スナフキン"),
            MoominQuote(text: "生きるなんて、だれにだってできるじゃないか", speaker: "ムーミンパパ"),
            MoominQuote(text: "月の光をごらんよ。なんてあったかいんだろ。ぼく、飛べそうな気がするよ！", speaker: "ムーミントロール"),
            MoominQuote(text: "これから、なにもかもがうまくいくんだ", speaker: "ムーミントロール"),
            MoominQuote(text: "今だったら、どんなことだってできるわ。ま、なにもしないけど。でも、なんだって自分のやりたいと思ったことをするっていうのは、すてきよね！", speaker: "ミムラねえさん"),
            MoominQuote(text: "劇場は、世界でいちばん大事なものなんだ。そこへ行けばだれでも、自分にどんな生き方ができるか、見ることができる", speaker: "エンマ"),
            MoominQuote(text: "友だちが、それぞれ自分にぴったりのことを見つけられるのって、うれしいものでしょ？", speaker: "ムーミンママ"),
            MoominQuote(text: "同じところに住みついていたんじゃ、冒険家になれるもんか！", speaker: "ムーミンパパ"),
            MoominQuote(text: "世の中には、すばらしいことがいっぱいあるが、そういうものはそれにふさわしい人物でなくては開かれんのだ", speaker: "ムーミンパパ"),
        ]
    case ..<55:
        quotes = [
            MoominQuote(text: "大切なのは、自分のしたいことを自分で知ってるってことだよ", speaker: "スナフキン"),
            MoominQuote(text: "「そのうち」なんて当てにならないな。いまがその時さ", speaker: "スナフキン"),
            MoominQuote(text: "いつも希望を胸に生きるって、いいことよね", speaker: "リトルミイ"),
            MoominQuote(text: "さあ、明日もまた、長い一日になるでしょうよ。しかも、はじめからおわりまで自分のものよ。とてもすてきなことじゃない！", speaker: "ムーミンママ"),
            MoominQuote(text: "たまには変化も必要ですよ。わたしたちはおたがいに、あまりにも、あたりまえのことをあたりまえと思いすぎるのじゃない？", speaker: "ムーミンママ"),
            MoominQuote(text: "しないではいられないということと、しなければならないということは、ちがうわよね。", speaker: "フィリフヨンカ"),
            MoominQuote(text: "なんにでも、時期というものがあってね。今は、はたらくときなのさ", speaker: "ヘムレン"),
            MoominQuote(text: "人と違った考えを持つことは一向にかまわないさ。でも、その考えを無理やり他の人に押し付けてはいけないなあ", speaker: "スナフキン"),
            MoominQuote(text: "心の繋がった仲間こそ、ルビーにも勝る美しいルビーさ。", speaker: "スナフキン"),
            MoominQuote(text: "今夜は歌のことだけを考えよう。明日は明日の風が吹くさ", speaker: "スナフキン"),
            MoominQuote(text: "ぜったいにたしかなもの―そういうものがあるんだよ。たとえば、海の潮流とか、季節のうつり変わりとか、朝になったら日がのぼるとかさ", speaker: "ムーミンパパ"),
            MoominQuote(text: "ときには思いついたことをやってみよ、ですわ", speaker: "フィリフヨンカ"),
        ]
    case ..<75:
        quotes = [
            MoominQuote(text: "あんまりおおげさに考えすぎないようにしろよ。なんでも、大きくしすぎちゃ、だめだぜ", speaker: "スナフキン"),
            MoominQuote(text: "ちょっと眠るよ。ちょいちょい、寝ている間に、問題が自然にとけることがあるからな。頭はほったらかしておくと、よく働くものなんだ", speaker: "ムーミンパパ"),
            MoominQuote(text: "眠っているときは、休んでいるときだ。春、また元気を取り戻すために", speaker: "スナフキン"),
            MoominQuote(text: "ゆううつになんか、ならないで。ぼくたちが帰ったら、ママはごちそうを作って待ってるんだ", speaker: "ムーミントロール"),
            MoominQuote(text: "もう泣くのはやめて、サンドイッチを食べなよ。", speaker: "ムーミントロール"),
            MoominQuote(text: "ものごとって、みんなとてもあいまいなのよ。まさにそのことが、わたしを安心させるんだけれどもね", speaker: "トゥーティッキ"),
            MoominQuote(text: "あんまりだれかを崇拝すると、本物の自由はえられないんだぜ。そういうものなのさ", speaker: "スナフキン"),
            MoominQuote(text: "生きるって、すばらしいことだなあ。どんなものでも、なんの理由もなしにあべこべになったりするんだねえ", speaker: "ムーミントロール"),
            MoominQuote(text: "なんだっておもしろいのよ—多かれ、少なかれ", speaker: "リトルミイ"),
            MoominQuote(text: "だけど、こんなに泣いてもいい理由があるときには、泣けるだけ泣いておくの", speaker: "ミーサ"),
            MoominQuote(text: "明日という日があるじゃないの", speaker: "ムーミンママ"),
        ]
    default:
        quotes = [
            MoominQuote(text: "どんなことでも、自分で見つけださなきゃいけないものよ。そうして自分ひとりで、それを乗りこえるんだわ", speaker: "トゥーティッキ"),
            MoominQuote(text: "ほら、元気をなくしてはだめだよ。もう一回！", speaker: "ヘムレン"),
            MoominQuote(text: "本当の勇気とは自分の弱い心に打ち勝つことだよ。包み隠さず本当のことを正々堂々と言える者こそ本当の勇気のある強い者なんだ", speaker: "スナフキン"),
            MoominQuote(text: "一度決めたら最後までやりぬく、それが俺の人生さ", speaker: "スナフキン"),
            MoominQuote(text: "あのさ、たたかうってことをおぼえないかぎり、あんたには自分の顔を持てるわけないわ", speaker: "リトルミイ"),
            MoominQuote(text: "飢えを知っていればこそ、ぼくは二度とそうなりたくないと努力するだけだよ", speaker: "スナフキン"),
            MoominQuote(text: "なにかちがうこと、なにかあたらしいことをしなくちゃな。なにかすごく大きなことをやるんだ", speaker: "ムーミンパパ"),
            MoominQuote(text: "いつでも日曜日だったら、すばらしいじゃないか。そういう気持ちこそ、われわれが見失っていたものなんだ", speaker: "ムーミンパパ"),
            MoominQuote(text: "おだやかな人生なんてあるわけがない", speaker: "スナフキン"),
            MoominQuote(text: "さあ、さっと思い立ったときに決心しなくては。決心がにぶらないうちに、すばやく実行しなくては", speaker: "フィリフヨンカ"),
            MoominQuote(text: "だれだって、ときにはおこるほうがいいのよ。どんな小さなクニットだって、おこる権利はあるのよ", speaker: "リトルミイ"),
        ]
    }
    let effectiveSeed: Int
    if seed >= 0 {
        effectiveSeed = seed
    } else {
        effectiveSeed = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
    }
    return quotes[effectiveSeed % quotes.count]
}

// MARK: - マインドフルネス時間フォーマット

func formatMindfulMinutes(_ minutes: Double) -> String {
    if minutes < 1 { return "\(Int(minutes * 60))秒" }
    if abs(minutes.rounded() - minutes) < 0.05 { return "\(Int(minutes.rounded()))分" }
    return String(format: "%.1f分", minutes)
}
