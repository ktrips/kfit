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
        1. ダッシュボードの ROUTIN ボタンをタップ
        2. 種目（プッシュアップ・スクワットなど）を選択
        3. ＋ ボタンでレップ数を入力、または「モーション自動検出」をONにする
        4. 「✓ トレーニングを記録」で保存
        5. XP が獲得されてダッシュボードに戻ります
        【ROUTIN ボタンの表情】
        • 今日の始まり → 落ち着いたマスコットと「今日のROUTINを始めよう！」
        • 目標に対して遅れているとき → 炎マスコットと「まだ全然終わってないよ！今すぐやろう！」
        • 達成済み → 達成メッセージ
        ボタン背景は進捗に合わせてグリーン〜シアン、黄色、オレンジ、赤へ変化します。
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
        icon: "🌀",
        title: "Mandala（スパイラルチャート）",
        content: """
        ダッシュボードとROUTINページに表示される「Mandala」カードは、今日の全目標を渦巻き状の曼荼羅チャートで可視化します。
        【ノードの見方】
        • 完了済み: カラフル・やや拡大・光るリング表示
        • 未完了: 薄く透過表示
        • 中央サークル: 全体の達成率（%）をリアルタイム表示
        【ノードの種類】
        • 💪 トレーニング / 🧘 マインドフルネス / 🤸 ストレッチ
        • 🍽️ 食事 / 💧 水分 / 😴 睡眠 / 🥗 PFC
        • カスタムアクティビティ（読書📚、Duolingo🦉など）
        【ノードをタップすると】
        • 💪 → トレーニング記録画面を開く
        • 🧘 → 1分マインドフルネスセッション開始
        • 🤸 → 3分ストレッチセッション開始
        • 💧 → 水 200ml の記録を確認
        • 🍽️ → 朝食 400kcal の記録を確認
        • その他 → 該当する時間帯へスクロール移動
        【ヘッダーの読み方】
        🌀 Mandala・今日の日付・完了/総数（例: 3/8）・⚙️（設定アイコン）が1行に並びます。
        螺旋の上のレジェンドで 朝(C/D)・昼(E/F)・午後・夜 など時間帯別の完了状況を確認できます。
        【スパイラルのアルゴリズム】
        アルキメデス螺旋の適応的角度ステップにより、ノード数が増えても隣接アーム間を含む全ノード間で最低46ptの間隔を確保し重なりを防いでいます。
        """
    ),
    HelpItem(
        icon: "🎯",
        title: "時間帯別目標の設定",
        content: """
        設定の一番上で、夜中・朝・昼・午後・夜の5時間帯にそれぞれ目標を設定できます。
        【設定できる目標】
        • 💪 トレーニングセット数
        • 🧘 マインドフルネス回数（Apple Watch の1分セッションをカウント）
        • 🤸 ストレッチ目標（Reflect の合計分数。例: 3分設定なら3分のReflectで達成）
        • 🍽️ 食事kcal・💧 水分ml
        • カスタムアクティビティ（読書、Duolingo、勉強など任意の習慣）
        【1日全体の目標】
        • アクティビティリング達成
        • 睡眠スコア目標（例: 80点以上）
        • PFCバランススコア目標（例: 80点以上）
        • 体重計測・マインドフルネス計測
        • 食事kcal・水分mlの1日目標（時間帯へ配分）
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
        ダッシュボードの「心拍/ストレス」タイル、HealthView の「心拍変動（HRV）」カード、下部メニューの「MIND」で確認できます。
        """
    ),
    HelpItem(
        icon: "🧠",
        title: "MINDタブ",
        content: """
        下部メニューの「MIND」では、Apple Healthの心拍数とHRVからストレス状態を確認できます。
        【表示される内容】
        • 現在の心拍数・最新HRV・現在のストレス指数
        • 1日の平均心拍・平均HRV・平均ストレス
        • ストレス状態に応じたメッセージ
        【具体的な提案】
        • まだ深呼吸やマインドフルネスをしていない場合は、1分の呼吸を提案
        • Reflectや軽いストレッチで首・肩・背中をゆるめる提案
        • スタンド時間や歩数が少ない場合は、短い散歩を提案
        • ストレスが高めの場合は、マッサージや画面から離れる休憩を提案
        • コーヒーを淹れる、水を飲む、歯磨きをするなど小さな切り替えも提案
        提案によってはタップするとマインドフルネス、Health、記録画面などへ移動できます。
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
        icon: "🎯",
        title: "FIT（ダイエット目標タブ）",
        content: """
        下部メニューの「FIT」では、体重・体脂肪・カロリー収支の目標を管理できます。
        【設定できる項目】
        • 目標体重・目標体脂肪率・目標日
        • スタート日・スタート体重・スタート体脂肪率
        • 1日の摂取カロリー目標・消費カロリー目標
        • 摂取/消費実績にApple Healthを使うかどうか
        【表示される内容】
        • スタート・今日・ゴールの体重と体脂肪率
        • スタート→今日、今日→ゴールの体重差分
        • 期間進捗と体重進捗
        • 週間消費・週間摂取傾向・週間カロリー収支
        • AIで目標から逆算したカロリー設定
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
        ダッシュボードのマインドフルネスボタンをタップすると、iOSアプリ内で1分の呼吸セッションを開始します。
        • 7秒吸って、8秒吐くリズムで「吸って / 吐いて」が切り替わり、Hapticで呼吸タイミングを促します
        • 1分完了後、Apple Healthにマインドフルネスとして自動保存されます
        • 1分以内の短いセッション（Breathe相当）が時間帯のマインドフルネス回数にカウントされます
        • Reflect セッションはストレッチ目標（分数）にカウントされます（🤸）
        """
    ),
    HelpItem(
        icon: "🔲",
        title: "ホーム画面ウィジェット",
        content: """
        ホーム画面にFitingoウィジェットを追加すると、アプリを開かずに今日の進捗を確認できます。
        【ウィジェットサイズ】
        • 小: ストリーク・達成度・カロリー収支・XP
        • 横長: 上記指標 + Fitingoアイコン・日付時刻
        • 大: 指標 + 目標別進捗リスト
        背景色は今日の達成度に連動して変化します。
        【追加方法】
        ホーム画面を長押し → 左上「＋」→「Fitingo」を検索 → サイズを選択
        【データ反映】
        アプリ起動時や記録保存時にウィジェットデータが更新されます（最大5分ごとに自動更新）。
        ウィジェットが0のままの場合は、Xcode の Signing & Capabilities で App Groups（group.com.kfit.app）が両ターゲットに設定されているか確認してください。
        """
    ),
    HelpItem(
        icon: "⌚",
        title: "Apple Watch画面",
        content: """
        Watchアプリは横スワイプで複数ページを切り替えます。
        【ページ構成】
        • 摂取記録: 食事kcal・水分mlをヘッダー表示し、朝食/昼食/夕食/水/コーヒー/アルコールを記録
        • メイン: トレーニング結果/目標とマインドフルネス結果/目標を表示
        • ウェルネス: 睡眠・マインドフルネス・ストレッチなどを確認
        • Health: アクティビティ・スタンドなどApple Healthデータを表示
        • Watch Face風ページ: 日付と連続記録を右上に表示。今日やることを大きめのアイコンで確認し、タップで記録やトレーニング開始
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
                                Text("Fitingo a.0.11.4")
                                    .font(.subheadline).fontWeight(.black)
                                Text("Web・iOS・Apple Watch 対応")
                                    .font(.caption).foregroundColor(Color.duoSubtitle)
                            }
                            Spacer()
                        }
                        .padding(16)
                        .background(Color(.systemBackground))
                        .cornerRadius(14)
                        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
                        .padding(.horizontal, 20)

                        // Fitingoの作り方
                        Link(destination: URL(string: "https://amzn.to/3Qspdq9")!) {
                            HStack(spacing: 12) {
                                Text("📖").font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Fitingoの作り方")
                                        .font(.subheadline).fontWeight(.black)
                                        .foregroundColor(Color.duoDark)
                                    Text("このアプリの開発ノウハウを解説した本")
                                        .font(.caption).foregroundColor(Color.duoSubtitle)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(Color.duoGreen)
                            }
                            .padding(16)
                            .background(Color(.systemBackground))
                            .cornerRadius(14)
                            .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
                        }
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
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
        .padding(.horizontal, 20)
    }
}

#Preview {
    HelpView()
}
