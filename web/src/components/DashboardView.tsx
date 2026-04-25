import React, { useEffect, useState } from 'react';
import { getTodayExercises, getUserProfile } from '../services/firebase';
import { useAppStore } from '../store/appStore';
import { Flame, Zap, Trophy } from 'lucide-react';

interface DashboardViewProps {
  onLogWorkout?: () => void;
}

interface CompletedExercise {
  id: string;
  exerciseName: string;
  reps: number;
  points: number;
  timestamp?: Date;
}

export const DashboardView: React.FC<DashboardViewProps> = ({ onLogWorkout }) => {
  const user = useAppStore((state) => state.user);
  const userProfile = useAppStore((state) => state.userProfile);
  const setUserProfile = useAppStore((state) => state.setUserProfile);

  const [todayExercises, setTodayExercises] = useState<CompletedExercise[]>([]);
  const [totalReps, setTotalReps] = useState(0);
  const [totalPoints, setTotalPoints] = useState(0);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const loadData = async () => {
      if (!user) return;

      try {
        const [profile, exercises] = await Promise.all([
          getUserProfile(user.uid),
          getTodayExercises(user.uid),
        ]);

        if (profile) {
          setUserProfile(profile);
        }

        setTodayExercises(exercises);
        setTotalReps(exercises.reduce((sum: number, ex: any) => sum + (ex.reps || 0), 0));
        setTotalPoints(exercises.reduce((sum: number, ex: any) => sum + (ex.points || 0), 0));
      } catch (error) {
        console.error('Error loading dashboard:', error);
      } finally {
        setIsLoading(false);
      }
    };

    loadData();
  }, [user, setUserProfile]);

  if (isLoading) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-blue-50 to-purple-50 flex items-center justify-center">
        <div className="text-2xl text-gray-600">Loading...</div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 to-purple-50 p-6">
      <div className="max-w-4xl mx-auto">
        {/* Header */}
        <div className="bg-white rounded-lg shadow-lg p-8 mb-6">
          <div className="flex justify-between items-center mb-6">
            <h1 className="text-4xl font-bold text-gray-900">Welcome, {userProfile?.username}!</h1>
            <div className="text-right">
              <p className="text-gray-600">Total Points</p>
              <p className="text-4xl font-bold text-blue-600">{userProfile?.totalPoints || 0}</p>
            </div>
          </div>

          {/* Stats Grid */}
          <div className="grid grid-cols-3 gap-4">
            {/* Streak */}
            <div className="bg-gradient-to-br from-orange-100 to-red-100 rounded-lg p-4">
              <div className="flex items-center gap-2 mb-2">
                <Flame className="text-red-500" size={24} />
                <span className="text-gray-700 font-semibold">Streak</span>
              </div>
              <p className="text-3xl font-bold text-red-600">{userProfile?.streak || 0}</p>
            </div>

            {/* Today's Reps */}
            <div className="bg-gradient-to-br from-green-100 to-emerald-100 rounded-lg p-4">
              <div className="flex items-center gap-2 mb-2">
                <Zap className="text-green-500" size={24} />
                <span className="text-gray-700 font-semibold">Today's Reps</span>
              </div>
              <p className="text-3xl font-bold text-green-600">{totalReps}</p>
            </div>

            {/* Today's Points */}
            <div className="bg-gradient-to-br from-blue-100 to-cyan-100 rounded-lg p-4">
              <div className="flex items-center gap-2 mb-2">
                <Trophy className="text-blue-500" size={24} />
                <span className="text-gray-700 font-semibold">Today's Points</span>
              </div>
              <p className="text-3xl font-bold text-blue-600">{totalPoints}</p>
            </div>
          </div>
        </div>

        {/* Today's Workouts */}
        <div className="bg-white rounded-lg shadow-lg p-8 mb-6">
          <h2 className="text-2xl font-bold mb-6 text-gray-900">Today's Workouts</h2>

          {todayExercises.length === 0 ? (
            <div className="text-center py-12">
              <p className="text-gray-600 text-lg mb-4">No workouts logged yet today</p>
              <button
                onClick={onLogWorkout}
                className="bg-blue-600 hover:bg-blue-700 text-white font-bold py-3 px-8 rounded-lg transition"
              >
                Log Your First Workout
              </button>
            </div>
          ) : (
            <div className="space-y-4">
              {todayExercises.map((exercise) => (
                <div
                  key={exercise.id}
                  className="flex justify-between items-center bg-gray-50 rounded-lg p-4 border border-gray-200"
                >
                  <div>
                    <p className="font-semibold text-gray-900">{exercise.exerciseName}</p>
                    <p className="text-gray-600">{exercise.reps} reps</p>
                  </div>
                  <div className="text-right">
                    <p className="text-2xl font-bold text-blue-600">{exercise.points}</p>
                    <p className="text-gray-600 text-sm">points</p>
                  </div>
                </div>
              ))}

              <button
                onClick={onLogWorkout}
                className="w-full bg-gradient-to-r from-blue-600 to-purple-600 hover:from-blue-700 hover:to-purple-700 text-white font-bold py-3 rounded-lg transition mt-4"
              >
                + Log Another Workout
              </button>
            </div>
          )}
        </div>

        {/* Daily Goal */}
        <div className="bg-white rounded-lg shadow-lg p-8">
          <h2 className="text-2xl font-bold mb-6 text-gray-900">3-Month Goal</h2>
          <div className="bg-blue-50 rounded-lg p-6 border-l-4 border-blue-600">
            <p className="text-gray-700 mb-2">Build a fitness habit and complete your 3-month challenge</p>
            <div className="mt-4">
              <p className="text-sm text-gray-600 mb-2">Days Exercised: {userProfile?.streak || 0} / 90</p>
              <div className="w-full bg-gray-200 rounded-full h-4">
                <div
                  className="bg-blue-600 h-4 rounded-full transition-all"
                  style={{ width: `${Math.min(((userProfile?.streak || 0) / 90) * 100, 100)}%` }}
                />
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
