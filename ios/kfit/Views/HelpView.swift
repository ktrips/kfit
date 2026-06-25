import SwiftUI

struct HelpItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let content: String
}

private let helpItems: [HelpItem] = [

    // ─── Fitingo Plus ───────────────────────────────────────────
    HelpItem(
        icon: "⊕",
        title: "Fitingo Plus について",
        content: """
        Fitingo には無料の「Free」プランと、有料の「Plus」プランがあります。
        【Free でできること】
        • ROUTINスパイラル・基本ゴール設定
        • アクティビティ記録（FIT タブ）
        • 食事ログ手入力・PFC表示（FOOD タブ）
        • 友達3人まで追加（TOMO タブ）
        • 基本ウィジェット・1スロット通知
        【Plus で解放される主な機能】
        • 広告なし・全機能フルアクセス
        • MIND タブ（睡眠スコア・HRV分析・AIコーチング）
        • FIT/FOOD/MIND 統合レポート・カロリー収支（ROUTIN ページ）
        • フォトログ AI 栄養解析（FOOD タブ、APIキー設定が別途必要）
        • FIT フィード・FOOD フィード写真記録
        • Apple Watch アプリ・Watchモーション検出・Watchウィジェット
        • Kindle 本を Web で全文読む
        • 友達無制限追加・フレンドフィード全閲覧（TOMO タブ）
        • スパイラルテーマ10種以上・全スロット通知
        【アップグレード方法】
        ハンバーガーメニュー（左上）→「Plus にアップグレード」からサブスクリプションを開始できます。
        月額¥480 / 年額¥3,800（7日間無料トライアル付き）。
        シークレットコードをお持ちの場合は「コードで解放」からも利用できます。
        """
    ),

    // ─── ROUTIN ─────────────────────────────────────────────────
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
        icon: "🌀",
        title: "Mandala（スパイラルチャート）",
        content: """
        ROUTINページに表示される「Mandala」カードは、今日の全目標を渦巻き状の曼荼羅チャートで可視化します。
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
        【スパイラル下のポイント表示】
        スパイラルの下に今日の獲得XPがコンパクトに重なって表示されます。
        """
    ),
    HelpItem(
        icon: "📊",
        title: "FIT・FOOD・MIND 統合レポート（Plus限定）",
        content: """
        ROUTINページのスパイラルの下に、FIT・FOOD・MIND の3リングカードが表示されます（Plus限定）。
        【FIT リング】
        Apple Watch のムーブ・エクササイズ・スタンドリングと総燃焼カロリーを表示。
        【FOOD リング（PFCリング）】
        今日のたんぱく質・脂質・炭水化物の比率を3色リングで表示。中央にPFCスコア（0〜100点）。
        FOODページのPFCリングと同じデータ（HealthKit + フォトログ合算値）を使用。
        【MIND リング（睡眠リング）】
        昨夜の睡眠時間と睡眠ゴールの達成率をリングで表示。中央に睡眠時間。
        MINDページの睡眠スコアと同じデータを使用。
        各リングをタップすると該当するタブに移動します。
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
        獲得 XP はスパイラル下のコンパクトな表示で確認できます。
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
        設定の一番上で、夜中・朝・昼・午後・夜の5時間帯にそれぞれ目標を設定できます。
        【設定できる目標】
        • 💪 トレーニングセット数
        • 🧘 マインドフルネス回数（Apple Watch の1分セッションをカウント）
        • 🤸 ストレッチ目標（Reflect の合計分数）
        • 🍽️ 食事kcal・💧 水分ml
        • カスタムアクティビティ（読書、Duolingo、勉強など任意の習慣）
        【1日全体の目標】
        • アクティビティリング達成
        • 睡眠スコア目標（例: 80点以上）
        • PFCバランススコア目標（例: 80点以上）
        • 体重計測・マインドフルネス計測
        • 食事kcal・水分mlの1日目標（時間帯へ配分）
        【デフォルト設定】
        MIND・TOMO タブはデフォルトでオフです。設定から有効にすると表示されます。
        時間帯別リマインダーもデフォルトでオフです（Free は1スロットのみ、Plus は全スロット）。
        """
    ),

    // ─── FIT タブ ────────────────────────────────────────────────
    HelpItem(
        icon: "🏃",
        title: "FITタブ（アクティビティ・体重）",
        content: """
        下部メニューの「FIT」では、体重・体脂肪・カロリー収支の目標を管理できます。
        【今日のアクティビティカード（Free・Plus共通）】
        Apple Watch の3リング（ムーブ・エクササイズ・スタンド）と体組成を表示。
        リング達成率を総合スコア（0〜100%）でカードに表示します。
        体重・体脂肪率の最新値と直近7日間の増減も表示。
        【詳細アクティビティ分析（Plus限定）】
        週間消費・週間摂取傾向・週間カロリー収支グラフ。
        AIで目標から逆算したカロリー設定（APIキー別途必要）。
        【体重スパイラルアイコンのタップ】
        Withingsアプリを開く / 写真を撮って体重ログを記録 の2択メニューが表示されます。
        写真付き体重ログは FIT フィードと TOMO フィードに「体重ログ」として表示されます。
        """
    ),
    HelpItem(
        icon: "📷",
        title: "FITフィード（写真記録、Plus限定）",
        content: """
        FITページの一番下に「FITフィード」があります（Plus限定）。
        体重計測時に写真を添付すると、ここに記録が蓄積されます。
        • 日付・体重・体脂肪率・写真が一覧で確認できます
        • FITフィードの記録は TOMO フィードにも「体重ログ」タグで表示されます
        【Freeの場合】
        「PlusにすればFITに関する写真を記録できます」と表示されます。
        Plusにアップグレードすると写真付き体重ログが使えるようになります。
        """
    ),

    // ─── FOOD タブ ───────────────────────────────────────────────
    HelpItem(
        icon: "📸",
        title: "フォトログ（AI食事分析、Plus限定・APIキー必要）",
        content: """
        食事の写真を撮影またはライブラリから選択すると、AIが自動でカロリーとPFCを分析します。
        ※ Plus プランで利用可能。別途 SETTINGS → LLM設定 でAPIキーの設定が必要です。
        1. FOODページ または ROUTINページ の「AI食事フォトログ」ボタンをタップ
        2. カメラで撮影 または 写真ライブラリから選択
        3. AIが食品を認識してカロリー・PFCを推定
        4. 確認して「記録する」で保存
        【対応AIモデル】
        • OpenAI GPT-4o
        • Anthropic Claude
        • Google Gemini 2.5 Flash
        設定画面からAPIキーとモデルを選択できます。
        【注意】
        AI機能はFitingo Plus のサブスクリプションとは別に、ご自身のAPIキーが必要です。
        """
    ),
    HelpItem(
        icon: "🥗",
        title: "PFCバランス分析の見方",
        content: """
        Apple Healthに記録された食事データからPFC（たんぱく質・脂質・炭水化物）を取得し、バランスをスコア化します。
        フォトログで記録した栄養素もHealthKit経由で合算されます。
        【目標比率の目安】
        • たんぱく質 💪: 15%
        • 脂質 🥑: 25%
        • 炭水化物 🍚: 60%
        【スコア】
        目標比率に近いほど高スコア（0〜100点）になります。
        FOODページ上部のリングで比率を確認し、ROUTINページの統合レポートにも同じリングが表示されます。
        """
    ),
    HelpItem(
        icon: "🍽️",
        title: "FOODフィード（写真記録、Plus限定）",
        content: """
        FOODページの一番下に「FOODフィード」があります（Plus限定）。
        フォトログで記録した食事写真がここに一覧で表示されます。
        • 写真・食品名・カロリー・PFCが確認できます
        • FOODフィードの記録は TOMO フィードにも「FOOD」タグで表示されます
        【Freeの場合】
        「PlusにすればFoodに関する写真とカロリーを記録できます」と表示されます。
        """
    ),

    // ─── MIND タブ ───────────────────────────────────────────────
    HelpItem(
        icon: "🧠",
        title: "MINDタブ（Plus限定）",
        content: """
        下部メニューの「MIND」は Fitingo Plus 限定のタブです。
        Freeユーザーには「MINDタブはPlus限定です」というロック画面が表示されます。
        【Plusで表示される内容】
        • 睡眠スコア（0〜100点）・睡眠ステージバー
        • 心拍数・HRV（心拍変動）・ストレス推定
        • マインドフルネス記録・ポモドーロタイマー統合（20分）
        • AIコーチングコメント（APIキー別途必要）
        • ストレス状態に応じた具体的な提案
        """
    ),
    HelpItem(
        icon: "😴",
        title: "睡眠スコアの見方（Plus限定）",
        content: """
        Apple Healthの睡眠データを分析して0〜100点でスコア化します（MINDタブ・Plus限定）。
        【スコアの計算式】
        • 睡眠時間（最大50点）: 実績 ÷ 目標時間 × 50（目標達成で満点）
        • 就寝時刻（最大30点）: 24:00以前なら満点。それ以降は10分遅れるごとに−1点
        • 睡眠中断（最大20点）: 覚醒時間が0なら満点。覚醒割合20%以上で0点
        【評価】
        90点以上: 最高 / 80点以上: 良好 / 70点以上: 普通 / 50点未満: 不十分
        【カードの見方】
        スコアサークルと評価ラベル・合計/深い/REM/コアの統計チップが表示されます。
        ステージバーで各睡眠ステージを時間軸で色分けして確認できます。
        """
    ),
    HelpItem(
        icon: "🫀",
        title: "HRV・ストレス推定（Plus限定）",
        content: """
        Apple Watchが計測した心拍変動（HRV）から、今日のストレス状態を推定します（MINDタブ・Plus限定）。
        【HRVとは】
        心拍間隔のばらつき（ms）。高いほど自律神経が整っており、ストレスが低い状態です。
        【ストレス目安】
        • HRV 80ms以上 → ストレス 低い
        • HRV 60〜80ms → ストレス やや低い
        • HRV 40〜60ms → ストレス 中程度
        • HRV 20〜40ms → ストレス やや高い
        • HRV 20ms未満 → ストレス 高い
        """
    ),
    HelpItem(
        icon: "🧘",
        title: "マインドフルネス",
        content: """
        ROUTINページのマインドフルネスボタンをタップすると、iOSアプリ内で1分の呼吸セッションを開始します。
        • 7秒吸って、8秒吐くリズムで「吸って / 吐いて」が切り替わり、Hapticで呼吸タイミングを促します
        • 1分完了後、Apple Healthにマインドフルネスとして自動保存されます
        • 1分以内の短いセッション（Breathe相当）が時間帯のマインドフルネス回数にカウントされます
        • Reflect セッションはストレッチ目標（分数）にカウントされます（🤸）
        • 20分ポモドーロタイマーの完了もマインドフルネス時間に加算されます
        """
    ),
    HelpItem(
        icon: "🤸",
        title: "ストレッチ目標（Reflect連携）",
        content: """
        時間帯別目標でストレッチを有効にすると、Apple Watch の Reflect セッションが自動連携されます。
        • 目標は「分数」で設定（デフォルト: 3分）
        • 設定した時間帯内で Reflect を合計N分行うと達成
        • 例: 3分設定 → 3分のReflect1回 or 1分×3回で達成
        ダッシュボードの時間帯行に 🤸 アイコンで進捗が確認できます。
        """
    ),

    // ─── TOMO タブ ───────────────────────────────────────────────
    HelpItem(
        icon: "👥",
        title: "TOMOフィード（友達とシェア）",
        content: """
        下部メニューの「TOMO」では、友達の習慣記録をタイムラインで確認できます。
        【フィードに表示される投稿種類】
        • 🍽️ FOOD: フォトログの食事記録（カロリー付き）
        • 💪 FIT: 体重ログ写真
        • 🦉 Duolingo: Duolingo学習記録（発音付き）
        • 📓 日記: テキスト日記
        【フィルタリング】
        フィードトップのチップで「FOOD」「FIT」「Duolingo」「日記」別にフィルタリングできます。
        【友達追加方法】
        1. TOMOページ右上の「＋」をタップ
        2. 相手のGmailアドレスを入力
        3. 相手が承認すると相互にフォロー状態になります
        Free: 友達3人まで / Plus: 無制限
        【投稿の公開設定】
        各投稿には「公開/非公開」の設定があります。
        非公開にした投稿は友達のフィードには表示されません。
        """
    ),

    // ─── Apple Watch ─────────────────────────────────────────────
    HelpItem(
        icon: "⌚",
        title: "Apple Watchアプリ（Plus限定）",
        content: """
        Apple Watch アプリは Fitingo Plus 限定の機能です。
        iOSアプリがPlus状態のとき、ペアリング済みのApple WatchにWatchアプリがインストールされます。
        【Watchアプリの画面構成（横スワイプで切り替え）】
        • 摂取記録: 食事kcal・水分mlをヘッダー表示し、朝食/昼食/夕食/水/コーヒー/アルコールを記録
        • メイン: トレーニング結果/目標とマインドフルネス結果/目標を表示
        • ウェルネス: 睡眠・マインドフルネス・ストレッチなどを確認
        • Health: アクティビティ・スタンドなどApple Healthデータを表示
        • Watch Face風ページ: 今日のやることをアイコンで確認し、タップで記録開始
        【モーション自動検出（Watch）】
        Watchの加速度センサーでrepを20Hzで自動カウント。フォームスコアも計算されます。
        WatchでのトレーニングはiPhoneに自動同期されます。
        """
    ),

    // ─── ウィジェット・その他 ─────────────────────────────────────
    HelpItem(
        icon: "🔲",
        title: "ホーム画面ウィジェット",
        content: """
        ホーム画面にFitingoウィジェットを追加すると、アプリを開かずに今日の進捗を確認できます。
        【ウィジェットサイズ】
        • 小: ストリーク・達成度・カロリー収支・XP（Free）
        • 横長: 上記指標 + Fitingoアイコン・日付時刻（Free）
        • 大: 指標 + 目標別進捗リスト（Free）
        • Plus ウィジェット: FIT/FOOD/MIND リング表示（Plus限定）
        背景色は今日の達成度に連動して変化します。
        【追加方法】
        ホーム画面を長押し → 左上「＋」→「Fitingo」を検索 → サイズを選択
        【データ反映】
        アプリ起動時や記録保存時に更新されます（最大5分ごとに自動更新）。
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
        • Apple Watch からもモーション検出が使えます（Plus限定）
        • Watch でのトレーニングはiPhoneに自動同期されます
        """
    ),
    HelpItem(
        icon: "🔐",
        title: "アカウント・データについて",
        content: """
        • Google アカウントでログインします
        • データは Firebase に安全に保存されます
        • Web・iOS・Watch のデータはリアルタイム同期されます
        • ログアウトはハンバーガーメニュー（左上）からプロフィール画面で行えます
        • Plus のサブスクリプション管理は「設定 → Apple ID → サブスクリプション」から
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
                                Text("Fitingo")
                                    .font(.subheadline).fontWeight(.black)
                                Text("Web・iOS・Apple Watch 対応（Plus限定）")
                                    .font(.caption).foregroundColor(Color.duoSubtitle)
                            }
                            Spacer()
                        }
                        .padding(16)
                        .background(Color(.systemBackground))
                        .cornerRadius(14)
                        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
                        .padding(.horizontal, 20)

                        // プライバシーポリシー
                        Link(destination: URL(string: "https://fit.ktrips.net/privacy-policy/")!) {
                            HStack(spacing: 12) {
                                Text("🔐").font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("プライバシーポリシー")
                                        .font(.subheadline).fontWeight(.black)
                                        .foregroundColor(Color.duoDark)
                                    Text("個人情報・HealthKitデータの取り扱いについて")
                                        .font(.caption).foregroundColor(Color.duoSubtitle)
                                        .lineLimit(2)
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

                        // Kindle書籍（もっと知りたい人向け）
                        Link(destination: URL(string: "https://fit.ktrips.net/books")!) {
                            HStack(spacing: 12) {
                                Text("📚").font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("もっと知りたい人の為のKindle書籍")
                                        .font(.subheadline).fontWeight(.black)
                                        .foregroundColor(Color.duoDark)
                                    Text("AppleWatch Diet Ultra2 など ─ Plusなら全文Webで読める")
                                        .font(.caption).foregroundColor(Color.duoSubtitle)
                                        .lineLimit(2)
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
