import React, { useEffect, useState } from 'react';
import {
  getWeeklyGoals,
  setWeeklyGoals,
  getWeeklyProgress,
  getWeekLabel,
  type WeeklyGoal,
  type WeeklyProgress,
} from '../services/firebase';
import { useAppStore } from '../store/appStore';

const EXERCISE_EMOJI: Record<string, string> = {
  pushup: '💪', 'push-up': '💪',
  squat: '🏋️',
  situp: '🔥', 'sit-up': '🔥',
  lunge: '🦵',
  burpee: '⚡',
  plank: '🧘',
};

function emoji(id: string) {
  return EXERCISE_EMOJI[id.toLowerCase()] ?? '🏃';
}

const GOAL_COLORS = [
  { bg: '#D7FFB8', border: '#58CC02', shadow: '#46A302', text: '#2d7a00' },
  { bg: '#E3F2FD', border: '#1CB0F6', shadow: '#0E8FC5', text: '#0a6c96' },
  { bg: '#FFF3E0', border: '#FF9600', shadow: '#CC7000', text: '#8a4700' },
  { bg: '#F3E5F5', border: '#CE82FF', shadow: '#9C27B0', text: '#6a1b9a' },
  { bg: '#FCE4EC', border: '#FF4B4B', shadow: '#C62828', text: '#7f0000' },
  { bg: '#FFF8E1', border: '#FFD900', shadow: '#CE9700', text: '#7a5800' },
];

const ACTIVE_DAYS = 5; // 7 - 2 rest days

