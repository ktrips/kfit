import React, { useEffect, useState } from 'react';
import { recordExercise } from '../services/firebase';
import { useAppStore } from '../store/appStore';

const EMOJI: Record<string, string> = {
  pushup: '💪', 'push-up': '💪',
  squat: '🏋️',
  situp: '🔥', 'sit-up': '🔥',
  lunge: '🦵',
  burpee: '⚡',
  plank: '🧘',
};
function getEmoji(id: string) { return EMOJI[id.toLowerCase()] ?? '⚡'; }

interface WorkoutStep {
  exerciseId: string;
  exerciseName: string;
  targetReps: number;
  basePoints: number;
}

interface Result {
  exerciseName: string;
  reps: number;
  points: number;
  emoji: string;
}

interface Props {
  onFinish: () => void;
}

export const DailyWorkoutFlow: React.FC<Props> = ({ onFinish }) => {
  const user = useAppStore((s) => s.user);
  const exercises = useAppStore((s) => s.exercises);
  const weeklyGoals = useAppStore((s) => s.weeklyGoals);

  // Build ordered exercise list from weekly goals (with dailyReps) or all exercises
  const steps: WorkoutStep[] = (() => {
    if (weeklyGoals.length > 0) {
      return weeklyGoals.map(g => {
        const def = exercises.find(e => e.id === g.exerciseId);
        return {
          exerciseId: g.exerciseId,
          exerciseName: g.exerciseName,
          targetReps: (g as any).dailyReps ?? 10,
          basePoints: def?.basePoints ?? 2,
        };
      });
    }
    return exercises.map(e => ({
      exerciseId: e.id,
      exerciseName: e.name,
      targetReps: 10,
      basePoints: e.basePoints,
    }));
  })();

  const [stepIdx, setStepIdx] = useState(0);
  const [reps, setReps] = useState(steps[0]?.targetReps ?? 10);
  const [phase, setPhase] = useState<'exercise' | 'feedback' | 'done'>('exercise');
  const [results, setResults] = useState<Result[]>([]);
  const [earnedXP, setEarnedXP] = useState(0);
  const [isSaving, setIsSaving] = useState(false);

  const current = steps[stepIdx];

  // Sync rep counter to new step
  useEffect(() => {
    if (current) setReps(current.targetReps);
  }, [stepIdx, current]);

  const totalXP = results.reduce((s, r) => s + r.points, 0);

  const handleDone = async () => {
    if (!user || !current || isSaving) return;
    setIsSaving(true);
    const pts = reps * current.basePoints;
    try {
      await recordExercise(user.uid, {
        exerciseId: current.exerciseId,
        exerciseName: current.exerciseName,
        reps,
        points: pts,
        formScore: 85,
      });
    } catch (e) {
      console.error(e);
    }
    setEarnedXP(pts);
    setResults(prev => [...prev, {
      exerciseName: current.exerciseName,
      reps,
      points: pts,
      emoji: getEmoji(current.exerciseId),
    }]);
    setIsSaving(false);
    setPhase('feedback');
    setTimeout(() => {
      if (stepIdx + 1 < steps.length) {
        setStepIdx(s => s + 1);
        setPhase('exercise');
      } else {
        setPhase('done');
      }
    }, 1400);
  };

  // ── Done screen ───────────────────────────────────────────────────────────
  if (phase === 'done') {
    return (
      <div className="min-h-screen bg-duo-gray-light flex flex-col items-center justify-center px-4 pb-10">
        <div className="max-w-md w-full text-center space-y-5">
          <img src="/mascot.png" alt="" className="w-32 h-32 rounded-full object-cover mx-auto animate-wiggle"
            style={{ border: '4px solid #58CC02' }} />
          <h2 className="text-4xl font-black text-duo-dark">完了！🎉</h2>
          <p className="text-duo-green font-extrabold text-lg">今日のメニュー全部やったね！</p>

          {/* Total XP */}
          <div
            className="py-4 rounded-2xl"
            style={{ background: '#FFF8E1', border: '3px solid #FFD900', boxShadow: '0 4px 0 #CE9700' }}
          >
            <p className="text-duo-gray font-bold text-xs uppercase tracking-wider mb-1">合計獲得XP</p>
            <p className="text-5xl font-black" style={{ color: '#CE9700' }}>+{totalXP}</p>
          </div>

          {/* Per-exercise summary */}
          <div className="space-y-2">
            {results.map((r, i) => (
              <div key={i}
                className="flex items-center justify-between rounded-2xl px-4 py-3"
                style={{ background: 'white', border: '2px solid #e5e5e5' }}
              >
                <div className="flex items-center gap-3">
                  <span className="text-2xl">{r.emoji}</span>
                  <div className="text-left">
                    <p className="font-extrabold text-duo-dark text-sm">{r.exerciseName}</p>
                    <p className="text-duo-gray font-bold text-xs">{r.reps} rep</p>
                  </div>
                </div>
                <span className="font-black" style={{ color: '#CE9700' }}>+{r.points} XP</span>
              </div>
            ))}
          </div>

          <button onClick={onFinish} className="duo-btn-primary w-full text-lg">
            ホームへ戻る 🏠
          </button>
        </div>
      </div>
    );
  }

  // ── Feedback flash ─────────────────────────────────────────────────────────
  if (phase === 'feedback') {
    return (
      <div className="min-h-screen bg-duo-gray-light flex flex-col items-center justify-center gap-6">
        <div
          className="w-28 h-28 rounded-full flex items-center justify-center text-6xl animate-bounce_in"
          style={{ background: '#D7FFB8', border: '4px solid #58CC02' }}
        >
          ✅
        </div>
        <div
          className="px-8 py-4 rounded-2xl font-black text-4xl animate-bounce_in"
          style={{ background: '#FFF8E1', border: '3px solid #FFD900', color: '#CE9700', boxShadow: '0 4px 0 #CE9700' }}
        >
          +{earnedXP} XP
        </div>
        <p className="font-extrabold text-duo-green text-xl">ナイス！💪</p>
      </div>
    );
  }

  // ── Exercise screen ────────────────────────────────────────────────────────
  const pct = ((stepIdx) / steps.length) * 100;

  return (
    <div className="min-h-screen bg-duo-gray-light flex flex-col">

      {/* Progress bar */}
      <div className="bg-white px-4 pt-4 pb-3" style={{ borderBottom: '2px solid #e5e5e5' }}>
        <div className="max-w-md mx-auto">
          <div className="flex items-center gap-3">
            <button
              onClick={onFinish}
              className="text-duo-gray font-black text-lg hover:text-duo-dark transition-colors"
            >
              ✕
            </button>
            {/* Segmented progress */}
            <div className="flex-1 flex gap-1.5">
              {steps.map((_, i) => (
                <div
                  key={i}
                  className="flex-1 h-3 rounded-full transition-all duration-500"
                  style={{
                    background: i < stepIdx
                      ? '#58CC02'
                      : i === stepIdx
                        ? 'linear-gradient(90deg, #58CC02, #91E62A)'
                        : '#e5e5e5',
                  }}
                />
              ))}
            </div>
            <span className="text-duo-gray font-bold text-xs shrink-0">
              {stepIdx + 1}/{steps.length}
            </span>
          </div>
        </div>
      </div>

      {/* Exercise card */}
      <div className="flex-1 flex flex-col items-center justify-center px-6 gap-8 max-w-md mx-auto w-full">

        {/* Exercise identity */}
        <div className="text-center">
          <div
            className="w-28 h-28 rounded-3xl flex items-center justify-center text-7xl mx-auto mb-4"
            style={{ background: '#D7FFB8', border: '3px solid #58CC02' }}
          >
            {getEmoji(current.exerciseId)}
          </div>
          <h2 className="text-3xl font-black text-duo-dark">{current.exerciseName}</h2>
          <p className="text-duo-gray font-bold text-base mt-1">
            目標 <span className="text-duo-green font-black">{current.targetReps}</span> rep
          </p>
        </div>

        {/* Rep counter */}
        <div className="w-full">
          <p className="text-center text-duo-gray font-extrabold text-xs uppercase tracking-widest mb-4">
            rep 数
          </p>
          <div className="flex items-center justify-center gap-8">
            <button
              onClick={() => setReps(r => Math.max(1, r - 1))}
              className="w-16 h-16 rounded-2xl font-black text-4xl flex items-center justify-center transition-all active:scale-90"
              style={{ background: '#E5E5E5', color: '#AFAFAF', boxShadow: '0 4px 0 #c0c0c0' }}
            >
              −
            </button>
            <span
              className="text-8xl font-black leading-none"
              style={{ color: '#58CC02', minWidth: '2.5ch', textAlign: 'center' }}
            >
              {reps}
            </span>
            <button
              onClick={() => setReps(r => r + 1)}
              className="w-16 h-16 rounded-2xl font-black text-4xl flex items-center justify-center transition-all active:scale-90"
              style={{ background: '#D7FFB8', color: '#46A302', boxShadow: '0 4px 0 #46A302' }}
            >
              ＋
            </button>
          </div>
          <p className="text-center font-extrabold text-sm mt-3" style={{ color: '#CE9700' }}>
            +{reps * current.basePoints} XP
          </p>
        </div>

        {/* Done button */}
        <button
          onClick={handleDone}
          disabled={isSaving}
          className="duo-btn-primary w-full text-2xl py-5"
          style={{ borderRadius: '1.25rem' }}
        >
          {isSaving ? '記録中…' : '完了！'}
        </button>

        {/* Skip */}
        <button
          onClick={() => {
            if (stepIdx + 1 < steps.length) { setStepIdx(s => s + 1); }
            else { setPhase('done'); }
          }}
          className="text-duo-gray font-bold text-sm hover:text-duo-dark transition-colors"
        >
          スキップ →
        </button>
      </div>
    </div>
  );
};
