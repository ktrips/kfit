import React, { useState } from 'react';

interface Section {
  icon: string;
  title: string;
  content: React.ReactNode;
}

const Li = ({ children }: { children: React.ReactNode }) => (
  <li style={{ marginBottom: 4 }}>{children}</li>
);

const Ul = ({ children }: { children: React.ReactNode }) => (
  <ul style={{ paddingLeft: 16, margin: '6px 0' }}>{children}</ul>
);

const PlusBadge = () => (
  <span style={{
    display: 'inline-flex', alignItems: 'center', gap: 3,
    background: 'linear-gradient(135deg, #FFD700, #FF8C00)',
    color: '#fff', fontWeight: 900, fontSize: 10,
    padding: '1px 7px', borderRadius: 20, marginLeft: 6, verticalAlign: 'middle',
  }}>
    ⊕ Plus限定
  </span>
);

// ─── FAQ データ（docs/SamBezThieMuskJobs_plan.md §2-3 と同期） ──
const FAQ_ITEMS: { q: string; a: string }[] = [
  {
    q: '無料で何ができますか？',
    a: '運動の自動カウント、1日1セットの目標、Apple ヘルスケア連携、AI食事解析（開始10日間は1日1回無料）、友達3人までのフィードは無料です。クレジットカード登録も不要です。',
  },
  {
    q: '今まで何をやっても続かなかった私でも続きますか？',
    a: '続かない原因の大半は「記録の手間」と「高すぎる初期目標」です。Fitingoは入力ゼロ・初期目標90秒に設計されており、「続けるための努力」自体を無くしています。それでも途切れた場合、ストリークには3日間の猶予があります（1日サボる→即リセット、にはなりません）。',
  },
  {
    q: 'Apple Watch は必須ですか？',
    a: '不要です。iPhoneだけで自動カウント・写真記録・歩数連携が使えます。Watchがあると手ぶら記録と文字盤での進捗表示が加わります。',
  },
  {
    q: 'あすけん・みんチャレ・Apple Fitness+ と何が違いますか？',
    a: 'あすけんは「食事記録」、みんチャレは「仲間」、Fitness+は「運動コンテンツ」にそれぞれ特化しています。Fitingoは「運動×食事×睡眠×仲間」を1つの継続スコアに束ね、かつ記録を自動化している点が違います。目的が「痩せる知識」ではなく「続いた実績を作る」ことならFitingoが向いています。',
  },
  {
    q: '食事写真のAI解析はどのくらい正確ですか？',
    a: '一般的な家庭料理・外食で主要栄養素の推定を行います。完璧ではありませんが、目的は栄養士並みの精度ではなく「記録が続くこと」です。数値は後から1タップで修正できます。',
  },
  {
    q: '健康データはどこに保存されますか？他人に見られませんか？',
    a: '健康データはApple ヘルスケアとあなたのアカウントにのみ保存されます。フィードに共有されるのは「今日やったか」だけで、体重・食事内容・睡眠は共有されません。データの外部販売は行いません。',
  },
  {
    q: '友達がいなくても意味がありますか？',
    a: 'あります。公式「90日チャレンジ」に参加すると同時期に始めた仲間と同じフィードに入るため、知り合いを誘う必要はありません。',
  },
  {
    q: '月額480円の元は取れますか？',
    a: 'ジム1回分の1/10以下です。Plusの中心価値はAIコーチと週次レポートによる「続く確率の底上げ」で、7日間の無料トライアルで判断できます。',
  },
  {
    q: '解約は簡単ですか？',
    a: 'iPhoneの「設定 → Apple ID → サブスクリプション」からいつでも解約でき、当社への連絡は不要です。解約後も無料機能と過去の記録はそのまま使えます。',
  },
  {
    q: '動作環境は？',
    a: 'iOS 17以降のiPhone。Apple Watchは任意（watchOS 10以降）。Web版はChrome/Safari/Firefoxの最新版で利用できます。',
  },
];

