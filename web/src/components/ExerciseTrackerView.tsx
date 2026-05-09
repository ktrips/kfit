import React, { useState } from 'react';
import { recordExercise, getUserProfile } from '../services/firebase';
import { useAppStore } from '../store/appStore';
interface ExerciseTrackerProps {
  onSuccess?: () => void;
  onBack?: () => void;
}

interface ExerciseCfg {
  emoji: string;
  bg: string;
  border: string;
  shadow: string;
  numColor: string;
}

const EXERCISE_CFG: Record<string, ExerciseCfg> = {
  default:   { emoji: '⚡', bg: '#F7F7F7', border: '#e5e5e5', shadow: '#c5c5c5', numColor: '#3C3C3C' },
  'push-up': { emoji: '💪', bg: '#D7FFB8', border: '#58CC02', shadow: '#46A302', numColor: '#2d7a00' },
  'pushup':  { emoji: '💪', bg: '#D7FFB8', border: '#58CC02', shadow: '#46A302', numColor: '#2d7a00' },
  'squat':   { emoji: '🏋️', bg: '#E3F2FD', border: '#1CB0F6', shadow: '#0E8FC5', numColor: '#0a6c96' },
  'sit-up':  { emoji: '🔥', bg: '#FFF3E0', border: '#FF9600', shadow: '#CC7000', numColor: '#8a4700' },
  'situp':   { emoji: '🔥', bg: '#FFF3E0', border: '#FF9600', shadow: '#CC7000', numColor: '#8a4700' },
};

function getCfg(name: string): ExerciseCfg {
  const key = (name ?? '').toLowerCase().replace(/\s+/g, '-');
  for (const [k, v] of Object.entries(EXERCISE_CFG)) {
    if (k !== 'default' && key.includes(k)) return v;
  }
  return EXERCISE_CFG.default;
}

