import React, { useEffect, useState } from 'react';
import {
  getDashboardData,
  getWeekLabel, getActiveDaysElapsed,
  type WeeklySetProgress, type CompletedSetRecord, type CompletedExercise,
} from '../services/firebase';
import { getGlobalProgress } from '../services/timeSlotService';
import { getDietGoalSettings } from '../services/wellnessService';
import { useAppStore } from '../store/appStore';
import type { GlobalProgress } from '../services/timeSlotService';
import type { DietGoalSettings } from '../types/wellness';

interface DashboardViewProps {
  onStartWorkout?: () => void;
  onLogWorkout?: () => void;
  onWeeklyGoal?: () => void;
  onWorkoutPlan?: () => void;

  onDietGoal?: () => void;

}

const EXERCISE_EMOJI: Record<string, string> = {
  'push-up': '💪', 'pushup': '💪',
  'squat':   '🏋️',
  'sit-up':  '🔥', 'situp': '🔥',
  'lunge':   '🦵',
  'plank':   '🧘',
};

function getExerciseEmoji(name: string): string {
  const key = (name ?? '').toLowerCase().replace(/\s+/g, '-');
  for (const [k, v] of Object.entries(EXERCISE_EMOJI)) {
    if (key.includes(k)) return v;
  }
  return '⚡';
}

