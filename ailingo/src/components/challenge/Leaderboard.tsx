import { useEffect, useState } from 'react';
import { ArrowLeft, Trophy, Loader2 } from 'lucide-react';
import { useGameStore } from '../../store/gameStore';
import { fetchLeaderboard } from '../../services/firebase';
import type { LeaderboardEntry } from '../../types/challenge';

export function Leaderboard() {
  const { setView, user, weekly } = useGameStore();
  const [entries, setEntries] = useState<LeaderboardEntry[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchLeaderboard()
      .then(setEntries)
      .catch(console.error)
      .finally(() => setLoading(false));
  }, []);

  const daysLeft = getDaysUntilSunday();

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="max-w-lg mx-auto px-4 py-8">
        <button
          onClick={() => setView('map')}
          className="flex items-center gap-1.5 text-gray-500 hover:text-brand mb-6 text-sm font-medium transition-colors"
        >
          <ArrowLeft className="w-4 h-4" />
          マップに戻る
        </button>

        <div className="flex items-center justify-between mb-6">
          <h1 className="text-2xl font-black text-gray-900 flex items-center gap-2">
            <Trophy className="w-6 h-6 text-amber-500" />
            週間ランキング
          </h1>
          <span className="text-xs text-gray-500 bg-gray-100 rounded-full px-3 py-1">
            残り{daysLeft}日
          </span>
        </div>

        {/* My stats */}
        <div className="bg-brand-light border border-brand/20 rounded-2xl p-4 mb-6">
          <p className="text-xs font-bold text-brand mb-2">今週のあなた</p>
          <div className="flex justify-between">
            <div>
              <p className="text-2xl font-black text-brand">{weekly.totalScore?.toLocaleString() ?? 0}<span className="text-sm font-medium ml-1">pt</span></p>
              <p className="text-xs text-brand/70">週間スコア</p>
            </div>
            <div>
              <p className="text-2xl font-black text-brand">{(weekly.tokensUsed ?? 0).toLocaleString()}<span className="text-sm font-medium ml-1">tok</span></p>
              <p className="text-xs text-brand/70">使用トークン</p>
            </div>
          </div>
        </div>

        {/* Ranking list */}
        {loading ? (
          <div className="flex justify-center py-12">
            <Loader2 className="w-6 h-6 animate-spin text-brand" />
          </div>
        ) : entries.length === 0 ? (
          <div className="text-center py-12 text-gray-400">
            <Trophy className="w-10 h-10 mx-auto mb-3 opacity-30" />
            <p className="font-medium">まだランキングデータがありません</p>
            <p className="text-sm">チャレンジを完了してランキングに載ろう！</p>
          </div>
        ) : (
          <div className="space-y-2">
            {entries.map((entry) => {
              const isMe = entry.uid === user?.uid;
              return (
                <div
                  key={entry.uid}
                  className={`flex items-center gap-3 rounded-2xl border p-4 transition-all ${
                    isMe
                      ? 'bg-brand-light border-brand/30'
                      : 'bg-white border-gray-200'
                  }`}
                >
                  <span className="text-lg font-black w-7 text-center">
                    {entry.rank === 1 ? '🥇' : entry.rank === 2 ? '🥈' : entry.rank === 3 ? '🥉' : entry.rank}
                  </span>
                  <div className="flex-1 min-w-0">
                    <p className={`font-bold text-sm truncate ${isMe ? 'text-brand' : 'text-gray-900'}`}>
                      {entry.username}{isMe ? ' (あなた)' : ''}
                    </p>
                    {entry.dojoComplete && (
                      <span className="text-xs text-emerald-600 font-medium">🏯 DOJO修了</span>
                    )}
                  </div>
                  <p className={`font-black text-sm ${isMe ? 'text-brand' : 'text-gray-700'}`}>
                    {entry.weeklyScore.toLocaleString()}pt
                  </p>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}

function getDaysUntilSunday(): number {
  const day = new Date().getDay();
  return day === 0 ? 0 : 7 - day;
}