const sections: Section[] = [
  // ─── Fitingoの約束（プレスリリース） ────────────────────────
  {
    icon: '📣',
    title: 'Fitingoの約束 — 今度こそ、続く。',
    content: (
      <div className="space-y-3 text-sm font-bold text-duo-gray">
        <p>
          ジムも、記録アプリも、3日で終わった。それはあなたの意志が弱いからではありません。
          <strong className="text-duo-dark">記録が面倒だったからです。</strong>
        </p>
        <p>
          ダイエットや運動の失敗要因は「キツさ」ではなく「記録と意志力への依存」にあります。
          Fitingoは3つの仕組みでこれを取り除きました。
        </p>
        <div>
          <p className="text-duo-dark mb-1">1. 記録ゼロ秒</p>
          <p>
            iPhone / Apple Watch が腕立て・スクワットを自動カウント。食事は写真を撮るだけでAIがカロリーと栄養素を記録。
            歩数・睡眠はApple ヘルスケアから自動取得。あなたが入力する項目は原則ゼロです。
          </p>
        </div>
        <div>
          <p className="text-duo-dark mb-1">2. 1日90秒から</p>
          <p>
            最初の目標は「1日1セット（約90秒）」。完了するとスパイラルとストリークが伸び、
            途切れそうな日は「スクワット5回だけ」と最小の行動を提案します。ストリークには3日間の猶予があります。
          </p>
        </div>
        <div>
          <p className="text-duo-dark mb-1">3. 見られている力</p>
          <p>
            TOMOフィードで仲間に共有されるのは「今日やった」だけ。体重や食事の中身は共有されません。
            公式の90日チャレンジに参加すれば、友達がいなくても同期の仲間ができます。
          </p>
        </div>
        <p>
          続いた日々は、スパイラルとストリークという「実績」になって残ります。
          10年三日坊主だった人の、最初の90秒を、Fitingoがお手伝いします。
        </p>
      </div>
    ),
  },

  // ─── よくある質問（FAQ） ────────────────────────────────────
  {
    icon: '❓',
    title: 'よくある質問（FAQ）',
    content: (
      <div className="space-y-4 text-sm font-bold text-duo-gray">
        {FAQ_ITEMS.map((item, i) => (
          <div key={i}>
            <p className="text-duo-dark mb-1">Q{i + 1}. {item.q}</p>
            <p>{item.a}</p>
          </div>
        ))}
      </div>
    ),
  },

  // ─── Fitingo Plus ──────────────────────────────────────────
  {
    icon: '⊕',
    title: 'Fitingo Plus について',
    content: (
      <div className="space-y-3 text-sm font-bold text-duo-gray">
        <p>Fitingo には無料の <strong className="text-duo-dark">Free</strong> プランと、有料の <strong style={{ color: '#FF8C00' }}>Plus</strong> プランがあります。</p>
        <div>
          <p className="text-duo-dark mb-1">✅ Free でできること</p>
          <Ul>
            <Li>ROUTINスパイラル・基本ゴール設定</Li>
            <Li>アクティビティ記録（FITタブ）</Li>
            <Li>食事ログ手入力・PFC表示（FOODタブ）</Li>
            <Li>友達3人まで追加（TOMOタブ）</Li>
            <Li>基本ウィジェット・1スロット通知</Li>
          </Ul>
        </div>
        <div>
          <p style={{ color: '#FF8C00' }} className="mb-1">🔑 Plus で解放される主な機能</p>
          <Ul>
            <Li>広告なし・全機能フルアクセス</Li>
            <Li>MINDタブ（睡眠スコア・HRV分析・AIコーチング）</Li>
            <Li>FIT/FOOD/MIND統合レポート・カロリー収支（ROUTINページ）</Li>
            <Li>食事フォトAI解析の回数アップ（APIキー不要・Freeは1日1回→Plusは1日3回）</Li>
            <Li>FITフィード・FOODフィード写真記録</Li>
            <Li>Apple Watchアプリ・Watchモーション検出・Watchウィジェット</Li>
            <Li>Kindle本をWebで全文読む</Li>
            <Li>友達無制限・フレンドフィード全閲覧</Li>
            <Li>スパイラルテーマ10種以上・全スロット通知</Li>
          </Ul>
        </div>
        <p style={{ fontSize: 11, color: '#aaa' }}>
          月額¥480 / 年額¥3,800（7日間無料トライアル付き）。
          iOSアプリのハンバーガーメニュー →「Plus にアップグレード」から購入できます。
        </p>
      </div>
    ),
  },

  // ─── ROUTIN ────────────────────────────────────────────────
  {
    icon: '💪',
    title: 'トレーニングの記録方法',
    content: (
      <div className="space-y-2 text-sm font-bold text-duo-gray">
        <ol className="list-decimal list-inside space-y-1">
          <li>ダッシュボードの ROUTIN ボタンをタップ</li>
          <li>種目（プッシュアップ・スクワットなど）を選択</li>
          <li>＋ ボタンでレップ数を入力</li>
          <li>「✓ トレーニングを記録」で保存</li>
          <li>XP が獲得されてダッシュボードに戻ります</li>
        </ol>
        <p className="pt-1">
          ROUTINボタンの背景色は進捗に合わせてグリーン〜オレンジ〜赤に変化します。
        </p>
      </div>
    ),
  },
  {
    icon: '🌀',
    title: 'Mandala（スパイラルチャート）',
    content: (
      <div className="space-y-2 text-sm font-bold text-duo-gray">
        <p>ROUTINページに表示される渦巻き状の曼荼羅チャートです。今日の全目標の達成状況を一目で確認できます。</p>
        <Ul>
          <Li>完了済みノード: カラフル・光るリング表示</Li>
          <Li>未完了ノード: 薄く透過表示</Li>
          <Li>中央サークル: 全体の達成率（%）をリアルタイム表示</Li>
        </Ul>
        <p>スパイラル下に今日の獲得XPがコンパクトに重なって表示されます。</p>
      </div>
    ),
  },
  {
    icon: '📊',
    title: 'FIT・FOOD・MIND 統合レポート',
    content: (
      <div className="space-y-2 text-sm font-bold text-duo-gray">
        <p><strong className="text-duo-dark">ROUTINページ</strong> のスパイラルの下に表示される3リングカードです。<PlusBadge /></p>
        <Ul>
          <Li><strong className="text-duo-dark">FITリング</strong>：Apple Watchのムーブ・エクササイズ・スタンドリングと総燃焼カロリー</Li>
          <Li><strong className="text-duo-dark">FOODリング（PFC）</strong>：P・F・Cの比率を3色で表示。中央にPFCスコア（0〜100点）。FOODページのリングと同じデータ</Li>
          <Li><strong className="text-duo-dark">MINDリング（睡眠）</strong>：昨夜の睡眠時間と目標達成率。MINDページの睡眠スコアと同じデータ</Li>
        </Ul>
        <p>各リングをタップすると該当するタブに移動します。</p>
      </div>
    ),
  },
  {
    icon: '⭐',
    title: 'XP（ポイント）の仕組み',
    content: (
      <div className="space-y-2 text-sm font-bold text-duo-gray">
        <p>1 rep ごとに以下の XP が加算されます。</p>
        <Ul>
          <Li>🤜 プッシュアップ・スクワット・ランジ：<strong className="text-duo-dark">2 XP / rep</strong></Li>
          <Li>🧘 シットアップ・プランク：<strong className="text-duo-dark">1 XP / rep（秒）</strong></Li>
          <Li>🔥 バーピー：<strong className="text-duo-dark">5 XP / rep</strong></Li>
        </Ul>
        <p>獲得 XP はスパイラル下のコンパクトな表示で確認できます。</p>
      </div>
    ),
  },
  {
    icon: '🔥',
    title: 'ストリーク（連続記録）',
    content: (
      <div className="space-y-2 text-sm font-bold text-duo-gray">
        <p>毎日トレーニングを記録すると連続日数が伸びます。</p>
        <Ul>
          <Li>週2日まで休息日を設けても streak は継続します</Li>
          <Li>3日以上空くとリセットされます</Li>
          <Li>90日連続達成が最初の大きな目標です</Li>
        </Ul>
      </div>
    ),
  },
  {
    icon: '🎯',
    title: '時間帯別目標の設定',
    content: (
      <div className="space-y-2 text-sm font-bold text-duo-gray">
        <p>設定から、夜中・朝・昼・午後・夜の5時間帯にそれぞれ目標を設定できます。</p>
        <Ul>
          <Li>💪 トレーニングセット数</Li>
          <Li>🧘 マインドフルネス回数</Li>
          <Li>🤸 ストレッチ目標（Reflect 合計分数）</Li>
          <Li>🍽️ 食事kcal・💧 水分ml</Li>
          <Li>カスタムアクティビティ（読書、Duolingo など）</Li>
        </Ul>
        <p style={{ fontSize: 11, color: '#aaa' }}>
          MIND・TOMOタブはデフォルトでオフです。設定から有効にすると表示されます。
          時間帯別リマインダーもデフォルトでオフ（Free は1スロット、Plus は全スロット）。
        </p>
      </div>
    ),
  },

  // ─── FIT タブ ───────────────────────────────────────────────
  {
    icon: '🏃',
    title: 'FITタブ（アクティビティ・体重）',
    content: (
      <div className="space-y-2 text-sm font-bold text-duo-gray">
        <p><strong className="text-duo-dark">今日のアクティビティカード</strong>（Free・Plus共通）</p>
        <Ul>
          <Li>Apple Watchの3リング（ムーブ・エクササイズ・スタンド）達成率を総合スコアで表示</Li>
          <Li>最新体重・体脂肪率と直近7日の増減</Li>
        </Ul>
        <p><strong className="text-duo-dark">詳細分析・グラフ</strong> <PlusBadge /></p>
        <Ul>
          <Li>週間消費・摂取傾向・カロリー収支グラフ</Li>
          <Li>AI目標逆算カロリー設定（APIキー別途必要）</Li>
          <Li>FITフィード写真記録（体重ログ写真）</Li>
        </Ul>
      </div>
    ),
  },

  // ─── FOOD タブ ──────────────────────────────────────────────
  {
    icon: '📸',
    title: 'フォトログ（AI食事分析）',
    content: (
      <div className="space-y-2 text-sm font-bold text-duo-gray">
        <p>食事写真からAIがカロリー・PFCを自動解析します。<PlusBadge /></p>
        <p style={{ fontSize: 11, color: '#aaa' }}>※ Plus プランで利用可能。別途 SETTINGS → LLM設定 でAPIキーの設定が必要です。</p>
        <ol className="list-decimal list-inside space-y-1">
          <li>FOODページ または ROUTINページ の「AI食事フォトログ」ボタンをタップ</li>
          <li>カメラで撮影 または 写真ライブラリから選択</li>
          <li>AIがカロリー・PFCを推定</li>
          <li>確認して「記録する」で保存</li>
        </ol>
        <p>対応AIモデル：OpenAI GPT-4o / Anthropic Claude / Google Gemini 2.5 Flash</p>
      </div>
    ),
  },
  {
    icon: '🥗',
    title: 'PFCバランス分析',
    content: (
      <div className="space-y-2 text-sm font-bold text-duo-gray">
        <p>Apple Healthに記録された食事データからPFC（たんぱく質・脂質・炭水化物）を取得し、バランスをスコア化します。</p>
        <Ul>
          <Li>たんぱく質 💪: 目標15% ／ 脂質 🥑: 目標25% ／ 炭水化物 🍚: 目標60%</Li>
          <Li>FOODページ上部のリングで比率を確認できます</Li>
          <Li>ROUTINページの統合レポートにも同じリングが表示されます（Plus）</Li>
        </Ul>
      </div>
    ),
  },

  // ─── MIND タブ ──────────────────────────────────────────────
  {
    icon: '🧠',
    title: 'MINDタブ',
    content: (
      <div className="space-y-2 text-sm font-bold text-duo-gray">
        <p>睡眠・マインドフルネス・ストレスを管理するタブです。<PlusBadge /></p>
        <p style={{ fontSize: 11, color: '#aaa' }}>Freeユーザーにはロック画面が表示されます。</p>
        <Ul>
          <Li>睡眠スコア（0〜100点）・睡眠ステージバー</Li>
          <Li>心拍数・HRV（心拍変動）・ストレス推定</Li>
          <Li>マインドフルネス記録・ポモドーロタイマー統合（20分）</Li>
          <Li>AIコーチングコメント（APIキー別途必要）</Li>
        </Ul>
      </div>
    ),
  },
  {
    icon: '😴',
    title: '睡眠スコアの見方',
    content: (
      <div className="space-y-2 text-sm font-bold text-duo-gray">
        <p>Apple Healthの睡眠データを0〜100点でスコア化します。<PlusBadge /></p>
        <Ul>
          <Li>睡眠時間（最大50点）: 実績 ÷ 目標時間 × 50</Li>
          <Li>就寝時刻（最大30点）: 24:00以前なら満点</Li>
          <Li>睡眠中断（最大20点）: 覚醒時間が少ないほど高得点</Li>
        </Ul>
        <p>90点以上: 最高 / 80点以上: 良好 / 70点以上: 普通 / 50点未満: 不十分</p>
      </div>
    ),
  },
  {
    icon: '🧘',
    title: 'マインドフルネス',
    content: (
      <div className="space-y-2 text-sm font-bold text-duo-gray">
        <p>ROUTINページのマインドフルネスボタンをタップすると1分の呼吸セッションを開始します。</p>
        <Ul>
          <Li>7秒吸って8秒吐くリズム。Hapticで呼吸タイミングを促します</Li>
          <Li>1分完了後、Apple Healthにマインドフルネスとして自動保存</Li>
          <Li>20分ポモドーロタイマーの完了もマインドフルネス時間に加算</Li>
        </Ul>
      </div>
    ),
  },

  // ─── TOMO タブ ──────────────────────────────────────────────
  {
    icon: '👥',
    title: 'TOMOフィード（友達とシェア）',
    content: (
      <div className="space-y-2 text-sm font-bold text-duo-gray">
        <p>友達の習慣記録をタイムラインで確認できます。</p>
        <Ul>
          <Li>🍽️ FOOD: フォトログの食事記録（カロリー付き）</Li>
          <Li>💪 FIT: 体重ログ写真</Li>
          <Li>🦉 Duolingo: Duolingo学習記録</Li>
          <Li>📓 日記: テキスト日記</Li>
        </Ul>
        <p>友達追加: 相手のGmailアドレスで検索 → 相互承認。</p>
        <p style={{ fontSize: 11, color: '#aaa' }}>Free: 友達3人まで ／ Plus: 無制限</p>
      </div>
    ),
  },

  // ─── Kindle 書籍 ────────────────────────────────────────────
  {
    icon: '📚',
    title: 'Kindle書籍（Books）',
    content: (
      <div className="space-y-3 text-sm font-bold text-duo-gray">
        <p>
          Fitingo 関連の3冊のKindle書籍を
          <a href="https://fit.ktrips.net/books" target="_blank" rel="noopener noreferrer" className="text-duo-green underline mx-1">fit.ktrips.net/books</a>
          で読めます。
        </p>
        <Ul>
          <Li>
            <strong className="text-duo-dark">⌚ AppleWatch Diet Ultra2</strong><br />
            Apple Watch Ultra 2 を使ったダイエット・健康管理の100メソッド
          </Li>
          <Li>
            <strong className="text-duo-dark">📱 Cursor + ClaudeでiPhoneアプリを作る</strong><br />
            SwiftUI・HealthKit・Apple Watch 連携アプリを個人開発した全工程
          </Li>
          <Li>
            <strong className="text-duo-dark">🚀 iPhoneアプリ＋！マーケティングする方法</strong> <PlusBadge /><br />
            Kindle出版・Plusマネタイズ・SNS拡散戦略まで解説するコンパニオン本
          </Li>
        </Ul>
        <p style={{ fontSize: 11, color: '#aaa' }}>
          Free: 各書籍の試し読みが無料（約10ページ分）。Plus: 全3冊の全文をWebで読めます。
        </p>
      </div>
    ),
  },

  // ─── iOSアプリ・Watch ────────────────────────────────────────
  {
    icon: '📱',
    title: 'iOSアプリ・Apple Watch',
    content: (
      <div className="space-y-2 text-sm font-bold text-duo-gray">
        <p>Fitingo は Web のほか iOS / Apple Watch アプリでも使えます。</p>
        <Ul>
          <Li>
            <strong className="text-duo-dark">iOSアプリ</strong>：
            モーションセンサーによる自動 rep 計測・HealthKit連携・フォトログ
          </Li>
          <Li>
            <strong className="text-duo-dark">Apple Watch</strong>（Plus限定）：
            Watchで rep を自動検知・触覚フィードバック・iPhoneへ自動同期
          </Li>
          <Li>3つのプラットフォームのデータは Firebase でリアルタイム同期されます</Li>
        </Ul>
        <p style={{ fontSize: 11, color: '#aaa' }}>Apple Watch アプリは Fitingo Plus 限定機能です。</p>
      </div>
    ),
  },

  // ─── アカウント ──────────────────────────────────────────────
  {
    icon: '🔐',
    title: 'アカウント・データについて',
    content: (
      <div className="space-y-2 text-sm font-bold text-duo-gray">
        <Ul>
          <Li>Google アカウントでログインします</Li>
          <Li>データは Google Firebase に安全に保存されます</Li>
          <Li>自分のデータ以外にはアクセスできません</Li>
          <Li>ログアウトはナビゲーションメニューから行えます</Li>
          <Li>Plus のサブスクリプション管理は iOSの「設定 → Apple ID → サブスクリプション」から</Li>
        </Ul>
      </div>
    ),
  },
];

