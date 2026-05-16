import React, { useEffect, useRef, useState, useCallback } from 'react';
import { recordExercise, recordCompletedSet } from '../services/firebase';
import { useAppStore } from '../store/appStore';

const FLOW_STEPS = [
  { exerciseId: 'squat',  exerciseName: 'スクワット',   emoji: '🏋️', targetReps: 20, basePoints: 2 },
  { exerciseId: 'pushup', exerciseName: '腕立て伏せ',   emoji: '💪', targetReps: 15, basePoints: 2 },
  { exerciseId: 'situp',  exerciseName: '腹筋',         emoji: '🔥', targetReps: 15, basePoints: 1 },
  { exerciseId: 'plank',  exerciseName: 'プランク',     emoji: '🧘', targetReps: 45, basePoints: 1 },
  { exerciseId: 'lunge',  exerciseName: 'ランジ',       emoji: '🦵', targetReps: 20, basePoints: 2 },
];

interface Result {
  exerciseId: string;
  exerciseName: string;
  emoji: string;
  reps: number;
  points: number;
}

interface Props {
  onFinish: () => void;
}

export const DailyWorkoutFlow: React.FC<Props> = ({ onFinish }) => {
  const user = useAppStore((s) => s.user);

  const steps = FLOW_STEPS;
  const [stepIdx, setStepIdx] = useState(0);
  const [reps, setReps] = useState(steps[0].targetReps);
  const [adjusting, setAdjusting] = useState(false);
  const [phase, setPhase] = useState<'exercise' | 'feedback' | 'done'>('exercise');
  const [results, setResults] = useState<Result[]>([]);
  const [earnedXP, setEarnedXP] = useState(0);
  const [isSaving, setIsSaving] = useState(false);
  const [showGoalReached, setShowGoalReached] = useState(false);

  // プランク専用
  const [plankSeconds, setPlankSeconds] = useState(0);
  const [plankRunning, setPlankRunning] = useState(false);
  const plankIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const setRecordedRef = useRef(false);
  const current = steps[stepIdx];
  const isPlank = current.exerciseId === 'plank';
  const isLast = stepIdx === steps.length - 1;
  const totalXP = results.reduce((s, r) => s + r.points, 0);

  // 目標達成チェック（プランク）
  useEffect(() => {
    if (isPlank && plankSeconds >= current.targetReps && !showGoalReached) {
      setShowGoalReached(true);
      setTimeout(() => setShowGoalReached(false), 2500);
    }
  }, [plankSeconds, isPlank, current.targetReps, showGoalReached]);

  // 種目切り替え時にリセット
  useEffect(() => {
    setReps(steps[stepIdx].targetReps);
    setAdjusting(false);
    setPlankSeconds(0);
    setPlankRunning(false);
    if (plankIntervalRef.current) {
      clearInterval(plankIntervalRef.current);
      plankIntervalRef.current = null;
    }
  }, [stepIdx]);

  const startPlank = useCallback(() => {
    setPlankRunning(true);
    plankIntervalRef.current = setInterval(() => {
      setPlankSeconds((s) => s + 1);
    }, 1000);
  }, []);

  const stopPlank = useCallback(() => {
    setPlankRunning(false);
    if (plankIntervalRef.current) {
      clearInterval(plankIntervalRef.current);
      plankIntervalRef.current = null;
    }
  }, []);

  useEffect(() => {
    return () => {
      if (plankIntervalRef.current) clearInterval(plankIntervalRef.current);
    };
  }, []);

  // セット完了記録
  useEffect(() => {
    if (phase === 'done' && results.length > 0 && user && !setRecordedRef.current) {
      setRecordedRef.current = true;
      recordCompletedSet(user.uid, results.map((r) => ({
        exerciseId: r.exerciseId,
        exerciseName: r.exerciseName,
        reps: r.reps,
        points: r.points,
      }))).catch(console.error);
    }
  }, [phase, results, user]);

  const handleDone = async () => {
    if (!user || !current || isSaving) return;
    setIsSaving(true);
    stopPlank();
    const actualReps = isPlank ? plankSeconds : reps;
    const pts = actualReps * current.basePoints;
    try {
      await recordExercise(user.uid, {
        exerciseId: current.exerciseId,
        exerciseName: current.exerciseName,
        reps: actualReps,
        points: pts,
        formScore: 85,
      });
    } catch (e) {
      console.error(e);
    }
    setEarnedXP(pts);
    setResults((prev) => [...prev, {
      exerciseId: current.exerciseId,
      exerciseName: current.exerciseName,
      emoji: current.emoji,
      reps: actualReps,
      points: pts,
    }]);
    setIsSaving(false);
    setPhase('feedback');
    setTimeout(() => {
      if (!isLast) {
        setStepIdx((s) => s + 1);
        setPhase('exercise');
      } else {
        setPhase('done');
      }
    }, 1400);
  };

  // ── Done ───────────────────────────────────────────────────────────────────
  if (phase === 'done') {
    return (
      <div className="min-h-screen bg-duo-gray-light flex flex-col items-center justify-center px-4 pb-10">
        <div className="max-w-md w-full text-center space-y-5">
          <img src="/mascot.png" alt="" className="w-32 h-32 rounded-full object-cover mx-auto animate-wiggle"
            style={{ border: '4px solid #58CC02' }} />
          <h2 className="text-4xl font-black text-duo-dark">完了！🎉</h2>
          <p className="text-duo-green font-extrabold text-lg">今日のメニュー全部やったね！</p>

          <div className="py-4 rounded-2xl"
            style={{ background: '#FFF8E1', border: '3px solid #FFD900', boxShadow: '0 4px 0 #CE9700' }}>
            <p className="text-duo-gray font-bold text-xs uppercase tracking-wider mb-1">合計獲得XP</p>
            <p className="text-5xl font-black" style={{ color: '#CE9700' }}>+{totalXP}</p>
          </div>

          <div className="space-y-2">
            {results.map((r, i) => (
              <div key={i} className="flex items-center justify-between rounded-2xl px-4 py-3"
                style={{ background: 'white', border: '2px solid #e5e5e5' }}>
                <div className="flex items-center gap-3">
                  <span className="text-2xl">{r.emoji}</span>
                  <div className="text-left">
                    <p className="font-extrabold text-duo-dark text-sm">{r.exerciseName}</p>
                    <p className="text-duo-gray font-bold text-xs">
                      {r.exerciseId === 'plank' ? `${r.reps} 秒` : `${r.reps} 回`}
                    </p>
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

  // ── Feedback ───────────────────────────────────────────────────────────────
  if (phase === 'feedback') {
    return (
      <div className="min-h-screen bg-duo-gray-light flex flex-col items-center justify-center gap-6">
        <div className="w-28 h-28 rounded-full flex items-center justify-center text-6xl animate-bounce_in"
          style={{ background: '#D7FFB8', border: '4px solid #58CC02' }}>
          ✅
        </div>
        <div className="px-8 py-4 rounded-2xl font-black text-4xl animate-bounce_in"
          style={{ background: '#FFF8E1', border: '3px solid #FFD900', color: '#CE9700', boxShadow: '0 4px 0 #CE9700' }}>
          +{earnedXP} XP
        </div>
        <p className="font-extrabold text-duo-green text-xl">ナイス！💪</p>
      </div>
    );
  }

  // ── Exercise ───────────────────────────────────────────────────────────────
  return (
    <div className="min-h-screen bg-duo-gray-light flex flex-col">

      {/* ヘッダー進捗 */}
      <div className="bg-white px-4 pt-4 pb-3" style={{ borderBottom: '2px solid #e5e5e5' }}>
        <div className="max-w-md mx-auto">
          <div className="flex items-center gap-3">
            <button onClick={onFinish}
              className="text-duo-gray font-black text-lg hover:text-duo-dark transition-colors">
              ✕
            </button>
            {/* 進捗ドット (iOSスタイル) */}
            <div className="flex-1 flex items-center justify-center gap-2">
              {steps.map((_, i) => (
                <div key={i}
                  className="rounded-full transition-all duration-300"
                  style={{
                    width: i === stepIdx ? 28 : 10,
                    height: 10,
                    background: i < stepIdx ? '#58CC02' : i === stepIdx ? '#58CC02' : '#e5e5e5',
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

      {/* メインコンテンツ */}
      <div className="flex-1 overflow-y-auto">
        <div className="max-w-md mx-auto px-4 py-4 space-y-4">

          {/* 完了済み種目リスト */}
          {results.length > 0 && (
            <div className="duo-card p-3 space-y-1">
              <p className="text-duo-gray font-bold text-xs uppercase tracking-wider mb-2">完了済み</p>
              {results.map((r, i) => (
                <div key={i} className="flex items-center justify-between py-1.5 px-2 rounded-lg"
                  style={{ background: '#F0FDE8' }}>
                  <div className="flex items-center gap-2">
                    <span className="text-base">{r.emoji}</span>
                    <span className="font-bold text-duo-dark text-sm">{r.exerciseName}</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="font-black text-duo-dark text-sm">
                      {r.exerciseId === 'plank' ? `${r.reps}秒` : `${r.reps}回`}
                    </span>
                    <span className="font-extrabold text-xs" style={{ color: '#CE9700' }}>+{r.points}XP</span>
                  </div>
                </div>
              ))}
            </div>
          )}

          {/* 種目カード */}
          <div className="duo-card p-6 text-center">
            <div className="w-24 h-24 rounded-3xl flex items-center justify-center text-6xl mx-auto mb-4"
              style={{ background: '#D7FFB8', border: '3px solid #58CC02', boxShadow: '0 6px 0 #46A302' }}>
              {current.emoji}
            </div>
            <h2 className="text-3xl font-black text-duo-dark">{current.exerciseName}</h2>
            <p className="text-duo-gray font-bold text-sm mt-1">
              目標: {current.targetReps}{isPlank ? ' 秒' : ' 回'}
            </p>
          </div>

          {/* カウンター / タイマー */}
          {isPlank ? (
            /* プランクタイマー */
            <div className="duo-card p-6 text-center"
              style={{ borderColor: plankRunning ? '#58CC02' : '#e5e5e5', boxShadow: plankRunning ? '0 4px 0 #46A302' : undefined }}>
              <p className="text-duo-gray font-extrabold text-xs uppercase tracking-wider mb-2">タイマー</p>
              <div className="relative mb-4">
                <svg className="mx-auto" width="140" height="140" viewBox="0 0 140 140">
                  <circle cx="70" cy="70" r="60" fill="none" stroke="#e5e5e5" strokeWidth="10" />
                  <circle
                    cx="70" cy="70" r="60" fill="none"
                    stroke={plankSeconds >= current.targetReps ? '#58CC02' : plankRunning ? '#1CB0F6' : '#e5e5e5'}
                    strokeWidth="10"
                    strokeLinecap="round"
                    strokeDasharray={`${2 * Math.PI * 60}`}
                    strokeDashoffset={`${2 * Math.PI * 60 * (1 - Math.min(plankSeconds / current.targetReps, 1))}`}
                    transform="rotate(-90 70 70)"
                    style={{ transition: 'stroke-dashoffset 1s linear, stroke 0.3s' }}
                  />
                  <text x="70" y="65" textAnchor="middle" fontSize="36" fontWeight="900"
                    fill={plankSeconds > 0 ? '#2d7a00' : '#AFAFAF'} fontFamily="system-ui">
                    {plankSeconds}
                  </text>
                  <text x="70" y="88" textAnchor="middle" fontSize="14" fontWeight="700"
                    fill="#AFAFAF" fontFamily="system-ui">
                    秒
                  </text>
                </svg>
              </div>
              <button
                onClick={plankRunning ? stopPlank : startPlank}
                className="w-full py-4 rounded-2xl font-black text-xl text-white transition-all"
                style={{
                  background: plankRunning ? '#FF9600' : '#58CC02',
                  boxShadow: plankRunning ? '0 4px 0 #CC7000' : '0 4px 0 #46A302',
                }}
              >
                {plankRunning ? '⏸ 停止' : (plankSeconds > 0 ? '▶ 再開' : '▶ 開始')}
              </button>
              {plankSeconds > 0 && !plankRunning && (
                <button
                  onClick={() => setPlankSeconds(0)}
                  className="mt-2 text-xs font-bold text-duo-gray underline"
                >
                  リセット
                </button>
              )}
            </div>
          ) : (
            /* 通常種目のレップ数 */
            <div className="duo-card p-6 text-center"
              style={{ borderColor: '#58CC02' }}>
              <p className="text-duo-gray font-extrabold text-xs uppercase tracking-wider mb-2">回数</p>
              {!adjusting ? (
                <>
                  <p className="text-8xl font-black leading-none mb-2" style={{ color: '#2d7a00' }}>{reps}</p>
                  <p className="text-duo-green font-extrabold text-sm mb-3">回</p>
                  <button onClick={() => setAdjusting(true)}
                    className="text-xs font-bold underline" style={{ color: '#46A302' }}>
                    回数を変更
                  </button>
                </>
              ) : (
                <>
                  <p className="text-duo-green font-extrabold text-xs uppercase tracking-widest mb-3">回数を調整</p>
                  <div className="flex items-center justify-center gap-6">
                    <button onClick={() => setReps((r) => Math.max(1, r - 1))}
                      className="w-14 h-14 rounded-2xl font-black text-3xl flex items-center justify-center"
                      style={{ background: 'white', border: '2px solid #58CC02', color: '#46A302', boxShadow: '0 3px 0 #46A302' }}>
                      −
                    </button>
                    <span className="text-6xl font-black" style={{ color: '#2d7a00', minWidth: '2.5ch', textAlign: 'center' }}>{reps}</span>
                    <button onClick={() => setReps((r) => r + 1)}
                      className="w-14 h-14 rounded-2xl font-black text-3xl flex items-center justify-center"
                      style={{ background: '#58CC02', color: 'white', boxShadow: '0 3px 0 #46A302' }}>
                      ＋
                    </button>
                  </div>
                  <button onClick={() => setAdjusting(false)}
                    className="mt-3 text-xs font-bold underline" style={{ color: '#46A302' }}>
                    確定
                  </button>
                </>
              )}
              <p className="font-extrabold text-sm mt-3" style={{ color: '#CE9700' }}>
                +{reps * current.basePoints} XP 獲得
              </p>
            </div>
          )}

          {/* 完了ボタン */}
          <button
            onClick={handleDone}
            disabled={isSaving || (isPlank && plankSeconds === 0)}
            className="duo-btn-primary w-full text-2xl py-5"
            style={{ borderRadius: '1.25rem', opacity: (isSaving || (isPlank && plankSeconds === 0)) ? 0.5 : 1 }}
          >
            {isSaving ? '記録中…' : isLast ? '✓ 完了！' : '次へ →'}
          </button>

          {/* スキップ */}
          <button
            onClick={() => {
              stopPlank();
              if (!isLast) { setStepIdx((s) => s + 1); }
              else { setPhase('done'); }
            }}
            className="w-full text-center text-duo-gray font-bold text-sm hover:text-duo-dark transition-colors pb-4"
          >
            スキップ →
          </button>
        </div>
      </div>

      {/* 目標達成オーバーレイ */}
      {showGoalReached && (
        <div
          className="fixed inset-0 flex items-center justify-center z-50"
          style={{ background: 'rgba(0,0,0,0.6)' }}
        >
          <div className="text-center px-10 py-8 rounded-3xl animate-bounce_in"
            style={{ background: 'rgba(0,0,0,0.85)', border: '2px solid #58CC02' }}>
            <p className="text-6xl mb-3">🎉</p>
            <p className="text-3xl font-black" style={{ color: '#58CC02' }}>Good Job!</p>
            <p className="text-white font-bold mt-2">目標達成！</p>
          </div>
        </div>
      )}
    </div>
  );
};
