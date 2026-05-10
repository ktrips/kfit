import React, { useEffect, useState } from 'react';
import {
  getTodayExercises, getUserProfile,
  getWeeklyGoals,
  getWeeklySetProgress, getDailySetGoal, getTodaySetCount, getTodaySetLog,
  getWeekLabel, getActiveDaysElapsed,
  getDailyCalorieGoal, setCalorieTarget,
  type WeeklySetProgress,
  type DailyCalorieGoal,
  type CompletedSetRecord,
} from '../services/firebase';
import { useAppStore } from '../store/appStore';
interface DashboardViewProps {
  onStartWorkout?: () => void;
  onLogWorkout?: () => void;
  onWeeklyGoal?: () => void;
  onWorkoutPlan?: () => void;
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

/** 種目ごとの推定カロリー（kcal/rep） */
const KCAL_PER_REP: Record<string, number> = {
  pushup: 0.5, 'push-up': 0.5,
  squat: 0.6,
  situp: 0.3, 'sit-up': 0.3,
  lunge: 0.5,
  burpee: 1.0,
  plank: 0.1,
};
function estimateKcal(exerciseId: string, reps: number): number {
  const rate = KCAL_PER_REP[(exerciseId ?? '').toLowerCase()] ?? 0.4;
  return reps * rate;
}

export const DashboardView: React.FC<DashboardViewProps> = ({ onStartWorkout, onWeeklyGoal, onWorkoutPlan }) => {
  const user = useAppStore((state) => state.user);
  const userProfile = useAppStore((state) => state.userProfile);
  const setUserProfile = useAppStore((state) => state.setUserProfile);
  const setStoreWeeklyGoals = useAppStore((s) => s.setWeeklyGoals);

  const [totalReps, setTotalReps] = useState(0);
  const [totalPoints, setTotalPoints] = useState(0);
  const [totalCalories, setTotalCalories] = useState(0);
  const [weeklyGoals, setWeeklyGoals] = useState<{ exerciseId: string; exerciseName: string; targetReps: number; dailyReps?: number }[]>([]);
  const [setProgress, setSetProgress] = useState<WeeklySetProgress>({ completedSets: 0, exercises: {} });
  const [dailySets, setDailySets] = useState(2);
  const [todaySetCount, setTodaySetCount] = useState(0);
  const [todaySets, setTodaySets] = useState<CompletedSetRecord[]>([]);
  const [expandedSetId, setExpandedSetId] = useState<string | null>(null);
  const [calorieGoal, setCalorieGoal] = useState<DailyCalorieGoal>({ targetCalories: 500, consumedCalories: 0, percentAchieved: 0 });
  const [editingCalorieTarget, setEditingCalorieTarget] = useState(false);
  const [tempCalorieTarget, setTempCalorieTarget] = useState(500);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const loadData = async () => {
      if (!user) return;
      try {
        const [profile, exercises, goals, sp, ds, tsc, tsl, cg] = await Promise.all([
          getUserProfile(user.uid),
          getTodayExercises(user.uid),
          getWeeklyGoals(user.uid),
          getWeeklySetProgress(user.uid),
          getDailySetGoal(user.uid),
          getTodaySetCount(user.uid),
          getTodaySetLog(user.uid),
          getDailyCalorieGoal(user.uid),
        ]);
        if (profile) setUserProfile(profile);
        setTotalReps(exercises.reduce((s: number, e: any) => s + (e.reps || 0), 0));
        setTotalPoints(exercises.reduce((s: number, e: any) => s + (e.points || 0), 0));
        setTotalCalories(Math.round(
          exercises.reduce((s: number, e: any) => s + estimateKcal(e.exerciseId ?? '', e.reps || 0), 0)
        ));
        setWeeklyGoals(goals);
        setStoreWeeklyGoals(goals);
        setSetProgress(sp);
        setDailySets(ds);
        setTodaySetCount(tsc);
        setTodaySets(tsl);
        setCalorieGoal(cg);
      } catch (err) {
        console.error('Error loading dashboard:', err);
      } finally {
        setIsLoading(false);
      }
    };
    loadData();
  }, [user, setUserProfile, setStoreWeeklyGoals]);

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

  const handleUpdateCalorieTarget = async () => {
    if (!user || tempCalorieTarget <= 0) return;
    try {
      await setCalorieTarget(user.uid, tempCalorieTarget);
      setCalorieGoal(prev => ({ ...prev, targetCalories: tempCalorieTarget }));
      setEditingCalorieTarget(false);
    } catch (err) {
      console.error('Error updating calorie target:', err);
    }
  };

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

        {/* Stats - 統一指標 */}
        <div className="grid grid-cols-3 gap-3">
          <div className="duo-stat-card" style={{ backgroundColor: '#FFF3E0', borderColor: '#FF9600', boxShadow: '0 3px 0 #CC7000' }}>
            <span className="text-3xl">🔥</span>
            <p className="text-3xl font-black text-duo-orange">{streak}</p>
            <p className="text-xs font-extrabold uppercase tracking-wide" style={{ color: '#CC7000' }}>日連続</p>
          </div>
          <div className="duo-stat-card" style={{ backgroundColor: '#E8F5E9', borderColor: '#58CC02', boxShadow: '0 3px 0 #46A302' }}>
            <span className="text-3xl">📊</span>
            <p className="text-2xl font-black text-duo-green leading-tight">{todaySetCount}/{dailySets}</p>
            <p className="text-xs font-extrabold uppercase tracking-wide" style={{ color: '#46A302' }}>セット</p>
          </div>
          <div className="duo-stat-card" style={{ backgroundColor: '#FFF8E1', borderColor: '#FFD900', boxShadow: '0 3px 0 #CE9700' }}>
            <span className="text-3xl">🔥</span>
            <p className="text-3xl font-black" style={{ color: '#CE9700' }}>{calorieGoal.percentAchieved}%</p>
            <p className="text-xs font-extrabold uppercase tracking-wide" style={{ color: '#CE9700' }}>カロリー</p>
          </div>
        </div>

        {/* Daily Calorie Goal */}
        <div className="duo-card p-5">
          <div className="flex items-center justify-between mb-3">
            <div className="flex items-center gap-2">
              <span className="text-lg">🔥</span>
              <h2 className="text-base font-black text-duo-dark">今日の目標カロリー</h2>
            </div>
            {!editingCalorieTarget ? (
              <button
                onClick={() => {
                  setTempCalorieTarget(calorieGoal.targetCalories);
                  setEditingCalorieTarget(true);
                }}
                className="text-duo-gray hover:text-duo-dark text-xs font-bold underline"
              >
                目標変更
              </button>
            ) : (
              <button
                onClick={() => setEditingCalorieTarget(false)}
                className="text-duo-gray hover:text-duo-dark text-xs font-bold"
              >
                ✕
              </button>
            )}
          </div>

          {editingCalorieTarget ? (
            <div className="space-y-3">
              <div className="flex items-center gap-3">
                <button
                  onClick={() => setTempCalorieTarget(t => Math.max(100, t - 50))}
                  className="w-10 h-10 rounded-xl font-black text-lg flex items-center justify-center"
                  style={{ background: '#FFEAEA', border: '2px solid #FF4B4B', color: '#FF4B4B' }}
                >
                  −
                </button>
                <div className="flex-1 text-center">
                  <input
                    type="number"
                    value={tempCalorieTarget}
                    onChange={(e) => {
                      const val = parseInt(e.target.value, 10);
                      if (!isNaN(val) && val > 0) setTempCalorieTarget(val);
                    }}
                    className="text-4xl font-black text-center w-full bg-transparent border-none outline-none text-duo-dark"
                    min="100"
                    step="50"
                  />
                  <p className="text-duo-gray font-bold text-sm">kcal</p>
                </div>
                <button
                  onClick={() => setTempCalorieTarget(t => t + 50)}
                  className="w-10 h-10 rounded-xl font-black text-lg flex items-center justify-center"
                  style={{ background: '#D7FFB8', border: '2px solid #58CC02', color: '#46A302' }}
                >
                  ＋
                </button>
              </div>
              <button
                onClick={handleUpdateCalorieTarget}
                className="duo-btn-primary w-full text-sm py-2"
              >
                ✓ 目標を設定
              </button>
            </div>
          ) : (
            <>
              <div className="flex items-center justify-between mb-1">
                <div className="flex items-end gap-2">
                  <span className="text-3xl font-black text-duo-dark leading-none">
                    {calorieGoal.consumedCalories}
                  </span>
                  <span className="text-duo-gray font-bold text-base mb-0.5">
                    / {calorieGoal.targetCalories} kcal
                  </span>
                </div>
                <span
                  className="text-base font-black"
                  style={{ color: calorieGoal.percentAchieved >= 100 ? '#46A302' : '#FF9600' }}
                >
                  {calorieGoal.percentAchieved}%
                </span>
              </div>
              <div className="duo-progress-bar" style={{ height: '8px' }}>
                <div
                  className="h-full rounded-full transition-all duration-500"
                  style={{
                    width: `${Math.min(calorieGoal.percentAchieved, 100)}%`,
                    background: calorieGoal.percentAchieved >= 100
                      ? 'linear-gradient(90deg, #58CC02, #91E62A)'
                      : 'linear-gradient(90deg, #FF9600, #FFD900)',
                  }}
                />
              </div>
              {calorieGoal.percentAchieved >= 100 && (
                <p className="text-duo-green font-extrabold text-sm mt-2">
                  🎉 今日の目標達成！
                </p>
              )}
            </>
          )}
        </div>

        {/* Today's set status — count-based */}
        {todaySetCount === 0 ? (
          <div className="duo-card p-6">
            <div className="flex items-center gap-3 mb-5">
              <div
                className="w-12 h-12 rounded-2xl flex items-center justify-center text-2xl shrink-0"
                style={{ background: '#F7F7F7', border: '2px solid #e5e5e5' }}
              >
                🔲
              </div>
              <div>
                <p className="font-black text-duo-dark text-lg leading-tight">今日のセット</p>
                <p className="text-duo-gray font-bold text-sm">
                  {weeklyGoals.length > 0
                    ? weeklyGoals.map(g => g.exerciseName).join(' · ')
                    : 'まだトレーニングしていません'}
                </p>
              </div>
            </div>
            <button
              onClick={onStartWorkout}
              className="duo-btn-primary text-xl w-full py-5"
              style={{ borderRadius: '1.25rem' }}
            >
              🏋️ 今日のセットを始める
            </button>
          </div>
        ) : (
          <div
            className="duo-card p-5"
            style={{
              borderColor: '#58CC02',
              boxShadow: '0 4px 0 #46A302',
              background: 'linear-gradient(135deg, #D7FFB8 0%, #E8F5E9 100%)',
            }}
          >
            <div className="flex items-center gap-4">
              {/* 件数バッジ */}
              <div
                className="shrink-0 w-16 h-16 rounded-2xl flex flex-col items-center justify-center"
                style={{ background: '#58CC02', boxShadow: '0 3px 0 #46A302' }}
              >
                <span className="text-white font-black text-3xl leading-none">{todaySetCount}</span>
                <span className="text-white font-bold text-[10px] leading-none mt-0.5">セット</span>
              </div>
              <div className="flex-1 min-w-0">
                <p className="font-black text-duo-dark text-lg leading-tight">
                  今日は{todaySetCount}セット完了！
                </p>
                <p className="text-duo-green font-extrabold text-sm mt-0.5">
                  {totalReps}回 / {totalCalories}kcal · +{totalPoints} XP 🎉
                </p>
                {dailySets > todaySetCount && (
                  <p className="text-duo-gray font-bold text-xs mt-1">
                    目標まであと {dailySets - todaySetCount} セット
                  </p>
                )}
                {dailySets <= todaySetCount && (
                  <p className="font-extrabold text-xs mt-1" style={{ color: '#46A302' }}>
                    ✅ 今日の目標達成！
                  </p>
                )}
              </div>
            </div>
            <button
              onClick={onStartWorkout}
              className="mt-4 w-full text-center text-duo-green font-bold text-sm underline"
            >
              もう1セットやる →
            </button>
          </div>
        )}

        {/* Weekly set progress mini card */}
        {(() => {
          const weeklyTarget = dailySets * 5;
          const activeDays = getActiveDaysElapsed();
          const expectedNow = dailySets * activeDays;
          const done = setProgress.completedSets;
          const pct = weeklyTarget > 0 ? Math.min((done / weeklyTarget) * 100, 100) : 0;
          const onTrack = expectedNow > 0 && done >= expectedNow;
          return (
            <div
              className="duo-card p-5 cursor-pointer hover:opacity-90 transition-opacity"
              onClick={onWeeklyGoal}
              style={onTrack ? { borderColor: '#58CC02', boxShadow: '0 4px 0 #46A302' } : {}}
            >
              <div className="flex items-center justify-between mb-3">
                <h2 className="text-lg font-black text-duo-dark">🎯 週間セット目標</h2>
                <span className="text-duo-gray font-bold text-xs">📅 {getWeekLabel()}</span>
              </div>
              <div className="flex items-end gap-2 mb-2">
                <span
                  className="text-3xl font-black leading-none"
                  style={{ color: onTrack ? '#46A302' : '#CE9700' }}
                >
                  {done}
                </span>
                <span className="font-bold text-duo-gray text-base mb-0.5">/ {weeklyTarget} セット</span>
                <span
                  className="ml-auto font-black text-base"
                  style={{ color: onTrack ? '#46A302' : '#CE9700' }}
                >
                  {Math.round(pct)}%
                </span>
              </div>
              <div className="duo-progress-bar" style={{ height: '10px' }}>
                <div
                  className="h-full rounded-full transition-all duration-500"
                  style={{
                    width: `${pct}%`,
                    background: onTrack
                      ? 'linear-gradient(90deg, #58CC02, #91E62A)'
                      : 'linear-gradient(90deg, #FFD900, #FF9600)',
                  }}
                />
              </div>
              <p className="text-duo-gray font-bold text-xs mt-2">
                {onTrack ? '✅ ペース通り！' : `今日まで目標 ${expectedNow} セット`}
                {'  '}
                <span className="underline text-duo-green">詳細 →</span>
              </p>
            </div>
          );
        })()}

        {/* Today's set details */}
        {todaySets.length > 0 && (
          <div className="duo-card p-5">
            <h2 className="text-lg font-black text-duo-dark mb-4">📊 今日の記録</h2>
            <div className="space-y-3">
              {todaySets.map((set) => {
                const isExpanded = expandedSetId === set.id;
                const time = set.timestamp.toLocaleTimeString('ja-JP', { hour: '2-digit', minute: '2-digit' });
                return (
                  <div key={set.id} className="border-2 border-duo-border rounded-xl overflow-hidden">
                    <button
                      onClick={() => setExpandedSetId(isExpanded ? null : set.id)}
                      className="w-full px-4 py-3 flex items-center justify-between bg-white hover:bg-gray-50 transition-colors"
                    >
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 rounded-lg bg-duo-green/10 flex items-center justify-center">
                          <span className="text-lg font-black text-duo-green">
                            {todaySets.indexOf(set) + 1}
                          </span>
                        </div>
                        <div className="text-left">
                          <p className="font-black text-duo-dark text-sm">セット {todaySets.indexOf(set) + 1}</p>
                          <p className="text-duo-gray text-xs font-bold">{time} · {set.totalReps}回 · +{set.totalXP} XP</p>
                        </div>
                      </div>
                      <span className="text-duo-gray text-xl">{isExpanded ? '▼' : '▶'}</span>
                    </button>
                    {isExpanded && (
                      <div className="px-4 py-3 bg-gray-50 border-t-2 border-duo-border space-y-2">
                        {set.exercises.map((ex, idx) => (
                          <div key={idx} className="flex items-center justify-between py-2 px-3 bg-white rounded-lg">
                            <div className="flex items-center gap-2">
                              <span className="text-base">{getExerciseEmoji(ex.exerciseName)}</span>
                              <span className="font-bold text-duo-dark text-sm">{ex.exerciseName}</span>
                            </div>
                            <div className="flex items-center gap-3">
                              <span className="font-black text-duo-dark text-sm">{ex.reps}回</span>
                              <span className="font-extrabold text-xs" style={{ color: '#CE9700' }}>
                                +{ex.points} XP
                              </span>
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {/* Health Data Card - hidden on web, iOS only */}

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
