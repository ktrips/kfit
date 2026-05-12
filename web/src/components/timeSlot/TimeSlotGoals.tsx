import React, { useEffect, useState } from 'react';
import { useAuth } from '../../hooks/useAuth';
import {
  TimeSlot,
  TimeSlotGoal,
  TimeSlotProgress,
  DailyTimeSlotSettings,
  DailyTimeSlotProgress,
  TIME_SLOT_INFO,
  calculateCompletionRate,
  isFullyCompleted
} from '../../types/timeSlot';
import {
  getTodaySettings,
  getTodayProgress
} from '../../services/timeSlotService';
import TimeSlotCard from './TimeSlotCard';
import TimeSlotEditModal from './TimeSlotEditModal';

const TimeSlotGoals: React.FC = () => {
  const { user } = useAuth();
  const [settings, setSettings] = useState<DailyTimeSlotSettings | null>(null);
  const [progress, setProgress] = useState<DailyTimeSlotProgress | null>(null);
  const [loading, setLoading] = useState(true);
  const [editingSlot, setEditingSlot] = useState<TimeSlot | null>(null);

  useEffect(() => {
    loadData();
  }, [user]);

  const loadData = async () => {
    if (!user) return;

    setLoading(true);
    try {
      const [settingsData, progressData] = await Promise.all([
        getTodaySettings(user.uid),
        getTodayProgress(user.uid)
      ]);
      setSettings(settingsData);
      setProgress(progressData);
    } catch (error) {
      console.error('Failed to load time slot data:', error);
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-green-500"></div>
      </div>
    );
  }

  if (!settings || !progress) {
    return <div>データの読み込みに失敗しました</div>;
  }

  return (
    <div className="max-w-4xl mx-auto p-4 space-y-6">
      {/* Header */}
      <div className="bg-white rounded-lg shadow-md p-6">
        <div className="flex items-center space-x-4">
          <div className="flex-shrink-0">
            <div className="w-14 h-14 bg-gradient-to-br from-green-400 to-green-600 rounded-full flex items-center justify-center">
              <span className="text-2xl">🕐</span>
            </div>
          </div>
          <div>
            <h1 className="text-2xl font-bold text-gray-800">
              時間帯別の目標設定
            </h1>
            <p className="text-sm text-gray-600">
              1日を4つの時間帯に分けて管理
            </p>
          </div>
        </div>
        <p className="mt-4 text-sm text-gray-600">
          朝・昼・午後・夜の時間帯ごとに、トレーニング、マインドフルネス、ログ記録の目標を設定できます。
        </p>
      </div>

      {/* Time Slot Cards */}
      <div className="space-y-4">
        {Object.values(TimeSlot).map(slot => {
          const goal = settings.goals.find(g => g.timeSlot === slot);
          const prog = progress.progress.find(p => p.timeSlot === slot);

          if (!goal || !prog) return null;

          return (
            <TimeSlotCard
              key={slot}
              timeSlot={slot}
              goal={goal}
              progress={prog}
              onEdit={() => setEditingSlot(slot)}
            />
          );
        })}
      </div>

      {/* Edit Modal */}
      {editingSlot && (
        <TimeSlotEditModal
          timeSlot={editingSlot}
          onClose={() => {
            setEditingSlot(null);
            loadData();
          }}
        />
      )}
    </div>
  );
};

export default TimeSlotGoals;
