import React, { useState } from 'react';
import { recordExercise } from '../services/firebase';
import { useAppStore } from '../store/appStore';
import { Plus, Minus } from 'lucide-react';

interface ExerciseTrackerProps {
  onSuccess?: () => void;
}

export const ExerciseTrackerView: React.FC<ExerciseTrackerProps> = ({ onSuccess }) => {
  const user = useAppStore((state) => state.user);
  const exercises = useAppStore((state) => state.exercises);
  const updateUserPoints = useAppStore((state) => state.updateUserPoints);
  const setError = useAppStore((state) => state.setError);

  const [selectedExerciseId, setSelectedExerciseId] = useState<string>('');
  const [reps, setReps] = useState<number>(0);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const selectedExercise = exercises.find((e) => e.id === selectedExerciseId);

  const handleAddRep = () => {
    setReps((r) => r + 1);
  };

  const handleRemoveRep = () => {
    if (reps > 0) setReps((r) => r - 1);
  };

  const handleSubmit = async () => {
    if (!user || !selectedExerciseId || reps === 0) {
      setError('Please select an exercise and enter reps');
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
      setReps(0);
      setSelectedExerciseId('');
      onSuccess?.();
    } catch (error) {
      setError(error instanceof Error ? error.message : 'Error recording exercise');
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="max-w-2xl mx-auto p-6">
      <div className="bg-white rounded-lg shadow-lg p-8">
        <h2 className="text-3xl font-bold mb-6 text-gray-900">Log Workout</h2>

        {/* Exercise Selection */}
        <div className="mb-8">
          <label className="block text-lg font-semibold mb-4 text-gray-700">
            Select Exercise
          </label>
          <div className="grid grid-cols-3 gap-3">
            {exercises.map((exercise) => (
              <button
                key={exercise.id}
                onClick={() => setSelectedExerciseId(exercise.id)}
                className={`p-4 rounded-lg font-semibold transition ${
                  selectedExerciseId === exercise.id
                    ? 'bg-blue-600 text-white'
                    : 'bg-gray-100 text-gray-900 hover:bg-gray-200'
                }`}
              >
                {exercise.name}
              </button>
            ))}
          </div>
        </div>

        {/* Rep Counter */}
        {selectedExerciseId && (
          <div className="mb-8 bg-gradient-to-r from-blue-50 to-purple-50 rounded-lg p-8">
            <div className="text-center">
              <p className="text-gray-600 mb-2">Reps</p>
              <div className="text-7xl font-bold text-blue-600 mb-6">{reps}</div>

              <div className="flex gap-4 justify-center mb-6">
                <button
                  onClick={handleRemoveRep}
                  className="bg-red-500 hover:bg-red-600 text-white rounded-full p-4 transition"
                >
                  <Minus size={32} />
                </button>

                <button
                  onClick={handleAddRep}
                  className="bg-green-500 hover:bg-green-600 text-white rounded-full p-4 transition"
                >
                  <Plus size={32} />
                </button>
              </div>

              {selectedExercise && (
                <p className="text-lg text-gray-700">
                  {reps} reps × {selectedExercise.basePoints} pts = <span className="font-bold text-blue-600">{reps * selectedExercise.basePoints} points</span>
                </p>
              )}
            </div>
          </div>
        )}

        {/* Submit Button */}
        <button
          onClick={handleSubmit}
          disabled={!selectedExerciseId || reps === 0 || isSubmitting}
          className="w-full bg-blue-600 hover:bg-blue-700 disabled:bg-gray-400 text-white font-bold py-4 px-6 rounded-lg transition text-lg"
        >
          {isSubmitting ? 'Recording...' : '✓ Log Workout'}
        </button>
      </div>
    </div>
  );
};
