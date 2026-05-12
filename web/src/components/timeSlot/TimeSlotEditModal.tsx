import React, { useEffect, useState } from 'react';
import { useAuth } from '../../hooks/useAuth';
import {
  TimeSlot,
  TimeSlotGoal,
  TIME_SLOT_INFO
} from '../../types/timeSlot';
import {
  getTodaySettings,
  saveTodaySettings
} from '../../services/timeSlotService';

interface TimeSlotEditModalProps {
  timeSlot: TimeSlot;
  onClose: () => void;
}

const TimeSlotEditModal: React.FC<TimeSlotEditModalProps> = ({
  timeSlot,
  onClose
}) => {
  const { user } = useAuth();
  const info = TIME_SLOT_INFO[timeSlot];

  const [trainingGoal, setTrainingGoal] = useState(1);
  const [mindfulnessGoal, setMindfulnessGoal] = useState(1);
  const [mealRequired, setMealRequired] = useState(true);
  const [drinkRequired, setDrinkRequired] = useState(true);
  const [mindInputRequired, setMindInputRequired] = useState(false);
  const [reminderEnabled, setReminderEnabled] = useState(false);
  const [reminderTime, setReminderTime] = useState('09:00');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    loadGoal();
  }, [timeSlot]);

  const loadGoal = async () => {
    if (!user) return;

    try {
      const settings = await getTodaySettings(user.uid);
      const goal = settings.goals.find(g => g.timeSlot === timeSlot);

      if (goal) {
        setTrainingGoal(goal.trainingGoal);
        setMindfulnessGoal(goal.mindfulnessGoal);
        setMealRequired(goal.logGoal.mealRequired);
        setDrinkRequired(goal.logGoal.drinkRequired);
        setMindInputRequired(goal.logGoal.mindInputRequired);
        setReminderEnabled(goal.reminderEnabled);
        if (goal.reminderTime) {
          const hours = goal.reminderTime.getHours().toString().padStart(2, '0');
          const minutes = goal.reminderTime
            .getMinutes()
            .toString()
            .padStart(2, '0');
          setReminderTime(`${hours}:${minutes}`);
        }
      }
    } catch (error) {
      console.error('Failed to load goal:', error);
    }
  };

  const handleSave = async () => {
    if (!user) return;

    setSaving(true);
    try {
      const settings = await getTodaySettings(user.uid);
      const goalIndex = settings.goals.findIndex(g => g.timeSlot === timeSlot);

      if (goalIndex !== -1) {
        const updatedGoal: TimeSlotGoal = {
          timeSlot,
          trainingGoal,
          mindfulnessGoal,
          logGoal: {
            mealRequired,
            drinkRequired,
            mindInputRequired
          },
          reminderEnabled
        };

        if (reminderEnabled && reminderTime) {
          const [hours, minutes] = reminderTime.split(':').map(Number);
          const time = new Date();
          time.setHours(hours, minutes, 0, 0);
          updatedGoal.reminderTime = time;
        }

        settings.goals[goalIndex] = updatedGoal;
        await saveTodaySettings(user.uid, settings);
      }

      onClose();
    } catch (error) {
      console.error('Failed to save goal:', error);
      alert('目標の保存に失敗しました');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-lg max-w-md w-full max-h-[90vh] overflow-y-auto">
        {/* Header */}
        <div className="sticky top-0 bg-white border-b border-gray-200 p-6">
          <div className="flex items-center justify-between">
            <div className="flex items-center space-x-3">
              <span className="text-3xl">{info.emoji}</span>
              <div>
                <h2 className="text-xl font-bold text-gray-800">
                  {info.displayName}の目標設定
                </h2>
                <p className="text-sm text-gray-500">{info.timeRange}</p>
              </div>
            </div>
            <button
              onClick={onClose}
              className="text-gray-400 hover:text-gray-600"
            >
              <svg
                className="w-6 h-6"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M6 18L18 6M6 6l12 12"
                />
              </svg>
            </button>
          </div>
        </div>

        <div className="p-6 space-y-6">
          {/* Training Goal */}
          <div className="space-y-2">
            <label className="flex items-center space-x-2 text-sm font-semibold text-gray-700">
              <span>💪</span>
              <span>トレーニング</span>
            </label>
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600">目標セット数</span>
              <div className="flex items-center space-x-3">
                <button
                  onClick={() => setTrainingGoal(Math.max(0, trainingGoal - 1))}
                  className="w-8 h-8 rounded-full bg-gray-200 hover:bg-gray-300 flex items-center justify-center"
                  disabled={trainingGoal <= 0}
                >
                  −
                </button>
                <span className="text-xl font-bold w-8 text-center">
                  {trainingGoal}
                </span>
                <button
                  onClick={() => setTrainingGoal(Math.min(10, trainingGoal + 1))}
                  className="w-8 h-8 rounded-full bg-green-500 hover:bg-green-600 text-white flex items-center justify-center"
                >
                  +
                </button>
              </div>
            </div>
            <p className="text-xs text-gray-500">
              この時間帯に完了するトレーニングセット数の目標
            </p>
          </div>

          {/* Mindfulness Goal */}
          <div className="space-y-2">
            <label className="flex items-center space-x-2 text-sm font-semibold text-gray-700">
              <span>🧘</span>
              <span>マインドフルネス</span>
            </label>
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600">目標回数</span>
              <div className="flex items-center space-x-3">
                <button
                  onClick={() =>
                    setMindfulnessGoal(Math.max(0, mindfulnessGoal - 1))
                  }
                  className="w-8 h-8 rounded-full bg-gray-200 hover:bg-gray-300 flex items-center justify-center"
                  disabled={mindfulnessGoal <= 0}
                >
                  −
                </button>
                <span className="text-xl font-bold w-8 text-center">
                  {mindfulnessGoal}
                </span>
                <button
                  onClick={() =>
                    setMindfulnessGoal(Math.min(10, mindfulnessGoal + 1))
                  }
                  className="w-8 h-8 rounded-full bg-purple-500 hover:bg-purple-600 text-white flex items-center justify-center"
                >
                  +
                </button>
              </div>
            </div>
            <p className="text-xs text-gray-500">
              この時間帯に実施するマインドフルネスの目標回数
            </p>
          </div>

          {/* Log Goals */}
          <div className="space-y-2">
            <label className="flex items-center space-x-2 text-sm font-semibold text-gray-700 mb-3">
              <span>📝</span>
              <span>ログ記録</span>
            </label>
            <div className="space-y-2">
              <label className="flex items-center space-x-3 p-3 bg-gray-50 rounded-lg cursor-pointer hover:bg-gray-100">
                <input
                  type="checkbox"
                  checked={mealRequired}
                  onChange={e => setMealRequired(e.target.checked)}
                  className="w-5 h-5 text-green-600 rounded"
                />
                <span className="text-xl">🍽️</span>
                <span className="text-sm font-medium text-gray-700">
                  食事記録
                </span>
              </label>
              <label className="flex items-center space-x-3 p-3 bg-gray-50 rounded-lg cursor-pointer hover:bg-gray-100">
                <input
                  type="checkbox"
                  checked={drinkRequired}
                  onChange={e => setDrinkRequired(e.target.checked)}
                  className="w-5 h-5 text-blue-600 rounded"
                />
                <span className="text-xl">💧</span>
                <span className="text-sm font-medium text-gray-700">
                  飲み物記録
                </span>
              </label>
              <label className="flex items-center space-x-3 p-3 bg-gray-50 rounded-lg cursor-pointer hover:bg-gray-100">
                <input
                  type="checkbox"
                  checked={mindInputRequired}
                  onChange={e => setMindInputRequired(e.target.checked)}
                  className="w-5 h-5 text-purple-600 rounded"
                />
                <span className="text-xl">💭</span>
                <span className="text-sm font-medium text-gray-700">
                  マインド入力
                </span>
              </label>
            </div>
            <p className="text-xs text-gray-500 mt-2">
              この時間帯に記録する必要がある項目をオンにしてください
            </p>
          </div>

          {/* Reminder */}
          <div className="space-y-2">
            <label className="flex items-center space-x-3 p-3 bg-gray-50 rounded-lg cursor-pointer hover:bg-gray-100">
              <input
                type="checkbox"
                checked={reminderEnabled}
                onChange={e => setReminderEnabled(e.target.checked)}
                className="w-5 h-5 text-green-600 rounded"
              />
              <span className="text-xl">🔔</span>
              <span className="text-sm font-medium text-gray-700">
                リマインダーを有効化
              </span>
            </label>
            {reminderEnabled && (
              <div className="ml-8 mt-2">
                <input
                  type="time"
                  value={reminderTime}
                  onChange={e => setReminderTime(e.target.value)}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-green-500 focus:border-transparent"
                />
              </div>
            )}
            <p className="text-xs text-gray-500">
              この時間帯に目標達成を促す通知を受け取ります
            </p>
          </div>
        </div>

        {/* Footer */}
        <div className="sticky bottom-0 bg-white border-t border-gray-200 p-6">
          <button
            onClick={handleSave}
            disabled={saving}
            className="w-full py-3 px-4 bg-green-500 hover:bg-green-600 disabled:bg-gray-300 text-white font-bold rounded-lg transition-colors flex items-center justify-center space-x-2"
          >
            {saving ? (
              <>
                <div className="animate-spin rounded-full h-5 w-5 border-b-2 border-white"></div>
                <span>保存中...</span>
              </>
            ) : (
              <>
                <span>✓</span>
                <span>保存する</span>
              </>
            )}
          </button>
        </div>
      </div>
    </div>
  );
};

export default TimeSlotEditModal;
