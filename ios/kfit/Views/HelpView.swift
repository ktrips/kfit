import SwiftUI

struct HelpItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let content: String
}

private let helpItems: [HelpItem] = [
    HelpItem(
        icon: "💪",
        title: "トレーニングの記録方法",
        content: """
        1. ダッシュボードの「今日のDuoFit!」ボタンをタップ
        2. 種目（プッシュアップ・スクワットなど）を選択
        3. ＋ ボタンでレップ数を入力、または「モーション自動検出」をONにする
        4. 「✓ トレーニングを記録」で保存
        5. XP が獲得されてダッシュボードに戻ります
        """
    ),
    HelpItem(
        icon: "⭐",
        title: "XP（ポイント）の仕組み",
        content: """
        1 rep ごとに以下の XP が加算されます：
        • プッシュアップ・スクワット・ランジ：2 XP / rep
        • シットアップ・プランク：1 XP / rep（秒）
        • バーピー：5 XP / rep
        獲得 XP はダッシュボードのポイントカードに表示されます。
        """
    ),
    HelpItem(
        icon: "🔥",
        title: "ストリーク（連続記録）",
        content: """
        毎日トレーニングを記録すると連続日数が伸びます。
        • 週2日まで休息日を設けても streak は継続します
        • 3日以上空くとリセットされます
        • 90日連続達成が最初の大きな目標です
        """
    ),
    HelpItem(
        icon: "🎯",
        title: "週間目標・1日全体の目標",
        content: """
        ダッシュボードの目標カードから設定できます。
        【週間目標】
        • 各種目の 1日のrep数 を入力
        • 週間目標は自動で × 5日（週2日休息）計算
        【1日全体の目標】
        • ワークアウト時間・スタンド時間の目標
        • 睡眠スコア目標（例: 80点以上）
        • PFCバランススコア目標（例: 80点以上）
        目標はダッシュボードの進捗でリアルタイム確認できます。
        """
    ),
    HelpItem(
        icon: "😴",
        title: "睡眠スコアの見方",
        content: """
        Apple Healthの睡眠データを分析して0〜100点でスコア化します。
        【スコアの内訳】
        • 睡眠時間（最大40点）: 目標7時間±30分以内で満点
        • 深い睡眠（最大30点）: 総睡眠の15〜20%が理想
        • REM睡眠（最大20点）: 総睡眠の20〜25%が理想
        • 連続性（最大10点）: 途中覚醒が少ないほど高得点
        【評価】
        90点以上: 最高 / 80点以上: 良好 / 70点以上: 普通
        50点以上: 要改善 / 50点未満: 不十分
        ダッシュボードの「睡眠スコア」カードで確認できます。
        """
    ),
    HelpItem(
        icon: "🥗",
        title: "PFCバランス分析の見方",
        content: """
        Apple Healthに記録された食事データからPFC（たんぱく質・脂質・炭水化物）を取得し、バランスをスコア化します。
        【目標比率の目安】
        • たんぱく質 💪: 15%
        • 脂質 🥑: 25%
        • 炭水化物 🍚: 60%
        スコアが高いほど目標比率に近いバランスで食事できています。
        ダッシュボードのドーナツ円グラフで比率を確認できます。
        「食事タブ」ではPFC詳細（g数・%）と評価コメントが表示されます。
        """
    ),
    HelpItem(
        icon: "📸",
        title: "フォトログ（AI食事分析）",
        content: """
        食事の写真を撮影またはライブラリから選択すると、AIが自動でカロリーとPFCを分析します。
        1. ダッシュボードのクイックメニュー → 「フォトログ」をタップ
        2. カメラで撮影 または 写真ライブラリから選択
        3. AIが食品を認識してカロリー・PFCを推定
        4. 確認して「記録する」で保存
        【対応AIモデル】
        • OpenAI GPT-4o
        • Anthropic Claude
        • Google Gemini 2.5 Flash
        設定画面からAPIキーとモデルを選択できます。
        """
    ),
    HelpItem(
        icon: "📅",
        title: "履歴の確認",
        content: """
        メニュー → 「履歴」から過去14日間のトレーニング記録を確認できます。
        各日のXP合計・種目別rep数が表示されます。
        """
    ),
    HelpItem(
        icon: "📱",
        title: "モーション自動検出（iPhone）",
        content: """
        トレーニング記録画面で「モーション自動検出」をONにすると、
        iPhoneの加速度センサーでrepを自動カウントします。
        • フォームスコアも同時に計算されます
        • Apple Watch からもモーション検出が使えます
        • Watch でのトレーニングはiPhoneに自動同期されます
        """
    ),
    HelpItem(
        icon: "🧘",
        title: "マインドフルネス",
        content: """
        ダッシュボードのマインドフルネスボタンをタップすると、Apple Watchのマインドフルネスアプリが直接起動します。
        • セッション完了後、Apple Healthに自動記録されます
        • 記録されたマインドフルネス時間はダッシュボードに反映されます
        • Watch が手元にない場合は iPhone の「マインドフルネス」アプリをご利用ください
        """
    ),
    HelpItem(
        icon: "🔐",
        title: "アカウント・データについて",
        content: """
        • Google アカウントでログインします
        • データは Firebase に安全に保存されます
        • Web・iOS・Watch のデータはリアルタイム同期されます
        • ログアウトはダッシュボード右下のボタンから行えます
        """
    ),
]

struct HelpView: View {
    @State private var openId: UUID? = helpItems.first?.id

    var body: some View {
        ZStack {
            Color.duoBg.ignoresSafeArea()

            ScrollView {
                    VStack(spacing: 16) {
                        // ヘッダー
                        HStack(spacing: 12) {
                            Image("mascot")
                                .resizable().scaledToFit().frame(width: 52, height: 52)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.duoGreen, lineWidth: 2))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ヘルプ・使い方")
                                    .font(.title3).fontWeight(.black).foregroundColor(Color.duoDark)
                                Text("DuoFit の使い方ガイド")
                                    .font(.caption).foregroundColor(Color.duoSubtitle)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                        // アコーディオン
                        ForEach(helpItems) { item in
                            accordionItem(item)
                        }

                        // バージョン情報
                        HStack(spacing: 12) {
                            Text("ℹ️").font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("DuoFit v0.6.0")
                                    .font(.subheadline).fontWeight(.black)
                                Text("Web・iOS・Apple Watch 対応")
                                    .font(.caption).foregroundColor(Color.duoSubtitle)
                            }
                            Spacer()
                        }
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(14)
                        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
                        .padding(.horizontal, 20)

                        Spacer(minLength: 40)
                    }
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("ヘルプ")
            .navigationBarTitleDisplayMode(.inline)
    }

    private func accordionItem(_ item: HelpItem) -> some View {
        let isOpen = openId == item.id

        return VStack(spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    openId = isOpen ? nil : item.id
                }
            }) {
                HStack(spacing: 12) {
                    Text(item.icon).font(.title3)
                    Text(item.title)
                        .font(.subheadline).fontWeight(.black)
                        .foregroundColor(Color.duoDark)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundColor(Color.duoSubtitle)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }

            if isOpen {
                Divider().padding(.horizontal, 16)
                Text(item.content)
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundColor(Color.duoDark)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
        .padding(.horizontal, 20)
    }
}

#Preview {
    HelpView()
}
