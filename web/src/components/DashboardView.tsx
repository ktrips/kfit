import React, { useEffect, useState } from 'react';
import { getTodayExercises, getUserProfile } from '../services/firebase';
import { useAppStore } from '../store/appStore';
interface DashboardViewProps {
  onLogWorkout?: () => void;
}

interface CompletedExercise {
  id: string;
  exerciseName: string;
  reps: number;
  points: number;
  timestamp?: Date;
}

const EXERCISE_EMOJI: Record<string, string> = {
  'push-up': '💪', 'pushup': '💪',
  'squat':   '🏋️',
  'sit-up':  '🔥', 'situp': '🔥',
};

function getExerciseEmoji(name: string): string {
  const key = (name ?? '').toLowerCase().replace(/\s+/g, '-');
  for (const [k, v] of Object.entries(EXERCISE_EMOJI)) {
    if (key.includes(k)) return v;
  }
  return '⚡';
}

export const DashboardView: React.FC<DashboardViewProps> = ({ onLogWorkout }) => {
  const user = useAppStore((state) => state.user);
  const userProfile = useAppStore((state) => state.userProfile);
  const setUserProfile = useAppStore((state) => state.setUserProfile);

  const [todayExercises, setTodayExercises] = useState<CompletedExercise[]>([]);
  const [totalReps, setTotalReps] = useState(0);
  const [totalPoints, setTotalPoints] = useState(0);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const loadData = async () => {
      if (!user) return;
      try {
        const [profile, exercises] = await Promise.all([
          getUserProfile(user.uid),
          getTodayExercises(user.uid),
        ]);
        if (profile) setUserProfile(profile);
        setTodayExercises(exercises);
        setTotalReps(exercises.reduce((s: number, e: any) => s + (e.reps || 0), 0));
        setTotalPoints(exercises.reduce((s: number, e: any) => s + (e.points || 0), 0));
      } catch (err) {
        console.error('Error loading dashboard:', err);
      } finally {
        setIsLoading(false);
      }
    };
    loadData();
  }, [user, setUserProfile]);

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

  const streak = userProfile?.streak || 0;
  const goalProgress = Math.min((streak / 90) * 100, 100);

  return (
    <div className="min-h-screen bg-duo-gray-light pb-10">
      <div className="max-w-2xl mx-auto px-4 pt-6 space-y-4">

        {/* Welcome banner */}
        <div className="duo-card p-5 flex items-center gap-4">
          <img src="/mascot.png" alt="mascot" className="w-16 h-16 rounded-full object-cover shrink-0" style={{ border: '3px solid #58CC02' }} />
          <div className="flex-1 min-w-0">
            <p className="text-duo-gray font-bold text-xs uppercase tracking-wider">おかえり！</p>
            <h1 className="text-2xl font-black text-duo-dark truncate">
              {userProfile?.username || 'トレーニー'} 🎉
            </h1>
            <p className="text-duo-green font-extrabold text-sm">今日もやっていこう！</p>
          </div>
          <div className="text-right shrink-0">
            <p className="text-duo-gray font-bold text-xs">総ポイント</p>
            <p className="text-3xl font-black" style={{ color: '#CE9700' }}>
              {userProfile?.totalPoints || 0}
            </p>
            <p className="text-duo-gray font-bold text-xs">XP</p>
          </div>
        </div>

        {/* Stats */}
        <div className="grid grid-cols-3 gap-3">
          <div className="duo-stat-card" style={{ backgroundColor: '#FFF3E0', borderColor: '#FF9600', boxShadow: '0 3px 0 #CC7000' }}>
            <span className="text-3xl">🔥</span>
            <p className="text-3xl font-black text-duo-orange">{streak}</p>
            <p className="text-xs font-extrabold uppercase tracking-wide" style={{ color: '#CC7000' }}>日連続</p>
          </div>
          <div className="duo-stat-card" style={{ backgroundColor: '#E8F5E9', borderColor: '#58CC02', boxShadow: '0 3px 0 #46A302' }}>
            <span className="text-3xl">⚡</span>
            <p className="text-3xl font-black text-duo-green">{totalReps}</p>
            <p className="text-xs font-extrabold text-duo-green-dark uppercase tracking-wide">今日のRep</p>
          </div>
          <div className="duo-stat-card" style={{ backgroundColor: '#FFF8E1', borderColor: '#FFD900', boxShadow: '0 3px 0 #CE9700' }}>
            <span className="text-3xl">⭐</span>
            <p className="text-3xl font-black" style={{ color: '#CE9700' }}>{totalPoints}</p>
            <p className="text-xs font-extrabold uppercase tracking-wide" style={{ color: '#CE9700' }}>今日のXP</p>
          </div>
        </div>

        {/* Today's workouts */}
        <div className="duo-card p-5">
          <h2 className="text-lg font-black text-duo-dark mb-4">💪 今日のトレーニング</h2>

          {todayExercises.length === 0 ? (
            <div className="text-center py-8 flex flex-col items-center gap-4">
              <img src="/mascot.png" alt="mascot" className="w-20 h-20 rounded-full object-cover" />
              <p className="text-duo-gray font-extrabold">まだトレーニングしていません</p>
              <button onClick={onLogWorkout} className="duo-btn-primary text-base">
                最初のトレーニングを記録！
              </button>
            </div>
          ) : (
            <div className="space-y-3">
              {todayExercises.map((ex) => (
                <div
                  key={ex.id}
                  className="flex items-center justify-between rounded-2xl p-4"
                  style={{ backgroundColor: '#F7F7F7', border: '2px solid #e5e5e5' }}
                >
                  <div className="flex items-center gap-3">
                    <span className="text-2xl">{getExerciseEmoji(ex.exerciseName)}</span>
                    <div>
                      <p className="font-extrabold text-duo-dark">{ex.exerciseName}</p>
                      <p className="text-duo-gray font-bold text-sm">{ex.reps} reps</p>
                    </div>
                  </div>
                  <div className="text-right">
                    <p className="text-xl font-black" style={{ color: '#CE9700' }}>+{ex.points}</p>
                    <p className="text-duo-gray font-bold text-xs">XP</p>
                  </div>
                </div>
              ))}
              <button onClick={onLogWorkout} className="duo-btn-secondary w-full text-base mt-2">
                ＋ もっとトレーニングする
              </button>
            </div>
          )}
        </div>

        {/* 90-day goal */}
        <div className="duo-card p-5">
          <div className="flex items-center justify-between mb-3">
            <h2 className="text-lg font-black text-duo-dark">🎯 90日チャレンジ</h2>
            <span className="font-extrabold text-duo-green text-sm">{streak} / 90日</span>
          </div>
          <div className="duo-progress-bar mb-2">
            <div className="duo-progress-fill" style={{ width: `${goalProgress}%` }} />
          </div>
          <p className="text-duo-gray font-bold text-sm">
            {goalProgress >= 100
              ? '🎉 チャレンジ達成！おめでとう！'
              : `あと ${90 - streak} 日で達成！続けよう！`}
          </p>
        </div>

      </div>
    </div>
  );
};
