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
    icon: '🎯',
    title: '週間目標の設定',
    content: (
      <div className="space-y-2 text-sm font-bold text-duo-gray">
        <p>メニュー → 「週間目標」から設定できます。</p>
        <ul className="list-disc list-inside space-y-1">
          <li>各種目の <strong className="text-duo-dark">1日のrep数</strong> を入力</li>
          <li>週間目標は自動で <strong className="text-duo-dark">× 5日</strong>（週2日休息）計算</li>
          <li>週が変わると目標はリセットされます</li>
        </ul>
      </div>
    ),
  },
  {
    icon: '⭐',
    title: 'ポイント（XP）の仕組み',
    content: (
      <div className="space-y-2 text-sm font-bold text-duo-gray">
        <ul className="list-disc list-inside space-y-1">
          <li>プッシュアップ・スクワット・ランジ：<strong className="text-duo-dark">2 XP / rep</strong></li>
          <li>シットアップ・プランク：<strong className="text-duo-dark">1 XP / rep</strong></li>
          <li>バーピー：<strong className="text-duo-dark">5 XP / rep</strong></li>
        </ul>
        <p>獲得XPはホーム画面の「総ポイント」に累積されます。</p>
      </div>
    ),
  },
  {
    icon: '🔥',
    title: 'ストリーク（連続記録）',
    content: (
      <p className="text-sm font-bold text-duo-gray">
        毎日トレーニングを記録すると連続日数が伸びます。
        90日連続達成を目指しましょう！24時間以上記録がないとリセットされます。
      </p>
    ),
  },
  {
    icon: '📅',
    title: '履歴の確認',
    content: (
      <p className="text-sm font-bold text-duo-gray">
        メニュー → 「履歴」から過去14日間のトレーニング記録を日別に確認できます。
      </p>
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

        {/* Claude Usage link */}
        <div
          className="duo-card p-4 flex items-center gap-3"
          style={{ borderColor: '#CE82FF', boxShadow: '0 4px 0 #9C27B0' }}
        >
          <span className="text-2xl shrink-0">🤖</span>
          <div className="flex-1">
            <p className="font-black text-duo-dark text-sm">Claude AI Usage</p>
            <p className="text-duo-gray font-bold text-xs">API使用量・課金状況を確認</p>
          </div>
          <a
            href="https://claude.ai/settings/usage"
            target="_blank"
            rel="noopener noreferrer"
            className="duo-btn-secondary px-3 py-1.5 text-xs font-extrabold shrink-0"
          >
            開く →
          </a>
        </div>

      </div>
    </div>
  );
};
