import React, { useState } from 'react';
import { recordExercise } from '../services/firebase';
import { useAppStore } from '../store/appStore';

interface ExerciseTrackerProps {
  onSuccess?: () => void;
}

const EXERCISE_CONFIG: Record<string, { emoji: string; color: string; border: string; shadow: string; textColor: string }> = {
  default: { emoji: '⚡', color: '#F7F7F7', border: '#e5e5e5', shadow: '#c5c5c5', textColor: '#3C3C3C' },
  'push-up': { emoji: '💪', color: '#D7FFB8', border: '#58CC02', shadow: '#46A302', textColor: '#3C3C3C' },
  'pushup': { emoji: '💪', color: '#D7FFB8', border: '#58CC02', shadow: '#46A302', textColor: '#3C3C3C' },
  'squat': { emoji: '🏋️', color: '#E3F2FD', border: '#1CB0F6', shadow: '#0E8FC5', textColor: '#3C3C3C' },
  'sit-up': { emoji: '🔥', color: '#FFF3E0', border: '#FF9600', shadow: '#CC7000', textColor: '#3C3C3C' },
  'situp': { emoji: '🔥', color: '#FFF3E0', border: '#FF9600', shadow: '#CC7000', textColor: '#3C3C3C' },
};

function getExerciseConfig(name: string) {
  const key = name?.toLowerCase().replace(/\s+/g, '-') ?? '';
  for (const [k, v] of Object.entries(EXERCISE_CONFIG)) {
    if (k !== 'default' && key.includes(k)) return v;
  }
  return EXERCISE_CONFIG.default;
}

export const ExerciseTrackerView: React.FC<ExerciseTrackerProps> = ({ onSuccess }) => {
  const user = useAppStore((state) => state.user);
  const exercises = useAppStore((state) => state.exercises);
  const updateUserPoints = useAppStore((state) => state.updateUserPoints);
  const setError = useAppStore((state) => state.setError);

  const [selectedExerciseId, setSelectedExerciseId] = useState<string>('');
  const [reps, setReps] = useState<number>(0);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [showCelebration, setShowCelebration] = useState(false);

  const selectedExercise = exercises.find((e) => e.id === selectedExerciseId);
  const selectedConfig = selectedExercise ? getExerciseConfig(selectedExercise.name) : EXERCISE_CONFIG.default;
  const previewPoints = reps * (selectedExercise?.basePoints || 0);

  const handleAddRep = () => setReps((r) => r + 1);
  const handleRemoveRep = () => { if (reps > 0) setReps((r) => r - 1); };

  const handleSubmit = async () => {
    if (!user || !selectedExerciseId || reps === 0) {
      setError('エクササイズを選んでレップ数を入力してください');
      return;
    }
    setIsSubmitting(true);
    try {
      const basePoints = selectedExercise?.basePoints || 10;
      const points = reps * basePoints;
      await recordExercise(user.uid, {
        exerciseId: selectedExerciseId,
        exerciseName: selectedExercise?.name,
        reps,
        points,
        formScore: 85,
      });
      updateUserPoints(points);
      setShowCelebration(true);
      setTimeout(() => {
        setShowCelebration(false);
        setReps(0);
        setSelectedExerciseId('');
        onSuccess?.();
      }, 1500);
    } catch (error) {
      setError(error instanceof Error ? error.message : 'エラーが発生しました');
    } finally {
      setIsSubmitting(false);
    }
  };

  if (showCelebration) {
    return (
      <div className="min-h-screen bg-duo-gray-light flex items-center justify-center">
        <div className="text-center animate-bounce_in">
          <p className="text-8xl mb-4">🎉</p>
          <p className="text-4xl font-black text-duo-green mb-2">やったー！</p>
          <p className="text-2xl font-extrabold text-duo-yellow-dark">+{previewPoints} XP 獲得！</p>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-duo-gray-light pb-10">
      <div className="max-w-md mx-auto px-4 pt-6 space-y-4">

        {/* Header */}
        <div className="text-center">
          <h2 className="text-3xl font-black text-duo-dark">💪 トレーニング記録</h2>
          <p className="text-duo-gray font-bold mt-1">エクササイズを選んでレップ数を入力！</p>
        </div>

        {/* Exercise selection */}
        <div className="duo-card p-5">
          <p className="text-duo-dark font-extrabold mb-3 text-sm uppercase tracking-wider">エクササイズ選択</p>
          <div className="grid grid-cols-1 gap-3">
            {exercises.map((exercise) => {
              const cfg = getExerciseConfig(exercise.name);
              const isSelected = selectedExerciseId === exercise.id;
              return (
                <button
                  key={exercise.id}
                  onClick={() => { setSelectedExerciseId(exercise.id); setReps(0); }}
                  className="duo-exercise-btn flex items-center gap-4 text-left"
                  style={isSelected ? {
                    backgroundColor: cfg.color,
                    borderColor: cfg.border,
                    boxShadow: `0 4px 0 ${cfg.shadow}`,
                  } : {}}
                >
                  <span className="text-4xl">{cfg.emoji}</span>
                  <div>
                    <p className="font-black text-duo-dark text-lg">{exercise.name}</p>
                    <p className="text-duo-gray font-bold text-sm">{exercise.basePoints} XP / rep</p>
                  </div>
                  {isSelected && (
                    <span className="ml-auto text-duo-green text-2xl">✓</span>
                  )}
                </button>
              );
            })}
          </div>
        </div>

        {/* Rep counter */}
        {selectedExerciseId && (
          <div
            className="duo-card p-6 text-center animate-bounce_in"
            style={{ borderColor: selectedConfig.border, boxShadow: `0 4px 0 ${selectedConfig.shadow}` }}
          >
            <p className="text-duo-gray font-extrabold text-sm uppercase tracking-wider mb-2">レップ数</p>

            <div
              className="text-8xl font-black mb-6 transition-all"
              style={{ color: selectedConfig.border }}
            >
              {reps}
            </div>

            <div className="flex gap-5 justify-center mb-5">
              <button
                onClick={handleRemoveRep}
                className="duo-rep-btn w-16 h-16 text-2xl bg-red-100 text-duo-red"
                style={{ boxShadow: '0 4px 0 #cc0000', borderColor: '#FF4B4B', border: '2px solid #FF4B4B' }}
                disabled={reps === 0}
              >
                −
              </button>
              <button
                onClick={handleAddRep}
                className="duo-rep-btn w-16 h-16 text-2xl bg-duo-green-light text-duo-green-dark"
                style={{ boxShadow: `0 4px 0 ${selectedConfig.shadow}`, border: `2px solid ${selectedConfig.border}` }}
              >
                ＋
              </button>
            </div>

            {reps > 0 && (
              <div
                className="rounded-xl px-4 py-2 inline-block font-extrabold text-lg"
                style={{ backgroundColor: selectedConfig.color, color: selectedConfig.shadow }}
              >
                {reps} rep × {selectedExercise?.basePoints} XP = <span className="font-black">+{previewPoints} XP</span>
              </div>
            )}
          </div>
        )}

        {/* Submit */}
        <button
          onClick={handleSubmit}
          disabled={!selectedExerciseId || reps === 0 || isSubmitting}
          className="duo-btn-primary w-full text-xl"
        >
          {isSubmitting ? '記録中...' : '✓ トレーニングを記録！'}
        </button>

      </div>
    </div>
  );
};
