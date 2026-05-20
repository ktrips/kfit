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
        1. ダッシュボードの Fitingo ボタンをタップ
        2. 種目（プッシュアップ・スクワットなど）を選択
        3. ＋ ボタンでレップ数を入力、または「モーション自動検出」をONにする
        4. 「✓ トレーニングを記録」で保存
        5. XP が獲得されてダッシュボードに戻ります
        【Fitingo ボタンの表情】
        • 目標に対して遅れているとき → 炎マスコット（🔥）
        • 順調・達成済みのとき → 通常マスコット
        【今日の状況（展開）】
        今日の状況カードをタップすると履歴が展開されます。
        • トレーニング: 種目ごとにグループ表示。タップで個別セットの時刻・rep・XPを確認
        • Breathe / Reflect / マインドフルネス: セッションごとに時刻と分数を表示
        • 体重: 今日の計測値と体脂肪率
        • 食事・水分: 記録時刻と数値
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
        title: "時間帯別目標の設定",
        content: """
        設定 → 「時間帯別目標」で朝・昼・午後・夜の4時間帯にそれぞれ目標を設定できます。
        【設定できる目標】
        • 💪 トレーニングセット数
        • 🧘 マインドフルネス回数（Apple Watch の1分セッションをカウント）
        • 🤸 ストレッチ目標（Reflect の合計分数。例: 3分設定なら3分のReflectで達成）
        • 🍽️ 食事記録・💧 水分記録
        • カスタムアクティビティ（任意の習慣を追加可能）
        【週間目標・1日全体の目標】
        • ワークアウト時間・スタンド時間の目標
        • 睡眠スコア目標（例: 80点以上）
        • PFCバランススコア目標（例: 80点以上）
        • アクティビティリング達成を目標に含めることも可能
        """
    ),
    HelpItem(
        icon: "🤸",
        title: "ストレッチ目標（Reflect連携）",
        content: """
        時間帯別目標でストレッチを有効にすると、Apple Watch の Reflect セッションが自動連携されます。
        【仕組み】
        • 目標は「分数」で設定（デフォルト: 3分）
        • 設定した時間帯内で Reflect を合計N分行うと達成
        • 例: 3分設定 → 3分のReflect1回 or 1分×3回で達成
        【マインドフルネスとの違い】
        • マインドフルネス回数: 1分以内の短いセッション（Breathe等）をカウント
        • ストレッチ: Reflect セッションの合計分数をカウント
        ダッシュボードの時間帯行に 🤸 アイコンで進捗が確認できます。
        """
    ),
    HelpItem(
        icon: "😴",
        title: "睡眠スコアの見方",
        content: """
        Apple Healthの睡眠データを分析して0〜100点でスコア化します。
        【スコアの計算式】
        • 睡眠時間（最大50点）: 実績 ÷ 目標時間 × 50（目標達成で満点）
        • 就寝時刻（最大30点）: 24:00以前なら満点。それ以降は10分遅れるごとに−1点
        • 睡眠中断（最大20点）: 覚醒時間が0なら満点。覚醒割合20%以上で0点
        【評価】
        90点以上: 最高 / 80点以上: 良好 / 70点以上: 普通
        50点以上: 要改善 / 50点未満: 不十分
        【カードの見方】
        スコアサークル（左）と評価ラベル・合計/深い/REM/コアの統計チップが1行で表示されます。
        その下にステージバー（各睡眠ステージを時間軸で色分け）と凡例が続きます。
        【データ取得の精度】
        Apple Watch のステージデータ（コア・深い・REM）を優先取得し、iPhoneの「就寝中」記録と重複しないよう自動除外します。対象時間帯は前日15:00〜当日14:00。
        """
    ),
    HelpItem(
        icon: "🫀",
        title: "HRV・ストレス推定",
        content: """
        Apple Watchが計測した心拍変動（HRV）から、今日のストレス状態を推定します。
        【HRVとは】
        心拍間隔のばらつき（ms）。高いほど自律神経が整っており、ストレスが低い状態を示します。
        【ストレススコアの計算】
        平均HRV から 0〜100 のストレス値を算出します：
        • HRV 80ms以上 → ストレス 低い
        • HRV 60〜80ms → ストレス やや低い
        • HRV 40〜60ms → ストレス 中程度
        • HRV 20〜40ms → ストレス やや高い
        • HRV 20ms未満 → ストレス 高い
        【カードの見方】
        HealthView の「心拍変動（HRV）」カードにスコア数値・レベルラベル・バーグラフで表示されます。
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
        icon: "🏃",
        title: "アクティビティリング・体重",
        content: """
        ダッシュボードのアクティビティカードで、Apple Watchの3つのリングと体組成を確認できます。
        【アクティビティスコア】
        ムーブ・エクササイズ・スタンドの各リング達成率を平均した総合スコア（0〜100%）を
        カードのタイトル行に表示します。
        • 100%以上: 緑（達成）
        • 70〜99%: オレンジ
        • 69%以下: 赤
        【体重・体脂肪】
        カード右側に Apple Health の最新体重（kg）と体脂肪率（%）を表示。
        その下に直近7日間の増減（例: +0.3 kg/7日）を小さく表示します。
        今日 体重を計測すると、時間帯別目標の「体重計測」が達成となります。
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
        • 1分以内の短いセッション（Breathe等）が時間帯のマインドフルネス回数にカウントされます
        • Reflect セッションはストレッチ目標（分数）にカウントされます（🤸）
        • Watch が手元にない場合は iPhone の「マインドフルネス」アプリをご利用ください
        """
    ),
    HelpItem(
        icon: "🔲",
        title: "ホーム画面ウィジェット",
        content: """
        ホーム画面にFitinoウィジェットを追加すると、アプリを開かずに今日の進捗を確認できます。
        【ウィジェットサイズ】
        • 小（2×2）: ストリーク・達成度・XP
        • 横長（2×4）: 上記指標 + Fitingoアイコン・日付・時刻
        • 大（2×4縦長）: 指標 + 目標別進捗リスト
        【追加方法】
        ホーム画面を長押し → 左上「＋」→「Fitingo」を検索 → サイズを選択
        【データ反映】
        アプリ起動時にウィジェットデータが更新されます（最大10分ごとに自動更新）。
        ウィジェットが0のままの場合は、Xcode の Signing & Capabilities で App Groups（group.com.kfit.app）が両ターゲットに設定されているか確認してください。
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
                                Text("Fitingo の使い方ガイド")
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
                                Text("Fitingo v0.9.21")
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