export const HelpView: React.FC = () => {
  const [openIdx, setOpenIdx] = useState<number | null>(0);

  return (
    <div className="min-h-screen bg-duo-gray-light pb-10">
      <div className="max-w-md mx-auto px-4 pt-6 space-y-4">

        {/* Header */}
        <div className="flex items-center gap-3 mb-2">
          <img src="/mascot.png" alt="" className="w-12 h-12 rounded-full object-cover shrink-0" />
          <div>
            <h2 className="text-2xl font-black text-duo-dark">ヘルプ・使い方</h2>
            <p className="text-duo-gray font-bold text-sm">Fitingo の使い方ガイド</p>
          </div>
        </div>

        {/* Accordion */}
        <div className="space-y-2">
          {sections.map((sec, i) => (
            <div
              key={i}
              className="duo-card overflow-hidden"
              style={{ padding: 0 }}
            >
              <button
                onClick={() => setOpenIdx(openIdx === i ? null : i)}
                className="w-full flex items-center gap-3 px-4 py-4 text-left"
              >
                <span className="text-2xl shrink-0">{sec.icon}</span>
                <span className="font-black text-duo-dark flex-1">{sec.title}</span>
                <span
                  className="text-lg font-black transition-transform duration-200"
                  style={{
                    color: '#AFAFAF',
                    transform: openIdx === i ? 'rotate(180deg)' : 'none',
                    display: 'inline-block',
                  }}
                >
                  ∨
                </span>
              </button>
              {openIdx === i && (
                <div className="px-4 pb-4" style={{ borderTop: '1.5px solid #e5e5e5' }}>
                  <div className="pt-3">{sec.content}</div>
                </div>
              )}
            </div>
          ))}
        </div>

        {/* バージョン情報 */}
        <div className="duo-card p-4 flex items-center gap-3">
          <span className="text-2xl shrink-0">ℹ️</span>
          <div className="flex-1">
            <p className="font-black text-duo-dark text-sm">Fitingo</p>
            <p className="text-duo-gray font-bold text-xs">
              Web・iOS・Apple Watch 対応 ／ Firebase バックエンド
            </p>
          </div>
          <a
            href="https://github.com/ktrips/kfit"
            target="_blank"
            rel="noopener noreferrer"
            className="duo-btn-secondary px-3 py-1.5 text-xs font-extrabold shrink-0"
          >
            GitHub →
          </a>
        </div>

        {/* Kindle書籍 */}
        <a
          href="https://fit.ktrips.net/books"
          target="_blank"
          rel="noopener noreferrer"
          className="duo-card p-4 flex items-center gap-3 no-underline hover:opacity-80 transition-opacity"
        >
          <span className="text-2xl shrink-0">📚</span>
          <div className="flex-1">
            <p className="font-black text-duo-dark text-sm">もっと知りたい人の為のKindle書籍</p>
            <p className="text-duo-gray font-bold text-xs">
              AppleWatch Diet / Cursor+Claude iOSアプリ開発 / マーケティング ─ Plusなら全3冊Webで全文読める
            </p>
          </div>
          <span className="font-black text-sm shrink-0" style={{ color: '#58CC02' }}>→</span>
        </a>

        {/* プライバシーポリシー */}
        <a
          href="https://fit.ktrips.net/privacy-policy/"
          target="_blank"
          rel="noopener noreferrer"
          className="duo-card p-4 flex items-center gap-3 no-underline hover:opacity-80 transition-opacity"
        >
          <span className="text-2xl shrink-0">🔐</span>
          <div className="flex-1">
            <p className="font-black text-duo-dark text-sm">プライバシーポリシー</p>
            <p className="text-duo-gray font-bold text-xs">
              個人情報・HealthKit データの取り扱いについて
            </p>
          </div>
          <span className="font-black text-sm shrink-0" style={{ color: '#58CC02' }}>→</span>
        </a>

      </div>
    </div>
  );
};
