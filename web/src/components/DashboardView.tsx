import React, { useEffect, useState } from 'react';
import { getTodayExercises, getUserProfile, getWeeklyGoals, getWeeklyProgress, getWeekLabel, getActiveDaysElapsed } from '../services/firebase';
import { useAppStore } from '../store/appStore';
interface DashboardViewProps {
  onStartWorkout?: () => void;
  onLogWorkout?: () => void;
  onWeeklyGoal?: () => void;
  onWorkoutPlan?: () => void;
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

export const DashboardView: React.FC<DashboardViewProps> = ({ onStartWorkout, onLogWorkout, onWeeklyGoal, onWorkoutPlan }) => {
  const user = useAppStore((state) => state.user);
  const userProfile = useAppStore((state) => state.userProfile);
  const setUserProfile = useAppStore((state) => state.setUserProfile);
  const setStoreWeeklyGoals = useAppStore((s) => s.setWeeklyGoals);
  const setStoreWeeklyProgress = useAppStore((s) => s.setWeeklyProgress);

  const [todayExercises, setTodayExercises] = useState<CompletedExercise[]>([]);
  const [totalReps, setTotalReps] = useState(0);
  const [totalPoints, setTotalPoints] = useState(0);
  const [weeklyGoals, setWeeklyGoals] = useState<{ exerciseId: string; exerciseName: string; targetReps: number; dailyReps?: number }[]>([]);
  const [weeklyProgress, setWeeklyProgress] = useState<Record<string, number>>({});
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const loadData = async () => {
      if (!user) return;
      try {
        const [profile, exercises, goals, progress] = await Promise.all([
          getUserProfile(user.uid),
          getTodayExercises(user.uid),
          getWeeklyGoals(user.uid),
          getWeeklyProgress(user.uid),
        ]);
        if (profile) setUserProfile(profile);
        setTodayExercises(exercises);
        setTotalReps(exercises.reduce((s: number, e: any) => s + (e.reps || 0), 0));
        setTotalPoints(exercises.reduce((s: number, e: any) => s + (e.points || 0), 0));
        setWeeklyGoals(goals);
        setWeeklyProgress(progress);
        setStoreWeeklyGoals(goals);
        setStoreWeeklyProgress(progress);
      } catch (err) {
        console.error('Error loading dashboard:', err);
      } finally {
        setIsLoading(false);
      }
    };
    loadData();
  }, [user, setUserProfile, setStoreWeeklyGoals, setStoreWeeklyProgress]);

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
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-lg font-black text-duo-dark">💪 今日のトレーニング</h2>
            {todayExercises.length > 0 && (
              <button onClick={onLogWorkout} className="text-duo-gray font-bold text-xs hover:text-duo-dark">
                ＋ 追加
              </button>
            )}
          </div>

          {todayExercises.length === 0 ? (
            <div className="text-center py-4 flex flex-col items-center gap-4">
              <img src="/mascot.png" alt="mascot" className="w-20 h-20 rounded-full object-cover" />
              <p className="text-duo-gray font-extrabold">まだトレーニングしていません</p>
              {/* Big Duolingo-style start button */}
              <button
                onClick={onStartWorkout}
                className="duo-btn-primary text-xl w-full py-5"
                style={{ borderRadius: '1.25rem', fontSize: '1.25rem' }}
              >
                🏋️ 今日のメニューを開始！
              </button>
            </div>
          ) : (
            <div className="space-y-2">
              {todayExercises.map((ex) => (
                <div
                  key={ex.id}
                  className="flex items-center justify-between rounded-2xl p-3"
                  style={{ backgroundColor: '#F7F7F7', border: '2px solid #e5e5e5' }}
                >
                  <div className="flex items-center gap-3">
                    <span className="text-xl">{getExerciseEmoji(ex.exerciseName)}</span>
                    <div>
                      <p className="font-extrabold text-duo-dark text-sm">{ex.exerciseName}</p>
                      <p className="text-duo-gray font-bold text-xs">{ex.reps} reps</p>
                    </div>
                  </div>
                  <p className="text-lg font-black" style={{ color: '#CE9700' }}>+{ex.points} XP</p>
                </div>
              ))}
              {/* Continue button after first round */}
              <button
                onClick={onStartWorkout}
                className="duo-btn-primary w-full text-base mt-1"
              >
                🔄 もう一周する
              </button>
            </div>
          )}
        </div>

        {/* Weekly goal mini card */}
        <div
          className="duo-card p-5 cursor-pointer hover:opacity-90 transition-opacity"
          onClick={onWeeklyGoal}
        >
          <div className="flex items-center justify-between mb-3">
            <h2 className="text-lg font-black text-duo-dark">🎯 週間目標</h2>
            <span className="text-duo-gray font-bold text-xs">📅 {getWeekLabel()}</span>
          </div>
          {weeklyGoals.length === 0 ? (
            <div className="flex items-center justify-between">
              <p className="text-duo-gray font-bold text-sm">目標がまだ設定されていません</p>
              <span className="text-duo-green font-extrabold text-sm">設定する →</span>
            </div>
          ) : (
            <div className="space-y-2">
              {weeklyGoals.map(goal => {
                const done = weeklyProgress[goal.exerciseId] ?? 0;
                const activeDays = getActiveDaysElapsed();
                const expectedToday = (goal.dailyReps ?? 0) * activeDays || goal.targetReps;
                const pct = Math.min((done / expectedToday) * 100, 100);
                return (
                  <div key={goal.exerciseId}>
                    <div className="flex justify-between mb-1">
                      <span className="text-duo-dark font-extrabold text-sm">{goal.exerciseName}</span>
                      <span className="font-bold text-sm" style={{ color: pct >= 100 ? '#46A302' : '#AFAFAF' }}>
                        {done}/{expectedToday}
                      </span>
                    </div>
                    <div className="duo-progress-bar" style={{ height: '10px' }}>
                      <div
                        className="h-full rounded-full transition-all duration-500"
                        style={{
                          width: `${pct}%`,
                          background: pct >= 100
                            ? 'linear-gradient(90deg, #58CC02, #91E62A)'
                            : 'linear-gradient(90deg, #1CB0F6, #58CC02)',
                        }}
                      />
                    </div>
                  </div>
                );
              })}
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

        {/* 今日のプランバナー */}
        <button
          onClick={onWorkoutPlan}
          className="duo-card p-5 w-full text-left hover:opacity-90 active:scale-[0.98] transition-all"
          style={{ background: 'linear-gradient(135deg, #E8F5E9 0%, #E3F2FD 100%)', border: '2px solid rgba(88,204,2,0.25)' }}
        >
          <div className="flex items-center gap-4">
            <div
              className="w-14 h-14 rounded-2xl flex items-center justify-center text-3xl shrink-0"
              style={{ background: 'white', boxShadow: '0 2px 8px rgba(0,0,0,0.08)' }}
            >
              📋
            </div>
            <div className="flex-1 min-w-0">
              <p className="font-black text-duo-dark text-base">今日のプラン</p>
              <p className="text-duo-gray font-bold text-xs mt-0.5">
                筋トレメニュー・有酸素・栄養目標を確認
              </p>
            </div>
            <span className="text-duo-gray text-lg">›</span>
          </div>
        </button>

      </div>
    </div>
  );
};