export const ExerciseTrackerView: React.FC<ExerciseTrackerProps> = ({ onSuccess, onBack }) => {
  const user = useAppStore((state) => state.user);
  const exercises = useAppStore((state) => state.exercises);
  const updateUserPoints = useAppStore((state) => state.updateUserPoints);
  const setUserProfile = useAppStore((state) => state.setUserProfile);
  const setError = useAppStore((state) => state.setError);

  const [selectedId, setSelectedId] = useState('');
  const [reps, setReps] = useState(0);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [earnedPoints, setEarnedPoints] = useState(0);
  const [showCelebration, setShowCelebration] = useState(false);

  const selected = exercises.find((e) => e.id === selectedId);
  const cfg = selected ? getCfg(selected.name) : EXERCISE_CFG.default;
  const preview = reps * (selected?.basePoints || 0);

  const addRep = () => setReps((r) => r + 1);
  const removeRep = () => { if (reps > 0) setReps((r) => r - 1); };

  // Keyboard shortcuts
  React.useEffect(() => {
    const handleKeyPress = (e: KeyboardEvent) => {
      if (!selectedId) return;
      if (e.key === '+' || e.key === 'ArrowUp') {
        e.preventDefault();
        addRep();
      } else if (e.key === '-' || e.key === 'ArrowDown') {
        e.preventDefault();
        removeRep();
      } else if (e.key === 'Enter' && reps > 0) {
        e.preventDefault();
        handleSubmit();
      }
    };
    window.addEventListener('keydown', handleKeyPress);
    return () => window.removeEventListener('keydown', handleKeyPress);
  }, [selectedId, reps]);

  const handleSubmit = async () => {
    if (!user || !selectedId || reps === 0) {
      setError('エクササイズを選んでレップ数を入力してください');
      return;
    }
    setIsSubmitting(true);
    try {
      const pts = reps * (selected?.basePoints || 10);
      await recordExercise(user.uid, {
        exerciseId: selectedId,
        exerciseName: selected?.name,
        reps,
        points: pts,
        formScore: 85,
      });
      updateUserPoints(pts);
      const refreshed = await getUserProfile(user.uid);
      if (refreshed) setUserProfile(refreshed as any);
      setEarnedPoints(pts);
      setShowCelebration(true);
      setTimeout(() => {
        setShowCelebration(false);
        setReps(0);
        setSelectedId('');
        onSuccess?.();
      }, 2000);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'エラーが発生しました');
    } finally {
      setIsSubmitting(false);
    }
  };

  if (showCelebration) {
    return (
      <div className="min-h-screen bg-duo-gray-light flex items-center justify-center">
        <div className="text-center animate-bounce_in flex flex-col items-center gap-4">
          <img src="/mascot.png" alt="mascot" className="w-36 h-36 rounded-full object-cover animate-wiggle" style={{ border: '4px solid #58CC02' }} />
          <p className="text-5xl font-black text-duo-green">やったー！🎉</p>
          <div
            className="px-8 py-4 rounded-2xl font-black text-3xl"
            style={{ background: '#FFF8E1', border: '3px solid #FFD900', boxShadow: '0 4px 0 #CE9700', color: '#CE9700' }}
          >
            +{earnedPoints} XP 獲得！
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-duo-gray-light pb-10">
      <div className="max-w-md mx-auto px-4 pt-6 space-y-4">

        {/* Header */}
        <div className="flex items-center gap-3 mb-2">
          {onBack && (
            <button
              onClick={onBack}
              className="shrink-0 w-10 h-10 rounded-full flex items-center justify-center bg-white border-2 border-duo-border hover:bg-gray-50 transition-colors"
              aria-label="戻る"
            >
              <span className="text-duo-gray font-black text-lg">←</span>
            </button>
          )}
          <img src="/mascot.png" alt="mascot" className="w-14 h-14 rounded-full object-cover shrink-0" />
          <div className="flex-1">
            <h2 className="text-2xl font-black text-duo-dark">トレーニング記録</h2>
            <p className="text-duo-gray font-bold text-sm">種目を選んでレップ数を入力！</p>
          </div>
        </div>

        {/* Exercise selection */}
        <div className="duo-card p-5">
          <p className="text-duo-dark font-extrabold mb-3 text-xs uppercase tracking-wider">エクササイズ選択</p>
          <div className="flex flex-col gap-3">
            {exercises.map((ex) => {
              const c = getCfg(ex.name);
              const isSelected = selectedId === ex.id;
              return (
                <button
                  key={ex.id}
                  onClick={() => { setSelectedId(ex.id); setReps(0); }}
                  className="duo-exercise-btn flex items-center gap-4 text-left w-full"
                  style={isSelected ? {
                    backgroundColor: c.bg,
                    borderColor: c.border,
                    boxShadow: `0 4px 0 ${c.shadow}`,
                  } : {}}
                >
                  <span className="text-4xl">{c.emoji}</span>
                  <div>
                    <p className="font-black text-duo-dark text-lg leading-tight">{ex.name}</p>
                    <p className="text-duo-gray font-bold text-sm">{ex.basePoints} XP / rep</p>
                  </div>
                  {isSelected && <span className="ml-auto text-2xl" style={{ color: c.border }}>✓</span>}
                </button>
              );
            })}
          </div>
        </div>

        {/* Rep counter */}
        {selectedId && (
          <div
            className="duo-card p-6 text-center animate-bounce_in"
            style={{ borderColor: cfg.border, boxShadow: `0 4px 0 ${cfg.shadow}` }}
          >
            <p className="text-duo-gray font-extrabold text-xs uppercase tracking-wider mb-1">レップ数</p>

            <input
              type="number"
              value={reps}
              onChange={(e) => {
                const val = parseInt(e.target.value, 10);
                if (!isNaN(val) && val >= 0) setReps(val);
              }}
              className="text-8xl font-black mb-5 leading-none text-center w-full bg-transparent border-none outline-none"
              style={{ color: cfg.border }}
              min="0"
              step="1"
            />

            <div className="flex gap-6 justify-center mb-5">
              {/* Minus */}
              <button
                onClick={removeRep}
                disabled={reps === 0}
                className="duo-rep-btn w-16 h-16 text-3xl"
                style={{
                  background: '#FFEAEA',
                  border: '2px solid #FF4B4B',
                  boxShadow: '0 4px 0 #cc0000',
                  color: '#FF4B4B',
                  opacity: reps === 0 ? 0.4 : 1,
                }}
              >
                −
              </button>
              {/* Plus */}
              <button
                onClick={addRep}
                className="duo-rep-btn w-16 h-16 text-3xl"
                style={{
                  background: cfg.bg,
                  border: `2px solid ${cfg.border}`,
                  boxShadow: `0 4px 0 ${cfg.shadow}`,
                  color: cfg.shadow,
                }}
              >
                ＋
              </button>
            </div>

            {reps > 0 && (
              <div
                className="rounded-xl px-4 py-2 inline-block font-extrabold text-lg"
                style={{ backgroundColor: cfg.bg, color: cfg.shadow }}
              >
                {reps} rep × {selected?.basePoints} XP = <span className="font-black">+{preview} XP</span>
              </div>
            )}
          </div>
        )}

        {/* Submit */}
        <button
          onClick={handleSubmit}
          disabled={!selectedId || reps === 0 || isSubmitting}
          className="duo-btn-primary w-full text-xl"
        >
          {isSubmitting ? '記録中...' : '✓ トレーニングを記録！'}
        </button>

        {/* Keyboard hints */}
        {selectedId && reps > 0 && (
          <div className="text-center">
            <p className="text-duo-gray text-xs font-bold">
              💡 キーボード: <span className="font-black">↑/+ 増やす</span> · <span className="font-black">↓/- 減らす</span> · <span className="font-black">Enter 記録</span>
            </p>
          </div>
        )}

      </div>
    </div>
  );
};
