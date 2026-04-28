import React, { useState } from 'react';

interface Section {
  icon: string;
  title: string;
  content: React.ReactNode;
}

const sections: Section[] = [
  {
    icon: '💪',
    title: 'トレーニングの記録方法',
    content: (
      <ol className="space-y-2 text-sm font-bold text-duo-gray list-decimal list-inside">
        <li>ヘッダーの「💪 トレーニング」ボタンをタップ</li>
        <li>種目（プッシュアップ・スクワットなど）を選択</li>
        <li>＋ ボタンでレップ数を入力</li>
        <li>「✓ トレーニングを記録！」で保存</li>
        <li>XP が獲得されてホームに戻ります</li>
      </ol>
    ),
  },
  {
    icon: '⭐',
    title: 'XP（ポイント）の仕組み',
    content: (
      <div className="space-y-2 text-sm font-bold text-duo-gray">
        <p>1 rep ごとに以下の XP が加算されます。</p>
        <ul className="list-none space-y-1">
          <li>🤜 プッシュアップ：<strong className="text-duo-dark">2 XP / rep</strong></li>
          <li>🦵 スクワット：<strong className="text-duo-dark">2 XP / rep</strong></li>
          <li>🧘 シットアップ：<strong className="text-duo-dark">1 XP / rep</strong></li>
          <li>🚶 ランジ：<strong className="text-duo-dark">2 XP / rep</strong></li>
          <li>🔥 バーピー：<strong className="text-duo-dark">5 XP / rep</strong></li>
          <li>🧱 プランク：<strong className="text-duo-dark">1 XP / 秒</strong></li>
        </ul>
        <p className="pt-1">獲得 XP はホーム画面の「今日の XP」に表示されます。</p>
      </div>
    ),
  },
  {
    icon: '🔥',
    title: 'ストリーク（連続記録）',
    content: (
      <div className="space-y-2 text-sm font-bold text-duo-gray">
        <p>毎日トレーニングを記録すると連続日数が伸びます。</p>
        <ul className="list-disc list-inside space-y-1">
          <li>24時間以上記録がないとリセットされます</li>
          <li>90日連続達成が最初の大きな目標です</li>
          <li>ホーム画面の🔥アイコンで現在の日数を確認できます</li>
        </ul>
      </div>
    ),
  },
  {
    icon: '🎯',
    title: '週間目標の設定',
    content: (
      <div className="space-y-2 text-sm font-bold text-duo-gray">
        <p>メニュー → 「週間目標」から設定できます。</p>
        <ul className="list-disc list-inside space-y-1">
          <li>各種目の <strong className="text-duo-dark">1日のrep数</strong> を入力</li>
          <li>週間目標は自動で <strong className="text-duo-dark">× 5日</strong>（週2日休息）計算</li>
          <li>ホーム画面の進捗バーでリアルタイム確認できます</li>
          <li>週が変わると目標はリセットされます</li>
        </ul>
      </div>
    ),
  },
  {
    icon: '📅',
    title: '履歴の確認',
    content: (
      <p className="text-sm font-bold text-duo-gray">
        メニュー → 「履歴」から過去14日間のトレーニング記録を日別に確認できます。
        各日のXP合計・種目別rep数が表示されます。
      </p>
    ),
  },
  {
    icon: '📱',
    title: 'iOSアプリ・Apple Watch',
    content: (
      <div className="space-y-2 text-sm font-bold text-duo-gray">
        <p>DuoFit は Web のほか iOS / Apple Watch アプリでも使えます。</p>
        <ul className="list-disc list-inside space-y-1">
          <li>
            <strong className="text-duo-dark">iOSアプリ</strong>：
            モーションセンサーによる自動 rep 計測・フォームスコア表示
          </li>
          <li>
            <strong className="text-duo-dark">Apple Watch</strong>：
            手首だけで rep を自動検知・触覚フィードバック・トレーニング完了後に iPhone へ自動同期
          </li>
          <li>3つのプラットフォームのデータは Firebase でリアルタイム同期されます</li>
        </ul>
      </div>
    ),
  },
  {
    icon: '🔐',
    title: 'アカウント・データについて',
    content: (
      <div className="space-y-2 text-sm font-bold text-duo-gray">
        <ul className="list-disc list-inside space-y-1">
          <li>Google アカウントでログインします</li>
          <li>データは Google Firebase に安全に保存されます</li>
          <li>自分のデータ以外にはアクセスできません</li>
          <li>ログアウトはナビゲーションメニューから行えます</li>
        </ul>
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
            <p className="text-duo-gray font-bold text-sm">DuoFit の使い方ガイド</p>
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
            <p className="font-black text-duo-dark text-sm">DuoFit</p>
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

      </div>
    </div>
  );
};
