import React, { useEffect, useState } from 'react';
import { getLeaderboard, type LeaderboardEntry } from '../services/firebase';
import { useAppStore } from '../store/appStore';

const RANK_COLORS: Record<number, { bg: string; border: string; emoji: string }> = {
  1: { bg: '#FFF8E1', border: '#FFD900', emoji: '🥇' },
  2: { bg: '#F5F5F5', border: '#9E9E9E', emoji: '🥈' },
  3: { bg: '#FFF3E0', border: '#FF9600', emoji: '🥉' },
};

export const LeaderboardView: React.FC = () => {
  const user = useAppStore((state) => state.user);
  const [entries, setEntries] = useState<LeaderboardEntry[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const loadLeaderboard = async () => {
      setIsLoading(true);
      try {
        const data = await getLeaderboard('week');
        setEntries(data);
      } catch (err) {
        console.error('Error loading leaderboard:', err);
      } finally {
        setIsLoading(false);
      }
    };
    loadLeaderboard();
  }, []);

  const myEntry = entries.find(e => e.userId === user?.uid);

  if (isLoading) {
    return (
      <div className="min-h-screen bg-duo-gray-light flex items-center justify-center">
        <div className="flex flex-col items-center gap-4">
          <img src="/mascot.png" alt="mascot" className="w-24 h-24 rounded-full object-cover animate-wiggle" />
          <p className="text-duo-green font-extrabold text-xl">読み込み中...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-duo-gray-light pb-10">
      <div className="max-w-2xl mx-auto px-4 pt-6 space-y-6">

        {/* Header */}
        <div className="duo-card p-5">
          <div className="flex items-center gap-4">
            <div className="text-5xl">🏆</div>
            <div>
              <h1 className="text-2xl font-black text-duo-dark">週間ランキング</h1>
              <p className="text-duo-gray font-bold text-sm">
                今週のトップトレーナー
              </p>
            </div>
          </div>
        </div>

        {/* My Rank */}
        {myEntry && (
          <div
            className="duo-card p-5"
            style={{
              borderColor: '#58CC02',
              boxShadow: '0 4px 0 #46A302',
              background: 'linear-gradient(135deg, #D7FFB8 0%, #E8F5E9 100%)',
            }}
          >
            <p className="text-duo-green font-extrabold text-xs uppercase tracking-wider mb-2">
              あなたの順位
            </p>
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-4">
                <div
                  className="w-12 h-12 rounded-xl flex items-center justify-center font-black text-2xl"
                  style={{ background: '#58CC02', color: 'white', boxShadow: '0 3px 0 #46A302' }}
                >
                  {myEntry.rank}
                </div>
                <div>
                  <p className="font-black text-duo-dark text-lg">{myEntry.username}</p>
                  <p className="text-duo-green font-bold text-sm">
                    {myEntry.workouts} workouts · {myEntry.streak}日連続
                  </p>
                </div>
              </div>
              <div className="text-right">
                <p className="font-black text-3xl" style={{ color: '#CE9700' }}>
                  {myEntry.points}
                </p>
                <p className="text-duo-gray font-bold text-xs">XP</p>
              </div>
            </div>
          </div>
        )}

        {/* Top 3 */}
        {entries.slice(0, 3).length > 0 && (
          <div className="space-y-3">
            {entries.slice(0, 3).map((entry) => {
              const colors = RANK_COLORS[entry.rank];
              const isMe = entry.userId === user?.uid;
              return (
                <div
                  key={entry.id}
                  className="duo-card p-5"
                  style={colors ? {
                    borderColor: colors.border,
                    boxShadow: `0 4px 0 ${colors.border}`,
                    background: colors.bg,
                  } : {}}
                >
                  <div className="flex items-center gap-4">
                    <div
                      className="w-14 h-14 rounded-2xl flex items-center justify-center text-3xl shrink-0"
                      style={colors ? {
                        background: 'white',
                        border: `3px solid ${colors.border}`,
                        boxShadow: `0 3px 0 ${colors.border}`,
                      } : {}}
                    >
                      {colors ? colors.emoji : `#${entry.rank}`}
                    </div>
                    <div className="flex-1">
                      <div className="flex items-center gap-2">
                        <p className="font-black text-duo-dark text-lg">
                          {entry.username}
                        </p>
                        {isMe && (
                          <span className="px-2 py-0.5 rounded-full bg-duo-green text-white text-xs font-black">
                            YOU
                          </span>
                        )}
                      </div>
                      <p className="text-duo-gray font-bold text-sm">
                        {entry.workouts} workouts · {entry.streak}日連続
                      </p>
                    </div>
                    <div className="text-right">
                      <p className="font-black text-2xl" style={{ color: '#CE9700' }}>
                        {entry.points}
                      </p>
                      <p className="text-duo-gray font-bold text-xs">XP</p>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}

        {/* Rest of leaderboard */}
        {entries.slice(3).length > 0 && (
          <div>
            <h2 className="text-lg font-black text-duo-dark mb-3">その他のランナー</h2>
            <div className="duo-card p-3 space-y-2">
              {entries.slice(3).map((entry) => {
                const isMe = entry.userId === user?.uid;
                return (
                  <div
                    key={entry.id}
                    className={`flex items-center justify-between p-3 rounded-xl transition-colors ${
                      isMe ? 'bg-duo-green-light' : 'bg-white hover:bg-gray-50'
                    }`}
                    style={isMe ? { border: '2px solid #58CC02' } : {}}
                  >
                    <div className="flex items-center gap-3">
                      <div
                        className="w-8 h-8 rounded-lg flex items-center justify-center font-black text-sm"
                        style={{
                          background: isMe ? '#58CC02' : '#f7f7f7',
                          color: isMe ? 'white' : '#3C3C3C',
                        }}
                      >
                        {entry.rank}
                      </div>
                      <div>
                        <div className="flex items-center gap-2">
                          <p className="font-bold text-duo-dark text-sm">
                            {entry.username}
                          </p>
                          {isMe && (
                            <span className="px-1.5 py-0.5 rounded bg-duo-green text-white text-xs font-black">
                              YOU
                            </span>
                          )}
                        </div>
                        <p className="text-duo-gray text-xs font-bold">
                          {entry.workouts} workouts
                        </p>
                      </div>
                    </div>
                    <div className="text-right">
                      <p className="font-black text-base" style={{ color: '#CE9700' }}>
                        {entry.points}
                      </p>
                      <p className="text-duo-gray text-xs font-bold">XP</p>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {entries.length === 0 && (
          <div className="duo-card p-8 text-center">
            <div className="text-5xl mb-4">📊</div>
            <p className="text-duo-dark font-black text-lg mb-2">ランキングデータなし</p>
            <p className="text-duo-gray font-bold text-sm">
              トレーニングを記録してランキングに参加しよう！
            </p>
          </div>
        )}

      </div>
    </div>
  );
};
