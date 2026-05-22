import React, { useEffect, useState } from 'react';
import { useAppStore } from '../../store/appStore';
import {
  CustomActivity,
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
  const user = useAppStore((state) => state.user);
  const info = TIME_SLOT_INFO[timeSlot];

  const [trainingGoal, setTrainingGoal] = useState(1);
  const [mindfulnessGoal, setMindfulnessGoal] = useState(1);
  const [stretchMinutesGoal, setStretchMinutesGoal] = useState(0);
  const [mealRequired, setMealRequired] = useState(true);
  const [drinkRequired, setDrinkRequired] = useState(true);
  const [mealKcalGoal, setMealKcalGoal] = useState(500);
  const [drinkMlGoal, setDrinkMlGoal] = useState(500);
  const [mindInputRequired, setMindInputRequired] = useState(false);
  const [customActivities, setCustomActivities] = useState<CustomActivity[]>([]);
  const [newActivityTitle, setNewActivityTitle] = useState('');
  const [newActivityEmoji, setNewActivityEmoji] = useState('✨');
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
        setStretchMinutesGoal(goal.stretchMinutesGoal || 0);
        setMealRequired(goal.logGoal.mealRequired);
        setDrinkRequired(goal.logGoal.drinkRequired);
        setMealKcalGoal(goal.logGoal.mealKcalGoal || 0);
        setDrinkMlGoal(goal.logGoal.drinkMlGoal || 0);
        setMindInputRequired(goal.logGoal.mindInputRequired);
        setCustomActivities(goal.customActivities || []);
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
          stretchMinutesGoal,
          logGoal: {
            mealRequired,
            drinkRequired,
            mealKcalGoal: mealRequired ? mealKcalGoal : 0,
            drinkMlGoal: drinkRequired ? drinkMlGoal : 0,
            mindInputRequired
          },
          customActivities,
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

  const addCustomActivity = () => {
    const title = newActivityTitle.trim();
    if (!title) return;
    setCustomActivities(current => [
      ...current,
      {
        id: `web-${Date.now()}`,
        title,
        emoji: newActivityEmoji.trim() || '✨',
        targetCount: 1
      }
    ]);
    setNewActivityTitle('');
    setNewActivityEmoji('✨');
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

          {/* Stretch Goal */}
          <div className="space-y-2">
            <label className="flex items-center space-x-2 text-sm font-semibold text-gray-700">
              <span>🤸</span>
              <span>ストレッチ / Reflect</span>
            </label>
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600">目標分数</span>
              <div className="flex items-center space-x-3">
                <button
                  onClick={() => setStretchMinutesGoal(Math.max(0, stretchMinutesGoal - 1))}
                  className="w-8 h-8 rounded-full bg-gray-200 hover:bg-gray-300 flex items-center justify-center"
                  disabled={stretchMinutesGoal <= 0}
                >
                  −
                </button>
                <span className="text-xl font-bold w-12 text-center">
                  {stretchMinutesGoal}分
                </span>
                <button
                  onClick={() => setStretchMinutesGoal(Math.min(60, stretchMinutesGoal + 1))}
                  className="w-8 h-8 rounded-full bg-blue-500 hover:bg-blue-600 text-white flex items-center justify-center"
                >
                  +
                </button>
              </div>
            </div>
            <p className="text-xs text-gray-500">
              Webでは手入力のストレッチ分数として記録します。
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
              {mealRequired && (
                <div className="ml-8 flex items-center gap-2">
                  <span className="text-sm text-gray-600">目標</span>
                  <input
                    type="number"
                    min={0}
                    value={mealKcalGoal}
                    onChange={e => setMealKcalGoal(Math.max(0, Number(e.target.value)))}
                    className="w-28 px-3 py-2 border border-gray-300 rounded-lg"
                  />
                  <span className="text-sm font-bold text-gray-600">kcal</span>
                </div>
              )}
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
              {drinkRequired && (
                <div className="ml-8 flex items-center gap-2">
                  <span className="text-sm text-gray-600">目標</span>
                  <input
                    type="number"
                    min={0}
                    step={50}
                    value={drinkMlGoal}
                    onChange={e => setDrinkMlGoal(Math.max(0, Number(e.target.value)))}
                    className="w-28 px-3 py-2 border border-gray-300 rounded-lg"
                  />
                  <span className="text-sm font-bold text-gray-600">ml</span>
                </div>
              )}
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

          {/* Custom Activities */}
          <div className="space-y-3">
            <label className="flex items-center space-x-2 text-sm font-semibold text-gray-700">
              <span>✨</span>
              <span>カスタムアクティビティ</span>
            </label>
            <div className="space-y-2">
              {customActivities.map(activity => (
                <div key={activity.id} className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                  <span className="text-sm font-bold text-gray-700">
                    {activity.emoji} {activity.title}
                  </span>
                  <button
                    onClick={() => setCustomActivities(current => current.filter(item => item.id !== activity.id))}
                    className="text-xs font-bold text-red-500"
                  >
                    削除
                  </button>
                </div>
              ))}
            </div>
            <div className="grid grid-cols-[64px_1fr_auto] gap-2">
              <input
                value={newActivityEmoji}
                onChange={e => setNewActivityEmoji(e.target.value)}
                className="px-3 py-2 border border-gray-300 rounded-lg text-center"
                maxLength={3}
              />
              <input
                value={newActivityTitle}
                onChange={e => setNewActivityTitle(e.target.value)}
                placeholder="読書、Duolingo、勉強など"
                className="px-3 py-2 border border-gray-300 rounded-lg"
              />
              <button
                onClick={addCustomActivity}
                className="px-4 py-2 bg-green-500 text-white font-bold rounded-lg"
              >
                追加
              </button>
            </div>
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