function getTimePeriod(date: Date): { label: string; emoji: string } {
  const h = date.getHours();
  if (h < 6)  return { label: '深夜', emoji: '🌙' };
  if (h < 12) return { label: '午前', emoji: '🌅' };
  if (h < 15) return { label: '昼',   emoji: '☀️' };
  if (h < 19) return { label: '午後', emoji: '🌤️' };
  return { label: '夜', emoji: '🌆' };
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

export const DashboardView: React.FC<DashboardViewProps> = ({ onStartWorkout, onWeeklyGoal, onWorkoutPlan, onDietGoal }) => {
  const user = useAppStore((state) => state.user);
  const userProfile = useAppStore((state) => state.userProfile);
  const setStoreWeeklyGoals = useAppStore((s) => s.setWeeklyGoals);
  const setStoreWeeklyProgress = useAppStore((s) => s.setWeeklyProgress);

  const [totalReps, setTotalReps] = useState(0);
  const [totalPoints, setTotalPoints] = useState(0);
  const [totalCalories, setTotalCalories] = useState(0);
  const [weeklyGoals, setWeeklyGoals] = useState<{ exerciseId: string; exerciseName: string; targetReps: number; dailyReps?: number }[]>([]);
  const [setProgress, setSetProgress] = useState<WeeklySetProgress>({ completedSets: 0, exercises: {} });
  const [dailySets, setDailySets] = useState(2);
  const [todaySetCount, setTodaySetCount] = useState(0);
  const [todaySets, setTodaySets] = useState<CompletedSetRecord[]>([]);
  const [_globalProgress, setGlobalProgress] = useState<GlobalProgress | null>(null);
  const [dietGoal, setDietGoal] = useState<DietGoalSettings | null>(null);
  const [expandedSetId, setExpandedSetId] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    const loadData = async () => {
      if (!user) return;
      try {
        const [dashboard, global, diet] = await Promise.all([
          getDashboardData(user.uid),
          getGlobalProgress(user.uid),
          getDietGoalSettings(user.uid),
        ]);
        if (cancelled) return;
        const exercises = dashboard.todayExercises;
        setTotalReps(exercises.reduce((s: number, e: CompletedExercise) => s + (e.reps || 0), 0));
        setTotalPoints(exercises.reduce((s: number, e: CompletedExercise) => s + (e.points || 0), 0));
        setTotalCalories(Math.round(
          exercises.reduce((s: number, e: CompletedExercise) => s + estimateKcal(e.exerciseId ?? '', e.reps || 0), 0)
        ));
        setWeeklyGoals(dashboard.weeklyGoals);
        setStoreWeeklyGoals(dashboard.weeklyGoals);
        setStoreWeeklyProgress(dashboard.weeklyProgress);
        setSetProgress(dashboard.setProgress);
        setDailySets(dashboard.dailySets);
        setTodaySetCount(dashboard.todaySetCount);
        setGlobalProgress(global);
        setDietGoal(diet);
        // 今日分だけフィルタ
        const today = new Date();
        setTodaySets(dashboard.weeklySetLog.filter(s => {
          const d = s.timestamp;
          return d.getFullYear() === today.getFullYear() &&
                 d.getMonth() === today.getMonth() &&
                 d.getDate() === today.getDate();
        }));
      } catch (err) {
        if (!cancelled) console.error('Error loading dashboard:', err);
      } finally {
        if (!cancelled) setIsLoading(false);
      }
    };
    loadData();
    return () => { cancelled = true; };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user?.uid]);

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

        {/* Fitingo workout GIF — タップでトレーニング開始 */}
        <button
          onClick={onStartWorkout}
          className="w-full relative overflow-hidden rounded-3xl active:scale-[0.98] transition-transform"
          style={{ boxShadow: '0 6px 0 #46A302', border: '3px solid #58CC02' }}
          aria-label="トレーニングを始める"
        >
          <img
            src="/fitingo_workout.gif"
            alt="Fitingo workout"
            className="w-full object-cover"
            style={{ display: 'block', maxHeight: '320px', objectPosition: 'center' }}
          />
          {/* オーバーレイ */}
          <div
            className="absolute inset-x-0 bottom-0 flex items-center justify-center gap-3 py-4"
            style={{ background: 'linear-gradient(to top, rgba(0,0,0,0.72) 0%, transparent 100%)' }}
          >
            <span className="text-white font-black text-xl drop-shadow">🏋️ トレーニングを始める</span>
            <span className="text-white text-xl">›</span>
          </div>
        </button>

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
            <p className="text-2xl font-black text-duo-green leading-tight">{totalReps}回</p>
            <p className="text-sm font-extrabold leading-none" style={{ color: '#46A302' }}>
              {totalCalories}kcal
            </p>
            <p className="text-xs font-extrabold text-duo-green-dark uppercase tracking-wide mt-0.5">今日</p>
          </div>
          <div className="duo-stat-card" style={{ backgroundColor: '#FFF8E1', borderColor: '#FFD900', boxShadow: '0 3px 0 #CE9700' }}>
            <span className="text-3xl">⭐</span>
            <p className="text-3xl font-black" style={{ color: '#CE9700' }}>{totalPoints}</p>
            <p className="text-xs font-extrabold uppercase tracking-wide" style={{ color: '#CE9700' }}>今日のXP</p>
          </div>
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

        {/* Today's set details */}
        {todaySets.length > 0 && (
          <div className="duo-card p-5">
            <h2 className="text-lg font-black text-duo-dark mb-4">📊 今日の記録</h2>
            <div className="space-y-3">
              {todaySets.map((set, idx) => {
                const isExpanded = expandedSetId === set.id;
                const time = set.timestamp.toLocaleTimeString('ja-JP', { hour: '2-digit', minute: '2-digit' });
                const period = getTimePeriod(set.timestamp);
                return (
                  <div key={set.id} className="border-2 border-duo-border rounded-xl overflow-hidden">
                    <button
                      onClick={() => setExpandedSetId(isExpanded ? null : set.id)}
                      className="w-full px-4 py-3 flex items-center justify-between bg-white hover:bg-gray-50 transition-colors"
                    >
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 rounded-lg bg-duo-green/10 flex items-center justify-center text-lg shrink-0">
                          {period.emoji}
                        </div>
                        <div className="text-left">
                          <p className="font-black text-duo-dark text-sm">{period.label} セット{idx + 1}</p>
                          <p className="text-duo-gray text-xs font-bold">{time} · {set.totalReps}回 · +{set.totalXP} XP</p>
                        </div>
                      </div>
                      <span className="text-duo-gray text-xl">{isExpanded ? '▼' : '▶'}</span>
                    </button>
                    {isExpanded && (
                      <div className="px-4 py-3 bg-gray-50 border-t-2 border-duo-border space-y-2">
                        {set.exercises.map((ex, exIdx) => {
                          const isPlankEx = (ex.exerciseId ?? '').toLowerCase().includes('plank');
                          return (
                            <div key={exIdx} className="flex items-center justify-between py-2 px-3 bg-white rounded-lg">
                              <div className="flex items-center gap-2">
                                <span className="text-base">{getExerciseEmoji(ex.exerciseName)}</span>
                                <span className="font-bold text-duo-dark text-sm">{ex.exerciseName}</span>
                              </div>
                              <div className="flex items-center gap-3">
                                <span className="font-black text-duo-dark text-sm">
                                  {ex.reps}{isPlankEx ? '秒' : '回'}
                                </span>
                                <span className="font-extrabold text-xs" style={{ color: '#CE9700' }}>
                                  +{ex.points} XP
                                </span>
                              </div>
                            </div>
                          );
                        })}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {/* ── DIET card (大) ── */}
        {(() => {
          const cw = dietGoal?.currentWeightKg ?? 0;
          const gw = dietGoal?.goalWeightKg ?? 0;
          const sw = dietGoal?.startWeightKg ?? 0;
          const cf = dietGoal?.currentBodyFatPercent ?? 0;
          const sf = dietGoal?.startBodyFatPercent ?? 0;
          const gf = dietGoal?.goalBodyFatPercent ?? 0;

          const totalWd = sw > 0 && gw > 0 ? sw - gw : 0;
          const doneWd  = sw > 0 && cw > 0 ? sw - cw : 0;
          const weightPct = totalWd !== 0 ? Math.min(100, Math.max(0, Math.round((doneWd / totalWd) * 100))) : 0;

          // 期間進捗
          const timePct = (() => {
            if (!dietGoal?.startDate || !dietGoal?.goalDate) return 0;
            const s = new Date(dietGoal.startDate).getTime();
            const g = new Date(dietGoal.goalDate).getTime();
            const n = Date.now();
            if (g <= s) return 0;
            return Math.min(100, Math.max(0, Math.round(((n - s) / (g - s)) * 100)));
          })();

          const diffFromStart = cw > 0 && sw > 0 ? cw - sw : 0;
          const diffToGoal    = cw > 0 && gw > 0 ? cw - gw : 0;

          const fmt = (d: string) => {
            if (!d) return '—';
            const dt = new Date(d);
            return `${dt.getMonth() + 1}/${dt.getDate()}`;
          };

          const motivationMsg = (() => {
            if (cw === 0) return null;
            if (diffToGoal <= 0) return '🎉 目標達成！';
            if (weightPct >= 50) return '👏 折り返し地点を超えました！';
            if (weightPct >= 25) return '💪 順調です！食事記録を続けよう！';
            return '🔥 食事記録を続けよう！';
          })();

          return (
            <button
              onClick={onDietGoal}
              className="w-full bg-white rounded-2xl p-5 text-left active:scale-[0.98] transition-transform"
              style={{ border: '2px solid #E8D0FF', boxShadow: '0 4px 0 #A15FD4' }}
            >
              {/* ヘッダー */}
              <div className="flex items-center justify-between mb-4">
                <span className="text-xs font-black tracking-wider" style={{ color: '#CE82FF' }}>🎯 DIET</span>
                {dietGoal?.goalDate && (
                  <span className="text-[10px] font-bold px-2 py-0.5 rounded-full text-white" style={{ background: '#CE82FF' }}>
                    ゴール {fmt(dietGoal.goalDate)}
                  </span>
                )}
              </div>

              {cw > 0 ? (
                <>
                  {/* ── 3列: スタート → 今日 → ゴール ── */}
                  <div className="flex items-start justify-between mb-4">
                    {/* スタート */}
                    <div className="text-left">
                      <p className="text-[9px] font-bold text-gray-400 mb-0.5">スタート</p>
                      {dietGoal?.startDate && (
                        <p className="text-[9px] font-bold text-gray-400 mb-1">{fmt(dietGoal.startDate)}</p>
                      )}
                      <p className="text-xl font-black text-gray-700">{sw.toFixed(1)}<span className="text-xs font-bold text-gray-400">kg</span></p>
                      {sf > 0 && <p className="text-[9px] font-bold text-gray-400">体脂肪 {sf.toFixed(0)}%</p>}
                    </div>

                    {/* スタート→今日 差分 */}
                    <div className="flex flex-col items-center justify-center pt-4 gap-0.5">
                      <span className="text-[9px] font-black" style={{ color: diffFromStart <= 0 ? '#58CC02' : '#FF4B4B' }}>
                        {diffFromStart !== 0 ? `${diffFromStart > 0 ? '+' : ''}${diffFromStart.toFixed(1)}kg` : ''}
                      </span>
                      <span className="text-gray-300 text-base">→</span>
                    </div>

                    {/* 今日 */}
                    <div className="text-center">
                      <p className="text-[9px] font-bold text-gray-400 mb-0.5">今日</p>
                      <p className="text-[9px] font-bold text-gray-400 mb-1">今日</p>
                      <p className="text-3xl font-black" style={{ color: '#58CC02' }}>{cw.toFixed(1)}<span className="text-sm font-bold text-gray-400">kg</span></p>
                      {cf > 0 && <p className="text-[9px] font-bold text-gray-400">体脂肪 {cf.toFixed(0)}%</p>}
                    </div>

                    {/* 今日→ゴール 差分 */}
                    <div className="flex flex-col items-center justify-center pt-4 gap-0.5">
                      <span className="text-[9px] font-black" style={{ color: diffToGoal > 0 ? '#FF9600' : '#58CC02' }}>
                        {diffToGoal !== 0 ? `${diffToGoal > 0 ? '' : '+'}${(-diffToGoal).toFixed(1)}kg` : ''}
                      </span>
                      <span className="text-gray-300 text-base">→</span>
                    </div>

                    {/* ゴール */}
                    <div className="text-right">
                      <p className="text-[9px] font-bold text-gray-400 mb-0.5">ゴール</p>
                      {dietGoal?.goalDate && (
                        <p className="text-[9px] font-bold text-gray-400 mb-1">{fmt(dietGoal.goalDate)}</p>
                      )}
                      <p className="text-xl font-black" style={{ color: '#58CC02' }}>{gw.toFixed(1)}<span className="text-xs font-bold text-gray-400">kg</span></p>
                      {gf > 0 && <p className="text-[9px] font-bold text-gray-400">体脂肪 {gf.toFixed(0)}%</p>}
                    </div>
                  </div>

                  {/* ── 進捗バー 2本 ── */}
                  <div className="space-y-2.5">
                    {/* 期間進捗 */}
                    <div>
                      <div className="flex justify-between items-center mb-1">
                        <span className="text-[10px] font-black text-gray-600">期間進捗</span>
                        <span className="text-[10px] font-black text-gray-600">{timePct}%</span>
                      </div>
                      <div className="rounded-full bg-gray-100" style={{ height: 8 }}>
                        <div className="rounded-full h-full transition-all duration-500" style={{ width: `${timePct}%`, background: 'linear-gradient(90deg,#58CC02,#46A302)' }} />
                      </div>
                    </div>
                    {/* 体重進捗 */}
                    <div>
                      <div className="flex justify-between items-center mb-1">
                        <span className="text-[10px] font-black text-gray-600">体重進捗</span>
                        <span className="text-[10px] font-black text-gray-600">{weightPct}%</span>
                      </div>
                      <div className="rounded-full bg-gray-100" style={{ height: 8 }}>
                        <div className="rounded-full h-full transition-all duration-500" style={{ width: `${weightPct}%`, background: 'linear-gradient(90deg,#CE82FF,#58CC02)' }} />
                      </div>
                    </div>
                  </div>

                  {/* モチベーションメッセージ */}
                  {motivationMsg && (
                    <p className="text-center text-sm font-black mt-3" style={{ color: '#58CC02' }}>{motivationMsg}</p>
                  )}
                </>
              ) : (
                <div className="text-center py-4">
                  <p className="text-sm font-bold text-gray-400 mb-2">ダイエット目標が未設定です</p>
                  <p className="text-xs font-bold" style={{ color: '#CE82FF' }}>タップして設定 →</p>
                </div>
              )}
            </button>
          );
        })()}

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

        {/* ── プロモーションカード ── */}
        <div className="pt-2">
          <p className="text-[10px] font-black text-duo-gray tracking-widest uppercase mb-3 px-1">関連情報</p>

          <div className="flex flex-col gap-3">

            {/* iOS アプリ */}
            <a
              href="https://apps.apple.com/app/fitingo/id000000000"
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-4 bg-white rounded-2xl p-4 hover:shadow-md active:scale-[0.98] transition-all"
              style={{ border: '2px solid #e5e5e5', boxShadow: '0 3px 0 #e5e5e5' }}
            >
              <div className="w-12 h-12 rounded-2xl bg-black flex items-center justify-center shrink-0">
                <svg className="w-7 h-7 text-white" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/>
                </svg>
              </div>
              <div className="flex-1 min-w-0">
                <p className="font-black text-duo-dark text-sm">📱 Fitingo iOSアプリ</p>
                <p className="text-xs text-duo-gray font-semibold mt-0.5">Apple Watch連携・モーションセンサーで本格トレーニング</p>
                <p className="text-[10px] text-duo-gray mt-0.5">App Store でダウンロード</p>
              </div>
              <span className="text-duo-gray shrink-0">›</span>
            </a>

            {/* AppleWatch Diet 本 */}
            <a
              href="https://amzn.to/4eEsrPg"
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-4 bg-white rounded-2xl p-4 hover:shadow-md active:scale-[0.98] transition-all"
              style={{ border: '2px solid #C8F0D8', boxShadow: '0 3px 0 #A0D8B8' }}
            >
              <div className="w-12 h-12 rounded-2xl flex items-center justify-center shrink-0 text-3xl"
                style={{ background: '#E8F8F0' }}>
                ⌚
              </div>
              <div className="flex-1 min-w-0">
                <p className="font-black text-sm" style={{ color: '#2D8A50' }}>AppleWatch Diet Ultra2</p>
                <p className="text-xs text-duo-gray font-semibold mt-0.5">Apple Watchで痩せる100のメソッド</p>
                <p className="text-[10px] font-bold mt-0.5" style={{ color: '#E8A020' }}>📖 Kindle で読む</p>
              </div>
              <span className="text-duo-gray shrink-0">›</span>
            </a>

            {/* Cursor + Claude 本 */}
            <a
              href="https://amzn.to/4aYIyGj"
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-4 bg-white rounded-2xl p-4 hover:shadow-md active:scale-[0.98] transition-all"
              style={{ border: '2px solid #C8D8F8', boxShadow: '0 3px 0 #A0B8E8' }}
            >
              <div className="w-12 h-12 rounded-2xl flex items-center justify-center shrink-0 text-3xl"
                style={{ background: '#EEF2FF' }}>
                📱
              </div>
              <div className="flex-1 min-w-0">
                <p className="font-black text-sm" style={{ color: '#2D50A0' }}>Cursor + Claude で iOS アプリを作る</p>
                <p className="text-xs text-duo-gray font-semibold mt-0.5">週末だけで iPhone・Apple Watch アプリを個人開発</p>
                <p className="text-[10px] font-bold mt-0.5" style={{ color: '#E8A020' }}>📖 Kindle で読む</p>
              </div>
              <span className="text-duo-gray shrink-0">›</span>
            </a>

          </div>
        </div>

      </div>
    </div>
  );
};
