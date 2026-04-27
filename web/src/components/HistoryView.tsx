import React, { useEffect, useState } from 'react';
import { getRecentExercises, type DayExercises } from '../services/firebase';
import { useAppStore } from '../store/appStore';

const EXERCISE_EMOJI: Record<string, string> = {
  'push-up': '💪', 'pushup': '💪',
  'squat': '🏋️',
  'sit-up': '🔥', 'situp': '🔥',
  'lunge': '🦵',
  'burpee': '⚡',
  'plank': '🧘',
};

function getEmoji(name: string): string {
  const key = (name ?? '').toLowerCase().replace(/\s+/g, '-');
  for (const [k, v] of Object.entries(EXERCISE_EMOJI)) {
    if (key.includes(k)) return v;
  }
  return '⚡';
}

export const HistoryView: React.FC = () => {
  const user = useAppStore((s) => s.user);
  const [history, setHistory] = useState<DayExercises[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    if (!user) return;
    (async () => {
      const data = await getRecentExercises(user.uid, 14);
      setHistory(data);
      setIsLoading(false);
    })();
  }, [user]);

  if (isLoading) {
    return (
      <div className="min-h-screen bg-duo-gray-light flex items-center justify-center">
        <div className="flex flex-col items-center gap-4">
          <img src="/mascot.png" alt="" className="w-20 h-20 rounded-full object-cover animate-wiggle" />
          <p className="text-duo-green font-extrabold text-lg">読み込み中...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-duo-gray-light pb-10">
      <div className="max-w-2xl mx-auto px-4 pt-6 space-y-4">

        <div className="flex items-center gap-3 mb-2">
          <img src="/mascot.png" alt="" className="w-12 h-12 rounded-full object-cover shrink-0" />
          <div>
            <h2 className="text-2xl font-black text-duo-dark">トレーニング履歴</h2>
            <p className="text-duo-gray font-bold text-sm">過去14日間の記録</p>
          </div>
        </div>

        {history.length === 0 ? (
          <div className="duo-card p-8 text-center flex flex-col items-center gap-4">
            <img src="/mascot.png" alt="" className="w-24 h-24 rounded-full object-cover" />
            <p className="text-duo-dark font-extrabold text-lg">まだ履歴がありません</p>
            <p className="text-duo-gray font-bold text-sm">トレーニングを記録すると、ここに表示されます！</p>
          </div>
        ) : (
          <div className="space-y-4">
            {history.map((day) => (
              <div key={day.date} className="duo-card p-4">
                <div className="flex items-center justify-between mb-3">
                  <h3 className="font-black text-duo-dark text-base">{day.label}</h3>
                  <div className="flex items-center gap-3">
                    <span className="font-bold text-sm text-duo-gray">⚡ {day.totalReps} rep</span>
                    <span
                      className="font-black text-sm px-2 py-0.5 rounded-lg"
                      style={{ background: '#FFF8E1', color: '#CE9700', border: '1.5px solid #FFD900' }}
                    >
                      +{day.totalPoints} XP
                    </span>
                  </div>
                </div>
                <div className="space-y-2">
                  {day.exercises.map((ex) => (
                    <div
                      key={ex.id}
                      className="flex items-center justify-between rounded-xl px-3 py-2"
                      style={{ backgroundColor: '#F7F7F7', border: '1.5px solid #e5e5e5' }}
                    >
                      <div className="flex items-center gap-2">
                        <span className="text-xl">{getEmoji(ex.exerciseName)}</span>
                        <span className="font-extrabold text-duo-dark text-sm">{ex.exerciseName}</span>
                      </div>
                      <div className="flex items-center gap-3">
                        <span className="text-duo-gray font-bold text-sm">{ex.reps} reps</span>
                        <span className="font-black text-sm" style={{ color: '#CE9700' }}>+{ex.points} XP</span>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
        )}

      </div>
    </div>
  );
};