export const WeeklyGoalView: React.FC = () => {
  const user = useAppStore((s) => s.user);
  const exercises = useAppStore((s) => s.exercises);
  const setStoreGoals = useAppStore((s) => s.setWeeklyGoals);
  const setStoreProgress = useAppStore((s) => s.setWeeklyProgress);

  const [goals, setGoals] = useState<WeeklyGoal[]>([]);
  const [progress, setProgress] = useState<WeeklyProgress>({});
  const [drafts, setDrafts] = useState<Record<string, number>>({});
  const [isEditing, setIsEditing] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    if (!user) return;
    (async () => {
      const [g, p] = await Promise.all([
        getWeeklyGoals(user.uid),
        getWeeklyProgress(user.uid),
      ]);
      setGoals(g);
      setProgress(p);
      setStoreGoals(g);
      setStoreProgress(p);
      const d: Record<string, number> = {};
      exercises.forEach(ex => {
        const existing = g.find(x => x.exerciseId === ex.id);
        d[ex.id] = existing?.dailyReps ?? 0;
      });
      setDrafts(d);
      setIsLoading(false);
      if (g.length === 0) setIsEditing(true);
    })();
  }, [user, exercises, setStoreGoals, setStoreProgress]);

  const handleSave = async () => {
    if (!user) return;
    setIsSaving(true);
    const newGoals: WeeklyGoal[] = exercises
      .filter(ex => (drafts[ex.id] ?? 0) > 0)
      .map(ex => ({
        exerciseId: ex.id,
        exerciseName: ex.name,
        dailyReps: drafts[ex.id],
        targetReps: drafts[ex.id] * ACTIVE_DAYS,
      }));
    await setWeeklyGoals(user.uid, newGoals);
    setGoals(newGoals);
    setStoreGoals(newGoals);
    setIsSaving(false);
    setIsEditing(false);
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
  };

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

  const hasGoals = goals.length > 0;
  const weekLabel = getWeekLabel();

  const totalTarget = goals.reduce((s, g) => s + g.targetReps, 0);
  const totalDone = goals.reduce((s, g) => s + (progress[g.exerciseId] ?? 0), 0);
  const overallPct = totalTarget > 0 ? Math.min((totalDone / totalTarget) * 100, 100) : 0;

  return (
    <div className="min-h-screen bg-duo-gray-light pb-10">
      <div className="max-w-md mx-auto px-4 pt-6 space-y-4">

        {/* Header */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <img src="/mascot.png" alt="" className="w-12 h-12 rounded-full object-cover shrink-0" />
            <div>
              <h2 className="text-2xl font-black text-duo-dark">週間目標</h2>
              <p className="text-duo-gray font-bold text-sm">📅 {weekLabel}</p>
            </div>
          </div>
          {hasGoals && !isEditing && (
            <button
              onClick={() => setIsEditing(true)}
              className="duo-btn-secondary px-4 py-2 text-sm"
            >
              ✏️ 編集
            </button>
          )}
        </div>

        {/* Rule hint */}
        <div
          className="rounded-2xl px-4 py-2 flex items-center gap-2"
          style={{ background: '#E3F2FD', border: '1.5px solid #1CB0F6' }}
        >
          <span className="text-lg">💡</span>
          <p className="font-bold text-sm" style={{ color: '#0a6c96' }}>
            1日の目標 × 5日（週2日休息）= 週間目標
          </p>
        </div>

        {/* Overall progress */}
        {hasGoals && !isEditing && (
          <div
            className="duo-card p-5"
            style={{ borderColor: overallPct >= 100 ? '#58CC02' : '#FFD900', boxShadow: `0 4px 0 ${overallPct >= 100 ? '#46A302' : '#CE9700'}` }}
          >
            <div className="flex items-center justify-between mb-2">
              <p className="font-extrabold text-duo-dark text-base">
                {overallPct >= 100 ? '🎉 今週の目標達成！' : '🎯 今週の総合進捗'}
              </p>
              <p className="font-black text-lg" style={{ color: overallPct >= 100 ? '#46A302' : '#CE9700' }}>
                {Math.round(overallPct)}%
              </p>
            </div>
            <div className="duo-progress-bar">
              <div className="duo-progress-fill" style={{ width: `${overallPct}%` }} />
            </div>
            <p className="text-duo-gray font-bold text-sm mt-2">
              {totalDone} / {totalTarget} rep 完了
            </p>
          </div>
        )}

        {/* Edit mode */}
        {isEditing ? (
          <div className="duo-card p-5 space-y-4">
            <div>
              <p className="text-duo-dark font-extrabold text-sm uppercase tracking-wider">
                1日のセット数を設定
              </p>
              <p className="text-duo-gray font-bold text-xs mt-0.5">週間目標は自動で × 5 計算されます</p>
            </div>
            {exercises.map((ex, i) => {
              const col = GOAL_COLORS[i % GOAL_COLORS.length];
              const daily = drafts[ex.id] ?? 0;
              const weekly = daily * ACTIVE_DAYS;
              return (
                <div
                  key={ex.id}
                  className="rounded-2xl p-4"
                  style={{ backgroundColor: col.bg, border: `2px solid ${col.border}` }}
                >
                  <div className="flex items-center gap-3 mb-3">
                    <span className="text-3xl shrink-0">{emoji(ex.id)}</span>
                    <div className="flex-1 min-w-0">
                      <p className="font-black text-duo-dark">{ex.name}</p>
                      <p className="text-xs font-bold" style={{ color: col.text }}>{ex.basePoints} XP / rep</p>
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    <button
                      onClick={() => setDrafts(d => ({ ...d, [ex.id]: Math.max(0, (d[ex.id] ?? 0) - 5) }))}
                      className="w-9 h-9 rounded-full font-black text-lg flex items-center justify-center shrink-0"
                      style={{ background: 'white', border: `2px solid ${col.border}`, color: col.text }}
                    >−</button>
                    <div className="flex-1 text-center">
                      <div className="flex items-end justify-center gap-1">
                        <input
                          type="number"
                          min={0}
                          value={daily}
                          onChange={e => setDrafts(d => ({ ...d, [ex.id]: Math.max(0, parseInt(e.target.value) || 0) }))}
                          className="w-16 text-center font-black text-2xl rounded-xl py-1 outline-none"
                          style={{ border: `2px solid ${col.border}`, color: col.text, background: 'white' }}
                        />
                        <span className="font-bold text-sm pb-1.5" style={{ color: col.text }}>rep/日</span>
                      </div>
                      {daily > 0 && (
                        <p className="text-xs font-extrabold mt-1" style={{ color: col.shadow }}>
                          週間目標: {weekly} rep
                        </p>
                      )}
                    </div>
                    <button
                      onClick={() => setDrafts(d => ({ ...d, [ex.id]: (d[ex.id] ?? 0) + 5 }))}
                      className="w-9 h-9 rounded-full font-black text-lg flex items-center justify-center shrink-0"
                      style={{ background: col.border, color: 'white' }}
                    >＋</button>
                  </div>
                </div>
              );
            })}

            <div className="flex gap-3 pt-2">
              {hasGoals && (
                <button
                  onClick={() => setIsEditing(false)}
                  className="duo-btn-secondary flex-1 text-base py-3"
                >
                  キャンセル
                </button>
              )}
              <button
                onClick={handleSave}
                disabled={isSaving || Object.values(drafts).every(v => v === 0)}
                className="duo-btn-primary flex-1 text-base py-3"
              >
                {isSaving ? '保存中...' : saved ? '✓ 保存済み！' : '目標を保存'}
              </button>
            </div>
          </div>
        ) : hasGoals ? (
          /* Progress mode */
          <div className="space-y-3">
            {goals.map((goal, i) => {
              const done = progress[goal.exerciseId] ?? 0;
              const pct = Math.min((done / goal.targetReps) * 100, 100);
              const col = GOAL_COLORS[i % GOAL_COLORS.length];
              const isComplete = pct >= 100;
              return (
                <div
                  key={goal.exerciseId}
                  className="duo-card p-4"
                  style={{ borderColor: isComplete ? '#58CC02' : col.border, boxShadow: `0 4px 0 ${isComplete ? '#46A302' : col.shadow}` }}
                >
                  <div className="flex items-center gap-3 mb-3">
                    <span className="text-3xl">{emoji(goal.exerciseId)}</span>
                    <div className="flex-1">
                      <div className="flex items-center justify-between">
                        <p className="font-black text-duo-dark">{goal.exerciseName}</p>
                        {isComplete && <span className="text-lg">✅</span>}
                      </div>
                      <div className="flex items-center gap-2">
                        <p className="text-xs font-bold" style={{ color: isComplete ? '#46A302' : col.text }}>
                          {done} / {goal.targetReps} rep
                        </p>
                        <span className="text-xs text-duo-gray">·</span>
                        <p className="text-xs font-bold text-duo-gray">
                          1日 {goal.dailyReps} rep × 5日
                        </p>
                      </div>
                    </div>
                    <p className="font-black text-xl shrink-0" style={{ color: isComplete ? '#46A302' : col.text }}>
                      {Math.round(pct)}%
                    </p>
                  </div>
                  <div className="duo-progress-bar" style={{ height: '12px' }}>
                    <div
                      className="h-full rounded-full transition-all duration-500"
                      style={{
                        width: `${pct}%`,
                        background: isComplete
                          ? 'linear-gradient(90deg, #58CC02, #91E62A)'
                          : `linear-gradient(90deg, ${col.border}, ${col.bg})`,
                      }}
                    />
                  </div>
                </div>
              );
            })}
          </div>
        ) : null}

        {/* Empty state */}
        {!hasGoals && !isEditing && (
          <div className="duo-card p-8 text-center flex flex-col items-center gap-4">
            <img src="/mascot.png" alt="" className="w-24 h-24 rounded-full object-cover" />
            <p className="text-duo-dark font-extrabold text-lg">今週の目標を設定しよう！</p>
            <button onClick={() => setIsEditing(true)} className="duo-btn-primary text-base">
              目標を設定する
            </button>
          </div>
        )}

      </div>
    </div>
  );
};
