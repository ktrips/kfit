import React, { useState, useRef, useCallback, useEffect } from 'react';
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
  isTimer?: boolean;
}

const EXERCISE_CFG: Record<string, ExerciseCfg> = {
  default:   { emoji: '⚡', bg: '#F7F7F7', border: '#e5e5e5', shadow: '#c5c5c5', numColor: '#3C3C3C' },
  'push-up': { emoji: '💪', bg: '#D7FFB8', border: '#58CC02', shadow: '#46A302', numColor: '#2d7a00' },
  'pushup':  { emoji: '💪', bg: '#D7FFB8', border: '#58CC02', shadow: '#46A302', numColor: '#2d7a00' },
  'squat':   { emoji: '🏋️', bg: '#E3F2FD', border: '#1CB0F6', shadow: '#0E8FC5', numColor: '#0a6c96' },
  'sit-up':  { emoji: '🔥', bg: '#FFF3E0', border: '#FF9600', shadow: '#CC7000', numColor: '#8a4700' },
  'situp':   { emoji: '🔥', bg: '#FFF3E0', border: '#FF9600', shadow: '#CC7000', numColor: '#8a4700' },
  'lunge':   { emoji: '🦵', bg: '#F3E5F5', border: '#9C27B0', shadow: '#6A1B9A', numColor: '#4A148C' },
  'plank':   { emoji: '🧘', bg: '#E8EAF6', border: '#5C6BC0', shadow: '#3949AB', numColor: '#283593', isTimer: true },
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

  // プランクタイマー
  const [plankSeconds, setPlankSeconds] = useState(0);
  const [plankRunning, setPlankRunning] = useState(false);
  const plankIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const selected = exercises.find((e) => e.id === selectedId);
  const cfg = selected ? getCfg(selected.name) : EXERCISE_CFG.default;
  const isPlank = selectedId === 'plank' || (selected?.name ?? '').toLowerCase().includes('plank');
  const preview = isPlank ? plankSeconds * (selected?.basePoints || 1) : reps * (selected?.basePoints || 0);

  const startPlank = useCallback(() => {
    setPlankRunning(true);
    plankIntervalRef.current = setInterval(() => setPlankSeconds((s) => s + 1), 1000);
  }, []);

  const stopPlank = useCallback(() => {
    setPlankRunning(false);
    if (plankIntervalRef.current) { clearInterval(plankIntervalRef.current); plankIntervalRef.current = null; }
  }, []);

  useEffect(() => {
    return () => { if (plankIntervalRef.current) clearInterval(plankIntervalRef.current); };
  }, []);

  // 種目切り替え時にタイマーリセット
  useEffect(() => {
    stopPlank();
    setPlankSeconds(0);
    setReps(0);
  }, [selectedId]);

  const addRep = () => setReps((r) => r + 1);
  const removeRep = () => { if (reps > 0) setReps((r) => r - 1); };

  // Keyboard shortcuts (プランク以外)
  useEffect(() => {
    if (isPlank) return;
    const handleKeyPress = (e: KeyboardEvent) => {
      if (!selectedId) return;
      if (e.key === '+' || e.key === 'ArrowUp') { e.preventDefault(); addRep(); }
      else if (e.key === '-' || e.key === 'ArrowDown') { e.preventDefault(); removeRep(); }
      else if (e.key === 'Enter' && reps > 0) { e.preventDefault(); handleSubmit(); }
    };
    window.addEventListener('keydown', handleKeyPress);
    return () => window.removeEventListener('keydown', handleKeyPress);
  }, [selectedId, reps, isPlank]);

  const handleSubmit = async () => {
    const actualReps = isPlank ? plankSeconds : reps;
    if (!user || !selectedId || actualReps === 0) {
      setError('エクササイズを選んで記録してください');
      return;
    }
    setIsSubmitting(true);
    stopPlank();
    try {
      const pts = actualReps * (selected?.basePoints || 10);
      await recordExercise(user.uid, {
        exerciseId: selectedId,
        exerciseName: selected?.name,
        reps: actualReps,
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
        setPlankSeconds(0);
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
            <p className="text-duo-gray font-bold text-sm">種目を選んで記録しよう！</p>
          </div>
        </div>

        {/* Exercise selection */}
        <div className="duo-card p-5">
          <p className="text-duo-dark font-extrabold mb-3 text-xs uppercase tracking-wider">エクササイズ選択</p>
          <div className="flex flex-col gap-3">
            {exercises.map((ex) => {
              const c = getCfg(ex.name);
              const isSelected = selectedId === ex.id;
              const isExPlank = ex.id === 'plank' || ex.name.toLowerCase().includes('plank');
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
                    <p className="text-duo-gray font-bold text-sm">
                      {isExPlank ? 'タイマー計測' : `${ex.basePoints} XP / rep`}
                    </p>
                  </div>
                  {isSelected && <span className="ml-auto text-2xl" style={{ color: c.border }}>✓</span>}
                </button>
              );
            })}
          </div>
        </div>

        {/* Rep counter / Plank timer */}
        {selectedId && (
          <div
            className="duo-card p-6 text-center animate-bounce_in"
            style={{ borderColor: cfg.border, boxShadow: `0 4px 0 ${cfg.shadow}` }}
          >
            {isPlank ? (
              /* プランクタイマー */
              <>
                <p className="text-duo-gray font-extrabold text-xs uppercase tracking-wider mb-3">プランクタイマー</p>
                <svg className="mx-auto mb-4" width="140" height="140" viewBox="0 0 140 140">
                  <circle cx="70" cy="70" r="60" fill="none" stroke="#e5e5e5" strokeWidth="10" />
                  <circle
                    cx="70" cy="70" r="60" fill="none"
                    stroke={plankRunning ? cfg.border : '#e5e5e5'}
                    strokeWidth="10"
                    strokeLinecap="round"
                    strokeDasharray={`${2 * Math.PI * 60}`}
                    strokeDashoffset={`${2 * Math.PI * 60 * Math.max(0, 1 - plankSeconds / 45)}`}
                    transform="rotate(-90 70 70)"
                    style={{ transition: 'stroke-dashoffset 1s linear' }}
                  />
                  <text x="70" y="65" textAnchor="middle" fontSize="36" fontWeight="900"
                    fill={plankSeconds > 0 ? cfg.numColor : '#AFAFAF'} fontFamily="system-ui">
                    {plankSeconds}
                  </text>
                  <text x="70" y="88" textAnchor="middle" fontSize="14" fontWeight="700"
                    fill="#AFAFAF" fontFamily="system-ui">秒</text>
                </svg>
                <button
                  onClick={plankRunning ? stopPlank : startPlank}
                  className="w-full py-3 rounded-2xl font-black text-lg text-white mb-2"
                  style={{
                    background: plankRunning ? '#FF9600' : cfg.border,
                    boxShadow: plankRunning ? '0 4px 0 #CC7000' : `0 4px 0 ${cfg.shadow}`,
                  }}
                >
                  {plankRunning ? '⏸ 停止' : (plankSeconds > 0 ? '▶ 再開' : '▶ 開始')}
                </button>
                {plankSeconds > 0 && !plankRunning && (
                  <button onClick={() => setPlankSeconds(0)} className="text-xs font-bold text-duo-gray underline">
                    リセット
                  </button>
                )}
                {plankSeconds > 0 && (
                  <div className="mt-3 rounded-xl px-4 py-2 inline-block font-extrabold text-lg"
                    style={{ backgroundColor: cfg.bg, color: cfg.shadow }}>
                    {plankSeconds}秒 × {selected?.basePoints} XP = <span className="font-black">+{preview} XP</span>
                  </div>
                )}
              </>
            ) : (
              /* 通常レップカウンター */
              <>
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
                  <button
                    onClick={removeRep}
                    disabled={reps === 0}
                    className="duo-rep-btn w-16 h-16 text-3xl"
                    style={{
                      background: '#FFEAEA', border: '2px solid #FF4B4B',
                      boxShadow: '0 4px 0 #cc0000', color: '#FF4B4B',
                      opacity: reps === 0 ? 0.4 : 1,
                    }}
                  >−</button>
                  <button
                    onClick={addRep}
                    className="duo-rep-btn w-16 h-16 text-3xl"
                    style={{
                      background: cfg.bg, border: `2px solid ${cfg.border}`,
                      boxShadow: `0 4px 0 ${cfg.shadow}`, color: cfg.shadow,
                    }}
                  >＋</button>
                </div>
                {reps > 0 && (
                  <div className="rounded-xl px-4 py-2 inline-block font-extrabold text-lg"
                    style={{ backgroundColor: cfg.bg, color: cfg.shadow }}>
                    {reps} rep × {selected?.basePoints} XP = <span className="font-black">+{preview} XP</span>
                  </div>
                )}
              </>
            )}
          </div>
        )}

        {/* Submit */}
        <button
          onClick={handleSubmit}
          disabled={!selectedId || (isPlank ? plankSeconds === 0 : reps === 0) || isSubmitting}
          className="duo-btn-primary w-full text-xl"
        >
          {isSubmitting ? '記録中...' : '✓ トレーニングを記録！'}
        </button>

        {/* Keyboard hints (プランク以外) */}
        {selectedId && reps > 0 && !isPlank && (
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
